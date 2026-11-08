package tailscale

import (
	"cmp"
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"maps"
	"net/netip"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"tailscale.com/ipn/ipnstate"
)

const (
	statusTimeout  = 3 * time.Second
	debounceWindow = 150 * time.Millisecond
)

// tailscaleClient abstracts the Tailscale local API for testing.
type tailscaleClient interface {
	WatchIPNBus(ctx context.Context, mask watchOpt) (ipnBusWatcher, error)
	Status(ctx context.Context) (*ipnstate.Status, error)
	GetPrefs(ctx context.Context) (*prefs, error)
	EditPrefs(ctx context.Context, mp *maskedPrefs) error
	StartLoginInteractive(ctx context.Context) error
	Logout(ctx context.Context) error
	ProfileStatus(ctx context.Context) (loginProfile, []loginProfile, error)
	SwitchProfile(ctx context.Context, id string) error
	SwitchToEmptyProfile(ctx context.Context) error
	SuggestExitNode(ctx context.Context) (ExitNodeSuggestion, error)
	CheckIPForwarding(ctx context.Context) error
}

// ipnBusWatcher abstracts the IPN bus watcher for testing.
type ipnBusWatcher interface {
	Next() (busNotify, error)
	Close() error
}

// Manager manages Tailscale state via IPN bus events and subscriber notifications.
type Manager struct {
	state                *TailscaleState
	stateMutex           sync.RWMutex
	subscribers          syncmap.Map[string, chan TailscaleState]
	client               tailscaleClient
	ctx                  context.Context
	cancel               context.CancelFunc
	watchWG              sync.WaitGroup
	closed               atomic.Bool
	dirty                chan struct{}
	available            atomic.Bool
	availabilityCallback atomic.Pointer[func(bool)]
	authURL              atomic.Pointer[string]
	authGen              atomic.Uint64
}

// NewManager creates a new Tailscale manager and starts watching the IPN bus.
func NewManager(socketPath string) *Manager {
	return newManager(newLocalClient(socketPath))
}

func newManager(client tailscaleClient) *Manager {
	ctx, cancel := context.WithCancel(context.Background())
	m := &Manager{
		state:  &TailscaleState{Prefs: TailscalePrefs{AdvertiseRoutes: []string{}}},
		client: client,
		ctx:    ctx,
		cancel: cancel,
		dirty:  make(chan struct{}, 1),
	}

	m.watchWG.Add(2)
	go m.watchLoop(ctx)
	go m.debounceLoop(ctx)

	return m
}

func (m *Manager) watchLoop(ctx context.Context) {
	defer m.watchWG.Done()

	mask := notifyInitialState | notifyInitialPrefs | notifyPeerChanges | notifyPeerPatches
	backoff := time.Second
	unreachableSent := false

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		watcher, err := m.client.WatchIPNBus(ctx, mask)
		if err != nil {
			if !unreachableSent {
				log.Warnf("[Tailscale] IPN bus subscribe failed: %v", err)
				m.updateState(&TailscaleState{BackendState: "Unreachable", Prefs: TailscalePrefs{AdvertiseRoutes: []string{}}})
				unreachableSent = true
			}
			if !sleepBackoff(ctx, &backoff) {
				return
			}
			continue
		}

		unreachableSent = false
		log.Info("[Tailscale] Connected to IPN bus")
		m.markAvailable()
		// A still-pending login URL is re-sent with the initial state.
		m.setAuthURL(nil)

		select {
		case m.dirty <- struct{}{}:
		default:
		}

		for {
			n, err := watcher.Next()
			if err != nil {
				log.Warnf("[Tailscale] IPN bus error: %v", err)
				break
			}

			switch {
			case n.BrowseToURL != nil:
				m.setAuthURL(n.BrowseToURL)
			case n.LoginFinished != nil, n.State != nil && *n.State == ipnStateRunning:
				m.setAuthURL(nil)
			}

			backoff = time.Second

			select {
			case m.dirty <- struct{}{}:
			default:
			}
		}

		watcher.Close()

		if !sleepBackoff(ctx, &backoff) {
			return
		}
	}
}

func sleepBackoff(ctx context.Context, backoff *time.Duration) bool {
	select {
	case <-ctx.Done():
		return false
	case <-time.After(*backoff):
	}
	*backoff = min(*backoff*2, 30*time.Second)
	return true
}

// debounceLoop coalesces rapid bus notifications into a single Status RPC
// per debounceWindow, since NetMap events can fire many times per second
// on busy tailnets.
func (m *Manager) debounceLoop(ctx context.Context) {
	defer m.watchWG.Done()

	for {
		select {
		case <-ctx.Done():
			return
		case <-m.dirty:
		}

		timer := time.NewTimer(debounceWindow)
		collecting := true
		for collecting {
			select {
			case <-ctx.Done():
				timer.Stop()
				return
			case <-m.dirty:
			case <-timer.C:
				collecting = false
			}
		}

		m.fetchAndBroadcast(ctx)
	}
}

// setAuthURL stores the pending login URL and invalidates fetches already in flight.
func (m *Manager) setAuthURL(u *string) {
	m.authURL.Store(u)
	m.authGen.Add(1)
}

func (m *Manager) fetchAndBroadcast(ctx context.Context) {
	gen := m.authGen.Load()
	statusCtx, cancel := context.WithTimeout(ctx, statusTimeout)
	defer cancel()

	state, err := m.fetchState(statusCtx)
	if err != nil {
		log.Warnf("[Tailscale] Failed to fetch status: %v", err)
		return
	}

	if m.authGen.Load() != gen {
		// The login URL changed mid-fetch; fetch again instead of broadcasting a stale one.
		select {
		case m.dirty <- struct{}{}:
		default:
		}
		return
	}

	m.updateState(state)
}

// fetchState fetches the current status and merges in pref-derived fields
// (e.g. exit-node LAN access) that are not present in the IPN status itself.
func (m *Manager) fetchState(ctx context.Context) (*TailscaleState, error) {
	status, err := m.client.Status(ctx)
	if err != nil {
		return nil, err
	}

	state := convertStatus(status)
	state.Prefs.AdvertiseRoutes = []string{}
	if u := m.authURL.Load(); u != nil {
		state.AuthURL = *u
	}

	// Prefs carry settings the status does not expose. Treat a prefs failure
	// as non-fatal so status still updates.
	if prefs, err := m.client.GetPrefs(ctx); err != nil {
		log.Warnf("[Tailscale] Failed to fetch prefs: %v", err)
	} else if prefs != nil {
		state.ExitNodeAllowLANAccess = prefs.ExitNodeAllowLANAccess
		state.Prefs = convertPrefs(prefs)
	}

	return state, nil
}

func convertPrefs(p *prefs) TailscalePrefs {
	routes, exitNode := splitAdvertisedRoutes(p.AdvertiseRoutes)
	out := TailscalePrefs{
		AcceptRoutes:      p.RouteAll,
		AcceptDNS:         p.CorpDNS,
		ShieldsUp:         p.ShieldsUp,
		RunSSH:            p.RunSSH,
		Hostname:          p.Hostname,
		OperatorUser:      p.OperatorUser,
		AdvertiseExitNode: exitNode,
		AdvertiseRoutes:   make([]string, len(routes)),
	}
	for i, r := range routes {
		out.AdvertiseRoutes[i] = r.String()
	}
	return out
}

// splitAdvertisedRoutes separates subnet routes from the default routes;
// a node is an exit node only when it advertises both 0.0.0.0/0 and ::/0.
func splitAdvertisedRoutes(all []netip.Prefix) (routes []netip.Prefix, exitNode bool) {
	var v4, v6 bool
	for _, p := range all {
		switch {
		case p.Bits() == 0 && p.Addr().Is4():
			v4 = true
		case p.Bits() == 0:
			v6 = true
		default:
			routes = append(routes, p)
		}
	}
	return routes, v4 && v6
}

func (m *Manager) updateState(state *TailscaleState) {
	m.stateMutex.Lock()
	m.state = state
	m.stateMutex.Unlock()

	m.broadcastState(*state)
}

func (m *Manager) broadcastState(state TailscaleState) {
	if m.closed.Load() {
		return
	}
	m.subscribers.Range(func(key string, ch chan TailscaleState) bool {
		select {
		case ch <- state:
		default:
		}
		return true
	})
}

// IsAvailable reports whether tailscaled has been reachable via the IPN bus
// at least once since the manager started. False means tailscaled appears
// to not be installed or has never been running.
func (m *Manager) IsAvailable() bool {
	return m.available.Load()
}

// SetAvailabilityCallback registers a callback fired when the manager
// transitions from unavailable to available. Replaces any previously set
// callback. Must be set before the manager has a chance to detect tailscaled.
func (m *Manager) SetAvailabilityCallback(cb func(bool)) {
	m.availabilityCallback.Store(&cb)
}

func (m *Manager) markAvailable() {
	if m.available.Swap(true) {
		return
	}
	if cb := m.availabilityCallback.Load(); cb != nil {
		(*cb)(true)
	}
}

// GetState returns a copy of the current Tailscale state.
func (m *Manager) GetState() TailscaleState {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()

	if m.state == nil {
		return TailscaleState{}
	}
	return *m.state
}

// Subscribe creates a buffered channel for the given client ID.
func (m *Manager) Subscribe(clientID string) chan TailscaleState {
	ch := make(chan TailscaleState, 64)
	m.subscribers.Store(clientID, ch)
	return ch
}

// Unsubscribe removes and closes the subscriber channel.
func (m *Manager) Unsubscribe(clientID string) {
	if val, ok := m.subscribers.LoadAndDelete(clientID); ok {
		close(val)
	}
}

// Close stops the watch loop and closes all subscriber channels.
func (m *Manager) Close() {
	m.closed.Store(true)
	m.cancel()
	m.watchWG.Wait()

	m.subscribers.Range(func(key string, ch chan TailscaleState) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})
}

// RefreshState triggers an immediate status fetch and broadcasts.
func (m *Manager) RefreshState() {
	ctx, cancel := context.WithTimeout(m.ctx, statusTimeout)
	defer cancel()

	state, err := m.fetchState(ctx)
	if err != nil {
		log.Warnf("[Tailscale] Failed to refresh state: %v", err)
		return
	}

	m.updateState(state)
}

// Connect brings the Tailscale backend up (WantRunning = true).
func (m *Manager) Connect() error {
	return m.editPrefs(&maskedPrefs{WantRunning: true, WantRunningSet: true})
}

// Disconnect brings the Tailscale backend down (WantRunning = false).
func (m *Manager) Disconnect() error {
	return m.editPrefs(&maskedPrefs{WantRunning: false, WantRunningSet: true})
}

// SetExitNode selects the exit node identified by its stable node ID. An empty
// id clears the current exit node. Mirrors `tailscale set --exit-node=<id>`,
// which also clears any legacy IP-based exit node so a stale ExitNodeIP cannot
// silently take precedence over the now-empty ID.
func (m *Manager) SetExitNode(id string) error {
	return m.editPrefs(&maskedPrefs{ExitNodeID: id, ExitNodeIDSet: true, ExitNodeIPSet: true})
}

// SetAllowLANAccess toggles whether locally accessible subnets remain
// reachable while an exit node is in use.
func (m *Manager) SetAllowLANAccess(enabled bool) error {
	return m.editPrefs(&maskedPrefs{ExitNodeAllowLANAccess: enabled, ExitNodeAllowLANAccessSet: true})
}

// editPrefs applies a masked prefs edit and refreshes state so subscribers see
// the result immediately, in addition to the IPN bus notification it triggers.
func (m *Manager) editPrefs(mp *maskedPrefs) error {
	if err := m.withTimeout(func(ctx context.Context) error { return m.client.EditPrefs(ctx, mp) }); err != nil {
		return err
	}

	m.RefreshState()
	return nil
}

// SetPrefs returns tailscaled's IP forwarding warning, if any. AdvertiseRoutes
// is shared by routes and the exit-node flag, so changing one keeps the other.
func (m *Manager) SetPrefs(p PrefsPatch) (string, error) {
	mp := &maskedPrefs{}
	if p.AcceptRoutes != nil {
		mp.RouteAll, mp.RouteAllSet = *p.AcceptRoutes, true
	}
	if p.AcceptDNS != nil {
		mp.CorpDNS, mp.CorpDNSSet = *p.AcceptDNS, true
	}
	if p.ShieldsUp != nil {
		mp.ShieldsUp, mp.ShieldsUpSet = *p.ShieldsUp, true
	}
	if p.RunSSH != nil {
		mp.RunSSH, mp.RunSSHSet = *p.RunSSH, true
	}
	if p.Hostname != nil {
		mp.Hostname, mp.HostnameSet = *p.Hostname, true
	}

	routesRequested := p.AdvertiseExitNode != nil || p.AdvertiseRoutes != nil
	routesTouched := routesRequested
	if routesTouched {
		routes, current, err := m.advertisedRoutes(p)
		if err != nil {
			return "", err
		}
		if slices.Equal(routes, current) {
			routesTouched = false
		} else {
			mp.AdvertiseRoutes, mp.AdvertiseRoutesSet = routes, true
		}
	}

	if !mp.RouteAllSet && !mp.CorpDNSSet && !mp.ShieldsUpSet && !mp.RunSSHSet && !mp.HostnameSet && !mp.AdvertiseRoutesSet {
		if !routesRequested {
			return "", errors.New("no changes")
		}
		return "", nil
	}

	if err := m.editPrefs(mp); err != nil {
		return "", err
	}

	if !routesTouched || len(mp.AdvertiseRoutes) == 0 {
		return "", nil
	}
	if err := m.withTimeout(m.client.CheckIPForwarding); err != nil {
		return err.Error(), nil
	}
	return "", nil
}

// advertisedRoutes returns the routes to set and the ones currently stored.
func (m *Manager) advertisedRoutes(p PrefsPatch) ([]netip.Prefix, []netip.Prefix, error) {
	if p.AdvertiseRoutes != nil {
		for _, s := range *p.AdvertiseRoutes {
			r, err := netip.ParsePrefix(s)
			if err != nil {
				return nil, nil, fmt.Errorf("invalid route %q", s)
			}
			if r.Bits() == 0 {
				return nil, nil, fmt.Errorf("route %q is a default route; use the exit node setting", s)
			}
		}
	}

	var current *prefs
	err := m.withTimeout(func(ctx context.Context) (err error) {
		current, err = m.client.GetPrefs(ctx)
		return err
	})
	if err != nil {
		return nil, nil, err
	}
	if current == nil {
		return nil, nil, errors.New("tailscaled returned no prefs")
	}
	stored, exitNode := splitAdvertisedRoutes(current.AdvertiseRoutes)

	routes := make([]string, len(stored))
	for i, r := range stored {
		routes[i] = r.String()
	}
	if p.AdvertiseRoutes != nil {
		routes = *p.AdvertiseRoutes
	}
	if p.AdvertiseExitNode != nil {
		exitNode = *p.AdvertiseExitNode
	}
	want, err := calcAdvertiseRoutes(routes, exitNode)
	return want, current.AdvertiseRoutes, err
}

var viaRange = netip.MustParsePrefix("fd7a:115c:a1e0:b1a::/64")

// calcAdvertiseRoutes follows `tailscale set --advertise-routes`: masked
// prefixes, 4via6 site IDs up to 0xffff, deduplicated and sorted.
func calcAdvertiseRoutes(routes []string, exitNode bool) ([]netip.Prefix, error) {
	set := map[netip.Prefix]bool{}
	for _, s := range routes {
		p, err := netip.ParsePrefix(s)
		if err != nil {
			return nil, fmt.Errorf("%q is not a valid IP address or CIDR prefix", s)
		}
		if p != p.Masked() {
			return nil, fmt.Errorf("%s has non-address bits set; expected %s", p, p.Masked())
		}
		if viaRange.Contains(p.Addr()) {
			a := p.Addr().As16()
			if p.Bits() < 96 || binary.BigEndian.Uint32(a[8:12]) > 0xffff {
				return nil, fmt.Errorf("%s is not a valid 4via6 route", p)
			}
		}
		set[p] = true
	}
	if exitNode {
		set[netip.MustParsePrefix("0.0.0.0/0")] = true
		set[netip.MustParsePrefix("::/0")] = true
	}
	if len(set) == 0 {
		return nil, nil
	}
	out := slices.Collect(maps.Keys(set))
	slices.SortFunc(out, func(a, b netip.Prefix) int {
		if c := cmp.Compare(a.Bits(), b.Bits()); c != 0 {
			return c
		}
		return a.Addr().Compare(b.Addr())
	})
	return out, nil
}

func (m *Manager) withTimeout(fn func(ctx context.Context) error) error {
	ctx, cancel := context.WithTimeout(m.ctx, statusTimeout)
	defer cancel()
	return fn(ctx)
}

// Login starts an interactive login; the URL to open arrives on the IPN bus
// and surfaces as TailscaleState.AuthURL.
func (m *Manager) Login() error {
	m.setAuthURL(nil)
	return m.withTimeout(m.client.StartLoginInteractive)
}

func (m *Manager) Logout() error {
	m.setAuthURL(nil)
	if err := m.withTimeout(m.client.Logout); err != nil {
		return err
	}
	m.RefreshState()
	return nil
}

// Profiles lists the known accounts. ProfileStatus needs LocalAPI write
// access, so an access-denied error means DMS cannot change Tailscale.
func (m *Manager) Profiles() (ProfilesResult, error) {
	var current loginProfile
	var all []loginProfile
	err := m.withTimeout(func(ctx context.Context) (err error) {
		current, all, err = m.client.ProfileStatus(ctx)
		return err
	})
	if errors.Is(err, errAccessDenied) {
		return ProfilesResult{}, nil
	}
	if err != nil {
		return ProfilesResult{}, err
	}

	res := ProfilesResult{
		CanOperate: true,
		Current:    current.ID,
		Profiles:   make([]TailscaleProfile, len(all)),
	}
	for i, p := range all {
		tailnet := p.NetworkProfile.DisplayName
		if tailnet == "" {
			tailnet = p.NetworkProfile.DomainName
		}
		res.Profiles[i] = TailscaleProfile{ID: p.ID, Name: p.Name, Tailnet: tailnet}
	}
	slices.SortFunc(res.Profiles, func(a, b TailscaleProfile) int { return strings.Compare(a.Name, b.Name) })
	return res, nil
}

func (m *Manager) SwitchProfile(id string) error {
	if id == "" {
		return errors.New("profile id is required")
	}
	m.setAuthURL(nil)
	err := m.withTimeout(func(ctx context.Context) error {
		return m.client.SwitchProfile(ctx, id)
	})
	if err != nil {
		return err
	}
	m.RefreshState()
	return nil
}

// AddProfile switches to a new empty profile and starts logging it in.
func (m *Manager) AddProfile() error {
	m.setAuthURL(nil)
	return m.withTimeout(func(ctx context.Context) error {
		if err := m.client.SwitchToEmptyProfile(ctx); err != nil {
			return err
		}
		return m.client.StartLoginInteractive(ctx)
	})
}

func (m *Manager) SuggestExitNode() (ExitNodeSuggestion, error) {
	var s ExitNodeSuggestion
	err := m.withTimeout(func(ctx context.Context) (err error) {
		s, err = m.client.SuggestExitNode(ctx)
		return err
	})
	return s, err
}
