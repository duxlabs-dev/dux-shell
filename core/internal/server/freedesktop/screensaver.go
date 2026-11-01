package freedesktop

import (
	"fmt"
	"path/filepath"
	"strings"
	"sync/atomic"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
)

type screensaverHandler struct {
	manager *Manager
}

func screensaverIntrospectIface(ifaceName string) introspect.Interface {
	return introspect.Interface{
		Name: ifaceName,
		Methods: []introspect.Method{
			{
				Name: "Inhibit",
				Args: []introspect.Arg{
					{Name: "application_name", Type: "s", Direction: "in"},
					{Name: "reason_for_inhibit", Type: "s", Direction: "in"},
					{Name: "cookie", Type: "u", Direction: "out"},
				},
			},
			{
				Name: "UnInhibit",
				Args: []introspect.Arg{
					{Name: "cookie", Type: "u", Direction: "in"},
				},
			},
			{
				Name: "GetActive",
				Args: []introspect.Arg{
					{Name: "active", Type: "b", Direction: "out"},
				},
			},
			{
				Name: "SetActive",
				Args: []introspect.Arg{
					{Name: "active", Type: "b", Direction: "in"},
				},
			},
			{
				Name: "Lock",
			},
		},
		Signals: []introspect.Signal{
			{
				Name: "ActiveChanged",
				Args: []introspect.Arg{
					{Name: "new_value", Type: "b"},
				},
			},
		},
	}
}

func (m *Manager) initializeScreensaver() error {
	if m.sessionConn == nil {
		m.stateMutex.Lock()
		m.state.Screensaver.Available = false
		m.stateMutex.Unlock()
		return nil
	}

	handler := &screensaverHandler{manager: m}

	m.screensaverFreedesktopClaimed = m.claimScreensaverName(handler,
		dbusScreensaverName, dbusScreensaverInterface, dbusScreensaverPath, dbusScreensaverPath2)
	m.screensaverGnomeClaimed = m.claimScreensaverName(handler,
		dbusGnomeScreensaverName, dbusGnomeScreensaverInterface, dbusGnomeScreensaverPath)

	if !m.screensaverFreedesktopClaimed && !m.screensaverGnomeClaimed {
		log.Warn("No screensaver interface could be claimed")
		m.stateMutex.Lock()
		m.state.Screensaver.Available = false
		m.stateMutex.Unlock()
		return nil
	}

	go m.watchPeerDisconnects()

	m.stateMutex.Lock()
	m.state.Screensaver.Available = true
	m.state.Screensaver.Active = false
	m.state.Screensaver.Inhibited = false
	m.state.Screensaver.Inhibitors = []ScreensaverInhibitor{}
	m.stateMutex.Unlock()

	log.Info("Screensaver listener initialized")
	return nil
}

func (m *Manager) claimScreensaverName(handler *screensaverHandler, name, iface string, paths ...dbus.ObjectPath) bool {
	reply, err := m.sessionConn.RequestName(name, dbus.NameFlagDoNotQueue)
	if err != nil {
		log.Warnf("Failed to request screensaver name %s: %v", name, err)
		return false
	}
	if reply != dbus.RequestNameReplyPrimaryOwner {
		log.Infof("Screensaver name %s already owned by another process (e.g. hypridle/swayidle)", name)
		return false
	}
	if err := m.exportScreensaverOnPaths(handler, iface, paths...); err != nil {
		log.Warnf("Failed to export screensaver on %s: %v", name, err)
		return false
	}
	log.Infof("Claimed %s on session bus", name)
	return true
}

// exportScreensaverOnPaths exports the handler and introspection on the given
// paths under the specified interface name.
func (m *Manager) exportScreensaverOnPaths(handler *screensaverHandler, ifaceName string, paths ...dbus.ObjectPath) error {
	iface := screensaverIntrospectIface(ifaceName)
	for _, path := range paths {
		if err := m.sessionConn.Export(handler, path, ifaceName); err != nil {
			return fmt.Errorf("export handler on %s: %w", path, err)
		}
		node := &introspect.Node{
			Name: string(path),
			Interfaces: []introspect.Interface{
				introspect.IntrospectData,
				iface,
			},
		}
		if err := m.sessionConn.Export(introspect.NewIntrospectable(node), path, "org.freedesktop.DBus.Introspectable"); err != nil {
			log.Warnf("Failed to export introspectable on %s: %v", path, err)
		}
	}
	return nil
}

func (h *screensaverHandler) Inhibit(sender dbus.Sender, appName, reason string) (uint32, *dbus.Error) {
	if appName == "" {
		return 0, dbus.NewError("org.freedesktop.DBus.Error.InvalidArgs", []any{"application name required"})
	}

	if reason == "" {
		return 0, dbus.NewError("org.freedesktop.DBus.Error.InvalidArgs", []any{"reason required"})
	}

	if strings.Contains(strings.ToLower(reason), "audio") && !strings.Contains(strings.ToLower(reason), "video") {
		log.Debugf("Ignoring audio-only inhibit from %s: %s", appName, reason)
		return 0, nil
	}

	if idx := strings.LastIndex(appName, "/"); idx != -1 && idx < len(appName)-1 {
		appName = appName[idx+1:]
	}
	appName = filepath.Base(appName)

	cookie := atomic.AddUint32(&h.manager.screensaverCookieCounter, 1)

	inhibitor := ScreensaverInhibitor{
		Cookie:    cookie,
		AppName:   appName,
		Reason:    reason,
		Peer:      string(sender),
		StartTime: time.Now().Unix(),
	}

	h.manager.stateMutex.Lock()
	h.manager.state.Screensaver.Inhibitors = append(h.manager.state.Screensaver.Inhibitors, inhibitor)
	h.manager.state.Screensaver.Inhibited = len(h.manager.state.Screensaver.Inhibitors) > 0
	h.manager.stateMutex.Unlock()

	log.Infof("Screensaver inhibited by %s (%s): %s -> cookie %08X", appName, sender, reason, cookie)

	h.manager.NotifyScreensaverSubscribers()

	return cookie, nil
}

func (h *screensaverHandler) UnInhibit(sender dbus.Sender, cookie uint32) *dbus.Error {
	h.manager.stateMutex.Lock()
	defer h.manager.stateMutex.Unlock()

	found := false
	inhibitors := h.manager.state.Screensaver.Inhibitors
	for i, inh := range inhibitors {
		if inh.Cookie != cookie {
			continue
		}
		log.Infof("Screensaver uninhibited by %s (%s) cookie %08X", inh.AppName, sender, cookie)
		h.manager.state.Screensaver.Inhibitors = append(inhibitors[:i], inhibitors[i+1:]...)
		found = true
		break
	}

	if !found {
		log.Debugf("UnInhibit: no match for cookie %08X", cookie)
		return nil
	}

	h.manager.state.Screensaver.Inhibited = len(h.manager.state.Screensaver.Inhibitors) > 0

	go h.manager.NotifyScreensaverSubscribers()

	return nil
}

func (m *Manager) watchPeerDisconnects() {
	if m.sessionConn == nil {
		return
	}

	if err := m.sessionConn.AddMatchSignal(
		dbus.WithMatchInterface("org.freedesktop.DBus"),
		dbus.WithMatchMember("NameOwnerChanged"),
	); err != nil {
		log.Warnf("Failed to watch peer disconnects: %v", err)
		return
	}

	signals := make(chan *dbus.Signal, 64)
	m.sessionConn.Signal(signals)

	for sig := range signals {
		if sig.Name != "org.freedesktop.DBus.NameOwnerChanged" {
			continue
		}
		if len(sig.Body) < 3 {
			continue
		}

		name, ok1 := sig.Body[0].(string)
		newOwner, ok2 := sig.Body[2].(string)
		if !ok1 || !ok2 {
			continue
		}
		if newOwner != "" {
			continue
		}

		m.removeInhibitorsByPeer(name)
	}
}

func (m *Manager) removeInhibitorsByPeer(peer string) {
	m.stateMutex.Lock()
	defer m.stateMutex.Unlock()

	var remaining []ScreensaverInhibitor
	var removed []ScreensaverInhibitor
	for _, inh := range m.state.Screensaver.Inhibitors {
		if inh.Peer == peer {
			removed = append(removed, inh)
			continue
		}
		remaining = append(remaining, inh)
	}

	if len(removed) == 0 {
		return
	}

	for _, inh := range removed {
		log.Infof("Screensaver: peer %s died, removing inhibitor from %s (cookie %08X)", peer, inh.AppName, inh.Cookie)
	}

	m.state.Screensaver.Inhibitors = remaining
	m.state.Screensaver.Inhibited = len(remaining) > 0

	go m.NotifyScreensaverSubscribers()
}

func (m *Manager) GetScreensaverState() ScreensaverState {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	return m.state.Screensaver
}

func (m *Manager) SubscribeScreensaver(id string) chan ScreensaverState {
	ch := make(chan ScreensaverState, 64)
	m.screensaverSubscribers.Store(id, ch)
	return ch
}

func (m *Manager) UnsubscribeScreensaver(id string) {
	if val, ok := m.screensaverSubscribers.LoadAndDelete(id); ok {
		close(val)
	}
}

func (m *Manager) NotifyScreensaverSubscribers() {
	state := m.GetScreensaverState()
	m.screensaverSubscribers.Range(func(key string, ch chan ScreensaverState) bool {
		select {
		case ch <- state:
		default:
		}
		return true
	})
}

func (h *screensaverHandler) GetActive() (bool, *dbus.Error) {
	h.manager.stateMutex.RLock()
	active := h.manager.state.Screensaver.Active
	h.manager.stateMutex.RUnlock()
	return active, nil
}

func (h *screensaverHandler) SetActive(active bool) *dbus.Error {
	h.manager.SetScreenLockActive(active)
	return nil
}

func (h *screensaverHandler) Lock() *dbus.Error {
	h.manager.SetScreenLockActive(true)
	return nil
}

func (m *Manager) SetScreenLockActive(active bool) {
	m.stateMutex.Lock()
	changed := m.state.Screensaver.Active != active
	m.state.Screensaver.Active = active
	m.stateMutex.Unlock()

	if !changed {
		return
	}

	log.Infof("Screen lock active changed: %v", active)
	defer m.NotifyScreensaverSubscribers()

	if m.sessionConn == nil {
		return
	}
	if m.screensaverFreedesktopClaimed {
		if err := m.sessionConn.Emit(dbusScreensaverPath, dbusScreensaverInterface+".ActiveChanged", active); err != nil {
			log.Warnf("Failed to emit ActiveChanged on %s: %v", dbusScreensaverPath, err)
		}
		if err := m.sessionConn.Emit(dbusScreensaverPath2, dbusScreensaverInterface+".ActiveChanged", active); err != nil {
			log.Warnf("Failed to emit ActiveChanged on %s: %v", dbusScreensaverPath2, err)
		}
	}
	if m.screensaverGnomeClaimed {
		if err := m.sessionConn.Emit(dbusGnomeScreensaverPath, dbusGnomeScreensaverInterface+".ActiveChanged", active); err != nil {
			log.Warnf("Failed to emit ActiveChanged on %s: %v", dbusGnomeScreensaverPath, err)
		}
	}
}
