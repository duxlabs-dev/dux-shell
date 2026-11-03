package luaconfig

import (
	"os"
	"path/filepath"
	"testing"
)

func TestModuleToRelPath(t *testing.T) {
	tests := map[string]string{
		"dms.binds":       filepath.Join("dms", "binds.lua"),
		"dms/binds-user":  filepath.Join("dms", "binds-user.lua"),
		" awesome.binds ": filepath.Join("awesome", "binds.lua"),
	}

	for input, want := range tests {
		if got := ModuleToRelPath(input); got != want {
			t.Fatalf("ModuleToRelPath(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestRequiresSkipsComments(t *testing.T) {
	if modules := Requires(`-- require("dms.binds")`); len(modules) != 0 {
		t.Fatalf("expected commented require to be ignored, got %#v", modules)
	}

	modules := Requires(`print("-- not a comment") require("dms.binds") -- require("ignored")`)
	if len(modules) != 1 || modules[0] != "dms.binds" {
		t.Fatalf("unexpected modules: %#v", modules)
	}
}

func TestRequiresTargetRecurses(t *testing.T) {
	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(dmsDir, "windowrules.lua")
	if err := os.WriteFile(filepath.Join(tmpDir, "hyprland.lua"), []byte(`require("dms.extra")`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dmsDir, "extra.lua"), []byte(`require("dms.windowrules")`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte(`-- rules`), 0o644); err != nil {
		t.Fatal(err)
	}

	if !RequiresTarget(filepath.Join(tmpDir, "hyprland.lua"), target, make(map[string]bool)) {
		t.Fatal("expected recursive require lookup to find target")
	}
}
