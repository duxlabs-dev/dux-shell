package matugen

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestIsDMSGTKActive(t *testing.T) {
	const dankImport = "@import url(\"dank-colors.css\");\n"

	tests := []struct {
		name  string
		setup func(t *testing.T, configDir, storeDir string)
		want  bool
	}{
		{
			name: "home-manager symlink to a stylesheet importing dank colors",
			setup: func(t *testing.T, configDir, storeDir string) {
				target := filepath.Join(storeDir, "hm-gtk.css")
				require.NoError(t, os.WriteFile(target, []byte(dankImport+"window { margin: 0; }\n"), 0o644))
				require.NoError(t, os.Symlink(target, filepath.Join(configDir, "gtk-4.0", "gtk.css")))
			},
			want: true,
		},
		{
			name: "gtk-3.0 import only",
			setup: func(t *testing.T, configDir, _ string) {
				require.NoError(t, os.WriteFile(filepath.Join(configDir, "gtk-3.0", "gtk.css"), []byte(dankImport), 0o644))
			},
			want: true,
		},
		{
			name: "user stylesheet without dank colors",
			setup: func(t *testing.T, configDir, storeDir string) {
				target := filepath.Join(storeDir, "hm-gtk.css")
				require.NoError(t, os.WriteFile(target, []byte("window { margin: 0; }\n"), 0o644))
				require.NoError(t, os.Symlink(target, filepath.Join(configDir, "gtk-4.0", "gtk.css")))
			},
			want: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			configDir := t.TempDir()
			for _, dir := range []string{"gtk-3.0", "gtk-4.0"} {
				require.NoError(t, os.MkdirAll(filepath.Join(configDir, dir), 0o755))
			}
			tt.setup(t, configDir, t.TempDir())
			assert.Equal(t, tt.want, isDMSGTKActive(configDir))
		})
	}
}

func TestColorSchemeTarget(t *testing.T) {
	tests := []struct {
		mode    ColorMode
		current string
		want    string
		changes bool
	}{
		{ColorModeDark, "prefer-dark", "prefer-dark", false},
		{ColorModeDark, "default", "prefer-dark", true},
		{ColorModeLight, "prefer-light", "default", false},
		{ColorModeLight, "prefer-dark", "default", true},
		{ColorModeLight, "", "default", true},
	}
	for _, tt := range tests {
		got, changes := colorSchemeTarget(tt.mode, tt.current)
		assert.Equal(t, tt.want, got, "%s from %q", tt.mode, tt.current)
		assert.Equal(t, tt.changes, changes, "%s from %q", tt.mode, tt.current)
	}
}
