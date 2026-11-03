package mangoconf

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Dir is the only config directory Mango reads; it ignores XDG_CONFIG_HOME.
func Dir() string {
	return filepath.Join(os.Getenv("HOME"), ".config", "mango")
}

const SessionTarget = "mango-session.target"

// Headers setup puts on a binds.conf that holds the user's binds; the keybind editor never rebuilds such a file.
const (
	BindsMovedHeader = "# Moved from config.conf by dms setup"
	BindsKeptHeader  = "# Kept by dms setup"
)

func HasUserBindsHeader(content string) bool {
	return strings.Contains(content, BindsMovedHeader) || strings.Contains(content, BindsKeptHeader)
}

var unitDirs = []string{
	"/etc/systemd/user",
	"/usr/local/lib/systemd/user",
	"/usr/lib/systemd/user",
	"/lib/systemd/user",
	"/run/current-system/sw/lib/systemd/user",
}

// SessionTargetInstalled reports whether this Mango ships mango-session.target,
// which Mango >= 0.17.1 starts itself after importing its environment into systemd.
func SessionTargetInstalled() bool {
	if _, err := exec.LookPath("systemctl"); err != nil {
		return false
	}
	dirs := append([]string{filepath.Join(os.Getenv("HOME"), ".config", "systemd", "user")}, unitDirs...)
	for _, dir := range dirs {
		if _, err := os.Stat(filepath.Join(dir, SessionTarget)); err == nil {
			return true
		}
	}
	return false
}
