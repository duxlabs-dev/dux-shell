package utils

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFlatpakInstallationDirNoFlatpak(t *testing.T) {
	tempDir := t.TempDir()
	t.Setenv("PATH", tempDir)

	_, err := FlatpakInstallationDir("any.package.name")
	if err == nil {
		t.Errorf("expected error when flatpak not in PATH")
	}
	if err != nil && !strings.Contains(err.Error(), "not found in PATH") {
		t.Errorf("expected 'not found in PATH' error, got: %v", err)
	}
}

func TestFlatpakInstallationDirCommandFailure(t *testing.T) {
	fakeTools(t, fakeTool{name: "flatpak", exit: 1})

	_, err := FlatpakInstallationDir("test.package")
	if err == nil {
		t.Errorf("expected error when flatpak command fails")
	}
	if err != nil && !strings.Contains(err.Error(), "not installed") {
		t.Errorf("expected 'not installed' error, got: %v", err)
	}
}

func TestFlatpakExistsByInstallationDir(t *testing.T) {
	fakeTools(t, fakeTool{name: "flatpak"})
	user := t.TempDir()
	system := t.TempDir()
	extra := t.TempDir()
	confDir := t.TempDir()
	t.Setenv("FLATPAK_USER_DIR", user)
	t.Setenv("FLATPAK_SYSTEM_DIR", system)
	old := flatpakInstallationsDir
	flatpakInstallationsDir = confDir
	t.Cleanup(func() { flatpakInstallationsDir = old })

	if err := os.MkdirAll(filepath.Join(user, "app", "app.user.test"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(extra, "app", "app.extra.test"), 0o755); err != nil {
		t.Fatal(err)
	}
	conf := "[Installation \"extra\"]\nPath=" + extra + "\n"
	if err := os.WriteFile(filepath.Join(confDir, "extra.conf"), []byte(conf), 0o644); err != nil {
		t.Fatal(err)
	}

	if !FlatpakExists("app.user.test") {
		t.Errorf("expected app in the user installation to be found")
	}
	if !FlatpakExists("app.extra.test") {
		t.Errorf("expected app in an installations.d path to be found")
	}
	if FlatpakExists("app.missing.test") {
		t.Errorf("expected missing app to be reported absent")
	}
	if !AnyFlatpakExists("app.missing.test", "app.user.test") {
		t.Errorf("expected AnyFlatpakExists to find the installed app")
	}
}
