package sysupdate

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

const shellyRepoFixture = `[{"Name":"linux","CurrentVersion":"2:6.18-1","NewVersion":"2:6.19-1","DownloadSize":1024,"Repository":"core"}]`
const shellyAURFixture = `[{"Name":"example-git","Version":"r1-1","NewVersion":"r2-1","DownloadSize":-1,"PackageBase":"example"}]`

func TestParseShellyUpdates(t *testing.T) {
	tests := []struct {
		name string
		out  string
		repo RepoKind
		want []Package
	}{
		{"repository", shellyRepoFixture, RepoSystem, []Package{{Name: "linux", Backend: "shelly", Repo: RepoSystem, FromVersion: "2:6.18-1", ToVersion: "2:6.19-1", SizeBytes: 1024}}},
		{"aur package base", shellyAURFixture, RepoAUR, []Package{{Name: "example-git", Backend: "shelly", Repo: RepoAUR, FromVersion: "r1-1", ToVersion: "r2-1", ChangelogURL: "https://aur.archlinux.org/packages/example"}}},
		{"aur name fallback", `[{"Name":"example","Version":"1","NewVersion":"2"}]`, RepoAUR, []Package{{Name: "example", Backend: "shelly", Repo: RepoAUR, FromVersion: "1", ToVersion: "2", ChangelogURL: "https://aur.archlinux.org/packages/example"}}},
		{"empty", "[]\n", RepoSystem, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseShellyUpdates(tt.out, tt.repo)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("packages = %#v, want %#v", got, tt.want)
			}
		})
	}
	for _, out := range []string{"", "null", `[{"Name":"linux"}]`} {
		t.Run(out, func(t *testing.T) {
			if _, err := parseShellyUpdates(out, RepoSystem); err == nil {
				t.Fatalf("expected error for %q", out)
			}
		})
	}
}

func writeUpdateExecutable(t *testing.T, dir, name, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
}

func TestShellySelection(t *testing.T) {
	for _, tt := range []struct {
		name    string
		bins    []string
		version string
		want    string
	}{
		{"shelly before pacman", []string{"shelly", "pacman"}, `{"schemaVersion":1,"name":"shelly"}`, "shelly"},
		{"paru preferred", []string{"paru", "yay", "shelly", "pacman"}, "", "paru"},
		{"yay preferred", []string{"yay", "shelly", "pacman"}, "", "yay"},
		{"legacy shelly", []string{"shelly", "pacman"}, "2.4.1", "pacman"},
		{"wrong binary", []string{"shelly", "pacman"}, `{"schemaVersion":1,"name":"shelly-ui"}`, "pacman"},
		{"unknown schema", []string{"shelly", "pacman"}, `{"schemaVersion":2,"name":"shelly"}`, "pacman"},
		{"pacman only", []string{"pacman"}, "", "pacman"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			t.Setenv("PATH", dir)
			for _, bin := range tt.bins {
				writeUpdateExecutable(t, dir, bin, "printf '%s\\n' '"+tt.version+"'")
			}
			selection := Select(t.Context())
			if selection.System == nil || selection.System.ID() != tt.want {
				t.Fatalf("selection = %#v, want %s", selection.System, tt.want)
			}
		})
	}
}

func fakeShelly(t *testing.T) (string, string) {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "calls")
	t.Setenv("PATH", dir)
	t.Setenv("TERMINAL", "")
	t.Setenv("DMS_FORCE_PKEXEC", "")
	t.Setenv("DMS_TEST_SHELLY_LOG", log)
	t.Setenv("DMS_TEST_SHELLY_EXIT", "0")
	t.Setenv("SHELLY_ELEVATOR", "")
	writeUpdateExecutable(t, dir, "shelly", `printf '%s|%s\n' "$*" "$SHELLY_ELEVATOR" >> "$DMS_TEST_SHELLY_LOG"
case "$*" in
  'list-updates standard --json') printf '%s\n' '`+shellyRepoFixture+`' ;;
  'list-updates aur --json') printf '%s\n' '`+shellyAURFixture+`' ;;
  'upgrade standard --no-confirm'|'upgrade all --no-flatpak --no-appimage --no-confirm') exit "$DMS_TEST_SHELLY_EXIT" ;;
  *) echo "unexpected arguments: $*" >&2; exit 99 ;;
esac`)
	return dir, log
}

func readUpdateCalls(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return ""
	}
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestShellyCheckUpdates(t *testing.T) {
	_, log := fakeShelly(t)
	pkgs, err := (shellyBackend{}).CheckUpdates(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	if len(pkgs) != 2 || pkgs[0].Repo != RepoSystem || pkgs[1].Repo != RepoAUR {
		t.Fatalf("unexpected packages: %#v", pkgs)
	}
	if got, want := readUpdateCalls(t, log), "list-updates standard --json|\nlist-updates aur --json|\n"; got != want {
		t.Fatalf("calls = %q, want %q", got, want)
	}
}

func TestShellyCheckFailures(t *testing.T) {
	t.Run("exit status", func(t *testing.T) {
		dir, _ := fakeShelly(t)
		writeUpdateExecutable(t, dir, "shelly", "echo 'database unavailable' >&2; exit 1")
		if _, err := (shellyBackend{}).CheckUpdates(t.Context()); err == nil || !strings.Contains(err.Error(), "database unavailable") {
			t.Fatalf("expected query failure with stderr, got %v", err)
		}
	})
	t.Run("cancellation", func(t *testing.T) {
		dir, _ := fakeShelly(t)
		blocker := filepath.Join(dir, "blocker.fifo")
		if err := unix.Mkfifo(blocker, 0o600); err != nil {
			t.Fatal(err)
		}
		writeUpdateExecutable(t, dir, "shelly", "read line < "+blocker)
		ctx, cancel := context.WithTimeout(t.Context(), 100*time.Millisecond)
		defer cancel()
		if _, err := (shellyBackend{}).CheckUpdates(ctx); !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("expected deadline error, got %v", err)
		}
	})
}

func TestShellyUpgrade(t *testing.T) {
	for _, tt := range []struct {
		name       string
		includeAUR bool
		attached   bool
		terminal   bool
	}{
		{"pkexec repository", false, false, false},
		{"attached aur", true, true, false},
		{"terminal aur", true, false, true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			dir, log := fakeShelly(t)
			opts := UpgradeOptions{IncludeAUR: tt.includeAUR, AttachStdio: tt.attached, Targets: []Package{{Name: "linux", Backend: "shelly", Repo: RepoSystem}}}
			elevator := ""
			if tt.terminal {
				opts.Terminal = "fake-terminal"
				writeUpdateExecutable(t, dir, opts.Terminal, `while [ "$1" != sh ] && [ "$#" -gt 0 ]; do shift; done
shift
exec /bin/sh "$@"`)
			} else if !tt.attached {
				t.Setenv("DMS_FORCE_PKEXEC", "1")
				elevator = "pkexec"
			}
			if err := (shellyBackend{}).Upgrade(t.Context(), opts, nil); err != nil {
				t.Fatal(err)
			}
			command := "upgrade standard --no-confirm"
			if tt.includeAUR {
				command = "upgrade all --no-flatpak --no-appimage --no-confirm"
			}
			if got, want := readUpdateCalls(t, log), command+"|"+elevator+"\n"; got != want {
				t.Fatalf("calls = %q, want %q", got, want)
			}
		})
	}
}

func TestShellyUpgradeHolds(t *testing.T) {
	for _, tt := range []struct {
		name       string
		includeAUR bool
		ignored    []string
		wantError  bool
		dryRun     bool
	}{
		{"held aur", true, []string{"example-git"}, true, false},
		{"repository only", false, []string{"example-git"}, false, false},
		{"repository hold cannot exclude system upgrade", true, []string{"linux"}, false, false},
		{"unrelated hold", true, []string{"org.example.Flatpak"}, false, false},
		{"dry held aur", true, []string{"example-git"}, true, true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			_, log := fakeShelly(t)
			t.Setenv("DMS_FORCE_PKEXEC", "1")
			opts := UpgradeOptions{DryRun: tt.dryRun, IncludeAUR: tt.includeAUR, Ignored: tt.ignored, Targets: []Package{{Name: "linux", Backend: "shelly", Repo: RepoSystem}}}
			err := (shellyBackend{}).Upgrade(t.Context(), opts, nil)
			calls := readUpdateCalls(t, log)
			if strings.Count(calls, "list-updates aur --json") > 1 {
				t.Fatalf("duplicate AUR check: %q", calls)
			}
			if tt.wantError {
				if err == nil || err.Error() != `shelly cannot exclude held AUR package "example-git"; disable AUR updates or remove its DMS hold before updating` || strings.Contains(calls, "upgrade ") {
					t.Fatalf("held AUR package must block upgrade, got %v, calls %q", err, readUpdateCalls(t, log))
				}
				return
			}
			if err != nil || strings.Contains(calls, "upgrade ") == tt.dryRun {
				t.Fatalf("unexpected result for dryRun=%v: %v, calls %q", tt.dryRun, err, calls)
			}
		})
	}
	if !isPacmanFamily(shellyBackend{}) {
		t.Fatal("Shelly must enforce repository hold restrictions")
	}
}

func TestShellyHoldCheckFailure(t *testing.T) {
	dir, log := fakeShelly(t)
	writeUpdateExecutable(t, dir, "shelly", `printf '%s\n' "$*" >> "$DMS_TEST_SHELLY_LOG"
echo 'AUR unavailable' >&2
exit 1`)
	opts := UpgradeOptions{IncludeAUR: true, Ignored: []string{"example-git"}, Targets: []Package{{Name: "linux", Backend: "shelly", Repo: RepoSystem}}}
	err := (shellyBackend{}).Upgrade(t.Context(), opts, nil)
	if err == nil || !strings.Contains(err.Error(), "AUR unavailable") {
		t.Fatalf("expected AUR query error, got %v", err)
	}
	if calls := readUpdateCalls(t, log); calls != "list-updates aur --json\n" {
		t.Fatalf("query failure must stop the operation: %q", calls)
	}
}

func TestShellyDryRun(t *testing.T) {
	for _, includeAUR := range []bool{false, true} {
		_, log := fakeShelly(t)
		var lines []string
		opts := UpgradeOptions{DryRun: true, IncludeAUR: includeAUR, Targets: []Package{{Name: "linux", Backend: "shelly", Repo: RepoSystem}}}
		if err := (shellyBackend{}).Upgrade(t.Context(), opts, func(line string) { lines = append(lines, line) }); err != nil {
			t.Fatal(err)
		}
		wantCalls := "list-updates standard --json|\n"
		wantLines := []string{"linux 2:6.18-1 -> 2:6.19-1"}
		if includeAUR {
			wantCalls = "list-updates aur --json|\n" + wantCalls
			wantLines = append(wantLines, "example-git r1-1 -> r2-1")
		}
		if got := readUpdateCalls(t, log); got != wantCalls || !reflect.DeepEqual(lines, wantLines) {
			t.Fatalf("calls = %q, lines = %q", got, lines)
		}
	}
}

func TestShellySkipsExcludedTargets(t *testing.T) {
	for _, targets := range [][]Package{
		nil,
		{{Name: "example-git", Backend: "shelly", Repo: RepoAUR}},
		{{Name: "org.example.App", Backend: "flatpak", Repo: RepoFlatpak}},
		{{Name: "linux", Backend: "pacman", Repo: RepoSystem}},
	} {
		_, log := fakeShelly(t)
		if err := (shellyBackend{}).Upgrade(t.Context(), UpgradeOptions{Targets: targets, IncludeFlatpak: true}, nil); err != nil {
			t.Fatal(err)
		}
		if got := readUpdateCalls(t, log); got != "" {
			t.Fatalf("excluded targets executed commands: %q", got)
		}
	}
}

func TestShellyUpgradeFailure(t *testing.T) {
	_, _ = fakeShelly(t)
	t.Setenv("DMS_FORCE_PKEXEC", "1")
	t.Setenv("DMS_TEST_SHELLY_EXIT", "126")
	opts := UpgradeOptions{Targets: []Package{{Name: "linux", Backend: "shelly", Repo: RepoSystem}}}
	if err := (shellyBackend{}).Upgrade(t.Context(), opts, nil); err == nil {
		t.Fatal("authentication or upgrade failure must propagate")
	}
}
