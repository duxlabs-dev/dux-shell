package main

import (
	"os"
	"path/filepath"
	"testing"
)

func writeConfigFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestNiriFindIncludeNestedRelativeToIncludingFile(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, filepath.Join(dir, "config.kdl"), "include \"dms/dms.kdl\"\n")
	writeConfigFile(t, filepath.Join(dir, "dms", "dms.kdl"), "include \"binds.kdl\"\ninclude \"./outputs.kdl\"\n")

	for _, name := range []string{"binds.kdl", "outputs.kdl"} {
		target := filepath.Join(dir, "dms", name)
		if !niriFindInclude(filepath.Join(dir, "config.kdl"), target, map[string]bool{}) {
			t.Errorf("%s included through dms/dms.kdl not detected", name)
		}
	}

	if niriFindInclude(filepath.Join(dir, "config.kdl"), filepath.Join(dir, "dms", "layout.kdl"), map[string]bool{}) {
		t.Error("layout.kdl reported included without an include line")
	}
}

func TestMangowcFindIncludeNestedRelativeToIncludingFile(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, filepath.Join(dir, "config.conf"), "source=./dms/dms.conf\n")
	writeConfigFile(t, filepath.Join(dir, "dms", "dms.conf"), "source = binds.conf\n")

	if !mangowcFindInclude(filepath.Join(dir, "config.conf"), filepath.Join(dir, "dms", "binds.conf"), map[string]bool{}) {
		t.Error("binds.conf sourced through dms/dms.conf not detected")
	}
}

func TestCheckHyprlandIncludeIgnoresLegacyConf(t *testing.T) {
	xdg := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", xdg)
	writeConfigFile(t, filepath.Join(xdg, "hypr", "hyprland.conf"), "source = ./dms/colors.conf\n")
	writeConfigFile(t, filepath.Join(xdg, "hypr", "dms", "colors.conf"), "")

	got, err := checkHyprlandInclude("colors.conf")
	if err != nil {
		t.Fatal(err)
	}
	if got.Included {
		t.Fatalf("got %+v; a hyprland.conf source must not count once Hyprland reads only Lua", got)
	}
}
