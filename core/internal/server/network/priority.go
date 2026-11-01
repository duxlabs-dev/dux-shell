package network

import (
	"fmt"
	"os/exec"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	priorityHigh    = int32(100)
	priorityLow     = int32(10)
	priorityDefault = int32(0)

	metricPreferred    = int64(100)
	metricNonPreferred = int64(300)
	// -1 lets NetworkManager pick the metric by device type (nm-settings ipv4.route-metric)
	metricDefault = int64(-1)
)

func (m *Manager) SetConnectionPreference(pref ConnectionPreference) error {
	switch pref {
	case PreferenceWiFi, PreferenceEthernet, PreferenceCellular, PreferenceAuto:
	default:
		return fmt.Errorf("invalid preference: %s", pref)
	}

	m.priorityMutex.Lock()
	defer m.priorityMutex.Unlock()

	m.stateMutex.Lock()
	m.state.Preference = pref
	m.stateMutex.Unlock()

	if _, ok := m.backend.(*NetworkManagerBackend); !ok {
		m.notifySubscribers()
		return nil
	}

	switch pref {
	case PreferenceWiFi:
		return m.prioritizeWiFi()
	case PreferenceEthernet:
		return m.prioritizeEthernet()
	case PreferenceCellular:
		return m.prioritizeCellular()
	case PreferenceAuto:
		return m.restoreDefaultPriorities()
	}

	return nil
}

func (m *Manager) prioritizeWiFi() error {
	if err := m.setConnectionPriority("802-11-wireless", priorityHigh, metricPreferred); err != nil {
		log.Warnf("Failed to set WiFi priority: %v", err)
	}

	if err := m.setConnectionPriority("802-3-ethernet", priorityLow, metricNonPreferred); err != nil {
		log.Warnf("Failed to set Ethernet priority: %v", err)
	}

	for _, connType := range []string{"gsm", "cdma"} {
		if err := m.setConnectionPriority(connType, priorityLow, metricNonPreferred); err != nil {
			log.Warnf("Failed to set cellular priority for %s: %v", connType, err)
		}
	}

	m.reapplyActiveConnections()
	m.notifySubscribers()
	return nil
}

func (m *Manager) prioritizeEthernet() error {
	if err := m.setConnectionPriority("802-3-ethernet", priorityHigh, metricPreferred); err != nil {
		log.Warnf("Failed to set Ethernet priority: %v", err)
	}

	if err := m.setConnectionPriority("802-11-wireless", priorityLow, metricNonPreferred); err != nil {
		log.Warnf("Failed to set WiFi priority: %v", err)
	}

	for _, connType := range []string{"gsm", "cdma"} {
		if err := m.setConnectionPriority(connType, priorityLow, metricNonPreferred); err != nil {
			log.Warnf("Failed to set cellular priority for %s: %v", connType, err)
		}
	}

	m.reapplyActiveConnections()
	m.notifySubscribers()
	return nil
}

func (m *Manager) prioritizeCellular() error {
	for _, connType := range []string{"gsm", "cdma"} {
		if err := m.setConnectionPriority(connType, priorityHigh, metricPreferred); err != nil {
			log.Warnf("Failed to set cellular priority for %s: %v", connType, err)
		}
	}

	if err := m.setConnectionPriority("802-3-ethernet", priorityLow, metricNonPreferred); err != nil {
		log.Warnf("Failed to set Ethernet priority: %v", err)
	}

	if err := m.setConnectionPriority("802-11-wireless", priorityLow, metricNonPreferred); err != nil {
		log.Warnf("Failed to set WiFi priority: %v", err)
	}

	m.reapplyActiveConnections()
	m.notifySubscribers()
	return nil
}

func (m *Manager) restoreDefaultPriorities() error {
	if err := m.setConnectionPriority("802-3-ethernet", priorityDefault, metricDefault); err != nil {
		log.Warnf("Failed to reset Ethernet priority: %v", err)
	}

	if err := m.setConnectionPriority("802-11-wireless", priorityDefault, metricDefault); err != nil {
		log.Warnf("Failed to reset WiFi priority: %v", err)
	}

	for _, connType := range []string{"gsm", "cdma"} {
		if err := m.setConnectionPriority(connType, priorityDefault, metricDefault); err != nil {
			log.Warnf("Failed to reset cellular priority for %s: %v", connType, err)
		}
	}

	m.reapplyActiveConnections()
	m.notifySubscribers()
	return nil
}

func (m *Manager) reapplyActiveConnections() {
	m.stateMutex.RLock()
	ethDev := m.state.EthernetDevice
	wifiDev := m.state.WiFiDevice
	cellularDev := m.state.CellularDevice
	m.stateMutex.RUnlock()

	if ethDev != "" {
		exec.Command("nmcli", "dev", "reapply", ethDev).Run()
	}
	if wifiDev != "" {
		exec.Command("nmcli", "dev", "reapply", wifiDev).Run()
	}
	if cellularDev != "" {
		exec.Command("nmcli", "dev", "reapply", cellularDev).Run()
	}
}

func (m *Manager) setConnectionPriority(connType string, autoconnectPriority int32, routeMetric int64) error {
	conn, err := dbus.ConnectSystemBus()
	if err != nil {
		return fmt.Errorf("failed to connect to system bus: %w", err)
	}
	defer conn.Close()

	settingsObj := conn.Object("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager/Settings")

	var connPaths []dbus.ObjectPath
	if err := settingsObj.Call("org.freedesktop.NetworkManager.Settings.ListConnections", 0).Store(&connPaths); err != nil {
		return fmt.Errorf("failed to list connections: %w", err)
	}

	for _, connPath := range connPaths {
		connObj := conn.Object("org.freedesktop.NetworkManager", connPath)

		var settings map[string]map[string]dbus.Variant
		if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.GetSettings", 0).Store(&settings); err != nil {
			continue
		}

		connSection, ok := settings["connection"]
		if !ok {
			continue
		}

		typeVariant, ok := connSection["type"]
		if !ok {
			continue
		}

		cType, ok := typeVariant.Value().(string)
		if !ok || cType != connType {
			continue
		}

		// AP-mode profiles (hotspots) are not routing candidates; leave their
		// autoconnect priority and metrics alone.
		if cType == "802-11-wireless" {
			if wifiSection, ok := settings["802-11-wireless"]; ok {
				if modeVariant, ok := wifiSection["mode"]; ok {
					if mode, _ := modeVariant.Value().(string); mode == "ap" {
						continue
					}
				}
			}
		}

		connName := ""
		if idVariant, ok := connSection["id"]; ok {
			connName, _ = idVariant.Value().(string)
		}

		if connName == "" {
			continue
		}

		connUUID := ""
		if uuidVariant, ok := connSection["uuid"]; ok {
			connUUID, _ = uuidVariant.Value().(string)
		}

		if priorityMatches(connSection["autoconnect-priority"], int64(autoconnectPriority)) &&
			routeMetricMatches(settings["ipv4"], routeMetric) &&
			routeMetricMatches(settings["ipv6"], routeMetric) {
			continue
		}

		args := []string{"con", "mod"}
		if connUUID != "" {
			args = append(args, "uuid", connUUID)
		} else {
			args = append(args, connName)
		}
		args = append(args,
			"connection.autoconnect-priority", fmt.Sprintf("%d", autoconnectPriority),
			"ipv4.route-metric", fmt.Sprintf("%d", routeMetric),
			"ipv6.route-metric", fmt.Sprintf("%d", routeMetric))

		if err := exec.Command("nmcli", args...).Run(); err != nil {
			log.Warnf("Failed to set priority for %s: %v", connName, err)
			continue
		}

		log.Infof("Updated %v: autoconnect-priority=%d, route-metric=%d", connName, autoconnectPriority, routeMetric)
	}

	return nil
}

func priorityMatches(variant dbus.Variant, expected int64) bool {
	return settingInt64(variant, int64(priorityDefault)) == expected
}

func routeMetricMatches(section map[string]dbus.Variant, expected int64) bool {
	return settingInt64(section["route-metric"], metricDefault) == expected
}

// GetSettings omits properties at their default, so a missing key is the default value
func settingInt64(variant dbus.Variant, def int64) int64 {
	value, ok := variantInt64(variant)
	if !ok {
		return def
	}
	return value
}

func variantInt64(variant dbus.Variant) (int64, bool) {
	switch value := variant.Value().(type) {
	case int:
		return int64(value), true
	case int32:
		return int64(value), true
	case int64:
		return value, true
	case uint:
		return int64(value), true
	case uint32:
		return int64(value), true
	case uint64:
		if value > uint64(^uint64(0)>>1) {
			return 0, false
		}
		return int64(value), true
	default:
		return 0, false
	}
}

func (m *Manager) GetConnectionPreference() ConnectionPreference {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	return m.state.Preference
}

func (m *Manager) WasRecentlyFailed(ssid string) bool {
	nm, ok := m.backend.(*NetworkManagerBackend)
	if !ok {
		return false
	}

	nm.failedMutex.RLock()
	defer nm.failedMutex.RUnlock()

	if nm.lastFailedSSID != ssid {
		return false
	}

	elapsed := time.Now().Unix() - nm.lastFailedTime
	return elapsed < 10
}
