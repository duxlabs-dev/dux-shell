package iconfolders

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func hct(t *testing.T, hex string) color.Hct {
	var argb color.ARGB
	require.NoError(t, argb.UnmarshalText([]byte(hex)))
	return argb.ToHct()
}

func TestRamp(t *testing.T) {
	t.Run("back is the primary twelve tones darker", func(t *testing.T) {
		ramp, err := NewRamp("69B2FF", "#003055")
		require.NoError(t, err)
		assert.Equal(t, "#69b2ff", ramp.Front)
		assert.Equal(t, "#003055", ramp.Glyph)

		front, back := hct(t, ramp.Front), hct(t, ramp.Back)
		assert.InDelta(t, front.Tone-12, back.Tone, 0.75)
		assert.InDelta(t, front.Hue, back.Hue, 3)
	})

	t.Run("back never drops below tone ten", func(t *testing.T) {
		ramp, err := NewRamp("#00214a", "")
		require.NoError(t, err)
		require.Less(t, hct(t, ramp.Front).Tone, 20.0)
		assert.InDelta(t, 10, hct(t, ramp.Back).Tone, 0.75)
		assert.Greater(t, hct(t, ramp.Glyph).Tone, 80.0, "a theme without on_primary still needs a readable glyph")
	})

	t.Run("rejects a primary that is not a color", func(t *testing.T) {
		_, err := NewRamp("blue", "")
		assert.Error(t, err)
	})
}

const adwaitaIndex = `[Icon Theme]
Name=Adwaita
Inherits=hicolor
Directories=16x16/places,scalable/places,scalable/status

[16x16/places]
Context=Places
Size=16
Type=Fixed

[scalable/places]
Context=Places
Size=128
MinSize=8
MaxSize=512
Type=Scalable

[scalable/status]
Context=Status
Size=128
MinSize=8
MaxSize=512
Type=Scalable
`

func adwaitaPack(e env) {
	e.write("Adwaita/index.theme", adwaitaIndex)
	e.write("Adwaita/16x16/places/folder.png", "raster")
	e.file("Adwaita/scalable/places/folder.svg", "adwaita-folder-documents.svg")
	e.file("Adwaita/scalable/places/network-workgroup.svg", "adwaita-network.svg")
	e.link("Adwaita/scalable/status/folder-open.svg", "../places/folder.svg")
}

func TestAdwaitaOverlay(t *testing.T) {
	e := newEnv(t)
	ramp := e.colors("#69b2ff", "#003055")
	adwaitaPack(e)

	state := e.apply("Adwaita")
	slot := filepath.Join(e.icons, state.Applied)

	want := e.fixture("adwaita-folder-documents.svg")
	want = strings.Replace(want, "#438de6", ramp.Back, 1)
	want = strings.NewReplacer(
		"#438de6", ramp.Glyph,
		"#62a0ea", ramp.Back,
		"#a4caee", ramp.Front,
		"#afd4ff", ramp.Front,
		"#c0d5ea", ramp.Front,
	).Replace(want)
	assert.Equal(t, want, e.overlay(state.Applied, "scalable/places/folder.svg"))

	target, err := os.Readlink(filepath.Join(slot, "scalable/status/folder-open.svg"))
	require.NoError(t, err)
	assert.Equal(t, "../places/folder.svg", target)

	assert.NoFileExists(t, filepath.Join(slot, "scalable/places/network-workgroup.svg"), "a shared palette blue outside the folder family is not folder art")
	assert.Equal(t, []string{state.Applied}, e.generated(), "a raster folder would keep the stock color, so it is not carried; the scalable one answers instead")
	assert.Equal(t, map[string]string{"folder": "scalable/places/folder.svg", "folder-open": "scalable/status/folder-open.svg"}, state.Icons)
	assert.NotContains(t, e.overlay(state.Applied, "index.theme"), "FollowsColorScheme")

	t.Run("light mode takes the light roles", func(t *testing.T) {
		opts := e.opts("Adwaita")
		opts.Mode = "light"
		light, err := Apply(opts)
		require.NoError(t, err)
		assert.Contains(t, e.overlay(light.Applied, "scalable/places/folder.svg"), `fill="#005e9e"`)
	})
}

const breezeIndex = `[Icon Theme]
Name=Breeze Dark
Inherits=hicolor
FollowsColorScheme=true
Directories=places/22,places/32,places/64,places/96,mimetypes/64
ScaledDirectories=places/22@2x,places/128@2x

[places/22]
Context=Places
Size=22
Type=Fixed

[places/32]
Context=Places
Size=32
Type=Fixed

[places/128@2x]
Context=Places
Size=128
Scale=2
Type=Fixed

[places/22@2x]
Context=Places
Size=22
Scale=2
Type=Fixed

[places/64]
Context=Places
Size=64
Type=Fixed

[places/96]
Context=Places
Size=96
MinSize=96
MaxSize=256
Type=Scalable

[mimetypes/64]
Context=MimeTypes
Size=64
Type=Fixed
`

func TestBreezeOverlay(t *testing.T) {
	e := newEnv(t)
	ramp := e.colors("#69b2ff", "#003055")
	e.write("breeze-dark/index.theme", breezeIndex)
	e.file("breeze-dark/places/22/folder.svg", "mono-folder.svg")
	e.file("breeze-dark/places/22/folder-red.svg", "mono-folder.svg")
	e.link("breeze-dark/places/22@2x", "22")
	e.file("breeze-dark/places/64/folder.svg", "breeze-folder.svg")
	e.file("breeze-dark/places/64/folder-red.svg", "breeze-folder-red.svg")
	e.file("breeze-dark/places/96/folder.svg", "breeze-folder-attr.svg")
	e.link("breeze-dark/mimetypes/64/inode-directory.svg", "../../places/64/folder.svg")
	e.file("breeze-dark/mimetypes/64/text-x-accent.svg", "breeze-folder.svg")
	for _, size := range []string{"32", "64", "128@2x"} {
		e.file("breeze-dark/places/"+size+"/user-home.svg", "breeze-folder.svg")
	}

	state := e.apply("breeze-dark")
	slot := filepath.Join(e.icons, state.Applied)

	t.Run("bakes the ramp into the elements", func(t *testing.T) {
		folder := e.overlay(state.Applied, "places/64/folder.svg")
		assert.Contains(t, folder, `<path style="fill:`+ramp.Front+`" d="M 4 6 H 28 L 32 10 H 60 V 58 H 4 Z"/>`)
		assert.Contains(t, folder, `<path style="fill:`+ramp.Back+`" d="M 4 6 H 28 L 32 10 H 60 V 16 H 26 L 22 20 H 4 Z"/>`)
		assert.Contains(t, folder, `<path style="fill:`+ramp.Glyph+`;stroke:none" d="M 23 27 H 41 V 47 H 23 Z"/>`, "the glyph is opaque: at the pack's 0.6 it falls under 3:1 on some schemes")
		assert.NotContains(t, folder, `class="ColorScheme-Accent"`, "KIconLoader would repaint a class it knows with the KDE scheme")
		assert.Contains(t, folder, `<path style="fill:#ffffff;fill-opacity:0.2" d="M 28 6 L 31 11 H 60 V 10 H 32 Z"/>`)
		assert.Contains(t, folder, `<path style="fill-opacity:0.2;fill-rule:evenodd" d="M 4 57 H 60 V 58 H 4 Z" class="ColorScheme-Text"/>`)
		assert.Contains(t, folder, `<path style="fill:#f89406;fill-opacity:0.33" d="M 44 44 H 56 V 56 H 44 Z"/>`, "only the unfilled overlay is the back plate")
	})

	t.Run("handles the attribute form of the back plate", func(t *testing.T) {
		folder := e.overlay(state.Applied, "places/96/folder.svg")
		assert.Contains(t, folder, `<path d="m6 9h36l6 6h42v9h-51l-6 6h-27z" fill="`+ramp.Back+`"/>`)
		assert.Contains(t, folder, `<path d="m42 9 5 7h43v-1h-42z" fill="#fff" fill-opacity=".2"/>`)
		assert.Contains(t, folder, `<path d="m5 86v1h86v-1z" fill-opacity=".2"/>`)
	})

	t.Run("carries monochrome sizes and hard-coded variants unchanged", func(t *testing.T) {
		assert.Equal(t, e.fixture("mono-folder.svg"), e.overlay(state.Applied, "places/22/folder.svg"))
		assert.Equal(t, e.fixture("mono-folder.svg"), e.overlay(state.Applied, "places/22@2x/folder.svg"))
		assert.Equal(t, e.fixture("breeze-folder-red.svg"), e.overlay(state.Applied, "places/64/folder-red.svg"))
		assert.Equal(t, map[string]bool{"folder": true, "folder-red": true, "inode-directory": true, "user-home": true}, iconNames(t, slot), "accent art outside places is not a folder")
	})

	t.Run("lists the scalable file, else the largest at scale one", func(t *testing.T) {
		assert.Equal(t, map[string]string{
			"folder":          "places/96/folder.svg",
			"user-home":       "places/64/user-home.svg",
			"inode-directory": "mimetypes/64/inode-directory.svg",
		}, state.Icons)
	})

	t.Run("keeps links that cross directories", func(t *testing.T) {
		target, err := os.Readlink(filepath.Join(slot, "mimetypes/64/inode-directory.svg"))
		require.NoError(t, err)
		assert.Equal(t, "../../places/64/folder.svg", target)
		assert.Contains(t, e.overlay(state.Applied, "mimetypes/64/inode-directory.svg"), ramp.Front)
	})
}

const telaIndex = `[Icon Theme]
Name=Tela
Inherits=hicolor
FollowsColorScheme=true
Directories=16/places,scalable/places,symbolic/places

[16/places]
Context=Places
Size=16
Type=Fixed

[scalable/places]
Context=Places
Size=64
MinSize=22
MaxSize=512
Type=Scalable

[symbolic/places]
Context=Places
Size=16
MinSize=16
MaxSize=512
Type=Scalable
`

func TestTelaOverlay(t *testing.T) {
	e := newEnv(t)
	ramp := e.colors("#69b2ff", "#003055")
	e.write("Tela/index.theme", telaIndex)
	e.file("Tela/scalable/places/default-folder.svg", "tela-folder.svg")
	e.link("Tela/scalable/places/folder.svg", "default-folder.svg")
	e.file("Tela/scalable/places/folder-appimage.svg", "tela-folder.svg")
	e.file("Tela/scalable/places/folder-android.svg", "tela-folder-own.svg")
	e.file("Tela/scalable/places/red-folder.svg", "tela-folder-red.svg")
	e.link("Tela/scalable/places/folder-red.svg", "red-folder.svg")
	e.file("Tela/16/places/folder.svg", "tela-folder-16.svg")
	e.file("Tela/symbolic/places/folder-symbolic.svg", "tela-folder-16.svg")

	state := e.apply("Tela")
	slot := filepath.Join(e.icons, state.Applied)

	want := strings.NewReplacer("#5294e2", ramp.Front, "#ffffff", ramp.Glyph).Replace(e.fixture("tela-folder.svg"))
	assert.Equal(t, want, e.overlay(state.Applied, "scalable/places/folder.svg"), "white on a light primary would not read, so paper and glyph take the glyph role")
	assert.NoFileExists(t, filepath.Join(slot, "scalable/places/default-folder.svg"), "the stock variant is only reached through the names linked to it")
	assert.Equal(t, want, e.overlay(state.Applied, "scalable/places/folder-appimage.svg"))
	assert.Contains(t, e.overlay(state.Applied, "16/places/folder.svg"), "color:"+ramp.Front)
	assert.Equal(t, "scalable/places/folder.svg", state.Icons["folder"])
	assert.Contains(t, e.overlay(state.Applied, "index.theme"), "FollowsColorScheme=true")

	assert.Equal(t, e.fixture("tela-folder-own.svg"), e.overlay(state.Applied, "scalable/places/folder-android.svg"), "a folder in its own color has no front color, so its white stays")
	assert.Equal(t, e.fixture("tela-folder-red.svg"), e.overlay(state.Applied, "scalable/places/folder-red.svg"), "the red a color variant installs is also the pack's own red folder")
	assert.Equal(t, e.fixture("tela-folder-16.svg"), e.overlay(state.Applied, "symbolic/places/folder-symbolic.svg"), "toolkits paint symbolic icons themselves")

	t.Run("a color variant carries its color in place of the stock blue", func(t *testing.T) {
		e.write("Tela-red/index.theme", telaIndex)
		e.file("Tela-red/scalable/places/default-folder.svg", "tela-folder-red.svg")
		e.link("Tela-red/scalable/places/folder.svg", "default-folder.svg")
		e.write("Tela-red-dark/index.theme", telaIndex)
		e.link("Tela-red-dark/scalable", "../Tela-red/scalable")

		state := e.apply("Tela-red-dark")
		want := strings.NewReplacer("#ef5350", ramp.Front, "#ffffff", ramp.Glyph).Replace(e.fixture("tela-folder-red.svg"))
		assert.Equal(t, want, e.overlay(state.Applied, "scalable/places/folder.svg"))
	})
}

const colloidIndex = `[Icon Theme]
Name=Colloid
Inherits=hicolor
Directories=places/scalable

[places/scalable]
Context=Places
Size=64
MinSize=16
MaxSize=512
Type=Scalable
`

func TestColloidOverlay(t *testing.T) {
	e := newEnv(t)
	ramp := e.colors("#69b2ff", "#003055")
	e.write("Colloid-Light/index.theme", colloidIndex)
	e.file("Colloid-Light/places/scalable/folder.svg", "colloid-folder.svg")
	e.file("Colloid-Light/places/scalable/folder-encrypted.svg", "colloid-folder-encrypted.svg")
	e.link("Colloid-Light/places/scalable/inode-directory.svg", "folder.svg")
	e.write("Colloid/index.theme", colloidIndex)
	e.link("Colloid/places", "../Colloid-Light/places")

	state := e.apply("Colloid")
	assert.Equal(t, strings.ReplaceAll(e.fixture("colloid-folder.svg"), "#60c0f0", ramp.Front), e.overlay(state.Applied, "places/scalable/folder.svg"))
	assert.Equal(t, e.fixture("colloid-folder-encrypted.svg"), e.overlay(state.Applied, "places/scalable/folder-encrypted.svg"))
	target, err := os.Readlink(filepath.Join(e.icons, state.Applied, "places/scalable/inode-directory.svg"))
	require.NoError(t, err)
	assert.Equal(t, "folder.svg", target)

	t.Run("an accent variant carries its color inline", func(t *testing.T) {
		e.write("Colloid-Purple-Dark/index.theme", colloidIndex)
		e.file("Colloid-Purple-Dark/places/scalable/folder.svg", "colloid-folder-purple.svg")

		state := e.apply("Colloid-Purple-Dark")
		assert.Equal(t, strings.ReplaceAll(e.fixture("colloid-folder-purple.svg"), "#BA68C8", ramp.Front), e.overlay(state.Applied, "places/scalable/folder.svg"))
	})

	t.Run("the grey accent is not covered: its color is also a detail color of the stock pack", func(t *testing.T) {
		e.write("Colloid-Grey/index.theme", colloidIndex)
		e.file("Colloid-Grey/places/scalable/folder.svg", "colloid-folder-encrypted.svg")

		assert.Equal(t, CodeNoColoredFolders, ProbeTheme(e.opts("Colloid-Grey")).Code)
	})
}

func TestRecipeFilesAreChecked(t *testing.T) {
	r, err := parseRecipe("demo", []byte(`{"themes": ["Demo", "Demo-*"], "icons": ["folder"], "stock": ["folder-blue*"], "palette": "folder-blue", "colors": {"#112233": "front", "#445566": ["back", "glyph"]}}`))
	require.NoError(t, err)
	assert.True(t, r.matches("Demo-dark"))
	assert.False(t, r.matches("Demolition"))
	assert.True(t, r.source("places", "folder") && r.source("places", "folder-blue-documents"))
	assert.False(t, r.hidden("folder"))
	assert.True(t, r.hidden("folder-blue"))
	assert.NotNil(t, r.palette)

	out, ok := r.recolor([]byte("#445566 #112233 #445566 #445566 #778899"), Ramp{Front: "F", Back: "B", Glyph: "G"})
	assert.True(t, ok)
	assert.Equal(t, "B F G G #778899", string(out))
	_, ok = r.recolor([]byte("#445566"), Ramp{})
	assert.False(t, ok, "a file without a front color is not a folder of this pack")

	crowded := `{"themes": ["Demo"], "icons": ["folder"], "colors": {"#112233": "front"`
	for i := range maxRecipeEntries {
		crowded += fmt.Sprintf(`, "#%06x": "back"`, i)
	}
	tests := []struct {
		name   string
		recipe string
		want   string
	}{
		{"not an object", `["Demo"]`, "cannot unmarshal"},
		{"a key that is not part of a recipe", `{"themes": ["Demo"], "icons": ["folder"], "colors": {"#112233": "front"}, "command": "./run"}`, "unknown field"},
		{"no themes", `{"icons": ["folder"], "colors": {"#112233": "front"}}`, "no themes"},
		{"no icons", `{"themes": ["Demo"], "colors": {"#112233": "front"}}`, "no icons"},
		{"too many entries", crowded + "}}", "too many entries"},
		{"a palette that is not a variant name", `{"themes": ["Demo"], "icons": ["folder"], "palette": "../blue", "colors": {"#112233": "front"}}`, "bad palette"},
		{"a pattern for every theme", `{"themes": ["*"], "icons": ["folder"], "colors": {"#112233": "front"}}`, "bad pattern"},
		{"a pattern that cannot be read", `{"themes": ["Demo"], "icons": ["folder[a"], "colors": {"#112233": "front"}}`, "bad pattern"},
		{"an empty pattern", `{"themes": ["Demo"], "icons": ["folder"], "stock": [""], "colors": {"#112233": "front"}}`, "bad pattern"},
		{"a color that is not six lowercase hex digits", `{"themes": ["Demo"], "icons": ["folder"], "colors": {"#11223G": "front"}}`, "bad color"},
		{"a short color", `{"themes": ["Demo"], "icons": ["folder"], "colors": {"#123": "front"}}`, "bad color"},
		{"a color without a role", `{"themes": ["Demo"], "icons": ["folder"], "colors": {"#112233": []}}`, "bad color"},
		{"a role that does not exist", `{"themes": ["Demo"], "icons": ["folder"], "colors": {"#112233": "front", "#445566": "sky"}}`, "bad role"},
		{"nothing mapped to front", `{"themes": ["Demo"], "icons": ["folder"], "colors": {"#112233": "back"}}`, "no front color"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := parseRecipe("demo", []byte(tc.recipe))
			assert.ErrorContains(t, err, tc.want)
		})
	}
}

const demoIndex = `[Icon Theme]
Name=Demo
Directories=places

[places]
Context=Places
Size=48
Type=Scalable
`

func (e env) plugin(dir, id, recipes string) {
	path := filepath.Join(filepath.Dir(e.state), dir, id, "plugin.json")
	require.NoError(e.t, os.MkdirAll(filepath.Dir(path), 0o755))
	require.NoError(e.t, os.WriteFile(path, fmt.Appendf(nil, `{"id": %q, "name": "Folders", "iconFolders": %s}`, id, recipes), 0o644))
}

func (e env) enable(ids ...string) {
	settings := map[string]any{"notAPlugin": 3}
	for _, id := range ids {
		settings[id] = map[string]any{"enabled": true}
	}
	data, err := json.Marshal(settings)
	require.NoError(e.t, err)
	require.NoError(e.t, os.WriteFile(filepath.Join(filepath.Dir(e.state), "plugin_settings.json"), data, 0o644))
}

func TestPluginRecipeRecolorsItsPack(t *testing.T) {
	e := newEnv(t)
	ramp := e.colors("#69b2ff", "#003055")
	e.write("Demo/index.theme", demoIndex)
	e.write("Demo/places/folder.svg", `<svg><path fill="#112233"/><path fill="#445566"/></svg>`)
	front := `{"themes": ["Demo"], "icons": ["folder"], "colors": {"#112233": "front"}}`

	skipped := `[{"themes": ["Demo"], "icons": ["folder"], "colors": {"#112233": "sky"}}, `
	e.plugin("plugins", "demoFolders", skipped+front+`]`)
	assert.Equal(t, CodeUnsupportedPack, ProbeTheme(e.opts("Demo")).Code, "a plugin that is not switched on adds nothing")

	e.enable("demoFolders")
	assert.True(t, ProbeTheme(e.opts("Demo")).Supported, "a recipe that fails its check is skipped and the next still answers")
	state := e.apply("Demo")
	assert.Equal(t, `<svg><path fill="`+ramp.Front+`"/><path fill="#445566"/></svg>`, e.overlay(state.Applied, "places/folder.svg"))

	e.plugin("system-plugins", "demoFolders", `[{"themes": ["Demo"], "icons": ["folder"], "colors": {"#112233": "front", "#445566": "glyph"}}]`)
	assert.Equal(t, state, e.apply("Demo"), "the user's plugin comes before a system one for the same pack")

	e.plugin("plugins", "demoFolders", skipped+`{"themes": ["Demo"], "icons": ["folder"], "colors": {"#112233": "front", "#445566": "back"}}]`)
	edited := e.apply("Demo")
	assert.NotEqual(t, state.Applied, edited.Applied, "an edited recipe must not answer with the overlay of the old one")
	assert.Equal(t, `<svg><path fill="`+ramp.Front+`"/><path fill="`+ramp.Back+`"/></svg>`, e.overlay(edited.Applied, "places/folder.svg"))

	t.Run("a pack DMS knows keeps its built-in recipe", func(t *testing.T) {
		adwaitaPack(e)
		e.plugin("plugins", "adwaitaFolders", `[{"themes": ["Adwaita"], "icons": ["folder"], "colors": {"#438de6": "front"}}]`)
		e.enable("demoFolders", "adwaitaFolders")

		state := e.apply("Adwaita")
		assert.Contains(t, e.overlay(state.Applied, "scalable/places/folder.svg"), ramp.Back)
	})

	t.Run("switching the plugin off drops the pack", func(t *testing.T) {
		e.enable()
		assert.Equal(t, State{}, e.apply("Demo"))
	})
}

func TestUserPluginsCanBeSwitchedOffByPolicy(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", "/config")
	dirs, settings := defaultPluginDirs()
	assert.Equal(t, []string{"/config/dms/plugins", systemPluginsDir}, dirs)
	assert.Equal(t, "/config/dms/plugin_settings.json", settings)

	t.Setenv("DMS_POLICY_DISABLE_USER_PLUGINS", "1")
	dirs, _ = defaultPluginDirs()
	assert.Equal(t, []string{systemPluginsDir}, dirs)
}

func TestPapirusPaletteNeedsACompleteColorSet(t *testing.T) {
	palette := paletteOf("folder-blue", map[string]bool{"folder-blue": true, "folder-new": true, "folder-open": true})
	assert.False(t, palette("folder-new"), "with nothing to compare against, every folder-<word> would pass for a color and none be carried")
}
