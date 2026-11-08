package drives

import (
	"os"
	"os/exec"
	"path/filepath"

	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
)

var installCommands = map[distros.DistroFamily]string{
	distros.FamilyArch:   "sudo pacman -S smartmontools",
	distros.FamilyFedora: "sudo dnf install smartmontools",
	distros.FamilyUbuntu: "sudo apt install smartmontools",
	distros.FamilyDebian: "sudo apt install smartmontools",
	distros.FamilySUSE:   "sudo zypper install smartmontools",
	distros.FamilyVoid:   "sudo xbps-install smartmontools",
	distros.FamilyGentoo: "sudo emerge sys-apps/smartmontools",
}

// smartctlPath also checks sbin directories, which are often missing from a user's PATH.
func smartctlPath() string {
	if p, err := exec.LookPath("smartctl"); err == nil {
		if abs, err := filepath.Abs(p); err == nil {
			return abs
		}
	}
	for _, p := range []string{"/usr/sbin/smartctl", "/sbin/smartctl"} {
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() && fi.Mode()&0o111 != 0 {
			return p
		}
	}
	return ""
}

func installCommand() string {
	info, err := distros.GetOSInfo()
	if err != nil || info.Immutable {
		return ""
	}
	return installCommands[distros.Registry[info.Distribution.ID].Family]
}
