package configprofile

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

type entry struct {
	name     string
	body     string
	typeflag byte
	link     string
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func tarGz(t *testing.T, entries []entry) string {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for _, e := range entries {
		tf := e.typeflag
		if tf == 0 {
			tf = tar.TypeReg
		}
		h := &tar.Header{Name: e.name, Typeflag: tf, Linkname: e.link, Mode: 0o644}
		if tf == tar.TypeReg {
			h.Size = int64(len(e.body))
		}
		if err := tw.WriteHeader(h); err != nil {
			t.Fatal(err)
		}
		if tf == tar.TypeReg {
			tw.Write([]byte(e.body))
		}
	}
	tw.Close()
	gz.Close()
	return buf.String()
}

func readJSON(t *testing.T, path string) map[string]any {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatal(err)
	}
	return m
}

func validProfile(extra string) string {
	return `{"version":1,"name":"Shared","groups":["wallpaper"],"configVersion":1,"sessionConfigVersion":1` + extra + `}`
}

func TestExportImportRoundTrip(t *testing.T) {
	root := t.TempDir()
	dir, wpDir, pics := filepath.Join(root, "profiles"), filepath.Join(root, "wallpapers"), filepath.Join(root, "pics")
	writeFile(t, filepath.Join(pics, "a.jpg"), "AAA")
	writeFile(t, filepath.Join(pics, "b.png"), "BBB")
	profile, _ := json.Marshal(map[string]any{
		"version": 1, "name": "Mine", "groups": []string{"wallpaper", "plugins"}, "configVersion": 1, "sessionConfigVersion": 1,
		"pluginSettings": map[string]any{"x": map[string]any{"cmd": "sh"}},
		"settings": map[string]any{
			"lockScreenWallpaperPath": filepath.Join(pics, "a.jpg"),
			"fontFamily":              "Inter Display",
			"desktopWidgetInstances":  []any{map[string]any{"widgetType": "desktopClock"}, map[string]any{"widgetType": "somePlugin", "config": map[string]any{"cmd": "id"}}},
			"builtInPluginSettings":   map[string]any{"a": 1},
			"dockConfigs":             []any{map[string]any{"trashCustomCommand": "id"}},
		},
		"session": map[string]any{
			"wallpaperPath":     filepath.Join(pics, "a.jpg"),
			"monitorWallpapers": map[string]any{"DP-1": filepath.Join(pics, "b.png")},
		},
	})
	writeFile(t, filepath.Join(dir, "p1", "profile.json"), string(profile))

	out := filepath.Join(root, "shared.tar.gz")
	if _, err := Export(dir, "p1", out); err != nil {
		t.Fatal(err)
	}
	id, err := Import(dir, wpDir, out)
	if err != nil {
		t.Fatal(err)
	}
	if id == "p1" {
		t.Fatal("import overwrote the source profile")
	}
	got := readJSON(t, filepath.Join(dir, id, "profile.json"))
	settings, session := got["settings"].(map[string]any), got["session"].(map[string]any)
	wp := session["wallpaperPath"].(string)
	if b, _ := os.ReadFile(wp); filepath.Dir(wp) != wpDir || string(b) != "AAA" {
		t.Errorf("wallpaperPath = %q", wp)
	}
	if settings["lockScreenWallpaperPath"] != wp {
		t.Error("same file not deduplicated")
	}
	if b, _ := os.ReadFile(session["monitorWallpapers"].(map[string]any)["DP-1"].(string)); string(b) != "BBB" {
		t.Error("monitor wallpaper not installed")
	}
	_, pluginSettings := got["pluginSettings"]
	_, builtIn := settings["builtInPluginSettings"]
	if pluginSettings || builtIn {
		t.Error("plugin data kept")
	}
	if settings["fontFamily"] != "Inter Display" {
		t.Errorf("fontFamily = %v", settings["fontFamily"])
	}
	if w := settings["desktopWidgetInstances"].([]any); len(w) != 1 || w[0].(map[string]any)["widgetType"] != "desktopClock" {
		t.Errorf("desktopWidgetInstances = %v, want only the built-in clock", w)
	}
	if settings["dockConfigs"].([]any)[0].(map[string]any)["trashCustomCommand"] != "" {
		t.Error("trashCustomCommand kept")
	}
}

func TestImportRejects(t *testing.T) {
	ok := entry{name: "profile.json", body: validProfile("")}
	withProfile := func(extra string) []entry { return []entry{{name: "profile.json", body: validProfile(extra)}} }
	cases := []struct {
		name    string
		entries []entry
		limit   func()
	}{
		{name: "path traversal", entries: []entry{ok, {name: "../x", body: "x"}}},
		{name: "symlink", entries: []entry{ok, {name: "wallpapers/a.jpg", typeflag: tar.TypeSymlink, link: "/etc/passwd"}}},
		{name: "non-image wallpaper", entries: []entry{ok, {name: "wallpapers/a.sh", body: "x"}}},
		{name: "duplicate", entries: []entry{ok, ok}},
		{name: "newer version", entries: []entry{{name: "profile.json", body: `{"version":2,"name":"x","groups":[]}`}}},
		{name: "no configVersion", entries: []entry{{name: "profile.json", body: `{"version":1,"name":"x","groups":[],"settings":{"a":1}}`}}},
		{name: "control character", entries: withProfile(`,"session":{"x":"a\u0007b"}`)},
		{name: "shell metacharacter in path", entries: withProfile(`,"session":{"wallpaperCyclingFolderPath":"/$(id)"}`)},
		{name: "icon theme with quote", entries: withProfile(`,"settings":{"iconThemeDark":"a'b"}`)},
		{name: "wildcard path", entries: withProfile(`,"session":{"monitorCyclingSettings":{"DP-1":{"folderPath":"/$(id)"}}}`)},
		{name: "list at a shell path", entries: withProfile(`,"settings":{"cursorSettings":{"theme":["\"; id; \""]}}`)},
		{name: "string cursor size", entries: withProfile(`,"settings":{"cursorSettings":{"size":"24; x"}}`)},
		{name: "file over limit", entries: []entry{ok, {name: "wallpapers/big.jpg", body: strings.Repeat("A", 64)}}, limit: func() { maxFileBytes = 32 }},
		{name: "total over limit", entries: []entry{ok, {name: "wallpapers/a.jpg", body: strings.Repeat("a", 60)}}, limit: func() { maxTotalBytes = 100 }},
		{name: "too many entries", entries: []entry{ok, {name: "wallpapers/", typeflag: tar.TypeDir}, {name: "wallpapers/", typeflag: tar.TypeDir}}, limit: func() { maxEntries = 2 }},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f, e, tot := maxFileBytes, maxEntries, maxTotalBytes
			t.Cleanup(func() { maxFileBytes, maxEntries, maxTotalBytes = f, e, tot })
			if c.limit != nil {
				c.limit()
			}
			root := t.TempDir()
			dir, wpDir, archive := filepath.Join(root, "p"), filepath.Join(root, "w"), filepath.Join(root, "a.tar.gz")
			writeFile(t, archive, tarGz(t, c.entries))
			if id, err := Import(dir, wpDir, archive); err == nil {
				t.Fatalf("accepted, id %q", id)
			}
			for _, d := range []string{dir, wpDir} {
				left, _ := os.ReadDir(d)
				if len(left) != 0 {
					t.Errorf("left behind in %s: %v", d, left)
				}
			}
		})
	}
}

func TestExportRefusesWhatImportRejects(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "profiles")
	writeFile(t, filepath.Join(dir, "bad", "profile.json"), validProfile(`,"session":{"wallpaperCyclingFolderPath":"/$(id)"}`))
	writeFile(t, filepath.Join(dir, "gone", "profile.json"), validProfile(`,"session":{"wallpaperPath":"`+filepath.Join(root, "gone.jpg")+`"}`))
	out := filepath.Join(root, "o.tar.gz")

	if _, err := Export(dir, "bad", out); err == nil {
		t.Error("exported a profile Import would reject")
	}
	if _, err := os.Stat(out); err == nil {
		t.Error("archive written")
	}
	warnings, err := Export(dir, "gone", out)
	if err != nil || len(warnings) != 1 {
		t.Errorf("warnings = %q, err = %v", warnings, err)
	}
}

// Every key the code special-cases by name must still sit in a non-"never" group, or a rename silently drops the handling.
func TestHandledKeysAreInProfileGroups(t *testing.T) {
	b, err := os.ReadFile("../../../quickshell/Common/settings/ConfigProfiles.js")
	if err != nil {
		t.Skip("quickshell tree not available")
	}
	js := string(b)
	listRe, keyRe := regexp.MustCompile(`(?s)(\w+): \[(.*?)\]`), regexp.MustCompile(`"(\w+)"`)
	mapped := map[string]bool{}
	for _, sec := range [][2]string{{"settings", "var SETTINGS_MAP"}, {"session", "var SESSION_MAP"}} {
		start := strings.Index(js, sec[1])
		if start < 0 {
			t.Fatalf("%s not found", sec[1])
		}
		for _, m := range listRe.FindAllStringSubmatch(js[start:start+strings.Index(js[start:], "\n};")], -1) {
			for _, k := range keyRe.FindAllStringSubmatch(m[2], -1) {
				mapped[sec[0]+"."+k[1]] = m[1] != "never"
			}
		}
	}
	var keys []string
	for _, k := range fileKeys {
		keys = append(keys, k.Section+"."+k.Key)
	}
	for _, r := range shellRules {
		keys = append(keys, strings.Join(r.path[:2], "."))
	}
	for _, p := range unbundledPaths {
		keys = append(keys, strings.Join(p[:2], "."))
	}
	for _, k := range widgetInstanceKeys {
		keys = append(keys, "settings."+k)
	}
	for _, k := range keys {
		if !mapped[k] {
			t.Errorf("%s is not mapped to a group in ConfigProfiles.js", k)
		}
	}
	if dock, err := os.ReadFile("../../../quickshell/Common/settings/DockConfig.js"); err != nil || !strings.Contains(string(dock), "trashCustomCommand:") {
		t.Error("trashCustomCommand is no longer a dock config key in DockConfig.js")
	}
	registry, err := os.ReadFile("../../../quickshell/Services/DesktopWidgetRegistry.qml")
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range regexp.MustCompile(`(?:id: |lockWidget\()"(\w+)"`).FindAllStringSubmatch(string(registry), -1) {
		if !slices.Contains(builtinWidgets, m[1]) {
			t.Errorf("built-in widget %s is missing from builtinWidgets, so imports drop it", m[1])
		}
	}
}
