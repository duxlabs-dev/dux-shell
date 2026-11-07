package config

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDisableSessionRemovesEveryWantsLink(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	for _, unit := range []string{HyprlandSessionTarget, mangoconf.SessionTarget} {
		link := WantsLink(unit)
		require.NoError(t, os.MkdirAll(filepath.Dir(link), 0o755))
		require.NoError(t, os.Symlink("/dev/null", link))
	}
	var reloads int
	prev := systemctlUser
	systemctlUser = func(args ...string) error {
		if args[0] == "daemon-reload" {
			reloads++
		}
		return nil
	}
	t.Cleanup(func() { systemctlUser = prev })

	assert.Equal(t, []string{HyprlandSessionTarget, mangoconf.SessionTarget}, SessionWanted())
	removed, err := DisableSession()
	require.NoError(t, err)
	assert.Equal(t, []string{HyprlandSessionTarget, mangoconf.SessionTarget}, removed)
	assert.Empty(t, SessionWanted())
	assert.Equal(t, 1, reloads)

	removed, err = DisableSession()
	require.NoError(t, err)
	assert.Nil(t, removed)
	assert.Equal(t, 1, reloads)
}

func TestEnableSessionMangoWithoutTarget(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	calls := stubMango(t, false, nil)
	unit, err := EnableSession(deps.WindowManagerMango)
	require.Error(t, err)
	assert.Empty(t, unit)
	assert.Equal(t, 0, *calls)
}
