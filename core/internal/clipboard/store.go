package clipboard

import (
	"os"
	"path/filepath"
)

func GetDBPath() (string, error) {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		cacheDir = filepath.Join(homeDir, ".cache")
	}

	newDir := filepath.Join(cacheDir, "dms", "clipboard")
	newPath := filepath.Join(newDir, "db")

	if _, err := os.Stat(newPath); err == nil {
		return newPath, nil
	}

	oldDir := filepath.Join(cacheDir, "dms-clipboard")
	oldPath := filepath.Join(oldDir, "db")

	if _, err := os.Stat(oldPath); err == nil {
		if err := os.MkdirAll(newDir, 0o700); err != nil {
			return "", err
		}
		if err := os.Rename(oldPath, newPath); err != nil {
			return "", err
		}
		os.Remove(oldDir)
		return newPath, nil
	}

	if err := os.MkdirAll(newDir, 0o700); err != nil {
		return "", err
	}
	return newPath, nil
}
