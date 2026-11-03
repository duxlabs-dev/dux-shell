package clipolicy

import (
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/spf13/afero"
)

const (
	PackagedPath = "/usr/share/dms/cli-policy.json"
	AdminPath    = "/etc/dms/cli-policy.json"
)

type File struct {
	PolicyVersion         int       `json:"policy_version"`
	ImmutableSystem       *bool     `json:"immutable_system"`
	BlockedCommands       *[]string `json:"blocked_commands"`
	Message               *string   `json:"message"`
	DisableRegistries     *bool     `json:"disable_registries"`
	DisableLockIPCUnlock  *bool     `json:"disable_lock_ipc_unlock"`
	DisableLogindUnlock   *bool     `json:"disable_logind_unlock"`
	DisableCustomLockPAM  *bool     `json:"disable_custom_lock_pam"`
	DisableUserPlugins    *bool     `json:"disable_user_plugins"`
	DisableSettingsIPCSet *bool     `json:"disable_settings_ipc_set"`

	LockSettings map[string]json.RawMessage `json:"lock_settings"`
}

// shellSwitches reach the shell as DMS_POLICY_<KEY> in its launch environment.
var shellSwitches = []struct {
	key   string
	value func(*File) *bool
}{
	{"disable_lock_ipc_unlock", func(p *File) *bool { return p.DisableLockIPCUnlock }},
	{"disable_logind_unlock", func(p *File) *bool { return p.DisableLogindUnlock }},
	{"disable_custom_lock_pam", func(p *File) *bool { return p.DisableCustomLockPAM }},
	{"disable_user_plugins", func(p *File) *bool { return p.DisableUserPlugins }},
	{"disable_settings_ipc_set", func(p *File) *bool { return p.DisableSettingsIPCSet }},
}

// lockSettingKeys are the shell settings lock_settings may manage.
var lockSettingKeys = []string{
	"customPowerActionLock",
	"lockBeforeSuspend",
	"loginctlLockIntegration",
	"lockAtStartup",
	"acLockTimeout",
	"batteryLockTimeout",
	"fadeToLockEnabled",
	"fadeToLockGracePeriod",
	"enableFprint",
	"maxFprintTries",
	"enableU2f",
	"u2fMode",
}

// LoadFile returns nil without an error when the file does not exist.
func LoadFile(fs afero.Fs, path string) (*File, error) {
	data, err := afero.ReadFile(fs, path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to read %s: %w", path, err)
	}

	var policy File
	if err := json.Unmarshal(data, &policy); err != nil {
		return nil, fmt.Errorf("failed to parse %s: %w", path, err)
	}

	return &policy, nil
}

// load returns the policy files that exist, PackagedPath first.
func load(fs afero.Fs) ([]*File, error) {
	var policies []*File
	for _, path := range []string{PackagedPath, AdminPath} {
		policy, err := LoadFile(fs, path)
		if err != nil {
			return nil, err
		}
		if policy != nil {
			policies = append(policies, policy)
		}
	}
	return policies, nil
}

// flag reports a boolean key, false unless set. An explicit value in AdminPath
// overrides PackagedPath.
func flag(policies []*File, value func(*File) *bool) bool {
	set := false
	for _, policy := range policies {
		if v := value(policy); v != nil {
			set = *v
		}
	}
	return set
}

// RegistriesDisabled reports whether the policy turns off the plugin and theme
// registries. An explicit value in AdminPath overrides PackagedPath.
func RegistriesDisabled(fs afero.Fs) (bool, error) {
	policies, err := load(fs)
	if err != nil {
		return false, err
	}
	return flag(policies, func(p *File) *bool { return p.DisableRegistries }), nil
}

// LogindUnlockDisabled reports whether a logind Unlock must leave a lock in
// place. An explicit value in AdminPath overrides PackagedPath.
func LogindUnlockDisabled(fs afero.Fs) (bool, error) {
	policies, err := load(fs)
	if err != nil {
		return false, err
	}
	return flag(policies, func(p *File) *bool { return p.DisableLogindUnlock }), nil
}

// lockSettings merges lock_settings per key, AdminPath over PackagedPath,
// without null values and keys outside lockSettingKeys.
func lockSettings(policies []*File) map[string]json.RawMessage {
	settings := make(map[string]json.RawMessage)
	for _, policy := range policies {
		for key, value := range policy.LockSettings {
			if !slices.Contains(lockSettingKeys, key) {
				log.Warnf("CLI policy: ignoring lock_settings key %q, which is not a managed lock setting", key)
				continue
			}
			if string(value) == "null" {
				continue
			}
			settings[key] = value
		}
	}
	return settings
}

// LockSettings returns the managed lock settings as raw JSON by key. A policy
// file that fails to load manages none, and its error is returned.
func LockSettings(fs afero.Fs) (map[string]json.RawMessage, error) {
	policies, err := load(fs)
	return lockSettings(policies), err
}

// LockSettingBool returns a managed boolean lock setting, or nil when it is
// not managed or not a boolean, which the shell ignores too.
func LockSettingBool(settings map[string]json.RawMessage, key string) *bool {
	var value *bool
	if err := json.Unmarshal(settings[key], &value); err != nil {
		return nil
	}
	return value
}

// ShellEnv returns every shell switch as DMS_POLICY_<KEY>=1 or 0 and the
// managed lock settings as DMS_POLICY_LOCK_SETTINGS=<JSON object>, so a value
// inherited by the shell never counts. A policy file that fails to load turns
// every switch on and manages no lock setting, and its error is returned with
// them.
func ShellEnv(fs afero.Fs) ([]string, error) {
	policies, err := load(fs)
	env := make([]string, 0, len(shellSwitches)+1)
	for _, s := range shellSwitches {
		value := "0"
		if err != nil || flag(policies, s.value) {
			value = "1"
		}
		env = append(env, "DMS_POLICY_"+strings.ToUpper(s.key)+"="+value)
	}
	// The values come from json.Unmarshal, so they marshal.
	settings, _ := json.Marshal(lockSettings(policies))
	env = append(env, "DMS_POLICY_LOCK_SETTINGS="+string(settings))
	return env, err
}
