package niriconf

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
)

const defaultKeep = 20

var historyPattern = regexp.MustCompile(`^([0-9]+)(\.failed)?\.kdl$`)

func (s *Store) historyDir(name string) string {
	return filepath.Join(s.ConfigDir, "dms", ".history", name)
}

func (s *Store) entryPath(name string, v Version) string {
	file := strconv.Itoa(v.N) + ".kdl"
	if v.Failed {
		file = strconv.Itoa(v.N) + ".failed.kdl"
	}
	return filepath.Join(s.historyDir(name), file)
}

func (s *Store) prune(name string, versions []Version) {
	keep := s.Keep
	if keep <= 0 {
		keep = defaultKeep
	}
	for _, old := range versions[min(keep, len(versions)):] {
		os.Remove(s.entryPath(name, old))
	}
}

// handEdited compares with the newest loaded version: a failed one was rolled back.
func handEdited(current string, versions []Version) bool {
	if current == "" {
		return false
	}
	for _, v := range versions {
		if !v.Failed {
			return v.Hash != PageHash(current, nil)
		}
	}
	return true
}

func (s *Store) History(name string) ([]Version, error) {
	if !validName(name) {
		return nil, ErrBadName
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.history(name)
}

func (s *Store) history(name string) ([]Version, error) {
	dir := s.historyDir(name)
	entries, err := os.ReadDir(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var versions []Version
	for _, e := range entries {
		m := historyPattern.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		n, err := strconv.Atoi(m[1])
		if err != nil {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			return nil, err
		}
		info, err := e.Info()
		if err != nil {
			return nil, err
		}
		versions = append(versions, Version{N: n, Time: info.ModTime(), Hash: PageHash(string(data), nil), Failed: m[2] != ""})
	}
	slices.SortFunc(versions, func(a, b Version) int { return b.N - a.N })
	return versions, nil
}

func (s *Store) versionContent(name string, n int) (string, error) {
	data, err := os.ReadFile(s.entryPath(name, Version{N: n}))
	if errors.Is(err, fs.ErrNotExist) {
		data, err = os.ReadFile(s.entryPath(name, Version{N: n, Failed: true}))
	}
	return string(data), err
}

// Restore returns the PageHash of name and extra after the restore, read under the lock.
func (s *Store) Restore(name string, n int, extra ...string) (Version, string, error) {
	if !validName(name) {
		return Version{}, "", ErrBadName
	}
	for _, f := range extra {
		if !validName(f) {
			return Version{}, "", ErrBadName
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	content, err := s.versionContent(name, n)
	if err != nil {
		return Version{}, "", err
	}
	current, err := s.read(name)
	if err != nil {
		return Version{}, "", err
	}
	v, err := s.apply(name, content, PageHash(current, nil), nil)
	if err != nil {
		return v, "", err
	}
	_, hash, err := s.Read(name, extra...)
	return v, hash, err
}
