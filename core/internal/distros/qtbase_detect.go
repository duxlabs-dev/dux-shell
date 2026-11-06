package distros

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"

	"github.com/duxlabs-dev/dux-go/qtbase"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

const duxQtBaseSoname = "libdux-qt-base.so.0"

func (b *BaseDistribution) detectDuxQtBase() deps.Dependency {
	dep := deps.Dependency{
		Name:        "dux-qt-base",
		Description: "Quickshell runtime library linked into dms",
		Required:    true,
		Variant:     deps.VariantStable,
	}
	switch {
	case qtbase.Embedded():
		dep.Status = deps.StatusInstalled
		dep.Version = qtbase.Version()
	case duxQtBaseInstalled():
		dep.Status = deps.StatusInstalled
	default:
		dep.Status = deps.StatusMissing
	}
	return dep
}

func duxQtBaseInstalled() bool {
	if exec.Command("pkg-config", "--exists", "dux-qt-base").Run() == nil {
		return true
	}
	for _, dir := range duxQtBaseLibDirs() {
		if _, err := os.Stat(filepath.Join(dir, duxQtBaseSoname)); err == nil {
			return true
		}
	}
	return false
}

func duxQtBaseLibDirs() []string {
	dirs := []string{"/usr/lib", "/usr/lib64", "/usr/local/lib", "/usr/local/lib64"}
	triplets := map[string]string{"amd64": "x86_64-linux-gnu", "arm64": "aarch64-linux-gnu"}
	if triplet, ok := triplets[runtime.GOARCH]; ok {
		dirs = append(dirs, filepath.Join("/usr/lib", triplet))
	}
	return dirs
}
