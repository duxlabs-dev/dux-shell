package iconfolders

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/klauspost/compress/zstd"
)

// An archive is untrusted: these stop one that expands without end. Variables so a test can lower them.
var (
	maxInstallEntries = 500_000
	maxInstallBytes   = int64(2 << 30)
)

const (
	stagePrefix = ".dms-install-"
	// No install runs this long; an older staging directory was left by one that died.
	stageMaxAge = time.Hour
)

// reserved names are never listed, installed or removed: generations, hidden entries and the shared fallbacks.
func reserved(name string) bool {
	switch name {
	case "", "hicolor", "default", "locolor":
		return true
	}
	return strings.HasPrefix(name, ".") || overlayName.MatchString(name)
}

// stager writes untrusted entries below root: never over another entry and never through a link.
type stager struct {
	root    string
	dirs    map[string]bool
	entries int
	bytes   int64
}

func (s *stager) count() error {
	if s.entries++; s.entries > maxInstallEntries {
		return errors.New("too many files")
	}
	return nil
}

// path maps an entry name to its place below root; a name that cleans to "." is root itself.
func (s *stager) path(name string) (string, error) {
	name = filepath.Clean(name)
	if !filepath.IsLocal(name) {
		return "", fmt.Errorf("%q is outside the archive", name)
	}
	return filepath.Join(s.root, name), nil
}

// For root itself mkdirs refuses: its parent is outside.
func (s *stager) place(name string) (string, error) {
	dst, err := s.path(name)
	if err == nil {
		err = s.count()
	}
	if err == nil {
		err = s.mkdirs(filepath.Dir(dst))
	}
	return dst, err
}

// mkdirs accepts real directories only; entries are never replaced, so a directory checked once stays one.
// Directories an archive only implies count as entries too.
func (s *stager) mkdirs(dir string) error {
	if dir == s.root || s.dirs[dir] {
		return nil
	}
	if !strings.HasPrefix(dir, s.root+string(filepath.Separator)) {
		return errors.New("outside the archive")
	}
	if err := s.mkdirs(filepath.Dir(dir)); err != nil {
		return err
	}
	if err := s.count(); err != nil {
		return err
	}
	if err := os.Mkdir(dir, 0o755); err != nil {
		if info, err := os.Lstat(dir); err != nil || !info.IsDir() {
			return fmt.Errorf("%q is not a folder", filepath.Base(dir))
		}
	}
	s.dirs[dir] = true
	return nil
}

// dir takes "./", the root entry of an archive made of a folder's contents.
func (s *stager) dir(name string) error {
	dst, err := s.path(name)
	if err != nil {
		return err
	}
	if dst == s.root || s.dirs[dst] {
		return s.count()
	}
	return s.mkdirs(dst)
}

// file drops the entry's mode: nothing installed is executable.
func (s *stager) file(name string, r io.Reader) error {
	dst, err := s.place(name)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return err
	}
	n, err := io.Copy(f, io.LimitReader(r, maxInstallBytes-s.bytes+1))
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if s.bytes += n; err == nil && s.bytes > maxInstallBytes {
		err = errors.New("too large")
	}
	return err
}

// link only records the target; checkLinks judges it once the whole tree is there.
func (s *stager) link(name, target string) error {
	dst, err := s.place(name)
	if err != nil {
		return err
	}
	return os.Symlink(target, dst)
}

// hardlink accepts only a file of this archive, reached through directories this extraction made:
// a link on the way could lead anywhere. Installed themes have hard links, as packagers link identical icons.
func (s *stager) hardlink(name, to string) error {
	dst, err := s.place(name)
	if err != nil {
		return err
	}
	src, err := s.path(to)
	if err == nil && filepath.Dir(src) != s.root && !s.dirs[filepath.Dir(src)] {
		err = errSkipped
	}
	if info, statErr := os.Lstat(src); err != nil || statErr != nil || !info.Mode().IsRegular() {
		return fmt.Errorf("%q links to %q, which is not a file of the archive", name, to)
	}
	return os.Link(src, dst)
}

func (s *stager) tar(r io.Reader) error {
	tr := tar.NewReader(r)
	for {
		h, err := tr.Next()
		switch {
		case err == io.EOF:
			return nil
		case err != nil:
			return err
		}
		switch h.Typeflag {
		case tar.TypeDir:
			err = s.dir(h.Name)
		case tar.TypeReg:
			err = s.file(h.Name, tr)
		case tar.TypeSymlink:
			err = s.link(h.Name, h.Linkname)
		case tar.TypeLink:
			err = s.hardlink(h.Name, h.Linkname)
		case tar.TypeXGlobalHeader:
		default:
			err = fmt.Errorf("%q is not a file, folder or link", h.Name)
		}
		if err != nil {
			return err
		}
	}
}

func (s *stager) zip(f *os.File, size int64) error {
	zr, err := zip.NewReader(f, size)
	if err != nil {
		return err
	}
	for _, entry := range zr.File {
		mode := entry.Mode()
		switch {
		case mode.IsDir():
			err = s.dir(entry.Name)
		case mode.IsRegular(), mode.Type() == fs.ModeSymlink:
			var r io.ReadCloser
			if r, err = entry.Open(); err != nil {
				return err
			}
			if mode.IsRegular() {
				err = s.file(entry.Name, r)
			} else if target, readErr := io.ReadAll(io.LimitReader(r, 4096)); readErr != nil {
				err = readErr
			} else {
				err = s.link(entry.Name, string(target))
			}
			r.Close()
		default:
			err = fmt.Errorf("%q is not a file, folder or link", entry.Name)
		}
		if err != nil {
			return err
		}
	}
	return nil
}

// tree copies the theme folder src; what is neither file, folder nor link is left behind.
func (s *stager) tree(src, as string) error {
	return filepath.WalkDir(src, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		name := filepath.Join(as, rel)
		switch {
		case entry.IsDir():
			return s.dir(name)
		case entry.Type().IsRegular():
			f, err := os.Open(path)
			if err != nil {
				return err
			}
			defer f.Close()
			return s.file(name, f)
		case entry.Type() == fs.ModeSymlink:
			target, err := os.Readlink(path)
			if err != nil {
				return err
			}
			return s.link(name, target)
		}
		return nil
	})
}

func (s *stager) unpack(src string) error {
	src, err := filepath.EvalSymlinks(src)
	if err != nil {
		return err
	}
	info, err := os.Stat(src)
	if err != nil {
		return err
	}
	if info.IsDir() {
		if hasIndex(src) {
			return s.tree(src, filepath.Base(src))
		}
		// Only theme folders are copied, never whatever else the picked folder holds.
		for _, name := range themeDirs(src) {
			if err := s.tree(filepath.Join(src, name), name); err != nil {
				return err
			}
		}
		return nil
	}

	f, err := os.Open(src)
	if err != nil {
		return err
	}
	defer f.Close()
	head := make([]byte, 6)
	n, _ := io.ReadFull(f, head)
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return err
	}

	var r io.Reader = f
	switch head = head[:n]; {
	case bytes.HasPrefix(head, []byte("PK")):
		return s.zip(f, info.Size())
	case bytes.HasPrefix(head, []byte{0x1f, 0x8b}):
		r, err = gzip.NewReader(f)
	case bytes.HasPrefix(head, []byte{0x28, 0xb5, 0x2f, 0xfd}):
		var zr *zstd.Decoder
		if zr, err = zstd.NewReader(f); err == nil {
			defer zr.Close()
			r = zr
		}
	case bytes.HasPrefix(head, []byte{0xfd, '7', 'z', 'X', 'Z', 0}):
		// Go has no xz reader. The system's one is handed the bytes on stdin and nothing else.
		ctx, cancel := context.WithCancel(context.Background())
		cmd := exec.CommandContext(ctx, "xz", "-dc", "--memlimit-decompress=512MiB")
		cmd.Stdin = f
		if r, err = cmd.StdoutPipe(); err == nil {
			err = cmd.Start()
		}
		if err == nil {
			defer func() { _ = cmd.Wait() }()
		}
		defer cancel()
	}
	if err != nil {
		return err
	}
	return s.tar(r)
}

func hasIndex(dir string) bool {
	info, err := os.Lstat(filepath.Join(dir, "index.theme"))
	return err == nil && info.Mode().IsRegular()
}

func themeDirs(dir string) []string {
	var names []string
	entries, _ := os.ReadDir(dir)
	for _, entry := range entries {
		if entry.IsDir() && !reserved(entry.Name()) && hasIndex(filepath.Join(dir, entry.Name())) {
			names = append(names, entry.Name())
		}
	}
	return names
}

// linkStays reports whether a link at rel, a path below the icon directory, resolves inside one of its themes.
// Climbing is allowed only at the start: "a/.." after a link named a would leave by a path the text does not show.
func linkStays(rel, target string) bool {
	if filepath.IsAbs(target) {
		return false
	}
	climbing := true
	for part := range strings.SplitSeq(target, "/") {
		switch part {
		case "", ".":
		case "..":
			if !climbing {
				return false
			}
		default:
			climbing = false
		}
	}
	// A sibling theme is allowed: Papirus-Dark holds its larger sizes as links into Papirus.
	to := filepath.Join(filepath.Dir(rel), target)
	return to != "." && filepath.IsLocal(to)
}

func checkLinks(root, name string) error {
	return filepath.WalkDir(filepath.Join(root, name), func(path string, entry fs.DirEntry, err error) error {
		if err != nil || entry.Type() != fs.ModeSymlink {
			return err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		if target, err := os.Readlink(path); err != nil || !linkStays(rel, target) {
			return fmt.Errorf("the link %q leaves the theme", rel)
		}
		return nil
	})
}

// discard deletes a tree even where a read-only directory refuses the first try.
func discard(dir string) {
	if os.RemoveAll(dir) == nil {
		return
	}
	_ = filepath.WalkDir(dir, func(path string, entry fs.DirEntry, err error) error {
		if err == nil && entry.IsDir() {
			_ = os.Chmod(path, 0o700)
		}
		return nil
	})
	os.RemoveAll(dir)
}

// InstallTheme copies the themes in src, an archive or a folder, into the user's icon directory.
// Nothing from src is run, and a theme already there is replaced only when asked.
func InstallTheme(o Options, src string, replace bool) ([]string, error) {
	o.defaults()
	if err := os.MkdirAll(o.IconsDir, 0o755); err != nil {
		return nil, err
	}
	// A crashed install leaves its staging directory behind; a young one may be another install at work.
	entries, _ := os.ReadDir(o.IconsDir)
	for _, entry := range entries {
		if info, err := entry.Info(); err == nil && strings.HasPrefix(entry.Name(), stagePrefix) && time.Since(info.ModTime()) > stageMaxAge {
			discard(filepath.Join(o.IconsDir, entry.Name()))
		}
	}
	// Staged beside its destination, so the install is a rename. Replaced themes leave through it too.
	stage, err := os.MkdirTemp(o.IconsDir, stagePrefix)
	if err != nil {
		return nil, err
	}
	defer discard(stage)
	fresh, old := filepath.Join(stage, "new"), filepath.Join(stage, "old")
	if err := errors.Join(os.Mkdir(fresh, 0o755), os.Mkdir(old, 0o755)); err != nil {
		return nil, err
	}
	// The staging path means nothing to the user reading the reason.
	bad := func(err error) error {
		return &LibraryError{Code: CodeBadSource, Reason: strings.ReplaceAll(err.Error(), fresh+string(filepath.Separator), "")}
	}

	s := &stager{root: fresh, dirs: map[string]bool{}}
	if err := s.unpack(src); err != nil {
		return nil, bad(err)
	}
	root, names := fresh, themeDirs(fresh)
	// Release archives wrap their themes in one folder. A link in its place could name any directory.
	if entries, _ := os.ReadDir(fresh); len(names) == 0 && len(entries) == 1 && entries[0].IsDir() {
		root = filepath.Join(fresh, entries[0].Name())
		names = themeDirs(root)
	}
	if len(names) == 0 {
		return nil, &LibraryError{Code: CodeNoTheme, Reason: "no icon theme found"}
	}

	var taken []string
	for _, name := range names {
		if err := checkLinks(root, name); err != nil {
			return nil, bad(err)
		}
		if _, err := os.Lstat(filepath.Join(o.IconsDir, name)); err == nil {
			taken = append(taken, name)
		}
	}
	if len(taken) > 0 && !replace {
		return nil, &LibraryError{Code: CodeExists, Themes: taken, Reason: "already installed"}
	}
	for _, name := range names {
		target, aside := filepath.Join(o.IconsDir, name), filepath.Join(old, name)
		// The old theme is deleted with the staging directory, after the new one is in place.
		if err := os.Rename(target, aside); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return nil, err
		}
		if err := os.Rename(filepath.Join(root, name), target); err != nil {
			os.Rename(aside, target)
			return nil, err
		}
	}
	return names, nil
}
