package sysupdate

import (
	"reflect"
	"testing"
)

func TestParseAptUpgradable(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  []Package
	}{
		{
			name: "multiple architectures and suites",
			input: `Listing... Done
bash/stable 5.2.40-1 amd64 [upgradable from: 5.2.39-1]
libfoo/stable-security 1.0.0-2 amd64 [upgradable from: 1.0.0-1]
zsh/testing 5.9-6 arm64 [upgradable from: 5.9-5]`,
			want: []Package{
				{Name: "bash", Repo: RepoSystem, Backend: "apt", FromVersion: "5.2.39-1", ToVersion: "5.2.40-1"},
				{Name: "libfoo", Repo: RepoSystem, Backend: "apt", FromVersion: "1.0.0-1", ToVersion: "1.0.0-2"},
				{Name: "zsh", Repo: RepoSystem, Backend: "apt", FromVersion: "5.9-5", ToVersion: "5.9-6"},
			},
		},
		{
			name: "package name with hyphens, dots, plus signs",
			input: `Listing... Done
g++/stable 4:13.3.0-1 amd64 [upgradable from: 4:13.2.0-1]
libsdl2-2.0-0/stable 2.30.0+dfsg-1 amd64 [upgradable from: 2.28.5+dfsg-1]`,
			want: []Package{
				{Name: "g++", Repo: RepoSystem, Backend: "apt", FromVersion: "4:13.2.0-1", ToVersion: "4:13.3.0-1"},
				{Name: "libsdl2-2.0-0", Repo: RepoSystem, Backend: "apt", FromVersion: "2.28.5+dfsg-1", ToVersion: "2.30.0+dfsg-1"},
			},
		},
		{
			name:  "non-matching lines ignored",
			input: "WARNING: this is some warning\nbash/stable 5.2.40-1 amd64 [upgradable from: 5.2.39-1]",
			want: []Package{
				{Name: "bash", Repo: RepoSystem, Backend: "apt", FromVersion: "5.2.39-1", ToVersion: "5.2.40-1"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseAptUpgradable(tt.input)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("parseAptUpgradable() = %#v\nwant %#v", got, tt.want)
			}
		})
	}
}

func TestFilterAptHeld(t *testing.T) {
	pkgs := []Package{
		{Name: "bash", Repo: RepoSystem, Backend: "apt"},
		{Name: "linux-image-generic", Repo: RepoSystem, Backend: "apt"},
		{Name: "zsh", Repo: RepoSystem, Backend: "apt"},
	}

	got := filterAptHeld(append([]Package(nil), pkgs...), map[string]bool{"linux-image-generic": true})
	want := []Package{pkgs[0], pkgs[2]}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("filterAptHeld() = %#v\nwant %#v", got, want)
	}

	unfiltered := filterAptHeld(append([]Package(nil), pkgs...), nil)
	if !reflect.DeepEqual(unfiltered, pkgs) {
		t.Errorf("filterAptHeld(nil held) = %#v\nwant %#v", unfiltered, pkgs)
	}
}
