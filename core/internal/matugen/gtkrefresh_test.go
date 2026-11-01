package matugen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// The gtk-theme round trip must never pass through a light theme in dark mode:
// Chromium/Electron without a settings portal follow the toolkit and latch light.
// Nor through HighContrast*, which latches GTK4 apps in high contrast.
func TestRefreshGTKThemeKeepsDarkPolarity(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	require.NoError(t, os.MkdirAll(filepath.Join(home, ".themes", "adw-gtk3-dark"), 0o755))

	binDir := t.TempDir()
	logPath := filepath.Join(binDir, "calls.log")
	script := "#!/bin/sh\necho \"$*\" >> " + logPath + "\n"
	require.NoError(t, os.WriteFile(filepath.Join(binDir, "dconf"), []byte(script), 0o755))
	t.Setenv("PATH", binDir)
	t.Setenv("GSETTINGS_BACKEND", "")

	refreshGTKTheme(ColorModeDark)

	data, err := os.ReadFile(logPath)
	require.NoError(t, err)
	calls := strings.Split(strings.TrimSpace(string(data)), "\n")
	require.Len(t, calls, 2)
	assert.Equal(t, "write /org/gnome/desktop/interface/gtk-theme 'adw-gtk3'", calls[0])
	assert.Equal(t, "write /org/gnome/desktop/interface/gtk-theme 'adw-gtk3-dark'", calls[1])
}
