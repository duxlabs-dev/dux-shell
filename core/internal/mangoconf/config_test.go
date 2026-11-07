package mangoconf

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestTOMLEntries(t *testing.T) {
	for name, tc := range map[string]struct {
		toml string
		want []string
	}{
		"a bind table names its mode and leaves the running key_mode alone": {
			`key_mode = "common"
[bind.default]
"SUPER+Return" = "spawn,foot"
[bind.resize]
"NONE+h" = "resizewin,-10,0"
[global]
bind = "SUPER,x,killclient"`,
			[]string{"key_mode=common", "default:bind=SUPER,Return,spawn,foot", "resize:bind=NONE,h,resizewin,-10,0", "bind=SUPER,x,killclient"},
		},
		"a rejected bind table empties the key mode, as upstream does": {
			`[bind]
"SUPER+q" = "quit"
[bind.default.bogus]
"SUPER+w" = "quit"
[global]
bind = "SUPER,e,quit"`,
			[]string{"key_mode=", "key_mode=", "bind=SUPER,e,quit"},
		},
		"flags on every bind kind": {
			`[mousebind.default.lock.pass]
"SUPER+btn_left" = "moveresize,curmove"
[axisbind.default.sym]
"SUPER+UP" = "viewtoleft"
[gesturebind.default.conflict]
"none+left+3" = "focusdir,left"
[switchbind.default.release]
"fold" = "spawn,monitor on"
[keybind.default.release.conflict]
"SUPER+a" = "killclient"`,
			[]string{
				"default:mousebindlp=SUPER,btn_left,moveresize,curmove", "default:axisbinds=SUPER,UP,viewtoleft",
				"default:gesturebindc=none,left,3,focusdir,left", "default:switchbindr=fold,spawn,monitor on",
				"default:bindrc=SUPER,a,killclient",
			},
		},
		"# and line breaks inside strings are values, not comments": {
			`[bind.default]
"SUPER+n" = "spawn,notify-send '#1'" # Notify
"SUPER+m" = ['spawn,printf "a\n"']
"SUPER+b" = "spawn,printf \"b\n\""`,
			[]string{"default:bind=SUPER,n,spawn,notify-send '#1'", `default:bind=SUPER,m,spawn,printf "a\n"`, "default:bind=SUPER,b,spawn,printf \"b\n\""},
		},
		"var from the top level, [global] and [var] expands later values": {
			`var = "mod,SUPER"
[global]
var = "term,foot"
[var]
dir = "./dms"
[bind.default]
"$mod+Return" = "spawn,${term}"
[[rule.window_rule]]
app_id = "$term"
is_floating = true
[global]
source = "$dir/binds.conf"`,
			[]string{
				"var=mod,SUPER", "var=term,foot", "var=dir,./dms", "default:bind=SUPER,Return,spawn,foot",
				"window_rule=app_id:foot,is_floating:1", "source=./dms/binds.conf",
			},
		},
	} {
		var got []string
		for _, e := range TOMLEntries(tc.toml) {
			line := e.Key + "=" + e.Value
			if e.Mode != "" {
				line = e.Mode + ":" + line
			}
			got = append(got, line)
		}
		if !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s:\ngot  %q\nwant %q", name, got, tc.want)
		}
	}
}

func TestTOMLEntriesComment(t *testing.T) {
	got := TOMLEntries(`[bind.default]
# Terminal
"SUPER+t" = "spawn,foot"
# stale

"SUPER+r" = [ # check then reload
    "spawn,config-check.sh",
    # "spawn,old",
]`)
	var comments []string
	for _, e := range got {
		comments = append(comments, e.Value+" "+e.Comment)
	}
	want := []string{"SUPER,t,spawn,foot Terminal", "SUPER,r,spawn,config-check.sh check then reload"}
	if !reflect.DeepEqual(comments, want) {
		t.Errorf("got %q, want %q", comments, want)
	}
}

func walkSources(t *testing.T, files map[string]string, root string) []string {
	t.Helper()
	dir := t.TempDir()
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	var out []string
	if err := Walk(dir, filepath.Join(dir, root), Vars{}, func(_ string, e Entry) {
		if !e.IsSource() {
			return
		}
		rel, _ := filepath.Rel(dir, e.Value)
		out = append(out, map[bool]string{true: rel}[e.Value != ""])
	}); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestWalkSources(t *testing.T) {
	for name, tc := range map[string]struct {
		files map[string]string
		want  []string
	}{
		"only top level, global and rule tables source files": {
			map[string]string{"config.toml": `source = "./top.conf"
[env]
source = "./env.conf"
[var]
source_optional = "./var.conf"
[bind.default]
"SUPER+s" = "spawn,cat ./dms/binds.conf"
[global]
source = ["./a.conf", # "./disabled.conf",
  "./b.toml"]
[rule]
source_optional = "./rule.conf"
[global]
source = "./again.conf"`},
			[]string{"top.conf", "a.conf", "b.toml", "rule.conf", "again.conf"},
		},
		"basic strings decode, literal strings do not, a bare path is not resolvable": {
			map[string]string{"config.toml": "source = ['C:\\raw.conf', \"./back\\\\slash.conf\", \"./tab\\tname.conf\"]\nsource = \"./with\\\"quote.conf\""},
			[]string{"", `back\slash.conf`, "tab\tname.conf", `with"quote.conf`},
		},
		"a var set at the top level or in [global] expands in a source": {
			map[string]string{"config.toml": "var = \"dms,./dms\"\n[global]\nvar = \"name,binds\"\nsource = \"$dms/${name}.conf\""},
			[]string{"dms/binds.conf"},
		},
		"a var from the main config reaches a sourced file": {
			map[string]string{
				"config.toml": "[var]\ndir = \"./dms\"\n[global]\nsource = \"./vars.toml\"",
				"vars.toml":   `source = "$dir/binds.conf"`,
			},
			[]string{"vars.toml", "dms/binds.conf"},
		},
		"a var a sourced file defines reaches the main config's later sources": {
			map[string]string{
				"config.conf": "source=./vars.conf\nsource=$dir/binds.conf # binds",
				"vars.conf":   "var=dir,./dms",
			},
			[]string{"vars.conf", "dms/binds.conf"},
		},
		"conf values drop one pair of quotes and a comment after whitespace": {
			map[string]string{"config.conf": "source=\"./a.conf\"\nsource_optional = './b#c.conf' # optional\n# source=./off.conf"},
			[]string{"a.conf", "b#c.conf"},
		},
		"a file without .toml or .conf is TOML when it starts with a table": {
			map[string]string{
				"config.conf": "source=./keys\nsource=./plain\nsource=./table.conf",
				"keys":        "# keys\n\n[global]\nsource = [\"./x.conf\"]",
				"plain":       "source = [\"./y.conf\"]",
				"table.conf":  "[global]\nsource = [\"./z.conf\"]",
			},
			[]string{"keys", "x.conf", "plain", "", "table.conf", ""},
		},
	} {
		root := "config.conf"
		if _, ok := tc.files["config.toml"]; ok {
			root = "config.toml"
		}
		if got := walkSources(t, tc.files, root); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: got %q, want %q", name, got, tc.want)
		}
	}
}
