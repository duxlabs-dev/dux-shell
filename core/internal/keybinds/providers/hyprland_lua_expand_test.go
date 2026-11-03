package providers

import (
	"strings"
	"testing"
)

func TestExpandLuaConfigLinesForLoop(t *testing.T) {
	lines := []string{
		`local mainMod = "SUPER"`,
		`for i = 1, 3 do`,
		`    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({workspace = tostring(i)}))`,
		`    hl.bind(mainMod .. " SHIFT + " .. i, hl.dsp.window.move({workspace = tostring(i)}))`,
		`end`,
	}
	got := strings.Join(expandLuaConfigLines(lines), "\n")

	for _, w := range []string{
		`hl.bind("SUPER + 1",`,
		`hl.bind("SUPER + 2",`,
		`hl.bind("SUPER + 3",`,
		`hl.bind("SUPER SHIFT + 3",`,
		`{workspace = "1"}`,
	} {
		if !strings.Contains(got, w) {
			t.Errorf("expanded loop missing %q\n---\n%s", w, got)
		}
	}
}

func TestParseLuaLinesDynamicBinds(t *testing.T) {
	content := strings.Join([]string{
		`local mainMod = "SUPER"`,
		`hl.bind(mainMod .. " + C", hl.dsp.window.close())`,
		`hl.bind("ALT + TAB", hl.dsp.window.cycle_next({}))`,
		`for i = 1, 2 do`,
		`    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({workspace = tostring(i)}))`,
		`end`,
	}, "\n")

	parser := NewHyprlandParser("")
	section, err := parser.parseLuaLines(content, "", "test.lua", "")
	if err != nil {
		t.Fatalf("parseLuaLines: %v", err)
	}

	keys := map[string]*HyprlandKeyBinding{}
	for i := range section.Keybinds {
		kb := &section.Keybinds[i]
		keys[parser.formatBindKey(kb)] = kb
	}

	for _, want := range []string{"SUPER+C", "ALT+TAB", "SUPER+1", "SUPER+2"} {
		if _, ok := keys[want]; !ok {
			t.Errorf("missing bind %q; got %v", want, keysList(keys))
		}
	}
	if kb := keys["SUPER+C"]; kb != nil && kb.Dispatcher != "killactive" {
		t.Errorf("SUPER+C dispatcher = %q, want killactive", kb.Dispatcher)
	}
	if kb := keys["SUPER+1"]; kb != nil {
		if kb.Dispatcher != "workspace" || kb.Params != "1" {
			t.Errorf("SUPER+1 = %q %q, want workspace 1", kb.Dispatcher, kb.Params)
		}
	}
}

func keysList(m map[string]*HyprlandKeyBinding) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

func TestEvalLuaConcat(t *testing.T) {
	env := luaVarEnv{"mainMod": "SUPER", "i": "5"}
	tests := []struct {
		expr string
		want string
		ok   bool
	}{
		{`mainMod .. " + C"`, "SUPER + C", true},
		{`mainMod .. " + " .. i`, "SUPER + 5", true},
		{`mainMod .. " + " .. tostring(i)`, "SUPER + 5", true},
		{`"ALT + TAB"`, "ALT + TAB", true},
		{`mainMod .. someFunc()`, "", false},
		{`unknownVar .. "x"`, "", false},
	}
	for _, tt := range tests {
		got, ok := evalLuaConcat(tt.expr, env)
		if ok != tt.ok || (ok && got != tt.want) {
			t.Errorf("evalLuaConcat(%q) = %q,%v want %q,%v", tt.expr, got, ok, tt.want, tt.ok)
		}
	}
}

func TestSubstituteLuaIdent(t *testing.T) {
	tests := []struct {
		line, name, value, want string
	}{
		{`hl.bind(m .. " + " .. i, x)`, "i", "3", `hl.bind(m .. " + " .. 3, x)`},
		{`hl.dsp.exec("light -i")`, "i", "3", `hl.dsp.exec("light -i")`},
		{`foo.i`, "i", "3", `foo.i`},
		{`tostring(i)`, "i", "3", `tostring(3)`},
	}
	for _, tt := range tests {
		if got := substituteLuaIdent(tt.line, tt.name, tt.value); got != tt.want {
			t.Errorf("substituteLuaIdent(%q,%q,%q) = %q, want %q", tt.line, tt.name, tt.value, got, tt.want)
		}
	}
}
