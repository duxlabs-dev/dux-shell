package providers

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
)

func TestMangoWCCategorizeByCommand(t *testing.T) {
	tests := []struct {
		command  string
		expected string
	}{
		{"view", "Tags"},
		{"tag", "Tags"},
		{"tagmon", "Monitor"},
		{"focusstack", "Window"},
		{"toggleoverview", "Overview"},
		{"toggle_scratchpad", "Scratchpad"},
		{"switch_layout", "Layout"},
		{"set_proportion", "Layout"},
		{"incgaps", "Gaps"},
		{"spawn", "Execute"},
		{"quit", "System"},
		{"unknown_command", "Other"},
	}

	provider := NewMangoWCProvider("")
	for _, tt := range tests {
		t.Run(tt.command, func(t *testing.T) {
			result := provider.categorizeByCommand(tt.command)
			if result != tt.expected {
				t.Errorf("categorizeByCommand(%q) = %q, want %q", tt.command, result, tt.expected)
			}
		})
	}
}

func TestMangoWCConvertKeybind(t *testing.T) {
	tests := []struct {
		name     string
		keybind  *MangoWCKeyBinding
		wantKey  string
		wantDesc string
	}{
		{
			name: "with_comment",
			keybind: &MangoWCKeyBinding{
				Mods:    []string{"ALT"},
				Key:     "t",
				Command: "spawn",
				Params:  "kitty",
				Comment: "Open terminal",
			},
			wantKey:  "ALT+t",
			wantDesc: "Open terminal",
		},
		{
			name: "without_comment",
			keybind: &MangoWCKeyBinding{
				Mods:    []string{"SUPER"},
				Key:     "r",
				Command: "reload_config",
				Params:  "",
				Comment: "",
			},
			wantKey:  "SUPER+r",
			wantDesc: "reload_config",
		},
		{
			name: "with_params_no_comment",
			keybind: &MangoWCKeyBinding{
				Mods:    []string{"CTRL"},
				Key:     "1",
				Command: "view",
				Params:  "1,0",
				Comment: "",
			},
			wantKey:  "CTRL+1",
			wantDesc: "view 1,0",
		},
	}

	provider := NewMangoWCProvider("")
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := provider.convertKeybind(tt.keybind, nil)
			if result.Key != tt.wantKey {
				t.Errorf("convertKeybind().Key = %q, want %q", result.Key, tt.wantKey)
			}
			if result.Description != tt.wantDesc {
				t.Errorf("convertKeybind().Description = %q, want %q", result.Description, tt.wantDesc)
			}
		})
	}
}

func TestMangoWCGetCheatSheet(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.conf")

	content := `# MangoWC Configuration
blur=0

# Key Bindings
bind=SUPER,r,reload_config
bind=Alt,t,spawn,kitty # Terminal
bind=ALT,q,killclient,

# Window management
bind=ALT,Left,focusdir,left
bind=ALT,Right,focusdir,right
bind=SUPER+SHIFT,Up,exchange_client,up

# Tags
bind=Ctrl,1,view,1,0
bind=Ctrl,2,view,2,0
bind=Alt,1,tag,1,0

# Layout
bind=SUPER,n,switch_layout

# Gaps
bind=ALT+SHIFT,X,incgaps,1
`

	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	provider := NewMangoWCProvider(tmpDir)
	sheet, err := provider.GetCheatSheet()
	if err != nil {
		t.Fatalf("GetCheatSheet failed: %v", err)
	}

	categories := []string{"System", "Execute", "Window", "Tags", "Layout", "Gaps"}
	for _, category := range categories {
		if _, exists := sheet.Binds[category]; !exists {
			t.Errorf("Expected category %q to exist", category)
		}
	}

	if len(sheet.Binds["System"]) < 1 {
		t.Error("Expected at least 1 System keybind")
	}
	if len(sheet.Binds["Execute"]) < 1 {
		t.Error("Expected at least 1 Execute keybind")
	}
	if len(sheet.Binds["Window"]) < 3 {
		t.Error("Expected at least 3 Window keybinds")
	}
	if len(sheet.Binds["Tags"]) < 3 {
		t.Error("Expected at least 3 Tags keybinds")
	}
}

func TestMangoWCSetBindPreservesStockCommentsAndGestures(t *testing.T) {
	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatalf("failed to create dms dir: %v", err)
	}
	bindsPath := filepath.Join(dmsDir, "binds.conf")
	stock := strings.ReplaceAll(config.MangoBindsConfig, "{{TERMINAL_COMMAND}}", "ghostty")
	if err := os.WriteFile(bindsPath, []byte(stock), 0o644); err != nil {
		t.Fatalf("failed to write stock binds: %v", err)
	}

	provider := NewMangoWCProvider(tmpDir)
	if err := provider.SetBind("SUPER+SHIFT+S", "spawn dms screenshot", "Screenshot: Interactive", nil); err != nil {
		t.Fatalf("SetBind failed: %v", err)
	}

	contentBytes, err := os.ReadFile(bindsPath)
	if err != nil {
		t.Fatalf("failed to read binds: %v", err)
	}
	content := string(contentBytes)

	for _, want := range []string{
		"# === Application Launchers ===",
		"# === Touchpad Gestures ===",
		"gesturebind=none,right,3,viewtoleft_have_client",
		"gesturebind=none,left,3,viewtoright_have_client",
		"# Screenshot: Interactive\nbind=SUPER+SHIFT,S,spawn,dms screenshot",
	} {
		if !strings.Contains(content, want) {
			t.Fatalf("expected saved binds to contain %q\ncontent:\n%s", want, content)
		}
	}
	if strings.Contains(content, "# === Audio Controls ===\n# === Audio Controls ===") {
		t.Fatalf("section header should not be duplicated as a bind description\ncontent:\n%s", content)
	}
}

func TestMangoWCSetBindRestoresScaffoldForStrippedFile(t *testing.T) {
	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatalf("failed to create dms dir: %v", err)
	}
	bindsPath := filepath.Join(dmsDir, "binds.conf")
	stripped := `bind=SUPER,t,spawn,ghostty
bind=SUPER,Return,spawn,ghostty
bind=SUPER,space,spawn,dms ipc call spotlight toggle
bind=SUPER,v,spawn,dms ipc call clipboard toggle
bind=SUPER,q,killclient
bind=SUPER,Left,focusdir,left
bind=SUPER,Right,focusdir,right
bind=SUPER,Up,focusdir,up
bind=SUPER,Down,focusdir,down
bind=SUPER,1,view,1
bind=SUPER,2,view,2
bind=SUPER,3,view,3
`
	if err := os.WriteFile(bindsPath, []byte(stripped), 0o644); err != nil {
		t.Fatalf("failed to write stripped binds: %v", err)
	}

	provider := NewMangoWCProvider(tmpDir)
	if err := provider.SetBind("SUPER+SHIFT+S", "spawn dms screenshot", "Screenshot: Interactive", nil); err != nil {
		t.Fatalf("SetBind failed: %v", err)
	}

	contentBytes, err := os.ReadFile(bindsPath)
	if err != nil {
		t.Fatalf("failed to read binds: %v", err)
	}
	content := string(contentBytes)

	for _, want := range []string{
		"# DMS default keybinds (MangoWM)",
		"# === Touchpad Gestures ===",
		"gesturebind=none,right,3,viewtoleft_have_client",
		"bind=SUPER,H,focusdir,left",
		"bind=SUPER,J,focusdir,down",
		"bind=SUPER,K,focusdir,up",
		"bind=SUPER,L,focusdir,right",
		"# === Custom Keybinds ===",
		"# Screenshot: Interactive\nbind=SUPER+SHIFT,S,spawn,dms screenshot",
		"bind=SUPER,t,spawn,ghostty",
	} {
		if !strings.Contains(content, want) {
			t.Fatalf("expected restored binds to contain %q\ncontent:\n%s", want, content)
		}
	}
	if strings.Contains(content, "{{TERMINAL_COMMAND}}") {
		t.Fatalf("terminal placeholder should have been resolved\ncontent:\n%s", content)
	}
}

func TestMangoWCSetBindTranslatesScrollWheelToAxisBind(t *testing.T) {
	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatalf("failed to create dms dir: %v", err)
	}
	bindsPath := filepath.Join(dmsDir, "binds.conf")
	seed := "# === Custom Keybinds ===\nbind=SUPER,t,spawn,ghostty\ngesturebind=none,left,3,focusdir,left\n"
	if err := os.WriteFile(bindsPath, []byte(seed), 0o644); err != nil {
		t.Fatalf("failed to write seed binds: %v", err)
	}

	provider := NewMangoWCProvider(tmpDir)
	if err := provider.SetBind("SUPER+WheelScrollDown", "spawn dms ipc call test", "Scroll down", nil); err != nil {
		t.Fatalf("SetBind failed: %v", err)
	}

	content := readFile(t, bindsPath)
	if !strings.Contains(content, "axisbind=SUPER,DOWN,spawn,dms ipc call test") {
		t.Fatalf("expected scroll bind written as axisbind direction, got:\n%s", content)
	}
	if strings.Contains(content, "WheelScroll") {
		t.Fatalf("expected no raw niri scroll keysym in mango output, got:\n%s", content)
	}

	if err := provider.SetBind("SUPER+WheelScrollDown", "spawn dms ipc call test2", "Scroll down", nil); err != nil {
		t.Fatalf("SetBind failed: %v", err)
	}
	content = readFile(t, bindsPath)
	if strings.Count(content, "axisbind=SUPER,DOWN,") != 1 {
		t.Fatalf("expected exactly one axisbind after re-save, got:\n%s", content)
	}
}

func TestMangoWCRemoveBindPreservesNonBindLines(t *testing.T) {
	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatalf("failed to create dms dir: %v", err)
	}
	bindsPath := filepath.Join(dmsDir, "binds.conf")
	stock := strings.ReplaceAll(config.MangoBindsConfig, "{{TERMINAL_COMMAND}}", "ghostty")
	if err := os.WriteFile(bindsPath, []byte(stock), 0o644); err != nil {
		t.Fatalf("failed to write stock binds: %v", err)
	}

	provider := NewMangoWCProvider(tmpDir)
	if err := provider.RemoveBind("SUPER+Tab"); err != nil {
		t.Fatalf("RemoveBind failed: %v", err)
	}

	contentBytes, err := os.ReadFile(bindsPath)
	if err != nil {
		t.Fatalf("failed to read binds: %v", err)
	}
	content := string(contentBytes)

	if strings.Contains(content, "bind=SUPER,Tab,focusstack,next") {
		t.Fatalf("removed bind should be absent\ncontent:\n%s", content)
	}
	if strings.Contains(content, "# Focus Next Window") {
		t.Fatalf("removed bind description should be absent\ncontent:\n%s", content)
	}
	for _, want := range []string{
		"# === Focus Navigation ===",
		"# === Touchpad Gestures ===",
		"gesturebind=none,down,4,toggleoverview",
	} {
		if !strings.Contains(content, want) {
			t.Fatalf("expected non-bind line %q to be preserved\ncontent:\n%s", want, content)
		}
	}
}

func TestMangoWCCheatSheetFirstBindWins(t *testing.T) {
	tmpDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmpDir, "dms"), 0o755); err != nil {
		t.Fatal(err)
	}
	main := "bind=SUPER,q,killclient\nsource=./dms/binds.conf\nbind=SUPER,w,spawn,late\n"
	dms := "bind=SUPER,q,spawn,dmsq\nbind=SUPER,w,spawn,dmsw\n"
	if err := os.WriteFile(filepath.Join(tmpDir, "config.conf"), []byte(main), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "dms", "binds.conf"), []byte(dms), 0o644); err != nil {
		t.Fatal(err)
	}

	sheet, err := NewMangoWCProvider(tmpDir).GetCheatSheet()
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, binds := range sheet.Binds {
		for _, b := range binds {
			conflict := ""
			if b.Conflict != nil {
				conflict = " <- " + b.Conflict.Action
			}
			got[strings.ToLower(b.Key)] = b.Action + conflict
		}
	}
	if got["super+q"] != "spawn dmsq <- killclient" {
		t.Errorf("super+q = %q: the earlier config bind shadows the DMS one", got["super+q"])
	}
	if got["super+w"] != "spawn dmsw" {
		t.Errorf("super+w = %q: a config bind after the DMS one is ignored by Mango", got["super+w"])
	}
	if sheet.DMSStatus == nil || sheet.DMSStatus.OverriddenBy != 1 {
		t.Errorf("DMSStatus = %+v, want OverriddenBy 1", sheet.DMSStatus)
	}
}

func TestMangoWCSetBindEditsUserBindsInPlace(t *testing.T) {
	stock := "bind=SUPER,t,spawn,ghostty\nbind=SUPER,space,spawn,dms ipc call spotlight toggle\n"
	for i := 0; i < 10; i++ {
		stock += fmt.Sprintf("bind=SUPER,%d,view,%d\n", i, i)
	}
	for name, content := range map[string]string{
		"kept":      mangoconf.BindsKeptHeader + "\n" + stock,
		"moved":     mangoconf.BindsMovedHeader + "\n" + stock,
		"mousebind": stock + "mousebind=SUPER,btn_left,moveresize,curmove\n",
		"keymode":   stock + "keymode=resize\nbind=NONE,h,resizewin,-10,0\n",
	} {
		tmpDir := t.TempDir()
		bindsPath := filepath.Join(tmpDir, "dms", "binds.conf")
		if err := os.MkdirAll(filepath.Dir(bindsPath), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(bindsPath, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := NewMangoWCProvider(tmpDir).SetBind("SUPER+SHIFT+S", "spawn dms screenshot", "", nil); err != nil {
			t.Fatalf("%s: SetBind failed: %v", name, err)
		}
		got, _ := os.ReadFile(bindsPath)
		if strings.Contains(string(got), "# DMS default keybinds") || strings.Contains(string(got), "gesturebind=") {
			t.Fatalf("%s: user binds were rebuilt from the stock template:\n%s", name, got)
		}
		if !strings.HasPrefix(strings.ToLower(string(got)), strings.ToLower(content)) {
			t.Fatalf("%s: existing lines changed:\n%s", name, got)
		}
	}
}
