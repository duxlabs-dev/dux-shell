package iconfolders

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"syscall"

	"github.com/duxlabs-dev/dux-go/paths"
)

// Only these contexts hold folder art; an app icon reusing the folder keeps the pack's drawing.
var folderContexts = map[string]bool{"places": true, "mimetypes": true, "status": true}

// Icons here are a few KB; anything larger is not one.
const maxIconBytes = 1 << 20

var errSkipped = errors.New("not a plain icon file of this theme")

// A variable so a test can see that nothing but a regular file is ever opened.
var openFile = os.OpenFile

var directoryKeys = []string{"Context", "Size", "Scale", "Type", "MinSize", "MaxSize", "Threshold"}

type themeDir struct {
	rel     string
	scaled  bool
	context string
	keys    map[string]string
}

type theme struct {
	name string
	path string
	// stamp changes when the installed pack moves or is updated.
	stamp  string
	follow string
	dirs   []themeDir
}

func DefaultIconsDir() string {
	return filepath.Join(paths.XDGDataHome(), "icons")
}

func DefaultBaseDirs() []string {
	dirs := []string{DefaultIconsDir()}
	if home, err := os.UserHomeDir(); err == nil {
		dirs = []string{filepath.Join(home, ".icons"), DefaultIconsDir()}
	}
	for _, dir := range paths.XDGDataDirs() {
		dirs = append(dirs, filepath.Join(dir, "icons"))
	}
	return dirs
}

func locateTheme(baseDirs []string, name string) (*theme, error) {
	if name == "" || name != filepath.Base(name) {
		return nil, fs.ErrNotExist
	}
	for _, base := range baseDirs {
		dir := filepath.Join(base, name)
		index := filepath.Join(dir, "index.theme")
		info, err := os.Stat(index)
		if err != nil {
			continue
		}
		real, err := filepath.EvalSymlinks(index)
		if err != nil {
			continue
		}
		data, err := readPlain(real)
		if err != nil {
			continue
		}
		th := parseIndex(data)
		th.name, th.path = name, dir
		resolved, err := filepath.EvalSymlinks(dir)
		if err != nil {
			resolved = dir
		}
		th.stamp = fmt.Sprintf("%s:%d:%d", resolved, info.ModTime().UnixNano(), info.Size())
		// Packages keep index.theme's mtime across updates; the icon cache bumps the directory instead.
		if top, err := os.Stat(dir); err == nil {
			th.stamp += fmt.Sprintf(":%d", top.ModTime().UnixNano())
		}
		return th, nil
	}
	return nil, fs.ErrNotExist
}

func parseIndex(data []byte) *theme {
	sections := map[string]map[string]string{}
	var current map[string]string
	sc := bufio.NewScanner(bytes.NewReader(data))
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		switch {
		case line == "" || line[0] == '#':
			continue
		case line[0] == '[' && line[len(line)-1] == ']':
			current = map[string]string{}
			sections[line[1:len(line)-1]] = current
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok || current == nil {
			continue
		}
		current[strings.TrimSpace(key)] = strings.TrimSpace(value)
	}

	head := sections["Icon Theme"]
	th := &theme{follow: head["FollowsColorScheme"]}
	seen := map[string]bool{}
	for _, list := range []struct {
		key    string
		scaled bool
	}{{"Directories", false}, {"ScaledDirectories", true}} {
		for rel := range strings.SplitSeq(head[list.key], ",") {
			rel = path.Clean(strings.TrimSpace(rel))
			// A theme is untrusted input; its directories must stay inside the overlay.
			if rel == "." || seen[rel] || !filepath.IsLocal(rel) {
				continue
			}
			seen[rel] = true
			keys := sections[rel]
			th.dirs = append(th.dirs, themeDir{
				rel:     rel,
				scaled:  list.scaled,
				context: strings.ToLower(keys["Context"]),
				keys:    keys,
			})
		}
	}
	return th
}

// scan holds a theme's icon files per directory, each name mapped to its symlink target or "".
type scan struct {
	theme *theme
	dirs  []string
	// Directories that are the same place on disk (16x16@2x -> 16x16) are read once.
	alias   map[string]string
	files   map[string]map[string]string
	context map[string]string
	names   map[string]bool
	// roots are the only places file contents may come from; a pack may symlink anywhere readable.
	roots []string
}

func scanTheme(th *theme, baseDirs []string) *scan {
	s := &scan{
		theme:   th,
		alias:   map[string]string{},
		files:   map[string]map[string]string{},
		context: map[string]string{},
		names:   map[string]bool{},
	}
	if root, err := filepath.EvalSymlinks(th.path); err == nil {
		s.roots = append(s.roots, root)
	}
	var iconDirs []string
	for _, dir := range baseDirs {
		if real, err := filepath.EvalSymlinks(dir); err == nil {
			iconDirs = append(iconDirs, real)
		}
	}

	byReal := map[string]string{}
	for _, dir := range th.dirs {
		full := filepath.Join(th.path, dir.rel)
		real, err := filepath.EvalSymlinks(full)
		if err != nil {
			continue
		}
		if first, ok := byReal[real]; ok {
			s.alias[dir.rel] = first
			continue
		}
		if !s.owns(real) {
			// Papirus-Dark links its larger sizes into Papirus; a sibling theme a pack links to is part of it.
			sibling, ok := themeRoot(iconDirs, real)
			if !ok {
				continue
			}
			s.roots = append(s.roots, sibling)
		}
		entries, err := os.ReadDir(real)
		if err != nil {
			continue
		}
		byReal[real] = dir.rel
		files := make(map[string]string, len(entries))
		for _, entry := range entries {
			name := entry.Name()
			if !isIcon(name) {
				continue
			}
			switch {
			case entry.Type().IsRegular():
				files[name] = ""
			case entry.Type()&fs.ModeSymlink != 0:
				target, err := os.Readlink(filepath.Join(real, name))
				if err != nil || target == "" {
					continue
				}
				files[name] = target
			default:
				continue
			}
			s.names[iconName(name)] = true
		}
		s.dirs = append(s.dirs, dir.rel)
		s.files[dir.rel] = files
		s.context[dir.rel] = dir.context
	}
	return s
}

func (s *scan) owns(real string) bool {
	return slices.ContainsFunc(s.roots, func(root string) bool {
		return real == root || strings.HasPrefix(real, root+string(filepath.Separator))
	})
}

func themeRoot(iconDirs []string, real string) (string, bool) {
	for _, dir := range iconDirs {
		rel, err := filepath.Rel(dir, real)
		if err != nil || rel == "." || !filepath.IsLocal(rel) {
			continue
		}
		name, _, _ := strings.Cut(rel, string(filepath.Separator))
		return filepath.Join(dir, name), true
	}
	return "", false
}

type fileKey struct{ dir, name string }

func (s *scan) follow(from fileKey, target string) (fileKey, bool) {
	if path.IsAbs(target) {
		return fileKey{}, false
	}
	dir, name := path.Split(path.Join(from.dir, target))
	dir = path.Clean(dir)
	if canonical, ok := s.alias[dir]; ok {
		dir = canonical
	}
	if _, ok := s.files[dir][name]; !ok {
		return fileKey{}, false
	}
	return fileKey{dir, name}, true
}

func (s *scan) resolve(key fileKey) (fileKey, bool) {
	for range 16 {
		target, ok := s.files[key.dir][key.name]
		if !ok {
			return fileKey{}, false
		}
		if target == "" {
			return key, true
		}
		if key, ok = s.follow(key, target); !ok {
			return fileKey{}, false
		}
	}
	return fileKey{}, false
}

// linkWithin keeps key's symlink only when the tree being written also holds its target.
func (s *scan) linkWithin(key fileKey, holds func(fileKey) bool) (string, bool) {
	target := s.files[key.dir][key.name]
	if target == "" {
		return "", false
	}
	next, ok := s.follow(key, target)
	if !ok || !holds(next) {
		return "", false
	}
	return target, true
}

func (s *scan) read(key fileKey) ([]byte, error) {
	real, err := filepath.EvalSymlinks(filepath.Join(s.theme.path, key.dir, key.name))
	if err != nil || !s.owns(real) {
		return nil, errSkipped
	}
	return readPlain(real)
}

// readPlain never opens anything but a regular file: a FIFO would block under the theme run lock.
func readPlain(path string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() {
		return nil, errSkipped
	}
	// Non-blocking and no-follow in case the file was swapped since the check.
	f, err := openFile(path, os.O_RDONLY|syscall.O_NONBLOCK|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return nil, errSkipped
	}
	defer f.Close()
	if info, err := f.Stat(); err != nil || !info.Mode().IsRegular() {
		return nil, errSkipped
	}
	data, err := io.ReadAll(io.LimitReader(f, maxIconBytes+1))
	if err != nil {
		return nil, err
	}
	if len(data) > maxIconBytes {
		return nil, errSkipped
	}
	return data, nil
}

func iconName(file string) string {
	return strings.TrimSuffix(file, path.Ext(file))
}

func isSVG(file string) bool {
	return strings.EqualFold(path.Ext(file), ".svg")
}

func isIcon(file string) bool {
	switch strings.ToLower(path.Ext(file)) {
	case ".svg", ".png", ".xpm":
		return true
	}
	return false
}
