package sysupdate

import (
	"context"
	"encoding/json"
	"net"
	"testing"

	"github.com/duxlabs-dev/dux-go/ipc"
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

func TestRepoStatus(t *testing.T) {
	const legacyPath = "/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:avengemedia:danklinux.repo"
	mover := &repoMoverFake{moves: []distros.RepoMove{
		{Kind: distros.RepoTypeCOPR, Old: "avengemedia/danklinux", New: "duxlabs/dux-repo", OldPath: legacyPath, OldPresent: true},
		{Kind: distros.RepoTypeCOPR, Old: "avengemedia/dms", New: "duxlabs/dms", NewPresent: true},
	}}
	got, _ := json.Marshal(repoStatus(mover))
	want := `{"legacy":["` + legacyPath + `"],"command":"dms migrate dux"}`
	if string(got) != want {
		t.Fatalf("got %s, want %s", got, want)
	}

	for name, distro := range map[string]distros.Distribution{"no mover": &plainDistroFake{}, "nil": nil} {
		got, _ := json.Marshal(repoStatus(distro))
		if string(got) != `{"legacy":[],"command":"dms migrate dux"}` {
			t.Fatalf("%s: got %s, want an empty list, never null", name, got)
		}
	}
}

// The route needs no manager: a shell on a host without a mover must still get an empty list.
func TestRepoStatusRoute(t *testing.T) {
	server, client := net.Pipe()
	defer client.Close()
	go func() {
		HandleRequest(context.Background(), ipc.NewConnWriter(server), ipc.Request{ID: 7, Method: "sysupdate.repoStatus"}, nil)
		server.Close()
	}()
	var resp ipc.Response[RepoStatus]
	if err := json.NewDecoder(client).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if resp.ID != 7 || resp.Error != "" || resp.Result == nil || resp.Result.Command != "dms migrate dux" || resp.Result.Legacy == nil {
		t.Fatalf("got %+v", resp)
	}
}
