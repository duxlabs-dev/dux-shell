package iconfolders

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"cmp"
	"compress/gzip"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/klauspost/compress/zstd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const shelfIndex = "[Icon Theme]\nName=x\nInherits=%s\nDirectories=16x16/places,256x256/places,48x48/places,scalable/apps\n" +
	"[16x16/places]\nSize=16\n[256x256/places]\nSize=256\n[48x48/places]\nSize=48\n[scalable/apps]\nSize=64\nType=Scalable\n"

// put writes a tree; a value starting with "->" is a link to the rest.
func put(t *testing.T, root string, files map[string]string) {
	for rel, content := range files {
		path := filepath.Join(root, rel)
		require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o755))
		if target, ok := strings.CutPrefix(content, "->"); ok {
			require.NoError(t, os.Symlink(target, path))
			continue
		}
		require.NoError(t, os.WriteFile(path, []byte(content), 0o644))
	}
}

func index(inherits string) string {
	return strings.Replace(shelfIndex, "%s", inherits, 1)
}

func TestListedThemesShowTheirOwnAndInheritedIcons(t *testing.T) {
	e := newEnv(t)
	put(t, e.sys, map[string]string{
		"Base/index.theme":                             index("hicolor"),
		"Base/16x16/places/folder.png":                 "small",
		"Base/256x256/places/folder.png":               "large",
		"Base/48x48/places/folder.png":                 "right",
		"Base/48x48/places/user-home.svg":              "home",
		"Base/48x48/places/user-trash-full.svg":        "<svg><mask/></svg>",
		"Base/256x256/places/user-trash-full.png":      "plain",
		"Base/48x48/places/preferences-system.svg":     "<svg><mask/></svg>",
		"Cursors/index.theme":                          "[Icon Theme]\nName=Cursors\n",
		"Cursors/cursors/left_ptr":                     "x",
		"hicolor/index.theme":                          index(""),
		"hicolor/scalable/apps/utilities-terminal.svg": "fallback",
		"Mine/index.theme":                             index("Base"),
		"Base-dms-0123abcd/index.theme":                index("Base"),
		"NoIndex/48x48/places/folder.png":              "x",
	})
	put(t, e.icons, map[string]string{
		"Mine/index.theme":                           index("Base, Missing"),
		"Mine/scalable/apps/folder.svg":              "own",
		"Mine/48x48/places/text-x-generic":           "not an icon file",
		"Mine/16x16/places/user-home.png":            "too small to show",
		"Mine/48x48/places/image-x-generic.svg/keep": "x",
	})

	themes := map[string]ThemeInfo{}
	for _, th := range ListThemes(e.opts("")) {
		themes[th.Name] = th
	}
	require.Len(t, themes, 2, "cursor themes, generated overlays, the fallback and folders without an index are not listed")

	base := themes["Base"]
	assert.False(t, base.Removable)
	assert.Equal(t, []string{
		filepath.Join(e.sys, "Base/48x48/places/folder.png"),
		filepath.Join(e.sys, "Base/48x48/places/user-home.svg"),
		"", "",
		filepath.Join(e.sys, "hicolor/scalable/apps/utilities-terminal.svg"),
		"",
		filepath.Join(e.sys, "Base/48x48/places/preferences-system.svg"),
		filepath.Join(e.sys, "Base/256x256/places/user-trash-full.png"),
	}, base.Icons, "a masked SVG gives way to any other file of the icon")

	mine := themes["Mine"]
	assert.True(t, mine.Removable, "the copy in the user's directory is the one in effect")
	assert.Equal(t, filepath.Join(e.icons, "Mine/scalable/apps/folder.svg"), mine.Icons[0])
	assert.Equal(t, filepath.Join(e.sys, "Base/48x48/places/user-home.svg"), mine.Icons[1])
	assert.Empty(t, mine.Icons[2])
	assert.Empty(t, mine.Icons[3], "a directory is not an icon")
}

func TestSelfBuiltPackIsListedByItsOwnName(t *testing.T) {
	e := newSelfEnv(t)
	state := e.apply(AppColor)
	names := []string{}
	for _, th := range ListThemes(e.opts()) {
		names = append(names, th.Name)
	}
	assert.Equal(t, []string{SelfBuilt}, names, "the generation "+state.Applied+" stays hidden")
}

func TestRemoveThemeGuards(t *testing.T) {
	setup := func(t *testing.T) env {
		e := newEnv(t)
		put(t, e.sys, map[string]string{
			"System/index.theme": index(""),
			"Child/index.theme":  index("Parent"),
		})
		put(t, e.icons, map[string]string{
			"Lone/index.theme":              index(""),
			"Lone/48x48/places/a.png":       "x",
			"Parent/index.theme":            index(""),
			"Big/index.theme":               index(""),
			"Big/256x256/places/a.png":      "x",
			"Linked/index.theme":            index(""),
			"Linked/256x256":                "->../Big/256x256",
			"Deep/index.theme":              index(""),
			"Deep/scalable/apps":            "->../../Big/256x256/places",
			"Plain/readme":                  "no index",
			"hicolor/48x48/apps/app.png":    "x",
			"hicolor/index.theme":           index(""),
			"Made/index.theme":              index(""),
			"Made-dms-01234567/index.theme": "[Icon Theme]\nHidden=true\n" + generatedKey + "\nInherits=Made,hicolor\n",
		})
		return e
	}

	tests := []struct {
		name  string
		theme string
		inUse []string
		state string
		code  string
		users []string
	}{
		{name: "a theme outside the user's directory", theme: "System", code: CodeNotRemovable},
		{name: "a path", theme: "../sys/System", code: CodeNotRemovable},
		{name: "an empty name", theme: "", code: CodeNotRemovable},
		{name: "a folder without an index", theme: "Plain", code: CodeNotRemovable},
		{name: "the shared fallback", theme: "hicolor", code: CodeNotRemovable},
		{name: "a generated overlay", theme: "Made-dms-01234567", code: CodeNotRemovable},
		{name: "the theme in use", theme: "Lone", inUse: []string{"System Default", "Lone"}, code: CodeInUse, users: []string{"Lone"}},
		{name: "a theme the one in use inherits", theme: "Parent", inUse: []string{"Child"}, code: CodeInUse, users: []string{"Child"}},
		{name: "a theme the one in use links into", theme: "Big", inUse: []string{"Linked"}, code: CodeInUse, users: []string{"Linked"}},
		{name: "a theme the one in use links into from below its top", theme: "Big", inUse: []string{"Deep"}, code: CodeInUse, users: []string{"Deep"}},
		{name: "the base of the applied overlay", theme: "Made", state: `{"base":"Made","applied":"Made-dms-01234567","inputs":"0123456789abcdef"}`, code: CodeInUse, users: []string{"Made"}},
		{name: "a theme nothing uses", theme: "Lone", inUse: []string{"Child", "Linked", "Missing"}},
		{name: "a base whose overlay is not applied", theme: "Made"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			e := setup(t)
			if tc.state != "" {
				require.NoError(t, os.WriteFile(filepath.Join(e.state, StateFile), []byte(tc.state), 0o644))
			}
			before := e.generated()

			err := RemoveTheme(e.opts(""), tc.theme, tc.inUse)
			if tc.code == "" {
				require.NoError(t, err)
				assert.NotContains(t, e.generated(), tc.theme)
				assert.Len(t, e.generated(), len(before)-1)
				return
			}
			var refusal *LibraryError
			require.ErrorAs(t, err, &refusal)
			assert.Equal(t, tc.code, refusal.Code)
			assert.Equal(t, tc.users, refusal.Themes)
			assert.Equal(t, before, e.generated())
			assert.FileExists(t, filepath.Join(e.sys, "System/index.theme"))
		})
	}
}

// From the root an archive is unpacked into up to the directory holding the icon directory.
const outOfStage = "../../.."

type entry struct {
	name string
	// body is a file's content, or "->target" for a link.
	body string
	kind byte
}

func tarball(t *testing.T, dir string, entries ...entry) string {
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	writeTar(t, gz, entries)
	require.NoError(t, gz.Close())
	path := filepath.Join(dir, "pack.tar.gz")
	require.NoError(t, os.WriteFile(path, buf.Bytes(), 0o644))
	return path
}

func writeTar(t *testing.T, w io.Writer, entries []entry) {
	tw := tar.NewWriter(w)
	for _, e := range entries {
		h := &tar.Header{Name: e.name, Mode: 0o755, Typeflag: tar.TypeReg, Size: int64(len(e.body))}
		target, isLink := strings.CutPrefix(e.body, "->")
		switch {
		case e.kind == tar.TypeXGlobalHeader:
			h = &tar.Header{Typeflag: e.kind, PAXRecords: map[string]string{"comment": "x"}}
		case e.kind != 0:
			h.Typeflag, h.Size, h.Linkname = e.kind, 0, target
		case isLink:
			h.Typeflag, h.Size, h.Linkname = tar.TypeSymlink, 0, target
		case strings.HasSuffix(e.name, "/"):
			h.Typeflag = tar.TypeDir
		}
		require.NoError(t, tw.WriteHeader(h))
		if h.Size > 0 {
			_, err := tw.Write([]byte(e.body))
			require.NoError(t, err)
		}
	}
	require.NoError(t, tw.Close())
}

var goodPack = []entry{
	{name: "pax_global_header", kind: tar.TypeXGlobalHeader},
	{name: "./"},
	{name: "pack-1.0/"},
	{name: "pack-1.0/README", body: "read me"},
	{name: "pack-1.0/install.sh", body: "#!/bin/sh\ntouch pwned\n"},
	{name: "pack-1.0/Foo/index.theme", body: "[Icon Theme]\nName=Foo\n"},
	{name: "pack-1.0/Foo/scalable/places/folder.svg", body: "<svg/>"},
	{name: "pack-1.0/Foo/scalable/places/inode-directory.svg", body: "->folder.svg"},
	{name: "pack-1.0/Foo/scalable/places/folder-copy.svg", body: "->pack-1.0/Foo/scalable/places/folder.svg", kind: tar.TypeLink},
	{name: "pack-1.0/Foo-Dark/index.theme", body: "[Icon Theme]\nName=Foo Dark\n"},
	{name: "pack-1.0/Foo-Dark/scalable", body: "->../Foo/scalable"},
	{name: "pack-1.0/hicolor/index.theme", body: "[Icon Theme]\nName=Hicolor\n"},
	{name: "pack-1.0/Foo-dms-0123abcd/index.theme", body: "[Icon Theme]\nName=Posing\n"},
	{name: "pack-1.0/NotATheme/folder.svg", body: "<svg/>"},
}

func TestInstallThemeTakesOnlyTheThemes(t *testing.T) {
	e := newEnv(t)
	put(t, e.icons, map[string]string{"hicolor/48x48/apps/mine.png": "kept", ".dms-install-stale/x": "left by a crash", ".dms-install-live/x": "another install at work"})
	long := time.Now().Add(-2 * stageMaxAge)
	require.NoError(t, os.Chtimes(filepath.Join(e.icons, ".dms-install-stale"), long, long))

	names, err := InstallTheme(e.opts(""), tarball(t, t.TempDir(), goodPack...), false)
	require.NoError(t, err)
	assert.Equal(t, []string{"Foo", "Foo-Dark"}, names)
	assert.Equal(t, []string{".dms-install-live", "Foo", "Foo-Dark", "hicolor"}, e.generated(), "no staging directory of its own, wrapper or reserved name is left")
	assert.Equal(t, "kept", e.overlay("hicolor", "48x48/apps/mine.png"))
	assert.Equal(t, "<svg/>", e.overlay("Foo", "scalable/places/inode-directory.svg"))
	assert.Equal(t, "<svg/>", e.overlay("Foo", "scalable/places/folder-copy.svg"), "a hard link to a file of the archive")
	assert.Equal(t, "<svg/>", e.overlay("Foo-Dark", "scalable/places/folder.svg"), "a link into a sibling theme is kept")
	info, err := os.Stat(filepath.Join(e.icons, "Foo/scalable/places/folder.svg"))
	require.NoError(t, err)
	assert.Zero(t, info.Mode().Perm()&0o111, "nothing installed is executable")
}

func TestInstallThemeReplacesOnlyWhenAsked(t *testing.T) {
	e := newEnv(t)
	put(t, e.icons, map[string]string{"Foo/index.theme": "[Icon Theme]\nName=Old\n", "Foo/old.svg": "old"})
	pack := tarball(t, t.TempDir(), goodPack...)

	_, err := InstallTheme(e.opts(""), pack, false)
	var refusal *LibraryError
	require.ErrorAs(t, err, &refusal)
	assert.Equal(t, CodeExists, refusal.Code)
	assert.Equal(t, []string{"Foo"}, refusal.Themes)
	assert.Equal(t, []string{"Foo"}, e.generated(), "a refused install adds nothing, not even the theme that was free")
	assert.Equal(t, "old", e.overlay("Foo", "old.svg"))

	// The old theme resists deletion; the new one must be in place all the same.
	put(t, e.icons, map[string]string{"Foo/locked/old.svg": "old"})
	locked := filepath.Join(e.icons, "Foo/locked")
	require.NoError(t, os.Chmod(locked, 0o555))
	t.Cleanup(func() { os.Chmod(locked, 0o755) })

	names, err := InstallTheme(e.opts(""), pack, true)
	require.NoError(t, err)
	assert.Equal(t, []string{"Foo", "Foo-Dark"}, names)
	assert.Equal(t, "[Icon Theme]\nName=Foo\n", e.overlay("Foo", "index.theme"))
	assert.NoFileExists(t, filepath.Join(e.icons, "Foo/old.svg"))
	assert.Equal(t, []string{"Foo", "Foo-Dark"}, e.generated(), "the old theme is gone with the staging directory")
}

func TestInstallThemeNeverTakesALinkForTheWrapperFolder(t *testing.T) {
	for _, target := range []string{"..", "../..", outOfStage + "/elsewhere"} {
		t.Run(target, func(t *testing.T) {
			e := newEnv(t)
			put(t, e.icons, map[string]string{"Mine/index.theme": "[Icon Theme]\nName=Mine\n"})
			put(t, filepath.Dir(e.icons), map[string]string{"elsewhere/Theirs/index.theme": "[Icon Theme]\nName=Theirs\n"})

			_, err := InstallTheme(e.opts(""), tarball(t, t.TempDir(), entry{name: "w", body: "->" + target}), true)
			var refusal *LibraryError
			require.ErrorAs(t, err, &refusal)
			assert.Equal(t, CodeNoTheme, refusal.Code)
			assert.Equal(t, []string{"Mine"}, e.generated())
			assert.Equal(t, "[Icon Theme]\nName=Mine\n", e.overlay("Mine", "index.theme"))
			assert.FileExists(t, filepath.Join(filepath.Dir(e.icons), "elsewhere/Theirs/index.theme"))
		})
	}
}

func TestInstallThemeRejectsWhatCouldLeaveTheTheme(t *testing.T) {
	theme := entry{name: "Foo/index.theme", body: "[Icon Theme]\nName=Foo\n"}
	tests := []struct {
		name     string
		entries  []entry
		entryCap int
		byteCap  int64
		code     string
	}{
		{name: "a name climbing out", entries: []entry{theme, {name: "../evil", body: "x"}}},
		{name: "a name climbing out from inside", entries: []entry{theme, {name: "Foo/../../outside/evil", body: "x"}}},
		{name: "an absolute name", entries: []entry{theme, {name: "/tmp/dms-install-test-evil", body: "x"}}},
		{name: "a link to an absolute path", entries: []entry{theme, {name: "Foo/passwd", body: "->/etc/passwd"}}},
		{name: "a link out of the icon directory", entries: []entry{theme, {name: "Foo/out", body: "->../../outside"}}},
		{name: "a link to the icon directory itself", entries: []entry{theme, {name: "Foo/up", body: "->.."}}},
		{name: "a link that climbs after descending", entries: []entry{theme, {name: "Foo/a/deep/"}, {name: "Foo/b", body: "->a/deep/.."}}},
		{name: "a file written through a link", entries: []entry{theme, {name: "Foo/out", body: "->../" + outOfStage + "/outside"}, {name: "Foo/out/evil", body: "x"}}},
		{name: "a folder made through a link", entries: []entry{theme, {name: "Foo/out", body: "->../" + outOfStage + "/outside"}, {name: "Foo/out/evil/"}}},
		{name: "a file over a link", entries: []entry{theme, {name: "Foo/out", body: "->../" + outOfStage + "/outside/evil"}, {name: "Foo/out", body: "x"}}},
		{name: "a hard link climbing out", entries: []entry{theme, {name: "Foo/hard", body: "->" + outOfStage + "/state/dms-colors.json", kind: tar.TypeLink}}},
		{name: "a hard link through a link no theme holds", entries: []entry{theme, {name: "out", body: "->" + outOfStage + "/state"}, {name: "Foo/hard.svg", body: "->out/dms-colors.json", kind: tar.TypeLink}}},
		{name: "a hard link to a link", entries: []entry{theme, {name: "Foo/out", body: "->../" + outOfStage + "/state/dms-colors.json"}, {name: "Foo/hard", body: "->Foo/out", kind: tar.TypeLink}}},
		{name: "a hard link to nothing", entries: []entry{theme, {name: "Foo/hard", body: "->Foo/missing.svg", kind: tar.TypeLink}}},
		{name: "a device", entries: []entry{theme, {name: "Foo/dev", kind: tar.TypeChar}}},
		{name: "a pipe", entries: []entry{theme, {name: "Foo/pipe", kind: tar.TypeFifo}}},
		{name: "a name that is the archive itself", entries: []entry{theme, {name: "Foo/..", body: "x"}}},
		{name: "more implied folders than the cap", entries: []entry{theme, {name: "Foo/a/b/c/d/e.svg", body: "x"}}, entryCap: 5},
		{name: "more entries than the cap", entries: []entry{theme, {name: "Foo/a.svg", body: "x"}, {name: "Foo/b.svg", body: "x"}}, entryCap: 2},
		{name: "more bytes than the cap", entries: []entry{theme, {name: "Foo/a.svg", body: strings.Repeat("x", 64)}}, byteCap: 64},
		{name: "no theme at all", entries: []entry{{name: "Foo/folder.svg", body: "x"}}, code: CodeNoTheme},
		{name: "themes nested too deep", entries: []entry{{name: "a/b/Foo/index.theme", body: "x"}}, code: CodeNoTheme},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			e := newEnv(t)
			outside := filepath.Join(filepath.Dir(e.icons), "outside")
			require.NoError(t, os.MkdirAll(outside, 0o755))
			if tc.entryCap > 0 {
				defer func(n int) { maxInstallEntries = n }(maxInstallEntries)
				maxInstallEntries = tc.entryCap
			}
			if tc.byteCap > 0 {
				defer func(n int64) { maxInstallBytes = n }(maxInstallBytes)
				maxInstallBytes = tc.byteCap
			}

			names, err := InstallTheme(e.opts(""), tarball(t, t.TempDir(), tc.entries...), true)
			var refusal *LibraryError
			require.ErrorAs(t, err, &refusal)
			assert.Equal(t, cmp.Or(tc.code, CodeBadSource), refusal.Code)
			assert.Empty(t, names)
			assert.NotContains(t, refusal.Reason, e.icons, "the reason names entries, not the staging directory")
			assert.Empty(t, e.generated(), "nothing is installed, and the staging directory is gone")
			left, err := os.ReadDir(outside)
			require.NoError(t, err)
			assert.Empty(t, left)
			assert.NoFileExists(t, "/tmp/dms-install-test-evil")
		})
	}
}

func TestInstallThemeReadsEveryArchiveKindAndFolders(t *testing.T) {
	plain := []entry{{name: "Foo/index.theme", body: "[Icon Theme]\nName=Foo\n"}, {name: "Foo/a.svg", body: "<svg/>"}, {name: "Foo/b.svg", body: "->a.svg"}}
	var tarred bytes.Buffer
	writeTar(t, &tarred, plain)

	sources := map[string]func(t *testing.T, dir string) string{
		"tar": func(t *testing.T, dir string) string {
			require.NoError(t, os.WriteFile(filepath.Join(dir, "p.tar"), tarred.Bytes(), 0o644))
			return filepath.Join(dir, "p.tar")
		},
		"tar.zst": func(t *testing.T, dir string) string {
			enc, err := zstd.NewWriter(nil)
			require.NoError(t, err)
			require.NoError(t, os.WriteFile(filepath.Join(dir, "p"), enc.EncodeAll(tarred.Bytes(), nil), 0o644))
			return filepath.Join(dir, "p")
		},
		"tar.xz": func(t *testing.T, dir string) string {
			if _, err := exec.LookPath("xz"); err != nil {
				t.Skip("xz is not installed")
			}
			require.NoError(t, os.WriteFile(filepath.Join(dir, "p.tar"), tarred.Bytes(), 0o644))
			require.NoError(t, exec.Command("xz", filepath.Join(dir, "p.tar")).Run())
			return filepath.Join(dir, "p.tar.xz")
		},
		"zip": func(t *testing.T, dir string) string {
			var buf bytes.Buffer
			zw := zip.NewWriter(&buf)
			for _, e := range plain {
				h := &zip.FileHeader{Name: e.name}
				body := e.body
				if target, ok := strings.CutPrefix(e.body, "->"); ok {
					h.SetMode(0o777 | os.ModeSymlink)
					body = target
				}
				w, err := zw.CreateHeader(h)
				require.NoError(t, err)
				_, err = w.Write([]byte(body))
				require.NoError(t, err)
			}
			require.NoError(t, zw.Close())
			require.NoError(t, os.WriteFile(filepath.Join(dir, "p.zip"), buf.Bytes(), 0o644))
			return filepath.Join(dir, "p.zip")
		},
		"a theme folder": func(t *testing.T, dir string) string {
			put(t, dir, map[string]string{"Foo/index.theme": "x", "Foo/a.svg": "<svg/>", "Foo/b.svg": "->a.svg"})
			require.NoError(t, syscall.Mkfifo(filepath.Join(dir, "Foo/pipe"), 0o644))
			return filepath.Join(dir, "Foo")
		},
		"a folder of themes": func(t *testing.T, dir string) string {
			put(t, dir, map[string]string{"Foo/index.theme": "x", "Foo/a.svg": "<svg/>", "Foo/b.svg": "->a.svg", "Other/huge.bin": "not copied", "notes.txt": "x"})
			return dir
		},
	}
	for name, source := range sources {
		t.Run(name, func(t *testing.T) {
			e := newEnv(t)
			names, err := InstallTheme(e.opts(""), source(t, t.TempDir()), false)
			require.NoError(t, err)
			assert.Equal(t, []string{"Foo"}, names)
			assert.Equal(t, []string{"Foo"}, e.generated())
			assert.Equal(t, "<svg/>", e.overlay("Foo", "b.svg"))
			assert.NoFileExists(t, filepath.Join(e.icons, "Foo/pipe"))
		})
	}

	t.Run("a zip entry climbing out", func(t *testing.T) {
		e := newEnv(t)
		var buf bytes.Buffer
		zw := zip.NewWriter(&buf)
		for _, name := range []string{"Foo/index.theme", "../evil"} {
			w, err := zw.Create(name)
			require.NoError(t, err)
			_, err = w.Write([]byte("x"))
			require.NoError(t, err)
		}
		require.NoError(t, zw.Close())
		pack := filepath.Join(t.TempDir(), "p.zip")
		require.NoError(t, os.WriteFile(pack, buf.Bytes(), 0o644))

		_, err := InstallTheme(e.opts(""), pack, false)
		var refusal *LibraryError
		require.ErrorAs(t, err, &refusal)
		assert.Equal(t, CodeBadSource, refusal.Code)
		assert.Empty(t, e.generated())
		assert.NoFileExists(t, filepath.Join(filepath.Dir(e.icons), "evil"))
	})
}
