package main

import (
	"reflect"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/dmenuipc"
)

func TestParseIndexSpec(t *testing.T) {
	for _, tc := range []struct {
		spec    string
		want    []dmenuipc.Range
		wantErr bool
	}{
		{"", nil, false},
		{"1,3", []dmenuipc.Range{{Start: 1, End: 2}, {Start: 3, End: 4}}, false},
		{"7:11", []dmenuipc.Range{{Start: 7, End: 11}}, false},
		{"-3:", []dmenuipc.Range{{Start: -3, End: -1}}, false},
		{":5", []dmenuipc.Range{{Start: 0, End: 5}}, false},
		{"1, 3 , 7:11", []dmenuipc.Range{{Start: 1, End: 2}, {Start: 3, End: 4}, {Start: 7, End: 11}}, false},
		{"1,,3", []dmenuipc.Range{{Start: 1, End: 2}, {Start: 3, End: 4}}, false},
		{"x", nil, true},
		{"1:y", nil, true},
		{"x:1", nil, true},
	} {
		got, err := parseIndexSpec(tc.spec)
		if tc.wantErr {
			if err == nil {
				t.Errorf("parseIndexSpec(%q): expected error, got %v", tc.spec, got)
			}
			continue
		}
		if err != nil {
			t.Errorf("parseIndexSpec(%q): unexpected error: %v", tc.spec, err)
			continue
		}
		if !reflect.DeepEqual(got, tc.want) {
			t.Errorf("parseIndexSpec(%q) = %+v, want %+v", tc.spec, got, tc.want)
		}
	}
}

func TestParseDmenuKeybinds(t *testing.T) {
	for _, tc := range []struct {
		name    string
		specs   []string
		want    []dmenuipc.Keybind
		wantErr bool
	}{
		{"empty", nil, nil, false},
		{"multiple", []string{"1=ctrl+e", "2=f5"}, []dmenuipc.Keybind{{N: 1, Key: "ctrl+e"}, {N: 2, Key: "f5"}}, false},
		{"missing equals", []string{"bad"}, nil, true},
		{"zero index", []string{"0=x"}, nil, true},
		{"out of range index", []string{"20=x"}, nil, true},
		{"empty key spec", []string{"1="}, nil, true},
		{"duplicate index", []string{"1=ctrl+e", "1=f5"}, nil, true},
		{"non numeric index", []string{"a=x"}, nil, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseDmenuKeybinds(tc.specs)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("parseDmenuKeybinds(%v): expected error, got %v", tc.specs, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("parseDmenuKeybinds(%v): unexpected error: %v", tc.specs, err)
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("parseDmenuKeybinds(%v) = %+v, want %+v", tc.specs, got, tc.want)
			}
		})
	}
}

func TestDmenuParseBool(t *testing.T) {
	for _, tc := range []struct {
		val  string
		want bool
	}{
		{"", false},
		{"0", false},
		{"false", false},
		{"False", false},
		{"no", false},
		{"anything-else", true},
	} {
		if got := dmenuParseBool(tc.val); got != tc.want {
			t.Errorf("dmenuParseBool(%q) = %v, want %v", tc.val, got, tc.want)
		}
	}
}

func TestParseDmenuRow(t *testing.T) {
	t.Run("plain text, no metadata", func(t *testing.T) {
		text, meta := parseDmenuRow("apple")
		if text != "apple" || meta != nil {
			t.Fatalf("parseDmenuRow(apple) = %q, %+v, want apple, nil", text, meta)
		}
	})

	t.Run("single field", func(t *testing.T) {
		text, meta := parseDmenuRow("Firefox\x00icon\x1ffirefox")
		if text != "Firefox" {
			t.Fatalf("text = %q, want Firefox", text)
		}
		if meta == nil || meta.Icon != "firefox" {
			t.Fatalf("meta = %+v, want Icon=firefox", meta)
		}
	})

	t.Run("all recognized fields", func(t *testing.T) {
		line := "Firefox\x00icon\x1ffirefox\x1fdisplay\x1fMozilla Firefox\x1fmeta\x1fbrowser\x1finfo\x1ffirefox.desktop" +
			"\x1fnonselectable\x1ftrue\x1furgent\x1ftrue\x1factive\x1ftrue\x1fpermanent\x1ftrue\x1fheader\x1ftrue"
		text, meta := parseDmenuRow(line)
		want := dmenuipc.ItemMeta{
			Icon: "firefox", Display: "Mozilla Firefox", Meta: "browser", Info: "firefox.desktop",
			NonSelectable: true, Urgent: true, Active: true, Permanent: true, Header: true,
		}
		if text != "Firefox" {
			t.Fatalf("text = %q, want Firefox", text)
		}
		if meta == nil || *meta != want {
			t.Fatalf("meta = %+v, want %+v", meta, want)
		}
	})

	t.Run("unknown field ignored but still produces meta", func(t *testing.T) {
		text, meta := parseDmenuRow("apple\x00bogus\x1fvalue")
		if text != "apple" {
			t.Fatalf("text = %q, want apple", text)
		}
		if meta != nil {
			t.Fatalf("meta = %+v, want nil (no recognized fields)", meta)
		}
	})

	t.Run("dangling unpaired field ignored", func(t *testing.T) {
		text, meta := parseDmenuRow("apple\x00icon\x1ffirefox\x1fdangling")
		if text != "apple" {
			t.Fatalf("text = %q, want apple", text)
		}
		if meta == nil || meta.Icon != "firefox" {
			t.Fatalf("meta = %+v, want Icon=firefox", meta)
		}
	})
}

func TestValidateDmenuFormat(t *testing.T) {
	for _, f := range []string{"", "s", "i", "d", "q", "p", "f", "F"} {
		if err := validateDmenuFormat(f); err != nil {
			t.Errorf("validateDmenuFormat(%q): unexpected error: %v", f, err)
		}
	}
	for _, f := range []string{"x", "S", "ff"} {
		if err := validateDmenuFormat(f); err == nil {
			t.Errorf("validateDmenuFormat(%q): expected error, got nil", f)
		}
	}
}

func TestValidateDmenuView(t *testing.T) {
	for _, v := range []string{"", "list", "grid", "tile"} {
		if err := validateDmenuView(v); err != nil {
			t.Errorf("validateDmenuView(%q): unexpected error: %v", v, err)
		}
	}
	for _, v := range []string{"bogus", "List"} {
		if err := validateDmenuView(v); err == nil {
			t.Errorf("validateDmenuView(%q): expected error, got nil", v)
		}
	}
}

func TestDmenuShellQuote(t *testing.T) {
	for _, tc := range []struct {
		in   string
		want string
	}{
		{"banana", "'banana'"},
		{"it's", `'it'\''s'`},
		{"", "''"},
	} {
		if got := dmenuShellQuote(tc.in); got != tc.want {
			t.Errorf("dmenuShellQuote(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestDmenuFormatOutput(t *testing.T) {
	for _, tc := range []struct {
		format     string
		index      int
		text       string
		filterText string
		want       string
		wantErr    bool
	}{
		{"", 1, "banana", "ban", "banana", false},
		{"s", 1, "banana", "ban", "banana", false},
		{"i", 1, "banana", "ban", "1", false},
		{"d", 1, "banana", "ban", "2", false},
		{"d", -1, "banana", "xyz", "-1", false},
		{"q", 0, "it's", "", "'it'\\''s'", false},
		{"p", 0, "<b>Bold</b> item", "", "Bold item", false},
		{"f", 0, "banana", "ban", "ban", false},
		{"F", 0, "banana", "it's", "'it'\\''s'", false},
		{"bogus", 0, "banana", "", "", true},
	} {
		got, err := dmenuFormatOutput(tc.format, tc.index, tc.text, tc.filterText)
		if tc.wantErr {
			if err == nil {
				t.Errorf("dmenuFormatOutput(%q, ...): expected error, got %q", tc.format, got)
			}
			continue
		}
		if err != nil {
			t.Errorf("dmenuFormatOutput(%q, ...): unexpected error: %v", tc.format, err)
			continue
		}
		if got != tc.want {
			t.Errorf("dmenuFormatOutput(%q, %d, %q, %q) = %q, want %q", tc.format, tc.index, tc.text, tc.filterText, got, tc.want)
		}
	}
}

func TestDmenuDumpLines(t *testing.T) {
	rows := []dmenuRow{
		{Text: "Header", Meta: &dmenuipc.ItemMeta{Header: true}},
		{Text: "Firefox", Meta: &dmenuipc.ItemMeta{Info: "firefox.desktop"}},
		{Text: "apple"},
		{Text: "skip", Meta: &dmenuipc.ItemMeta{NonSelectable: true}},
		{Text: "banana"},
	}

	t.Run("no filter, default format", func(t *testing.T) {
		got, err := dmenuDumpLines(rows, "", "s", false)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		want := []string{"Firefox", "apple", "banana"}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("got %v, want %v", got, want)
		}
	})

	t.Run("with select filter", func(t *testing.T) {
		got, err := dmenuDumpLines(rows, "an", "s", false)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		want := []string{"banana"}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("got %v, want %v", got, want)
		}
	})

	t.Run("print-info appends info lines", func(t *testing.T) {
		got, err := dmenuDumpLines(rows, "", "s", true)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		want := []string{"Firefox", "firefox.desktop", "apple", "banana"}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("got %v, want %v", got, want)
		}
	})

	t.Run("invalid format propagates error", func(t *testing.T) {
		if _, err := dmenuDumpLines(rows, "", "bogus", false); err == nil {
			t.Fatal("expected error, got nil")
		}
	})
}

func TestDmenuKeybindExitCode(t *testing.T) {
	for _, tc := range []struct {
		n    int
		want int
	}{
		{0, 0},
		{1, 10},
		{19, 28},
	} {
		if got := dmenuKeybindExitCode(tc.n); got != tc.want {
			t.Errorf("dmenuKeybindExitCode(%d) = %d, want %d", tc.n, got, tc.want)
		}
	}
}

func TestNormalizeDmenuArgv(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		want []string
	}{
		{
			"not the dmenu subcommand: untouched",
			[]string{"dms", "ipc", "-password"},
			[]string{"dms", "ipc", "-password"},
		},
		{
			"rofi-style single-dash long flags get a second dash",
			[]string{"dms", "dmenu", "-only-match", "-password", "-sep", ","},
			[]string{"dms", "dmenu", "--only-match", "--password", "--sep", ","},
		},
		{
			"= form is preserved",
			[]string{"dms", "dmenu", "-format=i"},
			[]string{"dms", "dmenu", "--format=i"},
		},
		{
			"already-double-dash flags are untouched",
			[]string{"dms", "dmenu", "--password", "-p", "hi"},
			[]string{"dms", "dmenu", "--password", "-p", "hi"},
		},
		{
			"single-char shorthands are untouched",
			[]string{"dms", "dmenu", "-p", "hi", "-l", "5", "-i"},
			[]string{"dms", "dmenu", "-p", "hi", "-l", "5", "-i"},
		},
		{
			"negative --active/--urgent spec values are not mistaken for flag names",
			[]string{"dms", "dmenu", "--active", "-3:"},
			[]string{"dms", "dmenu", "--active", "-3:"},
		},
		{
			"DMS-native long flags also get the single-dash alias",
			[]string{"dms", "dmenu", "-icon", "star"},
			[]string{"dms", "dmenu", "--icon", "star"},
		},
		{
			"rofi's -a/-u abbreviations are real shorthands, untouched by the rewrite",
			[]string{"dms", "dmenu", "-a", "1,3", "-u", "2"},
			[]string{"dms", "dmenu", "-a", "1,3", "-u", "2"},
		},
		{
			"stops rewriting after a bare --",
			[]string{"dms", "dmenu", "--", "-password"},
			[]string{"dms", "dmenu", "--", "-password"},
		},
	} {
		got := normalizeDmenuArgv(tc.args)
		if !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: normalizeDmenuArgv(%v) = %v, want %v", tc.name, tc.args, got, tc.want)
		}
	}
}
