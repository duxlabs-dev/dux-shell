package browser

import (
	"sync"

	"github.com/duxlabs-dev/dux-go/syncmap"
)

type Manager struct {
	subscribers syncmap.Map[string, chan OpenEvent]
	closeOnce   sync.Once
}

func NewManager() *Manager {
	return &Manager{}
}

func (m *Manager) Subscribe(id string) chan OpenEvent {
	ch := make(chan OpenEvent, 16)
	m.subscribers.Store(id, ch)
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)
	}
}

func (m *Manager) RequestOpen(url string) {
	event := OpenEvent{URL: url}
	m.subscribers.Range(func(key string, ch chan OpenEvent) bool {
		select {
		case ch <- event:
		default:
		}
		return true
	})
}

func (m *Manager) Close() {
	m.closeOnce.Do(func() {
		m.subscribers.Range(func(key string, ch chan OpenEvent) bool {
			close(ch)
			m.subscribers.Delete(key)
			return true
		})
	})
}
