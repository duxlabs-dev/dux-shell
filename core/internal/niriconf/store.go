package niriconf

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

var ErrChanged = errors.New("fragment changed on disk")

const reloadWait = 3 * time.Second

// Store owns every write to ConfigDir/dms/<name>.
// Events nil skips the reload watch.
type Store struct {
	ConfigDir string
	Keep      int
	Events    Events

	mu sync.Mutex
}

type Version struct {
	N    int
	Time time.Time
	Hash string
	// Failed marks an attempt niri could not load; the file was rolled back.
	Failed bool
}

// PageHash covers the extra fragments too, so a hand edit of any of them gives ErrChanged.
// An empty extra adds nothing, as a missing fragment reads empty.
func PageHash(content string, extra []Fragment) string {
	h := sha256.New()
	h.Write([]byte(content))
	for _, f := range extra {
		if f.Content != "" {
			fmt.Fprintf(h, "\x00%s\x00%d\x00%s", f.Name, len(f.Content), f.Content)
		}
	}
	return hex.EncodeToString(h.Sum(nil))
}

func (s *Store) path(name string) string {
	return filepath.Join(s.ConfigDir, "dms", name)
}

// Read returns the PageHash of name and the extra fragments.
func (s *Store) Read(name string, extra ...string) (content, hash string, err error) {
	if !validName(name) {
		return "", "", ErrBadName
	}
	current := make([]Fragment, len(extra))
	for i, f := range extra {
		if !validName(f) {
			return "", "", ErrBadName
		}
		current[i].Name = f
		if current[i].Content, err = s.read(f); err != nil {
			return "", "", err
		}
	}
	content, err = s.read(name)
	if err != nil {
		return "", "", err
	}
	return content, PageHash(content, current), nil
}

func (s *Store) read(name string) (string, error) {
	data, err := os.ReadFile(s.path(name))
	if errors.Is(err, fs.ErrNotExist) {
		return "", nil
	}
	return string(data), err
}

// Fragment is another file of ConfigDir/dms written by the same Apply.
type Fragment struct{ Name, Content string }

// Apply validates name and extra together: a refusal writes none of them.
// baseHash is the PageHash of name and extra as Read returned them.
func (s *Store) Apply(name, content, baseHash string, extra ...Fragment) (Version, error) {
	if !validName(name) {
		return Version{}, ErrBadName
	}
	for _, f := range extra {
		if !validName(f.Name) || f.Name == name {
			return Version{}, ErrBadName
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.apply(name, content, baseHash, extra)
}

type change struct {
	name, old, content string
	v                  Version
}

func (s *Store) apply(name, content, baseHash string, extra []Fragment) (Version, error) {
	files, changes, err := s.prepare(name, content, baseHash, extra)
	if err != nil {
		return Version{}, err
	}
	if err := validateFiles(s.ConfigDir, files); err != nil {
		return Version{}, err
	}

	waiter := s.subscribe()
	if waiter != nil {
		defer waiter.Close()
	}
	// The include stays on a failed reload: it is optional and niri validated it.
	if config, ok := files["config.kdl"]; ok {
		if err := WriteAtomic(filepath.Join(s.ConfigDir, "config.kdl"), config); err != nil {
			return Version{}, err
		}
	}
	for i := range changes {
		if err := s.commit(&changes[i]); err != nil {
			return Version{}, errors.Join(err, s.rollback(changes[:i]))
		}
	}
	main := &changes[len(changes)-1]
	if waiter == nil || !reloadFailed(waiter) {
		return main.v, nil
	}
	if err := s.rollback(changes); err != nil {
		return main.v, errors.Join(ErrReloadFailed, err)
	}
	return main.v, ErrReloadFailed
}

// prepare checks baseHash and lists the files to validate, config.kdl when it lacks the include.
func (s *Store) prepare(name, content, baseHash string, extra []Fragment) (map[string][]byte, []change, error) {
	current, err := s.read(name)
	if err != nil {
		return nil, nil, err
	}
	files := map[string][]byte{filepath.Join("dms", name): []byte(content)}
	var changes []change
	olds := make([]Fragment, len(extra))
	for i, f := range extra {
		old, err := s.read(f.Name)
		if err != nil {
			return nil, nil, err
		}
		olds[i] = Fragment{Name: f.Name, Content: old}
		files[filepath.Join("dms", f.Name)] = []byte(f.Content)
		if old != f.Content {
			changes = append(changes, change{name: f.Name, old: old, content: f.Content})
		}
	}
	if PageHash(current, olds) != baseHash {
		return nil, nil, ErrChanged
	}
	config, err := withInclude(s.ConfigDir, name)
	if err != nil {
		return nil, nil, err
	}
	if config != nil {
		files["config.kdl"] = config
	}
	return files, append(changes, change{name: name, old: current, content: content}), nil
}

// commit records c.content as a new version, after a hand edit it would overwrite.
func (s *Store) commit(c *change) error {
	versions, err := s.history(c.name)
	if err != nil {
		return err
	}
	next := 1
	if len(versions) > 0 {
		next = versions[0].N + 1
	}
	if handEdited(c.old, versions) {
		kept := Version{N: next, Hash: PageHash(c.old, nil)}
		if err := WriteAtomic(s.entryPath(c.name, kept), []byte(c.old)); err != nil {
			return err
		}
		versions = append([]Version{kept}, versions...)
		next++
	}
	v := Version{N: next, Hash: PageHash(c.content, nil)}
	entry := s.entryPath(c.name, v)
	if err := WriteAtomic(entry, []byte(c.content)); err != nil {
		return err
	}
	info, err := os.Stat(entry)
	if err != nil {
		os.Remove(entry)
		return err
	}
	v.Time = info.ModTime()
	if err := WriteAtomic(s.path(c.name), []byte(c.content)); err != nil {
		os.Remove(entry)
		return err
	}
	s.prune(c.name, append([]Version{v}, versions...))
	c.v = v
	return nil
}

// rollback skips validation: niri loaded the old contents before.
func (s *Store) rollback(changes []change) error {
	var errs []error
	for i := range changes {
		c := &changes[i]
		if err := WriteAtomic(s.path(c.name), []byte(c.old)); err != nil {
			errs = append(errs, err)
			continue
		}
		failed := c.v
		failed.Failed = true
		if err := os.Rename(s.entryPath(c.name, c.v), s.entryPath(c.name, failed)); err != nil {
			log.Warnf("niriconf: mark failed version %d of %s: %v", c.v.N, c.name, errors.Unwrap(err))
		}
		c.v = failed
	}
	return errors.Join(errs...)
}

// subscribe returns nil without a watch: niri not running cannot fail a reload.
func (s *Store) subscribe() Waiter {
	if s.Events == nil {
		return nil
	}
	waiter, err := s.Events.Subscribe()
	if err != nil {
		log.Warnf("niriconf: no reload watch: %v", err)
		return nil
	}
	return waiter
}

// reloadFailed treats a timeout as success: niri does not reload when the merged
// config is unchanged. A broken stream keeps the content too, since niri validated
// it already and rolling back on a socket hiccup would undo a good write.
func reloadFailed(waiter Waiter) bool {
	failed, err := waiter.Wait(reloadWait)
	if err != nil && !errors.Is(err, os.ErrDeadlineExceeded) {
		log.Warnf("niriconf: reload watch: %v", err)
	}
	return err == nil && failed
}
