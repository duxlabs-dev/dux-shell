package config

import (
	"bytes"
	"os"
	"path/filepath"
)

// WriteNiriConfig replaces path only once niri accepts content. The temp file sits beside the target so relative includes resolve.
func WriteNiriConfig(path string, content []byte) error {
	target := niriWriteTarget(path)
	dir := filepath.Dir(target)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, filepath.Base(target)+".*.tmp")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())

	_, err = tmp.Write(content)
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return err
	}
	// Bytes already on disk need no second verdict. The rename still runs: niri reloads on it and the shell's layout sync waits for that reload.
	if existing, err := os.ReadFile(target); err != nil || !bytes.Equal(existing, content) {
		if out, err := NiriValidateFile(tmp.Name()); err != nil {
			return niriValidateError(out, err)
		}
	}
	return os.Rename(tmp.Name(), target)
}

// dms/outputs.kdl links to the active profile, and the write has to land on the profile.
func niriWriteTarget(path string) string {
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		return resolved
	}
	link, err := os.Readlink(path)
	if err != nil {
		return path
	}
	if filepath.IsAbs(link) {
		return link
	}
	return filepath.Join(filepath.Dir(path), link)
}
