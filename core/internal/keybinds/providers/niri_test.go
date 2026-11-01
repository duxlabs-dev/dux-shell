package providers

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/keybinds"
)

func TestNiriProviderGetCheatSheet(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")

	content := `input {
    mod-key "Alt"
}
binds {
    Mod+Q { close-window; }
    Mod+F { fullscreen-window; }
    Mod+T hotkey-overlay-title="Open Terminal" { spawn "kitty"; }
    Mod+1 { focus-workspace 1; }
    Mod+Shift+1 { move-column-to-workspace 1; }
    Print { screenshot; }
    Mod+Shift+E { quit; }
}
`
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	niriNested = func() bool { return false }
	t.Cleanup(func() { niriNested = detectNiriNested })
	provider := NewNiriProvider(tmpDir)
	cheatSheet, err := provider.GetCheatSheet()
	if err != nil {
		t.Fatalf("GetCheatSheet failed: %v", err)
	}

	if cheatSheet.ModKey != "Alt" {
		t.Errorf("ModKey = %q, want %q", cheatSheet.ModKey, "Alt")
	}

	windowBinds := cheatSheet.Binds["Window"]
	if len(windowBinds) < 2 {
		t.Errorf("Expected at least 2 Window binds, got %d", len(windowBinds))
	}

	execBinds := cheatSheet.Binds["Execute"]
	if len(execBinds) < 1 {
		t.Errorf("Expected at least 1 Execute bind, got %d", len(execBinds))
	}

	workspaceBinds := cheatSheet.Binds["Workspace"]
	if len(workspaceBinds) < 2 {
		t.Errorf("Expected at least 2 Workspace binds, got %d", len(workspaceBinds))
	}

	screenshotBinds := cheatSheet.Binds["Screenshot"]
	if len(screenshotBinds) < 1 {
		t.Errorf("Expected at least 1 Screenshot bind, got %d", len(screenshotBinds))
	}

	systemBinds := cheatSheet.Binds["System"]
	if len(systemBinds) < 1 {
		t.Errorf("Expected at least 1 System bind, got %d", len(systemBinds))
	}
}

func TestNiriCategorizeByAction(t *testing.T) {
	provider := NewNiriProvider("")

	tests := []struct {
		action   string
		expected string
	}{
		{"move-column-to-workspace", "Workspace"},
		{"focus-monitor-left", "Monitor"},
		{"close-window", "Window"},
		{"spawn", "Execute"},
		{"power-off-monitors", "System"},
		{"toggle-touchpad", "System"},
		{"screenshot-window", "Screenshot"},
		{"toggle-overview", "Overview"},
		{"next-window", "Alt-Tab"},
		{"unknown-action", "Other"},
	}

	for _, tt := range tests {
		t.Run(tt.action, func(t *testing.T) {
			result := provider.categorizeByAction(tt.action)
			if result != tt.expected {
				t.Errorf("categorizeByAction(%q) = %q, want %q", tt.action, result, tt.expected)
			}
		})
	}
}

func TestNiriFormatRawAction(t *testing.T) {
	provider := NewNiriProvider("")

	tests := []struct {
		action   string
		args     []string
		expected string
	}{
		{"spawn", []string{"kitty"}, "spawn kitty"},
		{"spawn", []string{"dms", "ipc", "call", "brightness", "increment", "5", ""}, `spawn dms ipc call brightness increment 5 ""`},
		{"close-window", nil, "close-window"},
		{"set-column-width", []string{"+10%"}, "set-column-width +10%"},
		{"spawn", []string{"notify-send", "hello world"}, `spawn notify-send "hello world"`},
		{"spawn", []string{"sh", "-c", `grep "a b" C:\tmp\`}, `spawn sh -c "grep \"a b\" C:\\tmp\\"`},
		{"spawn", []string{"sh", "-c", "kitty"}, `spawn sh -c "kitty"`},
	}

	for _, tt := range tests {
		t.Run(tt.action, func(t *testing.T) {
			result := provider.formatRawAction(tt.action, tt.args)
			if result != tt.expected {
				t.Errorf("formatRawAction(%q, %v) = %q, want %q", tt.action, tt.args, result, tt.expected)
			}
		})
	}
}

func TestNiriGenerateBindsContent(t *testing.T) {
	provider := NewNiriProvider("")

	tests := []struct {
		name     string
		binds    map[string]*overrideBind
		expected string
	}{
		{
			name:     "empty binds",
			binds:    map[string]*overrideBind{},
			expected: "binds {}\n",
		},
		{
			name: "simple spawn bind",
			binds: map[string]*overrideBind{
				"Mod+T": {
					Key:         "Mod+T",
					Action:      "spawn kitty",
					Description: "Open Terminal",
				},
			},
			expected: `binds {
    Mod+T hotkey-overlay-title="Open Terminal" { spawn "kitty"; }
}
`,
		},
		{
			name: "spawn with multiple args",
			binds: map[string]*overrideBind{
				"Mod+Space": {
					Key:         "Mod+Space",
					Action:      `spawn "dms" "ipc" "call" "spotlight" "toggle"`,
					Description: "Application Launcher",
				},
			},
			expected: `binds {
    Mod+Space hotkey-overlay-title="Application Launcher" { spawn "dms" "ipc" "call" "spotlight" "toggle"; }
}
`,
		},
		{
			name: "spawn with equals arg",
			binds: map[string]*overrideBind{
				"Mod+B": {
					Key:    "Mod+B",
					Action: `spawn /opt/browser --profile-directory=Default`,
				},
			},
			expected: `binds {
    Mod+B { spawn "/opt/browser" "--profile-directory=Default"; }
}
`,
		},
		{
			name: "spawn shell command with quoted equals args",
			binds: map[string]*overrideBind{
				"Mod+C": {
					Key:    "Mod+C",
					Action: `spawn sh -c "chrome --profile-directory=Default --app=x"`,
				},
			},
			expected: `binds {
    Mod+C { spawn "sh" "-c" "chrome --profile-directory=Default --app=x"; }
}
`,
		},
		{
			name: "spawn env assignment stays arg",
			binds: map[string]*overrideBind{
				"Mod+E": {
					Key:    "Mod+E",
					Action: `spawn env FOO=bar mycmd`,
				},
			},
			expected: `binds {
    Mod+E { spawn "env" "FOO=bar" "mycmd"; }
}
`,
		},
		{
			name: "niri action property remains property",
			binds: map[string]*overrideBind{
				"Print": {
					Key:    "Print",
					Action: `screenshot show-pointer=false`,
				},
			},
			expected: `binds {
    Print { screenshot show-pointer=false; }
}
`,
		},
		{
			name: "bind with allow-when-locked",
			binds: map[string]*overrideBind{
				"XF86AudioMute": {
					Key:     "XF86AudioMute",
					Action:  `spawn "dms" "ipc" "call" "audio" "mute"`,
					Options: map[string]any{"allow-when-locked": true},
				},
			},
			expected: `binds {
    XF86AudioMute allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "mute"; }
}
`,
		},
		{
			name: "simple action without args",
			binds: map[string]*overrideBind{
				"Mod+Q": {
					Key:         "Mod+Q",
					Action:      "close-window",
					Description: "Close Window",
				},
			},
			expected: `binds {
    Mod+Q hotkey-overlay-title="Close Window" { close-window; }
}
`,
		},
		{
			name: "recent-windows action",
			binds: map[string]*overrideBind{
				"Alt+Tab": {
					Key:    "Alt+Tab",
					Action: "next-window",
				},
			},
			expected: `binds {
}

recent-windows {
    binds {
        Alt+Tab { next-window; }
    }
}
`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := provider.generateBindsContent(tt.binds)
			if result != tt.expected {
				t.Errorf("generateBindsContent() =\n%q\nwant:\n%q", result, tt.expected)
			}
		})
	}
}

func TestNiriEmptyArgsPreservation(t *testing.T) {
	provider := NewNiriProvider("")

	binds := map[string]*overrideBind{
		"XF86MonBrightnessUp": {
			Key:         "XF86MonBrightnessUp",
			Action:      `spawn dms ipc call brightness increment 5 ""`,
			Description: "Brightness Up",
		},
		"XF86MonBrightnessDown": {
			Key:         "XF86MonBrightnessDown",
			Action:      `spawn dms ipc call brightness decrement 5 ""`,
			Description: "Brightness Down",
		},
		"Super+Alt+Page_Up": {
			Key:         "Super+Alt+Page_Up",
			Action:      `spawn dms ipc call dash toggle ""`,
			Description: "Dashboard Toggle",
		},
	}

	content := provider.generateBindsContent(binds)

	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatalf("Failed to create dms directory: %v", err)
	}

	bindsFile := filepath.Join(dmsDir, "binds.kdl")
	if err := os.WriteFile(bindsFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write binds file: %v", err)
	}

	testProvider := NewNiriProvider(tmpDir)
	loadedBinds, err := testProvider.loadOverrideBinds()
	if err != nil {
		t.Fatalf("Failed to load binds: %v\nContent was:\n%s", err, content)
	}

	for key, expected := range binds {
		loaded, ok := loadedBinds[normalizeNiriBindKey(key)]
		if !ok {
			t.Errorf("Missing bind for key %s", key)
			continue
		}
		if loaded.Action != expected.Action {
			t.Errorf("Action mismatch for %s:\n  got:  %q\n  want: %q", key, loaded.Action, expected.Action)
		}
	}
}

func TestNiriGenerateBindsContentNumericArgs(t *testing.T) {
	provider := NewNiriProvider("")

	tests := []struct {
		name     string
		binds    map[string]*overrideBind
		expected string
	}{
		{
			name: "workspace with numeric arg",
			binds: map[string]*overrideBind{
				"Mod+1": {
					Key:         "Mod+1",
					Action:      "focus-workspace 1",
					Description: "Focus Workspace 1",
				},
			},
			expected: `binds {
    Mod+1 hotkey-overlay-title="Focus Workspace 1" { focus-workspace 1; }
}
`,
		},
		{
			name: "percentage string arg (should be quoted)",
			binds: map[string]*overrideBind{
				"Super+Minus": {
					Key:         "Super+Minus",
					Action:      `set-column-width "-10%"`,
					Description: "Adjust Column Width -10%",
				},
			},
			expected: `binds {
    Super+Minus hotkey-overlay-title="Adjust Column Width -10%" { set-column-width "-10%"; }
}
`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := provider.generateBindsContent(tt.binds)
			if result != tt.expected {
				t.Errorf("generateBindsContent() =\n%q\nwant:\n%q", result, tt.expected)
			}
		})
	}
}

func TestNiriGenerateActionWithUnquotedPercentArg(t *testing.T) {
	provider := NewNiriProvider("")

	binds := map[string]*overrideBind{
		"Super+Equal": {
			Key:         "Super+Equal",
			Action:      "set-window-height +10%",
			Description: "Adjust Window Height +10%",
		},
	}

	content := provider.generateBindsContent(binds)
	expected := `binds {
    Super+Equal hotkey-overlay-title="Adjust Window Height +10%" { set-window-height "+10%"; }
}
`
	if content != expected {
		t.Errorf("Content mismatch.\nGot:\n%s\nWant:\n%s", content, expected)
	}
}

func TestNiriGenerateSpawnWithNumericArgs(t *testing.T) {
	provider := NewNiriProvider("")

	binds := map[string]*overrideBind{
		"XF86AudioLowerVolume": {
			Key:     "XF86AudioLowerVolume",
			Action:  `spawn "dms" "ipc" "call" "audio" "decrement" "3"`,
			Options: map[string]any{"allow-when-locked": true},
		},
	}

	content := provider.generateBindsContent(binds)
	expected := `binds {
    XF86AudioLowerVolume allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "decrement" "3"; }
}
`
	if content != expected {
		t.Errorf("Content mismatch.\nGot:\n%s\nWant:\n%s", content, expected)
	}
}

func TestNiriGenerateSpawnNumericArgFromCLI(t *testing.T) {
	provider := NewNiriProvider("")

	binds := map[string]*overrideBind{
		"XF86AudioLowerVolume": {
			Key:     "XF86AudioLowerVolume",
			Action:  "spawn dms ipc call audio decrement 3",
			Options: map[string]any{"allow-when-locked": true},
		},
	}

	content := provider.generateBindsContent(binds)
	expected := `binds {
    XF86AudioLowerVolume allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "decrement" "3"; }
}
`
	if content != expected {
		t.Errorf("Content mismatch.\nGot:\n%s\nWant:\n%s", content, expected)
	}
}

func TestNiriGenerateWorkspaceBindsRoundTrip(t *testing.T) {
	provider := NewNiriProvider("")

	binds := map[string]*overrideBind{
		"Mod+1": {
			Key:         "Mod+1",
			Action:      "focus-workspace 1",
			Description: "Focus Workspace 1",
		},
		"Mod+2": {
			Key:         "Mod+2",
			Action:      "focus-workspace 2",
			Description: "Focus Workspace 2",
		},
		"Mod+Shift+1": {
			Key:         "Mod+Shift+1",
			Action:      "move-column-to-workspace 1",
			Description: "Move to Workspace 1",
		},
		"Super+Minus": {
			Key:         "Super+Minus",
			Action:      "set-column-width -10%",
			Description: "Adjust Column Width -10%",
		},
	}

	content := provider.generateBindsContent(binds)

	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.kdl")
	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write temp file: %v", err)
	}

	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("Failed to parse generated content: %v\nContent was:\n%s", err, content)
	}

	if len(result.Section.Keybinds) != 4 {
		t.Errorf("Expected 4 keybinds after round-trip, got %d", len(result.Section.Keybinds))
	}

	foundFocusWS1 := false
	foundMoveWS1 := false
	foundSetWidth := false

	for _, kb := range result.Section.Keybinds {
		switch {
		case kb.Action == "focus-workspace" && len(kb.Args) > 0 && kb.Args[0] == "1":
			foundFocusWS1 = true
		case kb.Action == "move-column-to-workspace" && len(kb.Args) > 0 && kb.Args[0] == "1":
			foundMoveWS1 = true
		case kb.Action == "set-column-width" && len(kb.Args) > 0 && kb.Args[0] == "-10%":
			foundSetWidth = true
		}
	}

	if !foundFocusWS1 {
		t.Error("focus-workspace 1 not found after round-trip")
	}
	if !foundMoveWS1 {
		t.Error("move-column-to-workspace 1 not found after round-trip")
	}
	if !foundSetWidth {
		t.Error("set-column-width -10% not found after round-trip")
	}
}

func TestNiriGenerateActionWithFilterAndScope(t *testing.T) {
	provider := NewNiriProvider("")

	binds := map[string]*overrideBind{
		"Alt+grave": {
			Key:         "Alt+grave",
			Action:      `next-window filter="app-id"`,
			Description: "Next Window (Same Application)",
		},
		"Alt+Tab": {
			Key:         "Alt+Tab",
			Action:      `next-window scope="output"`,
			Description: "Next Window",
		},
	}

	content := provider.generateBindsContent(binds)
	expected := `binds {
    Alt+Tab hotkey-overlay-title="Next Window" { next-window scope="output"; }
    Alt+grave hotkey-overlay-title="Next Window (Same Application)" { next-window filter="app-id"; }
}
`
	if content != expected {
		t.Errorf("Content mismatch.\nGot:\n%s\nWant:\n%s", content, expected)
	}
}

func TestNiriModKeyFollowsBackend(t *testing.T) {
	tests := []struct {
		name         string
		modKey       string
		modKeyNested string
		nested       bool
		want         keybinds.ModKey
	}{
		{"tty default", "", "", false, keybinds.ModKey{Symbol: "Mod", Resolved: "Super", Source: keybinds.ModSourceDefault}},
		{"tty configured", "Alt", "", false, keybinds.ModKey{Symbol: "Mod", Resolved: "Alt", Source: keybinds.ModSourceConfig}},
		{"nested default", "", "", true, keybinds.ModKey{Symbol: "Mod", Resolved: "Alt", Source: keybinds.ModSourceRuntime}},
		{"nested swaps when mod-key is alt", "Alt", "", true, keybinds.ModKey{Symbol: "Mod", Resolved: "Super", Source: keybinds.ModSourceRuntime}},
		{"nested configured", "Alt", "Super", true, keybinds.ModKey{Symbol: "Mod", Resolved: "Super", Source: keybinds.ModSourceConfig}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := niriModKey(&NiriParseResult{ModKey: tt.modKey, ModKeyNested: tt.modKeyNested}, tt.nested)
			if got != tt.want {
				t.Errorf("niriModKey() = %+v, want %+v", got, tt.want)
			}
		})
	}
}

func TestNiriParseModKeyNested(t *testing.T) {
	tmpDir := t.TempDir()
	config := `input {
    mod-key "Alt"
    mod-key-nested "Super"
}
`
	if err := os.WriteFile(filepath.Join(tmpDir, "config.kdl"), []byte(config), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}
	result, err := ParseNiriKeys(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriKeys failed: %v", err)
	}
	if result.ModKeyNested != "Super" {
		t.Errorf("ModKeyNested = %q, want %q", result.ModKeyNested, "Super")
	}
}

const niriBoundActionsBinds = `binds {
    Mod+J repeat=true { focus-window-down; }
    Control_R {
        press { spawn "ptt" "on"; }
        release { spawn "ptt" "off"; }
    }
    Mod+T pass-through=true { spawn "kitty"; }
    Mod {
        release { toggle-overview; }
    }
}
`

func writeNiriDMSBinds(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "dms"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "dms", "binds.kdl"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

// Parser and writer tests must not depend on which niri is installed.
func stubNiriValidate(t *testing.T) {
	t.Helper()
	orig := niriValidate
	niriValidate = func(string) ([]byte, error) { return nil, nil }
	t.Cleanup(func() { niriValidate = orig })
}

func TestNiriBoundActionsRoundTrip(t *testing.T) {
	provider := NewNiriProvider(writeNiriDMSBinds(t, niriBoundActionsBinds))
	binds, err := provider.loadOverrideBinds()
	if err != nil {
		t.Fatalf("loadOverrideBinds: %v", err)
	}
	if got := provider.generateBindsContent(binds); got != niriBoundActionsBinds {
		t.Errorf("round-trip changed binds:\n%s\nwant:\n%s", got, niriBoundActionsBinds)
	}
}

func TestNiriBoundActionsCheatSheet(t *testing.T) {
	niriNested = func() bool { return false }
	t.Cleanup(func() { niriNested = detectNiriNested })
	dir := writeNiriDMSBinds(t, niriBoundActionsBinds)
	if err := os.WriteFile(filepath.Join(dir, "config.kdl"), []byte(`include "dms/binds.kdl"`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	sheet, err := NewNiriProvider(dir).GetCheatSheet()
	if err != nil {
		t.Fatalf("GetCheatSheet: %v", err)
	}
	byKey := map[string]struct{ action, trigger, release string }{}
	passThrough := map[string]bool{}
	for _, binds := range sheet.Binds {
		for _, b := range binds {
			byKey[b.Key] = struct{ action, trigger, release string }{b.Action, b.Trigger, b.ReleaseAction}
			if b.PassThrough != nil {
				passThrough[b.Key] = *b.PassThrough
			}
		}
	}

	want := map[string]struct{ action, trigger, release string }{
		"Mod":       {"toggle-overview", "release", ""},
		"Control_R": {"spawn ptt on", "both", "spawn ptt off"},
		"Mod+T":     {"spawn kitty", "", ""},
	}
	for key, w := range want {
		if got := byKey[key]; got != w {
			t.Errorf("%s = %+v, want %+v", key, got, w)
		}
	}
	if !passThrough["Mod+T"] {
		t.Errorf("Mod+T pass-through not reported")
	}
}

func TestNiriSetBindKeepsReleaseBinds(t *testing.T) {
	stubNiriValidate(t)
	provider := NewNiriProvider(writeNiriDMSBinds(t, niriBoundActionsBinds))

	if err := provider.SetBind("Mod+Q", "close-window", "", nil); err != nil {
		t.Fatalf("SetBind on a file with release binds: %v", err)
	}
	if err := provider.SetBind("Mod", "toggle-overview", "Overview", nil); err != nil {
		t.Fatalf("SetBind Mod: %v", err)
	}

	binds, err := provider.loadOverrideBinds()
	if err != nil {
		t.Fatal(err)
	}
	mod := binds[normalizeNiriBindKey("Mod")]
	if mod == nil || mod.Action != "toggle-overview" || mod.Options["trigger"] != "release" {
		t.Errorf("Mod bind = %+v, want release-only toggle-overview", mod)
	}
	ptt := binds[normalizeNiriBindKey("Control_R")]
	if ptt == nil || ptt.Options["trigger"] != "both" || ptt.Options["release-action"] != "spawn ptt off" {
		t.Errorf("Control_R bind = %+v, want press+release", ptt)
	}
}

func TestNiriSetBindRejectsUnsupportedTriggers(t *testing.T) {
	stubNiriValidate(t)
	provider := NewNiriProvider(writeNiriDMSBinds(t, "binds {}\n"))

	cases := []struct {
		key  string
		opts map[string]any
	}{
		{"Mod+WheelScrollDown", map[string]any{"trigger": "release"}},
		{"TouchpadScrollUp", map[string]any{"trigger": "both", "release-action": "spawn x"}},
		{"Mod+MouseLeft", map[string]any{"pass-through": true}},
		{"Mod+T", map[string]any{"trigger": "both"}},
	}
	for _, c := range cases {
		if err := provider.SetBind(c.key, "spawn x", "", c.opts); err == nil {
			t.Errorf("SetBind(%s, %v) succeeded, want error", c.key, c.opts)
		}
	}
}

func TestNormalizeNiriBindKey(t *testing.T) {
	same := [][2]string{
		{"Shift+Alt", "Alt+Shift"},
		{"Mod+Shift+Alt+T", "Mod+Alt+Shift+t"},
		{"Control+Win+T", "Ctrl+Super+T"},
		{"ISO_Level3_Shift+x", "Mod5+X"},
		{"ISO_Level5_Shift+x", "Mod3+x"},
		{"Alt+Alt_L", "Alt_L"},
		{"Ctrl+ISO_Level3_Shift", "Mod5+Control"},
	}
	for _, p := range same {
		if a, b := normalizeNiriBindKey(p[0]), normalizeNiriBindKey(p[1]); a != b {
			t.Errorf("%s (%s) and %s (%s) should be the same bind", p[0], a, p[1], b)
		}
	}
	different := [][2]string{
		{"Mod+T", "Super+T"},
		{"Mod", "Super"},
		{"Alt_L", "Alt_R"},
		{"Alt+Shift", "Alt+Shift+T"},
	}
	for _, p := range different {
		if normalizeNiriBindKey(p[0]) == normalizeNiriBindKey(p[1]) {
			t.Errorf("%s and %s should be different binds", p[0], p[1])
		}
	}
}

func TestNiriBareModifierBindConflict(t *testing.T) {
	dir := writeNiriDMSBinds(t, "binds {\n    Alt+Shift { spawn \"dms-ptt\"; }\n}\n")
	config := "include \"dms/binds.kdl\"\nbinds {\n    Shift+Alt { spawn \"user-ptt\"; }\n}\n"
	if err := os.WriteFile(filepath.Join(dir, "config.kdl"), []byte(config), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := ParseNiriKeys(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.ConflictingConfigs) != 1 || len(result.Section.Keybinds) != 1 {
		t.Errorf("Shift+Alt vs Alt+Shift: %d conflicts, %d binds; want 1 and 1", len(result.ConflictingConfigs), len(result.Section.Keybinds))
	}
}

func TestNiriSetBindRealValidator(t *testing.T) {
	if _, err := exec.LookPath("niri"); err != nil {
		t.Skip("niri not installed")
	}
	if !config.NiriValidates(config.NiriBindsNextConfig) {
		t.Skip("installed niri does not accept press/release binds")
	}
	provider := NewNiriProvider(writeNiriDMSBinds(t, niriBoundActionsBinds))
	if err := provider.SetBind("Mod", "toggle-overview", "Overview", nil); err != nil {
		t.Fatalf("niri rejected the written binds: %v", err)
	}
}

func TestNiriEditorSaveKeepsReleaseArgs(t *testing.T) {
	stubNiriValidate(t)
	niriNested = func() bool { return false }
	t.Cleanup(func() { niriNested = detectNiriNested })
	dir := writeNiriDMSBinds(t, `binds {
    Control_R {
        press { spawn "ptt" "on"; }
        release { spawn "notify-send" "hello world" "say \"hi\"" "C:\\tmp"; }
    }
}
`)
	if err := os.WriteFile(filepath.Join(dir, "config.kdl"), []byte(`include "dms/binds.kdl"`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	provider := NewNiriProvider(dir)

	sheet, err := provider.GetCheatSheet()
	if err != nil {
		t.Fatal(err)
	}
	var sent struct {
		Action        string `json:"action"`
		ReleaseAction string `json:"releaseAction"`
	}
	for _, binds := range sheet.Binds {
		for _, b := range binds {
			if b.Key != "Control_R" {
				continue
			}
			data, err := json.Marshal(b)
			if err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(data, &sent); err != nil {
				t.Fatal(err)
			}
		}
	}

	opts := map[string]any{"trigger": "both", "release-action": sent.ReleaseAction}
	if err := provider.SetBind("Control_R", sent.Action, "Push to talk", opts); err != nil {
		t.Fatal(err)
	}

	result, err := ParseNiriKeys(dir)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"notify-send", "hello world", `say "hi"`, `C:\tmp`}
	for _, kb := range result.Section.Keybinds {
		if kb.Key == "Control_R" && slices.Equal(kb.ReleaseArgs, want) && kb.Description == "Push to talk" {
			return
		}
	}
	data, _ := os.ReadFile(filepath.Join(dir, "dms", "binds.kdl"))
	t.Errorf("release args changed after save (sent %q):\n%s", sent.ReleaseAction, data)
}

func TestNiriEditorSaveKeepsPressArgs(t *testing.T) {
	stubNiriValidate(t)
	niriNested = func() bool { return false }
	t.Cleanup(func() { niriNested = detectNiriNested })
	dir := writeNiriDMSBinds(t, `binds {
    Mod+X { spawn "notify-send" "hello world" "say \"hi\"" "C:\\tmp" ""; }
    Mod+Y { spawn "sh" "-c" "printf 'a\\n' | grep \"a b\""; }
    Mod+Z { move-column-to-workspace "my ws" focus=false; }
}
`)
	if err := os.WriteFile(filepath.Join(dir, "config.kdl"), []byte(`include "dms/binds.kdl"`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	provider := NewNiriProvider(dir)
	want := map[string][]string{
		"Mod+X": {"notify-send", "hello world", `say "hi"`, `C:\tmp`, ""},
		"Mod+Y": {"sh", "-c", `printf 'a\n' | grep "a b"`},
		"Mod+Z": {"my ws", "focus=false"},
	}

	sheet, err := provider.GetCheatSheet()
	if err != nil {
		t.Fatal(err)
	}
	sent := map[string]string{}
	for _, binds := range sheet.Binds {
		for _, b := range binds {
			data, err := json.Marshal(b)
			if err != nil {
				t.Fatal(err)
			}
			var got struct {
				Action string `json:"action"`
			}
			if err := json.Unmarshal(data, &got); err != nil {
				t.Fatal(err)
			}
			sent[b.Key] = got.Action
		}
	}

	for key := range want {
		if err := provider.SetBind(key, sent[key], "Edited "+key, nil); err != nil {
			t.Fatalf("SetBind %s (sent %q): %v", key, sent[key], err)
		}
	}

	result, err := ParseNiriKeys(dir)
	if err != nil {
		t.Fatal(err)
	}
	seen := 0
	for _, kb := range result.Section.Keybinds {
		key := provider.formatKey(&kb)
		args, ok := want[key]
		if !ok {
			continue
		}
		seen++
		if !slices.Equal(kb.Args, args) || kb.Description != "Edited "+key {
			t.Errorf("%s: args %q desc %q after save (sent %q), want args %q", key, kb.Args, kb.Description, sent[key], args)
		}
	}
	if seen != len(want) {
		t.Errorf("found %d of %d binds after save", seen, len(want))
	}
}

func TestNiriBindsConflict(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{"Alt", "Alt_L", true},
		{"Alt_R", "Alt", true},
		{"Alt_L", "Alt_R", false},
		{"Ctrl+Alt", "Ctrl+Alt_L", true},
		{"Alt", "Ctrl+Alt_L", false},
		{"Mod", "Super_L", false},
		{"Shift+Alt", "Alt+Shift", true},
		{"Alt+T", "Alt_L+T", false},
	}
	for _, c := range cases {
		if got := niriBindsConflict(c.a, c.b); got != c.want {
			t.Errorf("niriBindsConflict(%s, %s) = %v, want %v", c.a, c.b, got, c.want)
		}
	}
}

// niri drops the earlier generic bind when a later section binds a sided keysym.
func TestNiriGenericModifierBindConflict(t *testing.T) {
	dir := writeNiriDMSBinds(t, "binds {\n    Alt {\n        release { spawn \"dms-action\"; }\n    }\n}\n")
	config := "include \"dms/binds.kdl\"\nbinds {\n    Alt_L {\n        release { spawn \"user-action\"; }\n    }\n}\n"
	if err := os.WriteFile(filepath.Join(dir, "config.kdl"), []byte(config), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := ParseNiriKeys(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.ConflictingConfigs) != 1 || len(result.Section.Keybinds) != 1 {
		t.Errorf("Alt vs Alt_L: %d conflicts, %d binds; want 1 and 1", len(result.ConflictingConfigs), len(result.Section.Keybinds))
	}
}
