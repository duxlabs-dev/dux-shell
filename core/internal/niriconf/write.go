package niriconf

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
)

// WriteAtomic resolves symlinks first so a dotfiles link stays a link.
func WriteAtomic(path string, data []byte) error {
	target, err := writeTarget(path)
	if err != nil {
		return err
	}

	mode := fs.FileMode(0o644)
	if info, err := os.Stat(target); err == nil {
		mode = info.Mode().Perm()
	}

	dir := filepath.Dir(target)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	tmp, err := os.CreateTemp(dir, filepath.Base(target)+".tmp*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	ok := false
	defer func() {
		if !ok {
			tmp.Close()
			os.Remove(tmpName)
		}
	}()

	if _, err := tmp.Write(data); err != nil {
		return err
	}
	if err := tmp.Sync(); err != nil {
		return err
	}
	if err := tmp.Chmod(mode); err != nil {
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpName, target); err != nil {
		return err
	}
	ok = true
	return nil
}

func writeTarget(path string) (string, error) {
	target, err := filepath.EvalSymlinks(path)
	switch {
	case err == nil:
		return target, nil
	case errors.Is(err, fs.ErrNotExist):
		// A dangling link must not be replaced by a regular file.
		if _, lerr := os.Lstat(path); lerr == nil {
			return "", err
		}
		return path, nil
	}
	return "", err
}
