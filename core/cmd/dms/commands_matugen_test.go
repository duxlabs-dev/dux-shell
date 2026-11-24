package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/iconfolders"
	"github.com/spf13/cobra"
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

func TestIconTileFlagsDefaultToTodaysBuild(t *testing.T) {
	for _, cmd := range []*cobra.Command{matugenGenerateCmd, matugenQueueCmd} {
		opts := buildMatugenOptions(cmd)
		assert.Equal(t, "theme", opts.IconTileColor, cmd.Name())
		assert.Equal(t, "score", opts.IconColorSource, cmd.Name())
		assert.Equal(t, "tonal", opts.IconTileStyle, cmd.Name())
		assert.Equal(t, -1, opts.IconTileTone, cmd.Name())
		assert.Equal(t, -1, opts.IconOwnTone, cmd.Name())
		assert.Equal(t, "standard", opts.IconFileStyle, cmd.Name())
		assert.Equal(t, "color", opts.IconAppStyle, cmd.Name())
	}
	flags := matugenIconFoldersCmd.Flags()
	for name, want := range map[string]string{"tile-color": "theme", "color-source": "score", "tile-style": "tonal", "tile-tone": "-1", "own-tone": "-1", "file-style": "standard", "app-style": "color"} {
		flag := flags.Lookup(name)
		require.NotNil(t, flag, name)
		assert.Equal(t, want, flag.DefValue, name)
	}
}

func TestIconTileFlagsReachTheOptions(t *testing.T) {
	cmd := &cobra.Command{Use: "probe"}
	for _, name := range []string{"state-dir", "shell-dir", "config-dir", "kind", "value", "mode", "icon-theme", "matugen-type", "stock-colors", "terminal-palette", "skip-templates", "icon-shape", "source-mode", "seed-color", "spec"} {
		cmd.Flags().String(name, "", "")
	}
	for _, name := range []string{"run-user-templates", "sync-mode-with-portal", "terminals-always-dark", "icon-folders", "icon-gradient"} {
		cmd.Flags().Bool(name, false, "")
	}
	cmd.Flags().Int("terminal-opacity", 0, "")
	cmd.Flags().Float64("contrast", 0, "")
	cmd.Flags().String("icon-tile-color", "theme", "")
	cmd.Flags().String("icon-color-source", "score", "")
	cmd.Flags().String("icon-tile-style", "tonal", "")
	cmd.Flags().Int("icon-tile-tone", -1, "")
	cmd.Flags().Int("icon-own-tone", -1, "")
	cmd.Flags().String("icon-file-style", "standard", "")
	cmd.Flags().String("icon-app-style", "color", "")
	require.NoError(t, cmd.ParseFlags([]string{"--icon-tile-color", "edge", "--icon-color-source", "common", "--icon-tile-style", "content", "--icon-tile-tone", "0", "--icon-own-tone", "55", "--icon-file-style", "color", "--icon-app-style", "monochrome"}))

	opts := buildMatugenOptions(cmd)
	assert.Equal(t, "edge", opts.IconTileColor)
	assert.Equal(t, "common", opts.IconColorSource)
	assert.Equal(t, "content", opts.IconTileStyle)
	assert.Equal(t, 0, opts.IconTileTone)
	assert.Equal(t, 55, opts.IconOwnTone)
	assert.Equal(t, "color", opts.IconFileStyle)
	assert.Equal(t, "monochrome", opts.IconAppStyle)
}

func TestStyleFlagsTakeOnlyKnownStyles(t *testing.T) {
	for _, tc := range []struct {
		cmd             *cobra.Command
		files, appStyle string
	}{{matugenGenerateCmd, "icon-file-style", "icon-app-style"}, {matugenQueueCmd, "icon-file-style", "icon-app-style"}, {matugenIconFoldersCmd, "file-style", "app-style"}} {
		cmd := &cobra.Command{Use: tc.cmd.Name()}
		cmd.Flags().String(tc.files, "standard", "")
		cmd.Flags().String(tc.appStyle, "color", "")
		require.NotNil(t, tc.cmd.PreRunE, tc.cmd.Name())
		for _, value := range []string{"standard", "color", "Color"} {
			require.NoError(t, cmd.Flags().Set(tc.files, value))
			assert.NoError(t, tc.cmd.PreRunE(cmd, nil), tc.cmd.Name()+" "+value)
		}
		for _, value := range []string{"color", "themed", "Monochrome"} {
			require.NoError(t, cmd.Flags().Set(tc.appStyle, value))
			assert.NoError(t, tc.cmd.PreRunE(cmd, nil), tc.cmd.Name()+" "+value)
		}
		for _, value := range []string{"base", "papirus"} {
			require.NoError(t, cmd.Flags().Set(tc.files, value))
			assert.ErrorContains(t, tc.cmd.PreRunE(cmd, nil), "bad file style", tc.cmd.Name()+" "+value)
		}
		require.NoError(t, cmd.Flags().Set(tc.files, "color"))
		require.NoError(t, cmd.Flags().Set(tc.appStyle, "mono"))
		assert.ErrorContains(t, tc.cmd.PreRunE(cmd, nil), "bad app style", tc.cmd.Name())
	}
}
