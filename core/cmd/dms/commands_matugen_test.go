package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/iconfolders"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestIconFoldersPrintsOneLineOrNothing(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HOME", root)
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "data"))
	t.Setenv("XDG_DATA_DIRS", filepath.Join(root, "sys"))
	theme := filepath.Join(root, "sys", "icons", "Adwaita")
	require.NoError(t, os.MkdirAll(filepath.Join(theme, "scalable", "places"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(theme, "index.theme"), []byte("[Icon Theme]\nName=Adwaita\nDirectories=scalable/places\n\n[scalable/places]\nContext=Places\nSize=128\nType=Scalable\n"), 0o644))
	require.NoError(t, os.WriteFile(filepath.Join(theme, "scalable", "places", "folder.svg"), []byte(`<svg xmlns="http://www.w3.org/2000/svg"><path d="m 0 0 h 8 v 8 z" fill="#a4caee"/></svg>`), 0o644))
	stateDir := filepath.Join(root, "state")
	require.NoError(t, os.MkdirAll(stateDir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(stateDir, "dms-colors.json"), []byte(`{"colors":{"dark":{"primary":"#69b2ff","on_primary":"#003055"}}}`), 0o644))
	picked := iconfolders.Options{StateDir: stateDir, IconTheme: "Adwaita", Mode: "dark"}

	out, err := iconFoldersResult(picked, false, false)
	require.NoError(t, err)
	assert.NotContains(t, string(out), "\n")
	var state iconfolders.State
	require.NoError(t, json.Unmarshal(out, &state))
	assert.Equal(t, filepath.Join(root, "data", "icons", state.Applied), state.Dir)
	assert.Equal(t, map[string]string{"folder": "scalable/places/folder.svg"}, state.Icons)

	out, err = iconFoldersResult(iconfolders.Options{StateDir: stateDir}, true, false)
	require.NoError(t, err)
	assert.JSONEq(t, `{"base":"","applied":"","inputs":"","dir":"","icons":{}}`, string(out))
	assert.NoDirExists(t, state.Dir)

	require.NoError(t, os.MkdirAll(state.Dir, 0o755))
	out, err = iconFoldersResult(picked, false, false)
	assert.ErrorIs(t, err, iconfolders.ErrOccupied)
	assert.Nil(t, out, "the shell takes any stdout line for success")
}
