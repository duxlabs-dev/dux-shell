package iconfolders

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"image"
	"image/draw"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"syscall"
)

const (
	xcursorMagic = 0x72756358 // "Xcur"
	xcursorImage = 0xfffd0002
	// The nominal size a preview is taken at, and the largest image side and table read from a file.
	pointerSize    = 48
	maxPointerSide = 512
	maxPointerToc  = 1024
)

// The names a theme may give its default pointer, first found wins.
var pointerNames = []string{"left_ptr", "default", "arrow"}

// Representative cursor states previewed for each theme, in display order.
var cursorPreviewStates = [][]string{
	pointerNames,
	{"hand2", "pointer", "pointing_hand", "hand1"},
	{"xterm", "text", "ibeam"},
	{"left_ptr_watch", "progress", "watch", "wait"},
	{"crosshair", "cross", "tcross"},
	{"fleur", "move", "all-scroll", "grab"},
	{"sb_h_double_arrow", "ew-resize", "h_double_arrow"},
	{"sb_v_double_arrow", "ns-resize", "v_double_arrow"},
	{"not-allowed", "crossed_circle", "no-drop"},
}

type CursorInfo struct {
	Name string `json:"name"`
	// Removable cursor themes live in the user's icon directory.
	Removable bool `json:"removable"`
	// Pointer is the theme's default pointer as a PNG data URL, "" where it has none in Xcursor form.
	Pointer string `json:"pointer"`
	// Cursors holds PNG data URLs for representative cursor states in the theme.
	Cursors []string `json:"cursors,omitempty"`
}

func hasCursors(dir string) bool {
	info, err := os.Lstat(filepath.Join(dir, "cursors"))
	return err == nil && info.IsDir()
}

// hasCursorDir follows a symlinked cursors directory, matching ListCursors and libXcursor.
func hasCursorDir(dir string) bool {
	info, err := os.Stat(filepath.Join(dir, "cursors"))
	return err == nil && info.IsDir()
}

// ListCursors previews every installed cursor theme.
func ListCursors(o Options) []CursorInfo {
	o.defaults()
	lib := o.library()
	cursors, seen := []CursorInfo{}, map[string]bool{}
	for _, base := range lib.bases {
		entries, _ := os.ReadDir(base)
		for _, entry := range entries {
			name := entry.Name()
			if seen[name] || !hasCursorDir(filepath.Join(base, name)) {
				continue
			}
			seen[name] = true
			pointer := lib.pointer(name, 4)
			cursors = append(cursors, CursorInfo{
				Name:      name,
				Removable: base == o.IconsDir,
				Pointer:   pointer,
				Cursors:   lib.cursorPreviews(name, pointer),
			})
		}
	}
	return cursors
}

// pointer looks through a theme and then what it inherits, as libXcursor does.
func (l *library) pointer(name string, depth int) string {
	return l.cursorByNames(name, pointerNames, depth)
}

func (l *library) cursorPreviews(name, pointer string) []string {
	var previews []string
	if pointer != "" {
		previews = append(previews, pointer)
	}
	for _, names := range cursorPreviewStates[1:] {
		if url := l.cursorByNames(name, names, 4); url != "" {
			previews = append(previews, url)
		}
	}
	return previews
}

func (l *library) cursorByNames(name string, names []string, depth int) string {
	if depth == 0 || name == "" || name != filepath.Base(name) {
		return ""
	}
	for _, base := range l.bases {
		for _, file := range names {
			if url := pointerURL(filepath.Join(base, name, "cursors", file)); url != "" {
				return url
			}
		}
	}
	if sh := l.shelf(name); sh != nil {
		for _, parent := range sh.inherits {
			if url := l.cursorByNames(parent, names, depth-1); url != "" {
				return url
			}
		}
	}
	return ""
}

func pointerURL(path string) string {
	real, err := filepath.EvalSymlinks(path)
	if err != nil {
		return ""
	}
	// Non-blocking and no-follow, as readPlain: a cursor file is untrusted and may be swapped.
	f, err := openFile(real, os.O_RDONLY|syscall.O_NONBLOCK|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return ""
	}
	defer f.Close()
	if info, err := f.Stat(); err != nil || !info.Mode().IsRegular() {
		return ""
	}
	img := readPointer(f)
	if img == nil {
		return ""
	}
	var out bytes.Buffer
	if png.Encode(&out, img) != nil {
		return ""
	}
	return "data:image/png;base64," + base64.StdEncoding.EncodeToString(out.Bytes())
}

// readPointer decodes the image of an Xcursor file nearest the preview size, cropped to what it
// draws and centered in a square. It returns nil for anything it cannot read in full.
func readPointer(r io.ReaderAt) *image.RGBA {
	u32 := binary.LittleEndian.Uint32
	head := make([]byte, 16)
	if _, err := r.ReadAt(head, 0); err != nil || u32(head) != xcursorMagic {
		return nil
	}
	count := u32(head[12:])
	if count == 0 || count > maxPointerToc {
		return nil
	}
	toc := make([]byte, 12*count)
	if _, err := r.ReadAt(toc, int64(u32(head[4:]))); err != nil {
		return nil
	}
	at, off := int64(-1), int64(0)
	for i := 0; i < len(toc); i += 12 {
		// An animated cursor repeats a size; its first frame is the one kept.
		miss := max(int64(u32(toc[i+4:]))-pointerSize, pointerSize-int64(u32(toc[i+4:])))
		if u32(toc[i:]) == xcursorImage && (at < 0 || miss < off) {
			at, off = int64(u32(toc[i+8:])), miss
		}
	}
	chunk := make([]byte, 36)
	if at < 0 {
		return nil
	}
	if _, err := r.ReadAt(chunk, at); err != nil || u32(chunk[4:]) != xcursorImage {
		return nil
	}
	w, h := int(u32(chunk[16:])), int(u32(chunk[20:]))
	if w < 1 || h < 1 || w > maxPointerSide || h > maxPointerSide {
		return nil
	}
	src := image.NewRGBA(image.Rect(0, 0, w, h))
	if _, err := r.ReadAt(src.Pix, at+36); err != nil {
		return nil
	}

	drawn := image.Rectangle{}
	for i := 0; i < len(src.Pix); i += 4 {
		p := src.Pix[i : i+4]
		// Stored as premultiplied BGRA; a color above its alpha is not a valid pixel.
		p[0], p[2] = min(p[2], p[3]), min(p[0], p[3])
		p[1] = min(p[1], p[3])
		if p[3] != 0 {
			x, y := i/4%w, i/4/w
			drawn = drawn.Union(image.Rect(x, y, x+1, y+1))
		}
	}
	if drawn.Empty() {
		return nil
	}
	side := max(drawn.Dx(), drawn.Dy())
	out := image.NewRGBA(image.Rect(0, 0, side, side))
	draw.Draw(out, drawn.Sub(drawn.Min).Add(image.Pt((side-drawn.Dx())/2, (side-drawn.Dy())/2)), src, drawn.Min, draw.Src)
	return out
}
