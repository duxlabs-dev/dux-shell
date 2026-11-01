package niriconf

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

var NiriBin = "niri"

const (
	validateTimeout = 10 * time.Second
	validatePrefix  = "dms-niri-validate-"
	staleCopyAge    = 6 * validateTimeout
)

type InvalidError struct{ Output string }

func (e *InvalidError) Error() string { return "invalid config: " + e.Output }

// ValidateMerged runs niri validate on a copy of configDir where fragment holds content,
// so includes and overrides across files are checked together.
func ValidateMerged(configDir, fragment string, content []byte) error {
	return validateFiles(configDir, map[string][]byte{fragment: content})
}

// validateFiles is ValidateMerged with several fragments replaced at once.
func validateFiles(configDir string, files map[string][]byte) error {
	for fragment := range files {
		if !filepath.IsLocal(fragment) {
			return fmt.Errorf("fragment %q is outside the niri config dir", fragment)
		}
	}
	removeStaleCopies()
	tmp, err := os.MkdirTemp("", validatePrefix)
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	home := filepath.Join(tmp, "home")
	copyDir := filepath.Join(home, ".config", "niri")
	if err := writeCopy(configDir, copyDir, files); err != nil {
		return err
	}
	return runValidate(home, copyDir)
}

// removeStaleCopies drops the copies of the user's config a killed process left behind.
// A younger copy may belong to a validation still running in another process.
func removeStaleCopies() {
	dirs, _ := filepath.Glob(filepath.Join(os.TempDir(), validatePrefix+"*"))
	for _, dir := range dirs {
		if strings.Trim(strings.TrimPrefix(filepath.Base(dir), validatePrefix), "0123456789") != "" {
			continue
		}
		info, err := os.Lstat(dir)
		if err != nil || !info.IsDir() || time.Since(info.ModTime()) < staleCopyAge {
			continue
		}
		if st, ok := info.Sys().(*syscall.Stat_t); !ok || int(st.Uid) != os.Getuid() {
			continue
		}
		os.RemoveAll(dir)
	}
}

func writeCopy(configDir, copyDir string, files map[string][]byte) error {
	realDir, err := filepath.EvalSymlinks(configDir)
	if err != nil {
		return err
	}
	if err := copyTree(realDir, realDir, copyDir, map[string]bool{}); err != nil {
		return err
	}
	for fragment, content := range files {
		target := filepath.Join(copyDir, fragment)
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(target, content, 0o644); err != nil {
			return err
		}
	}
	return redirectAbsoluteIncludes(copyDir, []string{configDir, realDir})
}

func runValidate(home, copyDir string) error {
	ctx, cancel := context.WithTimeout(context.Background(), validateTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, NiriBin, "validate", "-c", filepath.Join(copyDir, "config.kdl"))
	cmd.Env = append(os.Environ(), "HOME="+home, "XDG_CONFIG_HOME="+filepath.Join(home, ".config"))
	out, err := cmd.CombinedOutput()
	// Paths relative to the niri dir: the absolute one carries the account name into logs and the UI.
	output := strings.ReplaceAll(string(out), copyDir+string(filepath.Separator), "")
	if err == nil {
		return nil
	}
	if ctx.Err() != nil {
		return fmt.Errorf("niri validate timed out")
	}
	// Exit 2 is a clap usage error: a niri without "validate -c", not a bad config.
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) && exitErr.ExitCode() == 1 {
		return &InvalidError{Output: output}
	}
	return fmt.Errorf("cannot run %s validate: %w: %s", NiriBin, err, strings.TrimSpace(output))
}

// copyTree copies regular files, following symlinks; seen breaks symlink loops.
// Hidden directories (.git of a dotfiles repo, .history) are skipped.
// A directory link leaving root is skipped, or a link to home would copy home;
// file links may leave it, as home-manager links config.kdl into the nix store.
func copyTree(root, src, dst string, seen map[string]bool) error {
	real, err := filepath.EvalSymlinks(src)
	if err != nil {
		return err
	}
	if rel, err := filepath.Rel(root, real); err != nil || rel != "." && !filepath.IsLocal(rel) {
		return nil
	}
	if seen[real] {
		return nil
	}
	seen[real] = true

	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	for _, e := range entries {
		from, to := filepath.Join(src, e.Name()), filepath.Join(dst, e.Name())
		info, err := os.Stat(from)
		if err != nil {
			continue // dangling symlink
		}
		switch {
		case info.IsDir():
			if strings.HasPrefix(e.Name(), ".") {
				continue
			}
			if err := copyTree(root, from, to, seen); err != nil {
				return err
			}
		case info.Mode().IsRegular():
			data, err := os.ReadFile(from)
			if err != nil {
				return err
			}
			if err := os.WriteFile(to, data, 0o644); err != nil {
				return err
			}
		}
	}
	return nil
}

// redirectAbsoluteIncludes points includes written as absolute paths into the
// niri dir at the copy; HOME only covers the "~/" form.
func redirectAbsoluteIncludes(copyDir string, liveDirs []string) error {
	return filepath.WalkDir(copyDir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || filepath.Ext(path) != ".kdl" {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		text := string(data)
		for _, dir := range liveDirs {
			text = strings.ReplaceAll(text, `"`+dir+`/`, `"`+copyDir+`/`)
		}
		if text == string(data) {
			return nil
		}
		return os.WriteFile(path, []byte(text), 0o644)
	})
}
