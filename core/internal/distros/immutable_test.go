package distros

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/spf13/afero"
)

func writeOSRelease(t *testing.T, fs afero.Fs, body string) {
	t.Helper()
	if err := afero.WriteFile(fs, "/etc/os-release", []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestDetectImmutable(t *testing.T) {
	cases := []struct {
		name      string
		files     []string
		osRelease map[string]string
		want      bool
	}{
		{"ostree marker beats plain fedora id", []string{"/run/ostree-booted"}, map[string]string{"ID": "fedora"}, true},
		{"silverblue variant without marker", nil, map[string]string{"ID": "fedora", "VARIANT_ID": "silverblue"}, true},
		{"sway atomic variant", nil, map[string]string{"ID": "fedora", "VARIANT_ID": "sway-atomic"}, true},
		{"workstation fedora", nil, map[string]string{"ID": "fedora", "VARIANT_ID": "workstation"}, false},
		{"bazzite id", nil, map[string]string{"ID": "bazzite", "ID_LIKE": "fedora"}, true},
		{"microos", []string{"/usr/sbin/transactional-update"}, map[string]string{"ID": "opensuse-microos"}, true},
		{"aeon by id_like", nil, map[string]string{"ID": "opensuse-aeon-rc", "ID_LIKE": "suse opensuse microos"}, true},
		{"tumbleweed", nil, map[string]string{"ID": "opensuse-tumbleweed", "ID_LIKE": "suse opensuse"}, false},
		{"vanilla by abroot", []string{"/usr/bin/abroot"}, map[string]string{"ID": "ubuntu", "ID_LIKE": "debian"}, true},
		{"steamos", nil, map[string]string{"ID": "steamos", "ID_LIKE": "arch"}, true},
		{"arch", nil, map[string]string{"ID": "arch"}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fs := afero.NewMemMapFs()
			for _, f := range c.files {
				if err := afero.WriteFile(fs, f, nil, 0o644); err != nil {
					t.Fatal(err)
				}
			}
			got, reason := detectImmutable(fs, c.osRelease)
			if got != c.want {
				t.Fatalf("detectImmutable = %v (%q), want %v", got, reason, c.want)
			}
			if got && reason == "" {
				t.Fatal("immutable without a reason")
			}
		})
	}
}

func TestGetOSInfoImmutable(t *testing.T) {
	t.Run("unregistered image id is accepted when immutable", func(t *testing.T) {
		fs := afero.NewMemMapFs()
		writeOSRelease(t, fs, "ID=\"zirconium\"\nID_LIKE=\"zirconium\"\nPRETTY_NAME=\"Zirconium\"\nVERSION_ID=44\n")
		if err := afero.WriteFile(fs, "/run/ostree-booted", nil, 0o644); err != nil {
			t.Fatal(err)
		}
		info, err := getOSInfo(fs, "amd64")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !info.Immutable || info.Distribution.ID != "zirconium" || info.VersionID != "44" {
			t.Fatalf("got %+v", info)
		}
	})

	t.Run("fedora derivative resolves through id_like", func(t *testing.T) {
		fs := afero.NewMemMapFs()
		writeOSRelease(t, fs, "ID=bazzite\nID_LIKE=fedora\nPRETTY_NAME=Bazzite\nVERSION_ID=44\n")
		info, err := getOSInfo(fs, "amd64")
		if err != nil {
			t.Fatal(err)
		}
		if !info.Immutable || info.ID != "bazzite" || info.Distribution.ID != "fedora" {
			t.Fatalf("got %+v", info)
		}
	})

	t.Run("unregistered mutable id still errors", func(t *testing.T) {
		fs := afero.NewMemMapFs()
		writeOSRelease(t, fs, "ID=slackware\nPRETTY_NAME=Slackware\n")
		if _, err := getOSInfo(fs, "amd64"); err == nil {
			t.Fatal("expected unsupported distribution error")
		}
	})

	t.Run("silverblue resolves to fedora but is flagged", func(t *testing.T) {
		fs := afero.NewMemMapFs()
		writeOSRelease(t, fs, "ID=fedora\nVARIANT_ID=silverblue\nPRETTY_NAME=\"Fedora Linux 44 (Silverblue)\"\nVERSION_ID=44\n")
		info, err := getOSInfo(fs, "amd64")
		if err != nil {
			t.Fatal(err)
		}
		if !info.Immutable || info.Distribution.ID != "fedora" || info.VariantID != "silverblue" {
			t.Fatalf("got %+v", info)
		}
	})

	t.Run("bluefin is no longer a mutable fedora", func(t *testing.T) {
		if IsDistroSupported("bluefin") {
			t.Fatal("bluefin must not be registered as an installable distribution")
		}
	})
}

func TestPendingDependencies(t *testing.T) {
	all := []deps.Dependency{
		{Name: "dms (Dux Shell)", Status: deps.StatusMissing},
		{Name: "niri", Status: deps.StatusInstalled},
		{Name: "quickshell", Status: deps.StatusInstalled},
		{Name: "danksearch", Status: deps.StatusMissing},
	}
	got := PendingDependencies(all, map[string]bool{"quickshell": true}, map[string]bool{"danksearch": true})
	if len(got) != 2 || got[0].Name != "dms (Dux Shell)" || got[1].Name != "quickshell" {
		t.Fatalf("got %+v", got)
	}
}

func TestApplyImmutableDetection(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "dms"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	got := ApplyImmutableDetection([]deps.Dependency{{Name: "dms (Dux Shell)", Status: deps.StatusMissing}, {Name: "niri", Status: deps.StatusMissing}})
	if got[0].Status != deps.StatusInstalled || got[1].Status != deps.StatusMissing {
		t.Fatalf("got %+v", got)
	}
}

func TestFedoraLayerCommands(t *testing.T) {
	f := NewFedoraDistribution(Registry["fedora"], nil)
	f.ostreeRequested = func() []string { return nil }
	dependencies := []deps.Dependency{
		{Name: "dms (Dux Shell)", Status: deps.StatusMissing},
		{Name: "niri", Status: deps.StatusMissing, Variant: deps.VariantGit},
		{Name: "ghostty", Status: deps.StatusInstalled},
		{Name: "matugen", Status: deps.StatusMissing},
		{Name: "danksearch", Status: deps.StatusMissing},
		{Name: "xwayland-satellite", Status: deps.StatusMissing},
	}
	got := strings.Join(f.LayerCommands(dependencies, deps.WindowManagerNiri, nil, map[string]bool{"danksearch": true}), "\n")

	for _, want := range []string{
		"_copr:copr.fedorainfracloud.org:duxlabs:dms.repo https://copr.fedorainfracloud.org/coprs/duxlabs/dms/repo/fedora-$(rpm -E %fedora)/duxlabs-dms-fedora-$(rpm -E %fedora).repo",
		"_copr:copr.fedorainfracloud.org:yalter:niri-git.repo",
		"echo priority=1 | sudo tee -a",
		"sudo rpm-ostree install xwayland-satellite dms niri matugen",
		"systemctl reboot",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("missing %q in:\n%s", want, got)
		}
	}
	for _, unwanted := range []string{"ghostty", "danksearch", "rpm-ostree upgrade", "dnf "} {
		if strings.Contains(got, unwanted) {
			t.Fatalf("unexpected %q in:\n%s", unwanted, got)
		}
	}
	if strings.Count(got, "duxlabs:dux-repo.repo https") != 1 {
		t.Fatalf("deps repo must be fetched exactly once:\n%s", got)
	}
}

func TestImmutableGuidance(t *testing.T) {
	steam := &OSInfo{PrettyName: "SteamOS", Distribution: DistroInfo{ID: "steamos"}, ImmutableReason: "os-release ID=steamos"}
	got := ImmutableGuidance(steam)
	if !strings.Contains(got, "SteamOS is an image-based system") || !strings.Contains(got, "Nothing was changed") {
		t.Fatalf("got %q", got)
	}
}

func TestFedoraLayerCommandsSwapVariants(t *testing.T) {
	f := NewFedoraDistribution(Registry["fedora"], nil)
	installed := map[string]bool{"dms-greeter": true, "dms": true}
	f.rpmInstalled = func(pkg string) bool { return installed[pkg] }
	f.ostreeRequested = func() []string { return []string{"dms", "dms-greeter"} }
	orig := installedFromCOPR
	installedFromCOPR = func(pkg, repo string) bool { return pkg == "dms" && repo == "duxlabs/dms-git" }
	t.Cleanup(func() { installedFromCOPR = orig })

	dependencies := []deps.Dependency{
		{Name: "dms (Dux Shell)", Status: deps.StatusInstalled, Variant: deps.VariantStable, CanToggle: true},
		{Name: "dms-greeter", Status: deps.StatusInstalled, Variant: deps.VariantGit, CanToggle: true},
		{Name: "danksearch", Status: deps.StatusInstalled},
	}
	reinstall := map[string]bool{"dms (Dux Shell)": true, "dms-greeter": true, "danksearch": true}
	got := strings.Join(f.LayerCommands(dependencies, deps.WindowManagerNiri, reinstall, nil), "\n")

	for _, want := range []string{
		"sudo rm -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:duxlabs:dms-git.repo /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:avengemedia:dms-git.repo",
		"sudo rpm-ostree install dms dux-greeter-git --uninstall dms dms-greeter",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("missing %q in:\n%s", want, got)
		}
	}
	if strings.Contains(got, "danksearch") {
		t.Fatalf("reinstall mark without a variant change must not be layered:\n%s", got)
	}
}

func TestFedoraLayerCommandsRenamedRequests(t *testing.T) {
	cases := []struct {
		name      string
		rpm       string
		requested []string
		want      string
	}{
		{"old package and request", "dms-greeter", []string{"dms-greeter", "danksearch"}, "sudo rpm-ostree install dux-greeter-git dux-search --uninstall dms-greeter danksearch"},
		{"old request resolved through Provides", "dux-greeter", []string{"dms-greeter"}, "sudo rpm-ostree install dux-greeter-git --uninstall dms-greeter"},
		{"new request", "dux-greeter", []string{"dux-greeter"}, "sudo rpm-ostree install dux-greeter-git --uninstall dux-greeter"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := NewFedoraDistribution(Registry["fedora"], nil)
			f.rpmInstalled = func(pkg string) bool { return pkg == tc.rpm }
			f.ostreeRequested = func() []string { return tc.requested }
			dependencies := []deps.Dependency{{Name: "dms-greeter", Status: deps.StatusInstalled, Variant: deps.VariantGit, CanToggle: true}}
			got := strings.Join(f.LayerCommands(dependencies, deps.WindowManagerNiri, map[string]bool{"dms-greeter": true}, nil), "\n")
			if !strings.Contains(got, tc.want) {
				t.Fatalf("missing %q in:\n%s", tc.want, got)
			}
		})
	}
}

func TestApplyImmutableDetectionReadsVariant(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "dms"), []byte("#!/bin/sh\necho 'dms (git) v2.0.0-5333'\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	got := ApplyImmutableDetection([]deps.Dependency{{Name: "dms (Dux Shell)", Status: deps.StatusMissing}})
	if got[0].Variant != deps.VariantGit || got[0].Version != "v2.0.0-5333" {
		t.Fatalf("got %+v", got[0])
	}
}
