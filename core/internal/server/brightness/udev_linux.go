package brightness

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/pilebones/go-udev/netlink"
)

const (
	udevRecvBufSize  = 8 * 1024 * 1024
	udevMaxRetries   = 5
	udevBaseDelay    = 2 * time.Second
	udevMaxDelay     = 60 * time.Second
	udevStableUptime = time.Minute
)

var errUdevStreamClosed = errors.New("event stream closed")

type UdevMonitor struct {
	stop          chan struct{}
	rescanMutex   sync.Mutex
	rescanTimer   *time.Timer
	rescanPending bool
}

func NewUdevMonitor(manager *Manager) *UdevMonitor {
	m := &UdevMonitor{
		stop: make(chan struct{}),
	}

	go m.run(manager)
	return m
}

func (m *UdevMonitor) run(manager *Manager) {
	matcher := &netlink.RuleDefinitions{
		Rules: []netlink.RuleDefinition{
			{Env: map[string]string{"SUBSYSTEM": "backlight"}},
			{Env: map[string]string{"SUBSYSTEM": "drm"}},
			{Env: map[string]string{"SUBSYSTEM": "i2c"}},
		},
	}
	if err := matcher.Compile(); err != nil {
		log.Errorf("Failed to compile udev matcher: %v", err)
		return
	}

	failures := 0
	for {
		started := time.Now()
		if err := m.monitorLoop(manager, matcher); err != nil {
			log.Errorf("Udev monitor error: %v", err)
		}

		select {
		case <-m.stop:
			return
		default:
		}

		if time.Since(started) >= udevStableUptime {
			failures = 0
		}

		failures++
		if failures > udevMaxRetries {
			log.Errorf("Udev monitor exceeded %d retries, giving up", udevMaxRetries)
			return
		}

		delay := min(udevBaseDelay*time.Duration(1<<(failures-1)), udevMaxDelay)
		log.Infof("Udev monitor reconnecting in %v (attempt %d/%d)", delay, failures, udevMaxRetries)

		select {
		case <-m.stop:
			return
		case <-time.After(delay):
		}
	}
}

func (m *UdevMonitor) monitorLoop(manager *Manager, matcher *netlink.RuleDefinitions) error {
	conn := &netlink.UEventConn{ReceiveBufferSize: udevRecvBufSize}
	if err := conn.Connect(netlink.UdevEvent); err != nil {
		return err
	}

	ctx, cancel := context.WithCancel(context.Background())
	events := make(chan netlink.UEvent)
	errs := make(chan error)
	go conn.MonitorWithContext(ctx, events, errs, matcher)

	defer func() {
		cancel()
		for range events {
		}
		conn.Close()
	}()

	log.Info("Udev monitor started for backlight/drm/i2c events")

	return m.consume(manager, events, errs)
}

func (m *UdevMonitor) consume(manager *Manager, events <-chan netlink.UEvent, errs <-chan error) error {
	for {
		select {
		case <-m.stop:
			return nil
		case err := <-errs:
			log.Warnf("Udev monitor: %v", err)
		case event, ok := <-events:
			if !ok {
				return errUdevStreamClosed
			}
			m.handleEvent(manager, event)
		}
	}
}

func (m *UdevMonitor) handleEvent(manager *Manager, event netlink.UEvent) {
	subsystem := event.Env["SUBSYSTEM"]
	devpath := event.Env["DEVPATH"]

	if subsystem == "" || devpath == "" {
		return
	}

	sysname := filepath.Base(devpath)
	action := string(event.Action)

	switch subsystem {
	case "drm", "i2c":
		m.handleDisplayEvent(manager, action, subsystem, sysname)
	case "backlight":
		m.handleBacklightEvent(manager, action, sysname)
	}
}

func (m *UdevMonitor) handleDisplayEvent(manager *Manager, action, subsystem, sysname string) {
	switch action {
	case "add", "remove", "change":
		log.Debugf("Udev %s event: %s:%s - queueing DDC rescan", action, subsystem, sysname)
		m.debouncedRescan(manager)
	}
}

func (m *UdevMonitor) debouncedRescan(manager *Manager) {
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

		log.Debug("Executing debounced DDC rescan")
		manager.Rescan()
	})
}

func (m *UdevMonitor) handleBacklightEvent(manager *Manager, action, sysname string) {
	switch action {
	case "change":
		m.handleChange(manager, "backlight", sysname)
	case "add", "remove":
		log.Debugf("Udev %s event: backlight:%s - triggering rescan", action, sysname)
		manager.Rescan()
	}
}

func (m *UdevMonitor) handleChange(manager *Manager, subsystem, sysname string) {
	deviceID := subsystem + ":" + sysname

	if manager.sysfsBackend == nil {
		return
	}

	brightnessPath := filepath.Join(manager.sysfsBackend.basePath, subsystem, sysname, "brightness")
	data, err := os.ReadFile(brightnessPath)
	if err != nil {
		log.Debugf("Udev change event for %s but failed to read brightness: %v", deviceID, err)
		return
	}

	brightness, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		log.Debugf("Failed to parse brightness for %s: %v", deviceID, err)
		return
	}

	manager.handleUdevBrightnessChange(deviceID, brightness)
}

func (m *UdevMonitor) Close() {
	close(m.stop)
}

func (m *Manager) handleUdevBrightnessChange(deviceID string, rawBrightness int) {
	if m.sysfsBackend == nil {
		return
	}

	dev, err := m.sysfsBackend.GetDevice(deviceID)
	if err != nil {
		log.Debugf("Udev event for unknown device %s: %v", deviceID, err)
		return
	}

	percent := m.sysfsBackend.ValueToPercent(rawBrightness, dev, false)

	m.stateMutex.Lock()
	var found bool
	for i, d := range m.state.Devices {
		if d.ID != deviceID {
			continue
		}
		found = true
		if d.Current == rawBrightness {
			m.stateMutex.Unlock()
			return
		}
		m.state.Devices[i].Current = rawBrightness
		m.state.Devices[i].CurrentPercent = percent
		break
	}
	m.stateMutex.Unlock()

	if !found {
		log.Debugf("Udev event for device not in state: %s", deviceID)
		return
	}

	log.Debugf("Udev brightness change: %s -> %d (%d%%)", deviceID, rawBrightness, percent)
	m.broadcastDeviceUpdate(deviceID)
}
