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

// Item is one wallpaper. A KDE package lists its sizes in Variants, largest first, and Path is the largest.
// Folder is the listed folder that owns it, as the caller spelled it. Size and Mtime come from the largest variant.
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
	set        folderSet
	cur        int
	items      []Item
	truncated  bool
	owners     map[ownerKey]int
}

type ownerKey struct {
	dir string
	pkg bool
}

// folderSet resolves each listed folder once. A folder that can't be resolved owns nothing.
type folderSet struct {
	folders []Folder
	real    []string
}

func newFolderSet(folders []Folder) folderSet {
	set := folderSet{folders: folders, real: make([]string, len(folders))}
	for i, folder := range folders {
		set.real[i], _ = filepath.EvalSymlinks(folder.Path)
	}
	return set
}

// owner returns the folder with the deepest real path that holds realDir, or -1. A non-recursive folder holds only
// its own files, a recursive one skips dot-directories, and a package needs a recursive folder.
func (s folderSet) owner(realDir string, pkg bool) int {
	best := -1
	for i, folder := range s.folders {
		if s.real[i] == "" || (pkg && !folder.Recursive) || (best >= 0 && len(s.real[i]) <= len(s.real[best])) {
			continue
		}
		rel, err := filepath.Rel(s.real[i], realDir)
		if err == nil && (rel == "." ||
			(folder.Recursive && !strings.HasPrefix(rel, ".") && !strings.Contains(rel, "/."))) {
			best = i
		}
	}
	return best
}

// dirOwner is owner for a spelled directory. A directory reached through a symlink to somewhere no folder holds
// belongs to the folder holding the nearest ancestor of its spelled path.
func (s folderSet) dirOwner(dir, realDir string, pkg bool) int {
	if i := s.owner(realDir, pkg); i >= 0 {
		return i
	}
	for d := dir; ; d = filepath.Dir(d) {
		if real, err := filepath.EvalSymlinks(d); err == nil {
			rest, _ := filepath.Rel(d, dir)
			if i := s.owner(filepath.Join(real, rest), pkg); i >= 0 {
				return i
			}
		}
		if filepath.Dir(d) == d {
			return -1
		}
	}
}

// FolderOf returns the listed folder that owns the file at path, as the caller spelled it, or "".
func FolderOf(path string, folders []Folder) string {
	realPath, err := filepath.EvalSymlinks(path)
	if err != nil {
		return ""
	}
	set := newFolderSet(folders)
	if i := set.dirOwner(filepath.Dir(path), filepath.Dir(realPath), false); i >= 0 {
		return folders[i].Path
	}
	return ""
}

// ListWallpapers walks folders and returns the files with one of the extensions, sorted by path.
// Each file belongs to one folder, and paths are spelled through it.
// The result is cut short when it reaches maxListedItems or ctx ends.
func ListWallpapers(ctx context.Context, folders []Folder, extensions []string) Library {
	l := &lister{ctx: ctx, extensions: map[string]bool{}, seen: map[string]bool{}, set: newFolderSet(folders), owners: map[ownerKey]int{}, items: []Item{}}
	for _, ext := range extensions {
		l.extensions[strings.ToLower(ext)] = true
	}

	missing := []string{}
	for i, folder := range folders {
		l.cur = i
		if l.set.real[i] == "" || l.walk(folder.Path, l.set.real[i], folder.Recursive, map[string]bool{}) != nil {
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
			l.add(Item{Path: path}, path, realPath, info, false)
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
	// A folder added inside the package's images folder lists those files itself.
	realImages, err := filepath.EvalSymlinks(imagesDir)
	if err != nil || l.dirOwner(imagesDir, realImages, false) != l.dirOwner(dir, realDir, true) {
		return false
	}

	slices.SortStableFunc(variants, func(a, b Variant) int {
		return cmp.Compare(b.Width*b.Height, a.Width*a.Height)
	})
	l.add(Item{Path: variants[0].Path, Variants: variants}, dir, realDir, infos[variants[0].Path], true)
	return true
}

// add lists a file, or a package whose folder is path, unless another folder owns it.
func (l *lister) add(item Item, path, realPath string, info fs.FileInfo, pkg bool) {
	dir, realDir := path, realPath
	if !pkg {
		dir, realDir = filepath.Dir(path), filepath.Dir(realPath)
	}
	// JSON can't carry a name that isn't valid UTF-8.
	if l.seen[realPath] || !utf8.ValidString(item.Path) {
		return
	}
	if owner := l.dirOwner(dir, realDir, pkg); owner >= 0 && owner != l.cur {
		return
	}
	if len(l.items) >= maxListedItems {
		l.truncated = true
		return
	}
	l.seen[realPath] = true
	item.Folder, item.Size, item.Mtime = l.set.folders[l.cur].Path, info.Size(), info.ModTime().Unix()
	l.items = append(l.items, item)
}

func (l *lister) dirOwner(dir, realDir string, pkg bool) int {
	key := ownerKey{dir, pkg}
	owner, ok := l.owners[key]
	if !ok {
		owner = l.set.dirOwner(dir, realDir, pkg)
		l.owners[key] = owner
	}
	return owner
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
