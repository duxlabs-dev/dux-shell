package wayland

import (
	"os"
	"path/filepath"
	"testing"
)

func TestStageICCProfile(t *testing.T) {
	configDir := t.TempDir()
	srcDir := t.TempDir()
	write := func(t *testing.T, path string, content string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	read := func(t *testing.T, path string) string {
		t.Helper()
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		return string(data)
	}

	first := filepath.Join(srcDir, "dp1", "display.icc")
	second := filepath.Join(srcDir, "dp2", "display.icc")
	write(t, first, "profile for DP-1")
	write(t, second, "profile for DP-2")

	name1, err := stageICCProfile(configDir, first)
	if err != nil {
		t.Fatalf("stageICCProfile(first): %v", err)
	}
	if name1 != "display.icc" {
		t.Fatalf("first copy: got %q", name1)
	}

	name2, err := stageICCProfile(configDir, second)
	if err != nil {
		t.Fatalf("stageICCProfile(second): %v", err)
	}
	if name2 != "display-1.icc" {
		t.Fatalf("same-named different profile must get a sibling: got %q", name2)
	}
	if got := read(t, filepath.Join(configDir, name1)); got != "profile for DP-1" {
		t.Fatalf("first copy was overwritten: %q", got)
	}
	if got := read(t, filepath.Join(configDir, name2)); got != "profile for DP-2" {
		t.Fatalf("second copy has wrong content: %q", got)
	}

	again, err := stageICCProfile(configDir, second)
	if err != nil {
		t.Fatalf("stageICCProfile(second again): %v", err)
	}
	if again != name2 {
		t.Fatalf("an identical copy must be reused: got %q", again)
	}

	inPlace, err := stageICCProfile(configDir, filepath.Join(configDir, name1))
	if err != nil {
		t.Fatalf("stageICCProfile(in place): %v", err)
	}
	if inPlace != name1 {
		t.Fatalf("a file already in the profile directory is used as it is: got %q", inPlace)
	}

	if _, err := stageICCProfile(configDir, filepath.Join(srcDir, "missing.icc")); err == nil {
		t.Fatal("expected an error for a missing source")
	}
}
