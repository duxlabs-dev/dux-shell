// Package shellembed carries the quickshell UI inside the dms binary and
// materializes it at runtime via dankgo/shellapp/shellfs, since quickshell
// needs a real filesystem path. Customization goes through -c /
// DMS_SHELL_DIR instead of editing the extraction.
package shellembed

import (
	"io/fs"
	"path"
	"strings"

	"github.com/duxlabs-dev/dux-go/shellapp/shellfs"
)

const (
	distRoot    = "dist"
	shellEntry  = "shell.qml"
	versionFile = "VERSION"
)

// Available reports whether this binary was built with the embedded UI
// (the withshell build tag).
func Available() bool {
	info, err := fs.Stat(distFS, path.Join(distRoot, shellEntry))
	return err == nil && !info.IsDir()
}

// Version reports the embedded UI's VERSION, empty when unavailable.
func Version() string {
	data, err := fs.ReadFile(distFS, path.Join(distRoot, versionFile))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func Extract(baseDir string) (string, error) {
	sub, err := fs.Sub(distFS, distRoot)
	if err != nil {
		return "", err
	}
	return shellfs.Extract(sub, baseDir)
}

func Prune(baseDir, keep string) {
	shellfs.Prune(baseDir, keep)
}
