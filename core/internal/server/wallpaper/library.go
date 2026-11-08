package wallpaper

import (
	"cmp"
	"context"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

const listTimeout = 30 * time.Second

var maxListedItems = 50000

type Folder struct {
	Path      string `json:"path"`
	Recursive bool   `json:"recursive"`
}

type Variant struct {
	Path   string `json:"path"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
}

// Item is one wallpaper. A KDE package has its sizes in Variants, largest first, and Path is the largest.
type Item struct {
	Path     string    `json:"path"`
	Variants []Variant `json:"variants,omitempty"`
}

type Library struct {
	Items     []Item   `json:"items"`
	Missing   []string `json:"missing"`
	Truncated bool     `json:"truncated"`
}

type lister struct {
	ctx        context.Context
	extensions map[string]bool
	seen       map[string]bool
	items      []Item
	truncated  bool
}

// ListWallpapers walks folders and returns the files with one of the extensions, sorted by path.
// Paths keep the folder's spelling, so symlinks in it stay unresolved. The result is cut short
// when it reaches maxListedItems or ctx ends.
func ListWallpapers(ctx context.Context, folders []Folder, extensions []string) Library {
	l := &lister{ctx: ctx, extensions: map[string]bool{}, seen: map[string]bool{}, items: []Item{}}
	for _, ext := range extensions {
		l.extensions[strings.ToLower(ext)] = true
	}

	missing := []string{}
	for _, folder := range folders {
		realPath, err := filepath.EvalSymlinks(folder.Path)
		if err == nil {
			err = l.walk(folder.Path, realPath, folder.Recursive, map[string]bool{})
		}
		if err != nil {
			missing = append(missing, folder.Path)
		}
	}

	slices.SortFunc(l.items, func(a, b Item) int { return cmp.Compare(a.Path, b.Path) })
	return Library{Items: l.items, Missing: missing, Truncated: l.truncated}
}

func (l *lister) walk(dir, realDir string, recursive bool, visited map[string]bool) error {
	if visited[realDir] {
		return nil
	}
	visited[realDir] = true

	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	if recursive && l.addPackage(dir, realDir, entries) {
		return nil
	}

	for _, entry := range entries {
		if l.ctx.Err() != nil {
			l.truncated = true
		}
		if l.truncated {
			return nil
		}

		name := entry.Name()
		path := filepath.Join(dir, name)
		realPath := filepath.Join(realDir, name)
		mode := entry.Type()
		if mode&fs.ModeSymlink != 0 {
			if realPath, err = filepath.EvalSymlinks(path); err != nil {
				continue
			}
			info, err := os.Stat(realPath)
			if err != nil {
				continue
			}
			mode = info.Mode()
		}

		switch {
		case mode.IsDir():
			if recursive && !strings.HasPrefix(name, ".") {
				_ = l.walk(path, realPath, true, visited)
			}
		case mode.IsRegular() && l.wanted(name):
			l.add(Item{Path: path}, realPath)
		}
	}
	return nil
}

// addPackage collapses a KDE wallpaper package, a folder with metadata and contents/images/WxH.ext, into one item.
func (l *lister) addPackage(dir, realDir string, entries []os.DirEntry) bool {
	hasMetadata := slices.ContainsFunc(entries, func(entry os.DirEntry) bool {
		return entry.Name() == "metadata.json" || entry.Name() == "metadata.desktop"
	})
	if !hasMetadata {
		return false
	}

	imagesDir := filepath.Join(dir, "contents", "images")
	images, err := os.ReadDir(imagesDir)
	if err != nil {
		return false
	}

	var variants []Variant
	for _, image := range images {
		width, height, ok := parseSize(image.Name())
		if !ok || !l.wanted(image.Name()) {
			continue
		}
		path := filepath.Join(imagesDir, image.Name())
		if info, err := os.Stat(path); err != nil || !info.Mode().IsRegular() {
			continue
		}
		variants = append(variants, Variant{Path: path, Width: width, Height: height})
	}
	if len(variants) == 0 {
		return false
	}

	slices.SortStableFunc(variants, func(a, b Variant) int {
		return cmp.Compare(b.Width*b.Height, a.Width*a.Height)
	})
	l.add(Item{Path: variants[0].Path, Variants: variants}, realDir)
	return true
}

func (l *lister) add(item Item, realPath string) {
	// JSON can't carry a name that isn't valid UTF-8.
	if l.seen[realPath] || !utf8.ValidString(item.Path) {
		return
	}
	if len(l.items) >= maxListedItems {
		l.truncated = true
		return
	}
	l.seen[realPath] = true
	l.items = append(l.items, item)
}

func (l *lister) wanted(name string) bool {
	return l.extensions[strings.ToLower(strings.TrimPrefix(filepath.Ext(name), "."))]
}

func parseSize(name string) (int, int, bool) {
	w, h, ok := strings.Cut(strings.TrimSuffix(name, filepath.Ext(name)), "x")
	if !ok {
		return 0, 0, false
	}
	width, errW := strconv.Atoi(w)
	height, errH := strconv.Atoi(h)
	if errW != nil || errH != nil || width <= 0 || height <= 0 {
		return 0, 0, false
	}
	return width, height, true
}
