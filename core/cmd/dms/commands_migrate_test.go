package main

import (
	"bytes"
	"context"
	"slices"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
)

type repoMoverFake struct {
	distros.Distribution
	moves []distros.RepoMove
}

func (f *repoMoverFake) RepoMoves() []distros.RepoMove { return f.moves }
func (f *repoMoverFake) ApplyRepoMoves(context.Context, []distros.RepoMove, string, chan<- distros.InstallProgressMsg) error {
	return nil
}
func (f *repoMoverFake) RepoMoveCommands([]distros.RepoMove) []string { return nil }

type plainDistroFake struct{ distros.Distribution }

func TestRunWithProgressOutputPrintsRepeatedLinesOnce(t *testing.T) {
	var out bytes.Buffer
	err := runWithProgressOutputTo(&out, func(ch chan<- distros.InstallProgressMsg) error {
		ch <- distros.InstallProgressMsg{Step: "Removing COPR repo...", LogOutput: "Repository successfully removed."}
		ch <- distros.InstallProgressMsg{Step: "Removing COPR repo...", LogOutput: "Repository successfully removed."}
		ch <- distros.InstallProgressMsg{Step: "Removing COPR repo...", LogOutput: "Repository successfully removed."}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	want := "Removing COPR repo...\n    Repository successfully removed.\n"
	if out.String() != want {
		t.Fatalf("got %q, want %q", out.String(), want)
	}
}

func TestCheckPackageRepos(t *testing.T) {
	legacy := distros.RepoMove{Kind: distros.RepoTypeCOPR, Old: "avengemedia/dms", New: "duxlabs/dms", OldPath: "/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:avengemedia:dms.repo", OldPresent: true}
	legacyDeps := distros.RepoMove{Kind: distros.RepoTypeCOPR, Old: "avengemedia/danklinux", New: "duxlabs/dux-repo", OldPath: "/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:avengemedia:danklinux.repo", OldPresent: true}
	current := distros.RepoMove{Kind: distros.RepoTypeCOPR, Old: "avengemedia/dms", New: "duxlabs/dms", NewPresent: true}
	absent := distros.RepoMove{Kind: distros.RepoTypeCOPR, Old: "avengemedia/dms", New: "duxlabs/dms"}

	cases := []struct {
		name    string
		moves   []distros.RepoMove
		status  status
		message string
	}{
		{"legacy", []distros.RepoMove{legacy, legacyDeps, current}, statusWarn, "Legacy repositories, run: dms migrate dux"},
		{"current", []distros.RepoMove{current, absent}, statusOK, "Current"},
		{"none", []distros.RepoMove{absent}, statusInfo, "No DMS package repositories"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			results := packageReposResult(&repoMoverFake{moves: tc.moves})
			if len(results) != 1 || results[0].status != tc.status || results[0].message != tc.message {
				t.Fatalf("got %+v, want %v %q", results, tc.status, tc.message)
			}
			if tc.status == statusWarn && results[0].details != legacy.OldPath+", "+legacyDeps.OldPath {
				t.Fatalf("details = %q, want the legacy paths on one line", results[0].details)
			}
		})
	}

	voidConf := "/etc/xbps.d/custom.conf"
	voidMoves := []distros.RepoMove{
		{Kind: distros.RepoTypeXBPS, Old: "https://void.danklinux.com/dms/current", New: "https://void.duxlabs.dev/dms/current", OldPath: voidConf, NewPath: voidConf, OldPresent: true},
		{Kind: distros.RepoTypeXBPS, Old: "https://void.danklinux.com/danklinux/current", New: "https://void.duxlabs.dev/dux-repo/current", OldPath: voidConf, NewPath: voidConf, OldPresent: true},
	}
	if results := packageReposResult(&repoMoverFake{moves: voidMoves}); len(results) != 1 || results[0].status != statusWarn || results[0].details != voidConf {
		t.Fatalf("got %+v, want one warning naming %s once", results, voidConf)
	}

	if results := packageReposResult(&plainDistroFake{}); results != nil {
		t.Fatalf("printed %+v on a family without repo moves", results)
	}
}

func TestRepoMoveRows(t *testing.T) {
	moves := []distros.RepoMove{
		{Kind: distros.RepoTypeCOPR, Old: "avengemedia/dms", New: "duxlabs/dms", OldPath: "/etc/yum.repos.d/a.repo", NewPath: "/etc/yum.repos.d/b.repo", OldPresent: true},
		{Kind: distros.RepoTypeCOPR, Old: "avengemedia/dms-git", New: "duxlabs/dms-git", OldPath: "/etc/yum.repos.d/c.repo", NewPath: "/etc/yum.repos.d/d.repo"},
		{Kind: distros.RepoTypeXBPS, New: "https://void.duxlabs.dev/dux-repo/current", NewPath: "/etc/xbps.d/dux.conf"},
	}
	want := []string{"  avengemedia/dms → duxlabs/dms", "  add https://void.duxlabs.dev/dux-repo/current"}
	if got := repoMoveRows(moves); !slices.Equal(got, want) {
		t.Fatalf("got %q, want %q", got, want)
	}
}
