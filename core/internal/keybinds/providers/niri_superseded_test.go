package providers

import (
	"os"
	"strings"
	"testing"
)

// A line still equal to what the stock used to bind is a default the user never touched:
// it follows the new stock, and the undo brings the old line back.
func TestMergeUpgradesSupersededDefaults(t *testing.T) {
	fakeNiriValidate(t)
	dir := seedMergeDir(t)
	provider := NewNiriProvider(dir)
	const old = "binds {\n    Mod+R { switch-preset-column-width; }\n    Mod+Shift+R repeat=false { switch-preset-window-height; }\n}\n"
	if err := os.WriteFile(provider.GetOverridePath(), []byte(old), 0o644); err != nil {
		t.Fatal(err)
	}

	added, err := provider.MergeMissingDefaults("foot")
	if err != nil {
		t.Fatalf("MergeMissingDefaults: %v", err)
	}
	if !strings.Contains(strings.Join(added, ","), "Mod+R") {
		t.Fatalf("added = %v, want Mod+R upgraded", added)
	}
	written, err := os.ReadFile(provider.GetOverridePath())
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(written), "{ switch-preset-column-width; }") {
		t.Fatalf("Mod+R still bound to niri:\n%s", written)
	}
	if !strings.Contains(string(written), `Mod+R hotkey-overlay-title="Column width" { spawn "dms" "ipc" "call" "niri" "cycleColumnWidth"; }`) {
		t.Fatalf("Mod+R not upgraded to the DMS cycle:\n%s", written)
	}
	// A line with options of its own is not the stock line: kept as is.
	if !strings.Contains(string(written), "Mod+Shift+R repeat=false { switch-preset-window-height; }") {
		t.Fatalf("personal Mod+Shift+R line lost:\n%s", written)
	}

	if err := provider.UndoMergeDefaults("foot"); err != nil {
		t.Fatalf("UndoMergeDefaults: %v", err)
	}
	written, _ = os.ReadFile(provider.GetOverridePath())
	if string(written) != old {
		t.Fatalf("undo left binds.kdl as %q", written)
	}
}

func TestMergeUpgradesStockWindowHeightLine(t *testing.T) {
	fakeNiriValidate(t)
	dir := seedMergeDir(t)
	provider := NewNiriProvider(dir)
	const old = "binds {\n    Mod+Shift+R { switch-preset-window-height; }\n}\n"
	if err := os.WriteFile(provider.GetOverridePath(), []byte(old), 0o644); err != nil {
		t.Fatal(err)
	}

	added, err := provider.MergeMissingDefaults("foot")
	if err != nil {
		t.Fatalf("MergeMissingDefaults: %v", err)
	}
	if !strings.Contains(strings.Join(added, ","), "Mod+Shift+R") {
		t.Fatalf("added = %v, want Mod+Shift+R upgraded", added)
	}
	written, err := os.ReadFile(provider.GetOverridePath())
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(written), "switch-preset-window-height") {
		t.Fatalf("Mod+Shift+R still bound to the old stock action:\n%s", written)
	}
	if !strings.Contains(string(written), "Mod+Shift+R { switch-preset-column-width-back; }") {
		t.Fatalf("Mod+Shift+R not upgraded to the new stock line:\n%s", written)
	}
}
