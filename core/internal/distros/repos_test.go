package distros

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

func TestOBSZypperAlias(t *testing.T) {
	if got := obsZypperAlias("home:AvengeMedia:dms"); got != "home_AvengeMedia_dms" {
		t.Fatalf("alias = %q, want the section header spelling home_AvengeMedia_dms", got)
	}
}

func TestCOPRFromRepoMatches(t *testing.T) {
	cases := []struct {
		fromRepo, repo string
		want           bool
	}{
		{"copr:copr.fedorainfracloud.org:duxlabs:dms-git\n", coprDMSGit, true},
		{"copr:copr.fedorainfracloud.org:avengemedia:dms-git", coprDMSGit, true},
		{"copr:copr.fedorainfracloud.org:avengemedia:danklinux", coprDeps, true},
		{"copr:copr.fedorainfracloud.org:duxlabs:dms", coprDMSGit, false},
		{"copr:copr.fedorainfracloud.org:avengemedia:dms", coprDMSGit, false},
		{"copr:copr.fedorainfracloud.org:duxlabs:dms-git", coprDMS, false},
		{"copr:copr.fedorainfracloud.org:yalter:niri-git", "yalter/niri-git", true},
	}
	for _, tc := range cases {
		if got := coprFromRepoMatches(tc.fromRepo, tc.repo); got != tc.want {
			t.Errorf("coprFromRepoMatches(%q, %q) = %v, want %v", tc.fromRepo, tc.repo, got, tc.want)
		}
	}
}

func existsIn(paths ...string) func(string) bool {
	return func(p string) bool { return slices.Contains(paths, p) }
}

func TestPlanRepoMoves(t *testing.T) {
	legacyDeps := coprRepoFile("avengemedia/danklinux")
	retiredDeps := coprRepoFile("duxlabs/dux")
	newDeps := coprRepoFile("duxlabs/dux-repo")
	cases := []struct {
		name          string
		exists        func(string) bool
		wantAdds      []string
		wantRemoves   []string
		wantLegacyIdx []string
	}{
		{"legacy only", existsIn(legacyDeps), []string{"duxlabs/dux-repo"}, []string{"avengemedia/danklinux"}, []string{legacyDeps}},
		{"both present", existsIn(legacyDeps, newDeps), nil, []string{"avengemedia/danklinux"}, []string{legacyDeps}},
		{"new only", existsIn(newDeps), nil, nil, nil},
		{"none", existsIn(), nil, nil, nil},
		{"retired dux slug", existsIn(retiredDeps), []string{"duxlabs/dux-repo"}, []string{"duxlabs/dux"}, []string{retiredDeps}},
		{"both legacy deps", existsIn(legacyDeps, retiredDeps), []string{"duxlabs/dux-repo"}, []string{"avengemedia/danklinux", "duxlabs/dux"}, []string{legacyDeps, retiredDeps}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			moves := coprChannel.moves(tc.exists)
			if len(moves) != 4 {
				t.Fatalf("got %d rows, want dms, dms-git and the two legacy deps rows", len(moves))
			}
			var adds, removes []string
			for _, add := range repoMoveAdds(moves) {
				adds = append(adds, add.RepoURL)
			}
			for _, move := range repoMoveRemoves(moves) {
				removes = append(removes, move.Old)
			}
			if !slices.Equal(adds, tc.wantAdds) || !slices.Equal(removes, tc.wantRemoves) {
				t.Fatalf("adds %v removes %v, want %v / %v", adds, removes, tc.wantAdds, tc.wantRemoves)
			}
			legacy := LegacyRepoPaths(moves)
			if len(legacy) == 0 && len(tc.wantLegacyIdx) == 0 {
				return
			}
			if !slices.Equal(legacy, tc.wantLegacyIdx) {
				t.Fatalf("legacy paths %v, want %v", legacy, tc.wantLegacyIdx)
			}
		})
	}
}

func TestPlanRepoMovesPPAGlob(t *testing.T) {
	moves := ppaChannel.moves(func(p string) bool {
		return p == "/etc/apt/sources.list.d/avengemedia-ubuntu-dms-*.list"
	})
	legacy := LegacyRepoPaths(moves)
	if len(legacy) != 1 || legacy[0] != "/etc/apt/sources.list.d/avengemedia-ubuntu-dms-*.list" {
		t.Fatalf("legacy = %v, want the 22.04 .list glob for dms only", legacy)
	}
}

// filepath.Glob over a fake listing, where dux-* also matches the dux-repo-* sibling.
func globIn(files ...string) func(string) []string {
	return func(pattern string) []string {
		var matches []string
		for _, file := range files {
			if ok, _ := filepath.Match(pattern, file); ok {
				matches = append(matches, file)
			}
		}
		return matches
	}
}

func TestUbuntuRepoMovesIgnoreRetiredSiblingGlob(t *testing.T) {
	orig := repoGlob
	repoGlob = globIn(
		"/etc/apt/sources.list.d/duxlabs-ubuntu-dux-repo-resolute.sources",
		"/etc/apt/sources.list.d/avengemedia-ubuntu-danklinux-resolute.sources")
	t.Cleanup(func() { repoGlob = orig })

	moves := NewUbuntuDistribution(Registry["ubuntu"], nil).RepoMoves()
	want := []string{"/etc/apt/sources.list.d/avengemedia-ubuntu-danklinux-*.sources"}
	if got := LegacyRepoPaths(moves); !slices.Equal(got, want) {
		t.Fatalf("legacy = %v, want %v", got, want)
	}
	if adds := repoMoveAdds(moves); len(adds) != 0 {
		t.Fatalf("planned adds %v while dux-repo is present", adds)
	}
}

func fakeXBPSConfs(t *testing.T, files map[string]string) {
	t.Helper()
	origGlob, origRead := repoGlob, repoReadFile
	var paths []string
	for path := range files {
		paths = append(paths, path)
	}
	slices.Sort(paths)
	repoGlob = globIn(paths...)
	repoReadFile = func(path string) ([]byte, error) {
		content, ok := files[path]
		if !ok {
			return nil, os.ErrNotExist
		}
		return []byte(content), nil
	}
	t.Cleanup(func() { repoGlob, repoReadFile = origGlob, origRead })
}

func TestVoidRepoMoves(t *testing.T) {
	const (
		legacyDMS  = "repository=https://void.danklinux.com/dms/current\n"
		legacyDeps = "repository=https://void.danklinux.com/danklinux/current\n"
		newDMS     = "repository=https://void.duxlabs.dev/dms/current\n"
		newDeps    = "repository=https://void.duxlabs.dev/dux-repo/current\n"
	)
	cases := []struct {
		name       string
		files      map[string]string
		wantMoves  []string
		wantLegacy []string
		wantNew    bool
	}{
		{
			"both legacy",
			map[string]string{"/etc/xbps.d/dms.conf": legacyDMS, "/etc/xbps.d/danklinux.conf": "# dms deps\n" + legacyDeps, "/etc/xbps.d/00-repository-main.conf": "repository=https://repo-default.voidlinux.org/current\n"},
			[]string{
				"https://void.danklinux.com/danklinux/current -> https://void.duxlabs.dev/dux-repo/current",
				"https://void.danklinux.com/dms/current -> https://void.duxlabs.dev/dms/current",
			},
			[]string{"/etc/xbps.d/danklinux.conf", "/etc/xbps.d/dms.conf"},
			false,
		},
		{
			"one migrated",
			map[string]string{"/etc/xbps.d/dms.conf": newDMS, "/etc/xbps.d/dux.conf": legacyDeps},
			[]string{"https://void.danklinux.com/danklinux/current -> https://void.duxlabs.dev/dux-repo/current"},
			[]string{"/etc/xbps.d/dux.conf"},
			true,
		},
		{
			"both lines in one file",
			map[string]string{"/etc/xbps.d/custom.conf": legacyDMS + legacyDeps},
			[]string{
				"https://void.danklinux.com/dms/current -> https://void.duxlabs.dev/dms/current",
				"https://void.danklinux.com/danklinux/current -> https://void.duxlabs.dev/dux-repo/current",
			},
			[]string{"/etc/xbps.d/custom.conf"},
			false,
		},
		{"greeter only", map[string]string{"/etc/xbps.d/dms.conf": legacyDMS}, []string{"https://void.danklinux.com/dms/current -> https://void.duxlabs.dev/dms/current"}, []string{"/etc/xbps.d/dms.conf"}, false},
		{"all migrated", map[string]string{"/etc/xbps.d/dms.conf": newDMS, "/etc/xbps.d/dux.conf": newDeps}, nil, nil, true},
		{"none", map[string]string{"/etc/xbps.d/00-repository-main.conf": "repository=https://repo-default.voidlinux.org/current\n"}, nil, nil, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			fakeXBPSConfs(t, tc.files)
			v := NewVoidDistribution(Registry["void"], nil)
			moves, _ := PlanRepoMoves(v)
			var got []string
			newPresent := false
			for _, move := range moves {
				newPresent = newPresent || move.NewPresent
				if move.OldPresent {
					if move.NewPath != move.OldPath {
						t.Fatalf("%s must be edited in place, got NewPath %s", move.OldPath, move.NewPath)
					}
					got = append(got, move.Old+" -> "+move.New)
				}
			}
			if !slices.Equal(got, tc.wantMoves) {
				t.Fatalf("moves %q, want %q", got, tc.wantMoves)
			}
			if legacy := LegacyRepoPaths(moves); !slices.Equal(legacy, tc.wantLegacy) && len(legacy)+len(tc.wantLegacy) > 0 {
				t.Fatalf("legacy paths %v, want %v", legacy, tc.wantLegacy)
			}
			if newPresent != tc.wantNew {
				t.Fatalf("new repo present = %v, want %v", newPresent, tc.wantNew)
			}
			if commands := v.RepoMoveCommands(moves); (len(commands) == 0) != (len(tc.wantMoves) == 0) {
				t.Fatalf("commands %q for moves %q", commands, tc.wantMoves)
			}
		})
	}
}

func TestVoidMappingsUseNewHost(t *testing.T) {
	v := NewVoidDistribution(Registry["void"], nil)
	for _, variants := range []map[string]deps.PackageVariant{
		{"dms (Dux Shell)": deps.VariantStable, "dms-greeter": deps.VariantStable},
		{"dms (Dux Shell)": deps.VariantGit, "dms-greeter": deps.VariantGit},
	} {
		packages := v.GetPackageMappingWithVariants(deps.WindowManagerNiri, variants)
		want := map[string]string{
			"dms (Dux Shell)": "https://void.duxlabs.dev/dms/current",
			"dms-greeter":     "https://void.duxlabs.dev/dux-repo/current",
			"danksearch":      "https://void.duxlabs.dev/dux-repo/current",
			"dankcalendar":    "https://void.duxlabs.dev/dux-repo/current",
		}
		for dep, url := range want {
			if got := packages[dep].RepoURL; got != url {
				t.Errorf("%s (%s) RepoURL = %q, want %q", dep, packages[dep].Name, got, url)
			}
		}
	}
}

func TestRepoMoveCommands(t *testing.T) {
	withOrig := func(c repoChannel, present ...string) []RepoMove {
		return c.moves(existsIn(present...))
	}

	t.Run("fedora", func(t *testing.T) {
		f := NewFedoraDistribution(Registry["fedora"], nil)
		moves := withOrig(coprChannel, coprRepoFile("avengemedia/dms"), coprRepoFile("avengemedia/danklinux"), coprRepoFile("duxlabs/dms"))
		want := []string{
			"sudo dnf copr enable -y duxlabs/dux-repo",
			"sudo dnf copr remove -y avengemedia/dms",
			"sudo dnf copr remove -y avengemedia/danklinux",
		}
		if got := f.RepoMoveCommands(moves); !slices.Equal(got, want) {
			t.Fatalf("got %q, want %q", got, want)
		}
	})

	t.Run("fedora image-based", func(t *testing.T) {
		f := NewFedoraDistribution(Registry["fedora"], nil)
		moves := withOrig(coprChannel, coprRepoFile("avengemedia/danklinux"))
		want := []string{
			"sudo curl -fsSLo /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:duxlabs:dux-repo.repo https://copr.fedorainfracloud.org/coprs/duxlabs/dux-repo/repo/fedora-$(rpm -E %fedora)/duxlabs-dux-repo-fedora-$(rpm -E %fedora).repo",
			"sudo rm -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:avengemedia:danklinux.repo",
		}
		if got := f.ImageRepoMoveCommands(moves); !slices.Equal(got, want) {
			t.Fatalf("got %q, want %q", got, want)
		}
	})

	t.Run("fedora retired dux slug", func(t *testing.T) {
		f := NewFedoraDistribution(Registry["fedora"], nil)
		moves := withOrig(coprChannel, coprRepoFile("duxlabs/dux"))
		want := []string{
			"sudo dnf copr enable -y duxlabs/dux-repo",
			"sudo dnf copr remove -y duxlabs/dux",
		}
		if got := f.RepoMoveCommands(moves); !slices.Equal(got, want) {
			t.Fatalf("got %q, want %q", got, want)
		}
	})

	t.Run("ubuntu", func(t *testing.T) {
		u := NewUbuntuDistribution(Registry["ubuntu"], nil)
		moves := withOrig(ppaChannel, "/etc/apt/sources.list.d/avengemedia-ubuntu-danklinux-*.sources", "/etc/apt/sources.list.d/duxlabs-ubuntu-dux-*.sources")
		want := []string{
			"sudo add-apt-repository -y ppa:duxlabs/dux-repo",
			"sudo add-apt-repository -r -y ppa:avengemedia/danklinux",
			"sudo add-apt-repository -r -y ppa:duxlabs/dux",
			"sudo apt-get update",
		}
		if got := u.RepoMoveCommands(moves); !slices.Equal(got, want) {
			t.Fatalf("got %q, want %q", got, want)
		}
	})

	t.Run("debian", func(t *testing.T) {
		moves := withOrig(obsAptChannel, obsAptListFile("home:AvengeMedia:dms-git"))
		want := []string{
			"curl -fsSL https://download.opensuse.org/repositories/home:/duxlabs:/dms-git/Debian_13/Release.key | gpg --dearmor | sudo tee /etc/apt/keyrings/home-duxlabs-dms-git.gpg",
			"echo 'deb [signed-by=/etc/apt/keyrings/home-duxlabs-dms-git.gpg arch=amd64] https://download.opensuse.org/repositories/home:/duxlabs:/dms-git/Debian_13/ /' | sudo tee /etc/apt/sources.list.d/home-duxlabs-dms-git.list",
			"sudo rm -f /etc/apt/sources.list.d/home-AvengeMedia-dms-git.list /etc/apt/keyrings/home-AvengeMedia-dms-git.gpg",
			"sudo apt-get update",
		}
		if got := debianRepoMoveCommands(moves, "Debian_13", "amd64"); !slices.Equal(got, want) {
			t.Fatalf("got %q, want %q", got, want)
		}
	})

	t.Run("void", func(t *testing.T) {
		fakeXBPSConfs(t, map[string]string{
			"/etc/xbps.d/dms.conf": "repository=https://void.danklinux.com/dms/current\n",
			"/etc/xbps.d/dux.conf": "repository=https://void.danklinux.com/danklinux/current\n",
		})
		v := NewVoidDistribution(Registry["void"], nil)
		want := []string{
			"sudo sed -i 's|repository=https://void.danklinux.com/dms/current|repository=https://void.duxlabs.dev/dms/current|' /etc/xbps.d/dms.conf",
			"sudo sed -i 's|repository=https://void.danklinux.com/danklinux/current|repository=https://void.duxlabs.dev/dux-repo/current|' /etc/xbps.d/dux.conf",
			"sudo xbps-install -S",
		}
		if got := v.RepoMoveCommands(v.RepoMoves()); !slices.Equal(got, want) {
			t.Fatalf("got %q, want %q", got, want)
		}
	})

	t.Run("void greeter only", func(t *testing.T) {
		fakeXBPSConfs(t, map[string]string{"/etc/xbps.d/dms.conf": "repository=https://void.danklinux.com/dms/current\n"})
		v := NewVoidDistribution(Registry["void"], nil)
		want := []string{
			"sudo sed -i 's|repository=https://void.danklinux.com/dms/current|repository=https://void.duxlabs.dev/dms/current|' /etc/xbps.d/dms.conf",
			"sudo sh -c 'echo repository=https://void.duxlabs.dev/dux-repo/current >> /etc/xbps.d/dux.conf'",
			"sudo xbps-install -S",
		}
		if got := v.RepoMoveCommands(v.RepoMoves()); !slices.Equal(got, want) {
			t.Fatalf("got %q, want %q", got, want)
		}
	})

	// Either spelling of the deps line already serves the greeter, so no second dux.conf entry.
	for name, deps := range map[string]string{
		"legacy": "repository=https://void.danklinux.com/danklinux/current\n",
		"new":    "repository=https://void.duxlabs.dev/dux-repo/current\n",
	} {
		t.Run("void deps already "+name, func(t *testing.T) {
			fakeXBPSConfs(t, map[string]string{
				"/etc/xbps.d/dms.conf":       "repository=https://void.danklinux.com/dms/current\n",
				"/etc/xbps.d/danklinux.conf": deps,
			})
			v := NewVoidDistribution(Registry["void"], nil)
			for _, command := range v.RepoMoveCommands(v.RepoMoves()) {
				if strings.Contains(command, "dux.conf") {
					t.Fatalf("added a duplicate deps repo: %q", command)
				}
			}
		})
	}

	t.Run("opensuse", func(t *testing.T) {
		moves := withOrig(obsZypperChannel, obsZypperRepoFile("home:AvengeMedia:danklinux"))
		want := []string{
			"sudo zypper addrepo -f https://download.opensuse.org/repositories/home:/duxlabs:/dux-repo/openSUSE_Tumbleweed/home:duxlabs:dux-repo.repo",
			"sudo zypper --gpg-auto-import-keys refresh",
			"sudo zypper removerepo home_AvengeMedia_danklinux",
		}
		if got := opensuseRepoMoveCommands(moves, "openSUSE_Tumbleweed"); !slices.Equal(got, want) {
			t.Fatalf("got %q, want %q", got, want)
		}
	})
}

// Until OBS publishes, movers must plan nothing even with legacy files present, or doctor and migrate nag.
func TestOBSMigrationGate(t *testing.T) {
	if obsMigrationReady {
		t.Skip("gate open")
	}
	orig := repoPathExists
	repoPathExists = func(string) bool { return true }
	t.Cleanup(func() { repoPathExists = orig })

	if moves := NewDebianDistribution(Registry["debian"], nil).RepoMoves(); moves != nil {
		t.Fatalf("debian planned %v while the gate is closed", moves)
	}
	if moves := NewOpenSUSEDistribution(Registry["opensuse-tumbleweed"], nil).RepoMoves(); moves != nil {
		t.Fatalf("opensuse planned %v while the gate is closed", moves)
	}
	if got := NewDebianDistribution(Registry["debian"], nil).GetPackageMapping(0)["dms-greeter"].RepoURL; got != "home:AvengeMedia:danklinux" {
		t.Fatalf("debian mapping = %q, must stay on the legacy OBS project while the gate is closed", got)
	}
}

func TestSwapVariantsDisablesLegacyCOPR(t *testing.T) {
	var commands []string
	origExec, origExists := privescExec, repoPathExists
	privescExec = func(_ context.Context, _, command string) *exec.Cmd {
		commands = append(commands, command)
		return exec.Command("true")
	}
	repoPathExists = existsIn(coprRepoFile("avengemedia/dms"))
	t.Cleanup(func() { privescExec, repoPathExists = origExec, origExists })

	f := NewFedoraDistribution(Registry["fedora"], nil)
	swaps := []VariantSwap{{Dep: "dms (Dux Shell)", From: f.getDmsMapping(0), To: f.getDmsMapping(1)}}
	progress := make(chan InstallProgressMsg, 100)
	if err := f.SwapVariants(context.Background(), swaps, "", progress); err != nil {
		t.Fatal(err)
	}

	joined := strings.Join(commands, "\n")
	if !strings.Contains(joined, "dnf copr disable -y avengemedia/dms") {
		t.Fatalf("legacy COPR left enabled on an un-migrated host:\n%s", joined)
	}
	if strings.Contains(joined, "dnf copr disable -y duxlabs/dms") {
		t.Fatalf("disabled a COPR whose file does not exist:\n%s", joined)
	}
	if !strings.Contains(joined, "dnf copr enable -y duxlabs/dms-git") {
		t.Fatalf("new git COPR not enabled:\n%s", joined)
	}
}
