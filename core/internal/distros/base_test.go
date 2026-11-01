package distros

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

func TestBaseDistribution_detectDMS_NotInstalled(t *testing.T) {
	originalHome := os.Getenv("HOME")
	defer os.Setenv("HOME", originalHome)

	tempDir := t.TempDir()
	os.Setenv("HOME", tempDir)

	logChan := make(chan string, 10)
	defer close(logChan)

	base := NewBaseDistribution(logChan)
	dep := base.detectDMS()

	if dep.Status != deps.StatusMissing {
		t.Errorf("Expected StatusMissing, got %d", dep.Status)
	}
}

func TestBaseDistribution_detectDMS_DirectoryWithoutGit(t *testing.T) {
	tempDir := t.TempDir()
	dmsPath := filepath.Join(tempDir, ".config", "quickshell", "dms")
	os.MkdirAll(dmsPath, 0o755)

	originalHome := os.Getenv("HOME")
	defer os.Setenv("HOME", originalHome)
	os.Setenv("HOME", tempDir)

	logChan := make(chan string, 10)
	defer close(logChan)

	base := NewBaseDistribution(logChan)
	dep := base.detectDMS()

	if dep.Status == deps.StatusMissing {
		t.Error("Expected DMS to be detected as present")
	}
}

func TestParseHyprlandVersion(t *testing.T) {
	tests := []struct{ name, out, want string }{
		{
			name: "0.56 main build reports the tag, not the first line",
			out: "Hyprland 0.56.0 built from branch main at commit 5a78b5e927345860a27e2893bf894f97ee620c48 clean (unknown).\n" +
				"Date: Tue Oct 06 01:20:44 2026\n" +
				"Tag: 0.56.2, commits: 7899\n" +
				"\nLibraries:\nHyprgraphics: built against 0.5.1, system has unknown\n",
			want: "0.56.2",
		},
		{
			name: "v-prefixed tag",
			out:  "Hyprland, built from branch  at commit 918d8340afd652b011b937d29d5eea0be08467f5  (version: bump to v0.41.2).\nTag: v0.41.2, commits: 4880\n",
			want: "0.41.2",
		},
		{
			name: "no tag line falls back to the first version",
			out:  "Hyprland v0.41.2 built from branch main\n",
			want: "0.41.2",
		},
	}
	for _, tt := range tests {
		if got := ParseHyprlandVersion(tt.out); got != tt.want {
			t.Errorf("%s: got %q, want %q", tt.name, got, tt.want)
		}
	}
}

func TestDetectGreeterPackageAcceptsOldNames(t *testing.T) {
	cases := []struct {
		installed     string
		wantInstalled bool
		wantVariant   deps.PackageVariant
	}{
		{"", false, deps.VariantStable},
		{"dms-greeter", true, deps.VariantStable},
		{"dux-greeter", true, deps.VariantStable},
		{"dms-greeter-git", true, deps.VariantGit},
		{"dux-greeter-git", true, deps.VariantGit},
	}
	for _, tc := range cases {
		dep := NewBaseDistribution(nil).detectGreeterPackage(func(p string) bool { return p == tc.installed })
		if (dep.Status == deps.StatusInstalled) != tc.wantInstalled || dep.Variant != tc.wantVariant {
			t.Errorf("%q installed: status %v variant %v, want installed=%v variant %v", tc.installed, dep.Status, dep.Variant, tc.wantInstalled, tc.wantVariant)
		}
	}
}

func TestDetectCalendarPackageAcceptsOldNames(t *testing.T) {
	for installed, want := range map[string]deps.PackageVariant{
		"":                 deps.VariantStable,
		"dankcalendar-git": deps.VariantGit,
		"dux-calendar-git": deps.VariantGit,
	} {
		dep := NewBaseDistribution(nil).detectCalendarPackage(func(p string) bool { return p == installed })
		if dep.Variant != want {
			t.Errorf("%q installed: variant %v, want %v", installed, dep.Variant, want)
		}
	}
}

func TestRenamedPackagesInstallNewNames(t *testing.T) {
	cases := map[string]Distribution{
		"fedora":   NewFedoraDistribution(Registry["fedora"], nil),
		"ubuntu":   NewUbuntuDistribution(Registry["ubuntu"], nil),
		"void":     NewVoidDistribution(Registry["void"], nil),
		"opensuse": NewOpenSUSEDistribution(Registry["opensuse-tumbleweed"], nil),
		"debian":   NewDebianDistribution(Registry["debian"], nil),
	}
	for id, d := range cases {
		for _, variant := range []deps.PackageVariant{deps.VariantStable, deps.VariantGit} {
			packages := d.GetPackageMappingWithVariants(deps.WindowManagerNiri, map[string]deps.PackageVariant{"dux-greeter": variant, "dux-calendar": variant, "dux-files": variant})
			for _, dep := range []string{"dux-greeter", "dux-search", "dux-calendar", "dux-files"} {
				if got := strings.TrimSuffix(packages[dep].Name, "-git"); got != dep {
					t.Errorf("%s %s (%v) installs %q, want %q", id, dep, variant, packages[dep].Name, dep)
				}
			}
		}
	}
}

func TestDuxFilesIsOfferedAndMapped(t *testing.T) {
	cases := map[string]struct {
		d           Distribution
		stable, git string
	}{
		"arch":     {NewArchDistribution(Registry["arch"], nil), "dux-files-bin", "dux-files-git"},
		"fedora":   {NewFedoraDistribution(Registry["fedora"], nil), "dux-files", "dux-files-git"},
		"ubuntu":   {NewUbuntuDistribution(Registry["ubuntu"], nil), "dux-files", "dux-files-git"},
		"debian":   {NewDebianDistribution(Registry["debian"], nil), "dux-files", "dux-files-git"},
		"pika":     {NewDebianDistribution(Registry["pika"], nil), "dux-files", "dux-files-git"},
		"opensuse": {NewOpenSUSEDistribution(Registry["opensuse-tumbleweed"], nil), "dux-files", "dux-files-git"},
		"void":     {NewVoidDistribution(Registry["void"], nil), "dux-files", "dux-files"},
		"gentoo":   {NewGentooDistribution(Registry["gentoo"], nil), "dux-desktop/dux-files", "dux-desktop/dux-files"},
	}
	for id, tc := range cases {
		dependencies, err := tc.d.DetectDependenciesWithTerminal(context.Background(), deps.WindowManagerNiri, deps.TerminalKitty)
		if err != nil {
			t.Fatal(err)
		}
		packages := tc.d.GetPackageMapping(deps.WindowManagerNiri)
		offered := false
		for _, dep := range dependencies {
			offered = offered || dep.Name == "dux-files"
			if _, ok := packages[dep.Name]; !ok {
				t.Errorf("%s offers %s but maps no package for it", id, dep.Name)
			}
		}
		if !offered {
			t.Errorf("%s does not offer dux-files", id)
		}
		for variant, want := range map[deps.PackageVariant]string{deps.VariantStable: tc.stable, deps.VariantGit: tc.git} {
			if got := tc.d.GetPackageMappingWithVariants(deps.WindowManagerNiri, map[string]deps.PackageVariant{"dux-files": variant})["dux-files"].Name; got != want {
				t.Errorf("%s dux-files (%v) installs %q, want %q", id, variant, got, want)
			}
		}
	}
}
