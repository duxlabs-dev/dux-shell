package tailscale

import (
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
	watchFn     func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error)
	statusFn    func(ctx context.Context) (*ipnstate.Status, error)
	getPrefsFn  func(ctx context.Context) (*prefs, error)
	editPrefsFn func(ctx context.Context, mp *maskedPrefs) error

	startLoginFn    func(ctx context.Context) error
	logoutFn        func(ctx context.Context) error
	profileStatusFn func(ctx context.Context) (loginProfile, []loginProfile, error)
	switchProfileFn func(ctx context.Context, id string) error
	switchEmptyFn   func(ctx context.Context) error
	suggestFn       func(ctx context.Context) (ExitNodeSuggestion, error)
	checkIPFwdFn    func(ctx context.Context) error
}

func (c *mockClient) StartLoginInteractive(ctx context.Context) error {
	if c.startLoginFn != nil {
		return c.startLoginFn(ctx)
	}
	return nil
}

func (c *mockClient) Logout(ctx context.Context) error {
	if c.logoutFn != nil {
		return c.logoutFn(ctx)
	}
	return nil
}

func (c *mockClient) ProfileStatus(ctx context.Context) (loginProfile, []loginProfile, error) {
	if c.profileStatusFn != nil {
		return c.profileStatusFn(ctx)
	}
	return loginProfile{}, nil, nil
}

func (c *mockClient) SwitchProfile(ctx context.Context, id string) error {
	if c.switchProfileFn != nil {
		return c.switchProfileFn(ctx, id)
	}
	return nil
}

func (c *mockClient) SwitchToEmptyProfile(ctx context.Context) error {
	if c.switchEmptyFn != nil {
		return c.switchEmptyFn(ctx)
	}
	return nil
}

func (c *mockClient) SuggestExitNode(ctx context.Context) (ExitNodeSuggestion, error) {
	if c.suggestFn != nil {
		return c.suggestFn(ctx)
	}
	return ExitNodeSuggestion{}, nil
}

func (c *mockClient) CheckIPForwarding(ctx context.Context) error {
	if c.checkIPFwdFn != nil {
		return c.checkIPFwdFn(ctx)
	}
	return nil
}

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

func prefixes(ss ...string) []netip.Prefix {
	out := make([]netip.Prefix, len(ss))
	for i, s := range ss {
		out[i] = netip.MustParsePrefix(s)
	}
	return out
}

func boolPtr(b bool) *bool { return &b }

func TestSetPrefs_AdvertiseExitNodeKeepsRoutesAndWarns(t *testing.T) {
	var captured *maskedPrefs
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		getPrefsFn: func(ctx context.Context) (*prefs, error) {
			return &prefs{AdvertiseRoutes: prefixes("192.168.1.0/24")}, nil
		},
		editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error {
			captured = mp
			return nil
		},
		checkIPFwdFn: func(ctx context.Context) error { return fmt.Errorf("IP forwarding is disabled") },
	}
	m := newManager(client)
	defer m.Close()

	warning, err := m.SetPrefs(PrefsPatch{AdvertiseExitNode: boolPtr(true)})
	require.NoError(t, err)
	require.NotNil(t, captured)
	assert.True(t, captured.AdvertiseRoutesSet)
	assert.Equal(t, prefixes("0.0.0.0/0", "::/0", "192.168.1.0/24"), captured.AdvertiseRoutes)
	assert.Equal(t, "IP forwarding is disabled", warning)
}

func TestSetPrefs_InvalidRouteWritesNothing(t *testing.T) {
	edited := false
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error {
			edited = true
			return nil
		},
	}
	m := newManager(client)
	defer m.Close()

	for _, bad := range []string{"bogus", "0.0.0.0/0", "::/0"} {
		_, err := m.SetPrefs(PrefsPatch{AdvertiseRoutes: &[]string{"10.0.0.0/8", bad}})
		require.Error(t, err)
		assert.Contains(t, err.Error(), bad)
	}
	_, err := m.SetPrefs(PrefsPatch{})
	assert.EqualError(t, err, "no changes")
	assert.False(t, edited)
}

func TestSetPrefs_MaskOnlyRequestedFields(t *testing.T) {
	var captured *maskedPrefs
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error {
			captured = mp
			return nil
		},
		checkIPFwdFn: func(ctx context.Context) error { return fmt.Errorf("must not be called") },
	}
	m := newManager(client)
	defer m.Close()

	host := "x"
	warning, err := m.SetPrefs(PrefsPatch{AcceptRoutes: boolPtr(true), Hostname: &host})
	require.NoError(t, err)
	assert.Empty(t, warning)
	want := &maskedPrefs{
		RouteAll:    true,
		Hostname:    "x",
		RouteAllSet: true,
		HostnameSet: true,
	}
	assert.Equal(t, want, captured)
}

func TestProfiles(t *testing.T) {
	denied := true
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		profileStatusFn: func(ctx context.Context) (loginProfile, []loginProfile, error) {
			if denied {
				return loginProfile{}, nil, fmt.Errorf("profiles: %w", errAccessDenied)
			}
			work := loginProfile{ID: "b", Name: "work@corp.com", NetworkProfile: networkProfile{DomainName: "corp.com"}}
			home := loginProfile{ID: "a", Name: "alice@example.com", NetworkProfile: networkProfile{DomainName: "example.com", DisplayName: "Alice's tailnet"}}
			return work, []loginProfile{work, home}, nil
		},
	}
	m := newManager(client)
	defer m.Close()

	res, err := m.Profiles()
	require.NoError(t, err)
	assert.Equal(t, ProfilesResult{}, res)

	denied = false
	res, err = m.Profiles()
	require.NoError(t, err)
	assert.Equal(t, ProfilesResult{
		CanOperate: true,
		Current:    "b",
		Profiles: []TailscaleProfile{
			{ID: "a", Name: "alice@example.com", Tailnet: "Alice's tailnet"},
			{ID: "b", Name: "work@corp.com", Tailnet: "corp.com"},
		},
	}, res)
}

func TestAccountActions(t *testing.T) {
	var calls []string
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		startLoginFn: func(ctx context.Context) error {
			calls = append(calls, "login")
			return nil
		},
		logoutFn: func(ctx context.Context) error {
			calls = append(calls, "logout")
			return nil
		},
		switchEmptyFn: func(ctx context.Context) error {
			calls = append(calls, "empty")
			return nil
		},
		switchProfileFn: func(ctx context.Context, id string) error {
			calls = append(calls, "switch:"+string(id))
			return nil
		},
		suggestFn: func(ctx context.Context) (ExitNodeSuggestion, error) {
			return ExitNodeSuggestion{ID: "nX", Name: "de-fra"}, nil
		},
	}
	m := newManager(client)
	defer m.Close()

	require.NoError(t, m.Login())
	require.NoError(t, m.Logout())
	require.NoError(t, m.AddProfile())
	require.NoError(t, m.SwitchProfile("p1"))
	assert.Error(t, m.SwitchProfile(""))
	assert.Equal(t, []string{"login", "logout", "empty", "login", "switch:p1"}, calls)

	s, err := m.SuggestExitNode()
	require.NoError(t, err)
	assert.Equal(t, ExitNodeSuggestion{ID: "nX", Name: "de-fra"}, s)

	client.startLoginFn = func(ctx context.Context) error { return fmt.Errorf("Access denied: login") }
	assert.EqualError(t, m.Login(), "Access denied: login")
}

func TestFetchState_MapsPrefs(t *testing.T) {
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		getPrefsFn: func(ctx context.Context) (*prefs, error) {
			return &prefs{
				RouteAll:        true,
				CorpDNS:         true,
				RunSSH:          true,
				Hostname:        "rog",
				AdvertiseRoutes: prefixes("0.0.0.0/0", "::/0", "10.0.0.0/8"),
			}, nil
		},
	}
	m := newManager(client)
	defer m.Close()

	m.RefreshState()
	assert.Equal(t, TailscalePrefs{
		AcceptRoutes:      true,
		AcceptDNS:         true,
		RunSSH:            true,
		Hostname:          "rog",
		AdvertiseExitNode: true,
		AdvertiseRoutes:   []string{"10.0.0.0/8"},
	}, m.GetState().Prefs)
}

func TestWatchLoop_AuthURL(t *testing.T) {
	notifyCh := make(chan busNotify, 1)
	client := &mockClient{
		watchFn: func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
			return &dynamicWatcher{ctx: ctx, ch: notifyCh}, nil
		},
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
	}
	m := newManager(client)
	defer m.Close()

	u := "https://login.tailscale.com/a/abc"
	notifyCh <- busNotify{BrowseToURL: &u}
	require.Eventually(t, func() bool { return m.GetState().AuthURL == u }, 2*time.Second, 10*time.Millisecond)

	notifyCh <- busNotify{LoginFinished: &struct{}{}}
	require.Eventually(t, func() bool { return m.GetState().AuthURL == "" }, 2*time.Second, 10*time.Millisecond)
}

func TestWatchLoop_ReconnectClearsAuthURL(t *testing.T) {
	notifyCh := make(chan busNotify, 1)
	var watches atomic.Int32
	client := &mockClient{
		watchFn: func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
			if watches.Add(1) == 1 {
				return &dynamicWatcher{ctx: ctx, ch: notifyCh}, nil
			}
			return newMockWatcher(ctx, 0, nil), nil
		},
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
	}
	m := newManager(client)
	defer m.Close()

	u := "https://login.tailscale.com/a/abc"
	notifyCh <- busNotify{BrowseToURL: &u}
	require.Eventually(t, func() bool { return m.GetState().AuthURL == u }, 2*time.Second, 10*time.Millisecond)

	close(notifyCh)
	require.Eventually(t, func() bool { return watches.Load() == 2 && m.GetState().AuthURL == "" }, 3*time.Second, 10*time.Millisecond)
}

func TestManager_AdvertiseRoutesNeverNull(t *testing.T) {
	m := newManager(&mockClient{watchFn: blockingWatch})
	assert.NotNil(t, m.GetState().Prefs.AdvertiseRoutes)
	m.Close()

	m = newManager(&mockClient{watchFn: func(ctx context.Context, mask watchOpt) (ipnBusWatcher, error) {
		return nil, fmt.Errorf("connection refused")
	}})
	defer m.Close()
	require.Eventually(t, func() bool { return m.GetState().BackendState == "Unreachable" }, 2*time.Second, 10*time.Millisecond)
	assert.NotNil(t, m.GetState().Prefs.AdvertiseRoutes)
}

func TestSetPrefs_DedupesRoutes(t *testing.T) {
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

	_, err := m.SetPrefs(PrefsPatch{AdvertiseRoutes: &[]string{"10.0.0.0/8", "192.168.1.0/24", "10.0.0.0/8"}})
	require.NoError(t, err)
	assert.Equal(t, prefixes("10.0.0.0/8", "192.168.1.0/24"), captured.AdvertiseRoutes)

	_, err = m.SetPrefs(PrefsPatch{AdvertiseRoutes: &[]string{"10.0.0.0/8,0.0.0.0/0"}})
	assert.Error(t, err)
}

func TestSetPrefs_UnchangedRoutesSkipEditAndForwardingCheck(t *testing.T) {
	edits, checks := 0, 0
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		getPrefsFn: func(ctx context.Context) (*prefs, error) {
			return &prefs{AdvertiseRoutes: prefixes("10.0.0.0/8", "192.168.1.0/24")}, nil
		},
		editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error {
			edits++
			return nil
		},
		checkIPFwdFn: func(ctx context.Context) error { checks++; return fmt.Errorf("IP forwarding is disabled") },
	}
	m := newManager(client)
	defer m.Close()

	warning, err := m.SetPrefs(PrefsPatch{AdvertiseRoutes: &[]string{"192.168.1.0/24", "10.0.0.0/8"}})
	require.NoError(t, err)
	assert.Empty(t, warning)
	assert.Zero(t, edits)
	assert.Zero(t, checks)
}
