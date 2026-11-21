package iconfolders

import (
	"bytes"
	"encoding/binary"
	"image"
	"image/color"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type cursorImage struct {
	kind, nominal, width, height uint32
	// pixels are premultiplied BGRA, as the file stores them; short of width*height*4 is a cut file.
	pixels []byte
}

// xcursor writes a cursor file holding the given chunks, each announced in the table of contents.
func xcursor(magic string, images ...cursorImage) []byte {
	u32 := binary.LittleEndian.AppendUint32
	head := u32(u32(u32([]byte(magic), 16), 0x10000), uint32(len(images)))
	var body []byte
	at := uint32(16 + 12*len(images))
	for _, img := range images {
		head = u32(u32(u32(head, img.kind), img.nominal), at+uint32(len(body)))
		for _, field := range []uint32{36, img.kind, img.nominal, 1, img.width, img.height, 0, 0, 0} {
			body = u32(body, field)
		}
		body = append(body, img.pixels...)
	}
	return append(head, body...)
}

func solid(width, height uint32, bgra ...byte) cursorImage {
	return cursorImage{kind: xcursorImage, nominal: width, width: width, height: height, pixels: bytes.Repeat(bgra, int(width*height))}
}

func TestReadPointerTakesTheSizeNearestThePreview(t *testing.T) {
	// A 3x2 image drawing one opaque pixel beside one half-clear one, off center.
	drawn := cursorImage{kind: xcursorImage, nominal: 40, width: 3, height: 2, pixels: []byte{
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 10, 20, 30, 255, 200, 90, 40, 128,
	}}
	comment := cursorImage{kind: 0xfffe0001, nominal: pointerSize, width: 1, height: 1, pixels: []byte{3, 3, 3, 255}}
	img := readPointer(bytes.NewReader(xcursor("Xcur", solid(24, 24, 1, 1, 1, 255), comment, drawn, solid(96, 96, 2, 2, 2, 255))))
	require.NotNil(t, img)
	assert.Equal(t, image.Rect(0, 0, 2, 2), img.Bounds(), "cropped to what is drawn, then squared")
	assert.Equal(t, color.RGBA{}, img.RGBAAt(0, 1))
	assert.Equal(t, color.RGBA{R: 30, G: 20, B: 10, A: 255}, img.RGBAAt(0, 0), "stored blue first")
	assert.Equal(t, color.RGBA{R: 40, G: 90, B: 128, A: 128}, img.RGBAAt(1, 0), "a color never exceeds its alpha")

	animated := xcursor("Xcur", solid(1, 1, 7, 7, 7, 255), solid(1, 1, 9, 9, 9, 255))
	assert.Equal(t, color.RGBA{R: 7, G: 7, B: 7, A: 255}, readPointer(bytes.NewReader(animated)).RGBAAt(0, 0), "the first frame")
}

func TestReadPointerRejectsWhatItCannotReadInFull(t *testing.T) {
	good := solid(4, 4, 5, 5, 5, 255)
	require.NotNil(t, readPointer(bytes.NewReader(xcursor("Xcur", good))))

	cut, huge, wide := good, good, good
	cut.pixels = cut.pixels[:len(cut.pixels)-1]
	huge.width, huge.height = 1<<30, 1<<30
	wide.width = maxPointerSide + 1
	wide.pixels = bytes.Repeat([]byte{5, 5, 5, 255}, int(wide.width*wide.height))
	elsewhere := xcursor("Xcur", good)
	binary.LittleEndian.PutUint32(elsewhere[24:], 1<<31)
	crowded := xcursor("Xcur", good)
	binary.LittleEndian.PutUint32(crowded[12:], maxPointerToc+1)

	tests := map[string][]byte{
		"an empty file":                    nil,
		"another format":                   xcursor("RIFF", good),
		"no chunks":                        xcursor("Xcur"),
		"only a comment":                   xcursor("Xcur", cursorImage{kind: 0xfffe0001, nominal: 1, width: 4, height: 4, pixels: good.pixels}),
		"pixels cut short":                 xcursor("Xcur", cut),
		"a size no file could hold":        xcursor("Xcur", huge),
		"a side past the cap":              xcursor("Xcur", wide),
		"a chunk placed past the end":      elsewhere,
		"a table longer than the cap":      append(crowded, make([]byte, 12*(maxPointerToc+1))...),
		"nothing drawn":                    xcursor("Xcur", solid(4, 4, 0, 0, 0, 0)),
		"a table entry naming a non-image": append(xcursor("Xcur", good)[:20], xcursor("Xcur", cursorImage{kind: 0xfffe0001, nominal: 4, width: 4, height: 4, pixels: good.pixels})[20:]...),
	}
	for name, data := range tests {
		t.Run(name, func(t *testing.T) {
			assert.Nil(t, readPointer(bytes.NewReader(data)))
		})
	}
}

func TestListCursorsFindsEachThemesPointer(t *testing.T) {
	e := newEnv(t)
	pointer := string(xcursor("Xcur", solid(8, 8, 5, 5, 5, 255)))
	e.write("Plain/cursors/default", pointer)
	require.NoError(t, os.Symlink("default", filepath.Join(e.sys, "Plain/cursors/left_ptr")))
	e.write("Named/cursors/arrow", pointer)
	e.write("Child/cursors/text", pointer)
	e.write("Child/index.theme", "[Icon Theme]\nInherits=Missing,Plain\n")
	e.write("Loop/cursors/text", pointer)
	e.write("Loop/index.theme", "[Icon Theme]\nInherits=Loop\n")
	e.write("Broken/cursors/left_ptr", "Xcur")
	e.write("Icons/index.theme", "[Icon Theme]\nInherits=Plain\n")
	require.NoError(t, os.MkdirAll(filepath.Join(e.icons, "Pipe/cursors"), 0o755))
	require.NoError(t, syscall.Mkfifo(filepath.Join(e.icons, "Pipe/cursors/left_ptr"), 0o644), "opening it must not wait for a writer")

	found := map[string]string{}
	for _, cursor := range ListCursors(e.opts("")) {
		found[cursor.Name] = cursor.Pointer
	}
	require.True(t, strings.HasPrefix(found["Plain"], "data:image/png;base64,iVBOR"))
	assert.Equal(t, map[string]string{
		"Plain": found["Plain"], "Named": found["Plain"], "Child": found["Plain"],
		"Loop": "", "Broken": "", "Pipe": "",
	}, found, "a theme with no cursors directory is not a cursor theme")
}

func TestListCursorsRemovableAndSymlinked(t *testing.T) {
	e := newEnv(t)
	pointer := string(xcursor("Xcur", solid(8, 8, 5, 5, 5, 255)))
	put(t, e.sys, map[string]string{
		"SysCursor/cursors/left_ptr": pointer,
	})
	put(t, e.icons, map[string]string{
		"UserCursor/cursors/left_ptr": pointer,
		"LinkedTarget/left_ptr":       pointer,
		"LinkedCursor/cursors":        "->../LinkedTarget",
	})

	found := map[string]CursorInfo{}
	for _, c := range ListCursors(e.opts("")) {
		found[c.Name] = c
	}
	assert.False(t, found["SysCursor"].Removable)
	assert.True(t, found["UserCursor"].Removable)
	require.Contains(t, found, "LinkedCursor")
	assert.True(t, found["LinkedCursor"].Removable)
	assert.True(t, strings.HasPrefix(found["LinkedCursor"].Pointer, "data:image/png;base64,iVBOR"))
	assert.Equal(t, []string{found["LinkedCursor"].Pointer}, found["LinkedCursor"].Cursors)
}

func TestListCursorsCollectsMultipleStates(t *testing.T) {
	e := newEnv(t)
	pointer := string(xcursor("Xcur", solid(8, 8, 5, 5, 5, 255)))
	hand := string(xcursor("Xcur", solid(8, 8, 9, 9, 9, 255)))
	text := string(xcursor("Xcur", solid(8, 8, 3, 3, 3, 255)))
	put(t, e.icons, map[string]string{
		"Multi/cursors/left_ptr": pointer,
		"Multi/cursors/hand2":    hand,
		"Multi/cursors/xterm":    text,
	})

	found := map[string]CursorInfo{}
	for _, c := range ListCursors(e.opts("")) {
		found[c.Name] = c
	}
	require.Contains(t, found, "Multi")
	assert.Len(t, found["Multi"].Cursors, 3)
	assert.Equal(t, found["Multi"].Pointer, found["Multi"].Cursors[0])
	assert.NotEqual(t, found["Multi"].Cursors[0], found["Multi"].Cursors[1])
	assert.NotEqual(t, found["Multi"].Cursors[1], found["Multi"].Cursors[2])
}

func TestInstallCursor(t *testing.T) {
	e := newEnv(t)
	pointer := string(xcursor("Xcur", solid(8, 8, 5, 5, 5, 255)))

	// Direct cursor-only tarball (no index.theme).
	pack := tarball(t, t.TempDir(), entry{name: "Pack/cursors/left_ptr", body: pointer})
	names, err := InstallCursor(e.opts(""), pack, false)
	require.NoError(t, err)
	assert.Equal(t, []string{"Pack"}, names)
	assert.FileExists(t, filepath.Join(e.icons, "Pack/cursors/left_ptr"))

	// Reinstall fails without replace, succeeds with replace.
	_, err = InstallCursor(e.opts(""), pack, false)
	var refusal *LibraryError
	require.ErrorAs(t, err, &refusal)
	assert.Equal(t, CodeExists, refusal.Code)
	assert.Equal(t, []string{"Pack"}, refusal.Themes)

	names, err = InstallCursor(e.opts(""), pack, true)
	require.NoError(t, err)
	assert.Equal(t, []string{"Pack"}, names)

	// Single-wrapper release archive.
	wrapped := tarball(t, t.TempDir(), entry{name: "release/Wrapped/cursors/left_ptr", body: pointer})
	names, err = InstallCursor(e.opts(""), wrapped, false)
	require.NoError(t, err)
	assert.Equal(t, []string{"Wrapped"}, names)
	assert.FileExists(t, filepath.Join(e.icons, "Wrapped/cursors/left_ptr"))

	// Plain folder source.
	folderSrc := filepath.Join(t.TempDir(), "FolderPack")
	put(t, folderSrc, map[string]string{"cursors/left_ptr": pointer})
	names, err = InstallCursor(e.opts(""), folderSrc, false)
	require.NoError(t, err)
	assert.Equal(t, []string{"FolderPack"}, names)
	assert.FileExists(t, filepath.Join(e.icons, "FolderPack/cursors/left_ptr"))

	// Icon-only archive without cursors/ is rejected with CodeNoTheme.
	iconOnly := tarball(t, t.TempDir(),
		entry{name: "Icons/index.theme", body: index("")},
		entry{name: "Icons/48x48/places/a.png", body: "x"},
	)
	_, err = InstallCursor(e.opts(""), iconOnly, false)
	require.ErrorAs(t, err, &refusal)
	assert.Equal(t, CodeNoTheme, refusal.Code)
}

func TestRemoveCursorGuards(t *testing.T) {
	setup := func(t *testing.T) env {
		e := newEnv(t)
		put(t, e.sys, map[string]string{
			"System/cursors/left_ptr": "x",
		})
		put(t, e.icons, map[string]string{
			"Plain/cursors/left_ptr":            "x",
			"Indexed/index.theme":               index(""),
			"Indexed/cursors/left_ptr":          "x",
			"IndexedParent/index.theme":         index(""),
			"IndexedParent/cursors/left_ptr":    "x",
			"IndexlessParent/cursors/left_ptr":  "x",
			"Mid/index.theme":                   index("IndexlessParent"),
			"Mid/cursors/left_ptr":              "x",
			"Child/index.theme":                 index("IndexedParent"),
			"Child/cursors/left_ptr":            "x",
			"ChildOfIndexless/index.theme":      index("IndexlessParent"),
			"ChildOfIndexless/cursors/left_ptr": "x",
			"GrandChild/index.theme":            index("Mid"),
			"GrandChild/cursors/left_ptr":       "x",
			"Linked/cursors/left_ptr":           "->../../Plain/cursors/left_ptr",
			"LinkedDir/cursors":                 "->../Plain/cursors",
			"NoCursors/index.theme":             index(""),
			"hicolor/cursors/left_ptr":          "x",
		})
		return e
	}

	tests := []struct {
		name   string
		cursor string
		inUse  []string
		code   string
		users  []string
	}{
		{name: "a cursor outside the user's directory", cursor: "System", code: CodeNotRemovable},
		{name: "a path", cursor: "../sys/System", code: CodeNotRemovable},
		{name: "an empty name", cursor: "", code: CodeNotRemovable},
		{name: "a folder without cursors", cursor: "NoCursors", code: CodeNotRemovable},
		{name: "the shared fallback", cursor: "hicolor", code: CodeNotRemovable},
		{name: "an indexless cursor in use", cursor: "Plain", inUse: []string{"Plain"}, code: CodeInUse, users: []string{"Plain"}},
		{name: "an indexed cursor in use", cursor: "Indexed", inUse: []string{"Indexed"}, code: CodeInUse, users: []string{"Indexed"}},
		{name: "an indexed parent inherited by in-use cursor", cursor: "IndexedParent", inUse: []string{"Child"}, code: CodeInUse, users: []string{"Child"}},
		{name: "an indexless parent inherited directly by in-use cursor", cursor: "IndexlessParent", inUse: []string{"ChildOfIndexless"}, code: CodeInUse, users: []string{"ChildOfIndexless"}},
		{name: "an indexless parent inherited transitively by in-use cursor", cursor: "IndexlessParent", inUse: []string{"GrandChild"}, code: CodeInUse, users: []string{"GrandChild"}},
		{name: "a cursor linked into by an indexless in-use cursor", cursor: "Plain", inUse: []string{"Linked"}, code: CodeInUse, users: []string{"Linked"}},
		{name: "a cursor whose cursors dir is linked into by an indexless in-use cursor", cursor: "Plain", inUse: []string{"LinkedDir"}, code: CodeInUse, users: []string{"LinkedDir"}},
		{name: "an unused cursor with a symlinked cursors dir", cursor: "LinkedDir", inUse: []string{"Plain"}},
		{name: "an unused cursor", cursor: "Plain", inUse: []string{"Indexed", "Child"}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			e := setup(t)
			before := e.generated()

			err := RemoveCursor(e.opts(""), tc.cursor, tc.inUse)
			if tc.code == "" {
				require.NoError(t, err)
				assert.NotContains(t, e.generated(), tc.cursor)
				assert.Len(t, e.generated(), len(before)-1)
				if tc.cursor == "LinkedDir" {
					assert.FileExists(t, filepath.Join(e.icons, "Plain/cursors/left_ptr"))
				}
				return
			}
			var refusal *LibraryError
			require.ErrorAs(t, err, &refusal)
			assert.Equal(t, tc.code, refusal.Code)
			assert.Equal(t, tc.users, refusal.Themes)
			assert.Equal(t, before, e.generated())
			assert.FileExists(t, filepath.Join(e.sys, "System/cursors/left_ptr"))
		})
	}
}
