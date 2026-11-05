package wallpaper

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"testing"
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
