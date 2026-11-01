package providers

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/windowrules"
)

func TestParseMangoWindowRuleLineSplitsFields(t *testing.T) {
	for _, line := range []string{
		"app_id:firefox,title:Gmail,is_floating:1,tags:2,monitor:HDMI-A-1",
		"app_id: firefox , title:Gmail,is_floating:1,tags:2,monitor:HDMI-A-1",
	} {
		fields := parseMangoWindowRuleLine(line)
		want := map[string]string{"app_id": "firefox", "title": "Gmail", "is_floating": "1", "tags": "2", "monitor": "HDMI-A-1"}
		for k, v := range want {
			if fields[k] != v {
				t.Errorf("%s: %s = %q, want %q", line, k, fields[k], v)
			}
		}
	}
}

func TestMangoRulesWrittenInSnakeCase(t *testing.T) {
	floating := true
	rule := windowrules.WindowRule{MatchCriteria: windowrules.MatchCriteria{AppID: "discord"}, Actions: windowrules.Actions{OpenFloating: &floating, NoAnim: &floating}}
	if got, want := formatMangoRule(rule), "window_rule=app_id:discord,is_floating:1,no_animation:1"; got != want {
		t.Errorf("snake = %q, want %q", got, want)
	}

	dir := t.TempDir()
	rulesPath := filepath.Join(dir, "dms", "windowrules.conf")
	_ = os.MkdirAll(filepath.Dir(rulesPath), 0o755)
	_ = os.WriteFile(rulesPath, []byte("# @id=a @name=A\nwindow_rule=app_id:discord,is_floating:1\n"), 0o644)
	loaded, err := (&MangoWritableProvider{configDir: dir}).LoadDMSRules()
	if err != nil || len(loaded) != 1 || loaded[0].MatchCriteria.AppID != "discord" || loaded[0].Actions.OpenFloating == nil {
		t.Fatalf("snake rule not loaded: %+v, %v", loaded, err)
	}
}

func TestConvertMangoRulesToWindowRules(t *testing.T) {
	mangoRules := []MangoWindowRule{
		{Source: "config.conf", Fields: parseMangoWindowRuleLine("app_id:discord,tags:9,is_floating:1,no_blur:1")},
	}
	rules := ConvertMangoRulesToWindowRules(mangoRules)
	if len(rules) != 1 {
		t.Fatalf("got %d rules, want 1", len(rules))
	}
	r := rules[0]
	if r.MatchCriteria.AppID != "discord" {
		t.Errorf("AppID = %q, want discord", r.MatchCriteria.AppID)
	}
	if r.Actions.Workspace != "9" {
		t.Errorf("Workspace = %q, want 9", r.Actions.Workspace)
	}
	if r.Actions.OpenFloating == nil || !*r.Actions.OpenFloating {
		t.Errorf("OpenFloating = %v, want true", r.Actions.OpenFloating)
	}
	if r.Actions.NoBlur == nil || !*r.Actions.NoBlur {
		t.Errorf("NoBlur = %v, want true", r.Actions.NoBlur)
	}
}

func TestMangoSetAndLoadRoundTrip(t *testing.T) {
	tmpDir := t.TempDir()
	provider := NewMangoWritableProvider(tmpDir)

	floating := true
	rule := windowrules.WindowRule{
		ID:      "rule_test",
		Name:    "Float Discord",
		Enabled: true,
		MatchCriteria: windowrules.MatchCriteria{
			AppID: "discord",
		},
		Actions: windowrules.Actions{
			OpenFloating: &floating,
			Workspace:    "9",
			SizeWidth:    "1000",
			SizeHeight:   "900",
		},
	}

	if err := provider.SetRule(rule); err != nil {
		t.Fatalf("SetRule: %v", err)
	}

	expectedPath := filepath.Join(tmpDir, "dms", "windowrules.conf")
	if _, err := os.Stat(expectedPath); err != nil {
		t.Fatalf("override file not written: %v", err)
	}

	loaded, err := provider.LoadDMSRules()
	if err != nil {
		t.Fatalf("LoadDMSRules: %v", err)
	}
	if len(loaded) != 1 {
		t.Fatalf("got %d rules, want 1", len(loaded))
	}
	got := loaded[0]
	if got.ID != "rule_test" {
		t.Errorf("ID = %q, want rule_test", got.ID)
	}
	if got.Name != "Float Discord" {
		t.Errorf("Name = %q, want 'Float Discord'", got.Name)
	}
	if got.MatchCriteria.AppID != "discord" {
		t.Errorf("AppID = %q, want discord", got.MatchCriteria.AppID)
	}
	if got.Actions.Workspace != "9" {
		t.Errorf("Workspace = %q, want 9", got.Actions.Workspace)
	}
	if got.Actions.SizeWidth != "1000" {
		t.Errorf("SizeWidth = %q, want 1000", got.Actions.SizeWidth)
	}
	if got.Actions.SizeHeight != "900" {
		t.Errorf("SizeHeight = %q, want 900", got.Actions.SizeHeight)
	}
	if got.Actions.OpenFloating == nil || !*got.Actions.OpenFloating {
		t.Errorf("OpenFloating = %v, want true", got.Actions.OpenFloating)
	}

	// Remove and confirm empty.
	if err := provider.RemoveRule("rule_test"); err != nil {
		t.Fatalf("RemoveRule: %v", err)
	}
	loaded, _ = provider.LoadDMSRules()
	if len(loaded) != 0 {
		t.Errorf("after remove got %d rules, want 0", len(loaded))
	}
}

func TestMangoRuleSaveKeepsUnmodeledFieldsAndOnceRules(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "dms", "windowrules.conf")
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	_ = os.WriteFile(path, []byte("# @id=a @name=A\nwindow_rule=app_id:mpv,is_global:1,offset_x:20,width:0.5\nwindow_rule_once=app_id:firefox,tags:2\n"), 0o644)

	p := &MangoWritableProvider{configDir: dir}
	floating := true
	if err := p.SetRule(windowrules.WindowRule{ID: "b", Name: "B", MatchCriteria: windowrules.MatchCriteria{AppID: "foot"}, Actions: windowrules.Actions{OpenFloating: &floating}}); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	got := string(data)
	for _, want := range []string{
		"window_rule=app_id:mpv,is_global:1,offset_x:20,width:0.5\n",
		"window_rule=app_id:foot,is_floating:1\n",
		"window_rule_once=app_id:firefox,tags:2\n",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}

	long := windowrules.WindowRule{ID: "c", MatchCriteria: windowrules.MatchCriteria{Title: strings.Repeat("x", 300)}}
	if err := p.SetRule(long); err == nil {
		t.Error("a rule Mango would truncate must be rejected")
	}
}
