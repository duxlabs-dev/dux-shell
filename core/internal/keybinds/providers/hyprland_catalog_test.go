package providers

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// hyprlandCatalogSamples fills required params for catalog ids the editor
// completes through HYPRLAND_ACTION_ARGS.
var hyprlandCatalogSamples = map[string]string{
	"workspace":                      "1",
	"movetoworkspace":                "2",
	"movetoworkspacesilent":          "2",
	"focusworkspaceoncurrentmonitor": "1",
	"renameworkspace":                "1 work",
	"focusmonitor":                   "DP-1",
	"movecurrentworkspacetomonitor":  "DP-1",
	"moveworkspacetomonitor":         "1 DP-1",
	"swapactiveworkspaces":           "DP-1 DP-2",
	"fullscreenstate":                "2 0",
	"resizeactive":                   "10 -10",
	"moveactive":                     "10 -10",
	"resizewindowpixel":              "100 100,class:^(app)$",
	"movewindowpixel":                "100 100,class:^(app)$",
	"splitratio":                     "+0.1",
	"focuswindow":                    "class:^(app)$",
	"alterzorder":                    "top",
	"setprop":                        "class:^(app)$ opaque 1",
	"forceidle":                      "300",
	"movecursortocorner":             "0",
	"movecursor":                     "100 100",
	"changegroupactive":              "2",
	"movefocus":                      "l",
	"swapwindow":                     "l",
	"pass":                           "class:^(app)$",
	"sendshortcut":                   "SUPER F4",
	"sendkeystate":                   "SUPER a down class:^(app)$",
	"layoutmsg":                      "togglesplit",
}

func jsObjectBlock(t *testing.T, src, name string) string {
	t.Helper()
	start := strings.Index(src, "const "+name+" = {")
	if start < 0 {
		t.Fatalf("%s not found in KeybindActions.js", name)
	}
	end := strings.Index(src[start:], "\n};")
	if end < 0 {
		t.Fatalf("%s is not terminated", name)
	}
	return src[start : start+end]
}

func TestHyprlandKeybindCatalogMapsToLua(t *testing.T) {
	data, err := os.ReadFile("../../../../quickshell/Common/KeybindActions.js")
	if os.IsNotExist(err) {
		t.Skip("quickshell tree not available")
	}
	if err != nil {
		t.Fatal(err)
	}
	src := string(data)
	ids := regexp.MustCompile(`id: "([^"]+)"`).FindAllStringSubmatch(jsObjectBlock(t, src, "HYPRLAND_ACTIONS"), -1)
	if len(ids) == 0 {
		t.Fatal("no Hyprland catalog ids found")
	}
	argBases := map[string]bool{}
	for _, m := range regexp.MustCompile(`(?m)^    "([a-z_]+)": \{`).FindAllStringSubmatch(jsObjectBlock(t, src, "HYPRLAND_ACTION_ARGS"), -1) {
		argBases[m[1]] = true
	}
	for _, m := range ids {
		id := m[1]
		if _, ok := luaActionStringFromHyprlangAction(id); ok {
			continue
		}
		sample, hasSample := hyprlandCatalogSamples[id]
		if !argBases[id] || !hasSample {
			t.Errorf("catalog id %q has no Lua dispatcher", id)
			continue
		}
		if _, ok := luaActionStringFromHyprlangAction(id + " " + sample); !ok {
			t.Errorf("catalog id %q with %q has no Lua dispatcher", id, sample)
		}
	}
}
