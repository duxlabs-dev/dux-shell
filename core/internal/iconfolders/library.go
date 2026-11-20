package iconfolders

import (
	"bytes"
	"cmp"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
)

// Library codes are a contract with the settings UI, which owns the translated text.
const (
	CodeExists       = "exists"
	CodeNoTheme      = "no-theme"
	CodeBadSource    = "bad-source"
	CodeNotRemovable = "not-removable"
	CodeInUse        = "in-use"
)

// LibraryError names the themes a refusal is about: the ones in the way, or the ones still using it.
type LibraryError struct {
	Code   string   `json:"code"`
	Themes []string `json:"themes,omitempty"`
	Reason string   `json:"error"`
}

func (e *LibraryError) Error() string {
	if len(e.Themes) == 0 {
		return e.Reason
	}
	return e.Reason + ": " + strings.Join(e.Themes, ", ")
}

// PreviewNames are the icons a theme is shown by, in the order ThemeInfo.Icons holds them.
var PreviewNames = []string{"folder", "user-home", "text-x-generic", "image-x-generic", "utilities-terminal", "system-file-manager", "preferences-system", "user-trash-full"}

const previewSize = 48

type ThemeInfo struct {
	Name string `json:"name"`
	// Removable themes live in the user's icon directory.
	Removable bool `json:"removable"`
	// Icons holds one file per preview name, "" where the theme and its parents have none.
	Icons []string `json:"icons"`
}

type shelf struct {
	path     string
	inherits []string
	// dirs can draw an icon at the preview size, best first.
	dirs []string
}

type library struct {
	bases  []string
	loaded map[string]*shelf
}

func readShelf(dir string) *shelf {
	index, err := filepath.EvalSymlinks(filepath.Join(dir, "index.theme"))
	if err != nil {
		return nil
	}
	data, err := readPlain(index)
	if err != nil {
		return nil
	}
	sh := &shelf{path: dir}
	for line := range strings.Lines(string(data)) {
		if key, value, ok := strings.Cut(line, "="); ok && strings.TrimSpace(key) == "Inherits" {
			sh.inherits = strings.FieldsFunc(value, func(r rune) bool { return r == ',' || r == ' ' || r == '\r' || r == '\n' })
			break
		}
	}

	rank := map[string]int{}
	for _, dir := range parseIndex(data).dirs {
		size, _ := strconv.Atoi(dir.keys["Size"])
		scalable := strings.EqualFold(dir.keys["Type"], "Scalable")
		if dir.scaled || !scalable && (size < 32 || size > 256) {
			continue
		}
		// Nearest the preview size first; a scalable directory wins a tie.
		rank[dir.rel] = 2 * max(size-previewSize, previewSize-size)
		if !scalable {
			rank[dir.rel]++
		}
		sh.dirs = append(sh.dirs, dir.rel)
	}
	slices.SortStableFunc(sh.dirs, func(a, b string) int { return cmp.Compare(rank[a], rank[b]) })
	return sh
}

func (l *library) shelf(name string) *shelf {
	if sh, ok := l.loaded[name]; ok {
		return sh
	}
	var sh *shelf
	if name != "" && name == filepath.Base(name) {
		for _, base := range l.bases {
			if sh = readShelf(filepath.Join(base, name)); sh != nil {
				break
			}
		}
	}
	l.loaded[name] = sh
	return sh
}

// chain is a theme followed by everything it inherits, breadth first as the icon spec looks icons up.
func (l *library) chain(first *shelf, fallback string) []*shelf {
	chain, seen := []*shelf{first}, map[string]bool{}
	for i := 0; i < len(chain) && len(chain) < 16; i++ {
		for _, name := range chain[i].inherits {
			if sh := l.shelf(name); sh != nil && !seen[name] {
				chain = append(chain, sh)
			}
			seen[name] = true
		}
	}
	if sh := l.shelf(fallback); sh != nil && !seen[fallback] {
		chain = append(chain, sh)
	}
	return chain
}

func (l *library) previews(first *shelf) []string {
	chain := l.chain(first, "hicolor")
	icons := make([]string, len(PreviewNames))
	for i, name := range PreviewNames {
		icons[i] = preview(chain, name)
	}
	return icons
}

// Qt paints a masked SVG on a black box, so one is shown only when nothing else draws the icon.
func preview(chain []*shelf, name string) string {
	masked := ""
	for _, sh := range chain {
		for _, dir := range sh.dirs {
			for _, ext := range []string{".svg", ".png"} {
				file := filepath.Join(sh.path, dir, name+ext)
				if info, err := os.Stat(file); err != nil || !info.Mode().IsRegular() {
					continue
				}
				if data, err := os.ReadFile(file); ext == ".svg" && (err != nil || bytes.Contains(data, []byte("<mask"))) {
					masked = cmp.Or(masked, file)
					continue
				}
				return file
			}
		}
	}
	return masked
}

func (o *Options) library() *library {
	o.defaults()
	return &library{bases: o.BaseDirs, loaded: map[string]*shelf{}}
}

// ListThemes previews every installed theme without making any of them the current one.
func ListThemes(o Options) []ThemeInfo {
	lib := o.library()
	themes := []ThemeInfo{}
	// The self-built pack is listed by its own name and drawn from the generation in use.
	if state := ReadState(o.StateDir); state.Base == SelfBuilt {
		if sh := readShelf(filepath.Join(o.IconsDir, state.Applied)); sh != nil {
			themes = append(themes, ThemeInfo{Name: SelfBuilt, Icons: lib.previews(sh)})
		}
	}

	seen := map[string]bool{}
	for _, base := range lib.bases {
		entries, _ := os.ReadDir(base)
		for _, entry := range entries {
			name := entry.Name()
			if seen[name] || reserved(name) {
				continue
			}
			sh := lib.shelf(name)
			// A cursor theme has an index too, with no icon directories.
			if sh == nil || len(sh.dirs) == 0 {
				continue
			}
			seen[name] = true
			themes = append(themes, ThemeInfo{Name: name, Removable: filepath.Dir(sh.path) == o.IconsDir, Icons: lib.previews(sh)})
		}
	}
	return themes
}

// needs reports whether a theme draws from the directory dir: by inheriting it, or by linking into it
// from anywhere in its tree, as the installer lets a theme do.
func (l *library) needs(user *shelf, dir string) bool {
	for _, sh := range l.chain(user, "") {
		if sh.path == dir || slices.Contains(sh.inherits, filepath.Base(dir)) {
			return true
		}
		// Only a neighbor's relative links reach dir: Papirus-Dark holds its larger sizes as links into Papirus.
		if filepath.Dir(sh.path) != filepath.Dir(dir) {
			continue
		}
		seen, linked := 0, false
		_ = filepath.WalkDir(sh.path, func(path string, entry fs.DirEntry, err error) error {
			// A tree that cannot be read to its end is taken to need it.
			if seen++; err != nil || seen > maxInstallEntries {
				linked = true
				return fs.SkipAll
			}
			if entry.Type() != fs.ModeSymlink {
				return nil
			}
			target, _ := os.Readlink(path)
			if !filepath.IsAbs(target) {
				target = filepath.Join(filepath.Dir(path), target)
			}
			if target == dir || strings.HasPrefix(target, dir+string(filepath.Separator)) {
				linked = true
				return fs.SkipAll
			}
			return nil
		})
		if linked {
			return true
		}
	}
	return false
}

// RemoveTheme deletes a theme from the user's icon directory, unless a theme in inUse draws from it.
func RemoveTheme(o Options, name string, inUse []string) error {
	return removePack(o, name, inUse, func(dir string) bool { return readShelf(dir) != nil })
}

// RemoveCursor deletes a cursor theme from the user's icon directory, unless a theme in inUse draws from it.
func RemoveCursor(o Options, name string, inUse []string) error {
	return removePack(o, name, inUse, hasCursors)
}

func removePack(o Options, name string, inUse []string, match func(string) bool) error {
	lib := o.library()
	dir := filepath.Join(o.IconsDir, name)
	if name != filepath.Base(name) || reserved(name) || !match(dir) {
		return &LibraryError{Code: CodeNotRemovable, Reason: "not a theme in " + o.IconsDir}
	}

	type user struct{ label, theme string }
	var using []user
	for _, name := range inUse {
		using = append(using, user{name, name})
	}
	// The generation in use inherits other packs: an overlay its base, the self-built pack whatever it was told.
	if state := ReadState(o.StateDir); state.Applied != "" {
		using = append(using, user{state.Base, state.Applied})
	}
	var users []string
	for _, u := range using {
		if slices.Contains(users, u.label) {
			continue
		}
		if u.theme == name {
			users = append(users, u.label)
			continue
		}
		sh := lib.shelf(u.theme)
		if sh == nil && u.theme != "" && u.theme == filepath.Base(u.theme) {
			if candidate := filepath.Join(o.IconsDir, u.theme); hasCursors(candidate) {
				sh = &shelf{path: candidate}
			}
		}
		if sh != nil && lib.needs(sh, dir) {
			users = append(users, u.label)
		}
	}
	if len(users) > 0 {
		return &LibraryError{Code: CodeInUse, Themes: users, Reason: name + " is in use"}
	}
	return o.remove(name)
}
