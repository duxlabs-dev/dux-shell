package globalshortcuts

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"

	"github.com/duxlabs-dev/dux-go/atomicfile"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type storeFile struct {
	Apps []App `json:"apps"`
}

func storePath() (string, error) {
	dir, err := utils.App().ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "global-shortcuts.json"), nil
}

func loadApps(path string) ([]App, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var file storeFile
	if err := json.Unmarshal(data, &file); err != nil {
		return nil, err
	}
	return file.Apps, nil
}

func saveApps(path string, apps []App) error {
	data, err := json.MarshalIndent(storeFile{Apps: apps}, "", "  ")
	if err != nil {
		return err
	}
	return atomicfile.WriteFileMkdir(path, data, 0o644, 0o755)
}
