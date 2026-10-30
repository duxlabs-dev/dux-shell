package utils

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setupMigrationHome(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, "config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(home, "state"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(home, "cache"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(home, "data"))
	return home
}

func writeMigrationFile(t *testing.T, path, content string) {
	t.Helper()
	require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o755))
	require.NoError(t, os.WriteFile(path, []byte(content), 0o644))
}

func readMigrationFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	require.NoError(t, err)
	return string(data)
}

func TestMigrateLegacyDirs(t *testing.T) {
	tests := []struct {
		name     string
		conflict bool
		setup    func(t *testing.T, home string)
		verify   func(t *testing.T, home string)
	}{
		{
			name:  "fresh install creates nothing",
			setup: func(t *testing.T, home string) {},
			verify: func(t *testing.T, home string) {
				_, err := os.Lstat(filepath.Join(home, "config", "DankMaterialShell"))
				assert.True(t, os.IsNotExist(err))
				_, err = os.Lstat(filepath.Join(home, "config", "dms"))
				assert.True(t, os.IsNotExist(err))
			},
		},
		{
			name: "legacy config moves and leaves a symlink",
			setup: func(t *testing.T, home string) {
				writeMigrationFile(t, filepath.Join(home, "config", "DankMaterialShell", "settings.json"), "settings")
			},
			verify: func(t *testing.T, home string) {
				assert.Equal(t, "settings", readMigrationFile(t, filepath.Join(home, "config", "dms", "settings.json")))
				target, err := os.Readlink(filepath.Join(home, "config", "DankMaterialShell"))
				require.NoError(t, err)
				assert.Equal(t, "dms", target)
				assert.Equal(t, "settings", readMigrationFile(t, filepath.Join(home, "config", "DankMaterialShell", "settings.json")))
			},
		},
		{
			name: "legacy cache merges into an existing dms cache",
			setup: func(t *testing.T, home string) {
				writeMigrationFile(t, filepath.Join(home, "cache", "DankMaterialShell", "clipboard", "db"), "history")
				writeMigrationFile(t, filepath.Join(home, "cache", "DankMaterialShell", "dms-colors.json"), "colors")
				writeMigrationFile(t, filepath.Join(home, "cache", "dms", "clipboard", "tmp-1"), "tmp")
				writeMigrationFile(t, filepath.Join(home, "cache", "DankMaterialShell", "lyrics", ".lastprune"), "")
				writeMigrationFile(t, filepath.Join(home, "cache", "dms", "lyrics", ".lastprune"), "")
			},
			verify: func(t *testing.T, home string) {
				assert.Equal(t, "history", readMigrationFile(t, filepath.Join(home, "cache", "dms", "clipboard", "db")))
				assert.Equal(t, "tmp", readMigrationFile(t, filepath.Join(home, "cache", "dms", "clipboard", "tmp-1")))
				assert.Equal(t, "colors", readMigrationFile(t, filepath.Join(home, "cache", "dms", "dms-colors.json")))
				target, err := os.Readlink(filepath.Join(home, "cache", "DankMaterialShell"))
				require.NoError(t, err)
				assert.Equal(t, "dms", target)
			},
		},
		{
			name:     "conflicting file keeps the legacy dir in place",
			conflict: true,
			setup: func(t *testing.T, home string) {
				writeMigrationFile(t, filepath.Join(home, "state", "DankMaterialShell", "session.json"), "old")
				writeMigrationFile(t, filepath.Join(home, "state", "dms", "session.json"), "new")
			},
			verify: func(t *testing.T, home string) {
				assert.Equal(t, "new", readMigrationFile(t, filepath.Join(home, "state", "dms", "session.json")))
				assert.Equal(t, "old", readMigrationFile(t, filepath.Join(home, "state", "DankMaterialShell", "session.json")))
			},
		},
		{
			name: "symlinked legacy dir gets a dms link to it",
			setup: func(t *testing.T, home string) {
				dotfiles := filepath.Join(home, "dotfiles", "dms")
				writeMigrationFile(t, filepath.Join(dotfiles, "settings.json"), "dotfiles")
				require.NoError(t, os.MkdirAll(filepath.Join(home, "config"), 0o755))
				require.NoError(t, os.Symlink(dotfiles, filepath.Join(home, "config", "DankMaterialShell")))
			},
			verify: func(t *testing.T, home string) {
				assert.Equal(t, "dotfiles", readMigrationFile(t, filepath.Join(home, "config", "dms", "settings.json")))
			},
		},
		{
			name: "dangling legacy link to a deleted dms dir is not linked back",
			setup: func(t *testing.T, home string) {
				require.NoError(t, os.MkdirAll(filepath.Join(home, "config"), 0o755))
				require.NoError(t, os.Symlink("dms", filepath.Join(home, "config", "DankMaterialShell")))
			},
			verify: func(t *testing.T, home string) {
				_, err := os.Lstat(filepath.Join(home, "config", "dms"))
				assert.True(t, os.IsNotExist(err))
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			home := setupMigrationHome(t)
			tt.setup(t, home)

			wantErrs := 0
			if tt.conflict {
				wantErrs = 1
			}
			for range 2 {
				assert.Len(t, MigrateLegacyDirs(), wantErrs)
				tt.verify(t, home)
			}
		})
	}
}
