package backup

import (
	"archive/tar"
	"compress/gzip"
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestSnapshotRestoresThroughSymlinkedConfig(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(home, ".local", "state"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(home, ".cache"))

	dotfiles := filepath.Join(home, "dotfiles", "dms")
	writeFile(t, filepath.Join(dotfiles, "settings.json"), `{"configVersion":17}`)
	if err := os.MkdirAll(filepath.Join(home, ".config"), 0o755); err != nil {
		t.Fatal(err)
	}
	configLink := filepath.Join(home, ".config", "dms")
	if err := os.Symlink(dotfiles, configLink); err != nil {
		t.Fatal(err)
	}
	session := filepath.Join(home, ".local", "state", "dms", "session.json")
	writeFile(t, session, `{"wallpaper":"a"}`)

	path, err := Snapshot("stable")
	if err != nil || path == "" {
		t.Fatalf("Snapshot = %q, %v", path, err)
	}

	writeFile(t, filepath.Join(dotfiles, "settings.json"), `{"configVersion":42}`)
	writeFile(t, session, `{"wallpaper":"b"}`)

	if err := RestoreSnapshot(path); err != nil {
		t.Fatal(err)
	}
	if got := readFile(t, filepath.Join(dotfiles, "settings.json")); got != `{"configVersion":17}` {
		t.Fatalf("settings = %s, want the snapshot's", got)
	}
	if got := readFile(t, session); got != `{"wallpaper":"a"}` {
		t.Fatalf("session = %s, want the snapshot's", got)
	}
	if info, err := os.Lstat(configLink); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Fatal("restore replaced the dotfiles symlink")
	}
}

func TestSnapshotKeepsNewestPerLabel(t *testing.T) {
	home := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(home, ".local", "state"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(home, ".cache"))
	writeFile(t, filepath.Join(home, ".config", "dms", "settings.json"), "{}")

	dir, _ := SnapshotDir()
	for _, stamp := range []string{"20260101-000000", "20260102-000000", "20260103-000000"} {
		writeFile(t, filepath.Join(dir, "stable-"+stamp+".tar.gz"), "")
	}
	writeFile(t, filepath.Join(dir, "beta-20250101-000000.tar.gz"), "")

	newest, err := Snapshot("stable")
	if err != nil {
		t.Fatal(err)
	}
	if got := listSnapshots("stable"); len(got) != snapshotsKept || got[len(got)-1] != newest {
		t.Fatalf("stable snapshots = %v, want the %d newest ending in %s", got, snapshotsKept, newest)
	}
	if got := listSnapshots("beta"); len(got) != 1 {
		t.Fatalf("pruning stable removed beta snapshots: %v", got)
	}
}

func TestRestoreSnapshotRejectsForeignEntries(t *testing.T) {
	home := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(home, ".local", "state"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(home, ".cache"))
	writeFile(t, filepath.Join(home, ".config", "dms", "settings.json"), "{}")

	archive := filepath.Join(home, "backup.tar.gz")
	if err := Create(archive); err != nil {
		t.Fatal(err)
	}
	// A plain backup lacks the config/ prefix, so its entries fall outside the snapshot roots.
	if err := RestoreSnapshot(archive); err == nil {
		t.Fatal("RestoreSnapshot accepted entries outside the snapshot roots")
	}
}

func TestRestoreSnapshotRejectsEscapingSymlink(t *testing.T) {
	home := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(home, ".local", "state"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(home, ".cache"))

	archive := filepath.Join(home, "evil.tar.gz")
	f, err := os.Create(archive)
	if err != nil {
		t.Fatal(err)
	}
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	if err := tw.WriteHeader(&tar.Header{Name: "config/dms/plugins", Typeflag: tar.TypeSymlink, Linkname: "../../../.ssh", Mode: 0o777}); err != nil {
		t.Fatal(err)
	}
	for _, c := range []interface{ Close() error }{tw, gz, f} {
		if err := c.Close(); err != nil {
			t.Fatal(err)
		}
	}

	if err := RestoreSnapshot(archive); err == nil {
		t.Fatal("RestoreSnapshot followed a symlink that points outside the config dir")
	}
	if _, err := os.Lstat(filepath.Join(home, ".config", "dms", "plugins")); err == nil {
		t.Fatal("the escaping symlink was created")
	}
}
