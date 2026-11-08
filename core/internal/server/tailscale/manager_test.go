package tailscale

import (
	"cmp"
	"context"
	"fmt"
	"net/netip"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"tailscale.com/ipn/ipnstate"
)

// blockingWatch is a watchFn that blocks until the context is cancelled, used
// by tests that exercise direct manager calls rather than the watch loop.
func blockingWatch(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
	<-ctx.Done()
	return nil, ctx.Err()
}

// mockWatcher yields a number of canned events, then returns err or blocks until Close/context cancel.
type mockWatcher struct {
	events int
	err    error
	done   chan struct{}
	ctx    context.Context
	mu     sync.Mutex
	closed bool
}

func newMockWatcher(ctx context.Context, events int, err error) *mockWatcher {
	return &mockWatcher{
		events: events,
		err:    err,
		done:   make(chan struct{}),
		ctx:    ctx,
	}
}

func (w *mockWatcher) Next() (busNotify, error) {
	w.mu.Lock()
	if w.events > 0 {
		w.events--
		w.mu.Unlock()
		return busNotify{}, nil
	}
	if w.err != nil {
		err := w.err
		w.mu.Unlock()
		return busNotify{}, err
	}
	w.mu.Unlock()
	select {
	case <-w.done:
		return busNotify{}, fmt.Errorf("watcher closed")
	case <-w.ctx.Done():
		return busNotify{}, w.ctx.Err()
	}
}

func (w *mockWatcher) Close() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if !w.closed {
		w.closed = true
		close(w.done)
	}
	return nil
}

// mockClient implements tailscaleClient for testing.
type mockClient struct {
	watchFn         func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error)
	statusFn        func(ctx context.Context) (*ipnstate.Status, error)
	getPrefsFn      func(ctx context.Context) (*prefs, error)
	editPrefsFn     func(ctx context.Context, mp *maskedPrefs) error
	profileStatusFn func(ctx context.Context) (loginProfile, []loginProfile, error)
	fwdErr          error
}

func (c *mockClient) StartLoginInteractive(ctx context.Context) error    { return nil }
func (c *mockClient) SwitchProfile(ctx context.Context, id string) error { return nil }
func (c *mockClient) Logout(ctx context.Context) error                   { return nil }
func (c *mockClient) SwitchToEmptyProfile(ctx context.Context) error     { return nil }
func (c *mockClient) SuggestExitNode(ctx context.Context) (ExitNodeSuggestion, error) {
	return ExitNodeSuggestion{ID: "n1"}, nil
}
func (c *mockClient) ProfileStatus(ctx context.Context) (loginProfile, []loginProfile, error) {
	if c.profileStatusFn != nil {
		return c.profileStatusFn(ctx)
	}
	return loginProfile{}, nil, nil
}
func (c *mockClient) CheckIPForwarding(ctx context.Context) error { return c.fwdErr }

func (c *mockClient) WatchIPNBus(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
	return c.watchFn(ctx, mask)
}

func (c *mockClient) Status(ctx context.Context) (*ipnstate.Status, error) {
	return c.statusFn(ctx)
}

func (c *mockClient) GetPrefs(ctx context.Context) (*prefs, error) {
	if c.getPrefsFn != nil {
		return c.getPrefsFn(ctx)
	}
	return &prefs{}, nil
}

func (c *mockClient) EditPrefs(ctx context.Context, mp *maskedPrefs) error {
	if c.editPrefsFn != nil {
		return c.editPrefsFn(ctx, mp)
	}
	return nil
}

func runningStatus() *ipnstate.Status {
	return &ipnstate.Status{
		Version:        "1.94.2",
		BackendState:   "Running",
		MagicDNSSuffix: "example.ts.net",
		CurrentTailnet: &ipnstate.TailnetStatus{
			Name:           "user@example.com",
			MagicDNSSuffix: "example.ts.net",
		},
		Self: &ipnstate.PeerStatus{
			HostName: "cachyos",
			DNSName:  "cachyos.example.ts.net.",
			OS:       "linux",
			Online:   true,
		},
	}
}

func TestWatchLoop_StateChange(t *testing.T) {
	var watchCount int32

	client := &mockClient{
		watchFn: func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
			watchCount++
			if watchCount == 1 {
				return newMockWatcher(ctx, 1, fmt.Errorf("done")), nil
			}
			return newMockWatcher(ctx, 0, nil), nil
		},
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) {
			return runningStatus(), nil
		},
	}

	m := newManager(client)
	defer m.Close()

	require.Eventually(t, func() bool {
		s := m.GetState()
		return s.Connected && s.BackendState == "Running" && s.Self.Hostname == "cachyos"
	}, 2*time.Second, 10*time.Millisecond)
}

func TestWatchLoop_CoalescesNotifies(t *testing.T) {
	var statusCalls atomic.Int32

	client := &mockClient{
		watchFn: func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
			return newMockWatcher(ctx, 20, nil), nil
		},
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) {
			statusCalls.Add(1)
			return runningStatus(), nil
		},
	}

	m := newManager(client)
	defer m.Close()

	require.Eventually(t, func() bool { return statusCalls.Load() > 0 }, 2*time.Second, 10*time.Millisecond)

	calls := statusCalls.Load()
	assert.Less(t, int(calls), 5,
		"20 rapid notifies should coalesce to a small number of Status RPCs, got %d", calls)
	assert.Greater(t, int(calls), 0, "expected at least one Status RPC")
}

func TestWatchLoop_Reconnect(t *testing.T) {
	watchCalled := make(chan struct{}, 4)

	client := &mockClient{
		watchFn: func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
			select {
			case watchCalled <- struct{}{}:
			default:
			}
			if len(watchCalled) <= 1 {
				return nil, fmt.Errorf("connection refused")
			}
			return newMockWatcher(ctx, 0, nil), nil
		},
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) {
			return runningStatus(), nil
		},
	}

	m := newManager(client)
	defer m.Close()

	require.Eventually(t, func() bool {
		state := m.GetState()
		return state.BackendState == "Unreachable"
	}, 2*time.Second, 10*time.Millisecond)

	require.Eventually(t, func() bool {
		return len(watchCalled) >= 2
	}, 3*time.Second, 50*time.Millisecond)
}

func TestWatchLoop_BacksOffOnPersistentBusError(t *testing.T) {
	var watchCalls atomic.Int32

	client := &mockClient{
		watchFn: func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
			watchCalls.Add(1)
			return newMockWatcher(ctx, 0, fmt.Errorf("json: cannot unmarshal object")), nil
		},
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) {
			return runningStatus(), nil
		},
	}

	m := newManager(client)
	defer m.Close()

	require.Eventually(t, func() bool { return watchCalls.Load() > 0 }, 2*time.Second, 10*time.Millisecond)

	calls := watchCalls.Load()
	assert.LessOrEqual(t, int(calls), 2,
		"a persistent bus read error should back off, not reconnect in a hot loop; got %d attempts", calls)
}

func TestManager_Availability(t *testing.T) {
	var watchAttempts atomic.Int32

	client := &mockClient{
		watchFn: func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
			n := watchAttempts.Add(1)
			if n == 1 {
				return nil, fmt.Errorf("tailscaled socket not found")
			}
			return newMockWatcher(ctx, 0, nil), nil
		},
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) {
			return runningStatus(), nil
		},
	}

	m := newManager(client)
	defer m.Close()

	cbFired := make(chan bool, 1)
	m.SetAvailabilityCallback(func(b bool) {
		select {
		case cbFired <- b:
		default:
		}
	})

	assert.False(t, m.IsAvailable())

	require.Eventually(t, func() bool {
		return m.IsAvailable()
	}, 3*time.Second, 50*time.Millisecond)

	select {
	case b := <-cbFired:
		assert.True(t, b)
	case <-time.After(time.Second):
		t.Fatal("availability callback did not fire")
	}
}

func TestManager_RefreshState_MergesPrefs(t *testing.T) {
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		getPrefsFn: func(ctx context.Context) (*prefs, error) {
			return &prefs{ExitNodeAllowLANAccess: true}, nil
		},
	}

	m := newManager(client)
	defer m.Close()

	m.RefreshState()

	assert.True(t, m.GetState().ExitNodeAllowLANAccess)
}

func TestManager_Actions_EditPrefs(t *testing.T) {
	var captured *maskedPrefs
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error {
			captured = mp
			return nil
		},
	}

	m := newManager(client)
	defer m.Close()

	require.NoError(t, m.Connect())
	require.NotNil(t, captured)
	assert.True(t, captured.WantRunningSet)
	assert.True(t, captured.WantRunning)

	require.NoError(t, m.Disconnect())
	assert.True(t, captured.WantRunningSet)
	assert.False(t, captured.WantRunning)

	require.NoError(t, m.SetExitNode("nABC123"))
	assert.True(t, captured.ExitNodeIDSet)
	assert.Equal(t, "nABC123", captured.ExitNodeID)
	// ExitNodeIPSet must also be set so a stale legacy ExitNodeIP cannot
	// override the ID-based selection (mirrors `tailscale set --exit-node`).
	assert.True(t, captured.ExitNodeIPSet)

	require.NoError(t, m.SetExitNode(""))
	assert.True(t, captured.ExitNodeIDSet)
	assert.Equal(t, "", captured.ExitNodeID)
	// Clearing must zero both the ID and any legacy IP-based exit node.
	assert.True(t, captured.ExitNodeIPSet)

	require.NoError(t, m.SetAllowLANAccess(true))
	assert.True(t, captured.ExitNodeAllowLANAccessSet)
	assert.True(t, captured.ExitNodeAllowLANAccess)
}

type dynamicWatcher struct {
	ctx context.Context
	ch  chan busNotify
}

func (w *dynamicWatcher) Next() (busNotify, error) {
	select {
	case n, ok := <-w.ch:
		if !ok {
			return n, fmt.Errorf("watcher closed")
		}
		return n, nil
	case <-w.ctx.Done():
		return busNotify{}, w.ctx.Err()
	}
}

func (w *dynamicWatcher) Close() error {
	return nil
}

func TestWatchLoop_LateNotifyRefetches(t *testing.T) {
	var statusCalls atomic.Int32
	notifyCh := make(chan busNotify, 1)

	client := &mockClient{
		watchFn: func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
			return &dynamicWatcher{ctx: ctx, ch: notifyCh}, nil
		},
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) {
			statusCalls.Add(1)
			return runningStatus(), nil
		},
	}

	m := newManager(client)
	defer m.Close()

	// Wait for the initial connect-time status call to complete.
	require.Eventually(t, func() bool {
		return statusCalls.Load() == 1
	}, 2*time.Second, 10*time.Millisecond)

	notifyCh <- busNotify{}

	require.Eventually(t, func() bool {
		return statusCalls.Load() >= 2
	}, 2*time.Second, 10*time.Millisecond)
}
func prefixes(ss ...string) (out []netip.Prefix) {
	for _, s := range ss {
		out = append(out, netip.MustParsePrefix(s))
	}
	return
}
func TestSetPrefs(t *testing.T) {
	yes, host, routes := true, "x", func(ss ...string) *[]string { return &ss }
	tests := []struct {
		name  string
		have  []netip.Prefix
		patch PrefsPatch
		want  *maskedPrefs
		err   string
	}{
		{"only requested fields", nil, PrefsPatch{AcceptRoutes: &yes, Hostname: &host}, &maskedPrefs{RouteAll: true, RouteAllSet: true, Hostname: "x", HostnameSet: true}, ""},
		{"exit node keeps routes", prefixes("192.168.1.0/24"), PrefsPatch{AdvertiseExitNode: &yes}, &maskedPrefs{AdvertiseRoutes: prefixes("0.0.0.0/0", "::/0", "192.168.1.0/24"), AdvertiseRoutesSet: true}, ""},
		{"routes deduped", nil, PrefsPatch{AdvertiseRoutes: routes("10.0.0.0/8", "10.0.0.0/8")}, &maskedPrefs{AdvertiseRoutes: prefixes("10.0.0.0/8"), AdvertiseRoutesSet: true}, ""},
		{"same routes write nothing", prefixes("10.0.0.0/8", "192.168.1.0/24"), PrefsPatch{AdvertiseRoutes: routes("192.168.1.0/24", "10.0.0.0/8")}, nil, ""},
		{"invalid route", nil, PrefsPatch{AdvertiseRoutes: routes("10.0.0.0/8", "bogus")}, nil, "bogus"},
		{"default route", nil, PrefsPatch{AdvertiseRoutes: routes("10.0.0.0/8", "::/0")}, nil, "::/0"},
		{"no changes", nil, PrefsPatch{}, nil, "no changes"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var got *maskedPrefs
			m := newManager(&mockClient{watchFn: blockingWatch, fwdErr: fmt.Errorf("IP forwarding is disabled"),
				statusFn:    func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
				getPrefsFn:  func(ctx context.Context) (*prefs, error) { return &prefs{AdvertiseRoutes: tc.have}, nil },
				editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error { got = mp; return nil }})
			defer m.Close()
			assert.NotNil(t, m.GetState().Prefs.AdvertiseRoutes)
			warn, err := m.SetPrefs(tc.patch)
			assert.Contains(t, fmt.Sprint(err), cmp.Or(tc.err, "<nil>"))
			assert.Equal(t, tc.want, got)
			assert.Equal(t, got != nil && got.AdvertiseRoutesSet, warn != "")
		})
	}
}
func TestWatchLoop_AuthURL(t *testing.T) {
	notifyCh := make(chan busNotify, 1)
	var watches atomic.Int32
	m := newManager(&mockClient{
		watchFn: func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
			if watches.Add(1) > 1 {
				return newMockWatcher(ctx, 0, nil), nil
			}
			return &dynamicWatcher{ctx: ctx, ch: notifyCh}, nil
		},
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil }})
	defer m.Close()
	authURL := func(want string) {
		require.Eventually(t, func() bool { return m.GetState().AuthURL == want }, 3*time.Second, 10*time.Millisecond)
	}
	u := "https://login.tailscale.com/a/abc"
	notifyCh <- busNotify{BrowseToURL: &u}
	authURL(u)
	notifyCh <- busNotify{LoginFinished: &struct{}{}}
	authURL("")
	notifyCh <- busNotify{BrowseToURL: &u}
	authURL(u)
	close(notifyCh)
	authURL("")
}
