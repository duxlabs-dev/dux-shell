package notifyactions

import (
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"

	"github.com/godbus/dbus/v5"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

const (
	notifyPath       = "/org/freedesktop/Notifications"
	notifyInterface  = "org.freedesktop.Notifications"
	actionInvoked    = notifyInterface + ".ActionInvoked"
	closed           = notifyInterface + ".NotificationClosed"
	dbusInterface    = "org.freedesktop.DBus"
	nameOwnerChanged = "NameOwnerChanged"
	ownerChanged     = dbusInterface + "." + nameOwnerChanged
)

type watched struct {
	path    string
	command []string
}

type Manager struct {
	conn    *dbus.Conn
	signals chan *dbus.Signal
	mu      sync.Mutex
	watched map[uint32]watched
}

func NewManager() (*Manager, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, err
	}
	if err := conn.AddMatchSignal(dbus.WithMatchObjectPath(notifyPath), dbus.WithMatchInterface(notifyInterface)); err != nil {
		return nil, err
	}
	// A restarted notification server reuses ids without sending NotificationClosed.
	if err := conn.AddMatchSignal(dbus.WithMatchInterface(dbusInterface), dbus.WithMatchMember(nameOwnerChanged), dbus.WithMatchArg(0, notifyInterface)); err != nil {
		return nil, err
	}
	m := &Manager{
		conn:    conn,
		signals: make(chan *dbus.Signal, 32),
		watched: make(map[uint32]watched),
	}
	conn.Signal(m.signals)
	go m.loop()
	return m, nil
}

func (m *Manager) Watch(id uint32, path string) {
	m.mu.Lock()
	m.watched[id] = watched{path: path}
	m.mu.Unlock()
}

func (m *Manager) WatchCommand(id uint32, argv []string) {
	m.mu.Lock()
	m.watched[id] = watched{command: argv}
	m.mu.Unlock()
}

func (m *Manager) Close() {
	m.conn.RemoveSignal(m.signals)
	_ = m.conn.RemoveMatchSignal(dbus.WithMatchObjectPath(notifyPath), dbus.WithMatchInterface(notifyInterface))
	_ = m.conn.RemoveMatchSignal(dbus.WithMatchInterface(dbusInterface), dbus.WithMatchMember(nameOwnerChanged), dbus.WithMatchArg(0, notifyInterface))
	close(m.signals)
}

func (m *Manager) loop() {
	for sig := range m.signals {
		switch sig.Name {
		case actionInvoked:
			m.handleAction(sig)
		case closed:
			m.forget(sig)
		case ownerChanged:
			// The shared bus connection also delivers other managers' NameOwnerChanged matches.
			if len(sig.Body) < 1 || sig.Body[0] != notifyInterface {
				continue
			}
			m.mu.Lock()
			clear(m.watched)
			m.mu.Unlock()
		}
	}
}

func (m *Manager) take(sig *dbus.Signal) (watched, bool) {
	if len(sig.Body) < 1 {
		return watched{}, false
	}
	id, ok := sig.Body[0].(uint32)
	if !ok {
		return watched{}, false
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	w, ok := m.watched[id]
	if !ok {
		return watched{}, false
	}
	delete(m.watched, id)
	return w, true
}

func (m *Manager) forget(sig *dbus.Signal) {
	m.take(sig)
}

func (m *Manager) handleAction(sig *dbus.Signal) {
	if len(sig.Body) < 2 {
		return
	}
	action, ok := sig.Body[1].(string)
	if !ok {
		return
	}
	w, ok := m.take(sig)
	if !ok {
		return
	}
	if len(w.command) > 0 {
		if action == "default" {
			run(w.command)
		}
		return
	}
	path := w.path
	if action == "folder" {
		path = filepath.Dir(path)
	}
	run([]string{"xdg-open", path})
}

func run(argv []string) {
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		log.Warnf("notifyactions: %v: %v", argv, err)
		return
	}
	go func() { _ = cmd.Wait() }()
}
