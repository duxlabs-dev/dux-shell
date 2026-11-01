package brightness

import (
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

func (m *Manager) initNative() {
	log.Debug("Initializing backlight backend...")
	backend, err := NewBacklightBackend()
	if err != nil {
		log.Warnf("Failed to initialize backlight backend: %v", err)
		return
	}

	devices, err := backend.GetDevices()
	if err == nil {
		log.Infof("Backlight backend initialized with %d devices", len(devices))
	}

	m.nativeBackend = backend
	m.nativeReady = true
	m.updateState()
	m.monitor = newDevdMonitor(m)
}
