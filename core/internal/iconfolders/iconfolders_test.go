package iconfolders

import (
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type env struct {
	t     *testing.T
	state string
	icons string
	sys   string
}

func newEnv(t *testing.T) env {
	root := t.TempDir()
	e := env{t: t, state: filepath.Join(root, "state"), icons: filepath.Join(root, "user"), sys: filepath.Join(root, "sys")}
	e.colors("#69b2ff", "#003055")
	return e
}

func (e env) opts(theme string) Options {
	root := filepath.Dir(e.state)
	return Options{
		StateDir: e.state, IconTheme: theme, Mode: "dark", IconsDir: e.icons, BaseDirs: []string{e.icons, e.sys},
		PluginDirs: []string{filepath.Join(root, "plugins"), filepath.Join(root, "system-plugins")}, PluginSettings: filepath.Join(root, "plugin_settings.json"),
		TileTone: ToneAuto, OwnTone: ToneAuto,
	}
}

func (e env) colors(primary, onPrimary string) Ramp {
	body, err := json.Marshal(map[string]any{"colors": map[string]any{
		"dark":  map[string]string{"primary": primary, "on_primary": onPrimary},
		"light": map[string]string{"primary": "#005e9e", "on_primary": "#edf3ff"},
	}})
	require.NoError(e.t, err)
	require.NoError(e.t, os.MkdirAll(e.state, 0o755))
	require.NoError(e.t, os.WriteFile(filepath.Join(e.state, "dms-colors.json"), body, 0o644))
	ramp, err := NewRamp(primary, onPrimary)
	require.NoError(e.t, err)
	return ramp
}

func (e env) write(rel, content string) {
	path := filepath.Join(e.sys, rel)
	require.NoError(e.t, os.MkdirAll(filepath.Dir(path), 0o755))
	require.NoError(e.t, os.WriteFile(path, []byte(content), 0o644))
}

func (e env) file(rel, fixture string) {
	e.write(rel, e.fixture(fixture))
}

func (e env) fixture(name string) string {
	data, err := os.ReadFile(filepath.Join("testdata", name))
	require.NoError(e.t, err)
	return string(data)
}

func (e env) link(rel, target string) {
	path := filepath.Join(e.sys, rel)
	require.NoError(e.t, os.MkdirAll(filepath.Dir(path), 0o755))
	require.NoError(e.t, os.Symlink(target, path))
}

func (e env) overlay(slot, rel string) string {
	data, err := os.ReadFile(filepath.Join(e.icons, slot, rel))
	require.NoError(e.t, err)
	return string(data)
}

func (e env) generated() []string {
	entries, err := os.ReadDir(e.icons)
	if os.IsNotExist(err) {
		return nil
	}
	require.NoError(e.t, err)
	var names []string
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	return names
}

func (e env) apply(theme string) State {
	state, err := Apply(e.opts(theme))
	require.NoError(e.t, err)
	return state
}

func iconNames(t *testing.T, roots ...string) map[string]bool {
	names := map[string]bool{}
	for _, root := range roots {
		require.NoError(t, filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
			if err == nil && !entry.IsDir() && isIcon(path) {
				names[iconName(filepath.Base(path))] = true
			}
			return err
		}))
	}
	return names
}

const papirusIndex = `[Icon Theme]
Name=Papirus
Inherits=hicolor
FollowsColorScheme=true
Directories=16x16/actions,16x16/places,48x48/places,48x48/mimetypes,48x48/apps,128x128/places
ScaledDirectories=16x16@2x/places,48x48@2x/places

[16x16/actions]
Context=Actions
Size=16
Type=Fixed

[16x16/places]
Context=Places
Size=16
Type=Fixed

[16x16@2x/places]
Context=Places
Size=16
Scale=2
Type=Fixed

[48x48/places]
Context=Places
Size=48
Type=Fixed

[48x48@2x/places]
Context=Places
Size=48
Scale=2
Type=Fixed

[48x48/mimetypes]
Context=MimeTypes
Size=48
Type=Fixed

[48x48/apps]
Context=Applications
Size=48
Type=Fixed

[128x128/places]
Context=Places
Size=128
MinSize=128
MaxSize=512
Type=Scalable
`

// Mirrors the real pack: symlinked folder names, a monochrome 16px, and linked sizes.
func papirusPack(e env) {
	e.write("Papirus/index.theme", papirusIndex)

	e.file("Papirus/16x16/actions/document.svg", "mono-action.svg")
	e.file("Papirus/16x16/actions/folder-new.svg", "mono-action.svg")
	e.file("Papirus/16x16/actions/folder-new-symbolic.svg", "mono-action.svg")
	e.file("Papirus/16x16/actions/stock_folder-copy.svg", "mono-action.svg")
	e.file("Papirus/16x16/actions/network-wired.svg", "mono-action.svg")
	e.file("Papirus/16x16/actions/emblem-shared-symbolic.svg", "mono-action.svg")
	e.file("Papirus/16x16/places/folder.svg", "mono-folder.svg")
	e.file("Papirus/16x16/places/folder-blue.svg", "papirus-folder.svg")
	e.write("Papirus/16x16/places/folder-bookmarks.png", "raster")
	e.link("Papirus/16x16/places/inode-directory.svg", "folder.svg")
	e.link("Papirus/16x16/places/folder-documents.svg", "../actions/document.svg")
	e.link("Papirus/16x16@2x", "16x16")

	e.file("Papirus/48x48/places/folder-blue.svg", "papirus-folder.svg")
	e.file("Papirus/48x48/places/folder-blue-documents.svg", "papirus-folder-documents.svg")
	e.file("Papirus/48x48/places/folder-red.svg", "papirus-folder-red.svg")
	e.file("Papirus/48x48/places/folder-red-documents.svg", "papirus-folder-red.svg")
	e.link("Papirus/48x48/places/folder-red-docs.svg", "folder-red-documents.svg")
	e.file("Papirus/48x48/places/folder-root.svg", "papirus-folder-red.svg")
	e.file("Papirus/48x48/places/user-trash.svg", "papirus-trash.svg")
	e.link("Papirus/48x48/places/folder-blue-docs.svg", "folder-blue-documents.svg")
	e.link("Papirus/48x48/places/folder.svg", "folder-blue.svg")
	e.link("Papirus/48x48/places/folder-documents.svg", "folder-blue-documents.svg")
	e.link("Papirus/48x48/places/inode-directory.svg", "folder.svg")
	e.link("Papirus/48x48/places/stock_folder.svg", "folder.svg")
	e.link("Papirus/48x48/places/network.svg", "folder-blue.svg")
	e.link("Papirus/48x48/places/emblem-symbolic.svg", "folder-blue.svg")
	e.link("Papirus/48x48/places/library-music.svg", "folder-blue-documents.svg")
	e.link("Papirus/48x48/mimetypes/application-x-share.svg", "../places/folder.svg")
	e.link("Papirus/48x48/apps/system-file-manager.svg", "../places/folder.svg")
	e.link("Papirus/48x48@2x", "48x48")
	e.link("Papirus/128x128/places", "../48x48/places")
}

func TestPapirusOverlay(t *testing.T) {
	e := newEnv(t)
	ramp := e.colors("#69b2ff", "#003055")
	papirusPack(e)

	state := e.apply("Papirus")
	require.Regexp(t, regexp.MustCompile(`^Papirus-dms-[0-9a-f]{8}$`), state.Applied)
	assert.Equal(t, "Papirus-dms-"+state.Inputs[:8], state.Applied)
	assert.Equal(t, filepath.Join(e.icons, state.Applied), state.Dir)
	assert.Equal(t, state, ReadState(e.state))
	assert.Equal(t, []string{state.Applied}, e.generated(), "the staging directory must be gone after the rename")

	entries, err := os.ReadDir(e.state)
	require.NoError(t, err)
	assert.Len(t, entries, 2, "the state file is renamed into place; only it and the colors may be here")

	slot := filepath.Join(e.icons, state.Applied)

	t.Run("recolors the default folder under its plain name", func(t *testing.T) {
		info, err := os.Lstat(filepath.Join(slot, "48x48/places/folder.svg"))
		require.NoError(t, err)
		assert.True(t, info.Mode().IsRegular(), "a link into the hidden blue variant becomes a real file")

		folder := e.overlay(state.Applied, "48x48/places/folder.svg")
		assert.Contains(t, folder, "fill:"+ramp.Back)
		assert.Contains(t, folder, "fill:"+ramp.Front, "hex matching must ignore case")
		assert.Contains(t, folder, "#e4e4e4", "paper keeps the pack's neutral")
		assert.NotContains(t, folder, "#4877b1")
		assert.Contains(t, e.overlay(state.Applied, "48x48/places/folder-documents.svg"), "fill:"+ramp.Glyph)
		assert.Contains(t, e.overlay(state.Applied, "48x48/places/library-music.svg"), "fill:"+ramp.Glyph, "a pack alias of a folder is a folder")
	})

	t.Run("reproduces symlinks onto the overlay's own files", func(t *testing.T) {
		for link, want := range map[string]string{
			"48x48/places/inode-directory.svg":        "folder.svg",
			"48x48/places/stock_folder.svg":           "folder.svg",
			"48x48/mimetypes/application-x-share.svg": "../places/folder.svg",
			"16x16/places/inode-directory.svg":        "folder.svg",
		} {
			target, err := os.Readlink(filepath.Join(slot, link))
			require.NoError(t, err, link)
			assert.Equal(t, want, target, link)
		}
		assert.Contains(t, e.overlay(state.Applied, "48x48/mimetypes/application-x-share.svg"), ramp.Front)
	})

	t.Run("passes monochrome sizes through unchanged", func(t *testing.T) {
		assert.Equal(t, e.fixture("mono-folder.svg"), e.overlay(state.Applied, "16x16/places/folder.svg"))

		info, err := os.Lstat(filepath.Join(slot, "16x16/places/folder-documents.svg"))
		require.NoError(t, err)
		assert.True(t, info.Mode().IsRegular(), "a link to an icon that is not carried must be copied, not reproduced")
		assert.Equal(t, e.fixture("mono-action.svg"), e.overlay(state.Applied, "16x16/places/folder-documents.svg"))
	})

	t.Run("declares the directories it wrote and the ones it shares", func(t *testing.T) {
		for alias, canonical := range map[string]string{"48x48@2x/places": "48x48/places", "128x128/places": "48x48/places", "16x16@2x/places": "16x16/places"} {
			linked, err := filepath.EvalSymlinks(filepath.Join(slot, alias))
			require.NoError(t, err)
			real, err := filepath.EvalSymlinks(filepath.Join(slot, canonical))
			require.NoError(t, err)
			assert.Equal(t, real, linked, alias)
		}

		th := parseIndex([]byte(e.overlay(state.Applied, "index.theme")))
		var dirs []string
		keys := map[string]map[string]string{}
		for _, dir := range th.dirs {
			dirs = append(dirs, dir.rel)
			keys[dir.rel] = dir.keys
		}
		assert.Equal(t, []string{
			"16x16/actions", "16x16/places", "48x48/places", "48x48/mimetypes", "128x128/places",
			"16x16@2x/places", "48x48@2x/places",
		}, dirs)
		assert.Equal(t, map[string]string{"Context": "Places", "Size": "48", "Scale": "2", "Type": "Fixed"}, keys["48x48@2x/places"])
		assert.Equal(t, map[string]string{"Context": "Actions", "Size": "16", "Type": "Fixed"}, keys["16x16/actions"])
		assert.Equal(t, "true", th.follow)

		index := e.overlay(state.Applied, "index.theme")
		assert.Contains(t, index, "\nInherits=Papirus,hicolor\n")
		assert.Contains(t, index, "\nHidden=true\n")
		assert.Contains(t, index, "\nX-DMS-Generated=icon-folders\n")
		assert.Contains(t, index, "\nScaledDirectories=16x16@2x/places,48x48@2x/places\n")
	})

	t.Run("lists one file per recolored icon, scalable first", func(t *testing.T) {
		assert.Equal(t, map[string]string{
			"folder":              "128x128/places/folder.svg",
			"folder-documents":    "128x128/places/folder-documents.svg",
			"inode-directory":     "128x128/places/inode-directory.svg",
			"stock_folder":        "128x128/places/stock_folder.svg",
			"library-music":       "128x128/places/library-music.svg",
			"application-x-share": "48x48/mimetypes/application-x-share.svg",
		}, state.Icons)
		for icon, rel := range state.Icons {
			assert.Contains(t, e.overlay(state.Applied, rel), ramp.Front, icon)
		}
	})
}

// GTK tries each fallback name in the applied theme first, so only palette variants may shadow.
func TestOverlayShadowsNoBaseIconButPaletteVariants(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	state := e.apply("Papirus")

	variant := regexp.MustCompile(`^folder-(blue|red)(-.+)?$`)
	overlay := iconNames(t, filepath.Join(e.icons, state.Applied))
	variants := 0
	for icon := range iconNames(t, filepath.Join(e.sys, "Papirus")) {
		if variant.MatchString(icon) {
			variants++
			assert.False(t, overlay[icon], "%s is a color variant; carrying all of those is 38 MB on the real pack", icon)
			continue
		}
		if overlay[icon] {
			continue
		}
		for cut := strings.LastIndex(icon, "-"); cut > 0; cut = strings.LastIndex(icon[:cut], "-") {
			assert.False(t, overlay[icon[:cut]], "%s would be answered by the overlay's %s", icon, icon[:cut])
			assert.False(t, overlay[icon[:cut]+"-symbolic"], "%s would be answered by the overlay's %s-symbolic", icon, icon[:cut])
		}
	}

	assert.False(t, overlay["network"], "an alias that shadows other icons is left to the base")
	assert.False(t, overlay["emblem-symbolic"], "GTK also tries the symbolic form of each shorter name")
	assert.True(t, overlay["library-music"], "an alias that shadows nothing is recolored")
	assert.True(t, overlay["stock_folder"], "the stock ids of the folder stay")
	assert.Equal(t, 6, variants)
	assert.Equal(t, map[string]bool{
		"folder": true, "inode-directory": true, "folder-documents": true, "stock_folder": true, "library-music": true, "application-x-share": true,
		"folder-root": true, "folder-new": true, "folder-new-symbolic": true, "folder-bookmarks": true, "stock_folder-copy": true,
	}, overlay, "what a folder name shadows is carried unchanged, in every context and format")
	for _, rel := range []string{"16x16/actions/folder-new.svg", "16x16/actions/folder-new-symbolic.svg", "16x16/actions/stock_folder-copy.svg"} {
		assert.Equal(t, e.fixture("mono-action.svg"), e.overlay(state.Applied, rel), rel)
	}
	assert.Equal(t, "raster", e.overlay(state.Applied, "16x16/places/folder-bookmarks.png"))
	assert.Equal(t, e.fixture("papirus-folder-red.svg"), e.overlay(state.Applied, "48x48/places/folder-root.svg"), "a folder with no color set of its own is not a variant")
}

func TestNameFollowsInputs(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)

	blue := e.apply("Papirus")
	marker := filepath.Join(e.icons, blue.Applied, "marker")
	require.NoError(t, os.WriteFile(marker, nil, 0o644))

	assert.Equal(t, blue, e.apply("Papirus"))
	assert.FileExists(t, marker, "unchanged inputs must not regenerate")

	ramp := e.colors("#a1d39a", "#0a390f")
	green := e.apply("Papirus")
	assert.NotEqual(t, blue.Applied, green.Applied, "toolkits only reload on a new name")
	assert.Equal(t, "Papirus-dms-"+green.Inputs[:8], green.Applied)
	assert.Contains(t, e.overlay(green.Applied, "48x48/places/folder.svg"), ramp.Front)
	assert.FileExists(t, marker, "running apps may still read the previous overlay")

	e.colors("#69b2ff", "#003055")
	assert.Equal(t, blue, e.apply("Papirus"), "the same inputs must give the same name")
	assert.FileExists(t, marker, "a name must never come back with different content")
	assert.Equal(t, blue, ReadState(e.state))

	e.colors("#fdb975", "#4a2800")
	orange := e.apply("Papirus")
	assert.ElementsMatch(t, []string{blue.Applied, orange.Applied}, e.generated(), "only the applied and the previously applied overlay stay")
}

func TestRegeneratesWhenTheBaseOrTheOverlayChanged(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	first := e.apply("Papirus")
	index := filepath.Join(e.sys, "Papirus/index.theme")
	info, err := os.Stat(index)
	require.NoError(t, err)
	dir, err := os.Stat(filepath.Dir(index))
	require.NoError(t, err)
	later := time.Now().Add(time.Hour)

	require.NoError(t, os.Chtimes(index, later, later))
	touched := e.apply("Papirus")
	assert.NotEqual(t, first.Applied, touched.Applied, "a changed index must regenerate")
	require.NoError(t, os.Chtimes(index, info.ModTime(), info.ModTime()))
	require.Equal(t, first, e.apply("Papirus"))

	require.NoError(t, os.Chtimes(filepath.Dir(index), later, later))
	updated := e.apply("Papirus")
	assert.NotEqual(t, first.Applied, updated.Applied, "a package update keeps the index mtime and only bumps the directory")
	require.NoError(t, os.Chtimes(filepath.Dir(index), dir.ModTime(), dir.ModTime()))
	require.Equal(t, first, e.apply("Papirus"))

	require.NoError(t, os.WriteFile(index, []byte(papirusIndex+"\n"), 0o644))
	require.NoError(t, os.Chtimes(index, info.ModTime(), info.ModTime()))
	require.NoError(t, os.Chtimes(filepath.Dir(index), dir.ModTime(), dir.ModTime()))
	resized := e.apply("Papirus")
	assert.NotEqual(t, first.Applied, resized.Applied, "an index of another size is another pack")

	require.NoError(t, os.RemoveAll(filepath.Join(e.icons, resized.Applied)))
	assert.Equal(t, resized, e.apply("Papirus"))
	assert.FileExists(t, filepath.Join(e.icons, resized.Applied, "16x16/places/folder.svg"), "a missing overlay is rebuilt even though the state already names it")
}

func TestANameSomethingElseHoldsIsNeverReplaced(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	first := e.apply("Papirus")
	ours := filepath.Join(e.icons, first.Applied)
	require.NoError(t, Clear(e.opts("")))

	require.NoError(t, os.MkdirAll(ours, 0o755))
	keepsake := filepath.Join(ours, "keepsake")
	require.NoError(t, os.WriteFile(keepsake, nil, 0o644))

	state, err := Apply(e.opts("Papirus"))
	assert.ErrorIs(t, err, ErrOccupied)
	assert.Equal(t, State{}, state)
	assert.FileExists(t, keepsake)
	assert.NoFileExists(t, filepath.Join(ours, "index.theme"))
	assert.NoFileExists(t, filepath.Join(e.state, StateFile), "a name that is not ours must not be handed to the toolkits")

	require.NoError(t, Clear(e.opts("")))
	assert.FileExists(t, keepsake, "clearing only removes what carries the generated key")
}

func TestUnsupportedThemeForgetsStateAndKeepsOverlays(t *testing.T) {
	tests := []struct {
		name  string
		theme string
		code  string
	}{
		{name: "no recipe for the theme", theme: "Fancy", code: "unsupported-pack"},
		{name: "placeholder for no theme", theme: "System Default", code: "system-default"},
		{name: "recipe matches but the theme is not installed", theme: "Papirus-Dark", code: "not-found"},
		{name: "recipe matches but finds none of its colors", theme: "Adwaita", code: "no-colored-folders"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			e := newEnv(t)
			papirusPack(e)
			e.write("Fancy/index.theme", "[Icon Theme]\nName=Fancy\nDirectories=48/places\n\n[48/places]\nContext=Places\nSize=48\n")
			e.file("Fancy/48/places/folder.svg", "papirus-folder.svg")
			e.write("Adwaita/index.theme", "[Icon Theme]\nName=Adwaita\nDirectories=scalable/places\n\n[scalable/places]\nContext=Places\nSize=128\nType=Scalable\n")
			e.file("Adwaita/scalable/places/folder.svg", "papirus-folder-red.svg")
			e.apply("Papirus")
			e.colors("#a1d39a", "#0a390f")
			e.apply("Papirus")
			before := e.generated()
			require.Len(t, before, 2)

			assert.Equal(t, State{}, e.apply(tc.theme))
			assert.NoFileExists(t, filepath.Join(e.state, StateFile))
			assert.Equal(t, before, e.generated(), "the session still has the overlay applied until the shell switches back")

			probe := ProbeTheme(e.opts(tc.theme))
			assert.False(t, probe.Supported)
			assert.Equal(t, tc.code, probe.Code)
			assert.NotEmpty(t, probe.Reason)
		})
	}
}

func TestClearRemovesEverythingGeneratedAndNothingElse(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	for _, theme := range []string{"", "System Default", "Papirus"} {
		require.NoError(t, Clear(e.opts(theme)), "clearing nothing must succeed for %q", theme)
	}

	e.apply("Papirus")
	e.colors("#a1d39a", "#0a390f")
	e.apply("Papirus")
	require.Len(t, e.generated(), 2)

	// None of these is a staging directory of ours, whatever it resembles.
	kept := []string{"Mine-dms-0a1b2c3d", ".Mine-dms-0a1b2c3d", ".cache-dms-backup.tmp-1", ".Papirus-dms-0a1b2c3d.tmp-", ".Papirus-dms-0A1B2C3D.tmp-7", "Papirus-dms-0a1b2c3d.tmp-7", ".Papirus-dms-0a1b2c3d.tmp-7x", ".Papirus-dms-0a1b2c3d.old-9.bak"}
	for _, name := range kept {
		require.NoError(t, os.MkdirAll(filepath.Join(e.icons, name), 0o755))
		require.NoError(t, os.WriteFile(filepath.Join(e.icons, name, "index.theme"), []byte("[Icon Theme]\nName=Mine\n"), 0o644))
	}
	require.NoError(t, os.WriteFile(filepath.Join(e.icons, ".Papirus-dms-0a1b2c3d.tmp-11"), nil, 0o644))
	kept = append(kept, ".Papirus-dms-0a1b2c3d.tmp-11")
	for _, name := range []string{".Papirus-dms-0a1b2c3d.tmp-4242", ".Papirus-dms-0a1b2c3d.old-4242"} {
		require.NoError(t, os.MkdirAll(filepath.Join(e.icons, name, "48x48"), 0o755))
	}

	require.NoError(t, os.Remove(filepath.Join(e.state, StateFile)))
	require.NoError(t, Clear(e.opts("")))

	assert.ElementsMatch(t, kept, e.generated())
	assert.NoFileExists(t, filepath.Join(e.state, StateFile))
}

func TestSwitchingBaseKeepsOnlyThePreviousOverlay(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	adwaitaPack(e)

	e.apply("Papirus")
	e.colors("#a1d39a", "#0a390f")
	papirus := e.apply("Papirus")
	require.Len(t, e.generated(), 2)

	adwaita := e.apply("Adwaita")
	assert.Regexp(t, regexp.MustCompile(`^Adwaita-dms-[0-9a-f]{8}$`), adwaita.Applied)
	assert.ElementsMatch(t, []string{adwaita.Applied, papirus.Applied}, e.generated())

	e.colors("#fdb975", "#4a2800")
	next := e.apply("Adwaita")
	assert.ElementsMatch(t, []string{adwaita.Applied, next.Applied}, e.generated(), "alternating packs must not leave an overlay behind each time")
}

func TestFailedGenerationKeepsThePreviousOverlay(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	first := e.apply("Papirus")

	require.NoError(t, os.WriteFile(filepath.Join(e.state, "dms-colors.json"), []byte(`{"colors":{"dark":{}}}`), 0o644))
	state, err := Apply(e.opts("Papirus"))

	assert.Error(t, err)
	assert.Equal(t, first, state)
	assert.Equal(t, first, ReadState(e.state))
	assert.Equal(t, []string{first.Applied}, e.generated())
}

func TestStateIsOnlyWrittenOnceTheOverlayIsInPlace(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	require.NoError(t, os.WriteFile(e.icons, nil, 0o644))

	state, err := Apply(e.opts("Papirus"))

	assert.Error(t, err)
	assert.Equal(t, State{}, state)
	assert.NoFileExists(t, filepath.Join(e.state, StateFile), "consumers apply whatever name this file holds")
}

func TestReadStateOnlyAcceptsWhatApplyWrites(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	good := e.apply("Papirus")
	put := func(state State) {
		data, err := json.Marshal(state)
		require.NoError(t, err)
		require.NoError(t, os.WriteFile(filepath.Join(e.state, StateFile), data, 0o644))
	}

	for _, applied := range []string{"Papirus", "Papirus-dms-a", "Other-dms-" + good.Inputs[:8], good.Applied + "; rm -rf ~"} {
		bad := good
		bad.Applied = applied
		put(bad)
		assert.Equal(t, State{}, ReadState(e.state), applied)
	}
}

func TestGeneratedNameIsTreatedAsItsBase(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	first := e.apply("Papirus")

	assert.Equal(t, first, e.apply(first.Applied))
	assert.Equal(t, []string{first.Applied}, e.generated())
}

func TestProbeWritesNothing(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	require.NoError(t, os.RemoveAll(e.state))

	assert.Equal(t, Probe{Supported: true, Code: "supported"}, ProbeTheme(e.opts("Papirus")))
	assert.NoDirExists(t, e.icons)
	assert.NoDirExists(t, e.state)
}

func TestThemeDirectoriesCannotEscapeTheOverlay(t *testing.T) {
	e := newEnv(t)
	e.write("Adwaita/index.theme", "[Icon Theme]\nName=Adwaita\nDirectories=scalable/places,../escape/places\n\n[scalable/places]\nContext=Places\nSize=128\nType=Scalable\n\n[../escape/places]\nContext=Places\nSize=128\nType=Scalable\n")
	e.file("Adwaita/scalable/places/folder.svg", "adwaita-folder-documents.svg")
	e.file("escape/places/folder-documents.svg", "adwaita-folder-documents.svg")

	state := e.apply("Adwaita")

	assert.Equal(t, []string{state.Applied}, e.generated())
	assert.Equal(t, map[string]string{"folder": "scalable/places/folder.svg"}, state.Icons)
}

func TestFirstBaseDirWins(t *testing.T) {
	e := newEnv(t)
	adwaitaPack(e)
	user := filepath.Join(e.icons, "Adwaita")
	require.NoError(t, os.MkdirAll(filepath.Join(user, "scalable/places"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(user, "index.theme"), []byte(adwaitaIndex), 0o644))
	require.NoError(t, os.WriteFile(filepath.Join(user, "scalable/places/folder-user.svg"), []byte(e.fixture("adwaita-folder-documents.svg")), 0o644))

	state := e.apply("Adwaita")

	assert.FileExists(t, filepath.Join(e.icons, state.Applied, "scalable/places/folder-user.svg"))
	assert.NoFileExists(t, filepath.Join(e.icons, state.Applied, "scalable/places/folder.svg"))
}

// Papirus-Dark's larger sizes are links into Papirus, which it does not inherit.
func TestSizesLinkedIntoASiblingThemeAreRead(t *testing.T) {
	e := newEnv(t)
	ramp := e.colors("#69b2ff", "#003055")
	papirusPack(e)
	e.write("Papirus-Dark/index.theme", strings.Replace(papirusIndex, "Name=Papirus", "Name=Papirus-Dark", 1))
	e.file("Papirus-Dark/16x16/places/folder.svg", "mono-folder.svg")
	e.link("Papirus-Dark/48x48", "../Papirus/48x48")

	state := e.apply("Papirus-Dark")

	assert.Contains(t, e.overlay(state.Applied, "48x48/places/folder.svg"), ramp.Front)
	assert.Equal(t, e.fixture("papirus-folder-red.svg"), e.overlay(state.Applied, "48x48/places/folder-root.svg"))
}

// A pack in ~/.icons is whatever its author made it.
func TestOnlyPlainFilesOfThePackAreRead(t *testing.T) {
	e := newEnv(t)
	papirusPack(e)
	secret := filepath.Join(filepath.Dir(e.sys), "private", "secret.svg")
	require.NoError(t, os.MkdirAll(filepath.Dir(secret), 0o755))
	require.NoError(t, os.WriteFile(secret, []byte(e.fixture("papirus-folder.svg")+"<!-- SECRET -->"), 0o600))
	pipe := filepath.Join(e.sys, "Papirus", "pipe")
	require.NoError(t, syscall.Mkfifo(pipe, 0o644))
	huge := e.fixture("papirus-folder.svg") + strings.Repeat(" ", maxIconBytes)

	e.link("Papirus/48x48/places/folder-blue-secret.svg", secret)
	e.link("Papirus/48x48/places/folder-secret.svg", "folder-blue-secret.svg")
	e.link("Papirus/16x16/places/folder-private.svg", secret)
	e.link("Papirus/48x48/places/folder-blue-pipe.svg", "../../pipe")
	e.link("Papirus/48x48/places/folder-pipe.svg", "folder-blue-pipe.svg")
	e.link("Papirus/16x16/places/folder-fifo.svg", "../../pipe")
	e.write("Papirus/48x48/places/folder-blue-huge.svg", huge)
	e.link("Papirus/48x48/places/folder-huge.svg", "folder-blue-huge.svg")
	e.write("Papirus/16x16/places/folder-big.svg", huge)
	e.link("Papirus/private", filepath.Dir(secret))
	e.write("Papirus/index.theme", strings.Replace(papirusIndex, "48x48/apps,", "48x48/apps,private,", 1)+"\n[private]\nContext=Places\nSize=48\nType=Fixed\n")

	var opened []string
	openFile = func(name string, flag int, perm os.FileMode) (*os.File, error) {
		opened = append(opened, name)
		return os.OpenFile(name, flag, perm)
	}
	t.Cleanup(func() { openFile = os.OpenFile })

	done := make(chan State, 1)
	go func() {
		ProbeTheme(e.opts("Papirus"))
		state, err := Apply(e.opts("Papirus"))
		assert.NoError(t, err)
		done <- state
	}()
	var state State
	select {
	case state = <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("blocked on a FIFO while it would be holding the theme run lock")
	}

	require.NotEmpty(t, opened)
	for _, name := range opened {
		info, err := os.Lstat(name)
		require.NoError(t, err)
		assert.True(t, info.Mode().IsRegular(), "%s was opened; opening a device or a FIFO can itself have effects", name)
	}

	names := iconNames(t, filepath.Join(e.icons, state.Applied))
	for _, icon := range []string{"folder-secret", "folder-blue-secret", "folder-private", "secret", "folder-pipe", "folder-blue-pipe", "folder-fifo", "folder-huge", "folder-blue-huge", "folder-big"} {
		assert.False(t, names[icon], icon)
		assert.NotContains(t, state.Icons, icon)
	}
	assert.True(t, names["folder"] && names["folder-root"], "the rest of the pack is unaffected")
	require.NoError(t, filepath.WalkDir(e.icons, func(path string, entry fs.DirEntry, err error) error {
		if err != nil || !entry.Type().IsRegular() {
			return err
		}
		data, err := os.ReadFile(path)
		assert.NotContains(t, string(data), "SECRET", path)
		return err
	}))
	dangling := 0
	require.NoError(t, filepath.WalkDir(e.icons, func(path string, entry fs.DirEntry, err error) error {
		if err == nil && entry.Type()&fs.ModeSymlink != 0 {
			if _, statErr := os.Stat(path); statErr != nil {
				dangling++
			}
		}
		return err
	}))
	assert.Zero(t, dangling, "a link to a file that was not copied must not be reproduced")
}
