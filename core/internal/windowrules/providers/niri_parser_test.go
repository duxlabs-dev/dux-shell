package providers

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/windowrules"
)

func TestNiriParseBasicWindowRule(t *testing.T) {
	tmpDir := t.TempDir()

	config := `
window-rule {
    match app-id="^firefox$"
    opacity 0.9
    open-floating true
}
`
	if err := os.WriteFile(filepath.Join(tmpDir, "config.kdl"), []byte(config), 0644); err != nil {
		t.Fatal(err)
	}

	parser := NewNiriRulesParser(tmpDir)
	rules, err := parser.Parse()
	if err != nil {
		t.Fatalf("Parse failed: %v", err)
	}

	if len(rules) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(rules))
	}

	rule := rules[0]
	if rule.MatchAppID != "^firefox$" {
		t.Errorf("MatchAppID = %q, want ^firefox$", rule.MatchAppID)
	}
	if rule.Opacity == nil || *rule.Opacity != 0.9 {
		t.Errorf("Opacity = %v, want 0.9", rule.Opacity)
	}
	if rule.OpenFloating == nil || !*rule.OpenFloating {
		t.Error("OpenFloating should be true")
	}
}

func TestNiriSetAndLoadDMSRules(t *testing.T) {
	tmpDir := t.TempDir()
	provider := NewNiriWritableProvider(tmpDir)

	rule := newTestWindowRule("test_id", "Test Rule", "^firefox$")
	rule.Actions.OpenFloating = new(true)
	rule.Actions.Opacity = new(0.85)

	if err := provider.SetRule(rule); err != nil {
		t.Fatalf("SetRule failed: %v", err)
	}

	rules, err := provider.LoadDMSRules()
	if err != nil {
		t.Fatalf("LoadDMSRules failed: %v", err)
	}

	if len(rules) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(rules))
	}

	if rules[0].ID != "test_id" {
		t.Errorf("ID = %q, want test_id", rules[0].ID)
	}
	if rules[0].MatchCriteria.AppID != "^firefox$" {
		t.Errorf("AppID = %q, want ^firefox$", rules[0].MatchCriteria.AppID)
	}
}

func TestNiriParseConfigWithInclude(t *testing.T) {
	tmpDir := t.TempDir()

	mainConfig := `
window-rule {
    match app-id="mainapp"
    opacity 1.0
}

include "extra.kdl"
`
	extraConfig := `
window-rule {
    match app-id="extraapp"
    open-maximized true
}
`

	if err := os.WriteFile(filepath.Join(tmpDir, "config.kdl"), []byte(mainConfig), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "extra.kdl"), []byte(extraConfig), 0644); err != nil {
		t.Fatal(err)
	}

	parser := NewNiriRulesParser(tmpDir)
	rules, err := parser.Parse()
	if err != nil {
		t.Fatalf("Parse failed: %v", err)
	}

	if len(rules) != 2 {
		t.Errorf("expected 2 rules, got %d", len(rules))
	}
}

func TestNiriParseSizeNode(t *testing.T) {
	tmpDir := t.TempDir()

	config := `
window-rule {
    match app-id="testapp"
    default-column-width { fixed 800; }
    default-window-height { proportion 0.5; }
}
`
	if err := os.WriteFile(filepath.Join(tmpDir, "config.kdl"), []byte(config), 0644); err != nil {
		t.Fatal(err)
	}

	parser := NewNiriRulesParser(tmpDir)
	rules, err := parser.Parse()
	if err != nil {
		t.Fatalf("Parse failed: %v", err)
	}

	if len(rules) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(rules))
	}

	if rules[0].DefaultColumnWidth != "fixed 800" {
		t.Errorf("DefaultColumnWidth = %q, want 'fixed 800'", rules[0].DefaultColumnWidth)
	}
	if rules[0].DefaultWindowHeight != "proportion 0.5" {
		t.Errorf("DefaultWindowHeight = %q, want 'proportion 0.5'", rules[0].DefaultWindowHeight)
	}
}

func TestFormatSizeProperty(t *testing.T) {
	tests := []struct {
		name     string
		propName string
		value    string
		want     string
	}{
		{
			name:     "fixed size",
			propName: "default-column-width",
			value:    "fixed 800",
			want:     "    default-column-width { fixed 800; }",
		},
		{
			name:     "proportion",
			propName: "default-window-height",
			value:    "proportion 0.5",
			want:     "    default-window-height { proportion 0.5; }",
		},
		{
			name:     "invalid format",
			propName: "default-column-width",
			value:    "invalid",
			want:     "    default-column-width { }",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := formatSizeProperty(tt.propName, tt.value)
			if result != tt.want {
				t.Errorf("formatSizeProperty(%q, %q) = %q, want %q",
					tt.propName, tt.value, result, tt.want)
			}
		})
	}
}

func TestNiriExcludesSurviveEditOfOtherRule(t *testing.T) {
	tmpDir := t.TempDir()
	provider := NewNiriWritableProvider(tmpDir)

	dmsDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(dmsDir, 0755); err != nil {
		t.Fatal(err)
	}
	existing := `// @id=thunderbird @name=Thunderbird
window-rule {
    match app-id="^org.mozilla.Thunderbird$"
    open-floating true
    exclude title="^Mozilla Thunderbird$"
    exclude title="^Verfassen:.*"
}

// @id=firefox @name=Firefox
window-rule {
    match app-id="^firefox$"
    open-floating true
}
`
	if err := os.WriteFile(filepath.Join(dmsDir, "windowrules.kdl"), []byte(existing), 0644); err != nil {
		t.Fatal(err)
	}

	edited := newTestWindowRule("firefox", "Firefox", "^firefox$")
	edited.Actions.OpenFloating = new(false)
	if err := provider.SetRule(edited); err != nil {
		t.Fatalf("SetRule failed: %v", err)
	}

	rules, err := provider.LoadDMSRules()
	if err != nil {
		t.Fatalf("LoadDMSRules failed: %v", err)
	}
	if len(rules) != 2 {
		t.Fatalf("expected 2 rules, got %d", len(rules))
	}
	if len(rules[0].Excludes) != 2 {
		t.Fatalf("expected 2 excludes on untouched rule, got %d", len(rules[0].Excludes))
	}
	if rules[0].Excludes[0].Title != "^Mozilla Thunderbird$" {
		t.Errorf("Excludes[0].Title = %q", rules[0].Excludes[0].Title)
	}
	if rules[0].Excludes[1].Title != "^Verfassen:.*" {
		t.Errorf("Excludes[1].Title = %q", rules[0].Excludes[1].Title)
	}
	if rules[1].Actions.OpenFloating == nil || *rules[1].Actions.OpenFloating {
		t.Error("edited rule should have open-floating false")
	}
}

func TestNiriParseIncludeNestedDMSRules(t *testing.T) {
	tmpDir := t.TempDir()
	subDir := filepath.Join(tmpDir, "dms")
	if err := os.MkdirAll(subDir, 0o755); err != nil {
		t.Fatal(err)
	}

	files := map[string]string{
		filepath.Join(tmpDir, "config.kdl"):      "include \"dms/dms.kdl\"\n",
		filepath.Join(subDir, "dms.kdl"):         "include \"windowrules.kdl\"\n",
		filepath.Join(subDir, "windowrules.kdl"): "window-rule {\n    match app-id=\"nested\"\n    opacity 0.9\n}\n",
	}
	for path, content := range files {
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	result, err := ParseNiriWindowRules(tmpDir)
	if err != nil {
		t.Fatalf("ParseNiriWindowRules failed: %v", err)
	}
	if !result.DMSRulesIncluded {
		t.Error("dms/windowrules.kdl included via dms/dms.kdl not detected")
	}
	if len(result.Rules) != 1 {
		t.Errorf("expected 1 rule from the nested include, got %d", len(result.Rules))
	}
}

func TestNiriNextOnlyActionsRoundTrip(t *testing.T) {
	existing := `// @id=game @name=Game
window-rule {
    match app-id="^steam_app_.*$"
    variable-refresh-rate "fullscreen-only"
}

// @id=pip @name=PiP
window-rule {
    match title="^Picture-in-Picture$"
    on-xdg-activate "set-urgent"
    pinch-sensitivity 0.5
}

// @id=firefox @name=Firefox
window-rule {
    match app-id="^firefox$"
    open-floating true
}
`
	tests := []struct {
		name     string
		capable  bool
		wantKDL  []string
		wantGone []string
	}{
		{
			name:    "capable niri keeps them",
			capable: true,
			wantKDL: []string{`variable-refresh-rate "fullscreen-only"`, `on-xdg-activate "set-urgent"`, "pinch-sensitivity 0.5"},
		},
		{
			name:     "niri 26.04 drops them",
			wantGone: []string{"variable-refresh-rate", "on-xdg-activate", "pinch-sensitivity"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			orig := niriConfigNext
			niriConfigNext = func() bool { return tt.capable }
			t.Cleanup(func() { niriConfigNext = orig })

			tmpDir := t.TempDir()
			rulesPath := filepath.Join(tmpDir, "dms", "windowrules.kdl")
			if err := os.MkdirAll(filepath.Dir(rulesPath), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(rulesPath, []byte(existing), 0o644); err != nil {
				t.Fatal(err)
			}
			provider := NewNiriWritableProvider(tmpDir)

			rules, err := provider.LoadDMSRules()
			if err != nil {
				t.Fatalf("LoadDMSRules failed: %v", err)
			}
			game, pip := rules[0].Actions, rules[1].Actions
			if game.VrrFullscreenOnly == nil || !*game.VrrFullscreenOnly || game.VariableRefreshRate != nil {
				t.Errorf("fullscreen-only parsed as vrrFullscreenOnly=%v variableRefreshRate=%v", game.VrrFullscreenOnly, game.VariableRefreshRate)
			}
			if pip.OnXdgActivate != "set-urgent" || pip.PinchSensitivity == nil || *pip.PinchSensitivity != 0.5 {
				t.Errorf("onXdgActivate=%q pinchSensitivity=%v", pip.OnXdgActivate, pip.PinchSensitivity)
			}

			edited := newTestWindowRule("firefox", "Firefox", "^firefox$")
			edited.Actions.OpenFloating = new(false)
			if err := provider.SetRule(edited); err != nil {
				t.Fatalf("SetRule failed: %v", err)
			}

			data, err := os.ReadFile(rulesPath)
			if err != nil {
				t.Fatal(err)
			}
			written := string(data)
			for _, want := range tt.wantKDL {
				if !strings.Contains(written, want) {
					t.Errorf("written rules miss %q:\n%s", want, written)
				}
			}
			for _, gone := range tt.wantGone {
				if strings.Contains(written, gone) {
					t.Errorf("written rules keep %q:\n%s", gone, written)
				}
			}
		})
	}
}

func TestNiriRejectedRuleKeepsThePriorFragment(t *testing.T) {
	prior := `// @id=firefox @name=Firefox
window-rule {
    match app-id="^firefox$"
    open-floating true
}
`
	tests := []struct {
		name      string
		edit      func(*windowrules.Actions)
		validator error
	}{
		{name: "negative pinch sensitivity", edit: func(a *windowrules.Actions) { a.PinchSensitivity = new(-1.0) }},
		{name: "pinch sensitivity above 100", edit: func(a *windowrules.Actions) { a.PinchSensitivity = new(101.0) }},
		{name: "negative scroll factor", edit: func(a *windowrules.Actions) { a.ScrollFactor = new(-0.5) }},
		{name: "niri validate rejects", edit: func(a *windowrules.Actions) {}, validator: errors.New("bad regex")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			origNext, origValidate := niriConfigNext, niriValidateRules
			niriConfigNext = func() bool { return true }
			niriValidateRules = func(string) error { return tt.validator }
			t.Cleanup(func() { niriConfigNext, niriValidateRules = origNext, origValidate })

			tmpDir := t.TempDir()
			rulesPath := filepath.Join(tmpDir, "dms", "windowrules.kdl")
			if err := os.MkdirAll(filepath.Dir(rulesPath), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(rulesPath, []byte(prior), 0o644); err != nil {
				t.Fatal(err)
			}

			rule := newTestWindowRule("pip", "PiP", "^mpv$")
			tt.edit(&rule.Actions)
			if err := NewNiriWritableProvider(tmpDir).SetRule(rule); err == nil {
				t.Fatal("SetRule succeeded, want an error")
			}

			data, err := os.ReadFile(rulesPath)
			if err != nil {
				t.Fatal(err)
			}
			if string(data) != prior {
				t.Errorf("prior fragment changed:\n%s", data)
			}
		})
	}
}
