package browser

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

func (m *Manager) Unsubscribe(id string) {
	m.broker.Unsubscribe(id)
}

func (m *Manager) RequestOpen(url string) {
	m.broker.Publish(OpenEvent{URL: url})
}

func (m *Manager) Close() {
	m.broker.Close()
}
