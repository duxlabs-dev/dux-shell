package sysupdate

import (
	"reflect"
	"testing"
)

func TestParseDnfList(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		backendID string
		installed map[string]string
		want      []Package
	}{
		{
			name: "noarch package and missing installed entry",
			input: `bash.x86_64        5.2.40-1.fc41        updates
fonts-misc.noarch  1.0.5-2.fc41         updates`,
			backendID: "dnf",
			installed: map[string]string{"bash": "5.2.39-1.fc41"},
			want: []Package{
				{Name: "bash.x86_64", Repo: RepoSystem, Backend: "dnf", FromVersion: "5.2.39-1.fc41", ToVersion: "5.2.40-1.fc41"},
				{Name: "fonts-misc.noarch", Repo: RepoSystem, Backend: "dnf", FromVersion: "", ToVersion: "1.0.5-2.fc41"},
			},
		},
		{
			name: "skips header rows",
			input: `Available
Upgrades
bash.x86_64       5.2.40-1.fc41       updates`,
			backendID: "dnf",
			installed: nil,
			want: []Package{
				{Name: "bash.x86_64", Repo: RepoSystem, Backend: "dnf", FromVersion: "", ToVersion: "5.2.40-1.fc41"},
			},
		},
		{
			name:      "skips lines with too few fields",
			input:     "incomplete",
			backendID: "dnf",
			want:      nil,
		},
		{
			name: "one package offered by two repos is reported once",
			input: `dux-greeter.x86_64   1.5.1-1.fc44   copr:copr.fedorainfracloud.org:avengemedia:danklinux
dux-greeter.x86_64   1.5.1-1.fc44   coprdep:copr.fedorainfracloud.org:avengemedia:danklinux`,
			backendID: "dnf5",
			installed: map[string]string{"dux-greeter": "1.5.0-1.fc44"},
			want: []Package{
				{Name: "dux-greeter.x86_64", Repo: RepoSystem, Backend: "dnf5", FromVersion: "1.5.0-1.fc44", ToVersion: "1.5.1-1.fc44"},
			},
		},
		{
			name: "duplicate rows do not suppress other packages or differing versions",
			input: `bash.x86_64      5.2.40-1.fc41   updates
bash.x86_64      5.2.40-1.fc41   fedora
bash.i686        5.2.40-1.fc41   updates
kernel.x86_64    6.14.2-1.fc41   updates
kernel.x86_64    6.14.3-1.fc41   updates`,
			backendID: "dnf5",
			installed: map[string]string{"bash": "5.2.39-1.fc41", "kernel": "6.14.1-1.fc41"},
			want: []Package{
				{Name: "bash.x86_64", Repo: RepoSystem, Backend: "dnf5", FromVersion: "5.2.39-1.fc41", ToVersion: "5.2.40-1.fc41"},
				{Name: "bash.i686", Repo: RepoSystem, Backend: "dnf5", FromVersion: "5.2.39-1.fc41", ToVersion: "5.2.40-1.fc41"},
				{Name: "kernel.x86_64", Repo: RepoSystem, Backend: "dnf5", FromVersion: "6.14.1-1.fc41", ToVersion: "6.14.2-1.fc41"},
				{Name: "kernel.x86_64", Repo: RepoSystem, Backend: "dnf5", FromVersion: "6.14.1-1.fc41", ToVersion: "6.14.3-1.fc41"},
			},
		},
		{
			name: "skips the obsoleted packages listed under an upgrade",
			input: `Upgrades
example-lib.x86_64             2.0.0-1.fc44   updates
example-app.noarch             3.1.0-1.fc44   updates

Obsoleting packages
example-app.noarch             3.1.0-1.fc44   updates
    example-app-old.noarch     3.0.0-1.fc44   updates
    example-helper.x86_64      1.4.0-1.fc44   updates`,
			backendID: "dnf5",
			installed: map[string]string{
				"example-lib":     "1.9.0-1.fc44",
				"example-app":     "3.0.0-1.fc44",
				"example-app-old": "3.0.0-1.fc44",
				"example-helper":  "1.4.0-1.fc44",
			},
			want: []Package{
				{Name: "example-lib.x86_64", Repo: RepoSystem, Backend: "dnf5", FromVersion: "1.9.0-1.fc44", ToVersion: "2.0.0-1.fc44"},
				{Name: "example-app.noarch", Repo: RepoSystem, Backend: "dnf5", FromVersion: "3.0.0-1.fc44", ToVersion: "3.1.0-1.fc44"},
			},
		},
		{
			name: "skips obsoleted packages in dnf4 output, which has no upgrades heading",
			input: `example-lib.x86_64             2.0.0-1.fc41   updates
Obsoleting Packages
example-app.noarch             3.1.0-1.fc41   updates
    example-app-old.noarch     3.0.0-1.fc41   @updates`,
			backendID: "dnf",
			installed: map[string]string{
				"example-lib":     "1.9.0-1.fc41",
				"example-app":     "3.0.0-1.fc41",
				"example-app-old": "3.0.0-1.fc41",
			},
			want: []Package{
				{Name: "example-lib.x86_64", Repo: RepoSystem, Backend: "dnf", FromVersion: "1.9.0-1.fc41", ToVersion: "2.0.0-1.fc41"},
				{Name: "example-app.noarch", Repo: RepoSystem, Backend: "dnf", FromVersion: "3.0.0-1.fc41", ToVersion: "3.1.0-1.fc41"},
			},
		},
		{
			name: "skips dnf5 banner / column header lines",
			input: `Updates available
Last metadata expiration check: 0:01:23 ago on Tue Apr 29 14:00:00 2026.
Package    Version    Repository    Size
bash.x86_64       5.2.40-1.fc41       updates`,
			backendID: "dnf",
			installed: nil,
			want: []Package{
				{Name: "bash.x86_64", Repo: RepoSystem, Backend: "dnf", FromVersion: "", ToVersion: "5.2.40-1.fc41"},
			},
		},
		{
			name: "skips dnf warning lines while keeping package rows",
			input: `Failed to expire repository cache in path "/home/user/.cache/libdnf5/updates": cannot open file
example-driver.x86_64                2:9.8.7-1.fc99                updates
example-tool.noarch                  1.2.3^45.gitabcdef-1.fc99     copr`,
			backendID: "dnf5",
			installed: map[string]string{
				"example-driver": "2:9.8.6-1.fc99",
				"example-tool":   "1.2.2^44.gitabcdef-1.fc99",
			},
			want: []Package{
				{Name: "example-driver.x86_64", Repo: RepoSystem, Backend: "dnf5", FromVersion: "2:9.8.6-1.fc99", ToVersion: "2:9.8.7-1.fc99"},
				{Name: "example-tool.noarch", Repo: RepoSystem, Backend: "dnf5", FromVersion: "1.2.2^44.gitabcdef-1.fc99", ToVersion: "1.2.3^45.gitabcdef-1.fc99"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseDnfList(tt.input, tt.backendID, tt.installed)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("parseDnfList() = %#v\nwant %#v", got, tt.want)
			}
		})
	}
}

func TestDnfCheckUpdatesArgv(t *testing.T) {
	tests := []struct {
		bin  string
		want []string
	}{
		{bin: "dnf5", want: []string{"dnf5", "check-upgrade", "--refresh", "--quiet"}},
		{bin: "dnf", want: []string{"dnf", "check-update", "--refresh", "--quiet"}},
	}

	for _, tt := range tests {
		t.Run(tt.bin, func(t *testing.T) {
			got := dnfCheckUpdatesArgv(tt.bin)
			if !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("dnfCheckUpdatesArgv(%q) = %#v, want %#v", tt.bin, got, tt.want)
			}
		})
	}
}
