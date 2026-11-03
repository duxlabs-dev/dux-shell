package utils

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-go/paths"
)

var app = paths.New("dms")

func App() paths.App { return app }

func RuntimeDir() string { return app.SocketDir() }

func XDGStateHome() string { return paths.XDGStateHome() }

func XDGDataHome() string { return paths.XDGDataHome() }

func XDGCacheHome() string { return paths.XDGCacheHome() }

func XDGConfigHome() string { return paths.XDGConfigHome() }

func ExpandPath(path string) (string, error) { return paths.ExpandPath(path) }

func XDGPicturesDir() string {
	if dir := os.Getenv("XDG_PICTURES_DIR"); dir != "" {
		if expanded, err := ExpandPath(dir); err == nil {
			return expanded
		}
	}

	data, err := os.ReadFile(filepath.Join(XDGConfigHome(), "user-dirs.dirs"))
	if err != nil {
		return ""
	}

	const prefix = "XDG_PICTURES_DIR="
	for line := range strings.SplitSeq(string(data), "\n") {
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		if !strings.HasPrefix(line, prefix) {
			continue
		}
		path := strings.Trim(line[len(prefix):], "\"")
		expanded, err := ExpandPath(path)
		if err != nil {
			return ""
		}
		return expanded
	}
	return ""
}

func EmacsConfigDir() string {
	home, _ := os.UserHomeDir()

	emacsD := filepath.Join(home, ".emacs.d")
	if info, err := os.Stat(emacsD); err == nil && info.IsDir() {
		return emacsD
	}

	xdgEmacs := filepath.Join(XDGConfigHome(), "emacs")
	if info, err := os.Stat(xdgEmacs); err == nil && info.IsDir() {
		return xdgEmacs
	}

	return ""
}
