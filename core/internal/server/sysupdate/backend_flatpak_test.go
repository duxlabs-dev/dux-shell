package sysupdate

import (
	"reflect"
	"strings"
	"testing"
)

func TestParseFlatpakUpdateOutput(t *testing.T) {
	realOutput := "Looking for updates…\n\n\n 1.\t   \torg.gtk.Gtk3theme.adw-gtk3-dark\t3.22\ti\tflathub\t< 131.4 kB\n\nProceed with these changes to the system installation? [Y/n]: n\n"

	tests := []struct {
		name      string
		input     string
		installed map[string]flatpakInstalledEntry
		want      []Package
	}{
		{
			name:  "nothing to do",
			input: "Looking for updates…\n\nNothing to do.\n",
			want:  nil,
		},
		{
			name:  "real flatpak update output — new install",
			input: realOutput,
			want: []Package{
				{
					Name:        "org.gtk.Gtk3theme.adw-gtk3-dark",
					Repo:        RepoFlatpak,
					Backend:     "flatpak",
					FromVersion: "",
					Ref:         "org.gtk.Gtk3theme.adw-gtk3-dark//3.22",
				},
			},
		},
		{
			name:  "update with installed version",
			input: "Looking for updates…\n\n 1.\tSlack\tcom.slack.Slack\tstable\tu\tflathub\t< 5.2 MB\n\nProceed? [Y/n]: n\n",
			installed: map[string]flatpakInstalledEntry{
				"com.slack.Slack//stable": {version: "4.40.0"},
			},
			want: []Package{
				{
					Name:        "Slack",
					Repo:        RepoFlatpak,
					Backend:     "flatpak",
					FromVersion: "4.40.0",
					Ref:         "com.slack.Slack//stable",
				},
			},
		},
		{
			name:  "reinstall op included",
			input: " 1.\t\torg.freedesktop.Platform\t25.08\tr\tflathub\t< 100 MB\n",
			want: []Package{
				{
					Name:    "org.freedesktop.Platform",
					Repo:    RepoFlatpak,
					Backend: "flatpak",
					Ref:     "org.freedesktop.Platform//25.08",
				},
			},
		},
		{
			name:  "unknown op excluded",
			input: " 1.\t\torg.freedesktop.Platform\t25.08\te\tflathub\t0\n",
			want:  nil,
		},
		{
			name:  "deduplicates same ref",
			input: " 1.\t\tcom.example.App\tstable\ti\tflathub\t< 1 MB\n 2.\t\tcom.example.App\tstable\ti\tflathub\t< 1 MB\n",
			want: []Package{
				{
					Name:    "com.example.App",
					Repo:    RepoFlatpak,
					Backend: "flatpak",
					Ref:     "com.example.App//stable",
				},
			},
		},
		{
			name:  "non-table lines ignored",
			input: "Looking for updates…\nSome warning line\nID\tBranch\tOp\n 1.\t\tcom.example.App\tstable\ti\tflathub\t< 1 MB\nProceed? [Y/n]: n\n",
			want: []Package{
				{
					Name:    "com.example.App",
					Repo:    RepoFlatpak,
					Backend: "flatpak",
					Ref:     "com.example.App//stable",
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseFlatpakUpdateOutput(tt.input, tt.installed)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("parseFlatpakUpdateOutput() = %#v\nwant %#v", got, tt.want)
			}
		})
	}
}

func TestFlatpakCheckUpdates(t *testing.T) {
	const runtimePrompt = `[ "$1" = list ] && exit 0
for a in "$@"; do
	if [ "$a" = --no-deps ]; then
		printf ' 1.\tVesktop\tdev.vencord.Vesktop\tstable\tu\tflathub\t< 130 MB\n\nProceed with these changes? [Y/n]: '
		exit 1
	fi
done
printf 'Required runtime for dev.vencord.Vesktop/x86_64/stable found in remote flathub\nDo you want to install it? [Y/n]: '
echo 'error: The application dev.vencord.Vesktop/x86_64/stable requires the runtime org.freedesktop.Platform/x86_64/26.08 which is not installed' >&2
exit 1`

	for _, tt := range []struct {
		name    string
		script  string
		wantRef string
		wantErr string
	}{
		{name: "update needing a new runtime", script: runtimePrompt, wantRef: "dev.vencord.Vesktop//stable"},
		{
			name:    "failure without a table",
			script:  "[ \"$1\" = list ] && exit 0\necho 'Looking for updates…'\necho 'error: Unable to load summary from remote flathub' >&2\nexit 1",
			wantErr: "Unable to load summary",
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			t.Setenv("PATH", dir)
			writeUpdateExecutable(t, dir, "flatpak", tt.script)

			pkgs, err := flatpakBackend{}.CheckUpdates(t.Context())
			if tt.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
					t.Errorf("err = %v, want %q (a failed check must not read as up to date)", err, tt.wantErr)
				}
				return
			}
			if err != nil || len(pkgs) != 1 || pkgs[0].Ref != tt.wantRef {
				t.Errorf("pkgs = %#v, err = %v, want %s", pkgs, err, tt.wantRef)
			}
		})
	}
}
