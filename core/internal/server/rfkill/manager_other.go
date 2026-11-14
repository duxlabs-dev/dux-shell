//go:build !linux

package rfkill

import "fmt"

type Manager struct{}

func InitializeManager() (*Manager, error) {
	return nil, fmt.Errorf("rfkill monitoring is only supported on Linux")
}

func (m *Manager) GetState() State {
	return State{}
}

func (m *Manager) Subscribe(id string) chan State {
	return make(chan State)
}

func (m *Manager) Unsubscribe(id string) {}

func (m *Manager) Close() {}
