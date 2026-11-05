package network

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	mock_gonetworkmanager "github.com/AvengeMedia/DankMaterialShell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/godbus/dbus/v5"
)

func helperAgentConnection(uuid string) map[string]nmVariantMap {
	return map[string]nmVariantMap{
		"connection": {
			"type": dbus.MakeVariant("vpn"), "id": dbus.MakeVariant("AnyConnect"), "uuid": dbus.MakeVariant(uuid),
		},
		"vpn": {
			"service-type": dbus.MakeVariant(openConnectHelperService),
			"data": dbus.MakeVariant(map[string]string{
				"protocol": "anyconnect", "cookie-flags": "2", "gateway-flags": "2", "gwcert-flags": "2", "resolve-flags": "2",
			}),
			"secrets": dbus.MakeVariant(map[string]string{"password": "old-password", "form:main:username": "alice"}),
		},
	}
}

func helperBackend(path dbus.ObjectPath) *NetworkManagerBackend {
	return &NetworkManagerBackend{
		state: &BackendState{},
		openConnectActiveResolver: func(_ context.Context, uuid string, settingsPath dbus.ObjectPath) (dbus.ObjectPath, error) {
			return path, nil
		},
		openConnectHelperFinder: func() (string, error) { return "/trusted/helper", nil },
		openConnectHelperRunner: func(_ context.Context, _, _, _ string, _, metadata map[string]string, _ bool) (*openConnectHelperResult, error) {
			if metadata["password"] != "" || metadata["form:main:username"] != "alice" {
				return nil, errOpenConnectHelperInvalidInput
			}
			return &openConnectHelperResult{
				Secrets:  map[string]string{"cookie": "new", "gateway": "vpn.example", "gwcert": "", "resolve": ""},
				Metadata: map[string]string{"form:main:group_list": "staff"},
			}, nil
		},
	}
}

// Install attempts without running authentication to control lifecycle interleavings.
func newHelperAttemptForTest(backend *NetworkManagerBackend, key openConnectHelperAttemptKey, settingsPath dbus.ObjectPath) (*openConnectHelperAttempt, bool, error) {
	backend.openConnectHelperMu.Lock()
	defer backend.openConnectHelperMu.Unlock()
	return backend.openConnectAttemptLocked(key, settingsPath, nil)
}

func TestOpenConnectHelperAgentSharesActiveAttempt(t *testing.T) {
	var mu sync.Mutex
	runs := 0
	started := make(chan struct{})
	release := make(chan struct{})
	backend := helperBackend("/org/freedesktop/NetworkManager/ActiveConnection/7")
	backend.openConnectHelperRunner = func(ctx context.Context, _, _, _ string, _, metadata map[string]string, _ bool) (*openConnectHelperResult, error) {
		mu.Lock()
		runs++
		mu.Unlock()
		if metadata["password"] != "" || metadata["form:main:username"] != "alice" {
			t.Errorf("unexpected helper metadata: %#v", metadata)
		}
		close(started)
		select {
		case <-release:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
		return &openConnectHelperResult{Secrets: map[string]string{"cookie": "new", "gateway": "vpn.example", "gwcert": "", "resolve": ""}}, nil
	}
	agent := &SecretAgent{backend: backend}
	conn := helperAgentConnection("one")
	responses := make(chan nmSettingMap, 2)
	errs := make(chan *dbus.Error, 2)
	for range 2 {
		go func() {
			out, err := agent.GetSecrets(conn, "/org/freedesktop/NetworkManager/Settings/1", "vpn", nil, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagUserRequested)
			responses <- out
			errs <- err
		}()
	}
	<-started
	close(release)
	for range 2 {
		if err := <-errs; err != nil {
			t.Fatal(err)
		}
		out := <-responses
		secrets := out["vpn"]["secrets"].Value().(map[string]string)
		if len(secrets) != 4 || secrets["cookie"] != "new" {
			t.Fatalf("unexpected response: %#v", secrets)
		}
	}
	mu.Lock()
	defer mu.Unlock()
	if runs != 1 {
		t.Fatalf("helper ran %d times", runs)
	}
}

func TestOpenConnectHelperStagesMetadataUntilSuccess(t *testing.T) {
	activePath := dbus.ObjectPath("/active/one")
	backend := helperBackend(activePath)
	saved := make(chan map[string]string, 2)
	backend.openConnectMetadataSaver = func(ctx context.Context, _ openConnectHelperAttemptKey, _ *openConnectHelperAttempt, _ dbus.ObjectPath, metadata map[string]string) error {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case saved <- cloneOpenConnectStrings(metadata):
			return nil
		}
	}
	agent := &SecretAgent{backend: backend}
	if _, err := agent.GetSecrets(helperAgentConnection("one"), "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagUserRequested); err != nil {
		t.Fatal(err)
	}
	select {
	case got := <-saved:
		t.Fatalf("metadata saved before activation success: %#v", got)
	default:
	}
	backend.finishOpenConnectHelperSuccess(activePath)
	backend.finishOpenConnectHelperSuccess(activePath)
	select {
	case got := <-saved:
		if got["form:main:username"] != "alice" || got["form:main:group_list"] != "staff" || got["password"] != "" || got["cookie"] != "" {
			t.Fatalf("unsafe staged metadata: %#v", got)
		}
	case <-time.After(time.Second):
		t.Fatal("success did not save staged metadata")
	}
	select {
	case <-saved:
		t.Fatal("duplicate success saved metadata twice")
	case <-time.After(50 * time.Millisecond):
	}
	backend.openConnectHelperMu.Lock()
	defer backend.openConnectHelperMu.Unlock()
	if len(backend.openConnectHelperAttempts) != 0 {
		t.Fatal("successful save retained helper record")
	}
}

func TestOpenConnectHelperFailureAndCancellationDropStagedMetadata(t *testing.T) {
	activePath := dbus.ObjectPath("/active/one")
	backend := helperBackend(activePath)
	saved := make(chan struct{}, 1)
	backend.openConnectMetadataSaver = func(context.Context, openConnectHelperAttemptKey, *openConnectHelperAttempt, dbus.ObjectPath, map[string]string) error {
		saved <- struct{}{}
		return nil
	}
	agent := &SecretAgent{backend: backend}
	if _, err := agent.GetSecrets(helperAgentConnection("one"), "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction); err != nil {
		t.Fatal(err)
	}
	backend.clearOpenConnectHelperAttempt(activePath)
	select {
	case <-saved:
		t.Fatal("failure saved metadata")
	case <-time.After(50 * time.Millisecond):
	}
	backend.cancelAllOpenConnectHelperAttempts()
	backend.openConnectHelperMu.Lock()
	defer backend.openConnectHelperMu.Unlock()
	if len(backend.openConnectHelperAttempts) != 0 || !backend.openConnectHelperClosed {
		t.Fatal("shutdown retained helper state")
	}
}

func TestOpenConnectHelperSuccessSaveCancelsWithProfile(t *testing.T) {
	activePath := dbus.ObjectPath("/active/one")
	backend := helperBackend(activePath)
	started := make(chan struct{})
	cancelled := make(chan struct{})
	backend.openConnectMetadataSaver = func(ctx context.Context, _ openConnectHelperAttemptKey, _ *openConnectHelperAttempt, _ dbus.ObjectPath, _ map[string]string) error {
		close(started)
		<-ctx.Done()
		close(cancelled)
		return ctx.Err()
	}
	agent := &SecretAgent{backend: backend}
	if _, err := agent.GetSecrets(helperAgentConnection("one"), "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction); err != nil {
		t.Fatal(err)
	}
	backend.finishOpenConnectHelperSuccess(activePath)
	<-started
	agent.CancelGetSecrets("/settings/one", "vpn")
	select {
	case <-cancelled:
	case <-time.After(time.Second):
		t.Fatal("profile cancellation did not cancel metadata save")
	}
}

func TestOpenConnectHelperAgentNonInteractiveAndRequestNew(t *testing.T) {
	var mu sync.Mutex
	runs := 0
	requests := []bool{}
	backend := helperBackend("/active/1")
	backend.openConnectHelperRunner = func(_ context.Context, _, _, _ string, _, _ map[string]string, requestNew bool) (*openConnectHelperResult, error) {
		mu.Lock()
		defer mu.Unlock()
		runs++
		requests = append(requests, requestNew)
		return &openConnectHelperResult{Secrets: map[string]string{"cookie": "cookie", "gateway": "vpn.example", "gwcert": "", "resolve": ""}}, nil
	}
	agent := &SecretAgent{backend: backend}
	conn := helperAgentConnection("one")
	if _, err := agent.GetSecrets(conn, "/settings/1", "vpn", nil, nmSecretAgentFlagUserRequested); err == nil || err.Name != "org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets" {
		t.Fatalf("noninteractive result: %v", err)
	}
	if len(backend.openConnectHelperAttempts) != 0 {
		t.Fatal("noninteractive request created an authentication attempt")
	}
	if _, err := agent.GetSecrets(conn, "/settings/1", "vpn", nil, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagUserRequested); err != nil {
		t.Fatal(err)
	}
	if out, err := agent.GetSecrets(conn, "/settings/1", "vpn", nil, nmSecretAgentFlagUserRequested); err != nil || out["vpn"]["secrets"].Value().(map[string]string)["cookie"] != "cookie" {
		t.Fatalf("noninteractive cache result: %#v, %v", out, err)
	}
	if _, err := agent.GetSecrets(conn, "/settings/1", "vpn", nil, nmSecretAgentFlagRequestNew); err == nil || err.Name != "org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets" {
		t.Fatalf("noninteractive request-new result: %v", err)
	}
	if len(backend.openConnectHelperAttempts) != 0 {
		t.Fatal("request-new did not invalidate cached attempt")
	}
	if _, err := agent.GetSecrets(conn, "/settings/1", "vpn", nil, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagRequestNew); err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	defer mu.Unlock()
	if runs != 2 || len(requests) != 2 || requests[0] || !requests[1] {
		t.Fatalf("runs=%d requestNew=%v", runs, requests)
	}
}

func TestOpenConnectHelperOldSignalAndTimeoutDoNotRetainAttempts(t *testing.T) {
	backend := &NetworkManagerBackend{openConnectHelperAttempts: make(map[openConnectHelperAttemptKey]*openConnectHelperAttempt), openConnectHelperAttemptTimeout: 20 * time.Millisecond}
	old, _, err := newHelperAttemptForTest(backend, openConnectHelperAttemptKey{uuid: "one", activePath: "/active/old"}, "/settings/one")
	if err != nil {
		t.Fatal(err)
	}
	backend.openConnectHelperMu.Lock()
	backend.cancelOpenConnectHelperAttemptLocked(openConnectHelperAttemptKey{uuid: "one", activePath: "/active/old"}, old)
	backend.openConnectHelperMu.Unlock()
	newAttempt, _, err := newHelperAttemptForTest(backend, openConnectHelperAttemptKey{uuid: "one", activePath: "/active/new"}, "/settings/one")
	if err != nil {
		t.Fatal(err)
	}
	backend.finishOpenConnectHelperSuccess("/active/old")
	backend.openConnectHelperMu.Lock()
	if backend.openConnectHelperAttempts[openConnectHelperAttemptKey{uuid: "one", activePath: "/active/new"}] != newAttempt {
		backend.openConnectHelperMu.Unlock()
		t.Fatal("old signal cleared new generation")
	}
	backend.openConnectHelperMu.Unlock()
	select {
	case <-newAttempt.done:
	case <-time.After(time.Second):
		t.Fatal("attempt expiry did not release waiter")
	}
	backend.openConnectHelperMu.Lock()
	defer backend.openConnectHelperMu.Unlock()
	if len(backend.openConnectHelperAttempts) != 0 {
		t.Fatal("expired attempt retained in registry")
	}
}

func TestOpenConnectHelperAgentRejectsUnpreparedExternalProfile(t *testing.T) {
	backend := &NetworkManagerBackend{state: &BackendState{}}
	agent := &SecretAgent{backend: backend}
	conn := helperAgentConnection("one")
	data, _ := readOpenConnectDataAndSecrets(conn)
	delete(data, "resolve-flags")
	conn["vpn"]["data"] = dbus.MakeVariant(data)
	_, err := agent.GetSecrets(conn, "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagUserRequested)
	if err == nil || err.Name != "org.freedesktop.DBus.Error.Failed" || err.Body[0] != "this profile must be connected once from DMS before external activation" {
		t.Fatalf("unexpected unprepared profile error: %#v", err)
	}
}

func TestOpenConnectHelperPausedResolutionLifecycle(t *testing.T) {
	for _, event := range []string{"cancel", "close", "terminal", "success", "removal", "unrelated-terminal", "unrelated-success", "unrelated-removal", "unrelated-cancel", "retired-overflow"} {
		t.Run(event, func(t *testing.T) {
			backend := helperBackend("/active/one")
			t.Cleanup(backend.cancelAllOpenConnectHelperAttempts)
			agent := &SecretAgent{backend: backend}
			started := make(chan context.Context, 1)
			release := make(chan struct{})
			backend.openConnectActiveResolver = func(ctx context.Context, _ string, _ dbus.ObjectPath) (dbus.ObjectPath, error) {
				started <- ctx
				<-release // Deliberately return a stale result even after cancellation.
				return "/active/one", nil
			}
			var runs atomic.Int32
			runner := backend.openConnectHelperRunner
			backend.openConnectHelperRunner = func(ctx context.Context, path, uuid, name string, data, metadata map[string]string, requestNew bool) (*openConnectHelperResult, error) {
				runs.Add(1)
				return runner(ctx, path, uuid, name, data, metadata, requestNew)
			}
			done := make(chan *dbus.Error, 1)
			go func() {
				_, err := agent.GetSecrets(helperAgentConnection("one"), "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction)
				done <- err
			}()
			ctx := <-started
			wantSuccess := false
			switch event {
			case "cancel":
				agent.CancelGetSecrets("/settings/one", "vpn")
			case "close":
				agent.Close()
				backend.reopenOpenConnectHelperAttempts() // Reopening must not revive old tokens.
			case "terminal":
				backend.clearOpenConnectHelperAttempt("/active/one")
			case "success":
				backend.finishOpenConnectHelperSuccess("/active/one")
			case "removal":
				backend.reconcileOpenConnectHelperSnapshot(backend.snapshotOpenConnectHelperAttempts(), []dbus.ObjectPath{"/active/other"})
				backend.reconcileOpenConnectHelperSnapshot(backend.snapshotOpenConnectHelperAttempts(), []dbus.ObjectPath{"/active/one", "/active/other"})
			case "unrelated-terminal":
				backend.clearOpenConnectHelperAttempt("/active/other")
				wantSuccess = true
			case "unrelated-success":
				backend.finishOpenConnectHelperSuccess("/active/other")
				wantSuccess = true
			case "unrelated-removal":
				backend.reconcileOpenConnectHelperSnapshot(backend.snapshotOpenConnectHelperAttempts(), []dbus.ObjectPath{"/active/one"})
				wantSuccess = true
			case "unrelated-cancel":
				agent.CancelGetSecrets("/settings/other", "vpn")
				wantSuccess = true
			case "retired-overflow":
				for i := range openConnectHelperRetiredPathLimit + 1 {
					backend.clearOpenConnectHelperAttempt(dbus.ObjectPath(fmt.Sprintf("/active/other%d", i)))
				}
			}
			if (event == "cancel" || event == "close" || event == "retired-overflow") && ctx.Err() == nil {
				t.Error("resolver context was not cancelled")
			}
			close(release)
			select {
			case err := <-done:
				if wantSuccess {
					if err != nil || runs.Load() != 1 {
						t.Fatalf("unrelated event affected request: err=%v runs=%d", err, runs.Load())
					}
				} else if err == nil || err.Name != "org.freedesktop.NetworkManager.SecretAgent.Error.UserCanceled" || runs.Load() != 0 {
					t.Fatalf("stale request launched helper: err=%v runs=%d", err, runs.Load())
				}
			case <-time.After(time.Second):
				t.Fatal("request did not return")
			}
			backend.openConnectHelperMu.Lock()
			defer backend.openConnectHelperMu.Unlock()
			if len(backend.openConnectHelperRequests) != 0 || (!wantSuccess && len(backend.openConnectHelperAttempts) != 0) {
				t.Fatal("request retained lifecycle state")
			}
		})
	}
}

func TestOpenConnectHelperResolverContextCancellationAndTimeout(t *testing.T) {
	for _, cancelRequest := range []bool{true, false} {
		t.Run(fmt.Sprint(cancelRequest), func(t *testing.T) {
			backend := helperBackend("/active/one")
			t.Cleanup(backend.cancelAllOpenConnectHelperAttempts)
			if !cancelRequest {
				backend.openConnectHelperAttemptTimeout = 20 * time.Millisecond
			}
			started := make(chan struct{})
			backend.openConnectActiveResolver = func(ctx context.Context, _ string, _ dbus.ObjectPath) (dbus.ObjectPath, error) {
				close(started)
				<-ctx.Done()
				return "", ctx.Err()
			}
			backend.openConnectHelperFinder = func() (string, error) {
				t.Error("cancelled resolution reached finder")
				return "", errOpenConnectHelperCancelled
			}
			agent := &SecretAgent{backend: backend}
			done := make(chan *dbus.Error, 1)
			go func() {
				_, err := agent.GetSecrets(helperAgentConnection("one"), "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction)
				done <- err
			}()
			<-started
			if cancelRequest {
				agent.CancelGetSecrets("/settings/one", "vpn")
			}
			select {
			case err := <-done:
				if err == nil {
					t.Fatal("cancelled resolver succeeded")
				}
			case <-time.After(time.Second):
				t.Fatal("resolver ignored cancellation/timeout")
			}
			backend.openConnectHelperMu.Lock()
			defer backend.openConnectHelperMu.Unlock()
			if len(backend.openConnectHelperRequests) != 0 || len(backend.openConnectHelperAttempts) != 0 {
				t.Fatal("resolver retained state")
			}
		})
	}
}

func TestOpenConnectHelperPendingRequestNewJoins(t *testing.T) {
	for _, firstNew := range []bool{false, true} {
		t.Run(fmt.Sprint(firstNew), func(t *testing.T) {
			backend := helperBackend("/active/one")
			t.Cleanup(backend.cancelAllOpenConnectHelperAttempts)
			started := make(chan struct{}, 2)
			release := make(chan struct{})
			var runs atomic.Int32
			backend.openConnectHelperRunner = func(ctx context.Context, _, _, _ string, _, _ map[string]string, _ bool) (*openConnectHelperResult, error) {
				runs.Add(1)
				started <- struct{}{}
				select {
				case <-release:
					return &openConnectHelperResult{Secrets: map[string]string{"cookie": "fresh", "gateway": "vpn.example", "gwcert": "", "resolve": ""}}, nil
				case <-ctx.Done():
					return nil, ctx.Err()
				}
			}
			agent := &SecretAgent{backend: backend}
			conn := helperAgentConnection("one")
			done := make(chan *dbus.Error, 2)
			flags := uint32(nmSecretAgentFlagAllowInteraction)
			if firstNew {
				flags |= nmSecretAgentFlagRequestNew
			}
			go func() {
				_, err := agent.GetSecrets(conn, "/settings/one", "vpn", nil, flags)
				done <- err
			}()
			<-started
			if _, err := agent.GetSecrets(conn, "/settings/one", "vpn", nil, nmSecretAgentFlagRequestNew); err == nil || err.Name != "org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets" {
				t.Fatalf("noninteractive pending REQUEST_NEW: %v", err)
			}
			secondResolved := make(chan struct{})
			backend.openConnectActiveResolver = func(context.Context, string, dbus.ObjectPath) (dbus.ObjectPath, error) {
				close(secondResolved)
				return "/active/one", nil
			}
			go func() {
				_, err := agent.GetSecrets(conn, "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagRequestNew)
				done <- err
			}()
			<-secondResolved
			deadline := time.After(time.Second)
			for {
				backend.openConnectHelperMu.Lock()
				pending := 0
				for request := range backend.openConnectHelperRequests {
					if request.activePath == "" {
						pending++
					}
				}
				backend.openConnectHelperMu.Unlock()
				if pending == 0 {
					break
				}
				select {
				case <-deadline:
					t.Fatal("second request did not join")
				case <-time.After(time.Millisecond):
				}
			}
			close(release)
			for range 2 {
				select {
				case err := <-done:
					if err != nil {
						t.Fatalf("overlapping request cancelled another waiter: %v", err)
					}
				case <-time.After(time.Second):
					t.Fatal("waiter did not complete")
				}
			}
			if runs.Load() != 1 {
				t.Fatalf("overlapping requests ran %d helpers", runs.Load())
			}
		})
	}
}

func TestOpenConnectHelperRequestLimitAndIndependentWaiters(t *testing.T) {
	backend := helperBackend("/active/one")
	t.Cleanup(backend.cancelAllOpenConnectHelperAttempts)
	key := openConnectHelperAttemptKey{uuid: "one", activePath: "/active/one"}
	attempt, _, err := newHelperAttemptForTest(backend, key, "/settings/one")
	if err != nil {
		t.Fatal(err)
	}
	for range openConnectHelperAttemptLimit - 1 {
		request, err := backend.beginOpenConnectHelperRequest("/settings/one", false)
		if err != nil {
			t.Fatal(err)
		}
		defer backend.endOpenConnectHelperRequest(request)
	}
	if _, err := backend.beginOpenConnectHelperRequest("/settings/other", false); err == nil {
		t.Fatal("pending requests bypassed combined registry limit")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := backend.openConnectHelperResult(ctx, key, attempt); err != context.Canceled {
		t.Fatalf("waiter cancellation: %v", err)
	}
	if attempt.ctx.Err() != nil {
		t.Fatal("one waiter cancelled shared helper")
	}
	backend.runOpenConnectHelperAttempt(key, attempt, "AnyConnect", nil, map[string]string{"form:main:username": "alice"}, false)
	if result, err := backend.openConnectHelperResult(context.Background(), key, attempt); err != nil || result.Secrets["cookie"] != "new" {
		t.Fatalf("independent waiter failed: %#v %v", result, err)
	}
}

func TestOpenConnectHelperRequestNewInvalidatesCompletedResultAndError(t *testing.T) {
	for _, firstFails := range []bool{false, true} {
		t.Run(fmt.Sprint(firstFails), func(t *testing.T) {
			backend := helperBackend("/active/one")
			t.Cleanup(backend.cancelAllOpenConnectHelperAttempts)
			var runs atomic.Int32
			backend.openConnectHelperRunner = func(_ context.Context, _, _, _ string, _, _ map[string]string, requestNew bool) (*openConnectHelperResult, error) {
				call := runs.Add(1)
				if call == 1 && firstFails {
					return nil, errOpenConnectHelperMalformed
				}
				if call == 2 && !requestNew {
					t.Error("replacement did not request fresh authentication")
				}
				return &openConnectHelperResult{Secrets: map[string]string{"cookie": fmt.Sprint(call), "gateway": "vpn.example", "gwcert": "", "resolve": ""}}, nil
			}
			agent := &SecretAgent{backend: backend}
			conn := helperAgentConnection("one")
			_, err := agent.GetSecrets(conn, "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction)
			if (err != nil) != firstFails {
				t.Fatalf("initial result: %v", err)
			}
			out, err := agent.GetSecrets(conn, "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagRequestNew)
			if err != nil || runs.Load() != 2 || out["vpn"]["secrets"].Value().(map[string]string)["cookie"] != "2" {
				t.Fatalf("completed result was not invalidated: %#v %v runs=%d", out, err, runs.Load())
			}
		})
	}
}

func TestOpenConnectHelperRequestNewPausedResolutionReusesConcurrentResult(t *testing.T) {
	for _, interactive := range []bool{false, true} {
		for _, firstReadsBeforeResume := range []bool{false, true} {
			t.Run(fmt.Sprintf("interactive=%t/first-read=%t", interactive, firstReadsBeforeResume), func(t *testing.T) {
				backend := helperBackend("/active/one")
				t.Cleanup(backend.cancelAllOpenConnectHelperAttempts)
				started, releaseRunner := make(chan struct{}), make(chan struct{})
				var runs atomic.Int32
				backend.openConnectHelperRunner = func(ctx context.Context, _, _, _ string, _, _ map[string]string, requestNew bool) (*openConnectHelperResult, error) {
					n := runs.Add(1)
					if n == 1 {
						close(started)
						select {
						case <-releaseRunner:
						case <-ctx.Done():
							return nil, ctx.Err()
						}
					} else if !requestNew {
						t.Error("future refresh lost REQUEST_NEW runner flag")
					}
					return &openConnectHelperResult{Secrets: map[string]string{"cookie": fmt.Sprint(n), "gateway": "vpn.example", "gwcert": "", "resolve": ""}}, nil
				}
				key := openConnectHelperAttemptKey{uuid: "one", activePath: "/active/one"}
				first, _, err := newHelperAttemptForTest(backend, key, "/settings/one")
				if err != nil {
					t.Fatal(err)
				}
				go backend.runOpenConnectHelperAttempt(key, first, "AnyConnect", nil, nil, true)
				<-started
				resolving, resume := make(chan struct{}), make(chan struct{})
				var resolves atomic.Int32
				backend.openConnectActiveResolver = func(context.Context, string, dbus.ObjectPath) (dbus.ObjectPath, error) {
					if resolves.Add(1) == 1 {
						close(resolving)
						<-resume
					}
					return key.activePath, nil
				}
				agent := &SecretAgent{backend: backend}
				type response struct {
					out nmSettingMap
					err *dbus.Error
				}
				done := make(chan response, 1)
				go func() {
					flags := uint32(nmSecretAgentFlagRequestNew)
					if interactive {
						flags |= nmSecretAgentFlagAllowInteraction
					}
					out, err := agent.GetSecrets(helperAgentConnection("one"), "/settings/one", "vpn", nil, flags)
					done <- response{out, err}
				}()
				<-resolving
				close(releaseRunner)
				<-first.done
				readFirst := func() {
					out, err := backend.openConnectHelperResult(context.Background(), key, first)
					if err != nil || out.Secrets["cookie"] != "1" {
						t.Fatalf("first waiter lost its fresh result: %#v %v", out, err)
					}
				}
				if firstReadsBeforeResume {
					readFirst()
				}
				close(resume)
				select {
				case response := <-done:
					if response.err != nil || response.out["vpn"]["secrets"].Value().(map[string]string)["cookie"] != "1" || runs.Load() != 1 {
						t.Fatalf("concurrent freshness lost: %#v %v runs=%d", response.out, response.err, runs.Load())
					}
				case <-time.After(time.Second):
					t.Fatal("second waiter did not finish")
				}
				if !firstReadsBeforeResume {
					readFirst()
				}
				out, dbusErr := agent.GetSecrets(helperAgentConnection("one"), "/settings/one", "vpn", nil, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagRequestNew)
				if dbusErr != nil || out["vpn"]["secrets"].Value().(map[string]string)["cookie"] != "2" || runs.Load() != 2 {
					t.Fatalf("future REQUEST_NEW did not refresh: %#v %v runs=%d", out, dbusErr, runs.Load())
				}
			})
		}
	}
}

func TestOpenConnectHelperTerminalSuccessCancelsUnfinishedAndFailedAttempts(t *testing.T) {
	for _, failed := range []bool{false, true} {
		t.Run(fmt.Sprint(failed), func(t *testing.T) {
			backend := helperBackend("/active/one")
			t.Cleanup(backend.cancelAllOpenConnectHelperAttempts)
			started, release, finished := make(chan struct{}), make(chan struct{}), make(chan struct{})
			backend.openConnectHelperRunner = func(context.Context, string, string, string, map[string]string, map[string]string, bool) (*openConnectHelperResult, error) {
				close(started)
				if failed {
					return nil, errOpenConnectHelperMalformed
				}
				<-release // Even an uncooperative runner must not restore state after success.
				return &openConnectHelperResult{Secrets: map[string]string{"cookie": "late", "gateway": "vpn.example", "gwcert": "", "resolve": ""}}, nil
			}
			key := openConnectHelperAttemptKey{uuid: "one", activePath: "/active/one"}
			attempt, _, err := newHelperAttemptForTest(backend, key, "/settings/one")
			if err != nil {
				t.Fatal(err)
			}
			go func() {
				defer close(finished)
				backend.runOpenConnectHelperAttempt(key, attempt, "AnyConnect", nil, nil, false)
			}()
			<-started
			if failed {
				<-finished
			}
			backend.finishOpenConnectHelperSuccess(key.activePath)
			if attempt.ctx.Err() == nil {
				t.Error("terminal success did not cancel obsolete attempt")
			}
			close(release)
			<-finished
			backend.openConnectHelperMu.Lock()
			defer backend.openConnectHelperMu.Unlock()
			if len(backend.openConnectHelperAttempts) != 0 || attempt.result != nil || attempt.metadata != nil {
				t.Fatal("terminal success retained or restored an obsolete cookie")
			}
		})
	}
}

func TestOpenConnectHelperCleanupUsesFreshQueryNotQueuedSignalPayload(t *testing.T) {
	backend := helperBackend("/active/one")
	t.Cleanup(backend.cancelAllOpenConnectHelperAttempts)
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockSettings := mock_gonetworkmanager.NewMockSettings(t)
	backend.nmConn, backend.settings = mockNM, mockSettings
	mockNM.EXPECT().GetPropertyActiveConnections().Return(nil, errors.New("unrelated state refresh")).Twice()
	mockSettings.EXPECT().ListConnections().Return(nil, errors.New("unrelated hotspot refresh")).Once()
	key := openConnectHelperAttemptKey{uuid: "one", activePath: "/active/one"}
	attempt, _, err := newHelperAttemptForTest(backend, key, "/settings/one")
	if err != nil {
		t.Fatal(err)
	}
	queries := 0
	backend.openConnectActivePathsReader = func(context.Context) ([]dbus.ObjectPath, error) {
		queries++
		return []dbus.ObjectPath{key.activePath}, nil
	}
	backend.handleNetworkManagerChange(map[string]dbus.Variant{"ActiveConnections": dbus.MakeVariant([]dbus.ObjectPath{})})
	if queries != 1 || attempt.ctx.Err() != nil || !backend.ownsOpenConnectHelperAttempt(key, attempt) {
		t.Fatal("queued empty snapshot cancelled a currently active path")
	}
	backend.cancelAllOpenConnectHelperAttempts()
	backend.cleanupOpenConnectHelperAttempts()
	if queries != 1 {
		t.Fatal("empty registry performed an idle D-Bus query")
	}
}

func TestOpenConnectHelperCleanupSnapshotOwnsOnlyCapturedGenerations(t *testing.T) {
	for _, capturedRequestReturned := range []bool{false, true} {
		t.Run(fmt.Sprint(capturedRequestReturned), func(t *testing.T) {
			backend := helperBackend("/active/old")
			t.Cleanup(backend.cancelAllOpenConnectHelperAttempts)
			makeAttempt := func(name string) (openConnectHelperAttemptKey, *openConnectHelperAttempt) {
				key := openConnectHelperAttemptKey{uuid: name, activePath: dbus.ObjectPath("/active/" + name)}
				attempt, _, err := newHelperAttemptForTest(backend, key, dbus.ObjectPath("/settings/"+name))
				if err != nil {
					t.Fatal(err)
				}
				return key, attempt
			}
			makeRequest := func(name string) *openConnectHelperRequest {
				request, err := backend.beginOpenConnectHelperRequest(dbus.ObjectPath("/settings/"+name), false)
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { backend.endOpenConnectHelperRequest(request) })
				return request
			}
			bind := func(request *openConnectHelperRequest, key openConnectHelperAttemptKey, attempt *openConnectHelperAttempt) {
				backend.openConnectHelperMu.Lock()
				defer backend.openConnectHelperMu.Unlock()
				if err := backend.resolveOpenConnectHelperRequestLocked(request, key.activePath); err != nil {
					t.Fatal(err)
				}
				request.attempt = attempt
				request.ownsAttempt = true
			}
			oldKey, oldAttempt := makeAttempt("old")
			replacedKey, replacedAttempt := makeAttempt("replaced")
			captured := makeRequest("pending")
			queryStarted, releaseQuery, queryFinished := make(chan struct{}), make(chan struct{}), make(chan struct{})
			backend.openConnectActivePathsReader = func(context.Context) ([]dbus.ObjectPath, error) {
				close(queryStarted)
				<-releaseQuery
				return nil, nil // These paths were absent when the query was issued.
			}
			go func() {
				defer close(queryFinished)
				backend.cleanupOpenConnectHelperAttempts()
			}()
			<-queryStarted
			newRequest := makeRequest("new")
			newKey, newAttempt := makeAttempt("new")
			bind(newRequest, newKey, newAttempt)
			pendingKey, pendingAttempt := makeAttempt("pending")
			bind(captured, pendingKey, pendingAttempt)
			if capturedRequestReturned {
				backend.endOpenConnectHelperRequest(captured)
			}
			backend.openConnectHelperMu.Lock()
			backend.cancelOpenConnectHelperAttemptLocked(replacedKey, replacedAttempt)
			backend.openConnectHelperMu.Unlock()
			_, replacement := makeAttempt("replaced")
			close(releaseQuery)
			<-queryFinished
			if oldAttempt.ctx.Err() == nil || backend.ownsOpenConnectHelperAttempt(oldKey, oldAttempt) {
				t.Error("missing captured attempt survived")
			}
			if pendingAttempt.ctx.Err() == nil || backend.ownsOpenConnectHelperAttempt(pendingKey, pendingAttempt) {
				t.Error("captured request's newly acquired attempt survived removal")
			}
			if newRequest.ctx.Err() != nil || newAttempt.ctx.Err() != nil || !backend.ownsOpenConnectHelperAttempt(newKey, newAttempt) {
				t.Error("old query cancelled a newer request or attempt")
			}
			if replacement.ctx.Err() != nil || !backend.ownsOpenConnectHelperAttempt(replacedKey, replacement) {
				t.Error("old query cancelled a replacement at the same key")
			}
		})
	}
}

func TestOpenConnectHelperCancelledFinderDoesNotLaunchRunner(t *testing.T) {
	backend := helperBackend("/active/one")
	t.Cleanup(backend.cancelAllOpenConnectHelperAttempts)
	backend.openConnectHelperFinder = func() (string, error) {
		backend.cancelOpenConnectHelperAttempts("/settings/one")
		return "/trusted/helper", nil
	}
	backend.openConnectHelperRunner = func(context.Context, string, string, string, map[string]string, map[string]string, bool) (*openConnectHelperResult, error) {
		t.Error("launched runner after finder observed cancellation")
		return nil, errOpenConnectHelperCancelled
	}
	key := openConnectHelperAttemptKey{uuid: "one", activePath: "/active/one"}
	attempt, _, err := newHelperAttemptForTest(backend, key, "/settings/one")
	if err != nil {
		t.Fatal(err)
	}
	backend.runOpenConnectHelperAttempt(key, attempt, "AnyConnect", nil, nil, false)
	if _, err := backend.openConnectHelperResult(context.Background(), key, attempt); err != errOpenConnectHelperCancelled {
		t.Fatalf("cancelled finder result: %v", err)
	}
}
