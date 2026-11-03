package sysupdate

import (
	"reflect"
	"strings"
	"testing"
)

func TestPortagePretendFailureIsNotAnEmptyUpdateList(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("PATH", dir)
	writeUpdateExecutable(t, dir, "pkexec", `exec "$@"`)
	writeUpdateExecutable(t, dir, "emerge", `case "$1" in
--sync) exit 0 ;;
--pretend) echo '!!! The following packages are blocked by another package:' >&2; exit 1 ;;
esac`)

	out, err := capturePortageUpdates(t.Context())
	if err == nil {
		t.Fatalf("capturePortageUpdates() = %q, want error", out)
	}
	if out != "" {
		t.Errorf("capturePortageUpdates() output = %q, want empty on failure", out)
	}
	if !strings.Contains(err.Error(), "blocked by another package") {
		t.Errorf("error lost emerge stderr: %v", err)
	}
}

func TestParsePortageUpdates(t *testing.T) {
	input := `These are the packages that would be merged, in order:

Calculating dependencies ... done!
[ebuild     U  ] app-text/ansifilter-2.23::gentoo [2.22::gentoo] USE="gui -verify-sig" 0 KiB
[ebuild     U ~] sys-apps/kmscon-10.0.4::gentoo [10.0.3::gentoo] USE="drm fbdev gles2 pango -debug" 0 KiB
[ebuild     UD~] gui-wm/umbriel-0.0.0_pre20260924::guru [0.0.0_pre20261003::guru] USE="X%* screencast -jemalloc" 0 KiB
[binary    gU  ] mail-client/thunderbird-153.4.0-1:0/esr::gentoo [153.3.0:0/esr::gentoo] USE="X clang pulseaudio" 0 KiB
[binary  rRg   ] media-video/mpv-0.41.0-r2-21:0/2::gentoo  USE="X alsa cdda cli" 0 KiB
[ebuild     U  ] www-client/librewolf-bin-157.0_p1::librewolf [156.0.1_p1::librewolf] USE="wayland (-selinux)" 0 KiB
[ebuild     U  ] dev-lang/rust-1.83.0:1.83::gentoo [1.82.0:1.82::gentoo] USE="lto rustfmt -clippy" 0 KiB
[ebuild     U  ] sys-libs/glibc-2.41-r3:2.2::gentoo [2.41-r2:2.2::gentoo] USE="multiarch -audit" 0 KiB

Total: 8 packages (8 upgrades), Size of downloads: 0 KiB
`

	want := []Package{
		{Name: "app-text/ansifilter", Repo: "gentoo (ebuild)", Backend: "portage", FromVersion: "2.22", ToVersion: "2.23"},
		{Name: "sys-apps/kmscon", Repo: "gentoo (ebuild)", Backend: "portage", FromVersion: "10.0.3", ToVersion: "10.0.4"},
		{Name: "gui-wm/umbriel", Repo: "guru (ebuild)", Backend: "portage", FromVersion: "0.0.0_pre20261003", ToVersion: "0.0.0_pre20260924"},
		{Name: "mail-client/thunderbird", Repo: "gentoo (binary)", Backend: "portage", FromVersion: "153.3.0:0/esr", ToVersion: "153.4.0-1:0/esr"},
		{Name: "media-video/mpv", Repo: "gentoo (binary)", Backend: "portage", ToVersion: "0.41.0-r2-21:0/2"},
		{Name: "www-client/librewolf-bin", Repo: "librewolf (ebuild)", Backend: "portage", FromVersion: "156.0.1_p1", ToVersion: "157.0_p1"},
		{Name: "dev-lang/rust", Repo: "gentoo (ebuild)", Backend: "portage", FromVersion: "1.82.0:1.82", ToVersion: "1.83.0:1.83"},
		{Name: "sys-libs/glibc", Repo: "gentoo (ebuild)", Backend: "portage", FromVersion: "2.41-r2:2.2", ToVersion: "2.41-r3:2.2"},
	}

	got := parsePortageUpdates(input, "portage")
	if !reflect.DeepEqual(got, want) {
		t.Errorf("parsePortageUpdates() =\n%#v\nwant\n%#v", got, want)
	}
}

func TestPortageIsExcluded(t *testing.T) {
	tests := []struct {
		name     string
		ignored  []string
		excluded bool
	}{
		{name: "portage ignored", ignored: []string{"sys-apps/portage"}, excluded: true},
		{name: "portage slot ignored", ignored: []string{"sys-apps/portage:0"}, excluded: true},
		{name: "portage nonzero slot ignored", ignored: []string{"sys-apps/portage:2"}, excluded: true},
		{name: "other package ignored", ignored: []string{"mail-client/thunderbird", "bad;name"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := portageIsExcluded(UpgradeOptions{Ignored: tt.ignored}); got != tt.excluded {
				t.Fatalf("portageIsExcluded(%v) = %v, want %v", tt.ignored, got, tt.excluded)
			}
		})
	}
}

func TestPackageMatchesIgnore(t *testing.T) {
	tests := []struct {
		pkg     string
		ignored string
		want    bool
	}{
		{pkg: "gui-wm/gamescope", ignored: "gui-wm/gamescope", want: true},
		{pkg: "gui-wm/gamescope", ignored: "gui-wm/sway"},
		{pkg: "app-misc/fastfetch:0", ignored: "app-misc/fastfetch", want: true},
		{pkg: "app-misc/fastfetch:0", ignored: "app-misc/fastfetch:0", want: true},
		{pkg: "app-misc/fastfetch:2", ignored: "app-misc/fastfetch:0"},
		{pkg: "app-misc/fastfetch:2", ignored: "app-misc/fastfetch:2", want: true},
		{pkg: "app-misc/fastfetch:2", ignored: "app-misc/fastfetch:5"},
		{pkg: "app-misc/fastfetch", ignored: "app-misc/fastfetch:0", want: true},
		{pkg: "app-misc/fastfetch", ignored: "app-misc/fastfetch:2"},
	}
	for _, tt := range tests {
		if got := PackageMatchesIgnore(tt.pkg, tt.ignored); got != tt.want {
			t.Errorf("PackageMatchesIgnore(%q, %q) = %v, want %v", tt.pkg, tt.ignored, got, tt.want)
		}
	}
}
