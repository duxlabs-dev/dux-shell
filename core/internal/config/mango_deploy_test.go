package config

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func stubMango(t *testing.T, target bool, addWants error) *int {
	t.Helper()
	prevTarget := mangoSessionTargetInstalled
	mangoSessionTargetInstalled = func() bool { return target }
	t.Cleanup(func() { mangoSessionTargetInstalled = prevTarget })
	return stubAddWants(t, addWants)
}

func readMango(t *testing.T, home, rel string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(home, ".config", "mango", rel))
	require.NoError(t, err)
	return string(data)
}

const oldMangoConfig = `exec-once=waybar
bind=SUPER,Return,spawn,foot
key_mode=resize
bind=NONE,h,resizewin,-10,0
monitor_rule=name:^DP-1$,width:2560,height:1440,refresh:144,x:0,y:0,scale:1,rr:0,vrr:1,hdr:1
window_rule=app_id:pavucontrol,is_floating:1
mousebindl=SUPER,btn_left,moveresize,curmove
`

func TestMangoDeployMovesUserRulesAndKeepsBindsByDefault(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	stubMango(t, false, nil)
	require.NoError(t, os.MkdirAll(filepath.Join(home, ".config", "mango"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(home, ".config", "mango", "config.conf"), []byte(oldMangoConfig), 0o644))

	result, err := NewConfigDeployer(nil).DeployCompositor(deps.WindowManagerMango, "kitty", true)
	require.NoError(t, err)
	assert.NotEmpty(t, result.BackupPath)

	assert.Contains(t, readMango(t, home, "config.conf"), "exec_once=dms run")
	assert.Contains(t, readMango(t, home, "config.conf"), "source=./dms/input.conf")
	assert.Contains(t, readMango(t, home, "config.conf"), "source=./dms/animations.conf")
	assert.Equal(t, MangoAnimationsConfig, readMango(t, home, "dms/animations.conf"))
	assert.Equal(t, "", readMango(t, home, "dms/input.conf"))
	binds := readMango(t, home, "dms/binds.conf")
	assert.Contains(t, binds, "bind=SUPER,Return,spawn,foot\nkey_mode=resize\nbind=NONE,h,resizewin,-10,0")
	assert.Contains(t, binds, "mousebindl=SUPER,btn_left,moveresize,curmove")
	assert.NotContains(t, binds, "{{TERMINAL_COMMAND}}")
	assert.Contains(t, readMango(t, home, "dms/outputs.conf"), "monitor_rule=name:^DP-1$")
	assert.Contains(t, readMango(t, home, "dms/outputs.conf"), "hdr:1")
	assert.Contains(t, readMango(t, home, "dms/windowrules.conf"), "window_rule=app_id:pavucontrol,is_floating:1")
}

func TestMangoDeployReplacesConfigToml(t *testing.T) {
	for _, target := range []bool{false, true} {
		home := t.TempDir()
		t.Setenv("HOME", home)
		stubMango(t, target, nil)
		dir := filepath.Join(home, ".config", "mango")
		require.NoError(t, os.MkdirAll(dir, 0o755))
		old := "[bind.default]\n\"SUPER+Return\" = \"spawn,foot\"\n[[rule.window_rule]]\napp_id = \"pavucontrol\"\nis_floating = 1\n"
		require.NoError(t, os.WriteFile(filepath.Join(dir, "config.toml"), []byte(old), 0o644))

		_, ok := MangoExistingBinds()
		assert.False(t, ok, "replace never carries TOML binds, so there are none to keep")

		result, err := NewConfigDeployer(nil).DeployCompositor(deps.WindowManagerMango, "kitty", true)
		require.NoError(t, err)

		assert.NoFileExists(t, filepath.Join(dir, "config.conf"), "a config.conf would shadow config.toml")
		assert.Equal(t, filepath.Join(dir, "config.toml"), result.Path)
		assert.Equal(t, old, readMango(t, home, filepath.Base(result.BackupPath)))
		assert.Equal(t, strings.ReplaceAll(MangoBindsConfig, "{{TERMINAL_COMMAND}}", "kitty"), readMango(t, home, "dms/binds.conf"))
		assert.Equal(t, "", readMango(t, home, "dms/windowrules.conf"))

		// Mango must read the TOML template as it reads the conf one; only systemd starts DMS when there is a session target.
		var want, got []string
		for line := range strings.SplitSeq(MangoConfig, "\n") {
			if line != "" && !strings.HasPrefix(line, "#") && (!target || line != "exec_once=dms run") {
				want = append(want, line)
			}
		}
		for _, e := range mangoconf.TOMLEntries(readMango(t, home, "config.toml")) {
			got = append(got, e.Key+"="+e.Value)
		}
		assert.Equal(t, want, got, "session target=%v", target)
		assert.Equal(t, !target, slices.Contains(got, "exec_once=dms run"), "session target=%v", target)
	}
}

func TestMangoDeployLeavesUnreadableConfigAlone(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads any file")
	}
	home := t.TempDir()
	t.Setenv("HOME", home)
	stubMango(t, false, nil)
	dir := filepath.Join(home, ".config", "mango")
	require.NoError(t, os.MkdirAll(dir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, "config.conf"), []byte("bind=SUPER,q,killclient\n"), 0o000))

	_, err := NewConfigDeployer(nil).DeployCompositor(deps.WindowManagerMango, "kitty", true)
	require.Error(t, err)

	entries, _ := os.ReadDir(dir)
	assert.Len(t, entries, 1, "nothing may be written next to a config that cannot be backed up")
}

func TestMangoDeployBindsChoiceAlwaysBacksUp(t *testing.T) {
	for _, replace := range []bool{false, true} {
		home := t.TempDir()
		t.Setenv("HOME", home)
		stubMango(t, false, nil)
		dms := filepath.Join(home, ".config", "mango", "dms")
		require.NoError(t, os.MkdirAll(dms, 0o755))
		require.NoError(t, os.WriteFile(filepath.Join(dms, "binds.conf"), []byte("bind=SUPER,x,killclient\nkey_mode=resize\n"), 0o644))
		require.NoError(t, os.WriteFile(filepath.Join(dms, "windowrules.conf"), []byte("window_rule=app_id:keep,is_global:1\n"), 0o644))

		cd := NewConfigDeployer(nil)
		cd.SetReplaceBinds(replace)
		_, err := cd.DeployCompositor(deps.WindowManagerMango, "kitty", false)
		require.NoError(t, err)

		backups, _ := filepath.Glob(filepath.Join(dms, "binds.conf.backup.*"))
		assert.Len(t, backups, 1, "replace=%v", replace)
		binds := readMango(t, home, "dms/binds.conf")
		assert.Equal(t, !replace, binds == mangoconf.BindsKeptHeader+"\nbind=SUPER,x,killclient\nkey_mode=resize\n", "replace=%v", replace)
		assert.Equal(t, "window_rule=app_id:keep,is_global:1\n", readMango(t, home, "dms/windowrules.conf"), "kept fragments are left alone")
	}
}

func TestMangoDeploySystemdAutostart(t *testing.T) {
	cases := []struct {
		name      string
		target    bool
		addWants  error
		wantExec  bool
		wantCalls int
	}{
		{"session target", true, nil, false, 1},
		{"no session target", false, nil, true, 0},
		{"add-wants fails", true, errors.New("no user bus"), true, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			home := t.TempDir()
			t.Setenv("HOME", home)
			calls := stubMango(t, tc.target, tc.addWants)
			_, err := NewConfigDeployer(nil).DeployCompositor(deps.WindowManagerMango, "kitty", true)
			require.NoError(t, err)
			main := readMango(t, home, "config.conf")
			assert.Equal(t, tc.wantExec, strings.Contains(main, "exec_once=dms run"))
			assert.NotContains(t, main, "exec-once")
			assert.Equal(t, tc.wantExec, strings.Contains(main, "Starts the shell"))
			assert.Equal(t, tc.wantCalls, *calls)
		})
	}
}
