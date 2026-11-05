package network

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

func TestOpenConnectHelperOldCleanupPreservesNewerSharedAttempt(t *testing.T) {
	b := helperBackend("/active/one")
	defer b.cancelAllOpenConnectHelperAttempts()
	agent := &SecretAgent{backend: b}
	conn := helperAgentConnection("one")
	resolving, resumeResolution := make(chan struct{}), make(chan struct{})
	var resolves atomic.Int32
	b.openConnectActiveResolver = func(context.Context, string, dbus.ObjectPath) (dbus.ObjectPath, error) {
		if resolves.Add(1) == 1 {
			close(resolving)
			<-resumeResolution
		}
		return "/active/one", nil
	}
	queryStarted, resumeQuery, queryFinished := make(chan struct{}), make(chan struct{}), make(chan struct{})
	b.openConnectActivePathsReader = func(context.Context) ([]dbus.ObjectPath, error) {
		close(queryStarted)
		<-resumeQuery
		return nil, nil
	}
	runnerStarted := make(chan struct{})
	b.openConnectHelperRunner = func(ctx context.Context, _, _, _ string, _, _ map[string]string, _ bool) (*openConnectHelperResult, error) {
		close(runnerStarted)
		<-ctx.Done()
		return nil, ctx.Err()
	}
	oldDone, newDone := make(chan *dbus.Error, 1), make(chan *dbus.Error, 1)
	go func() {
		_, err := agent.GetSecrets(conn, "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction)
		oldDone <- err
	}()
	<-resolving
	go func() { defer close(queryFinished); b.cleanupOpenConnectHelperAttempts() }()
	<-queryStarted
	go func() {
		_, err := agent.GetSecrets(conn, "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction)
		newDone <- err
	}()
	<-runnerStarted
	key := openConnectHelperAttemptKey{uuid: "one", activePath: "/active/one"}
	b.openConnectHelperMu.Lock()
	newer := b.openConnectHelperAttempts[key]
	b.openConnectHelperMu.Unlock()
	close(resumeResolution)
	deadline := time.Now().Add(time.Second)
	for {
		b.openConnectHelperMu.Lock()
		attached := 0
		for r := range b.openConnectHelperRequests {
			if r.attempt == newer {
				attached++
			}
		}
		b.openConnectHelperMu.Unlock()
		if attached == 2 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("old request did not join")
		}
		time.Sleep(time.Millisecond)
	}
	close(resumeQuery)
	<-queryFinished
	if newer.ctx.Err() != nil || !b.ownsOpenConnectHelperAttempt(key, newer) {
		t.Fatal("old query cancelled helper created by newer request after snapshot")
	}
	b.cancelAllOpenConnectHelperAttempts()
	<-oldDone
	<-newDone
}
