package sysupdate

import (
	"reflect"
	"testing"
)

func TestParseXbpsInstalled(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  map[string]string
	}{
		{
			name: "splits on the last dash so hyphenated names survive",
			input: `ii bash-5.2.21_1                         GNU Bourne Again Shell
ii xorg-server-xwayland-24.1.2_1         Nested X server that runs as a wayland client
ii dms-shell-git-1.7.0+git4915_1         Dux Shell
`,
			want: map[string]string{
				"bash":                 "5.2.21_1",
				"xorg-server-xwayland": "24.1.2_1",
				"dms-shell-git":        "1.7.0+git4915_1",
			},
		},
		{
			name:  "skips lines without a pkgver",
			input: "ii\nii nodash\n\nuu glibc-2.39_2 GNU C library\n",
			want:  map[string]string{"glibc": "2.39_2"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseXbpsInstalled(tt.input)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got %#v, want %#v", got, tt.want)
			}
		})
	}
}

func TestParseXbpsDryRun(t *testing.T) {
	installed := map[string]string{
		"xorg-server-xwayland": "24.1.1_1",
		"bash":                 "5.2.21_1",
	}
	tests := []struct {
		name  string
		input string
		want  []Package
	}{
		{
			name: "updates only, installs and removals ignored",
			input: `xorg-server-xwayland-24.1.2_1 update x86_64 https://repo-default.voidlinux.org/current 2461696 912345
bash-5.2.32_1 update x86_64 https://repo-default.voidlinux.org/current 9043968 1602832
libnew-1.0_1 install x86_64 https://repo-default.voidlinux.org/current 102400 40960
oldlib-0.9_3 remove x86_64 https://repo-default.voidlinux.org/current 0 0
`,
			want: []Package{
				{Name: "xorg-server-xwayland", Repo: RepoSystem, Backend: "xbps", FromVersion: "24.1.1_1", ToVersion: "24.1.2_1"},
				{Name: "bash", Repo: RepoSystem, Backend: "xbps", FromVersion: "5.2.21_1", ToVersion: "5.2.32_1"},
			},
		},
		{
			name:  "unknown installed version stays empty",
			input: "xbps-0.60.3_1 update x86_64 https://repo-default.voidlinux.org/current 1638400 409600\n",
			want: []Package{
				{Name: "xbps", Repo: RepoSystem, Backend: "xbps", FromVersion: "", ToVersion: "0.60.3_1"},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseXbpsDryRun(tt.input, installed)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got %#v, want %#v", got, tt.want)
			}
		})
	}
}
