package niriconf

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// configEvents records config.kdl at Subscribe: the watch must start before the write.
type configEvents struct {
	path, seen string
	failed     bool
	onWait     func()
}

func (e *configEvents) Subscribe() (Waiter, error) {
	data, _ := os.ReadFile(e.path)
	e.seen = string(data)
	return e, nil
}

func (e *configEvents) Wait(time.Duration) (bool, error) {
	if e.onWait != nil {
		e.onWait()
	}
	return e.failed, nil
}
func (e *configEvents) Close() error { return nil }

func addAlttab(t *testing.T, mode os.FileMode, ev *configEvents) (dir string, err error) {
	t.Helper()
	dir = setupValidate(t, dmsInclude, "")
	config := filepath.Join(dir, "config.kdl")
	if err := os.Chmod(config, mode); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "dms", "alttab.kdl"), []byte("recent-windows { off; }\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	ev.path = config
	return dir, (&Store{ConfigDir: dir, Events: ev}).AddInclude("alttab.kdl")
}

func TestIncludeBackupLivesNextToConfig(t *testing.T) {
	dir, err := addAlttab(t, 0o600, &configEvents{})
	if err != nil {
		t.Fatal(err)
	}
	backup := filepath.Join(dir, "config.kdl.dms-bak")
	info, err := os.Stat(backup)
	if err != nil {
		t.Fatalf("backup next to config.kdl: %v", err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Errorf("backup mode = %o, want 600", got)
	}
	if data, _ := os.ReadFile(backup); string(data) != dmsInclude {
		t.Errorf("backup = %q, want the config before the include", data)
	}
	if _, err := os.Stat(filepath.Join(dir, "dms", ".history", ".include")); !os.IsNotExist(err) {
		t.Errorf("old backup folder still there: %v", err)
	}
}

// A fragment niri refuses leaves nothing behind: no include line, no backup for an Undo that could not exist.
func TestAddIncludeInvalidPosesNothing(t *testing.T) {
	dir := setupValidate(t, dmsInclude, "")
	if err := os.WriteFile(filepath.Join(dir, "dms", "bad.kdl"), []byte("BAD\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var inv *InvalidError
	if err := (&Store{ConfigDir: dir}).AddInclude("bad.kdl"); !errors.As(err, &inv) {
		t.Fatalf("err = %v, want *InvalidError", err)
	}
	if data, _ := os.ReadFile(filepath.Join(dir, "config.kdl")); string(data) != dmsInclude {
		t.Fatalf("config = %q, want %q", data, dmsInclude)
	}
	if _, err := os.Stat(filepath.Join(dir, "config.kdl.dms-bak")); !os.IsNotExist(err) {
		t.Fatalf("backup posed for a refused fragment: %v", err)
	}
}

// One copy, overwritten before each write: the second include refreshes it and undo takes back only the last write.
func TestIncludeBackupOverwrittenBeforeEachWrite(t *testing.T) {
	ev := &configEvents{}
	dir, err := addAlttab(t, 0o644, ev)
	if err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(filepath.Join(dir, "config.kdl"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "dms", "cursor.kdl"), []byte("xwayland { off; }\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := (&Store{ConfigDir: dir, Events: ev}).AddInclude("cursor.kdl"); err != nil {
		t.Fatal(err)
	}
	backup := filepath.Join(dir, "config.kdl.dms-bak")
	if data, _ := os.ReadFile(backup); string(data) != string(before) {
		t.Fatalf("backup = %q, want %q", data, before)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if e.Name() != "config.kdl" && e.Name() != "config.kdl.dms-bak" && e.Name() != "dms" {
			t.Errorf("unexpected copy next to config.kdl: %s", e.Name())
		}
	}
	if err := (&Store{ConfigDir: dir, Events: ev}).UndoInclude(); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(filepath.Join(dir, "config.kdl")); string(data) != string(before) {
		t.Fatalf("config after undo = %q, want %q", data, before)
	}
}

// An old backup gets its private mode before the new content lands; a read-only one shows the order.
func TestBackupModeFixedBeforeWrite(t *testing.T) {
	path := filepath.Join(t.TempDir(), "backup", "before.kdl")
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("old"), 0o444); err != nil {
		t.Fatal(err)
	}
	if err := writeBackup(path, []byte("new"), 0o600); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(path); string(data) != "new" || info.Mode().Perm() != 0o600 {
		t.Fatalf("backup = %q mode %o, want \"new\" mode 600", data, info.Mode().Perm())
	}
}

func TestFailedRestoreKeepsBackup(t *testing.T) {
	var configDir string
	ev := &configEvents{failed: true}
	// A read-only config folder makes the restore of config.kdl fail.
	ev.onWait = func() {
		configDir = filepath.Dir(ev.path)
		os.Chmod(configDir, 0o500)
	}
	dir, err := addAlttab(t, 0o644, ev)
	os.Chmod(configDir, 0o755)
	if !errors.Is(err, ErrReloadFailed) {
		t.Fatalf("err = %v, want %v", err, ErrReloadFailed)
	}
	before := filepath.Join(dir, "config.kdl.dms-bak")
	if data, rerr := os.ReadFile(before); rerr != nil || string(data) != dmsInclude {
		t.Fatalf("backup after a failed restore = %q, %v", data, rerr)
	}
}

func TestAddIncludeBackupUndoRestore(t *testing.T) {
	const base = dmsInclude
	const added = base + "include optional=true \"dms/alttab.kdl\"\n"
	for name, c := range map[string]struct {
		reloadFail  bool
		handEdit    string
		undo        bool
		wantAdd     error
		wantUndo    error
		wantConfig  string
		wantUndoNow bool
	}{
		"added, undo offered":        {wantConfig: added, wantUndoNow: true},
		"undo puts the backup back":  {undo: true, wantConfig: base},
		"reload failed, restored":    {reloadFail: true, wantAdd: ErrReloadFailed, wantConfig: base},
		"nothing to undo after fail": {reloadFail: true, wantAdd: ErrReloadFailed, undo: true, wantUndo: ErrNoUndo, wantConfig: base},
		"hand edit blocks the undo":  {handEdit: added + "// mine\n", undo: true, wantUndo: ErrChanged, wantConfig: added + "// mine\n"},
		"hand edit hides the undo":   {handEdit: added + "// mine\n", wantConfig: added + "// mine\n"},
	} {
		t.Run(name, func(t *testing.T) {
			dir := setupValidate(t, base, "")
			config := filepath.Join(dir, "config.kdl")
			if err := os.WriteFile(filepath.Join(dir, "dms", "alttab.kdl"), []byte("recent-windows { off; }\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			ev := &configEvents{path: config, failed: c.reloadFail}
			s := &Store{ConfigDir: dir, Events: ev}

			if err := s.AddInclude("alttab.kdl"); !errors.Is(err, c.wantAdd) {
				t.Fatalf("add: err = %v, want %v", err, c.wantAdd)
			}
			if ev.seen != base {
				t.Fatalf("watch started after the write: %q", ev.seen)
			}
			if c.handEdit != "" {
				if err := os.WriteFile(config, []byte(c.handEdit), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			if c.undo {
				if err := s.UndoInclude(); !errors.Is(err, c.wantUndo) {
					t.Fatalf("undo: err = %v, want %v", err, c.wantUndo)
				}
			}
			if data, _ := os.ReadFile(config); string(data) != c.wantConfig {
				t.Fatalf("config = %q, want %q", data, c.wantConfig)
			}
			if got := Doctor(dir, nil).Undo; got != c.wantUndoNow {
				t.Fatalf("report undo = %v, want %v", got, c.wantUndoNow)
			}
		})
	}
}
