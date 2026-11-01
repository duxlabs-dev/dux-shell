package providers

import (
	"github.com/duxlabs-dev/dux-shell/core/internal/luaconfig"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/keybinds"
)

func TestHyprlandAutogenerateComment(t *testing.T) {
	tests := []struct {
		dispatcher string
		params     string
		expected   string
	}{
		{"resizewindow", "", "Resize window"},
		{"movewindow", "", "Move window"},
		{"movewindow", "l", "move in left direction"},
		{"pin", "", "pin (show on all workspaces)"},
		{"splitratio", "0.5", "Window split ratio 0.5"},
		{"togglefloating", "", "Float/unfloat window"},
		{"resizeactive", "10 20", "Grow window width by 10, grow height by 20"},
		{"resizeactive", "-100 0", "Shrink window width by 100"},
		{"resizeactive", "0 -5%", "Shrink window height by 5%"},
		{"resizeactive", "exact 1280 720", "Resize window to 1280x720"},
		{"moveactive", "-50 0", "Move window left by 50"},
		{"movewindow", "mon:l", "move to left monitor"},
		{"movewindow", "mon:+1", "move to next monitor"},
		{"movewindow", "mon:DP-1", "move to monitor DP-1"},
		{"focuswindow", "first", "focus window first"},
		{"focuswindow", "class:kitty", "focus kitty window"},
		{"movetoworkspacesilent", "special:magic", "move to special workspace magic"},
		{"moveintogroup", "l", "move into left group"},
		{"changegroupactive", "b", "previous window in group"},
		{"layoutmsg", "togglesplit", "Toggle split"},
		{"layoutmsg", "splitratio 0.1", "Window split ratio 0.1"},
		{"fullscreen", "1 set", "Enter maximization"},
		{"killactive", "", "Close window"},
		{"fullscreen", "0", "Toggle fullscreen"},
		{"fullscreen", "1", "Toggle maximization"},
		{"fullscreen", "2", "Toggle fullscreen on Hyprland's side"},
		{"workspace", "+1", "focus right"},
		{"workspace", "-1", "focus left"},
		{"workspace", "5", "focus workspace 5"},
		{"movefocus", "l", "move focus left"},
		{"swapwindow", "l", "swap in left direction"},
		{"movetoworkspace", "+1", "move to right workspace (non-silent)"},
		{"movetoworkspace", "3", "move to workspace 3 (non-silent)"},
		{"movetoworkspacesilent", "-1", "move to left workspace"},
		{"movetoworkspacesilent", "2", "move to workspace 2"},
		{"togglespecialworkspace", "", "toggle special"},
		{"exec", "firefox", "firefox"},
		{"unknown", "", ""},
	}

	for _, tt := range tests {
		t.Run(tt.dispatcher+"_"+tt.params, func(t *testing.T) {
			result := hyprlandAutogenerateComment(tt.dispatcher, tt.params)
			if result != tt.expected {
				t.Errorf("hyprlandAutogenerateComment(%q, %q) = %q, want %q",
					tt.dispatcher, tt.params, result, tt.expected)
			}
		})
	}
}

func TestHyprlandLuaBindRoundTripHelpers(t *testing.T) {
	tests := []struct {
		expr           string
		wantDispatcher string
		wantParams     string
	}{
		{`hl.dsp.exec_cmd([[dms ipc call brightness increment 5 ""]])`, "exec", `dms ipc call brightness increment 5 ""`},
		{`hl.dsp.exec_cmd([[hyprctl dispatch workspace 1]])`, "workspace", "1"},
		{`hl.dispatch("workspace 2")`, "workspace", "2"},
		{`hl.dispatch([[customdispatcher arg one]])`, "customdispatcher", "arg one"},
		{`hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })`, "fullscreen", "1"},
		{`hl.dsp.window.float({ action = "on" })`, "setfloating", ""},
		{`hl.dsp.window.close()`, "killactive", ""},
		{`hl.dsp.window.kill()`, "forcekillactive", ""},
		{`hl.dsp.window.close({ window = "class:^(kitty)$" })`, "closewindow", "class:^(kitty)$"},
		{`hl.dsp.focus({ workspace = "e+1" })`, "workspace", "e+1"},
		{`hl.dsp.focus({ workspace = "2", on_current_monitor = true })`, "focusworkspaceoncurrentmonitor", "2"},
		{`hl.dsp.window.move({ monitor = "l" })`, "movewindow", "mon:l"},
		{`hl.dsp.window.move({ direction = "r", group_aware = true })`, "movewindoworgroup", "r"},
		{`hl.dsp.window.move({ into_group = "l" })`, "moveintogroup", "l"},
		{`hl.dsp.window.move({ out_of_group = true })`, "moveoutofgroup", ""},
		{`hl.dsp.window.move({ workspace = "special:magic", follow = false })`, "movetoworkspacesilent", "special:magic"},
		{`hl.dsp.window.resize({ x = -100, y = 0, relative = true })`, "resizeactive", "-100 0"},
		{`hl.dsp.window.resize({ x = 1280, y = 720, relative = false })`, "resizeactive", "exact 1280 720"},
		{`hl.dsp.window.resize({ x = 100, y = 50, relative = true, window = "class:^(app)$" })`, "resizewindowpixel", "100 50,class:^(app)$"},
		{`hl.dsp.window.cycle_next({ next = false, tiled = true })`, "cyclenext", "prev tiled"},
		{`hl.dsp.group.next()`, "changegroupactive", "f"},
		{`hl.dsp.group.prev()`, "changegroupactive", "b"},
		{`hl.dsp.group.active({ index = 2 })`, "changegroupactive", "2"},
		{`hl.dsp.group.move_window({ forward = false })`, "movegroupwindow", "b"},
		{`hl.dsp.group.lock({ all = true, action = "on" })`, "lockgroups", "lock"},
		{`hl.dsp.group.lock({ action = "off", window = "class:^(kitty)$" })`, "lockactivegroup", "unlock class:^(kitty)$"},
		{`hl.dsp.group.lock_active({ action = "off" })`, "lockactivegroup", "unlock"},
		{`hl.dsp.reload_config()`, "reloadconfig", ""},
		{`hl.dsp.exec_cmd("hyprctl reload")`, "reloadconfig", ""},
		{`hl.dsp.window.deny_from_group({ action = "toggle" })`, "denywindowfromgroup", "toggle"},
		{`function() hl.exec_cmd("hyprctl dispatch splitratio +0.1") end`, "splitratio", "+0.1"},
		{`hl.dsp.layout("togglesplit")`, "layoutmsg", "togglesplit"},
		{`hl.dsp.dpms({ action = "toggle" })`, "dpms", "toggle"},
		{`hl.dsp.workspace.rename({ workspace = "1", name = "work" })`, "renameworkspace", "1 work"},
		{`hl.dsp.no_op()`, "hl.dsp.no_op()", ""},
		{`hl.dsp.exec_cmd(terminal)`, "hl.dsp.exec_cmd(terminal)", ""},
		{`hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" })`, "fullscreen", "1 unset"},
		{`hl.dsp.dpms({ action = "disable", monitor = "DP-1" })`, "dpms", "off DP-1"},
		{`hl.dsp.dpms({ monitor = "DP-1" })`, "dpms", "toggle DP-1"},
		{`hl.dsp.release_input_capture()`, "releaseinputcapture", ""},
	}

	for _, tt := range tests {
		t.Run(tt.expr, func(t *testing.T) {
			gotDispatcher, gotParams := luaExprToDispatcherParams(tt.expr)
			if gotDispatcher != tt.wantDispatcher || gotParams != tt.wantParams {
				t.Fatalf("luaExprToDispatcherParams() = %q, %q; want %q, %q", gotDispatcher, gotParams, tt.wantDispatcher, tt.wantParams)
			}
		})
	}
}

func TestWriteLuaBindLineOptionsInsideCall(t *testing.T) {
	var sb strings.Builder
	writeLuaBindLine(&sb, &hyprlandOverrideBind{
		Key:         "Super+k",
		Action:      "exec kitty",
		Description: "Open terminal",
		Flags:       "led",
	})

	want := `hl.unbind("SUPER + K")
hl.bind("SUPER + K", hl.dsp.exec_cmd("kitty"), { locked = true, repeating = true, description = "Open terminal" })`
	if got := strings.TrimSpace(sb.String()); got != want {
		t.Fatalf("writeLuaBindLine() = %q, want %q", got, want)
	}
}

func TestWriteLuaBindLineMapsSpawnActionForHyprland(t *testing.T) {
	var sb strings.Builder
	writeLuaBindLine(&sb, &hyprlandOverrideBind{
		Key:         "Super+n",
		Action:      "spawn dms ipc call notepad toggle",
		Description: "Notepad: Toggle",
	})

	want := `hl.unbind("SUPER + N")
hl.bind("SUPER + N", hl.dsp.exec_cmd("dms ipc call notepad toggle"), { description = "Notepad: Toggle" })`
	if got := strings.TrimSpace(sb.String()); got != want {
		t.Fatalf("writeLuaBindLine() = %q, want %q", got, want)
	}
}

func TestWriteLuaBindLineLeavesCustomLuaDispatcherRaw(t *testing.T) {
	var sb strings.Builder
	writeLuaBindLine(&sb, &hyprlandOverrideBind{
		Key:          "Super+u",
		Action:       "hl.dsp.no_op()",
		Description:  "Custom Lua",
		RawLuaAction: true,
	})

	want := `hl.unbind("SUPER + U")
hl.bind("SUPER + U", hl.dsp.no_op(), { description = "Custom Lua" })`
	if got := strings.TrimSpace(sb.String()); got != want {
		t.Fatalf("writeLuaBindLine() = %q, want %q", got, want)
	}
}

func TestWriteLuaBindLineCommentsOutUnrecognizedAction(t *testing.T) {
	var sb strings.Builder
	writeLuaBindLine(&sb, &hyprlandOverrideBind{
		Key:    "Super+u",
		Action: "customdispatcher x\nos.execute(\"id\")",
	})

	got := strings.TrimSuffix(sb.String(), "\n")
	if strings.Contains(got, "\n") || !strings.HasPrefix(got, "-- ") {
		t.Fatalf("expected a single comment line, got %q", got)
	}
}

func TestLuaActionStringFromHyprlangActionUsesNativeDispatchers(t *testing.T) {
	tests := []struct {
		action string
		want   string
	}{
		{"killactive", `hl.dsp.window.close()`},
		{"forcekillactive", `hl.dsp.window.kill()`},
		{"workspace 1", `hl.dsp.focus({ workspace = "1" })`},
		{"movetoworkspace 2", `hl.dsp.window.move({ workspace = "2" })`},
		{"movetoworkspacesilent special:magic", `hl.dsp.window.move({ workspace = "special:magic", follow = false })`},
		{"focusmonitor DP-1", `hl.dsp.focus({ monitor = "DP-1" })`},
		{"resizeactive exact 1280 720", `hl.dsp.window.resize({ x = 1280, y = 720, relative = false })`},
		{"dpms toggle", `hl.dsp.dpms({ action = "toggle" })`},
		{"renameworkspace 1 work", `hl.dsp.workspace.rename({ workspace = "1", name = "work" })`},
		{"changegroupactive f", `hl.dsp.group.next()`},
		{"changegroupactive b", `hl.dsp.group.prev()`},
		{"changegroupactive 2", `hl.dsp.group.active({ index = 2 })`},
		{"moveintogroup l", `hl.dsp.window.move({ into_group = "l" })`},
		{"moveoutofgroup", `hl.dsp.window.move({ out_of_group = true })`},
		{"movewindoworgroup r", `hl.dsp.window.move({ direction = "r", group_aware = true })`},
		{"movegroupwindow b", `hl.dsp.group.move_window({ forward = false })`},
		{"lockgroups lock", `hl.dsp.group.lock({ all = true, action = "on" })`},
		{"lockactivegroup unlock", `hl.dsp.group.lock_active({ action = "off" })`},
		{"lockactivegroup lock class:^(kitty)$", `hl.dsp.group.lock({ action = "on", window = "class:^(kitty)$" })`},
		{"reloadconfig", `hl.dsp.exec_cmd("hyprctl reload")`},
		{"denywindowfromgroup toggle", `hl.dsp.window.deny_from_group({ action = "toggle" })`},
		{"cyclenext prev", `hl.dsp.window.cycle_next({ next = false })`},
		{"setfloating", `hl.dsp.window.float({ action = "on" })`},
		{"settiled", `hl.dsp.window.float({ action = "off" })`},
		{"bringactivetotop", `hl.dsp.window.bring_to_top()`},
		{"toggleswallow", `hl.dsp.window.toggle_swallow()`},
		{"forceidle 300", `hl.dsp.force_idle(300)`},
		{"splitratio +0.1", `hl.dsp.layout("splitratio +0.1")`},
		{"splitratio exact 0.5", `hl.dsp.layout("splitratio 0.5 exact")`},
		{"fullscreen 0 set", `hl.dsp.window.fullscreen({ mode = "fullscreen", action = "set" })`},
		{"fullscreen 1 unset", `hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" })`},
		{"fullscreen", `hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })`},
		{"releaseinputcapture", `hl.dsp.release_input_capture()`},
		{"dpms off DP-1", `hl.dsp.dpms({ action = "disable", monitor = "DP-1" })`},
		{"pseudo", `hl.dsp.window.pseudo({ action = "toggle" })`},
		{"moveintoorcreategroup l", `hl.dsp.window.move({ into_or_create_group = "l" })`},
		{"layoutmsg swapsplit", `hl.dsp.layout("swapsplit")`},
	}

	for _, tt := range tests {
		t.Run(tt.action, func(t *testing.T) {
			got, ok := luaActionStringFromHyprlangAction(tt.action)
			if !ok || got != tt.want {
				t.Fatalf("luaActionStringFromHyprlangAction(%q) = %q, %v; want %q", tt.action, got, ok, tt.want)
			}
			// each mapping must parse back to the same action
			if again, _ := luaActionStringFromHyprlangAction(strings.Join(nonEmpty(luaExprToDispatcherParams(got)), " ")); again != got {
				t.Fatalf("round trip of %q produced %q", got, again)
			}
		})
	}
}

func nonEmpty(values ...string) []string {
	out := values[:0]
	for _, v := range values {
		if v != "" {
			out = append(out, v)
		}
	}
	return out
}

func TestHyprlandRejectsActionsWithoutLuaDispatcher(t *testing.T) {
	actions := []string{
		"resizeactive exact 100% 100%",
		"fakefullscreen",
		"focuswindowbyclass kitty",
		"togglesplit",
		"swapsplit",
		"workspaceopt allfloat",
		"setignoregrouplock on",
		"fullscreen 2",
		"pass",
		"customdispatcher arg",
	}
	p := NewHyprlandProvider(t.TempDir())
	for _, action := range actions {
		t.Run(action, func(t *testing.T) {
			if got, ok := luaActionStringFromHyprlangAction(action); ok {
				t.Fatalf("luaActionStringFromHyprlangAction(%q) = %q, want no mapping", action, got)
			}
			if err := p.validateAction(action); err == nil {
				t.Fatalf("validateAction(%q) = nil, want error", action)
			}
		})
	}
	for _, action := range []string{"hl.dsp.no_op()", "splitratio -0.1"} {
		if err := p.validateAction(action); err != nil {
			t.Fatalf("validateAction(%q) = %v, want nil", action, err)
		}
	}
}

func TestParseLuaBindLineKeepsUnmappableDispatchWrapperVerbatim(t *testing.T) {
	expr := `function() hl.exec_cmd("hyprctl dispatch resizeactive exact 100% 100%") end`
	line := `hl.bind("SUPER + R", ` + expr + `, { description = "Unsupported Resize" })`
	got, ok := parseLuaBindOverrideLine(line)
	if !ok {
		t.Fatalf("expected line to parse")
	}
	if got.Action != expr || !got.RawLuaAction {
		t.Fatalf("Action = %q (raw %v), want verbatim %q", got.Action, got.RawLuaAction, expr)
	}
	if got.Description != "Unsupported Resize" {
		t.Fatalf("Description = %q, want Unsupported Resize", got.Description)
	}
}

func TestParseLuaBindLineUpgradesMappableDispatchWrapper(t *testing.T) {
	line := `hl.bind("SUPER + O", function() hl.exec_cmd("hyprctl dispatch splitratio +0.1") end)`
	got, ok := parseLuaBindOverrideLine(line)
	if !ok {
		t.Fatalf("expected line to parse")
	}
	var sb strings.Builder
	writeLuaBindLine(&sb, got)
	if !strings.Contains(sb.String(), `hl.bind("SUPER + O", hl.dsp.layout("splitratio +0.1"))`) {
		t.Fatalf("expected native layout dispatcher, got %q", sb.String())
	}
}

func TestParseLuaBindLineBareGroupLockFollowsHyprlandVersion(t *testing.T) {
	prev := luaconfig.HyprlandVersion
	t.Cleanup(func() { luaconfig.HyprlandVersion = prev })
	for _, tc := range []struct {
		minor  int
		action string
		want   string
	}{
		{56, "lockgroups toggle", `hl.dsp.group.lock({ all = true, action = "toggle" })`},
		{57, "lockactivegroup toggle", `hl.dsp.group.lock_active({ action = "toggle" })`},
	} {
		minor := tc.minor
		luaconfig.HyprlandVersion = func() (int, int) { return 0, minor }
		got, ok := parseLuaBindOverrideLine(`hl.bind("SUPER + G", hl.dsp.group.lock({ action = "toggle" }))`)
		if !ok {
			t.Fatalf("0.%d: expected line to parse", minor)
		}
		if got.Action != tc.action {
			t.Fatalf("0.%d: action = %q, want %q", minor, got.Action, tc.action)
		}
		var sb strings.Builder
		writeLuaBindLine(&sb, got)
		if !strings.Contains(sb.String(), tc.want) {
			t.Fatalf("0.%d: expected %q, got %q", minor, tc.want, sb.String())
		}
	}
}

func TestReadLuaOverrideMigratesTrailingCommentToDescription(t *testing.T) {
	tmpDir := t.TempDir()
	overridePath := filepath.Join(tmpDir, "binds-user.lua")
	contents := `hl.unbind("SUPER + N")
hl.bind("SUPER + N", hl.dsp.exec_cmd("dms ipc call notepad toggle")) -- Notepad: Toggle
hl.bind("SUPER + H", hl.dsp.exec_cmd("app --help"))
`
	if err := os.WriteFile(overridePath, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}

	binds, err := readLuaOverride(overridePath)
	if err != nil {
		t.Fatal(err)
	}
	got := binds["super+n"]
	if got == nil {
		t.Fatalf("expected SUPER+N override, got %#v", binds)
	}
	if got.Description != "Notepad: Toggle" {
		t.Fatalf("expected trailing comment to be preserved as description, got %q", got.Description)
	}
	if got := binds["super+h"]; got == nil || got.Description != "" {
		t.Fatalf("expected -- inside a Lua string to stay out of the description, got %#v", got)
	}
}

func TestHyprlandLuaBindsUserOverridesDefaults(t *testing.T) {
	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "hyprland.lua"), []byte(`
require("dms.binds")
require("dms.binds-user")
`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dmsDir, "binds.lua"), []byte(`hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dmsDir, "binds-user.lua"), []byte(`hl.bind("SUPER + T", hl.dsp.exec_cmd("foot"), { description = "User terminal" })`), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := ParseHyprlandKeysWithDMS(tmpDir)
	if err != nil {
		t.Fatal(err)
	}

	var found []HyprlandKeyBinding
	var walk func(HyprlandSection)
	walk = func(section HyprlandSection) {
		for _, kb := range section.Keybinds {
			if strings.EqualFold(strings.Join(append(kb.Mods, kb.Key), "+"), "SUPER+T") {
				found = append(found, kb)
			}
		}
		for _, child := range section.Children {
			walk(child)
		}
	}
	walk(*result.Section)

	if len(found) != 1 {
		t.Fatalf("expected one effective SUPER+T bind, got %d: %#v", len(found), found)
	}
	if found[0].Params != "foot" || found[0].Comment != "User terminal" {
		t.Fatalf("expected user override bind, got %#v", found[0])
	}
}

func TestWriteLuaBindLineEmitsUnbindOnlyForNegativeOverride(t *testing.T) {
	var sb strings.Builder
	writeLuaBindLine(&sb, &hyprlandOverrideBind{Key: "Super+i", Unbind: true})

	want := `hl.unbind("SUPER + I")`
	if got := strings.TrimSpace(sb.String()); got != want {
		t.Fatalf("writeLuaBindLine() = %q, want %q", got, want)
	}
}

func TestReadLuaOverrideRecognizesLoneUnbindAsNegativeOverride(t *testing.T) {
	tmpDir := t.TempDir()
	overridePath := filepath.Join(tmpDir, "binds-user.lua")
	contents := `-- DMS user keybind overrides
hl.unbind("SUPER + I")
hl.unbind("SUPER + N")
hl.bind("SUPER + N", hl.dsp.exec_cmd("dms ipc call notepad toggle"))
`
	if err := os.WriteFile(overridePath, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}

	binds, err := readLuaOverride(overridePath)
	if err != nil {
		t.Fatal(err)
	}

	got, ok := binds["super+i"]
	if !ok {
		t.Fatalf("expected SUPER+I entry in override map, got: %#v", binds)
	}
	if !got.Unbind {
		t.Fatalf("expected SUPER+I to be marked Unbind, got: %#v", got)
	}
	if rebind, ok := binds["super+n"]; !ok || rebind.Unbind {
		t.Fatalf("expected SUPER+N to be a normal rebind override, got: %#v", rebind)
	}
}

func TestParserDropsDMSDefaultsSuppressedByBindsUserUnbind(t *testing.T) {
	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "hyprland.lua"), []byte(`
require("dms.binds")
require("dms.binds-user")
`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dmsDir, "binds.lua"), []byte(
		`hl.bind("SUPER + I", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))`,
	), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dmsDir, "binds-user.lua"), []byte(`hl.unbind("SUPER + I")`), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := ParseHyprlandKeysWithDMS(tmpDir)
	if err != nil {
		t.Fatal(err)
	}

	var keys []string
	var walk func(HyprlandSection)
	walk = func(section HyprlandSection) {
		for _, kb := range section.Keybinds {
			keys = append(keys, strings.ToUpper(strings.Join(append(kb.Mods, kb.Key), "+")))
		}
		for _, child := range section.Children {
			walk(child)
		}
	}
	walk(*result.Section)

	for _, k := range keys {
		if k == "SUPER+I" {
			t.Fatalf("expected SUPER+I to be suppressed by binds-user.lua unbind, got: %v", keys)
		}
	}
	foundT := false
	for _, k := range keys {
		if k == "SUPER+T" {
			foundT = true
		}
	}
	if !foundT {
		t.Fatalf("expected SUPER+T to remain (only SUPER+I was unbound), got: %v", keys)
	}
}

func TestHyprlandRemoveBindWritesNegativeOverrideForDefault(t *testing.T) {
	tmpDir := hyprLuaTestDir(t)
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}

	provider := NewHyprlandProvider(tmpDir)
	if err := provider.RemoveBind("SUPER+I"); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(filepath.Join(dmsDir, "binds-user.lua"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `hl.unbind("SUPER + I")`) {
		t.Fatalf("expected negative override hl.unbind line, got:\n%s", string(data))
	}
	if strings.Contains(string(data), `hl.bind("SUPER + I"`) {
		t.Fatalf("expected NO hl.bind for SUPER+I, got:\n%s", string(data))
	}
}

func TestIsRawLuaActionText(t *testing.T) {
	cases := []struct {
		action string
		want   bool
	}{
		{`function() hl.plugin.scrolloverview.overview("toggle") end`, true},
		{`hl.dsp.exec_cmd("foo")`, true},
		{`hl.dsp.no_op()`, true},
		{"workspace 3", false},
		{"exec zeditor", false},
		{`function() hl.foo( end`, false},
		{`function() hl.foo("a) end`, false},
		{`hl.foo()) hl.bar((`, false},
	}
	for _, tc := range cases {
		if got := isRawLuaActionText(tc.action); got != tc.want {
			t.Errorf("isRawLuaActionText(%q) = %v, want %v", tc.action, got, tc.want)
		}
	}
}

func TestHyprlandSetBindPreservesRawLuaAction(t *testing.T) {
	tmpDir := hyprLuaTestDir(t)
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dmsDir, "binds-user.lua"), []byte("-- DMS user keybind overrides\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	provider := NewHyprlandProvider(tmpDir)
	rawAction := `function() hl.plugin.scrolloverview.overview("toggle") end`
	if err := provider.SetBind("SUPER + G", rawAction, "Toggle overview", nil); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(filepath.Join(dmsDir, "binds-user.lua"))
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)
	if !strings.Contains(got, `hl.bind("SUPER + G", `+rawAction) {
		t.Fatalf("expected raw Lua action to be written verbatim, got:\n%s", got)
	}
	if strings.Contains(got, "hyprctl dispatch function") {
		t.Fatalf("expected raw Lua action to not be wrapped in hyprctl dispatch, got:\n%s", got)
	}
}

func TestHyprlandSetBindUpdatesSpacedLuaOverrideWithoutDuplicates(t *testing.T) {
	tmpDir := hyprLuaTestDir(t)
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	override := `-- DMS user keybind overrides

hl.unbind("SUPER + SHIFT + S")
hl.bind("SUPER + 1", hl.dsp.exec_cmd("hyprctl dispatch workspace 1"))
`
	if err := os.WriteFile(filepath.Join(dmsDir, "binds-user.lua"), []byte(override), 0o644); err != nil {
		t.Fatal(err)
	}

	provider := NewHyprlandProvider(tmpDir)
	if err := provider.SetBind("SUPER + 1", "workspace 1", "", nil); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(filepath.Join(dmsDir, "binds-user.lua"))
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)
	if strings.Count(got, `hl.unbind("SUPER + 1")`) != 1 {
		t.Fatalf("expected one SUPER+1 unbind, got:\n%s", got)
	}
	if strings.Count(got, `hl.bind("SUPER + 1", hl.dsp.focus({ workspace = "1" }))`) != 1 {
		t.Fatalf("expected one native SUPER+1 bind, got:\n%s", got)
	}
	if strings.Contains(got, "hyprctl dispatch workspace 1") {
		t.Fatalf("expected old hyprctl workspace dispatcher to be replaced, got:\n%s", got)
	}
	if !strings.Contains(got, `hl.unbind("SUPER + SHIFT + S")`) {
		t.Fatalf("expected unrelated override to be preserved, got:\n%s", got)
	}
}

func TestHyprlandSetBindTranslatesScrollWheelToMouse(t *testing.T) {
	tmpDir := hyprLuaTestDir(t)
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	bindsUser := filepath.Join(dmsDir, "binds-user.lua")
	if err := os.WriteFile(bindsUser, []byte("-- DMS user keybind overrides\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	provider := NewHyprlandProvider(tmpDir)
	if err := provider.SetBind("SUPER + WheelScrollDown", "workspace 1", "", nil); err != nil {
		t.Fatal(err)
	}

	got := readFile(t, bindsUser)
	if !strings.Contains(got, `hl.bind("SUPER + mouse_down"`) {
		t.Fatalf("expected scroll key translated to mouse_down, got:\n%s", got)
	}
	if strings.Contains(got, "WheelScroll") {
		t.Fatalf("expected no raw niri scroll keysym in hyprland output, got:\n%s", got)
	}

	if err := provider.SetBind("SUPER + WheelScrollDown", "workspace 2", "", nil); err != nil {
		t.Fatal(err)
	}
	got = readFile(t, bindsUser)
	if strings.Count(got, `hl.bind("SUPER + mouse_down"`) != 1 {
		t.Fatalf("expected exactly one mouse_down bind after re-save, got:\n%s", got)
	}
}

func TestHyprlandScrollWheelRoundTrips(t *testing.T) {
	for native, canonical := range map[string]string{
		"mouse_up":    "WheelScrollUp",
		"mouse_down":  "WheelScrollDown",
		"mouse_left":  "WheelScrollLeft",
		"mouse_right": "WheelScrollRight",
	} {
		if got := luaKeyComboToInternalKey("SUPER + " + native); got != "SUPER+"+canonical {
			t.Errorf("luaKeyComboToInternalKey(%q) = %q, want SUPER+%s", native, got, canonical)
		}
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestHyprlandRemoveBindReplacesExistingOverrideWithNegativeOverride(t *testing.T) {
	tmpDir := hyprLuaTestDir(t)
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	override := `hl.unbind("SUPER + N")
hl.bind("SUPER + N", hl.dsp.exec_cmd("dms ipc call notepad toggle"))
`
	if err := os.WriteFile(filepath.Join(dmsDir, "binds-user.lua"), []byte(override), 0o644); err != nil {
		t.Fatal(err)
	}

	provider := NewHyprlandProvider(tmpDir)
	if err := provider.RemoveBind("SUPER+N"); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(filepath.Join(dmsDir, "binds-user.lua"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `hl.unbind("SUPER + N")`) {
		t.Fatalf("expected negative override hl.unbind line, got:\n%s", string(data))
	}
	if strings.Contains(string(data), `hl.bind("SUPER + N"`) {
		t.Fatalf("expected NO hl.bind for SUPER+N after remove, got:\n%s", string(data))
	}
}

func TestHyprlandResetBindRevertsExistingOverrideToDefault(t *testing.T) {
	tmpDir := hyprLuaTestDir(t)
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	override := `hl.unbind("SUPER + N")
hl.bind("SUPER + N", hl.dsp.exec_cmd("dms ipc call notepad toggle"))
`
	if err := os.WriteFile(filepath.Join(dmsDir, "binds-user.lua"), []byte(override), 0o644); err != nil {
		t.Fatal(err)
	}

	provider := NewHyprlandProvider(tmpDir)
	if err := provider.ResetBind("SUPER+N"); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(filepath.Join(dmsDir, "binds-user.lua"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), `SUPER + N`) {
		t.Fatalf("expected SUPER+N to be fully removed (revert to default), got:\n%s", string(data))
	}
}

func TestHyprlandHasDefaultSetForOverrideOfDefaultKey(t *testing.T) {
	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "hyprland.lua"), []byte(`
require("dms.binds")
require("dms.binds-user")
`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dmsDir, "binds.lua"), []byte(
		`hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))`,
	), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dmsDir, "binds-user.lua"), []byte(
		`hl.unbind("SUPER + T")
hl.bind("SUPER + T", hl.dsp.exec_cmd("foot"))
hl.bind("SUPER + Z", hl.dsp.exec_cmd("custom"))`,
	), 0o644); err != nil {
		t.Fatal(err)
	}

	provider := NewHyprlandProvider(tmpDir)
	sheet, err := provider.GetCheatSheet()
	if err != nil {
		t.Fatal(err)
	}

	var foundT, foundZ *keybinds.Keybind
	for _, group := range sheet.Binds {
		for i := range group {
			kb := group[i]
			keyUpper := strings.ToUpper(kb.Key)
			if keyUpper == "SUPER+T" {
				foundT = &group[i]
			}
			if keyUpper == "SUPER+Z" {
				foundZ = &group[i]
			}
		}
	}
	if foundT == nil {
		t.Fatalf("expected SUPER+T override in cheatsheet")
	}
	if !foundT.HasDefault {
		t.Fatalf("expected SUPER+T HasDefault=true (default exists in binds.lua), got %+v", foundT)
	}
	if foundZ == nil {
		t.Fatalf("expected SUPER+Z (user-only) in cheatsheet")
	}
	if foundZ.HasDefault {
		t.Fatalf("expected SUPER+Z HasDefault=false (no default), got %+v", foundZ)
	}
}

func TestHyprlandBindFlagsRoundTrip(t *testing.T) {
	tests := []struct {
		flag string
		opt  string
	}{
		{"l", "locked = true"},
		{"e", "repeating = true"},
		{"r", "release = true"},
		{"n", "non_consuming = true"},
		{"m", "mouse = true"},
		{"t", "transparent = true"},
		{"i", "ignore_mods = true"},
		{"o", "long_press = true"},
		{"u", "submap_universal = true"},
		{"a", "auto_consuming = true"},
		{"x", "allow_input_capture = true"},
		{"p", "dont_inhibit = true"},
		{"c", "click = true"},
		{"g", "drag = true"},
		{"k", `device = { inclusive = false, list = { "my-kb", "other" } }`},
	}
	for _, tt := range tests {
		t.Run(tt.flag, func(t *testing.T) {
			line := `hl.bind("SUPER + X", hl.dsp.window.close(), { ` + tt.opt + ` })`
			kb, ok := parseLuaBindOverrideLine(line)
			if !ok {
				t.Fatalf("parse failed for %q", line)
			}
			if kb.Flags != tt.flag {
				t.Fatalf("Flags = %q, want %q", kb.Flags, tt.flag)
			}
			var sb strings.Builder
			writeLuaBindLine(&sb, kb)
			if !strings.Contains(sb.String(), line) {
				t.Fatalf("rewrite = %q, want it to contain %q", sb.String(), line)
			}
		})
	}
}

func TestHyprlandSetBindKeepsDeviceTable(t *testing.T) {
	tmpDir := hyprLuaTestDir(t)
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	device := `device = { inclusive = true, list = { "my-kb" } }`
	if err := os.WriteFile(filepath.Join(dmsDir, "binds-user.lua"), []byte(`hl.bind("SUPER + X", hl.dsp.window.close(), { `+device+` })`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := NewHyprlandProvider(tmpDir).SetBind("SUPER+X", "togglefloating", "", map[string]any{"flags": "k"}); err != nil {
		t.Fatal(err)
	}
	if got := readFile(t, filepath.Join(dmsDir, "binds-user.lua")); !strings.Contains(got, device) {
		t.Fatalf("expected device table to survive the edit, got:\n%s", got)
	}
}

func TestHyprlandSetBindKeepsMainConfigDeviceTable(t *testing.T) {
	tmpDir := t.TempDir()
	device := `device = { list = { "my-kb" } }`
	main := `hl.bind("SUPER + X", hl.dsp.window.close(), { ` + device + ` })` + "\n"
	if err := os.WriteFile(filepath.Join(tmpDir, "hyprland.lua"), []byte(main), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := NewHyprlandProvider(tmpDir).SetBind("SUPER+X", "togglefloating", "", map[string]any{"flags": "k"}); err != nil {
		t.Fatal(err)
	}
	if got := readFile(t, filepath.Join(tmpDir, "dms", "binds-user.lua")); !strings.Contains(got, device) {
		t.Fatalf("expected the main config device table on the override, got:\n%s", got)
	}
}

func TestHyprlandSetBindLeavesConfOnlyInstallReadOnly(t *testing.T) {
	tmpDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(tmpDir, "hyprland.conf"), []byte("bind = SUPER, T, exec, kitty\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	provider := NewHyprlandProvider(tmpDir)
	err := provider.SetBind("SUPER+N", "workspace 1", "Workspace 1", nil)
	if err == nil {
		t.Fatal("expected SetBind to reject conf-only Hyprland config")
	}
	if !strings.Contains(err.Error(), "dms setup") {
		t.Fatalf("expected a run-dms-setup error, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(tmpDir, "dms", "binds-user.lua")); !os.IsNotExist(err) {
		t.Fatalf("expected no Lua override to be created for conf-only config, stat err=%v", err)
	}
}

func hyprLuaTestDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "hyprland.lua"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}
