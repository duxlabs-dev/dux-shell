package main

import (
	"os"
	"path/filepath"
	"strings"
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

func TestMangowcFindIncludeResolvesLikeMango(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".config", "mango")
	writeConfigFile(t, filepath.Join(dir, "config.conf"), "source=./dms/dms.conf\n")
	// Mango reads ./ from the config dir whichever file sources it, and a bare path from its working directory.
	writeConfigFile(t, filepath.Join(dir, "dms", "dms.conf"), "source=./dms/binds.conf\nsource = cursor.conf\n")
	writeConfigFile(t, filepath.Join(dir, "dms", "binds.conf"), "")
	writeConfigFile(t, filepath.Join(dir, "dms", "cursor.conf"), "")

	for name, want := range map[string]bool{"binds.conf": true, "cursor.conf": false} {
		got, err := checkMangoWCInclude(name)
		if err != nil {
			t.Fatal(err)
		}
		if got.Included != want {
			t.Errorf("%s included = %v, want %v", name, got.Included, want)
		}
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

func TestCheckMangoWCIncludeReadsConfigToml(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".config", "mango")
	writeConfigFile(t, filepath.Join(dir, "config.toml"), `[global]
source = [
    "./dms/cursor.conf", # pointer
    # "./dms/layout.conf",
]

[bind.default]
"SUPER+Return" = "spawn,foot"

# DMS Include Configs
[global]
source = "./dms/outputs.conf"
`)

	for name, want := range map[string]bool{"cursor.conf": true, "outputs.conf": true, "layout.conf": false} {
		got, err := checkMangoWCInclude(name)
		if err != nil {
			t.Fatal(err)
		}
		if got.Included != want {
			t.Errorf("%s included = %v, want %v", name, got.Included, want)
		}
	}
}

func TestCheckMangoWCIncludeFollowsMangoVars(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".config", "mango")
	writeConfigFile(t, filepath.Join(dir, "config.toml"), `[env]
source = "./dms/cursor.conf"
[var]
dms = "./dms"
[global]
source = ["./vars.conf", "$dms/${name}.conf"]
`)
	writeConfigFile(t, filepath.Join(dir, "vars.conf"), "var=name,binds\n")

	for name, want := range map[string]bool{"binds.conf": true, "cursor.conf": false} {
		got, err := checkMangoWCInclude(name)
		if err != nil {
			t.Fatal(err)
		}
		if got.Included != want {
			t.Errorf("%s included = %v, want %v", name, got.Included, want)
		}
	}
}

func TestMangoMonitorRulesReadsConfigToml(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	writeConfigFile(t, path, `[[rule.monitor_rule]]
name = "^DP-1$"
width = 2560
hdr = true
icc = "/home/u/display.icc"
[[rule.monitor_rule]]
name = "bad\n"
[bind.default]
"SUPER+m" = "spawn,monitor_rule=x"
`)
	got := strings.Join(mangoMonitorRules(filepath.Dir(path)), "\n")
	if want := "monitor_rule=name:^DP-1$,width:2560,hdr:1,icc:/home/u/display.icc"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestMangoMonitorRulesFollowSources(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, filepath.Join(dir, "config.toml"), `[global]
source = ["./vars.conf", "./dms/outputs.conf"]
[[rule.monitor_rule]]
name = "$monitor"
hdr = true
icc = "$profile"
`)
	writeConfigFile(t, filepath.Join(dir, "vars.conf"), "var=monitor,^DP-1$\nvar=profile,/home/u/display.icc\n")
	writeConfigFile(t, filepath.Join(dir, "dms", "outputs.conf"), "monitor_rule=name:^HDMI-A-1$,width:1920\n")

	got := strings.Join(mangoMonitorRules(dir), "\n")
	if want := "monitor_rule=name:^HDMI-A-1$,width:1920\nmonitor_rule=name:^DP-1$,hdr:1,icc:/home/u/display.icc"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}
