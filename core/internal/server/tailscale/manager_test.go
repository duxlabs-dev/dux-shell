package tailscale

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnstate"
	"tailscale.com/tailcfg"
)

// blockingWatch is a watchFn that blocks until the context is cancelled, used
// by tests that exercise direct manager calls rather than the watch loop.
func blockingWatch(ctx context.Context, mask ipn.NotifyWatchOpt) (ipnBusWatcher, error) {
	<-ctx.Done()
	return nil, ctx.Err()
}

// mockWatcher yields canned Notify events, then returns err or blocks until Close/context cancel.
type mockWatcher struct {
	events []ipn.Notify
	idx    int
	err    error
	done   chan struct{}
	ctx    context.Context
	mu     sync.Mutex
	closed bool
}

func newMockWatcher(ctx context.Context, events []ipn.Notify, err error) *mockWatcher {
	return &mockWatcher{
		events: events,
		err:    err,
		done:   make(chan struct{}),
		ctx:    ctx,
	}
}

func (w *mockWatcher) Next() (ipn.Notify, error) {
	w.mu.Lock()
	if w.idx < len(w.events) {
		n := w.events[w.idx]
		w.idx++
		w.mu.Unlock()
		return n, nil
	}
	if w.err != nil {
		err := w.err
		w.mu.Unlock()
		return ipn.Notify{}, err
	}
	w.mu.Unlock()
	select {
	case <-w.done:
		return ipn.Notify{}, fmt.Errorf("watcher closed")
	case <-w.ctx.Done():
		return ipn.Notify{}, w.ctx.Err()
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
	watchFn     func(ctx context.Context, mask ipn.NotifyWatchOpt) (ipnBusWatcher, error)
	statusFn    func(ctx context.Context) (*ipnstate.Status, error)
	getPrefsFn  func(ctx context.Context) (*ipn.Prefs, error)
	editPrefsFn func(ctx context.Context, mp *ipn.MaskedPrefs) (*ipn.Prefs, error)
}

func (c *mockClient) WatchIPNBus(ctx context.Context, mask ipn.NotifyWatchOpt) (ipnBusWatcher, error) {
	return c.watchFn(ctx, mask)
}

func (c *mockClient) Status(ctx context.Context) (*ipnstate.Status, error) {
	return c.statusFn(ctx)
}

func (c *mockClient) GetPrefs(ctx context.Context) (*ipn.Prefs, error) {
	if c.getPrefsFn != nil {
		return c.getPrefsFn(ctx)
	}
	return &ipn.Prefs{}, nil
}

func (c *mockClient) EditPrefs(ctx context.Context, mp *ipn.MaskedPrefs) (*ipn.Prefs, error) {
	if c.editPrefsFn != nil {
		return c.editPrefsFn(ctx, mp)
	}
	return &ipn.Prefs{}, nil
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
	stateVal := ipn.Running
	var watchCount int32

	client := &mockClient{
		watchFn: func(ctx context.Context, mask ipn.NotifyWatchOpt) (ipnBusWatcher, error) {
			watchCount++
			if watchCount == 1 {
				return newMockWatcher(ctx,
					[]ipn.Notify{{State: &stateVal}},
					fmt.Errorf("done"),
				), nil
			}
			return newMockWatcher(ctx, nil, nil), nil
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
	stateVal := ipn.Running
	var statusCalls atomic.Int32

	notifies := make([]ipn.Notify, 0, 20)
	for range 20 {
		notifies = append(notifies, ipn.Notify{State: &stateVal})
	}

	client := &mockClient{
		watchFn: func(ctx context.Context, mask ipn.NotifyWatchOpt) (ipnBusWatcher, error) {
			return newMockWatcher(ctx, notifies, nil), nil
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
		watchFn: func(ctx context.Context, mask ipn.NotifyWatchOpt) (ipnBusWatcher, error) {
			select {
			case watchCalled <- struct{}{}:
			default:
			}
			if len(watchCalled) <= 1 {
				return nil, fmt.Errorf("connection refused")
			}
			return newMockWatcher(ctx, nil, nil), nil
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
		watchFn: func(ctx context.Context, mask ipn.NotifyWatchOpt) (ipnBusWatcher, error) {
			watchCalls.Add(1)
			return newMockWatcher(ctx, nil, fmt.Errorf("json: cannot unmarshal object")), nil
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
		watchFn: func(ctx context.Context, mask ipn.NotifyWatchOpt) (ipnBusWatcher, error) {
			n := watchAttempts.Add(1)
			if n == 1 {
				return nil, fmt.Errorf("tailscaled socket not found")
			}
			return newMockWatcher(ctx, nil, nil), nil
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
		getPrefsFn: func(ctx context.Context) (*ipn.Prefs, error) {
			return &ipn.Prefs{ExitNodeAllowLANAccess: true}, nil
		},
	}

	m := newManager(client)
	defer m.Close()

	m.RefreshState()

	assert.True(t, m.GetState().ExitNodeAllowLANAccess)
}

func TestManager_Actions_EditPrefs(t *testing.T) {
	var captured *ipn.MaskedPrefs
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		editPrefsFn: func(ctx context.Context, mp *ipn.MaskedPrefs) (*ipn.Prefs, error) {
			captured = mp
			return &ipn.Prefs{}, nil
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
	assert.Equal(t, tailcfg.StableNodeID("nABC123"), captured.ExitNodeID)
	// ExitNodeIPSet must also be set so a stale legacy ExitNodeIP cannot
	// override the ID-based selection (mirrors `tailscale set --exit-node`).
	assert.True(t, captured.ExitNodeIPSet)

	require.NoError(t, m.SetExitNode(""))
	assert.True(t, captured.ExitNodeIDSet)
	assert.Equal(t, tailcfg.StableNodeID(""), captured.ExitNodeID)
	// Clearing must zero both the ID and any legacy IP-based exit node.
	assert.True(t, captured.ExitNodeIPSet)

	require.NoError(t, m.SetAllowLANAccess(true))
	assert.True(t, captured.ExitNodeAllowLANAccessSet)
	assert.True(t, captured.ExitNodeAllowLANAccess)
}

type dynamicWatcher struct {
	ctx context.Context
	ch  chan ipn.Notify
}

func (w *dynamicWatcher) Next() (ipn.Notify, error) {
	select {
	case n, ok := <-w.ch:
		if !ok {
			return ipn.Notify{}, fmt.Errorf("watcher closed")
		}
		return n, nil
	case <-w.ctx.Done():
		return ipn.Notify{}, w.ctx.Err()
	}
}

func (w *dynamicWatcher) Close() error {
	return nil
}

func TestWatchLoop_NotifyWithoutStateOrNetMap(t *testing.T) {
	var statusCalls atomic.Int32
	notifyCh := make(chan ipn.Notify, 1)

	client := &mockClient{
		watchFn: func(ctx context.Context, mask ipn.NotifyWatchOpt) (ipnBusWatcher, error) {
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

	// Send an event with State == nil and NetMap == nil.
	notifyCh <- ipn.Notify{Engine: &ipn.EngineStatus{}}

	// Verify that the notification without State or NetMap triggers a second status call.
	require.Eventually(t, func() bool {
		return statusCalls.Load() >= 2
	}, 2*time.Second, 10*time.Millisecond)
}
