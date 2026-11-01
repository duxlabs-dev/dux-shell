package niriconf

import (
	"bytes"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

var ErrNoUndo = errors.New("nothing to undo")

// includeBackup is the one copy of config.kdl kept before the doctor rewrites it, next to it.
func includeBackup(configDir string) string {
	return filepath.Join(configDir, "config.kdl.dms-bak")
}

// writeBackup narrows an old backup before the new content lands in it: config.kdl may hold commands or env values.
func writeBackup(path string, data []byte, mode fs.FileMode) error {
	if err := os.Chmod(path, mode); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return os.WriteFile(path, data, mode)
}

func dropIncludeBackup(configDir string) {
	os.Remove(includeBackup(configDir))
}

// AddInclude appends `include optional=true "dms/name"` to config.kdl once niri validates it,
// keeps a backup for UndoInclude, and puts the old file back if niri fails to reload.
func (s *Store) AddInclude(name string) error {
	if !validName(name) {
		return ErrBadName
	}
	if _, err := os.Stat(s.path(name)); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	old, config, err := stageInclude(s.ConfigDir, name)
	if err != nil || config == nil {
		return err
	}
	return s.applyInclude(old, config)
}

// stageInclude returns config.kdl before and after the include, validated and backed up.
// A nil config means the include is already there.
func stageInclude(configDir, name string) (old, config []byte, err error) {
	configPath := filepath.Join(configDir, "config.kdl")
	info, err := os.Stat(configPath)
	if err != nil {
		return nil, nil, err
	}
	if old, err = os.ReadFile(configPath); err != nil {
		return nil, nil, err
	}
	if config, err = withInclude(configDir, name); err != nil || config == nil {
		return nil, nil, err
	}
	if err := validateFiles(configDir, map[string][]byte{"config.kdl": config}); err != nil {
		return nil, nil, err
	}
	if err := writeBackup(includeBackup(configDir), old, info.Mode().Perm()); err != nil {
		return nil, nil, err
	}
	return old, config, nil
}

// applyInclude writes config and puts old back if niri fails to reload it.
func (s *Store) applyInclude(old, config []byte) error {
	configPath := filepath.Join(s.ConfigDir, "config.kdl")
	waiter := s.subscribe()
	if waiter != nil {
		defer waiter.Close()
	}
	if err := WriteAtomic(configPath, config); err != nil {
		dropIncludeBackup(s.ConfigDir)
		return err
	}
	if waiter == nil || !reloadFailed(waiter) {
		return nil
	}
	// Restore first: the backup is the only copy of the old file until the restore lands.
	if err := WriteAtomic(configPath, old); err != nil {
		return errors.Join(ErrReloadFailed, err)
	}
	dropIncludeBackup(s.ConfigDir)
	return ErrReloadFailed
}

// UndoInclude puts back config.kdl as it was before the last AddInclude, unless it changed since.
func (s *Store) UndoInclude() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	old, err := os.ReadFile(includeBackup(s.ConfigDir))
	if errors.Is(err, fs.ErrNotExist) {
		return ErrNoUndo
	}
	if err != nil {
		return err
	}
	if !undoable(s.ConfigDir) {
		return ErrChanged
	}
	// No validation: niri loaded this file before the include was added.
	if err := WriteAtomic(filepath.Join(s.ConfigDir, "config.kdl"), old); err != nil {
		return err
	}
	dropIncludeBackup(s.ConfigDir)
	return nil
}

// undoable is true while config.kdl is still the file AddInclude wrote: the backup plus its one include line.
func undoable(configDir string) bool {
	old, err := os.ReadFile(includeBackup(configDir))
	if err != nil {
		return false
	}
	current, err := os.ReadFile(filepath.Join(configDir, "config.kdl"))
	if err != nil {
		return false
	}
	added, ok := bytes.CutPrefix(current, old)
	if !ok {
		return false
	}
	name, ok := strings.CutPrefix(strings.TrimPrefix(string(added), "\n"), `include optional=true "dms/`)
	if !ok {
		return false
	}
	name, ok = strings.CutSuffix(name, "\"\n")
	return ok && validName(name)
}
