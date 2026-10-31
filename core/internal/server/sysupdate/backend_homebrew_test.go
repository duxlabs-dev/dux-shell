package sysupdate

import (
	"reflect"
	"testing"
)

func TestParseBrewOutdated(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    []Package
		wantErr bool
	}{
		{
			name:  "nothing outdated",
			input: `{"formulae":[],"casks":[]}`,
		},
		{
			name: "formulae and casks, pinned skipped",
			input: `{
				"formulae": [
					{
						"name": "git",
						"installed_versions": ["2.50.0", "2.51.0"],
						"current_version": "2.51.1",
						"pinned": false,
						"pinned_version": null
					},
					{
						"name": "dmstest/fixtures/dmsworld",
						"installed_versions": ["1.0"],
						"current_version": "1.1",
						"pinned": true,
						"pinned_version": "1.0"
					}
				],
				"casks": [
					{
						"name": "font-fira-code",
						"installed_versions": ["6.2"],
						"current_version": "6.3"
					},
					{
						"name": "old-cask",
						"installed_versions": "1.0",
						"current_version": "2.0"
					}
				]
			}`,
			want: []Package{
				{Name: "git", Repo: RepoHomebrew, Backend: "homebrew", FromVersion: "2.51.0", ToVersion: "2.51.1"},
				{Name: "font-fira-code", Repo: RepoHomebrew, Backend: "homebrew", FromVersion: "6.2", ToVersion: "6.3"},
				{Name: "old-cask", Repo: RepoHomebrew, Backend: "homebrew", FromVersion: "1.0", ToVersion: "2.0"},
			},
		},
		{
			name:    "not json",
			input:   "Error: Homebrew is not installed",
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseBrewOutdated([]byte(tt.input))
			if (err != nil) != tt.wantErr {
				t.Fatalf("err = %v, wantErr %v", err, tt.wantErr)
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("parseBrewOutdated() = %#v\nwant %#v", got, tt.want)
			}
		})
	}
}
