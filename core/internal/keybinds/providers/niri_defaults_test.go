package providers

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/niriconf"
)

// stockBindsContent is the embedded stock with the terminal substituted,
// what dms setup writes into a fresh dms/binds.kdl.
var stockBindsContent = strings.ReplaceAll(config.NiriBindsConfig, "{{TERMINAL_COMMAND}}", "foot")

func fakeNiriValidate(t *testing.T) {
	t.Helper()
	fake, err := filepath.Abs("testdata/niri")
	if err != nil {
		t.Fatal(err)
	}
	old := niriconf.NiriBin
	niriconf.NiriBin = fake
	t.Cleanup(func() { niriconf.NiriBin = old })
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
}

const mergeTestConfig = `include optional=true "dms/binds.kdl"
binds {
    Mod+Q { quit; }
}
`

const mergeTestBinds = `binds {
    Mod+Shift+D hotkey-overlay-title="Perso" { spawn "sh" "-c" "perso script"; }
    Mod+Y { spawn "wallpapers"; }
}
`

// seedMergeDir writes a config.kdl that includes dms/binds.kdl and binds Mod+Q in it.
func seedMergeDir(t *testing.T) string {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "niri")
	if err := os.MkdirAll(filepath.Join(dir, "dms"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "config.kdl"), []byte(mergeTestConfig), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestMergeAddsOnlyMissingDefaults(t *testing.T) {
	fakeNiriValidate(t)
	dir := seedMergeDir(t)
	provider := NewNiriProvider(dir)
	if err := os.WriteFile(provider.GetOverridePath(), []byte(mergeTestBinds), 0o644); err != nil {
		t.Fatal(err)
	}

	added, err := provider.MergeMissingDefaults("foot")
	if err != nil {
		t.Fatalf("MergeMissingDefaults: %v", err)
	}

	addedKeys := map[string]bool{}
	for _, key := range added {
		addedKeys[key] = true
	}
	if !addedKeys["Mod+D"] {
		t.Fatalf("added = %v, want the dash default", added)
	}
	if addedKeys["Mod+Shift+D"] {
		t.Fatal("Mod+Shift+D is bound in binds.kdl: the default must not be added")
	}
	if addedKeys["Mod+Q"] {
		t.Fatal("Mod+Q is bound in config.kdl: the default must not be added")
	}

	written, err := os.ReadFile(provider.GetOverridePath())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(written), `spawn "dms" "ipc" "call" "dash" "toggle" ""`) {
		t.Fatalf("merged binds.kdl has no dash default:\n%s", written)
	}
	if strings.Count(string(written), "Mod+Q") != 0 {
		t.Fatalf("Mod+Q from config.kdl leaked into binds.kdl:\n%s", written)
	}
	// The personal lines and the file's own shape are kept.
	for _, line := range strings.Split(strings.TrimSuffix(mergeTestBinds, "\n"), "\n") {
		if !strings.Contains(string(written), line) {
			t.Fatalf("merged binds.kdl lost the line %q:\n%s", line, written)
		}
	}
	if n := strings.Count(string(written), "\n"); n < 4 {
		t.Fatalf("merged binds.kdl looks truncated:\n%s", written)
	}
	if !strings.Contains(string(written), `spawn "foot"`) {
		t.Fatalf("terminal command not substituted:\n%s", written)
	}

	backup, err := os.ReadFile(provider.bindsBackup())
	if err != nil {
		t.Fatalf("binds.kdl.dms-bak missing: %v", err)
	}
	if string(backup) != mergeTestBinds {
		t.Fatalf("backup = %q, want the pre-merge file", backup)
	}
}

func TestMergeBackupStaysPrivate(t *testing.T) {
	fakeNiriValidate(t)
	dir := seedMergeDir(t)
	provider := NewNiriProvider(dir)
	if err := os.WriteFile(provider.GetOverridePath(), []byte(mergeTestBinds), 0o644); err != nil {
		t.Fatal(err)
	}
	// A backup an older build left world-readable.
	if err := os.WriteFile(provider.bindsBackup(), []byte("stale"), 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := provider.MergeMissingDefaults("foot"); err != nil {
		t.Fatalf("MergeMissingDefaults: %v", err)
	}
	info, err := os.Stat(provider.bindsBackup())
	if err != nil {
		t.Fatal(err)
	}
	if mode := info.Mode().Perm(); mode != 0o600 {
		t.Fatalf("backup mode = %o, want 600", mode)
	}
}

func TestMergeCreatesMissingFile(t *testing.T) {
	fakeNiriValidate(t)
	dir := seedMergeDir(t)
	provider := NewNiriProvider(dir)

	added, err := provider.MergeMissingDefaults("foot")
	if err != nil {
		t.Fatalf("MergeMissingDefaults: %v", err)
	}
	if len(added) == 0 {
		t.Fatal("a missing binds.kdl must gain the whole stock")
	}

	written, err := os.ReadFile(provider.GetOverridePath())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(written), `spawn "dms" "ipc" "call" "dash" "toggle" ""`) {
		t.Fatalf("stock binds.kdl has no dash default:\n%s", written)
	}
	if _, err := os.Stat(provider.bindsBackup()); !os.IsNotExist(err) {
		t.Fatalf("no file existed: a backup must not be written, %v", err)
	}
}

func TestMergeNoWriteWhenNothingMissing(t *testing.T) {
	fakeNiriValidate(t)
	dir := seedMergeDir(t)
	provider := NewNiriProvider(dir)

	stock := strings.ReplaceAll(config.NiriBindsConfig, "{{TERMINAL_COMMAND}}", "foot")
	if err := os.MkdirAll(filepath.Join(dir, "dms"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(provider.GetOverridePath(), []byte(stock), 0o644); err != nil {
		t.Fatal(err)
	}

	added, err := provider.MergeMissingDefaults("foot")
	if err != nil {
		t.Fatalf("MergeMissingDefaults: %v", err)
	}
	if len(added) != 0 {
		t.Fatalf("added = %v, want nothing", added)
	}
	after, err := os.ReadFile(provider.GetOverridePath())
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != stock {
		t.Fatal("nothing was missing: binds.kdl must not be rewritten")
	}
	if _, err := os.Stat(provider.bindsBackup()); !os.IsNotExist(err) {
		t.Fatalf("nothing was missing: no backup, %v", err)
	}
}

func TestMergeRefusesWhenConfigInvalid(t *testing.T) {
	home := t.TempDir()
	bin := filepath.Join(home, "niri-invalid")
	script := "#!/bin/sh\necho broken\nexit 1\n"
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	old := niriconf.NiriBin
	niriconf.NiriBin = bin
	t.Cleanup(func() { niriconf.NiriBin = old })
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))

	dir := seedMergeDir(t)
	provider := NewNiriProvider(dir)
	if err := os.WriteFile(provider.GetOverridePath(), []byte(mergeTestBinds), 0o644); err != nil {
		t.Fatal(err)
	}

	_, err := provider.MergeMissingDefaults("foot")
	if err == nil || !strings.HasPrefix(err.Error(), "invalid config: ") {
		t.Fatalf("MergeMissingDefaults error = %v, want invalid config", err)
	}
	written, err := os.ReadFile(provider.GetOverridePath())
	if err != nil {
		t.Fatal(err)
	}
	if string(written) != mergeTestBinds {
		t.Fatal("an invalid merged config must not be written")
	}
	if _, err := os.Stat(provider.bindsBackup()); !os.IsNotExist(err) {
		t.Fatalf("a refused merge must not leave a backup, %v", err)
	}
}

func TestUndoRestoresPreMergeFile(t *testing.T) {
	fakeNiriValidate(t)
	dir := seedMergeDir(t)
	provider := NewNiriProvider(dir)
	if err := os.WriteFile(provider.GetOverridePath(), []byte(mergeTestBinds), 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := provider.MergeMissingDefaults("foot"); err != nil {
		t.Fatalf("MergeMissingDefaults: %v", err)
	}
	if err := provider.UndoMergeDefaults("foot"); err != nil {
		t.Fatalf("UndoMergeDefaults: %v", err)
	}
	written, err := os.ReadFile(provider.GetOverridePath())
	if err != nil {
		t.Fatal(err)
	}
	if string(written) != mergeTestBinds {
		t.Fatalf("undo left binds.kdl as %q", written)
	}
	if _, err := os.Stat(provider.bindsBackup()); !os.IsNotExist(err) {
		t.Fatalf("undo must drop the backup, %v", err)
	}
	if err := provider.UndoMergeDefaults("foot"); !errors.Is(err, niriconf.ErrNoUndo) {
		t.Fatalf("second undo error = %v, want ErrNoUndo", err)
	}
}

func TestUndoRefusesWhenFileChanged(t *testing.T) {
	fakeNiriValidate(t)
	dir := seedMergeDir(t)
	provider := NewNiriProvider(dir)
	if err := os.WriteFile(provider.GetOverridePath(), []byte(mergeTestBinds), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := provider.MergeMissingDefaults("foot"); err != nil {
		t.Fatalf("MergeMissingDefaults: %v", err)
	}

	// A rebind through the page rewrote the file: the backup no longer matches it.
	if err := provider.SetBind("Mod+Y", "spawn other", "", nil); err != nil {
		t.Fatalf("SetBind: %v", err)
	}
	if err := provider.UndoMergeDefaults("foot"); !errors.Is(err, niriconf.ErrChanged) {
		t.Fatalf("UndoMergeDefaults error = %v, want ErrChanged", err)
	}
}

func TestInsertBindsLines(t *testing.T) {
	content := "// a comment { with a brace\nbinds {\n    Mod+T { spawn \"foot\"; }\n}\n\nrecent-windows {\n    binds {\n        Mod+Tab { x; }\n    }\n}\n"
	merged, ok := insertBindsLines(content, "    Mod+D { y; }\n")
	if !ok {
		t.Fatal("insertBindsLines reported no binds node")
	}
	want := "// a comment { with a brace\nbinds {\n    Mod+T { spawn \"foot\"; }\n    Mod+D { y; }\n}\n\nrecent-windows {\n    binds {\n        Mod+Tab { x; }\n    }\n}\n"
	if merged != want {
		t.Fatalf("merged = %q,\nwant  %q", merged, want)
	}

	if _, ok := insertBindsLines("input {\n}\n", "    Mod+D { y; }\n"); ok {
		t.Fatal("insertBindsLines must report no binds node")
	}
}
