package backup

import (
	"archive/tar"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

const snapshotsKept = 3

// snapshotRoot is one piece of user state a snapshot carries, archived under prefix/entry.
type snapshotRoot struct {
	prefix string
	parent func() (string, error)
	entry  string
}

var snapshotRoots = []snapshotRoot{
	{prefix: "config", parent: os.UserConfigDir, entry: dirName},
	{prefix: "state", parent: stateDir, entry: filepath.Join(dirName, "session.json")},
	{prefix: "cache", parent: os.UserCacheDir, entry: filepath.Join(dirName, "cache.json")},
}

func stateDir() (string, error) {
	if dir := os.Getenv("XDG_STATE_HOME"); dir != "" {
		return dir, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".local", "state"), nil
}

func SnapshotDir() (string, error) {
	dir, err := stateDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, dirName, "switch"), nil
}

// Snapshot archives settings, plugins, themes, session and cache state under label, keeping the
// newest few per label. It returns "" when there is no state to save.
func Snapshot(label string) (string, error) {
	dir, err := SnapshotDir()
	if err != nil {
		return "", err
	}

	type source struct{ path, name string }
	var sources []source
	for _, root := range snapshotRoots {
		parent, err := root.parent()
		if err != nil {
			return "", err
		}
		path := filepath.Join(parent, root.entry)
		if _, err := os.Stat(path); err != nil {
			continue
		}
		sources = append(sources, source{path, filepath.Join(root.prefix, root.entry)})
	}
	if len(sources) == 0 {
		return "", nil
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(dir, fmt.Sprintf("%s-%s.tar.gz", label, time.Now().Format("20060102-150405")))
	tmp := path + ".partial"
	err = writeArchive(tmp, func(tw *tar.Writer) error {
		for _, src := range sources {
			if err := addPath(tw, src.path, src.name); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		os.Remove(tmp)
		return "", err
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return "", err
	}

	pruneSnapshots(label)
	return path, nil
}

func LatestSnapshot(label string) (string, bool) {
	snapshots := listSnapshots(label)
	if len(snapshots) == 0 {
		return "", false
	}
	return snapshots[len(snapshots)-1], true
}

func listSnapshots(label string) []string {
	dir, err := SnapshotDir()
	if err != nil {
		return nil
	}
	matches, _ := filepath.Glob(filepath.Join(dir, label+"-*.tar.gz"))
	// The timestamp format sorts chronologically.
	slices.Sort(matches)
	return matches
}

func pruneSnapshots(label string) {
	snapshots := listSnapshots(label)
	for len(snapshots) > snapshotsKept {
		os.Remove(snapshots[0])
		snapshots = snapshots[1:]
	}
}

// RestoreSnapshot writes the snapshot's files over the current ones, through any symlinks, so
// dotfile-managed configs are updated in place. Files created since the snapshot are left alone;
// callers take a snapshot of the current state first.
func RestoreSnapshot(archivePath string) error {
	targets := make(map[string]string, len(snapshotRoots))
	for _, root := range snapshotRoots {
		parent, err := root.parent()
		if err != nil {
			return err
		}
		targets[root.prefix] = parent
	}

	targetFor := func(name string) (string, error) {
		if filepath.IsAbs(name) || strings.HasPrefix(name, "..") {
			return "", fmt.Errorf("unsafe path in snapshot: %s", name)
		}
		prefix, rest, _ := strings.Cut(filepath.ToSlash(name), "/")
		parent, ok := targets[prefix]
		if !ok || (rest != dirName && !strings.HasPrefix(rest, dirName+"/")) {
			return "", fmt.Errorf("not a DMS snapshot: unexpected entry %s", name)
		}
		return filepath.Join(parent, rest), nil
	}

	if err := walkArchive(archivePath, func(header *tar.Header, _ *tar.Reader) error {
		_, err := targetFor(filepath.Clean(header.Name))
		return err
	}); err != nil {
		return err
	}

	return walkArchive(archivePath, func(header *tar.Header, tr *tar.Reader) error {
		target, err := targetFor(filepath.Clean(header.Name))
		if err != nil {
			return err
		}

		switch header.Typeflag {
		case tar.TypeDir:
			return os.MkdirAll(target, 0o755)
		case tar.TypeSymlink:
			if filepath.IsAbs(header.Linkname) || slices.Contains(strings.Split(filepath.ToSlash(header.Linkname), "/"), "..") {
				return fmt.Errorf("unsafe symlink in snapshot: %s -> %s", header.Name, header.Linkname)
			}
			if _, err := os.Lstat(target); err == nil {
				return nil
			}
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			return os.Symlink(header.Linkname, target)
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			f, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, os.FileMode(header.Mode))
			if err != nil {
				return err
			}
			defer f.Close()
			_, err = io.Copy(f, tr)
			return err
		default:
			return nil
		}
	})
}
