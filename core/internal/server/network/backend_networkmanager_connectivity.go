package network

import (
	"fmt"

	"github.com/godbus/dbus/v5"
)

var connectivityProps = []string{"Connectivity", "ConnectivityCheckEnabled", "ConnectivityCheckAvailable", "ConnectivityCheckUri"}

func connectivityName(v uint32) string {
	switch v {
	case 1:
		return "none"
	case 2:
		return "portal"
	case 3:
		return "limited"
	case 4:
		return "full"
	}
	return "unknown"
}

// applyConnectivityProperty stores one NM connectivity property and reports
// whether the key was one of them.
func (b *NetworkManagerBackend) applyConnectivityProperty(key string, v dbus.Variant) bool {
	b.stateMutex.Lock()
	defer b.stateMutex.Unlock()
	switch key {
	case "Connectivity":
		n, _ := v.Value().(uint32)
		b.state.Connectivity = connectivityName(n)
	case "ConnectivityCheckEnabled":
		b.state.ConnectivityCheckEnabled, _ = v.Value().(bool)
	case "ConnectivityCheckAvailable":
		b.state.ConnectivityCheckAvailable, _ = v.Value().(bool)
	case "ConnectivityCheckUri":
		b.state.ConnectivityCheckURI, _ = v.Value().(string)
	default:
		return false
	}
	return true
}

func (b *NetworkManagerBackend) updateConnectivityState() {
	obj := b.nmObject(dbusNMPath)
	if obj == nil {
		return
	}
	for _, key := range connectivityProps {
		if v, err := obj.GetProperty(dbusNMInterface + "." + key); err == nil {
			b.applyConnectivityProperty(key, v)
		}
	}
}

func (b *NetworkManagerBackend) CheckConnectivity() (string, error) {
	obj := b.nmObject(dbusNMPath)
	if obj == nil {
		return "", fmt.Errorf("D-Bus connection unavailable")
	}
	var v uint32
	if err := obj.Call(dbusNMInterface+".CheckConnectivity", 0).Store(&v); err != nil {
		return "", fmt.Errorf("check connectivity: %w", err)
	}
	name := connectivityName(v)
	b.applyConnectivityProperty("Connectivity", dbus.MakeVariant(v))
	return name, nil
}

func (b *NetworkManagerBackend) SetConnectivityCheckEnabled(enabled bool) error {
	obj := b.nmObject(dbusNMPath)
	if obj == nil {
		return fmt.Errorf("D-Bus connection unavailable")
	}
	call := obj.Call(dbusPropsInterface+".Set", dbus.FlagAllowInteractiveAuthorization,
		dbusNMInterface, "ConnectivityCheckEnabled", dbus.MakeVariant(enabled))
	if call.Err != nil {
		return fmt.Errorf("set connectivity check: %w", call.Err)
	}
	return nil
}
