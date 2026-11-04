package niriconf

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

const dmsInclude = "include optional=true \"dms/niri.kdl\"\n"

func writeConfig(t *testing.T, content string) (configDir, configPath string) {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	configDir = filepath.Join(home, ".config", "niri")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}
	configPath = filepath.Join(configDir, "config.kdl")
	if err := os.WriteFile(configPath, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return configDir, configPath
}

func TestWithIncludeAppends(t *testing.T) {
	for original, want := range map[string]string{
		"input {\n    keyboard {}\n}\n": "input {\n    keyboard {}\n}\n" + dmsInclude,
		"layout {}":                     "layout {}\n" + dmsInclude,
	} {
		configDir, _ := writeConfig(t, original)
		got, err := withInclude(configDir, "niri.kdl")
		if err != nil {
			t.Fatal(err)
		}
		if string(got) != want {
			t.Fatalf("config = %q, want %q", got, want)
		}
	}
}

func TestWithIncludeFindsExisting(t *testing.T) {
	for _, line := range []string{
		`include "dms/niri.kdl"`,
		`include "~/.config/niri/dms/niri.kdl"`,
	} {
		configDir, _ := writeConfig(t, "layout {}\n"+line+"\n")
		got, err := withInclude(configDir, "niri.kdl")
		if err != nil {
			t.Fatal(err)
		}
		if got != nil {
			t.Fatalf("%s: want no change, got %q", line, got)
		}
	}
}

func TestWithIncludeRefusesBadName(t *testing.T) {
	for _, c := range []struct {
		name string
		ok   bool
	}{
		{"../x.kdl", false},
		{"x.txt", false},
		{"X.kdl", false},
		{"a/b.kdl", false},
		{`a"b.kdl`, false},
		{"niri.kdl", true},
	} {
		configDir, _ := writeConfig(t, "layout {}\n")
		_, err := withInclude(configDir, c.name)
		if c.ok != (err == nil) || !c.ok && !errors.Is(err, ErrBadName) {
			t.Fatalf("%s: err = %v", c.name, err)
		}
	}
}
