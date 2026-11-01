package config

import (
	"errors"
	"os"
	"path/filepath"
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
	assert.Equal(t, "", readMango(t, home, "dms/input.conf"))
	binds := readMango(t, home, "dms/binds.conf")
	assert.Contains(t, binds, "bind=SUPER,Return,spawn,foot\nkey_mode=resize\nbind=NONE,h,resizewin,-10,0")
	assert.NotContains(t, binds, "{{TERMINAL_COMMAND}}")
	assert.Contains(t, readMango(t, home, "dms/outputs.conf"), "monitor_rule=name:^DP-1$")
	assert.Contains(t, readMango(t, home, "dms/outputs.conf"), "hdr:1")
	assert.Contains(t, readMango(t, home, "dms/windowrules.conf"), "window_rule=app_id:pavucontrol,is_floating:1")
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
