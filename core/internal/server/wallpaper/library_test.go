package wallpaper

import (
	"context"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
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

func TestListWallpapersFolderOwner(t *testing.T) {
	cases := []struct {
		name         string
		childRecurse bool
		want         map[string]string
	}{
		{name: "recursive child", childRecurse: true, want: map[string]string{"a.png": "parent", "sub/b.png": "child", "sub/deep/c.png": "child"}},
		{name: "non-recursive child", want: map[string]string{"a.png": "parent", "sub/b.png": "child", "sub/deep/c.png": "parent"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			root := t.TempDir()
			writeFiles(t, root, "a.png", "sub/b.png", "sub/deep/c.png")
			parent, child := Folder{Path: root, Recursive: true}, Folder{Path: filepath.Join(root, "sub"), Recursive: c.childRecurse}
			got := map[string]string{}
			for _, item := range ListWallpapers(context.Background(), []Folder{parent, child}, []string{"png"}).Items {
				rel, _ := filepath.Rel(root, item.Path)
				got[rel] = map[string]string{parent.Path: "parent", child.Path: "child"}[item.Folder]
			}
			if !maps.Equal(got, c.want) {
				t.Errorf("got %v, want %v", got, c.want)
			}
		})
	}
}

func TestListWallpapersFileInfo(t *testing.T) {
	root := t.TempDir()
	when := time.Unix(1700000000, 0)
	files := map[string]string{"a.png": "12345", "Next/metadata.json": "", "Next/contents/images/100x100.png": "12", "Next/contents/images/200x200.png": "1234567"}
	for name, content := range files {
		path := filepath.Join(root, name)
		writeFiles(t, root, name)
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(path, when, when); err != nil {
			t.Fatal(err)
		}
	}

	got := map[string]int64{}
	for _, item := range ListWallpapers(context.Background(), []Folder{{Path: root, Recursive: true}}, []string{"png"}).Items {
		if item.Mtime != when.Unix() {
			t.Errorf("%s: mtime %d", item.Path, item.Mtime)
		}
		got[filepath.Base(item.Path)] = item.Size
	}
	if want := map[string]int64{"a.png": 5, "200x200.png": 7}; !maps.Equal(got, want) {
		t.Errorf("got %v, want %v", got, want)
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
		if got := FolderListed(c.path, c.listed); got != c.want {
			t.Errorf("%s: got %v", c.name, got)
		}
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
	if got := SuggestFolders(want); len(got) != 1 {
		t.Errorf("all but one listed: got %q", got)
	}
}
