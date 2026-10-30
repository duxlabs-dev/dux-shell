package providers

import (
	"github.com/duxlabs-dev/dux-shell/core/internal/luaconfig"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/windowrules"
)

func TestHyprlandIgnoresConfWhenLuaPresent(t *testing.T) {
	tmpDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(tmpDir, "hyprland.conf"), []byte("windowrule = match:class ^conf$, float on\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "hyprland.lua"), []byte(`hl.window_rule({ match = { class = "^lua$" }, float = true })`+"\n"), 0644); err != nil {
		t.Fatal(err)
	}

	res, err := ParseHyprlandWindowRules(tmpDir)
	if err != nil {
		t.Fatalf("ParseHyprlandWindowRules: %v", err)
	}
	if len(res.Rules) != 1 || res.Rules[0].Match.AppID != "^lua$" {
		t.Fatalf("expected only the Lua rule, got %+v", res.Rules)
	}
	if err := NewHyprlandWritableProvider(tmpDir).EnsureWritable(); err != nil {
		t.Errorf("EnsureWritable with hyprland.lua present: %v", err)
	}
}

func TestHyprlandSetRuleLeavesConfOnlyInstallReadOnly(t *testing.T) {
	tmpDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(tmpDir, "hyprland.conf"), []byte("windowrulev2 = float, class:^(kitty)$\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	provider := NewHyprlandWritableProvider(tmpDir)
	rule := newTestWindowRule("test_id", "Test Rule", "^(firefox)$")
	rule.Actions.OpenFloating = new(true)

	err := provider.SetRule(rule)
	if err == nil {
		t.Fatal("expected SetRule to reject conf-only Hyprland config")
	}
	if !strings.Contains(err.Error(), "dms setup") {
		t.Fatalf("expected a run-dms-setup error, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(tmpDir, "dms", "windowrules.lua")); !os.IsNotExist(err) {
		t.Fatalf("expected no Lua windowrules file to be created for conf-only config, stat err=%v", err)
	}
}

func TestHyprlandRemoveRule(t *testing.T) {
	tmpDir := hyprLuaDir(t)
	provider := NewHyprlandWritableProvider(tmpDir)

	rule1 := newTestWindowRule("rule1", "Rule 1", "^(app1)$")
	rule1.Actions.OpenFloating = new(true)
	rule2 := newTestWindowRule("rule2", "Rule 2", "^(app2)$")
	rule2.Actions.OpenFloating = new(true)

	_ = provider.SetRule(rule1)
	_ = provider.SetRule(rule2)

	if err := provider.RemoveRule("rule1"); err != nil {
		t.Fatalf("RemoveRule failed: %v", err)
	}

	rules, _ := provider.LoadDMSRules()
	if len(rules) != 1 {
		t.Fatalf("expected 1 rule after removal, got %d", len(rules))
	}
	if rules[0].ID != "rule2" {
		t.Errorf("remaining rule ID = %q, want rule2", rules[0].ID)
	}
}

func TestHyprlandReorderRules(t *testing.T) {
	tmpDir := hyprLuaDir(t)
	provider := NewHyprlandWritableProvider(tmpDir)

	rule1 := newTestWindowRule("rule1", "Rule 1", "^(app1)$")
	rule1.Actions.OpenFloating = new(true)
	rule2 := newTestWindowRule("rule2", "Rule 2", "^(app2)$")
	rule2.Actions.OpenFloating = new(true)
	rule3 := newTestWindowRule("rule3", "Rule 3", "^(app3)$")
	rule3.Actions.OpenFloating = new(true)

	_ = provider.SetRule(rule1)
	_ = provider.SetRule(rule2)
	_ = provider.SetRule(rule3)

	if err := provider.ReorderRules([]string{"rule3", "rule1", "rule2"}); err != nil {
		t.Fatalf("ReorderRules failed: %v", err)
	}

	rules, _ := provider.LoadDMSRules()
	if len(rules) != 3 {
		t.Fatalf("expected 3 rules, got %d", len(rules))
	}
	expectedOrder := []string{"rule3", "rule1", "rule2"}
	for i, expectedID := range expectedOrder {
		if rules[i].ID != expectedID {
			t.Errorf("rule %d ID = %q, want %q", i, rules[i].ID, expectedID)
		}
	}
}

func TestParseHyprlandLuaRequiresFragment(t *testing.T) {
	tmpDir := t.TempDir()
	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0755); err != nil {
		t.Fatal(err)
	}

	mainLua := filepath.Join(tmpDir, "hyprland.lua")
	fragLua := filepath.Join(dmsDir, "windowrules.lua")

	if err := os.WriteFile(fragLua, []byte(`
hl.window_rule({ match = { class = "^test$" }, float = true })
`), 0644); err != nil {
		t.Fatal(err)
	}

	if err := os.WriteFile(mainLua, []byte(`
require("dms.windowrules")
`), 0644); err != nil {
		t.Fatal(err)
	}

	res, err := ParseHyprlandWindowRules(tmpDir)
	if err != nil {
		t.Fatalf("ParseHyprlandWindowRules: %v", err)
	}
	if len(res.Rules) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(res.Rules))
	}
	if !res.DMSRulesIncluded {
		t.Fatal("expected dms.windowrules fragment to be marked included")
	}
	wr := ConvertHyprlandRulesToWindowRules(res.Rules)[0]
	if wr.MatchCriteria.AppID != "^test$" || wr.Actions.OpenFloating == nil || !*wr.Actions.OpenFloating {
		t.Fatalf("unexpected merged rule: %#v", wr)
	}
}

func TestFormatLuaManagedHyprRuleUsesLuaFieldNames(t *testing.T) {
	enabled := true
	rule := windowrules.WindowRule{
		ID:      "test-rule",
		Enabled: true,
		MatchCriteria: windowrules.MatchCriteria{
			AppID: "^app$",
		},
		Actions: windowrules.Actions{
			NoFocus:     &enabled,
			NoShadow:    &enabled,
			NoDim:       &enabled,
			NoBlur:      &enabled,
			NoAnim:      &enabled,
			ForcergbX:   &enabled,
			Idleinhibit: "focus",
		},
	}

	lines := formatLuaManagedHyprRule(rule)
	joined := strings.Join(lines, "\n")
	for _, want := range []string{
		"no_focus = true",
		"no_shadow = true",
		"no_dim = true",
		"no_blur = true",
		"no_anim = true",
		"force_rgbx = true",
		`idle_inhibit = "focus"`,
	} {
		if !strings.Contains(joined, want) {
			t.Fatalf("formatted rule missing %q: %s", want, joined)
		}
	}
}

func TestLuaAppendActionsTableSyntax(t *testing.T) {
	actions := windowrules.Actions{
		SizeWidth:  "800",
		SizeHeight: "600",
		MoveX:      "100",
		MoveY:      "200",
	}

	var out []string
	luaAppendActions(actions, &out)
	joined := strings.Join(out, "\n")
	for _, want := range []string{
		`size = { 800, 600 }`,
		`move = { 100, 200 }`,
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("expected output to contain %q, got:\n%s", want, joined)
		}
	}
}

func TestLuaAppendActionsExprWrap(t *testing.T) {
	actions := windowrules.Actions{
		SizeWidth:  "window_w * 0.5",
		SizeHeight: "window_h - 50",
		MoveX:      "100",
		MoveY:      "(monitor_h / 2) + 17",
	}

	var out []string
	luaAppendActions(actions, &out)
	joined := strings.Join(out, "\n")
	for _, want := range []string{
		`size = { "window_w * 0.5", "window_h - 50" }`,
		`move = { 100, "(monitor_h / 2) + 17" }`,
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("expected output to contain %q, got:\n%s", want, joined)
		}
	}
}

func TestApplyLuaActionKeyTableSyntax(t *testing.T) {
	tests := []struct {
		name      string
		key       string
		raw       string
		wantSizeW string
		wantSizeH string
		wantMoveX string
		wantMoveY string
	}{
		{
			name:      "size table syntax",
			key:       "size",
			raw:       `{ 800, 600 }`,
			wantSizeW: "800",
			wantSizeH: "600",
		},
		{
			name:      "move table syntax",
			key:       "move",
			raw:       `{ 100, 200 }`,
			wantMoveX: "100",
			wantMoveY: "200",
		},
		{
			name: "size string syntax returns false",
			key:  "size",
			raw:  `"800x600"`,
		},
		{
			name:      "size expressions",
			key:       "size",
			raw:       `{ "window_w * 0.5", "window_h - 50" }`,
			wantSizeW: "window_w * 0.5",
			wantSizeH: "window_h - 50",
		},
		{
			name:      "move expressions",
			key:       "move",
			raw:       `{ 100, "(monitor_h / 2) + 17" }`,
			wantMoveX: "100",
			wantMoveY: "(monitor_h / 2) + 17",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var a windowrules.Actions
			result := applyLuaActionKey(&a, tt.key, tt.raw)
			if tt.wantSizeW == "" && tt.wantSizeH == "" && tt.wantMoveX == "" && tt.wantMoveY == "" {
				if result {
					t.Errorf("expected applyLuaActionKey to return false for string syntax, got true")
				}
				return
			}
			if !result {
				t.Fatal("applyLuaActionKey returned false")
			}
			if tt.wantSizeW != "" && a.SizeWidth != tt.wantSizeW {
				t.Errorf("SizeWidth = %q, want %q", a.SizeWidth, tt.wantSizeW)
			}
			if tt.wantSizeH != "" && a.SizeHeight != tt.wantSizeH {
				t.Errorf("SizeHeight = %q, want %q", a.SizeHeight, tt.wantSizeH)
			}
			if tt.wantMoveX != "" && a.MoveX != tt.wantMoveX {
				t.Errorf("MoveX = %q, want %q", a.MoveX, tt.wantMoveX)
			}
			if tt.wantMoveY != "" && a.MoveY != tt.wantMoveY {
				t.Errorf("MoveY = %q, want %q", a.MoveY, tt.wantMoveY)
			}
		})
	}
}

func TestFormatLuaManagedHyprRuleHyprlandKeyNames(t *testing.T) {
	rule := windowrules.WindowRule{
		ID:      "keys",
		Enabled: true,
		MatchCriteria: windowrules.MatchCriteria{
			AppID:       "^app$",
			IsFloating:  new(true),
			Pinned:      new(false),
			Initialised: new(true),
		},
		Actions: windowrules.Actions{
			NoBorder:     new(true),
			NoRounding:   new(true),
			CornerRadius: new(8),
		},
	}
	joined := strings.Join(formatLuaManagedHyprRule(rule), "\n")

	for _, want := range []string{"float = true", "pin = false", "border_size = 0"} {
		if got := strings.Count(joined, want); got != 1 {
			t.Errorf("%q appears %d times, want 1:\n%s", want, got, joined)
		}
	}
	if got := strings.Count(joined, "rounding = "); got != 1 {
		t.Errorf("rounding key appears %d times, want 1:\n%s", got, joined)
	}
	if !strings.Contains(joined, "rounding = 0") {
		t.Errorf("missing rounding = 0:\n%s", joined)
	}
	for _, bad := range []string{"floating", "pinned", "noborder", "norounding", "rounding = 8", "initialised"} {
		if strings.Contains(joined, bad) {
			t.Errorf("unexpected %q:\n%s", bad, joined)
		}
	}
}

func TestFormatLuaManagedHyprRuleCornerRadiusWithoutNoRounding(t *testing.T) {
	rule := windowrules.WindowRule{
		ID:      "radius",
		Enabled: true,
		Actions: windowrules.Actions{CornerRadius: new(8)},
	}
	joined := strings.Join(formatLuaManagedHyprRule(rule), "\n")
	if !strings.Contains(joined, "rounding = 8") {
		t.Errorf("missing rounding = 8:\n%s", joined)
	}
}

func TestFormatLuaManagedHyprRuleCornerRadiusCappedByVersion(t *testing.T) {
	prev := luaconfig.HyprlandVersion
	t.Cleanup(func() { luaconfig.HyprlandVersion = prev })
	rule := windowrules.WindowRule{
		ID:      "radius",
		Enabled: true,
		Actions: windowrules.Actions{CornerRadius: new(120)},
	}
	for minor, want := range map[int]string{56: "rounding = 20", 57: "rounding = 100"} {
		m := minor
		luaconfig.HyprlandVersion = func() (int, int) { return 0, m }
		joined := strings.Join(formatLuaManagedHyprRule(rule), "\n")
		if !strings.Contains(joined, want) {
			t.Errorf("0.%d: missing %s:\n%s", minor, want, joined)
		}
	}
}

func TestParseMatchLuaSpellings(t *testing.T) {
	tests := []struct {
		name         string
		in           string
		wantFloating *bool
		wantPinned   *bool
	}{
		{"floating", `{ floating = true }`, new(true), nil},
		{"float", `{ float = true }`, new(true), nil},
		{"float false", `{ float = false }`, new(false), nil},
		{"pinned", `{ pinned = true }`, nil, new(true)},
		{"pin", `{ pin = false }`, nil, new(false)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var m windowrules.MatchCriteria
			parseMatchLua(tt.in, &m)
			if (m.IsFloating == nil) != (tt.wantFloating == nil) || (m.IsFloating != nil && *m.IsFloating != *tt.wantFloating) {
				t.Errorf("floating = %v, want %v", m.IsFloating, tt.wantFloating)
			}
			if (m.Pinned == nil) != (tt.wantPinned == nil) || (m.Pinned != nil && *m.Pinned != *tt.wantPinned) {
				t.Errorf("pinned = %v, want %v", m.Pinned, tt.wantPinned)
			}
		})
	}
}

func TestParseMatchLuaStillReadsInitialised(t *testing.T) {
	var m windowrules.MatchCriteria
	parseMatchLua(`{ initialised = true }`, &m)
	if m.Initialised == nil || !*m.Initialised {
		t.Fatalf("initialised not parsed: %v", m.Initialised)
	}
}

func TestApplyLuaActionKeyBorderAndRounding(t *testing.T) {
	tests := []struct {
		name         string
		key, raw     string
		wantHandled  bool
		wantNoBorder bool
		wantNoRound  bool
		wantRadius   int
	}{
		{"noborder", "noborder", "true", true, true, false, 0},
		{"border_size 0", "border_size", "0", true, true, false, 0},
		{"border_size 2 unmanaged", "border_size", "2", false, false, false, 0},
		{"norounding", "norounding", "true", true, false, true, 0},
		{"rounding 0", "rounding", "0", true, false, true, 0},
		{"rounding 6", "rounding", "6", true, false, false, 6},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var a windowrules.Actions
			if got := applyLuaActionKey(&a, tt.key, tt.raw); got != tt.wantHandled {
				t.Fatalf("handled = %v, want %v", got, tt.wantHandled)
			}
			if gotB := a.NoBorder != nil && *a.NoBorder; gotB != tt.wantNoBorder {
				t.Errorf("NoBorder = %v, want %v", gotB, tt.wantNoBorder)
			}
			if gotR := a.NoRounding != nil && *a.NoRounding; gotR != tt.wantNoRound {
				t.Errorf("NoRounding = %v, want %v", gotR, tt.wantNoRound)
			}
			if tt.wantRadius == 0 {
				if a.CornerRadius != nil {
					t.Errorf("CornerRadius = %d, want nil", *a.CornerRadius)
				}
			} else if a.CornerRadius == nil || *a.CornerRadius != tt.wantRadius {
				t.Errorf("CornerRadius = %v, want %d", a.CornerRadius, tt.wantRadius)
			}
		})
	}
}

func TestHyprlandLuaRoundTripMatchAndActions(t *testing.T) {
	provider := NewHyprlandWritableProvider(hyprLuaDir(t))
	rule := newTestWindowRule("rt", "Round Trip", "^throwaway$")
	rule.MatchCriteria.IsFloating = new(true)
	rule.MatchCriteria.Pinned = new(false)
	rule.Actions.NoBorder = new(true)
	rule.Actions.NoRounding = new(true)
	rule.Actions.CornerRadius = new(8)

	if err := provider.SetRule(rule); err != nil {
		t.Fatalf("SetRule: %v", err)
	}
	rules, err := provider.LoadDMSRules()
	if err != nil {
		t.Fatalf("LoadDMSRules: %v", err)
	}
	if len(rules) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(rules))
	}
	got := rules[0]
	if got.MatchCriteria.IsFloating == nil || !*got.MatchCriteria.IsFloating {
		t.Errorf("IsFloating lost: %v", got.MatchCriteria.IsFloating)
	}
	if got.MatchCriteria.Pinned == nil || *got.MatchCriteria.Pinned {
		t.Errorf("Pinned lost: %v", got.MatchCriteria.Pinned)
	}
	if got.Actions.NoBorder == nil || !*got.Actions.NoBorder {
		t.Errorf("NoBorder lost")
	}
	if got.Actions.NoRounding == nil || !*got.Actions.NoRounding {
		t.Errorf("NoRounding lost")
	}
	if got.Actions.CornerRadius != nil {
		t.Errorf("CornerRadius = %d, want nil (suppressed by NoRounding)", *got.Actions.CornerRadius)
	}
}

func ruleOrder(t *testing.T, content string, ids ...string) {
	t.Helper()
	last := -1
	for _, id := range ids {
		i := strings.Index(content, id)
		if i < 0 || i < last {
			t.Fatalf("rule %q missing or out of order (want %v) in:\n%s", id, ids, content)
		}
		last = i
	}
}

func TestHyprlandEndToEndWriterOrderAndKeys(t *testing.T) {
	provider := NewHyprlandWritableProvider(hyprLuaDir(t))

	user1 := newTestWindowRule("user1", "User 1", "^throwaway$")
	user1.MatchCriteria.IsFloating = new(true)
	user1.Actions.NoBorder = new(true)
	user1.Actions.NoRounding = new(true)
	opaque := newTestWindowRule(windowrules.OpaqueRuleID, "Opaque", ".*")
	opaque.Actions.Opaque = new(true)
	user2 := newTestWindowRule("user2", "User 2", "^tiled$")
	user2.Actions.Tile = new(true)

	for _, r := range []windowrules.WindowRule{user1, opaque, user2} {
		if err := provider.SetRule(r); err != nil {
			t.Fatalf("SetRule %s: %v", r.ID, err)
		}
	}

	read := func() string {
		b, err := os.ReadFile(provider.GetOverridePath())
		if err != nil {
			t.Fatal(err)
		}
		return string(b)
	}
	content := read()
	for _, want := range []string{"float = true", "border_size = 0", "rounding = 0"} {
		if !strings.Contains(content, want) {
			t.Errorf("missing %q in:\n%s", want, content)
		}
	}
	for _, bad := range []string{"floating =", "noborder", "norounding"} {
		if strings.Contains(content, bad) {
			t.Errorf("unexpected %q in:\n%s", bad, content)
		}
	}
	ruleOrder(t, content, "user1", "user2", windowrules.OpaqueRuleID)

	if err := provider.ReorderRules([]string{"user2", "user1"}); err != nil {
		t.Fatalf("ReorderRules: %v", err)
	}
	ruleOrder(t, read(), "user2", "user1", windowrules.OpaqueRuleID)

	rules, err := provider.LoadDMSRules()
	if err != nil {
		t.Fatalf("LoadDMSRules: %v", err)
	}
	got := map[string]windowrules.WindowRule{}
	for _, r := range rules {
		got[r.ID] = r
	}
	if len(got) != 3 {
		t.Fatalf("expected 3 rules, got %d", len(got))
	}
	if a := got[windowrules.OpaqueRuleID].Actions.Opaque; a == nil || !*a {
		t.Error("opaque lost")
	}
	if a := got["user2"].Actions.Tile; a == nil || !*a {
		t.Error("tile lost")
	}
	if a := got["user1"].Actions.NoBorder; a == nil || !*a {
		t.Error("NoBorder lost")
	}
}

func TestNiriEndToEndOpaqueLast(t *testing.T) {
	provider := NewNiriWritableProvider(t.TempDir())
	opaque := newTestWindowRule(windowrules.OpaqueRuleID, "Opaque", ".*")
	opaque.Actions.Opacity = new(1.0)
	user := newTestWindowRule("user1", "User 1", "^a$")
	user.Actions.OpenFloating = new(true)

	for _, r := range []windowrules.WindowRule{opaque, user} {
		if err := provider.SetRule(r); err != nil {
			t.Fatalf("SetRule %s: %v", r.ID, err)
		}
	}
	b, err := os.ReadFile(provider.GetOverridePath())
	if err != nil {
		t.Fatal(err)
	}
	content := string(b)
	if !strings.Contains(content, "opacity 1.00") {
		t.Errorf("missing opacity 1.00 in:\n%s", content)
	}
	if strings.Index(content, "^a$") > strings.Index(content, "opacity 1.00") {
		t.Errorf("opaque rule not last in:\n%s", content)
	}
}

func TestHyprlandLuaRoundTripCatalogKeys(t *testing.T) {
	tests := []struct {
		name  string
		lua   string
		match windowrules.MatchCriteria
		act   windowrules.Actions
	}{
		{"initial_class", `initial_class = "^steam$"`, windowrules.MatchCriteria{InitialClass: "^steam$"}, windowrules.Actions{}},
		{"initial_title", `initial_title = "^Login$"`, windowrules.MatchCriteria{InitialTitle: "^Login$"}, windowrules.Actions{}},
		{"tag", `tag = "negative:games"`, windowrules.MatchCriteria{Tag: "negative:games"}, windowrules.Actions{}},
		{"workspace", `workspace = "w[tv1]"`, windowrules.MatchCriteria{Workspace: "w[tv1]"}, windowrules.Actions{}},
		{"content", `content = "video"`, windowrules.MatchCriteria{Content: "video"}, windowrules.Actions{}},
		{"xdg_tag", `xdg_tag = "^portal$"`, windowrules.MatchCriteria{XdgTag: "^portal$"}, windowrules.Actions{}},
		{"focus", `focus = false`, windowrules.MatchCriteria{IsFocused: new(false)}, windowrules.Actions{}},
		{"group", `group = true`, windowrules.MatchCriteria{Grouped: new(true)}, windowrules.Actions{}},
		{"modal", `modal = true`, windowrules.MatchCriteria{Modal: new(true)}, windowrules.Actions{}},
		{"fullscreen_state_internal", `fullscreen_state_internal = 2`, windowrules.MatchCriteria{FullscreenStateInternal: new(2)}, windowrules.Actions{}},
		{"fullscreen_state_client", `fullscreen_state_client = 0`, windowrules.MatchCriteria{FullscreenStateClient: new(0)}, windowrules.Actions{}},
		{"no_initial_focus", `no_initial_focus = true`, windowrules.MatchCriteria{}, windowrules.Actions{NoInitialFocus: new(true)}},
		{"focus_on_activate", `focus_on_activate = false`, windowrules.MatchCriteria{}, windowrules.Actions{FocusOnActivate: new(false)}},
		{"stay_focused", `stay_focused = true`, windowrules.MatchCriteria{}, windowrules.Actions{StayFocused: new(true)}},
		{"confine_pointer", `confine_pointer = true`, windowrules.MatchCriteria{}, windowrules.Actions{ConfinePointer: new(true)}},
		{"no_xdg_drags", `no_xdg_drags = true`, windowrules.MatchCriteria{}, windowrules.Actions{NoXdgDrags: new(true)}},
		{"no_auto_hdr", `no_auto_hdr = true`, windowrules.MatchCriteria{}, windowrules.Actions{NoAutoHDR: new(true)}},
		{"no_glow", `no_glow = true`, windowrules.MatchCriteria{}, windowrules.Actions{NoGlow: new(true)}},
		{"no_wobble", `no_wobble = true`, windowrules.MatchCriteria{}, windowrules.Actions{NoWobble: new(true)}},
		{"scrolling_width", `scrolling_width = 0.5`, windowrules.MatchCriteria{}, windowrules.Actions{ScrollingWidth: new(0.5)}},
		{"tonemap", `tonemap = "clamp"`, windowrules.MatchCriteria{}, windowrules.Actions{Tonemap: "clamp"}},
		{"suppress_event", `suppress_event = "maximize fullscreen"`, windowrules.MatchCriteria{}, windowrules.Actions{SuppressEvent: "maximize fullscreen"}},
		{"monitor silent", `monitor = "DP-1 silent"`, windowrules.MatchCriteria{}, windowrules.Actions{Monitor: "DP-1 silent"}},
		{"border_color per focus", `border_color = "rgb(ff0000)"`, windowrules.MatchCriteria{IsFocused: new(true)}, windowrules.Actions{BorderColor: "rgb(ff0000)"}},
		{"rounding at pre-0.57 cap", `rounding = 20`, windowrules.MatchCriteria{}, windowrules.Actions{CornerRadius: new(20)}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := NewHyprlandWritableProvider(hyprLuaDir(t))
			rule := newTestWindowRule("rt", "Round Trip", "^app$")
			tt.match.AppID = "^app$"
			rule.MatchCriteria = tt.match
			rule.Actions = tt.act
			if tt.act == (windowrules.Actions{}) {
				rule.Actions.OpenFloating = new(true)
			}
			if err := provider.SetRule(rule); err != nil {
				t.Fatalf("SetRule: %v", err)
			}
			written, err := os.ReadFile(provider.GetOverridePath())
			if err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(string(written), tt.lua) {
				t.Fatalf("missing %q in:\n%s", tt.lua, written)
			}
			rules, err := provider.LoadDMSRules()
			if err != nil || len(rules) != 1 {
				t.Fatalf("LoadDMSRules: %v, %d rules", err, len(rules))
			}
			if !reflect.DeepEqual(rules[0].MatchCriteria, rule.MatchCriteria) {
				t.Errorf("match = %+v, want %+v", rules[0].MatchCriteria, rule.MatchCriteria)
			}
			if !reflect.DeepEqual(rules[0].Actions, rule.Actions) {
				t.Errorf("actions = %+v, want %+v", rules[0].Actions, rule.Actions)
			}
		})
	}
}

func TestHyprlandNoInitialFocusStaysDistinct(t *testing.T) {
	tmpDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(tmpDir, "hyprland.lua"), []byte(`
hl.window_rule({
	match = { class = "^steam$" },
	no_initial_focus = true,
})
`), 0644); err != nil {
		t.Fatal(err)
	}
	res, err := ParseHyprlandWindowRules(tmpDir)
	if err != nil || len(res.Rules) != 1 {
		t.Fatalf("ParseHyprlandWindowRules: %v, %d rules", err, len(res.Rules))
	}
	wr := ConvertHyprlandRulesToWindowRules(res.Rules)[0]
	if wr.Actions.NoFocus != nil {
		t.Errorf("no_initial_focus leaked into NoFocus")
	}
	joined := strings.Join(formatLuaManagedHyprRule(wr), "\n")
	if !strings.Contains(joined, "no_initial_focus = true") || strings.Contains(joined, "no_focus") {
		t.Errorf("no_initial_focus not re-emitted unchanged:\n%s", joined)
	}
}

func hyprLuaDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "hyprland.lua"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}
