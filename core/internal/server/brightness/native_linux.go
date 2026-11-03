package brightness

import (
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

func (m *Manager) initNative() {
	log.Debug("Initializing sysfs backend...")
	sysfs, err := NewSysfsBackend()
	if err != nil {
		log.Warnf("Failed to initialize sysfs backend: %v", err)
		return
	}

	devices, err := sysfs.GetDevices()
	if err != nil {
		log.Warnf("Failed to get initial sysfs devices: %v", err)
		m.sysfsBackend = sysfs
		m.nativeBackend = sysfs
		m.nativeReady = true
		m.updateState()
		m.monitor = NewUdevMonitor(m)
		return
	}

	log.Infof("Sysfs backend initialized with %d devices", len(devices))
	for _, d := range devices {
		log.Debugf("  - %s: %s (%d%%)", d.ID, d.Name, d.CurrentPercent)
	}

	m.sysfsBackend = sysfs
	m.nativeBackend = sysfs
	m.nativeReady = true
	m.updateState()
	m.monitor = NewUdevMonitor(m)
}
