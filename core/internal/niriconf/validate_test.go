package niriconf

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func setupValidate(t *testing.T, config, live string) string {
	t.Helper()
	bin, err := filepath.Abs("testdata/fake-niri.sh")
	if err != nil {
		t.Fatal(err)
	}
	old := NiriBin
	NiriBin = bin
	t.Cleanup(func() { NiriBin = old })

	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".config", "niri")
	if err := os.MkdirAll(filepath.Join(dir, "dms"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "config.kdl"), []byte(config), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "dms", "niri.kdl"), []byte(live), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestValidateMergedSeesNewFragment(t *testing.T) {
	dir := setupValidate(t, `include "dms/niri.kdl"`+"\n", "layout {}\n")

	err := ValidateMerged(dir, "dms/niri.kdl", []byte("BAD\n"))
	var inv *InvalidError
	if !errors.As(err, &inv) {
		t.Fatalf("want *InvalidError, got %v", err)
	}
	if inv.Output != "error: bad\n" {
		t.Fatalf("output %q", inv.Output)
	}
	got, _ := os.ReadFile(filepath.Join(dir, "dms", "niri.kdl"))
	if string(got) != "layout {}\n" {
		t.Fatalf("live file changed: %q", got)
	}
	if err := ValidateMerged(dir, "dms/niri.kdl", []byte("layout {}\n")); err != nil {
		t.Fatalf("clean content: %v", err)
	}
}

// The live fragment holds BAD and the new one is clean: niri must read the copy.
func TestValidateMergedIncludeReachesCopy(t *testing.T) {
	cases := map[string]string{
		"tilde":    `include "~/.config/niri/dms/niri.kdl"`,
		"absolute": "",
	}
	for name, include := range cases {
		t.Run(name, func(t *testing.T) {
			dir := setupValidate(t, "", "BAD\n")
			if include == "" {
				include = `include "` + filepath.Join(dir, "dms", "niri.kdl") + `"`
			}
			if err := os.WriteFile(filepath.Join(dir, "config.kdl"), []byte(include+"\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := ValidateMerged(dir, "dms/niri.kdl", []byte("layout {}\n")); err != nil {
				t.Fatalf("validation read the live fragment: %v", err)
			}
		})
	}
}

func TestValidateMergedFollowsSymlinkedDir(t *testing.T) {
	dir := setupValidate(t, `include "dms/niri.kdl"`+"\n", "layout {}\n")
	real := filepath.Join(t.TempDir(), "dots")
	if err := os.Rename(dir, real); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(real, dir); err != nil {
		t.Fatal(err)
	}

	err := ValidateMerged(dir, "dms/niri.kdl", []byte("BAD\n"))
	var inv *InvalidError
	if !errors.As(err, &inv) {
		t.Fatalf("want *InvalidError, got %v", err)
	}
}

func TestValidateMergedNiriCannotRun(t *testing.T) {
	cases := map[string]func(t *testing.T){
		"missing": func(t *testing.T) { NiriBin = filepath.Join(t.TempDir(), "no-niri") },
		"too old": func(t *testing.T) { t.Setenv("FAKE_NIRI_OLD", "1") },
	}
	for name, setup := range cases {
		t.Run(name, func(t *testing.T) {
			dir := setupValidate(t, `include "dms/niri.kdl"`+"\n", "layout {}\n")
			setup(t)
			err := ValidateMerged(dir, "dms/niri.kdl", []byte("layout {}\n"))
			var inv *InvalidError
			if err == nil || errors.As(err, &inv) {
				t.Fatalf("want a plain error, got %v", err)
			}
		})
	}
}

func TestValidateMergedOutputHasRelativePaths(t *testing.T) {
	dir := setupValidate(t, `include "dms/niri.kdl"`+"\n", "")
	t.Setenv("FAKE_NIRI_PATHS", "1")

	err := ValidateMerged(dir, "dms/niri.kdl", []byte("BAD\n"))
	var inv *InvalidError
	if !errors.As(err, &inv) {
		t.Fatalf("want *InvalidError, got %v", err)
	}
	if inv.Output != "dms/niri.kdl\nerror: bad\n" {
		t.Fatalf("output %q", inv.Output)
	}
}

func TestValidateMergedSkipsDirLinkLeavingConfig(t *testing.T) {
	cases := map[string]struct {
		target func(dir string) string
		ok     bool
	}{
		"outside": {func(string) string { return t.TempDir() }, true},
		"inside":  {func(dir string) string { return filepath.Join(dir, "parts") }, false},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			dir := setupValidate(t, `include "dms/niri.kdl"`+"\n", "")
			target := c.target(dir)
			if err := os.MkdirAll(target, 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(target, "x.kdl"), []byte("BAD\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := os.Symlink(target, filepath.Join(dir, "linked")); err != nil {
				t.Fatal(err)
			}
			err := ValidateMerged(dir, "dms/niri.kdl", []byte("layout {}\n"))
			if (err == nil) != c.ok {
				t.Fatalf("err = %v, want ok %v", err, c.ok)
			}
		})
	}
}

func TestValidateMergedRefusesFragmentOutsideDir(t *testing.T) {
	dir := setupValidate(t, "", "")
	if err := ValidateMerged(dir, "../x.kdl", []byte("layout {}\n")); err == nil {
		t.Fatal("want an error")
	}
}

func TestValidateRemovesStaleCopies(t *testing.T) {
	dir := setupValidate(t, `include "dms/niri.kdl"`+"\n", "")
	tmp := t.TempDir()
	t.Setenv("TMPDIR", tmp)
	old := time.Now().Add(-time.Hour)
	want := map[string]bool{
		"dms-niri-validate-111":   false,
		"dms-niri-validate-222":   true,
		"dms-niri-validate-other": true,
		"other-333":               true,
	}
	for name := range want {
		path := filepath.Join(tmp, name)
		if err := os.MkdirAll(filepath.Join(path, "home"), 0o700); err != nil {
			t.Fatal(err)
		}
		if name != "dms-niri-validate-222" {
			if err := os.Chtimes(path, old, old); err != nil {
				t.Fatal(err)
			}
		}
	}

	if err := ValidateMerged(dir, "dms/niri.kdl", []byte("layout {}\n")); err != nil {
		t.Fatal(err)
	}
	for name, kept := range want {
		if _, err := os.Stat(filepath.Join(tmp, name)); (err == nil) != kept {
			t.Errorf("%s: kept %v, want %v", name, err == nil, kept)
		}
	}
}
