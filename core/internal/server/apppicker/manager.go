package apppicker

import "github.com/duxlabs-dev/dux-shell/core/internal/server/pubsub"

type Manager struct {
	broker *pubsub.Broker[OpenEvent]
}

func NewManager() *Manager {
	return &Manager{broker: pubsub.NewBroker[OpenEvent](16)}
}

func (m *Manager) Subscribe(id string) chan OpenEvent {
	return m.broker.Subscribe(id)
}

func (m *Manager) Unsubscribe(id string, ch chan OpenEvent) {
	m.broker.Unsubscribe(id, ch)
}

func (m *Manager) RequestOpen(event OpenEvent) {
	m.broker.Publish(event)
}

func (m *Manager) Close() {
	m.broker.Close()
}
