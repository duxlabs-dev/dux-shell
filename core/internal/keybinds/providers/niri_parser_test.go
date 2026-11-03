package providers

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestNiriParseModKey(t *testing.T) {
	config := `input {
    mod-key "Alt"
}
binds {
    Mod+T { spawn "kitty"; }
}
`
	tmpDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(tmpDir, "config.kdl"), []byte(config), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}
	if result.ModKey != "Alt" {
		t.Errorf("ModKey = %q, want %q", result.ModKey, "Alt")
	}
}

func TestNiriParse_NoSpaceBeforeBrace(t *testing.T) {
	config := `recent-windows {
    binds {
        Alt+Tab         { next-window scope="output"; }
        Alt+Shift+Tab   { previous-window scope="output"; }
        Alt+grave       { next-window filter="app-id"; }
        Alt+Shift+grave { previous-window filter="app-id"; }
        Alt+Escape      { next-window scope="all"; }
        Alt+Shift+Escape{ previous-window scope="all"; }
    }
}
`
	tmpDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(tmpDir, "config.kdl"), []byte(config), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed on valid niri config: %v", err)
	}

	var found *NiriKeyBinding
	for i := range result.Section.Keybinds {
		kb := &result.Section.Keybinds[i]
		if kb.Key == "Escape" && slices.Contains(kb.Mods, "Alt") && slices.Contains(kb.Mods, "Shift") {
			found = kb
			break
		}
	}
	if found == nil {
		t.Fatal("Alt+Shift+Escape bind missing — '{' without preceding space was not handled")
	}
	if found.Action != "previous-window" {
		t.Errorf("Action = %q, want %q", found.Action, "previous-window")
	}
}

func TestNormalizeKDLBraces(t *testing.T) {
	tests := []struct {
		name string
		in   string
		out  string
	}{
		{"already spaced", "node { child }\n", "node { child }\n"},
		{"missing space", "node{ child }\n", "node { child }\n"},
		{"niri keybind", "Alt+Shift+Escape{ previous-window; }", "Alt+Shift+Escape { previous-window; }"},
		{"brace inside string", `node "a{b" { child }`, `node "a{b" { child }`},
		{"brace in line comment", "// foo{bar\nnode { }", "// foo{bar\nnode { }"},
		{"brace in block comment", "/* foo{bar */ node{ }", "/* foo{bar */ node { }"},
		{"escaped quote in string", `node "a\"b{c" { }`, `node "a\"b{c" { }`},
		{"leading brace", "{ child }", "{ child }"},
		{"nested missing space", "a{b{ c }}", "a {b { c }}"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := normalizeKDLBraces(tc.in)
			if got != tc.out {
				t.Errorf("normalizeKDLBraces(%q) = %q, want %q", tc.in, got, tc.out)
			}
		})
	}
}

func TestQuoteLeadingUnderscoreIdents(t *testing.T) {
	tests := []struct {
		name string
		in   string
		out  string
	}{
		{"leading underscore node", `_JAVA_AWT_WM_NONREPARENTING "1"`, `"_JAVA_AWT_WM_NONREPARENTING" "1"`},
		{"mid underscore untouched", `XDG_CURRENT_DESKTOP "niri"`, `XDG_CURRENT_DESKTOP "niri"`},
		{"indented node", "environment {\n  _FOO \"1\"\n}", "environment {\n  \"_FOO\" \"1\"\n}"},
		{"underscore in string", `spawn "_not_a_node"`, `spawn "_not_a_node"`},
		{"underscore in line comment", "// _comment\n_FOO \"1\"", "// _comment\n\"_FOO\" \"1\""},
		{"underscore in block comment", "/* _x */ _FOO \"1\"", "/* _x */ \"_FOO\" \"1\""},
		{"block comment abuts node", `/* x */_FOO "1"`, `/* x */"_FOO" "1"`},
		{"slashdash before node", `/-_FOO "1"`, `/-"_FOO" "1"`},
		{"node after closing paren", "node (u8)_v", `node (u8)"_v"`},
		{"node before brace without space", "_FOO{ }", `"_FOO"{ }`},
		{"lone underscore", `_ "x"`, `"_" "x"`},
		{"property value", "node key=_val", `node key="_val"`},
		{"no underscores", "node child", "node child"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := quoteLeadingUnderscoreIdents(tc.in)
			if got != tc.out {
				t.Errorf("quoteLeadingUnderscoreIdents(%q) = %q, want %q", tc.in, got, tc.out)
			}
		})
	}
}

func TestNiriParseLeadingUnderscoreEnvironment(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")

	// A leading-underscore environment node (a common Java/tiling-WM fix) must
	// not abort parsing of the rest of the config — keybinds still have to load.
	content := `environment {
    XDG_CURRENT_DESKTOP "niri"
    _JAVA_AWT_WM_NONREPARENTING "1"
}
binds {
    Mod+Q { close-window; }
    Mod+KP_Home { focus-workspace 1; }
}
`
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed on config with leading-underscore env node: %v", err)
	}

	if len(result.Section.Keybinds) != 2 {
		t.Errorf("Expected 2 keybinds, got %d", len(result.Section.Keybinds))
	}

	foundClose := false
	for _, kb := range result.Section.Keybinds {
		if kb.Action == "close-window" {
			foundClose = true
		}
	}
	if !foundClose {
		t.Error("close-window keybind not found — leading-underscore env node broke parsing")
	}
}

func TestNiriParseSlashdashLeadingUnderscore(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")

	// A slashdashed leading-underscore node must not abort parsing either.
	content := `environment {
    /-_JAVA_AWT_WM_NONREPARENTING "1"
}
binds {
    Mod+Q { close-window; }
}
`
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed on config with slashdashed leading-underscore node: %v", err)
	}

	if len(result.Section.Keybinds) != 1 {
		t.Errorf("Expected 1 keybind, got %d", len(result.Section.Keybinds))
	}
}

func TestNiriParseKeyCombo(t *testing.T) {
	tests := []struct {
		combo        string
		expectedMods []string
		expectedKey  string
	}{
		{"Mod+Q", []string{"Mod"}, "Q"},
		{"Print", nil, "Print"},
		{"Mod+Shift+Ctrl+H", []string{"Mod", "Shift", "Ctrl"}, "H"},
	}

	parser := NewNiriParser("")
	for _, tt := range tests {
		t.Run(tt.combo, func(t *testing.T) {
			mods, key := parser.parseKeyCombo(tt.combo)

			if len(mods) != len(tt.expectedMods) {
				t.Errorf("Mods length = %d, want %d", len(mods), len(tt.expectedMods))
			} else {
				for i := range mods {
					if mods[i] != tt.expectedMods[i] {
						t.Errorf("Mods[%d] = %q, want %q", i, mods[i], tt.expectedMods[i])
					}
				}
			}

			if key != tt.expectedKey {
				t.Errorf("Key = %q, want %q", key, tt.expectedKey)
			}
		})
	}
}

func TestNiriParseBasicBinds(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")

	content := `binds {
    Mod+Q { close-window; }
    Mod+F { fullscreen-window; }
    Mod+T hotkey-overlay-title="Open Terminal" { spawn "kitty"; }
}
`
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}

	if len(result.Section.Keybinds) != 3 {
		t.Errorf("Expected 3 keybinds, got %d", len(result.Section.Keybinds))
	}

	foundClose := false
	foundFullscreen := false
	foundTerminal := false

	for _, kb := range result.Section.Keybinds {
		switch kb.Action {
		case "close-window":
			foundClose = true
			if kb.Key != "Q" || len(kb.Mods) != 1 || kb.Mods[0] != "Mod" {
				t.Errorf("close-window keybind mismatch: %+v", kb)
			}
		case "fullscreen-window":
			foundFullscreen = true
		case "spawn":
			foundTerminal = true
			if kb.Description != "Open Terminal" {
				t.Errorf("spawn description = %q, want %q", kb.Description, "Open Terminal")
			}
			if len(kb.Args) != 1 || kb.Args[0] != "kitty" {
				t.Errorf("spawn args = %v, want [kitty]", kb.Args)
			}
		}
	}

	if !foundClose {
		t.Error("close-window keybind not found")
	}
	if !foundFullscreen {
		t.Error("fullscreen-window keybind not found")
	}
	if !foundTerminal {
		t.Error("spawn keybind not found")
	}
}

func TestNiriParseInclude(t *testing.T) {
	tmpDir := t.TempDir()
	subDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(subDir, 0o755); err != nil {
		t.Fatalf("Failed to create subdir: %v", err)
	}

	mainConfig := filepath.Join(tmpDir, "config.kdl")
	includeConfig := filepath.Join(subDir, "binds.kdl")

	mainContent := `binds {
    Mod+Q { close-window; }
}
include "dms/binds.kdl"
`
	includeContent := `binds {
    Mod+T hotkey-overlay-title="Terminal" { spawn "kitty"; }
}
`

	if err := os.WriteFile(mainConfig, []byte(mainContent), 0o644); err != nil {
		t.Fatalf("Failed to write main config: %v", err)
	}
	if err := os.WriteFile(includeConfig, []byte(includeContent), 0o644); err != nil {
		t.Fatalf("Failed to write include config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}

	if len(result.Section.Keybinds) != 2 {
		t.Errorf("Expected 2 keybinds (1 main + 1 include), got %d", len(result.Section.Keybinds))
	}
}

func TestNiriParseCircularInclude(t *testing.T) {
	tmpDir := t.TempDir()

	mainConfig := filepath.Join(tmpDir, "config.kdl")
	otherConfig := filepath.Join(tmpDir, "other.kdl")

	mainContent := `binds {
    Mod+Q { close-window; }
}
include "other.kdl"
`
	otherContent := `binds {
    Mod+T { spawn "kitty"; }
}
include "config.kdl"
`

	if err := os.WriteFile(mainConfig, []byte(mainContent), 0o644); err != nil {
		t.Fatalf("Failed to write main config: %v", err)
	}
	if err := os.WriteFile(otherConfig, []byte(otherContent), 0o644); err != nil {
		t.Fatalf("Failed to write other config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed (should handle circular includes): %v", err)
	}

	if len(result.Section.Keybinds) != 2 {
		t.Errorf("Expected 2 keybinds (circular include handled), got %d", len(result.Section.Keybinds))
	}
}

func TestNiriParseMissingInclude(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")

	content := `binds {
    Mod+Q { close-window; }
}
include "nonexistent/file.kdl"
`
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed (should skip missing include): %v", err)
	}

	if len(result.Section.Keybinds) != 1 {
		t.Errorf("Expected 1 keybind (missing include skipped), got %d", len(result.Section.Keybinds))
	}
}

func TestNiriParseErrors(t *testing.T) {
	tests := []struct {
		name string
		path string
	}{
		{
			name: "nonexistent_directory",
			path: "/nonexistent/path/that/does/not/exist",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseNiriKeys(tt.path)
			if err == nil {
				t.Error("Expected error, got nil")
			}
		})
	}
}

func TestNiriBindOverrideBehavior(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")

	content := `binds {
    Mod+T hotkey-overlay-title="First" { spawn "first"; }
    Mod+Q { close-window; }
    Mod+T hotkey-overlay-title="Second" { spawn "second"; }
    Mod+F { fullscreen-window; }
    Mod+T hotkey-overlay-title="Third" { spawn "third"; }
}
`
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}

	if len(result.Section.Keybinds) != 3 {
		t.Fatalf("Expected 3 unique keybinds, got %d", len(result.Section.Keybinds))
	}

	var modT *NiriKeyBinding
	for i := range result.Section.Keybinds {
		kb := &result.Section.Keybinds[i]
		if len(kb.Mods) == 1 && kb.Mods[0] == "Mod" && kb.Key == "T" {
			modT = kb
			break
		}
	}

	if modT == nil {
		t.Fatal("Mod+T keybind not found")
	}

	if modT.Description != "Third" {
		t.Errorf("Mod+T description = %q, want 'Third' (last definition wins)", modT.Description)
	}

	if len(modT.Args) != 1 || modT.Args[0] != "third" {
		t.Errorf("Mod+T args = %v, want [third] (last definition wins)", modT.Args)
	}
}

func TestNiriBindOverrideWithIncludes(t *testing.T) {
	tmpDir := t.TempDir()
	subDir := filepath.Join(tmpDir, "custom")
	if err := os.MkdirAll(subDir, 0o755); err != nil {
		t.Fatalf("Failed to create subdir: %v", err)
	}

	mainConfig := filepath.Join(tmpDir, "config.kdl")
	includeConfig := filepath.Join(subDir, "overrides.kdl")

	mainContent := `binds {
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+T hotkey-overlay-title="Default Terminal" { spawn "xterm"; }
}
include "custom/overrides.kdl"
binds {
    Mod+3 { focus-workspace 3; }
}
`
	includeContent := `binds {
    Mod+T hotkey-overlay-title="Custom Terminal" { spawn "kitty"; }
    Mod+2 { focus-workspace 22; }
}
`

	if err := os.WriteFile(mainConfig, []byte(mainContent), 0o644); err != nil {
		t.Fatalf("Failed to write main config: %v", err)
	}
	if err := os.WriteFile(includeConfig, []byte(includeContent), 0o644); err != nil {
		t.Fatalf("Failed to write include config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}

	if len(result.Section.Keybinds) != 4 {
		t.Errorf("Expected 4 unique keybinds, got %d", len(result.Section.Keybinds))
	}

	bindMap := make(map[string]*NiriKeyBinding)
	for i := range result.Section.Keybinds {
		kb := &result.Section.Keybinds[i]
		var key strings.Builder
		for _, m := range kb.Mods {
			key.WriteString(m + "+")
		}
		key.WriteString(kb.Key)
		bindMap[key.String()] = kb
	}

	if kb, ok := bindMap["Mod+T"]; ok {
		if kb.Description != "Custom Terminal" {
			t.Errorf("Mod+T should be overridden by include, got description %q", kb.Description)
		}
	} else {
		t.Error("Mod+T not found")
	}

	if kb, ok := bindMap["Mod+2"]; ok {
		if len(kb.Args) != 1 || kb.Args[0] != "22" {
			t.Errorf("Mod+2 should be overridden by include with workspace 22, got args %v", kb.Args)
		}
	} else {
		t.Error("Mod+2 not found")
	}

	if _, ok := bindMap["Mod+1"]; !ok {
		t.Error("Mod+1 should exist (not overridden)")
	}

	if _, ok := bindMap["Mod+3"]; !ok {
		t.Error("Mod+3 should exist (added after include)")
	}
}

func TestNiriKeyIdentityIsCaseInsensitive(t *testing.T) {
	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatalf("Failed to create dms dir: %v", err)
	}

	config := `binds {
    Alt+Space hotkey-overlay-title="Spotlight Bar" { spawn "dms" "ipc" "call" "spotlight-bar" "toggle"; }
}
include "dms/binds.kdl"
`
	if err := os.WriteFile(filepath.Join(tmpDir, "config.kdl"), []byte(config), 0o644); err != nil {
		t.Fatalf("Failed to write config: %v", err)
	}
	include := `binds {
    Alt+space hotkey-overlay-title="Default Launcher" { spawn "dms" "ipc" "call" "spotlight" "toggle"; }
}
`
	if err := os.WriteFile(filepath.Join(dmsDir, "binds.kdl"), []byte(include), 0o644); err != nil {
		t.Fatalf("Failed to write binds include: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}

	var altSpaceBinds []NiriKeyBinding
	parser := NewNiriParser("")
	for _, kb := range result.Section.Keybinds {
		if normalizeNiriBindKey(parser.formatBindKey(&kb)) == "alt+space" {
			altSpaceBinds = append(altSpaceBinds, kb)
		}
	}

	if len(altSpaceBinds) != 1 {
		t.Fatalf("Expected one Alt+Space identity, got %d", len(altSpaceBinds))
	}
	if got := altSpaceBinds[0].Args; len(got) < 5 || got[3] != "spotlight" || got[4] != "toggle" {
		t.Fatalf("Expected later DMS include to win with spotlight toggle, got action=%s args=%v", altSpaceBinds[0].Action, got)
	}
}

func TestNiriParseMultipleArgs(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")

	content := `binds {
    Mod+Space hotkey-overlay-title="Application Launcher" {
        spawn "dms" "ipc" "call" "spotlight" "toggle";
    }
}
`
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}

	if len(result.Section.Keybinds) != 1 {
		t.Fatalf("Expected 1 keybind, got %d", len(result.Section.Keybinds))
	}

	kb := result.Section.Keybinds[0]
	if len(kb.Args) != 5 {
		t.Errorf("Expected 5 args, got %d: %v", len(kb.Args), kb.Args)
	}

	expectedArgs := []string{"dms", "ipc", "call", "spotlight", "toggle"}
	for i, arg := range expectedArgs {
		if i < len(kb.Args) && kb.Args[i] != arg {
			t.Errorf("Args[%d] = %q, want %q", i, kb.Args[i], arg)
		}
	}
}

func TestNiriParseNumericWorkspaceBinds(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")

	content := `binds {
    Mod+1 hotkey-overlay-title="Focus Workspace 1" { focus-workspace 1; }
    Mod+2 hotkey-overlay-title="Focus Workspace 2" { focus-workspace 2; }
    Mod+0 hotkey-overlay-title="Focus Workspace 10" { focus-workspace 10; }
    Mod+Shift+1 hotkey-overlay-title="Move to Workspace 1" { move-column-to-workspace 1; }
}
`
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}

	if len(result.Section.Keybinds) != 4 {
		t.Errorf("Expected 4 keybinds, got %d", len(result.Section.Keybinds))
	}

	for _, kb := range result.Section.Keybinds {
		switch kb.Key {
		case "1":
			if len(kb.Mods) == 1 && kb.Mods[0] == "Mod" {
				if kb.Action != "focus-workspace" || len(kb.Args) != 1 || kb.Args[0] != "1" {
					t.Errorf("Mod+1 action/args mismatch: %+v", kb)
				}
				if kb.Description != "Focus Workspace 1" {
					t.Errorf("Mod+1 description = %q, want 'Focus Workspace 1'", kb.Description)
				}
			}
		case "0":
			if kb.Action != "focus-workspace" || len(kb.Args) != 1 || kb.Args[0] != "10" {
				t.Errorf("Mod+0 action/args mismatch: %+v", kb)
			}
		}
	}
}

func TestNiriParseQuotedStringArgs(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")

	content := `binds {
    Super+Minus hotkey-overlay-title="Adjust Column Width -10%" { set-column-width "-10%"; }
    Super+Equal hotkey-overlay-title="Adjust Column Width +10%" { set-column-width "+10%"; }
    Super+Shift+Minus hotkey-overlay-title="Adjust Window Height -10%" { set-window-height "-10%"; }
}
`
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}

	if len(result.Section.Keybinds) != 3 {
		t.Errorf("Expected 3 keybinds, got %d", len(result.Section.Keybinds))
	}

	for _, kb := range result.Section.Keybinds {
		if kb.Action == "set-column-width" {
			if len(kb.Args) != 1 {
				t.Errorf("set-column-width should have 1 arg, got %d", len(kb.Args))
				continue
			}
			if kb.Args[0] != "-10%" && kb.Args[0] != "+10%" {
				t.Errorf("set-column-width arg = %q, want -10%% or +10%%", kb.Args[0])
			}
		}
	}
}

func TestNiriParseActionWithProperties(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")

	content := `binds {
    Mod+Shift+1 hotkey-overlay-title="Move to Workspace 1" { move-column-to-workspace 1 focus=false; }
    Mod+Shift+2 hotkey-overlay-title="Move to Workspace 2" { move-column-to-workspace 2 focus=false; }
    Alt+Tab { next-window scope="output"; }
    Alt+grave { next-window filter="app-id"; }
}
`
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}

	if len(result.Section.Keybinds) != 4 {
		t.Errorf("Expected 4 keybinds, got %d", len(result.Section.Keybinds))
	}

	for _, kb := range result.Section.Keybinds {
		switch kb.Action {
		case "move-column-to-workspace":
			if len(kb.Args) != 2 {
				t.Errorf("move-column-to-workspace should have 2 args (index + focus), got %d", len(kb.Args))
			}
			hasIndex := false
			hasFocus := false
			for _, arg := range kb.Args {
				if arg == "1" || arg == "2" {
					hasIndex = true
				}
				if arg == "focus=false" {
					hasFocus = true
				}
			}
			if !hasIndex {
				t.Errorf("move-column-to-workspace missing index arg")
			}
			if !hasFocus {
				t.Errorf("move-column-to-workspace missing focus=false arg")
			}
		case "next-window":
			if kb.Key == "Tab" {
				if len(kb.Args) != 1 || kb.Args[0] != "scope=\"output\"" {
					t.Errorf("next-window Tab args = %v, want [scope=\"output\"]", kb.Args)
				}
			} else if kb.Key == "grave" {
				if len(kb.Args) != 1 || kb.Args[0] != "filter=\"app-id\"" {
					t.Errorf("next-window grave args = %v, want [filter=\"app-id\"]", kb.Args)
				}
			} else {
				t.Errorf("unexpected next-window key: %q", kb.Key)
			}
		}
	}
}

func TestNiriParseIncludeNestedDMSBinds(t *testing.T) {
	tmpDir := t.TempDir()
	subDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(subDir, 0o755); err != nil {
		t.Fatal(err)
	}

	files := map[string]string{
		filepath.Join(tmpDir, "config.kdl"): "include \"dms/dms.kdl\"\n",
		filepath.Join(subDir, "dms.kdl"):    "include \"binds.kdl\"\n",
		filepath.Join(subDir, "binds.kdl"):  "binds {\n    Mod+T { spawn \"kitty\"; }\n}\n",
	}
	for path, content := range files {
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}
	if !result.DMSBindsIncluded {
		t.Error("dms/binds.kdl included via dms/dms.kdl not detected")
	}
	if len(result.Section.Keybinds) != 1 {
		t.Errorf("expected 1 keybind from the nested include, got %d", len(result.Section.Keybinds))
	}
}
