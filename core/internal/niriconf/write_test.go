package niriconf

import (
	"os"
	"path/filepath"
	"testing"
)

func readFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestWriteAtomicReplacesContent(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "niri.kdl")

	for _, content := range []string{"a", "b"} {
		if err := WriteAtomic(path, []byte(content)); err != nil {
			t.Fatal(err)
		}
	}

	if got := readFile(t, path); got != "b" {
		t.Fatalf("content = %q, want %q", got, "b")
	}
	leftovers, err := filepath.Glob(filepath.Join(dir, "*.tmp*"))
	if err != nil {
		t.Fatal(err)
	}
	if len(leftovers) != 0 {
		t.Fatalf("temp files left: %v", leftovers)
	}
}

func TestWriteAtomicFollowsSymlink(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "real", "target.kdl")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "link")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}

	if err := WriteAtomic(link, []byte("new")); err != nil {
		t.Fatal(err)
	}

	info, err := os.Lstat(link)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("link was replaced by a regular file")
	}
	if got := readFile(t, target); got != "new" {
		t.Fatalf("target content = %q, want %q", got, "new")
	}
}

func TestWriteAtomicKeepsMode(t *testing.T) {
	dir := t.TempDir()
	existing := filepath.Join(dir, "existing.kdl")
	if err := os.WriteFile(existing, []byte("old"), 0o600); err != nil {
		t.Fatal(err)
	}
	fresh := filepath.Join(dir, "sub", "fresh.kdl")

	cases := []struct {
		path string
		want os.FileMode
	}{
		{existing, 0o600},
		{fresh, 0o644},
	}
	for _, c := range cases {
		if err := WriteAtomic(c.path, []byte("x")); err != nil {
			t.Fatal(err)
		}
		info, err := os.Stat(c.path)
		if err != nil {
			t.Fatal(err)
		}
		if got := info.Mode().Perm(); got != c.want {
			t.Fatalf("%s mode = %o, want %o", filepath.Base(c.path), got, c.want)
		}
	}
}
