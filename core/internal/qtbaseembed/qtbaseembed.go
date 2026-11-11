// Package qtbaseembed carries libdux-qt-base.so inside the dms binary and
// materializes it for dlopen via dankgo/shellapp/shellfs, the same way
// shellembed does for the QML tree.
package qtbaseembed

import (
	"io/fs"
	"os"
	"path"
	"path/filepath"

	"github.com/duxlabs-dev/dux-go/qtbase"
	"github.com/duxlabs-dev/dux-go/shellapp/shellfs"
)

const libRoot = "lib"

// Available reports whether this binary was built with the embedded runtime
// (the withqtbase build tag).
func Available() bool {
	info, err := fs.Stat(libFS, path.Join(libRoot, qtbase.Soname))
	return err == nil && !info.IsDir()
}

// Extract is the qtbase.Locator for the embedded copy: "" when this build has none.
func Extract() (string, error) {
	if !Available() {
		return "", nil
	}
	sub, err := fs.Sub(libFS, libRoot)
	if err != nil {
		return "", err
	}
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		return "", err
	}
	// the cache dir rather than the runtime tmpfs keeps the mapped code evictable
	baseDir := filepath.Join(cacheDir, "dms", "qtbase")
	dir, err := shellfs.Extract(sub, baseDir)
	if err != nil {
		return "", err
	}
	// dlopen maps the whole file, so a running older shell keeps its copy after the unlink
	shellfs.Prune(baseDir, dir)
	return filepath.Join(dir, qtbase.Soname), nil
}

// Resolve returns the runtime library this binary would run the UI with.
func Resolve() (string, error) {
	return qtbase.Locate(Extract)
}
