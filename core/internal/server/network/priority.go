package network

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	metricPreferred    = int64(100)
	metricNonPreferred = int64(300)
	// -1 lets NetworkManager pick the metric by device type (nm-settings ipv4.route-metric)
	metricDefault = int64(-1)

	priorityHigh    = int32(100)
	priorityLow     = int32(10)
	priorityDefault = int32(0)
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

	nm, ok := m.backend.(*NetworkManagerBackend)
	if !ok {
		m.notifySubscribers()
		return nil
	}

	changed, err := applyConnectionPreference(nm, pref)
	if changed {
		m.reapplyActiveConnections()
	}
	m.notifySubscribers()
	return err
}

func preferredConnType(pref ConnectionPreference, connType string) bool {
	switch pref {
	case PreferenceWiFi:
		return connType == "802-11-wireless"
	case PreferenceEthernet:
		return connType == "802-3-ethernet"
	case PreferenceCellular:
		return connType == "gsm" || connType == "cdma"
	}
	return false
}

// preferenceUpdate decides the new route metric and autoconnect priority for
// one profile and IP family. Absent keys count as NM defaults (metric -1,
// priority 0). Only values DMS writes (metric -1/100/300, priority 100/10)
// are ever replaced; anything else belongs to the user.
func preferenceUpdate(connType string, pref ConnectionPreference, metric int64, priority int32) (newMetric int64, metricChange bool, newPriority int32, priorityChange bool) {
	if pref == PreferenceAuto {
		if metric == metricPreferred || metric == metricNonPreferred {
			newMetric, metricChange = metricDefault, true
		}
		if priority == priorityHigh || priority == priorityLow {
			newPriority, priorityChange = priorityDefault, true
		}
		return
	}

	if metric != metricDefault && metric != metricPreferred && metric != metricNonPreferred {
		return
	}
	newMetric = metricNonPreferred
	if preferredConnType(pref, connType) {
		newMetric = metricPreferred
	}
	metricChange = newMetric != metric
	return
}

func (m *Manager) reapplyActiveConnections() {
	m.stateMutex.RLock()
	var devs []string
	for _, d := range m.state.EthernetDevices {
		if d.Connected {
			devs = append(devs, d.Name)
		}
	}
	for _, d := range m.state.WiFiDevices {
		if d.Connected {
			devs = append(devs, d.Name)
		}
	}
	for _, d := range m.state.CellularDevices {
		if d.Connected {
			devs = append(devs, d.Name)
		}
	}
	m.stateMutex.RUnlock()

	for _, dev := range devs {
		if err := reapplyDevice(dev); err != nil {
			log.Warnf("Failed to reapply %s: %v", dev, err)
		}
	}
}

var reapplyDevice = func(dev string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nmcli", "dev", "reapply", dev)
	cmd.WaitDelay = time.Second
	return cmd.Run()
}

// applyConnectionPreference reports whether any profile was rewritten.
func applyConnectionPreference(b *NetworkManagerBackend, pref ConnectionPreference) (bool, error) {
	settingsObj := b.nmObject(nmSettingsPath)
	if settingsObj == nil {
		return false, fmt.Errorf("D-Bus connection unavailable")
	}

	var connPaths []dbus.ObjectPath
	if err := settingsObj.Call("org.freedesktop.NetworkManager.Settings.ListConnections", 0).Store(&connPaths); err != nil {
		return false, fmt.Errorf("failed to list connections: %w", err)
	}

	var errs []error
	anyChanged := false
	for _, connPath := range connPaths {
		changed, err := applyPreferenceToProfile(b.nmObject(connPath), pref)
		if err != nil {
			errs = append(errs, err)
		}
		anyChanged = anyChanged || changed
	}
	return anyChanged, errors.Join(errs...)
}

func applyPreferenceToProfile(connObj dbus.BusObject, pref ConnectionPreference) (bool, error) {
	var settings nmSettings
	if err := connObj.Call(nmConnGetSettings, 0).Store(&settings); err != nil {
		return false, nil
	}

	connSection := settings["connection"]
	cType, _ := connSection["type"].Value().(string)
	switch cType {
	case "802-3-ethernet", "802-11-wireless", "gsm", "cdma":
	default:
		return false, nil
	}

	// AP-mode profiles (hotspots) are not routing candidates.
	if mode, _ := settings["802-11-wireless"]["mode"].Value().(string); cType == "802-11-wireless" && mode == "ap" {
		return false, nil
	}

	name, _ := connSection["id"].Value().(string)
	if name == "" {
		return false, nil
	}

	prio := int32(0)
	if v, ok := variantInt64(connSection["autoconnect-priority"]); ok {
		prio = int32(v)
	}

	metrics := map[string]int64{}
	prioChange, newPrio := false, int32(0)
	for _, fam := range []string{"ipv4", "ipv6"} {
		section, ok := settings[fam]
		if !ok {
			continue
		}
		cur := metricDefault
		if v, ok := variantInt64(section["route-metric"]); ok {
			cur = v
		}
		nm, mc, np, pc := preferenceUpdate(cType, pref, cur, prio)
		if mc {
			metrics[fam] = nm
		}
		if pc {
			prioChange, newPrio = true, np
		}
	}
	if len(metrics) == 0 && !prioChange {
		return false, nil
	}

	err := updateConnectionSettings(connObj, true, func(s nmSettings) error {
		for fam, nm := range metrics {
			setSettingValue(s, fam, "route-metric", nm)
		}
		if prioChange {
			setSettingValue(s, "connection", "autoconnect-priority", newPrio)
		}
		return nil
	})
	if err != nil {
		return false, fmt.Errorf("%s: %w", name, err)
	}
	log.Infof("Updated %v: route-metric=%v", name, metrics)
	return true, nil
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
