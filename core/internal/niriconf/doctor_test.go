package niriconf

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func writeTree(t *testing.T, files map[string]string) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	dir := filepath.Join(home, ".config", "niri")
	for name, content := range files {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestDoctorFindings(t *testing.T) {
	for name, c := range map[string]struct {
		files  map[string]string
		appIDs []string
		want   []Finding
	}{
		"clean": {
			files: map[string]string{
				"config.kdl":          "layout { gaps 8; }\ninclude optional=true \"dms/niri.kdl\"\nbinds { Mod+T { spawn \"foot\"; } }\n",
				"dms/niri.kdl":        "layout { gaps 16; }\ninclude optional=true \"niri-custom.kdl\"\n",
				"dms/niri-custom.kdl": "",
			},
			want: []Finding{},
		},
		"underscore environment still parses": {
			files: map[string]string{"config.kdl": "environment {\n    _JAVA_AWT_WM_NONREPARENTING \"1\"\n}\n"},
			want:  []Finding{},
		},
		"duplicate bind in one block": {
			files: map[string]string{"config.kdl": "binds {\n    Mod+T { spawn \"foot\"; }\n    mod+t { spawn \"kitty\"; }\n}\n"},
			want:  []Finding{{Kind: KindDuplicateBind, Severity: SeverityError, Subject: "mod+t", Files: []string{"config.kdl"}}},
		},
		"modifier order and aliases are one key": {
			files: map[string]string{"config.kdl": "binds {\n    Ctrl+Win+A { spawn \"a\"; }\n    Super+Control+a { spawn \"b\"; }\n}\n"},
			want:  []Finding{{Kind: KindDuplicateBind, Severity: SeverityError, Subject: "Super+Control+a", Files: []string{"config.kdl"}}},
		},
		"bind hidden by a later file": {
			files: map[string]string{
				"config.kdl":    "binds { Mod+E { spawn \"nautilus\"; } }\ninclude \"dms/binds.kdl\"\n",
				"dms/binds.kdl": "binds { Mod+E { spawn \"dolphin\"; } }\n",
			},
			want: []Finding{{Kind: KindOverride, Severity: SeverityWarning, Subject: "Mod+E", Files: []string{"config.kdl", "dms/binds.kdl"}}},
		},
		"missing include": {
			files: map[string]string{"config.kdl": "include \"dms/gone.kdl\"\ninclude optional=true \"dms/fine.kdl\"\n"},
			want:  []Finding{{Kind: KindMissingInclude, Severity: SeverityError, Subject: "dms/gone.kdl", Files: []string{"config.kdl", "dms/gone.kdl"}}},
		},
		"fragment never included": {
			files: map[string]string{"config.kdl": "layout {}\n", "dms/alttab.kdl": "recent-windows { off; }\n"},
			want:  []Finding{{Kind: KindNotIncluded, Severity: SeverityWarning, Subject: "dms/alttab.kdl", Files: []string{"dms/alttab.kdl"}, Fix: FixAddInclude}},
		},
		"empty fragment never included": {
			// No setting inside: nothing to include, so the page must not pose an include for it
			files: map[string]string{"config.kdl": "layout {}\n", "dms/empty.kdl": ""},
			want:  []Finding{},
		},
		"option set twice in one file": {
			files: map[string]string{"config.kdl": "layout { center-focused-column \"never\"; }\nlayout { center-focused-column \"always\"; }\n"},
			want:  []Finding{{Kind: KindOverride, Severity: SeverityWarning, Subject: "layout center-focused-column", Files: []string{"config.kdl", "config.kdl"}}},
		},
		"option overridden by a later file only counts": {
			files: map[string]string{
				"config.kdl":     "layout { gaps 8; focus-ring { width 2; } }\ninclude \"dms/layout.kdl\"\n",
				"dms/layout.kdl": "layout { gaps 16; focus-ring { active-color \"red\"; } }\n",
			},
			want: []Finding{},
		},
		"device block replaced whole": {
			files: map[string]string{
				"config.kdl":    "input { touchpad { tap; natural-scroll; } }\ninclude \"dms/input.kdl\"\n",
				"dms/input.kdl": "input { touchpad { } }\n",
			},
			want: []Finding{{Kind: KindReplaced, Severity: SeverityError, Subject: "input touchpad", Files: []string{"config.kdl", "dms/input.kdl"}}},
		},
		"rule matching no known app": {
			files: map[string]string{"config.kdl": "window-rule { match app-id=\"^old-mail$\"; opacity 0.9; }\n" +
				"window-rule { match app-id=\"^firefox$\"; open-maximized true; }\n" +
				"window-rule { match title=\"Picture\"; open-floating true; }\n"},
			appIDs: []string{"firefox", "foot"},
			want:   []Finding{{Kind: KindUnusedRule, Severity: SeverityWarning, Subject: "^old-mail$", Files: []string{"config.kdl"}}},
		},
		"rules not judged without apps": {
			files: map[string]string{"config.kdl": "window-rule { match app-id=\"^old-mail$\"; }\n"},
			want:  []Finding{},
		},
		"obsolete options": {
			files: map[string]string{"config.kdl": "output \"eDP-1\" { background-color \"#003300\"; }\n" +
				"layout { focus-ring { active-color 127 200 255 255; } }\n"},
			want: []Finding{
				{Kind: KindObsolete, Severity: SeverityWarning, Subject: "output background-color", Files: []string{"config.kdl"}},
				{Kind: KindObsolete, Severity: SeverityWarning, Subject: "layout focus-ring active-color", Files: []string{"config.kdl"}},
			},
		},
		"unreadable file": {
			files: map[string]string{"config.kdl": "include \"dms/broken.kdl\"\n", "dms/broken.kdl": "layout { gaps \"\n"},
			want:  []Finding{{Kind: KindUnreadable, Severity: SeverityWarning, Subject: "dms/broken.kdl", Files: []string{"dms/broken.kdl"}}},
		},
	} {
		t.Run(name, func(t *testing.T) {
			got := Doctor(writeTree(t, c.files), c.appIDs).Findings
			if !reflect.DeepEqual(got, c.want) {
				t.Fatalf("findings = %+v\nwant %+v", got, c.want)
			}
		})
	}
}

// An app both in XDG autostart and in a spawn-at-startup opens twice at login: the doctor says so.
func TestDoctorDuplicateStartup(t *testing.T) {
	for name, c := range map[string]struct {
		config    string
		autostart map[string]string
		want      []Finding
	}{
		"app in autostart and session": {
			config:    "spawn-at-startup \"i6-test-app\" \"--flag\" \"a b\"\n",
			autostart: map[string]string{"i6-test-app.desktop": "[Desktop Entry]\nType=Application\nName=Test\nExec=i6-test-app --flag \"a b\"\n"},
			want: []Finding{{
				Kind: KindDuplicateStartup, Severity: SeverityWarning, Subject: "i6-test-app",
				Files: []string{"config.kdl", "autostart/i6-test-app.desktop"},
			}},
		},
		"program name with spaces is one argument": {
			config:    "spawn-at-startup \"app with spaces\" \"--flag\" \"a b\"\n",
			autostart: map[string]string{"spaces.desktop": "[Desktop Entry]\nExec=\"app with spaces\" --flag\n"},
			want: []Finding{{
				Kind: KindDuplicateStartup, Severity: SeverityWarning, Subject: "app with spaces",
				Files: []string{"config.kdl", "autostart/spaces.desktop"},
			}},
		},
		"only the session starts it": {
			config: "spawn-at-startup \"i6-test-app\"\n",
			want:   []Finding{},
		},
		"hidden autostart entry starts nothing": {
			config:    "spawn-at-startup \"i6-test-app\"\n",
			autostart: map[string]string{"i6-test-app.desktop": "[Desktop Entry]\nExec=i6-test-app\nHidden=true\n"},
			want:      []Finding{},
		},
		"another app in autostart": {
			config:    "spawn-at-startup \"i6-test-app\"\n",
			autostart: map[string]string{"other.desktop": "[Desktop Entry]\nExec=i6-other-app\n"},
			want:      []Finding{},
		},
		"autostart command behind a wrapper": {
			config:    "spawn-at-startup \"/usr/bin/i6-test-app\"\n",
			autostart: map[string]string{"i6-test-app.desktop": "[Desktop Entry]\nExec=uwsm app -- i6-test-app\n"},
			want: []Finding{{
				Kind: KindDuplicateStartup, Severity: SeverityWarning, Subject: "/usr/bin/i6-test-app",
				Files: []string{"config.kdl", "autostart/i6-test-app.desktop"},
			}},
		},
	} {
		t.Run(name, func(t *testing.T) {
			dir := writeTree(t, map[string]string{"config.kdl": c.config})
			autostart := filepath.Join(filepath.Dir(dir), "autostart")
			if err := os.MkdirAll(autostart, 0o755); err != nil {
				t.Fatal(err)
			}
			for file, content := range c.autostart {
				if err := os.WriteFile(filepath.Join(autostart, file), []byte(content), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			got := Doctor(dir, nil).Findings
			if !reflect.DeepEqual(got, c.want) {
				t.Fatalf("findings = %+v\nwant %+v", got, c.want)
			}
		})
	}
}

func TestDoctorFiles(t *testing.T) {
	dir := writeTree(t, map[string]string{
		"config.kdl":     "layout { gaps 8; }\ninclude \"dms/layout.kdl\"\ninclude optional=true \"dms/cursor.kdl\"\n",
		"dms/layout.kdl": "layout { gaps 16; }\n",
		// An empty fragment carries no setting: no file entry, no include to pose
		"dms/alttab.kdl": "",
	})
	want := []FileState{
		{Path: "config.kdl", State: FileBase},
		{Path: "dms/layout.kdl", State: FileActive, Overrides: 1},
		{Path: "dms/cursor.kdl", State: FileMissing},
	}
	if got := Doctor(dir, nil).Files; !reflect.DeepEqual(got, want) {
		t.Fatalf("files = %+v\nwant %+v", got, want)
	}
}

func TestAddInclude(t *testing.T) {
	dir := setupValidate(t, dmsInclude, "")
	if err := os.WriteFile(filepath.Join(dir, "dms", "alttab.kdl"), []byte("recent-windows { off; }\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	s := &Store{ConfigDir: dir}
	if err := s.AddInclude("alttab.kdl"); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(dir, "config.kdl"))
	if !strings.HasSuffix(string(data), "include optional=true \"dms/alttab.kdl\"\n") {
		t.Fatalf("config = %q", data)
	}
	if got := Doctor(dir, nil).Findings; len(got) != 0 {
		t.Fatalf("findings after fix = %+v", got)
	}
}

func TestAddIncludeRefuses(t *testing.T) {
	dir := setupValidate(t, "layout {}\n", "")
	if err := os.WriteFile(filepath.Join(dir, "dms", "bad.kdl"), []byte("BAD\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	s := &Store{ConfigDir: dir}
	for name, want := range map[string]bool{"bad.kdl": true, "gone.kdl": true, "../x.kdl": true} {
		if err := s.AddInclude(name); (err != nil) != want {
			t.Fatalf("%s: err = %v", name, err)
		}
	}
	if data, _ := os.ReadFile(filepath.Join(dir, "config.kdl")); string(data) != "layout {}\n" {
		t.Fatalf("config changed: %q", data)
	}
}
