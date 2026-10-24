package utils

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

const (
	AppDirName        = "dms"
	legacyDirName     = "DankMaterialShell"
	migrateLock       = "dms-migrate"
	maxCompareFileLen = 1 << 20
)

func ColorsFilePath() string {
	return filepath.Join(XDGCacheHome(), AppDirName, "dms-colors.json")
}

// MigrateLegacyDirs moves the pre-2.0 DankMaterialShell config, state, cache and
// data dirs to dms and leaves a symlink at the old path for older binaries and plugins.
func MigrateLegacyDirs() []error {
	lock, err := TryLock(migrateLock)
	if err != nil {
		return nil
	}
	defer lock.Release()

	var errs []error
	for _, base := range []string{XDGConfigHome(), XDGStateHome(), XDGCacheHome(), XDGDataHome()} {
		if err := migrateLegacyDir(filepath.Join(base, legacyDirName), filepath.Join(base, AppDirName)); err != nil {
			errs = append(errs, err)
		}
	}
	return errs
}

func migrateLegacyDir(oldDir, newDir string) error {
	oldInfo, err := os.Lstat(oldDir)
	if err != nil {
		return nil
	}
	_, newErr := os.Lstat(newDir)
	newExists := newErr == nil

	switch {
	case oldInfo.Mode()&os.ModeSymlink != 0:
		if newExists {
			return nil
		}
		return os.Symlink(legacyDirName, newDir)
	case !oldInfo.IsDir():
		return nil
	case !newExists:
		if err := os.Rename(oldDir, newDir); err != nil {
			// A bind-mounted or persisted legacy dir cannot be renamed; read it through a link instead.
			return os.Symlink(legacyDirName, newDir)
		}
		return os.Symlink(AppDirName, oldDir)
	}

	if err := mergeDir(oldDir, newDir); err != nil {
		if errors.Is(err, syscall.EXDEV) {
			return fmt.Errorf("%s is on another filesystem, persist %s instead: %w", oldDir, newDir, err)
		}
		return err
	}
	// dms-greeter sync grants the greeter group read access through an ACL on the legacy dir.
	copyDirACL(oldDir, newDir)
	if err := os.Remove(oldDir); err != nil {
		return errors.New("legacy dir " + oldDir + " still has entries that also exist in " + newDir)
	}
	return os.Symlink(AppDirName, oldDir)
}

func mergeDir(src, dst string) error {
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		from := filepath.Join(src, entry.Name())
		to := filepath.Join(dst, entry.Name())
		toInfo, err := os.Lstat(to)
		if err != nil {
			if err := os.Rename(from, to); err != nil {
				return err
			}
			continue
		}
		if sameFileContent(from, to) {
			os.Remove(from)
			continue
		}
		if !entry.IsDir() || !toInfo.IsDir() {
			continue
		}
		if err := mergeDir(from, to); err != nil {
			return err
		}
		os.Remove(from)
	}
	return nil
}

func sameFileContent(a, b string) bool {
	aInfo, err := os.Lstat(a)
	if err != nil || !aInfo.Mode().IsRegular() {
		return false
	}
	bInfo, err := os.Lstat(b)
	if err != nil || !bInfo.Mode().IsRegular() || aInfo.Size() != bInfo.Size() || aInfo.Size() > maxCompareFileLen {
		return false
	}
	aData, err := os.ReadFile(a)
	if err != nil {
		return false
	}
	bData, err := os.ReadFile(b)
	if err != nil {
		return false
	}
	return bytes.Equal(aData, bData)
}
