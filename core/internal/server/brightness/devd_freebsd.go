package brightness

import (
	"net"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

// devd(8) publishes device events on this SOCK_SEQPACKET socket, one
// "!system=... subsystem=... type=..." record per packet.
const devdSocketPath = "/var/run/devd.seqpacket.pipe"

const (
	devdMaxRetries = 5
	devdBaseDelay  = 2 * time.Second
	devdMaxDelay   = 60 * time.Second
)

type DevdMonitor struct {
	stop          chan struct{}
	rescanMutex   sync.Mutex
	rescanTimer   *time.Timer
	rescanPending bool
}

func newDevdMonitor(manager *Manager) *DevdMonitor {
	m := &DevdMonitor{
		stop: make(chan struct{}),
	}

	go m.run(manager)
	return m
}

func (m *DevdMonitor) run(manager *Manager) {
	failures := 0
	for {
		if err := m.monitorLoop(manager); err != nil {
			log.Errorf("Devd monitor error: %v", err)
		}

		select {
		case <-m.stop:
			return
		default:
		}

		failures++
		if failures > devdMaxRetries {
			log.Errorf("Devd monitor exceeded %d retries, giving up", devdMaxRetries)
			return
		}

		delay := min(devdBaseDelay*time.Duration(1<<(failures-1)), devdMaxDelay)
		log.Infof("Devd monitor reconnecting in %v (attempt %d/%d)", delay, failures, devdMaxRetries)

		select {
		case <-m.stop:
			return
		case <-time.After(delay):
		}
	}
}

func (m *DevdMonitor) monitorLoop(manager *Manager) error {
	conn, err := net.Dial("unixpacket", devdSocketPath)
	if err != nil {
		return err
	}
	defer conn.Close()

	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-m.stop:
			conn.Close()
		case <-done:
		}
	}()

	log.Info("Devd monitor started for backlight/drm events")

	buf := make([]byte, 8192)
	for {
		n, err := conn.Read(buf)
		if err != nil {
			select {
			case <-m.stop:
				return nil
			default:
				return err
			}
		}
		m.handleEvent(manager, string(buf[:n]))
	}
}

func (m *DevdMonitor) handleEvent(manager *Manager, event string) {
	notification, ok := strings.CutPrefix(event, "!")
	if !ok {
		return
	}

	fields := parseDevdEvent(notification)
	switch fields["system"] {
	case "DRM":
		m.debouncedRescan(manager)
	case "DEVFS":
		if fields["subsystem"] != "CDEV" {
			return
		}
		if !strings.HasPrefix(fields["cdev"], "backlight/") {
			return
		}
		m.debouncedRescan(manager)
	}
}

func parseDevdEvent(s string) map[string]string {
	fields := make(map[string]string)
	for _, part := range strings.Fields(s) {
		k, v, ok := strings.Cut(part, "=")
		if !ok {
			continue
		}
		fields[k] = v
	}
	return fields
}

func (m *DevdMonitor) debouncedRescan(manager *Manager) {
	m.rescanMutex.Lock()
	defer m.rescanMutex.Unlock()

	m.rescanPending = true

	if m.rescanTimer != nil {
		m.rescanTimer.Reset(2 * time.Second)
		return
	}

	m.rescanTimer = time.AfterFunc(2*time.Second, func() {
		m.rescanMutex.Lock()
		pending := m.rescanPending
		m.rescanPending = false
		m.rescanMutex.Unlock()

		if !pending {
			return
		}

		manager.Rescan()
	})
}

func (m *DevdMonitor) Close() {
	close(m.stop)
}
