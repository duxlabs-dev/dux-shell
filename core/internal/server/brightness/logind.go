package brightness

import (
	"fmt"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

type DBusConn interface {
	Object(dest string, path dbus.ObjectPath) dbus.BusObject
}

type LogindBackend struct {
	conn DBusConn
}

func NewLogindBackend() (*LogindBackend, error) {
	conn, err := dbus.SystemBus()
	if err != nil {
		return nil, fmt.Errorf("connect to system bus: %w", err)
	}

	obj := conn.Object("org.freedesktop.login1", "/org/freedesktop/login1/session/auto")
	call := obj.Call("org.freedesktop.DBus.Peer.Ping", 0)
	if call.Err != nil {
		return nil, fmt.Errorf("logind not available: %w", call.Err)
	}

	return &LogindBackend{conn: conn}, nil
}

func NewLogindBackendWithConn(conn DBusConn) *LogindBackend {
	return &LogindBackend{
		conn: conn,
	}
}

func (b *LogindBackend) SetBrightness(subsystem, name string, brightness uint32) error {
	if b.conn == nil {
		conn, err := dbus.SystemBus()
		if err != nil {
			return fmt.Errorf("connect to system bus: %w", err)
		}
		b.conn = conn
	}

	obj := b.conn.Object("org.freedesktop.login1", "/org/freedesktop/login1/session/auto")
	call := obj.Call("org.freedesktop.login1.Session.SetBrightness", 0, subsystem, name, brightness)
	if call.Err != nil {
		return fmt.Errorf("dbus call failed: %w", call.Err)
	}

	log.Debugf("logind: set %s/%s to %d", subsystem, name, brightness)
	return nil
}

func (b *LogindBackend) Close() {}
