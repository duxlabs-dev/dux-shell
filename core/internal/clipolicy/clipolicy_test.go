package clipolicy

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/spf13/afero"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRegistriesDisabled(t *testing.T) {
	tests := []struct {
		name     string
		packaged string
		admin    string
		want     bool
		wantErr  string
	}{
		{name: "no policy files"},
		{name: "packaged policy", packaged: `{"disable_registries": true}`, want: true},
		{name: "admin policy overrides packaged", packaged: `{"disable_registries": true}`, admin: `{"disable_registries": false}`},
		{name: "admin policy", admin: `{"disable_registries": true}`, want: true},
		{name: "admin policy without the key keeps packaged", packaged: `{"disable_registries": true}`, admin: `{"immutable_system": true}`, want: true},
		{name: "malformed packaged policy", packaged: "{not json", admin: `{"disable_registries": false}`, wantErr: "failed to parse " + PackagedPath},
		{name: "malformed admin policy", packaged: `{"disable_registries": false}`, admin: "{not json", wantErr: "failed to parse " + AdminPath},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fs := afero.NewMemMapFs()
			if tt.packaged != "" {
				require.NoError(t, afero.WriteFile(fs, PackagedPath, []byte(tt.packaged), 0o644))
			}
			if tt.admin != "" {
				require.NoError(t, afero.WriteFile(fs, AdminPath, []byte(tt.admin), 0o644))
			}

			disabled, err := RegistriesDisabled(fs)
			if tt.wantErr != "" {
				require.ErrorContains(t, err, tt.wantErr)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.want, disabled)
		})
	}
}

func TestLogindUnlockDisabled(t *testing.T) {
	tests := []struct {
		name     string
		packaged string
		admin    string
		want     bool
		wantErr  string
	}{
		{name: "no policy files"},
		{name: "admin policy", admin: `{"disable_logind_unlock": true}`, want: true},
		{name: "admin policy overrides packaged", packaged: `{"disable_logind_unlock": true}`, admin: `{"disable_logind_unlock": false}`},
		{name: "another key", admin: `{"disable_lock_ipc_unlock": true}`},
		{name: "malformed admin policy", admin: "{not json", wantErr: "failed to parse " + AdminPath},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fs := afero.NewMemMapFs()
			if tt.packaged != "" {
				require.NoError(t, afero.WriteFile(fs, PackagedPath, []byte(tt.packaged), 0o644))
			}
			if tt.admin != "" {
				require.NoError(t, afero.WriteFile(fs, AdminPath, []byte(tt.admin), 0o644))
			}

			disabled, err := LogindUnlockDisabled(fs)
			if tt.wantErr != "" {
				require.ErrorContains(t, err, tt.wantErr)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.want, disabled)
		})
	}
}

var shellSwitchEnv = map[string]string{
	"disable_lock_ipc_unlock":  "DMS_POLICY_DISABLE_LOCK_IPC_UNLOCK",
	"disable_logind_unlock":    "DMS_POLICY_DISABLE_LOGIND_UNLOCK",
	"disable_custom_lock_pam":  "DMS_POLICY_DISABLE_CUSTOM_LOCK_PAM",
	"disable_user_plugins":     "DMS_POLICY_DISABLE_USER_PLUGINS",
	"disable_settings_ipc_set": "DMS_POLICY_DISABLE_SETTINGS_IPC_SET",
}

func TestShellEnv(t *testing.T) {
	tests := []struct {
		name     string
		packaged string
		admin    string
		on       bool
	}{
		{name: "no policy files"},
		{name: "packaged policy", packaged: `{"KEY": true}`, on: true},
		{name: "admin policy", admin: `{"KEY": true}`, on: true},
		{name: "admin policy overrides packaged", packaged: `{"KEY": true}`, admin: `{"KEY": false}`},
		{name: "admin policy without the key keeps packaged", packaged: `{"KEY": true}`, admin: `{"immutable_system": true}`, on: true},
	}

	for key, name := range shellSwitchEnv {
		for _, tt := range tests {
			t.Run(key+"/"+tt.name, func(t *testing.T) {
				fs := afero.NewMemMapFs()
				if tt.packaged != "" {
					require.NoError(t, afero.WriteFile(fs, PackagedPath, []byte(strings.ReplaceAll(tt.packaged, "KEY", key)), 0o644))
				}
				if tt.admin != "" {
					require.NoError(t, afero.WriteFile(fs, AdminPath, []byte(strings.ReplaceAll(tt.admin, "KEY", key)), 0o644))
				}

				var want []string
				for _, other := range shellSwitchEnv {
					if other == name && tt.on {
						want = append(want, other+"=1")
					} else {
						want = append(want, other+"=0")
					}
				}
				want = append(want, "DMS_POLICY_LOCK_SETTINGS={}")

				env, err := ShellEnv(fs)
				require.NoError(t, err)
				assert.ElementsMatch(t, want, env)
			})
		}
	}
}

func TestShellEnvMalformedPolicyTurnsEverySwitchOnAndIgnoresLockSettings(t *testing.T) {
	fs := afero.NewMemMapFs()
	require.NoError(t, afero.WriteFile(fs, PackagedPath, []byte(`{"lock_settings": {"lockBeforeSuspend": true}}`), 0o644))
	require.NoError(t, afero.WriteFile(fs, AdminPath, []byte("{not json"), 0o644))

	want := []string{"DMS_POLICY_LOCK_SETTINGS={}"}
	for _, name := range shellSwitchEnv {
		want = append(want, name+"=1")
	}

	env, err := ShellEnv(fs)
	require.ErrorContains(t, err, "failed to parse "+AdminPath)
	assert.ElementsMatch(t, want, env)
}

func TestLockSettings(t *testing.T) {
	tests := []struct {
		name     string
		packaged string
		admin    string
		want     string
		wantErr  string
	}{
		{name: "no policy files", want: `{}`},
		{name: "no lock settings", admin: `{"disable_registries": true}`, want: `{}`},
		{name: "packaged policy", packaged: `{"lock_settings": {"lockBeforeSuspend": true, "customPowerActionLock": ""}}`, want: `{"lockBeforeSuspend": true, "customPowerActionLock": ""}`},
		{name: "admin policy overrides packaged per key", packaged: `{"lock_settings": {"lockBeforeSuspend": true, "acLockTimeout": 300}}`, admin: `{"lock_settings": {"lockBeforeSuspend": false}}`, want: `{"lockBeforeSuspend": false, "acLockTimeout": 300}`},
		{name: "admin policy without lock settings keeps packaged", packaged: `{"lock_settings": {"enableFprint": false}}`, admin: `{"disable_registries": true}`, want: `{"enableFprint": false}`},
		{name: "null leaves a key unset", packaged: `{"lock_settings": {"u2fMode": "and"}}`, admin: `{"lock_settings": {"u2fMode": null, "lockAtStartup": null}}`, want: `{"u2fMode": "and"}`},
		{
			name:  "only lock settings are managed",
			admin: `{"lock_settings": {"customPowerActionLock": "", "lockBeforeSuspend": true, "loginctlLockIntegration": true, "lockAtStartup": true, "acLockTimeout": 300, "batteryLockTimeout": 120, "fadeToLockEnabled": true, "fadeToLockGracePeriod": 5, "enableFprint": true, "maxFprintTries": 3, "enableU2f": true, "u2fMode": "and", "lockScreenShowPowerActions": false, "lockPamPath": "/tmp/pam", "unknownSetting": 1}}`,
			want:  `{"customPowerActionLock": "", "lockBeforeSuspend": true, "loginctlLockIntegration": true, "lockAtStartup": true, "acLockTimeout": 300, "batteryLockTimeout": 120, "fadeToLockEnabled": true, "fadeToLockGracePeriod": 5, "enableFprint": true, "maxFprintTries": 3, "enableU2f": true, "u2fMode": "and"}`,
		},
		{name: "values are passed as written", admin: `{"lock_settings": {"lockBeforeSuspend": "yes", "acLockTimeout": [1]}}`, want: `{"lockBeforeSuspend": "yes", "acLockTimeout": [1]}`},
		{name: "malformed admin policy manages nothing", packaged: `{"lock_settings": {"lockBeforeSuspend": true}}`, admin: "{not json", want: `{}`, wantErr: "failed to parse " + AdminPath},
		{name: "lock settings not an object", packaged: `{"lock_settings": {"lockBeforeSuspend": true}}`, admin: `{"lock_settings": ["lockBeforeSuspend"]}`, want: `{}`, wantErr: "failed to parse " + AdminPath},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fs := afero.NewMemMapFs()
			if tt.packaged != "" {
				require.NoError(t, afero.WriteFile(fs, PackagedPath, []byte(tt.packaged), 0o644))
			}
			if tt.admin != "" {
				require.NoError(t, afero.WriteFile(fs, AdminPath, []byte(tt.admin), 0o644))
			}

			settings, err := LockSettings(fs)
			if tt.wantErr != "" {
				require.ErrorContains(t, err, tt.wantErr)
			} else {
				require.NoError(t, err)
			}
			got, err := json.Marshal(settings)
			require.NoError(t, err)
			assert.JSONEq(t, tt.want, string(got))
		})
	}
}

func TestShellEnvLockSettings(t *testing.T) {
	fs := afero.NewMemMapFs()
	require.NoError(t, afero.WriteFile(fs, PackagedPath, []byte(`{"lock_settings": {"lockBeforeSuspend": false, "acLockTimeout": 300}}`), 0o644))
	require.NoError(t, afero.WriteFile(fs, AdminPath, []byte(`{"lock_settings": {"lockBeforeSuspend": true, "customPowerActionLock": "", "lockScreenShowWeather": false}}`), 0o644))

	env, err := ShellEnv(fs)
	require.NoError(t, err)
	assert.Contains(t, env, `DMS_POLICY_LOCK_SETTINGS={"acLockTimeout":300,"customPowerActionLock":"","lockBeforeSuspend":true}`)
}

func TestLockSettingBool(t *testing.T) {
	on, off := true, false
	tests := []struct {
		name     string
		settings string
		want     *bool
	}{
		{name: "not managed", settings: `{"lockAtStartup": true}`},
		{name: "managed on", settings: `{"lockBeforeSuspend": true}`, want: &on},
		{name: "managed off", settings: `{"lockBeforeSuspend": false}`, want: &off},
		{name: "null", settings: `{"lockBeforeSuspend": null}`},
		{name: "not a boolean", settings: `{"lockBeforeSuspend": "true"}`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var settings map[string]json.RawMessage
			require.NoError(t, json.Unmarshal([]byte(tt.settings), &settings))
			assert.Equal(t, tt.want, LockSettingBool(settings, "lockBeforeSuspend"))
		})
	}
}
