package providers

import (
	"maps"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
)

func TestMangoWCParseAxisBindToScrollKey(t *testing.T) {
	tmpDir := t.TempDir()
	cfg := filepath.Join(tmpDir, "config.conf")
	content := "axisbind=SUPER,UP,spawn,dms ipc call test\n"
	if err := os.WriteFile(cfg, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	binds, err := ParseMangoWCKeys(cfg)
	if err != nil {
		t.Fatalf("ParseMangoWCKeys failed: %v", err)
	}
	if len(binds) != 1 {
		t.Fatalf("expected 1 bind, got %d", len(binds))
	}
	if binds[0].Key != "WheelScrollUp" {
		t.Fatalf("expected axis direction parsed as WheelScrollUp, got %q", binds[0].Key)
	}
	if len(binds[0].Mods) != 1 || binds[0].Mods[0] != "SUPER" {
		t.Fatalf("expected SUPER mod, got %v", binds[0].Mods)
	}
}

func TestMangoWCAutogenerateComment(t *testing.T) {
	tests := []struct {
		command  string
		params   string
		expected string
	}{
		{"spawn", "kitty", "kitty"},
		{"killclient", "", "Close window"},
		{"focusstack", "next", "Focus next window"},
		{"focusstack", "prev", "Focus previous window"},
		{"focusdir", "left", "Focus left"},
		{"exchange_client", "left", "Swap window left"},
		{"move_client", "left", "Move window left"},
		{"scroller_stack", "up", "Stack window up"},
		{"togglejump", "", "Jump to window"},
		{"setlayout", "tile", "Set layout tile"},
		{"view", "1,0", "View tag 1"},
		{"tag", "2,0", "Move to tag 2"},
		{"toggleview", "3,0", "Toggle tag 3"},
		{"viewtoleft_have_client", "", "View left tag"},
		{"focusmon", "left", "Focus monitor left"},
		{"incgaps", "1", "Increase gaps"},
		{"incgaps", "-1", "Decrease gaps"},
		{"movewin", "+0,-50", "Move window by +0,-50"},
		{"unknown", "", ""},
	}

	for _, tt := range tests {
		t.Run(tt.command+"_"+tt.params, func(t *testing.T) {
			result := mangowcAutogenerateComment(tt.command, tt.params)
			if result != tt.expected {
				t.Errorf("mangowcAutogenerateComment(%q, %q) = %q, want %q",
					tt.command, tt.params, result, tt.expected)
			}
		})
	}
}

func TestMangoWCGetKeybindAtLine(t *testing.T) {
	tests := []struct {
		name             string
		line             string
		precedingComment string
		expected         *MangoWCKeyBinding
	}{
		{
			name: "basic_keybind",
			line: "bind=ALT,q,killclient,",
			expected: &MangoWCKeyBinding{
				Mods:    []string{"ALT"},
				Key:     "q",
				Command: "killclient",
				Params:  "",
				Comment: "Close window",
			},
		},
		{
			name: "keybind_with_params",
			line: "bind=ALT,Left,focusdir,left",
			expected: &MangoWCKeyBinding{
				Mods:    []string{"ALT"},
				Key:     "Left",
				Command: "focusdir",
				Params:  "left",
				Comment: "Focus left",
			},
		},
		{
			name: "keybind_with_comment",
			line: "bind=Alt,t,spawn,kitty # Open terminal",
			expected: &MangoWCKeyBinding{
				Mods:    []string{"Alt"},
				Key:     "t",
				Command: "spawn",
				Params:  "kitty",
				Comment: "Open terminal",
			},
		},
		{
			name:     "keybind_hidden",
			line:     "bind=SUPER,h,spawn,secret # [hidden]",
			expected: nil,
		},
		{
			name: "keybind_multiple_mods",
			line: "bind=SUPER+SHIFT,Up,exchange_client,up",
			expected: &MangoWCKeyBinding{
				Mods:    []string{"SUPER", "SHIFT"},
				Key:     "Up",
				Command: "exchange_client",
				Params:  "up",
				Comment: "Swap window up",
			},
		},
		{
			name: "keybind_no_mods",
			line: "bind=NONE,Print,spawn,screenshot",
			expected: &MangoWCKeyBinding{
				Mods:    []string{},
				Key:     "Print",
				Command: "spawn",
				Params:  "screenshot",
				Comment: "screenshot",
			},
		},
		{
			name: "keybind_multiple_params",
			line: "bind=Ctrl,1,view,1,0",
			expected: &MangoWCKeyBinding{
				Mods:    []string{"Ctrl"},
				Key:     "1",
				Command: "view",
				Params:  "1,0",
				Comment: "View tag 1",
			},
		},
		{
			name: "bindl_flag",
			line: "bindl=SUPER+ALT,l,spawn,dms ipc call lock lock",
			expected: &MangoWCKeyBinding{
				Mods:    []string{"SUPER", "ALT"},
				Key:     "l",
				Command: "spawn",
				Params:  "dms ipc call lock lock",
				Comment: "dms ipc call lock lock",
			},
		},
		{
			name:             "preceding_comment",
			line:             "bind=SUPER+SHIFT,S,spawn,dms screenshot",
			precedingComment: "Screenshot: Interactive",
			expected: &MangoWCKeyBinding{
				Mods:    []string{"SUPER", "SHIFT"},
				Key:     "S",
				Command: "spawn",
				Params:  "dms screenshot",
				Comment: "Screenshot: Interactive",
			},
		},
		{
			name:             "section_header_not_description",
			line:             "bind=none,XF86AudioRaiseVolume,spawn,dms ipc call audio increment 3",
			precedingComment: "=== Audio Controls ===",
			expected: &MangoWCKeyBinding{
				Mods:    []string{},
				Key:     "XF86AudioRaiseVolume",
				Command: "spawn",
				Params:  "dms ipc call audio increment 3",
				Comment: "dms ipc call audio increment 3",
			},
		},
		{
			name: "keybind_with_spaces",
			line: "bind = SUPER, r, reload_config",
			expected: &MangoWCKeyBinding{
				Mods:    []string{"SUPER"},
				Key:     "r",
				Command: "reload_config",
				Params:  "",
				Comment: "Reload configuration",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parser := NewMangoWCParser("")
			parser.contentLines = []string{tt.line}
			result := parser.getKeybindAtLine(0, tt.precedingComment)

			if tt.expected == nil {
				if result != nil {
					t.Errorf("expected nil, got %+v", result)
				}
				return
			}

			if result == nil {
				t.Errorf("expected %+v, got nil", tt.expected)
				return
			}

			if result.Key != tt.expected.Key {
				t.Errorf("Key = %q, want %q", result.Key, tt.expected.Key)
			}
			if result.Command != tt.expected.Command {
				t.Errorf("Command = %q, want %q", result.Command, tt.expected.Command)
			}
			if result.Params != tt.expected.Params {
				t.Errorf("Params = %q, want %q", result.Params, tt.expected.Params)
			}
			if result.Comment != tt.expected.Comment {
				t.Errorf("Comment = %q, want %q", result.Comment, tt.expected.Comment)
			}
			if len(result.Mods) != len(tt.expected.Mods) {
				t.Errorf("Mods length = %d, want %d", len(result.Mods), len(tt.expected.Mods))
			} else {
				for i := range result.Mods {
					if result.Mods[i] != tt.expected.Mods[i] {
						t.Errorf("Mods[%d] = %q, want %q", i, result.Mods[i], tt.expected.Mods[i])
					}
				}
			}
		})
	}
}

func TestMangoWCParseKeys(t *testing.T) {
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "config.conf")

	content := `# MangoWC Configuration
blur=0
border_radius=12

# Key Bindings
bind=SUPER,r,reload_config
bind=Alt,t,spawn,kitty # Terminal
bind=ALT,q,killclient,
bind=ALT,Left,focusdir,left

# Hidden binding
bind=SUPER,h,spawn,secret # [hidden]

# Multiple modifiers
bind=SUPER+SHIFT,Up,exchange_client,up

# Workspace bindings
bind=Ctrl,1,view,1,0
bind=Ctrl,2,view,2,0
`

	if err := os.WriteFile(configFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	keybinds, err := ParseMangoWCKeys(configFile)
	if err != nil {
		t.Fatalf("ParseMangoWCKeys failed: %v", err)
	}

	expectedCount := 7
	if len(keybinds) != expectedCount {
		t.Errorf("Expected %d keybinds, got %d", expectedCount, len(keybinds))
	}

	if len(keybinds) > 0 && keybinds[0].Command != "reload_config" {
		t.Errorf("First keybind command = %q, want %q", keybinds[0].Command, "reload_config")
	}

	foundHidden := false
	for _, kb := range keybinds {
		if kb.Command == "spawn" && kb.Params == "secret" {
			foundHidden = true
		}
	}
	if foundHidden {
		t.Error("Hidden keybind should not be included in results")
	}
}

func TestMangoWCReadContentMultipleFiles(t *testing.T) {
	tmpDir := t.TempDir()

	file1 := filepath.Join(tmpDir, "a.conf")
	file2 := filepath.Join(tmpDir, "b.conf")

	content1 := "bind=ALT,q,killclient,\n"
	content2 := "bind=Alt,t,spawn,kitty\n"

	if err := os.WriteFile(file1, []byte(content1), 0o644); err != nil {
		t.Fatalf("Failed to write file1: %v", err)
	}
	if err := os.WriteFile(file2, []byte(content2), 0o644); err != nil {
		t.Fatalf("Failed to write file2: %v", err)
	}

	parser := NewMangoWCParser("")
	if err := parser.ReadContent(tmpDir); err != nil {
		t.Fatalf("ReadContent failed: %v", err)
	}

	keybinds := parser.ParseKeys()
	if len(keybinds) != 2 {
		t.Errorf("Expected 2 keybinds from multiple files, got %d", len(keybinds))
	}
}

func TestMangoWCReadContentErrors(t *testing.T) {
	tests := []struct {
		name string
		path string
	}{
		{
			name: "nonexistent_directory",
			path: "/nonexistent/path/that/does/not/exist",
		},
		{
			name: "empty_directory",
			path: t.TempDir(),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseMangoWCKeys(tt.path)
			if err == nil {
				t.Error("Expected error, got nil")
			}
		})
	}
}

func TestMangoWCInvalidBindLines(t *testing.T) {
	tests := []struct {
		name string
		line string
	}{
		{
			name: "missing_parts",
			line: "bind=SUPER,q",
		},
		{
			name: "not_bind",
			line: "blur=0",
		},
		{
			name: "empty_line",
			line: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parser := NewMangoWCParser("")
			parser.contentLines = []string{tt.line}
			result := parser.getKeybindAtLine(0, "")

			if result != nil {
				t.Errorf("expected nil for invalid line, got %+v", result)
			}
		})
	}
}

func TestMangoWCParseWithDMSKeyModes(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "dms"), 0o755); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		filepath.Join(dir, "config.conf"): `key_mode=resize
bind=SUPER,q,killclient
key_mode=common
bind=SUPER,x,killclient
key_mode=default
bindc=SUPER,Return,spawn,foot
source=./dms/binds.conf
`,
		filepath.Join(dir, "dms", "binds.conf"): "bind=SUPER,q,spawn,dms ipc call powermenu toggle\nbind=SUPER,x,spawn,dms ipc call spotlight toggle\n",
	}
	for path, content := range files {
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	result, err := ParseMangoWCKeysWithDMS(dir)
	if err != nil {
		t.Fatal(err)
	}
	var binds []string
	for _, kb := range result.Keybinds {
		binds = append(binds, strings.Join(append(kb.Mods, kb.Key), "+")+" "+filepath.Base(kb.Source))
	}
	want := []string{"SUPER+q config.conf", "SUPER+x binds.conf", "SUPER+Return config.conf", "SUPER+q binds.conf"}
	if !reflect.DeepEqual(binds, want) {
		t.Errorf("binds = %v, want %v", binds, want)
	}
	conflicts := slices.Sorted(maps.Keys(result.ConflictingConfigs))
	if !reflect.DeepEqual(conflicts, []string{"default:super+x"}) {
		t.Errorf("conflicts = %v, want only the common-mode super+x", conflicts)
	}
}

func TestMangoWCParseWithDMSReadsConfigToml(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "dms"), 0o755); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		filepath.Join(dir, "config.toml"): `key_mode = "common"
[bind.default]
"SUPER+Return" = "spawn,foot" # Terminal
"SUPER+n" = "spawn,notify-send '#1'"
[bind.resize]
"SUPER+q" = "killclient"
[global]
bind = "SUPER,x,killclient"
key_mode = "default"
source = "./dms/binds.conf"
`,
		filepath.Join(dir, "dms", "binds.conf"): "bind=SUPER,q,spawn,dms ipc call powermenu toggle\nbind=SUPER,x,spawn,dms ipc call spotlight toggle\n",
	}
	for path, content := range files {
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	result, err := ParseMangoWCKeysWithDMS(dir)
	if err != nil {
		t.Fatal(err)
	}
	var binds []string
	for _, kb := range result.Keybinds {
		binds = append(binds, strings.Join([]string{kb.Mode, strings.Join(append(kb.Mods, kb.Key), "+"), kb.Params, kb.Comment, filepath.Base(kb.Source)}, " | "))
	}
	want := []string{
		"default | SUPER+Return | foot | Terminal | config.toml",
		"default | SUPER+n | notify-send '#1' | notify-send '#1' | config.toml",
		"resize | SUPER+q |  | Close window | config.toml",
		"default | SUPER+x | dms ipc call spotlight toggle | dms ipc call spotlight toggle | binds.conf",
		"default | SUPER+q | dms ipc call powermenu toggle | dms ipc call powermenu toggle | binds.conf",
	}
	if !reflect.DeepEqual(binds, want) {
		t.Errorf("binds =\n%q\nwant\n%q", binds, want)
	}
	conflict := result.ConflictingConfigs["default:super+x"]
	if len(result.ConflictingConfigs) != 1 || conflict == nil || conflict.Mode != "common" {
		t.Errorf("conflicts = %v, want only the common super+x; the resize super+q leaves the DMS bind alone", result.ConflictingConfigs)
	}
	if !result.DMSBindsIncluded {
		t.Error("dms/binds.conf is sourced from config.toml")
	}
}

func writeMangoFiles(t *testing.T, dir string, files map[string]string) {
	t.Helper()
	for name, content := range files {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestMangoWCParseFollowsMangoState(t *testing.T) {
	for name, tc := range map[string]struct {
		files map[string]string
		want  []string
	}{
		"vars span sourced files": {
			map[string]string{
				"config.toml": "[var]\nmod = \"SUPER\"\n[global]\nsource = [\"./binds.toml\", \"./more.conf\"]\n",
				"binds.toml":  "[bind.default]\n\"$mod+Return\" = \"spawn,foot\"\n",
				"more.conf":   "var=term,kitty\nbind=$mod,t,spawn,$term\n",
			},
			[]string{"default SUPER+Return foot", "default SUPER+t kitty"},
		},
		"a quoted conf key_mode is the bare mode": {
			map[string]string{"config.conf": "key_mode=\"resize\"\nbind=NONE,h,resizewin,-10,0\nkey_mode='default' # back\nbind=SUPER,r,reload_config\n"},
			[]string{"resize h -10,0", "default SUPER+r "},
		},
		"./ is read from the config dir and a bare path is not followed": {
			map[string]string{
				"config.conf":    "source=./dms/more.conf\n",
				"dms/more.conf":  "source=./dms/binds.conf\nsource = other.conf\n",
				"dms/binds.conf": "bind=SUPER,d,spawn,dms\n",
				"dms/other.conf": "bind=SUPER,o,spawn,other\n",
			},
			[]string{"default SUPER+d dms"},
		},
		"a sourced file without an extension is TOML when it starts with a table": {
			map[string]string{
				"config.toml": "source = \"./keys\"\n",
				"keys":        "# keys\n[bind.default]\n\"SUPER+Return\" = \"spawn,foot\"\n",
			},
			[]string{"default SUPER+Return foot"},
		},
		"flagged axis binds": {
			map[string]string{
				"config.toml": "[axisbind.default.lock]\n\"SUPER+UP\" = \"viewtoleft\"\n",
			},
			[]string{"default SUPER+WheelScrollUp "},
		},
	} {
		dir := t.TempDir()
		writeMangoFiles(t, dir, tc.files)
		result, err := ParseMangoWCKeysWithDMS(dir)
		if err != nil {
			t.Fatal(err)
		}
		var got []string
		for _, kb := range result.Keybinds {
			got = append(got, kb.Mode+" "+strings.Join(append(kb.Mods, kb.Key), "+")+" "+kb.Params)
		}
		if !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: got %q, want %q", name, got, tc.want)
		}
	}
}

func TestMangoWCCheatSheetConflictsPerMode(t *testing.T) {
	dir := t.TempDir()
	writeMangoFiles(t, dir, map[string]string{
		"config.conf":    "key_mode=\"common\"\nbind=SUPER,q,killclient\nkey_mode=\" resize \"\nbind=SUPER,r,killclient\nkey_mode=default\nbind=SUPER,x,killclient\nbindc=SUPER,c,killclient\nsource=./dms/binds.conf\n",
		"dms/binds.conf": "bind=SUPER,x,spawn,dmsx\nbind=SUPER,q,spawn,dmsq\nbind=SUPER,c,spawn,dmsc\nkey_mode=resize\nbind=SUPER,x,spawn,dmsx-resize\nbind=SUPER,q,spawn,dmsq-resize\nbind=SUPER,r,spawn,dmsr-resize\n",
	})

	sheet, err := NewMangoWCProvider(dir).GetCheatSheet()
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, binds := range sheet.Binds {
		for _, b := range binds {
			if b.Conflict != nil {
				got = append(got, b.Action+" <- "+b.Conflict.Action)
			}
		}
	}
	slices.Sort(got)
	want := []string{"spawn dmsq <- killclient", "spawn dmsq-resize <- killclient", "spawn dmsr-resize <- killclient", "spawn dmsx <- killclient"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("conflicts = %q, want %q: a common bind shadows every mode, a default one only default, a bindc none", got, want)
	}
}
