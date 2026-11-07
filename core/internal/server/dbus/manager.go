package dbus

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"strings"

	"github.com/duxlabs-dev/dux-go/dbusutil"
	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

func NewManager() (*Manager, error) {
	systemConn, err := dbus.SystemBus()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to system bus: %w", err)
	}

	sessionConn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to session bus: %w", err)
	}

	m := &Manager{
		systemConn:     systemConn,
		sessionConn:    sessionConn,
		systemSignals:  make(chan *dbus.Signal, 256),
		sessionSignals: make(chan *dbus.Signal, 256),
	}

	go m.processSystemSignals()
	go m.processSessionSignals()

	return m, nil
}

func (m *Manager) getConn(bus string) (*dbus.Conn, error) {
	switch bus {
	case "system":
		if m.systemConn == nil {
			return nil, fmt.Errorf("system bus not connected")
		}
		return m.systemConn, nil
	case "session":
		if m.sessionConn == nil {
			return nil, fmt.Errorf("session bus not connected")
		}
		return m.sessionConn, nil
	default:
		return nil, fmt.Errorf("invalid bus: %s (must be 'system' or 'session')", bus)
	}
}

func (m *Manager) Call(bus, dest, path, iface, method string, args []any) (*CallResult, error) {
	conn, err := m.getConn(bus)
	if err != nil {
		return nil, err
	}

	obj := conn.Object(dest, dbus.ObjectPath(path))
	fullMethod := iface + "." + method

	convertedArgs := convertArgs(args)
	call := obj.Call(fullMethod, 0, convertedArgs...)
	if call.Err != nil {
		return nil, fmt.Errorf("dbus call failed: %w", call.Err)
	}

	return &CallResult{Values: dbusutil.NormalizeSlice(call.Body)}, nil
}

func convertArgs(args []any) []any {
	result := make([]any, len(args))
	for i, arg := range args {
		result[i] = convertArg(arg)
	}
	return result
}

func convertArg(arg any) any {
	switch v := arg.(type) {
	case float64:
		if v == float64(uint32(v)) && v >= 0 && v <= float64(^uint32(0)) {
			return uint32(v)
		}
		if v == float64(int32(v)) {
			return int32(v)
		}
		return v
	case []any:
		return convertArgs(v)
	case map[string]any:
		result := make(map[string]any)
		for k, val := range v {
			result[k] = convertArg(val)
		}
		return result
	default:
		return arg
	}
}

func (m *Manager) GetProperty(bus, dest, path, iface, property string) (*PropertyResult, error) {
	conn, err := m.getConn(bus)
	if err != nil {
		return nil, err
	}

	obj := conn.Object(dest, dbus.ObjectPath(path))

	var variant dbus.Variant
	err = obj.Call("org.freedesktop.DBus.Properties.Get", 0, iface, property).Store(&variant)
	if err != nil {
		return nil, fmt.Errorf("failed to get property: %w", err)
	}

	return &PropertyResult{Value: dbusutil.Normalize(variant.Value())}, nil
}

func (m *Manager) SetProperty(bus, dest, path, iface, property string, value any) error {
	conn, err := m.getConn(bus)
	if err != nil {
		return err
	}

	obj := conn.Object(dest, dbus.ObjectPath(path))

	call := obj.Call("org.freedesktop.DBus.Properties.Set", 0, iface, property, dbus.MakeVariant(value))
	if call.Err != nil {
		return fmt.Errorf("failed to set property: %w", call.Err)
	}

	return nil
}

func (m *Manager) GetAllProperties(bus, dest, path, iface string) (map[string]any, error) {
	conn, err := m.getConn(bus)
	if err != nil {
		return nil, err
	}

	obj := conn.Object(dest, dbus.ObjectPath(path))

	var props map[string]dbus.Variant
	err = obj.Call("org.freedesktop.DBus.Properties.GetAll", 0, iface).Store(&props)
	if err != nil {
		return nil, fmt.Errorf("failed to get properties: %w", err)
	}

	result := make(map[string]any)
	for k, v := range props {
		result[k] = dbusutil.Normalize(v.Value())
	}

	return result, nil
}

func (m *Manager) Introspect(bus, dest, path string) (*IntrospectResult, error) {
	conn, err := m.getConn(bus)
	if err != nil {
		return nil, err
	}

	obj := conn.Object(dest, dbus.ObjectPath(path))

	var xml string
	err = obj.Call("org.freedesktop.DBus.Introspectable.Introspect", 0).Store(&xml)
	if err != nil {
		return nil, fmt.Errorf("failed to introspect: %w", err)
	}

	return &IntrospectResult{XML: xml}, nil
}

func (m *Manager) ListNames(bus string) (*ListNamesResult, error) {
	conn, err := m.getConn(bus)
	if err != nil {
		return nil, err
	}

	var names []string
	err = conn.BusObject().Call("org.freedesktop.DBus.ListNames", 0).Store(&names)
	if err != nil {
		return nil, fmt.Errorf("failed to list names: %w", err)
	}

	return &ListNamesResult{Names: names}, nil
}

func (m *Manager) Subscribe(owner *ipc.ConnWriter, clientID, bus, sender, path, iface, member string) (*SubscribeResult, error) {
	conn, err := m.getConn(bus)
	if err != nil {
		return nil, err
	}

	subID := generateSubscriptionID()

	parts := []string{"type='signal'"}
	if sender != "" {
		parts = append(parts, fmt.Sprintf("sender='%s'", sender))
	}
	if path != "" {
		parts = append(parts, fmt.Sprintf("path='%s'", path))
	}
	if iface != "" {
		parts = append(parts, fmt.Sprintf("interface='%s'", iface))
	}
	if member != "" {
		parts = append(parts, fmt.Sprintf("member='%s'", member))
	}
	matchRule := strings.Join(parts, ",")

	call := conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0, matchRule)
	if call.Err != nil {
		return nil, fmt.Errorf("failed to add match rule: %w", call.Err)
	}

	sub := &signalSubscription{
		Bus:       bus,
		Sender:    sender,
		Path:      path,
		Interface: iface,
		Member:    member,
		ClientID:  clientID,
		Owner:     owner,
	}
	m.subscriptions.Store(subID, sub)

	log.Debugf("dbus: subscribed %s to %s", subID, matchRule)

	return &SubscribeResult{SubscriptionID: subID}, nil
}

func (m *Manager) Unsubscribe(subID string) error {
	sub, ok := m.subscriptions.LoadAndDelete(subID)
	if !ok {
		return fmt.Errorf("subscription not found: %s", subID)
	}

	conn, err := m.getConn(sub.Bus)
	if err != nil {
		return err
	}

	parts := []string{"type='signal'"}
	if sub.Sender != "" {
		parts = append(parts, fmt.Sprintf("sender='%s'", sub.Sender))
	}
	if sub.Path != "" {
		parts = append(parts, fmt.Sprintf("path='%s'", sub.Path))
	}
	if sub.Interface != "" {
		parts = append(parts, fmt.Sprintf("interface='%s'", sub.Interface))
	}
	if sub.Member != "" {
		parts = append(parts, fmt.Sprintf("member='%s'", sub.Member))
	}
	matchRule := strings.Join(parts, ",")

	call := conn.BusObject().Call("org.freedesktop.DBus.RemoveMatch", 0, matchRule)
	if call.Err != nil {
		log.Warnf("dbus: failed to remove match rule: %v", call.Err)
	}

	log.Debugf("dbus: unsubscribed %s", subID)

	return nil
}

// Match rules live as long as the request connection that added them, not the
// subscribe socket, which the shell re-dials whenever its service list changes.
func (m *Manager) ReleaseOnClose(ctx context.Context, owner *ipc.ConnWriter) {
	if _, loaded := m.owners.LoadOrStore(owner, struct{}{}); loaded {
		return
	}
	go func() {
		<-ctx.Done()
		m.owners.Delete(owner)
		m.unsubscribeOwner(owner)
	}()
}

func (m *Manager) unsubscribeOwner(owner *ipc.ConnWriter) {
	var toDelete []string
	m.subscriptions.Range(func(subID string, sub *signalSubscription) bool {
		if sub.Owner == owner {
			toDelete = append(toDelete, subID)
		}
		return true
	})

	for _, subID := range toDelete {
		_ = m.Unsubscribe(subID)
	}
}

// A re-dialed subscribe socket can register before the old one tears down, so
// the old release must only drop the channel it created. Channels are never
// closed here because dispatchSignal may be mid-send on another goroutine.
func (m *Manager) SubscribeSignals(clientID string) chan SignalEvent {
	ch := make(chan SignalEvent, 64)
	m.subscribersMu.Lock()
	m.signalSubscribers.Store(clientID, ch)
	m.subscribersMu.Unlock()
	return ch
}

func (m *Manager) UnsubscribeSignals(clientID string, ch chan SignalEvent) {
	m.subscribersMu.Lock()
	defer m.subscribersMu.Unlock()
	if current, ok := m.signalSubscribers.Load(clientID); ok && current == ch {
		m.signalSubscribers.Delete(clientID)
	}
}

func (m *Manager) processSystemSignals() {
	if m.systemConn == nil {
		return
	}
	m.systemConn.Signal(m.systemSignals)

	for sig := range m.systemSignals {
		m.dispatchSignal("system", sig)
	}
}

func (m *Manager) processSessionSignals() {
	if m.sessionConn == nil {
		return
	}
	m.sessionConn.Signal(m.sessionSignals)

	for sig := range m.sessionSignals {
		m.dispatchSignal("session", sig)
	}
}

func (m *Manager) dispatchSignal(bus string, sig *dbus.Signal) {
	path := string(sig.Path)
	iface := ""
	member := sig.Name

	if idx := strings.LastIndex(sig.Name, "."); idx != -1 {
		iface = sig.Name[:idx]
		member = sig.Name[idx+1:]
	}

	m.subscriptions.Range(func(subID string, sub *signalSubscription) bool {
		if sub.Bus != bus {
			return true
		}
		if sub.Path != "" && sub.Path != path && !strings.HasPrefix(path, sub.Path) {
			return true
		}
		if sub.Interface != "" && sub.Interface != iface {
			return true
		}
		if sub.Member != "" && sub.Member != member {
			return true
		}

		event := SignalEvent{
			SubscriptionID: subID,
			Sender:         sig.Sender,
			Path:           path,
			Interface:      iface,
			Member:         member,
			Body:           dbusutil.NormalizeSlice(sig.Body),
		}

		ch, ok := m.signalSubscribers.Load(sub.ClientID)
		if !ok {
			return true
		}

		select {
		case ch <- event:
		default:
			log.Warnf("dbus: channel full for %s, dropping signal", subID)
		}

		return true
	})
}

func (m *Manager) Close() {
	m.signalSubscribers.Range(func(clientID string, ch chan SignalEvent) bool {
		close(ch)
		m.signalSubscribers.Delete(clientID)
		return true
	})

	if m.systemConn != nil {
		m.systemConn.RemoveSignal(m.systemSignals)
		close(m.systemSignals)
	}
	if m.sessionConn != nil {
		m.sessionConn.RemoveSignal(m.sessionSignals)
		close(m.sessionSignals)
	}
}

func generateSubscriptionID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		log.Warnf("dbus: failed to generate random subscription ID: %v", err)
	}
	return hex.EncodeToString(b)
}
