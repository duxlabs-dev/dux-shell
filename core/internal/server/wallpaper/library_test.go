package wallpaper

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"golang.org/x/image/bmp"
)

func writeFiles(t *testing.T, root string, names ...string) {
	t.Helper()
	for _, name := range names {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func listedNames(root string, library Library) []string {
	names := []string{}
	for _, item := range library.Items {
		name, _ := filepath.Rel(root, item.Path)
		names = append(names, name)
	}
	return names
}

func TestListWallpapers(t *testing.T) {
	cases := []struct {
		name      string
		files     []string
		links     map[string]string
		recursive bool
		want      []string
	}{
		{name: "quote and newline in names", files: []string{"wall\"papers/a.png", "b\nc.png"}, recursive: true, want: []string{"b\nc.png", "wall\"papers/a.png"}},
		{name: "not recursive", files: []string{"a.png", "sub/b.png"}, want: []string{"a.png"}},
		{name: "extension case and other files", files: []string{"a.PNG", "b.Mp4", "c.txt", "d"}, want: []string{"a.PNG", "b.Mp4"}},
		{name: "dot directory skipped, dot file kept", files: []string{".git/a.png", ".b.png"}, recursive: true, want: []string{".b.png"}},
		{name: "symlink loop", files: []string{"sub/a.png"}, links: map[string]string{"sub/loop": ".."}, recursive: true, want: []string{"sub/a.png"}},
		{name: "symlinked file listed once", files: []string{"a.png"}, links: map[string]string{"b.png": "a.png"}, want: []string{"a.png"}},
		{name: "broken symlink ignored", files: []string{"a.png"}, links: map[string]string{"z": "/nonexistent"}, want: []string{"a.png"}},
		{
			name:      "KDE package is one item",
			files:     []string{"Next/metadata.json", "Next/contents/images/1920x1080.png", "Next/contents/images/5120x2880.png", "Next/contents/images_dark/5120x2880.png", "Next/contents/screenshot.png"},
			recursive: true,
			want:      []string{"Next/contents/images/5120x2880.png"},
		},
		{name: "contents without metadata is not a package", files: []string{"Plain/contents/images/1920x1080.png"}, recursive: true, want: []string{"Plain/contents/images/1920x1080.png"}},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			root := t.TempDir()
			writeFiles(t, root, c.files...)
			for name, target := range c.links {
				if err := os.Symlink(target, filepath.Join(root, name)); err != nil {
					t.Fatal(err)
				}
			}

			library := ListWallpapers(context.Background(), []Folder{{Path: root, Recursive: c.recursive}}, []string{"png", "mp4"})
			if got := listedNames(root, library); !slices.Equal(got, c.want) {
				t.Errorf("got %q, want %q", got, c.want)
			}
			if len(library.Missing) != 0 || library.Truncated {
				t.Errorf("missing %q, truncated %v", library.Missing, library.Truncated)
			}
		})
	}
}

func TestListWallpapersPackageVariants(t *testing.T) {
	root := t.TempDir()
	writeFiles(t, root, "Next/metadata.desktop", "Next/contents/images/1440x2960.png", "Next/contents/images/7680x2160.png", "Next/contents/images/notes.png")

	library := ListWallpapers(context.Background(), []Folder{{Path: root, Recursive: true}}, []string{"png"})
	images := filepath.Join(root, "Next", "contents", "images")
	want := []Variant{{filepath.Join(images, "7680x2160.png"), 7680, 2160}, {filepath.Join(images, "1440x2960.png"), 1440, 2960}}
	if len(library.Items) != 1 || !slices.Equal(library.Items[0].Variants, want) {
		t.Errorf("got %+v", library.Items)
	}
}

func TestListWallpapersKeepsFolderSpelling(t *testing.T) {
	root := t.TempDir()
	writeFiles(t, root, "real/a.png")
	link := filepath.Join(root, "link")
	if err := os.Symlink("real", link); err != nil {
		t.Fatal(err)
	}

	library := ListWallpapers(context.Background(), []Folder{{Path: link}}, []string{"png"})
	if len(library.Items) != 1 || library.Items[0].Path != filepath.Join(link, "a.png") {
		t.Errorf("got %+v", library.Items)
	}
}

func TestListWallpapersMissingFolder(t *testing.T) {
	root := t.TempDir()
	gone := filepath.Join(root, "gone")
	writeFiles(t, root, "a.png")

	library := ListWallpapers(context.Background(), []Folder{{Path: gone}, {Path: root}}, []string{"png"})
	if !slices.Equal(library.Missing, []string{gone}) || len(library.Items) != 1 {
		t.Errorf("got %+v", library)
	}
}

func TestListWallpapersCutShort(t *testing.T) {
	root := t.TempDir()
	writeFiles(t, root, "a.png", "b.png", "c.png")
	folders := []Folder{{Path: root}}

	defer func(limit int) { maxListedItems = limit }(maxListedItems)
	maxListedItems = 3
	if library := ListWallpapers(context.Background(), folders, []string{"png"}); len(library.Items) != 3 || library.Truncated {
		t.Errorf("at the cap: got %+v", library)
	}
	maxListedItems = 2
	if library := ListWallpapers(context.Background(), folders, []string{"png"}); len(library.Items) != 2 || !library.Truncated {
		t.Errorf("over the cap: got %+v", library)
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if library := ListWallpapers(ctx, folders, []string{"png"}); !library.Truncated || len(library.Missing) != 0 {
		t.Errorf("timed out: got %+v", library)
	}
}

func TestFolderOwner(t *testing.T) {
	cases := []struct {
		name    string
		files   []string
		links   map[string]string
		folders []Folder
		want    []string
	}{
		{
			"recursive child",
			[]string{"a.png", "sub/b.png", "sub/deep/c.png"},
			nil,
			[]Folder{{Path: "", Recursive: true}, {Path: "sub", Recursive: true}},
			[]string{"a.png=.", "sub/b.png=sub", "sub/deep/c.png=sub"},
		},
		{
			"non-recursive child",
			[]string{"a.png", "sub/b.png", "sub/deep/c.png"},
			nil,
			[]Folder{{Path: "", Recursive: true}, {Path: "sub"}},
			[]string{"a.png=.", "sub/b.png=sub", "sub/deep/c.png=."},
		},
		{
			"real folder beats the symlink to it",
			[]string{"Walls/x.png"},
			map[string]string{"Pictures/Walls": "../Walls"},
			[]Folder{{Path: "Pictures", Recursive: true}, {Path: "Walls", Recursive: true}},
			[]string{"Walls/x.png=Walls"},
		},
		{
			"symlinked folder inside a recursive folder",
			[]string{"Pictures/Walls/x.png", "Pictures/y.png"},
			map[string]string{"Walls": "Pictures/Walls"},
			[]Folder{{Path: "Pictures", Recursive: true}, {Path: "Walls"}},
			[]string{"Pictures/y.png=Pictures", "Walls/x.png=Walls"},
		},
		{
			"non-recursive folder does not claim nested files",
			[]string{"Pictures/a.png", "Pictures/sub/b.png"},
			map[string]string{"Walls": "Pictures"},
			[]Folder{{Path: "Pictures"}, {Path: "Walls", Recursive: true}},
			[]string{"Pictures/a.png=Pictures", "Walls/sub/b.png=Walls"},
		},
		{
			"symlinked file pointing outside",
			[]string{"out/x.png"},
			map[string]string{"a/link.png": "../out/x.png"},
			[]Folder{{Path: "a"}},
			[]string{"a/link.png=a"},
		},
		{
			"symlinked folder pointing outside",
			[]string{"out/x.png"},
			map[string]string{"a/sub": "../out"},
			[]Folder{{Path: "a", Recursive: true}},
			[]string{"a/sub/x.png=a"},
		},
		{
			"outside symlink goes to the nearest nested folder",
			[]string{"out/x.png"},
			map[string]string{"a/d/link.png": "../../out/x.png"},
			[]Folder{{Path: "a", Recursive: true}, {Path: "a/d"}},
			[]string{"a/d/link.png=a/d"},
		},
		{
			"outside symlink below a non-recursive folder goes to the recursive one",
			[]string{"out/d/e.png"},
			map[string]string{"r/a/link": "../../out/d"},
			[]Folder{{Path: "r/a"}, {Path: "r", Recursive: true}},
			[]string{"r/a/link/e.png=r"},
		},
		{
			"dot-directory reached through a symlink",
			[]string{"b/.hidden/h.png"},
			map[string]string{"c/vis": "../b/.hidden"},
			[]Folder{{Path: "b", Recursive: true}, {Path: "c", Recursive: true}},
			[]string{"c/vis/h.png=c"},
		},
		{
			"images folder inside a package",
			[]string{"p/pkg/metadata.json", "p/pkg/contents/images/1x1.png", "p/pkg/contents/images/2x2.png"},
			nil,
			[]Folder{{Path: "p", Recursive: true}, {Path: "p/pkg/contents/images"}},
			[]string{"p/pkg/contents/images/1x1.png=p/pkg/contents/images", "p/pkg/contents/images/2x2.png=p/pkg/contents/images"},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			root, err := filepath.EvalSymlinks(t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			writeFiles(t, root, c.files...)
			for name, target := range c.links {
				if err := os.MkdirAll(filepath.Dir(filepath.Join(root, name)), 0o755); err != nil {
					t.Fatal(err)
				}
				if err := os.Symlink(target, filepath.Join(root, name)); err != nil {
					t.Fatal(err)
				}
			}
			folders := []Folder{}
			for _, folder := range c.folders {
				folders = append(folders, Folder{Path: filepath.Join(root, folder.Path), Recursive: folder.Recursive})
			}

			got := []string{}
			for _, item := range ListWallpapers(context.Background(), folders, []string{"png"}).Items {
				rel, _ := filepath.Rel(root, item.Path)
				owner, _ := filepath.Rel(root, item.Folder)
				got = append(got, rel+"="+owner)
				if listed := FolderOf(item.Path, folders); listed != item.Folder {
					t.Errorf("FolderOf(%s) = %q, listed under %q", rel, listed, item.Folder)
				}
			}
			if !slices.Equal(got, c.want) {
				t.Errorf("got %q, want %q", got, c.want)
			}
		})
	}
}

func TestFolderListed(t *testing.T) {
	root := t.TempDir()
	target := filepath.Join(root, "target")
	other := filepath.Join(root, "other")
	link := filepath.Join(root, "link")
	gone := filepath.Join(root, "gone")
	for _, dir := range []string{target, other} {
		if err := os.Mkdir(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		name   string
		path   string
		listed []string
		want   bool
	}{
		{"through a symlink", link, []string{target}, true},
		{"listed through a symlink", target, []string{link}, true},
		{"trailing slash", target + "/", []string{target}, true},
		{"missing but identical", gone, []string{gone + "/"}, true},
		{"different folder", other, []string{target}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := FolderListed(c.path, c.listed); got != c.want {
				t.Errorf("got %v", got)
			}
		})
	}
}

func TestSuggestFolders(t *testing.T) {
	root := t.TempDir()
	home, share, pictures := filepath.Join(root, "home"), filepath.Join(root, "share"), filepath.Join(root, "pics")
	for _, dir := range []string{home + "/wallpapers", share + "/backgrounds", share + "/wallpapers", pictures + "/Wallpapers"} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	writeFiles(t, home, "backgrounds")
	link := filepath.Join(root, "link")
	if err := os.Symlink(share+"/wallpapers", link); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_DATA_HOME", home)
	t.Setenv("XDG_DATA_DIRS", share+":"+share+"/../share:"+filepath.Join(root, "missing"))
	t.Setenv("XDG_PICTURES_DIR", pictures)

	got := SuggestFolders([]string{link})
	want := []string{home + "/wallpapers", share + "/backgrounds", pictures + "/Wallpapers"}
	if !slices.Equal(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
}

func writeImage(t *testing.T, path string, w, h int) {
	t.Helper()
	var buf bytes.Buffer
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	var err error
	switch filepath.Ext(path) {
	case ".jpg":
		err = jpeg.Encode(&buf, img, nil)
	case ".bmp":
		err = bmp.Encode(&buf, img)
	default:
		err = png.Encode(&buf, img)
	}
	if err == nil {
		err = os.WriteFile(path, buf.Bytes(), 0o644)
	}
	if err != nil {
		t.Fatal(err)
	}
}

// fakeFFprobe puts an ffprobe on an otherwise empty PATH that leaves a marker file and lists sections for -sections.
// A probe naming a stream_group section outside sections exits 1 like the real one; otherwise it prints out and exits with code.
func fakeFFprobe(t *testing.T, out string, code int, sections ...string) (ran string) {
	t.Helper()
	dir := t.TempDir()
	if sections == nil {
		sections = []string{"stream_group_component", "stream_group_side_data"}
	}
	script := fmt.Sprintf(`#!/bin/sh
: > "$0.ran"
case "$*" in *-sections*) printf '%%s\n' %s; exit 0;; esac
IFS=:
set -f
for w in $*; do
	case "$w" in stream_group_*) case " %s " in *" ${w%%%%=*} "*) ;; *) exit 1;; esac;; esac
done
printf '%%s' '%s'
exit %d
`, "root stream_groups "+strings.Join(sections, " "), strings.Join(sections, " "), out, code)
	if err := os.WriteFile(filepath.Join(dir, "ffprobe"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	return filepath.Join(dir, "ffprobe.ran")
}

func TestReadSizes(t *testing.T) {
	const tiled = `{"stream_groups":[{"components":[{"width":4000,"height":3000,"side_data_list":[{"rotation":-90}]}]}],"streams":[{"width":512,"height":512}]}`
	cases := []struct {
		name, file string
		w, h       int
		raw        string
		probe      string
		code       int
		sections   []string
		variants   bool
		wantW      int
		wantH      int
		wantProbe  bool
	}{
		{name: "png", file: "a.png", w: 300, h: 200, wantW: 300, wantH: 200},
		{name: "jpeg", file: "a.jpg", w: 64, h: 48, wantW: 64, wantH: 48},
		{name: "bmp", file: "a.bmp", w: 10, h: 20, wantW: 10, wantH: 20},
		{name: "corrupt png", file: "a.png", raw: "\x89PNG\r\n\x1a\ngarbage"},
		{name: "svg", file: "a.svg", raw: "<svg/>", probe: `{"streams":[{"width":5,"height":5}]}`},
		{name: "rotated video", file: "a.mp4", raw: "x", probe: `{"streams":[{"width":1920,"height":1080,"side_data_list":[{"rotation":90}]}]}`, wantW: 1080, wantH: 1920, wantProbe: true},
		{name: "rotated video, ffprobe 6", file: "a.mp4", raw: "x", probe: `{"streams":[{"width":1920,"height":1080,"side_data_list":[{"rotation":90}]}]}`, sections: []string{"streams"}, wantW: 1080, wantH: 1920, wantProbe: true},
		{name: "rotated video, ffprobe 7", file: "a.mp4", raw: "x", probe: `{"streams":[{"width":1920,"height":1080,"side_data_list":[{"rotation":90}]}]}`, sections: []string{"stream_group_component"}, wantW: 1080, wantH: 1920, wantProbe: true},
		{name: "tile grid", file: "a.heic", raw: "x", probe: tiled, wantW: 3000, wantH: 4000, wantProbe: true},
		{name: "ffprobe fails", file: "a.mp4", raw: "x", probe: `{"streams":[{"width":5,"height":5}]}`, code: 1, wantProbe: true},
		{name: "package", file: "a.png", w: 30, h: 20, variants: true},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			ran := fakeFFprobe(t, c.probe, c.code, c.sections...)
			path := filepath.Join(t.TempDir(), c.file)
			if c.raw != "" {
				if err := os.WriteFile(path, []byte(c.raw), 0o644); err != nil {
					t.Fatal(err)
				}
			} else {
				writeImage(t, path, c.w, c.h)
			}
			items := []Item{{Path: path}}
			if c.variants {
				items[0].Variants = []Variant{{Path: path, Width: 30, Height: 20}}
			}

			readSizes(context.Background(), items)
			if items[0].Width != c.wantW || items[0].Height != c.wantH {
				t.Errorf("got %dx%d, want %dx%d", items[0].Width, items[0].Height, c.wantW, c.wantH)
			}
			if _, err := os.Stat(ran); (err == nil) != c.wantProbe {
				t.Errorf("ffprobe ran: %v, want %v", err == nil, c.wantProbe)
			}
			os.Remove(ran)
			readSizes(context.Background(), items)
			if _, err := os.Stat(ran); err == nil {
				t.Error("ffprobe ran again for a final answer")
			}
		})
	}
}

func TestReadSizesCache(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("PATH", "")
	read := func(item Item) Item {
		items := []Item{item}
		readSizes(context.Background(), items)
		return items[0]
	}

	still := filepath.Join(dir, "a.png")
	writeImage(t, still, 30, 20)
	read(Item{Path: still, Size: 1, Mtime: 1})
	writeImage(t, still, 40, 10)
	if got := read(Item{Path: still, Size: 1, Mtime: 1}); got.Width != 30 {
		t.Errorf("same size and mtime: got width %d, want the cached 30", got.Width)
	}
	if got := read(Item{Path: still, Size: 1, Mtime: 2}); got.Width != 40 {
		t.Errorf("new mtime: got width %d, want 40", got.Width)
	}

	video := Item{Path: filepath.Join(dir, "a.mp4")}
	writeFiles(t, dir, "a.mp4")
	if got := read(video); got.Width != 0 {
		t.Errorf("without ffprobe: got width %d", got.Width)
	}
	fakeFFprobe(t, `{"streams":[{"width":1920,"height":1080}]}`, 0)
	if got := read(video); got.Width != 1920 {
		t.Errorf("ffprobe installed later: got width %d, want 1920", got.Width)
	}
}
