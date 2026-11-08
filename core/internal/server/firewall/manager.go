package firewall

import (
	"errors"
	"reflect"
	"slices"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

const refreshDebounce = 500 * time.Millisecond

type Manager struct {
	firewalld Backend
	ufw       Backend

	stateMu   sync.RWMutex
	state     State
	refreshMu sync.Mutex
	writeMu   sync.Mutex

	subscribersMu sync.Mutex
	subscribers   map[string]chan State

	dirty chan struct{}
	stop  chan struct{}
	wg    sync.WaitGroup
}

func NewManager() (*Manager, error) {
	var fw, ufw Backend
	installed := Installed()
	if slices.Contains(installed, BackendFirewalld) {
		backend, err := newFirewalldBackend()
		if err != nil {
			log.Warnf("[Firewall] firewalld unavailable: %v", err)
		} else {
			fw = backend
		}
	}
	if slices.Contains(installed, BackendUFW) {
		ufw = newUFWBackend()
	}
	if fw == nil && ufw == nil {
		return nil, errors.New("no supported firewall installed")
	}

	m := newManager(fw, ufw)
	for _, backend := range m.backends() {
		if err := backend.Start(m.markDirty); err != nil {
			log.Warnf("[Firewall] %s watcher failed: %v", backend.Name(), err)
		}
	}
	m.wg.Go(m.refreshLoop)
	return m, nil
}

func newManager(fw, ufw Backend) *Manager {
	m := &Manager{
		firewalld:   fw,
		ufw:         ufw,
		subscribers: map[string]chan State{},
		dirty:       make(chan struct{}, 1),
		stop:        make(chan struct{}),
	}
	m.refresh()
	return m
}

func (m *Manager) backends() []Backend {
	backends := []Backend{}
	if m.firewalld != nil {
		backends = append(backends, m.firewalld)
	}
	if m.ufw != nil {
		backends = append(backends, m.ufw)
	}
	return backends
}

// A stopped firewalld has no API at all, so ufw wins unless firewalld is actually up.
func (m *Manager) active() Backend {
	if m.firewalld != nil && m.firewalld.Running() {
		return m.firewalld
	}
	if m.ufw != nil {
		return m.ufw
	}
	return m.firewalld
}

func (m *Manager) refresh() {
	m.refreshMu.Lock()
	defer m.refreshMu.Unlock()

	state, err := m.active().Snapshot()
	if err != nil {
		log.Warnf("[Firewall] refresh failed: %v", err)
		state.Error = err.Error()
	}
	for _, backend := range m.backends() {
		state.Installed = append(state.Installed, backend.Name())
	}
	state.Conflict = m.firewalld != nil && m.ufw != nil && m.firewalld.Running() && m.ufw.Running()

	m.stateMu.Lock()
	changed := !reflect.DeepEqual(m.state, state)
	m.state = state
	m.stateMu.Unlock()
	if !changed {
		return
	}
	m.subscribersMu.Lock()
	defer m.subscribersMu.Unlock()
	for _, ch := range m.subscribers {
		select {
		case ch <- state:
		default:
		}
	}
}

func (m *Manager) markDirty() {
	select {
	case m.dirty <- struct{}{}:
	default:
	}
}

// Docker bridge churn fires bursts of signals, which should cost one refresh.
func (m *Manager) refreshLoop() {
	timer := time.NewTimer(refreshDebounce)
	timer.Stop()
	for {
		select {
		case <-m.stop:
			timer.Stop()
			return
		case <-m.dirty:
			timer.Reset(refreshDebounce)
		case <-timer.C:
			m.refresh()
		}
	}
}

func (m *Manager) GetState() State {
	m.stateMu.RLock()
	defer m.stateMu.RUnlock()
	return m.state
}

func (m *Manager) Subscribe(id string) chan State {
	ch := make(chan State, 16)
	m.subscribersMu.Lock()
	defer m.subscribersMu.Unlock()
	m.subscribers[id] = ch
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	m.subscribersMu.Lock()
	defer m.subscribersMu.Unlock()
	if ch, ok := m.subscribers[id]; ok {
		delete(m.subscribers, id)
		close(ch)
	}
}

func (m *Manager) write(apply func(Backend) error) error {
	m.writeMu.Lock()
	defer m.writeMu.Unlock()
	err := apply(m.active())
	m.refresh()
	return err
}

func (m *Manager) Unlock() error {
	return m.write(func(b Backend) error { return b.Unlock() })
}

func (m *Manager) AddRule(zone string, spec RuleSpec) error {
	if err := spec.Validate(); err != nil {
		return err
	}
	return m.write(func(b Backend) error { return b.AddRule(zone, spec) })
}

func (m *Manager) RemoveRule(zone, id string) error {
	return m.write(func(b Backend) error { return b.RemoveRule(zone, id) })
}

func (m *Manager) SetDefaults(change DefaultsChange) error {
	return m.write(func(b Backend) error { return b.SetDefaults(change) })
}

func (m *Manager) SetInterfaceZone(iface, zone string) error {
	return m.write(func(b Backend) error { return b.SetInterfaceZone(iface, zone) })
}

func (m *Manager) AddZone(name string) error {
	return m.write(func(b Backend) error { return b.AddZone(name) })
}

func (m *Manager) RenameZone(name, newName string) error {
	return m.write(func(b Backend) error { return b.RenameZone(name, newName) })
}

func (m *Manager) RemoveZone(name string) error {
	return m.write(func(b Backend) error { return b.RemoveZone(name) })
}

func (m *Manager) ListServices() ([]Service, error) {
	return m.active().ListServices()
}

func (m *Manager) Close() {
	close(m.stop)
	m.wg.Wait()
	for _, backend := range m.backends() {
		backend.Close()
	}
	m.subscribersMu.Lock()
	defer m.subscribersMu.Unlock()
	for id, ch := range m.subscribers {
		delete(m.subscribers, id)
		close(ch)
	}
}
