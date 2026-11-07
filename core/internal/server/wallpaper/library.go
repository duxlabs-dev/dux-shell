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

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
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
// Folder is the listed folder that owns the file, spelled as the caller sent it. Size and Mtime
// (Unix seconds) come from the largest variant for a package.
type Item struct {
	Path     string    `json:"path"`
	Variants []Variant `json:"variants,omitempty"`
	Folder   string    `json:"folder"`
	Size     int64     `json:"size"`
	Mtime    int64     `json:"mtime"`
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
	folder     string
	items      []Item
	truncated  bool
}

// ListWallpapers walks folders and returns the files with one of the extensions, sorted by path.
// A file belongs to the deepest listed folder that reaches it.
// Paths keep the folder's spelling, so symlinks in it stay unresolved. The result is cut short
// when it reaches maxListedItems or ctx ends.
func ListWallpapers(ctx context.Context, folders []Folder, extensions []string) Library {
	l := &lister{ctx: ctx, extensions: map[string]bool{}, seen: map[string]bool{}, items: []Item{}}
	for _, ext := range extensions {
		l.extensions[strings.ToLower(ext)] = true
	}

	realPaths := make([]string, len(folders))
	failed := make([]bool, len(folders))
	order := make([]int, len(folders))
	for i, folder := range folders {
		order[i] = i
		var err error
		if realPaths[i], err = filepath.EvalSymlinks(folder.Path); err != nil {
			failed[i] = true
		}
	}
	slices.SortStableFunc(order, func(a, b int) int { return cmp.Compare(len(realPaths[b]), len(realPaths[a])) })

	for _, i := range order {
		if failed[i] {
			continue
		}
		l.folder = folders[i].Path
		if l.walk(folders[i].Path, realPaths[i], folders[i].Recursive, map[string]bool{}) != nil {
			failed[i] = true
		}
	}

	missing := []string{}
	for i, folder := range folders {
		if failed[i] {
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
		var info fs.FileInfo
		if mode&fs.ModeSymlink != 0 {
			if realPath, err = filepath.EvalSymlinks(path); err != nil {
				continue
			}
			if info, err = os.Stat(realPath); err != nil {
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
			if info == nil {
				if info, err = entry.Info(); err != nil {
					continue
				}
			}
			l.add(Item{Path: path}, realPath, info)
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
	infos := map[string]fs.FileInfo{}
	for _, image := range images {
		width, height, ok := parseSize(image.Name())
		if !ok || !l.wanted(image.Name()) {
			continue
		}
		path := filepath.Join(imagesDir, image.Name())
		info, err := os.Stat(path)
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		infos[path] = info
		variants = append(variants, Variant{Path: path, Width: width, Height: height})
	}
	if len(variants) == 0 {
		return false
	}

	slices.SortStableFunc(variants, func(a, b Variant) int {
		return cmp.Compare(b.Width*b.Height, a.Width*a.Height)
	})
	l.add(Item{Path: variants[0].Path, Variants: variants}, realDir, infos[variants[0].Path])
	return true
}

func (l *lister) add(item Item, realPath string, info fs.FileInfo) {
	// JSON can't carry a name that isn't valid UTF-8.
	if l.seen[realPath] || !utf8.ValidString(item.Path) {
		return
	}
	if len(l.items) >= maxListedItems {
		l.truncated = true
		return
	}
	l.seen[realPath] = true
	item.Folder, item.Size, item.Mtime = l.folder, info.Size(), info.ModTime().Unix()
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

// SuggestFolders returns the existing standard wallpaper folders that aren't listed yet, each once.
func SuggestFolders(listed []string) []string {
	dataDirs := os.Getenv("XDG_DATA_DIRS")
	if dataDirs == "" {
		dataDirs = "/usr/local/share:/usr/share"
	}
	candidates := []string{}
	for _, dir := range append([]string{utils.XDGDataHome()}, strings.Split(dataDirs, ":")...) {
		if dir = strings.TrimSpace(dir); dir != "" {
			candidates = append(candidates, filepath.Join(dir, "wallpapers"), filepath.Join(dir, "backgrounds"))
		}
	}
	if pictures := utils.XDGPicturesDir(); pictures != "" {
		candidates = append(candidates, filepath.Join(pictures, "Wallpapers"))
	}

	taken := map[string]bool{}
	for _, path := range listed {
		taken[realOrClean(path)] = true
	}

	suggestions := []string{}
	for _, path := range candidates {
		realPath, err := filepath.EvalSymlinks(path)
		if err != nil || taken[realPath] {
			continue
		}
		if info, err := os.Stat(realPath); err != nil || !info.IsDir() {
			continue
		}
		taken[realPath] = true
		suggestions = append(suggestions, path)
	}
	return suggestions
}

// FolderListed reports whether path is one of the listed folders, comparing real paths.
// A path that can't be resolved, such as an unmounted folder, compares by its cleaned spelling.
func FolderListed(path string, listed []string) bool {
	target := realOrClean(path)
	return slices.ContainsFunc(listed, func(p string) bool { return realOrClean(p) == target })
}

func realOrClean(path string) string {
	if realPath, err := filepath.EvalSymlinks(path); err == nil {
		return realPath
	}
	return filepath.Clean(path)
}
