package sysupdate

import (
	"reflect"
	"testing"
)

func TestParseArchUpdates(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		backendID string
		repo      RepoKind
		want      []Package
	}{
		{
			name: "multiple updates with epoch versions",
			input: `cups 2:2.4.18-1 -> 2:2.4.19-1
linux 6.18.0-1 -> 6.18.1-1
mesa 26.4.0-1 -> 26.4.1-1`,
			backendID: "paru",
			repo:      RepoSystem,
			want: []Package{
				{Name: "cups", Repo: RepoSystem, Backend: "paru", FromVersion: "2:2.4.18-1", ToVersion: "2:2.4.19-1"},
				{Name: "linux", Repo: RepoSystem, Backend: "paru", FromVersion: "6.18.0-1", ToVersion: "6.18.1-1"},
				{Name: "mesa", Repo: RepoSystem, Backend: "paru", FromVersion: "26.4.0-1", ToVersion: "26.4.1-1"},
			},
		},
		{
			name:      "AUR update with changelog url",
			input:     "google-chrome 147.0.7727.116-1 -> 147.0.7727.137-1",
			backendID: "paru",
			repo:      RepoAUR,
			want: []Package{
				{
					Name:         "google-chrome",
					Repo:         RepoAUR,
					Backend:      "paru",
					FromVersion:  "147.0.7727.116-1",
					ToVersion:    "147.0.7727.137-1",
					ChangelogURL: "https://aur.archlinux.org/packages/google-chrome",
				},
			},
		},
		{
			name:      "git package latest-commit marker",
			input:     "niri-git 26.04.r5.ga85b922-1 -> latest-commit",
			backendID: "yay",
			repo:      RepoAUR,
			want: []Package{
				{
					Name:         "niri-git",
					Repo:         RepoAUR,
					Backend:      "yay",
					FromVersion:  "26.04.r5.ga85b922-1",
					ToVersion:    "latest-commit",
					ChangelogURL: "https://aur.archlinux.org/packages/niri-git",
				},
			},
		},
		{
			name: "skips lines that don't match arrow format",
			input: `bat 0.26.0-1 -> 0.26.1-2
this is not an update line
foo`,
			backendID: "pacman",
			repo:      RepoSystem,
			want: []Package{
				{Name: "bat", Repo: RepoSystem, Backend: "pacman", FromVersion: "0.26.0-1", ToVersion: "0.26.1-2"},
			},
		},
		{
			name: "skips IgnorePkg entries",
			input: `bat 0.26.0-1 -> 0.26.1-2
linux 6.18.0-1 -> 6.18.1-1 [ignored]
discord 0.0.108-1 -> 0.0.109-1 [ignored]`,
			backendID: "pacman",
			repo:      RepoSystem,
			want: []Package{
				{Name: "bat", Repo: RepoSystem, Backend: "pacman", FromVersion: "0.26.0-1", ToVersion: "0.26.1-2"},
			},
		},
		{
			name:      "extra whitespace tolerated",
			input:     "  bat   0.26.0-1   ->   0.26.1-2  ",
			backendID: "paru",
			repo:      RepoSystem,
			want: []Package{
				{Name: "bat", Repo: RepoSystem, Backend: "paru", FromVersion: "0.26.0-1", ToVersion: "0.26.1-2"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseArchUpdates(tt.input, tt.backendID, tt.repo)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("parseArchUpdates() = %#v\nwant %#v", got, tt.want)
			}
		})
	}
}
