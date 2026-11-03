package network

import (
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	dbusNMSettingsPath                = "/org/freedesktop/NetworkManager/Settings"
	dbusNMSettingsInterface           = "org.freedesktop.NetworkManager.Settings"
	dbusNMSettingsConnectionInterface = "org.freedesktop.NetworkManager.Settings.Connection"

	wifiNetworksUpdateDelay = 500 * time.Millisecond
)

func (b *NetworkManagerBackend) startSignalPump() error {
	conn, err := dbus.SystemBus()
	if err != nil {
		return err
	}
	b.dbusConn = conn

	signals := make(chan *dbus.Signal, 256)
	b.signals = signals
	conn.Signal(signals)

	if err := conn.AddMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMPath)),
		dbus.WithMatchInterface(dbusPropsInterface),
		dbus.WithMatchMember("PropertiesChanged"),
	); err != nil {
		conn.RemoveSignal(signals)
		return err
	}

	if err := conn.AddMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMSettingsPath)),
		dbus.WithMatchInterface(dbusNMSettingsInterface),
		dbus.WithMatchMember("NewConnection"),
	); err != nil {
		conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMPath)),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
		conn.RemoveSignal(signals)
		return err
	}

	if err := conn.AddMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMSettingsPath)),
		dbus.WithMatchInterface(dbusNMSettingsInterface),
		dbus.WithMatchMember("ConnectionRemoved"),
	); err != nil {
		conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMPath)),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
		conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMSettingsPath)),
			dbus.WithMatchInterface(dbusNMSettingsInterface),
			dbus.WithMatchMember("NewConnection"),
		)
		conn.RemoveSignal(signals)
		return err
	}

	if err := conn.AddMatchSignal(
		dbus.WithMatchPathNamespace(dbus.ObjectPath(dbusNMSettingsPath)),
		dbus.WithMatchInterface(dbusNMSettingsConnectionInterface),
		dbus.WithMatchMember("Updated"),
	); err != nil {
		conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMPath)),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
		conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMSettingsPath)),
			dbus.WithMatchInterface(dbusNMSettingsInterface),
			dbus.WithMatchMember("NewConnection"),
		)
		conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMSettingsPath)),
			dbus.WithMatchInterface(dbusNMSettingsInterface),
			dbus.WithMatchMember("ConnectionRemoved"),
		)
		conn.RemoveSignal(signals)
		return err
	}

	if err := conn.AddMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMPath)),
		dbus.WithMatchInterface(dbusNMInterface),
		dbus.WithMatchMember("DeviceAdded"),
	); err != nil {
		conn.RemoveSignal(signals)
		return err
	}

	if err := conn.AddMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMPath)),
		dbus.WithMatchInterface(dbusNMInterface),
		dbus.WithMatchMember("DeviceRemoved"),
	); err != nil {
		conn.RemoveSignal(signals)
		return err
	}

	for _, info := range b.wifiDevicesSnapshot() {
		if err := conn.AddMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(info.device.GetPath())),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		); err != nil {
			conn.RemoveSignal(signals)
			return err
		}
	}

	for _, info := range b.ethernetDevicesSnapshot() {
		if err := conn.AddMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(info.device.GetPath())),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		); err != nil {
			conn.RemoveSignal(signals)
			return err
		}
	}

	// activating->activated/failed fires on the active-connection object, not the
	// manager's ActiveConnections property. VPN.Connection covers plugin VPNs;
	// Connection.Active covers the rest, including WireGuard.
	if err := conn.AddMatchSignal(
		dbus.WithMatchPathNamespace(dbus.ObjectPath(dbusNMActiveConnPath)),
		dbus.WithMatchInterface(dbusNMVPNConnInterface),
		dbus.WithMatchMember("VpnStateChanged"),
	); err != nil {
		conn.RemoveSignal(signals)
		return err
	}

	if err := conn.AddMatchSignal(
		dbus.WithMatchPathNamespace(dbus.ObjectPath(dbusNMActiveConnPath)),
		dbus.WithMatchInterface(dbusNMActiveConnInterface),
		dbus.WithMatchMember("StateChanged"),
	); err != nil {
		conn.RemoveSignal(signals)
		return err
	}

	for _, info := range b.cellularDevicesSnapshot() {
		if err := conn.AddMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(info.device.GetPath())),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		); err != nil {
			conn.RemoveSignal(signals)
			return err
		}
	}

	// ModemManager is optional: without it cellular still works, just without
	// radio metrics, so match failures are not fatal.
	if err := conn.AddMatchSignal(
		dbus.WithMatchPathNamespace(dbus.ObjectPath(dbusMMPath)),
		dbus.WithMatchInterface(dbusPropsInterface),
		dbus.WithMatchMember("PropertiesChanged"),
	); err != nil {
		log.Warnf("Failed to watch ModemManager properties: %v", err)
	}

	if err := conn.AddMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusMMPath)),
		dbus.WithMatchInterface(dbusObjectManagerInterface),
	); err != nil {
		log.Warnf("Failed to watch ModemManager objects: %v", err)
	}

	b.refreshModems()
	b.updateAllCellularDevices()

	b.sigWG.Go(func() {
		for {
			select {
			case <-b.stopChan:
				return
			case sig, ok := <-signals:
				if !ok {
					return
				}
				if sig == nil {
					continue
				}
				b.handleDBusSignal(sig)
			}
		}
	})
	return nil
}

func (b *NetworkManagerBackend) stopSignalPump() {
	if b.dbusConn == nil {
		return
	}

	b.dbusConn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMPath)),
		dbus.WithMatchInterface(dbusPropsInterface),
		dbus.WithMatchMember("PropertiesChanged"),
	)

	b.dbusConn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMSettingsPath)),
		dbus.WithMatchInterface(dbusNMSettingsInterface),
		dbus.WithMatchMember("NewConnection"),
	)
	b.dbusConn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMSettingsPath)),
		dbus.WithMatchInterface(dbusNMSettingsInterface),
		dbus.WithMatchMember("ConnectionRemoved"),
	)
	b.dbusConn.RemoveMatchSignal(
		dbus.WithMatchPathNamespace(dbus.ObjectPath(dbusNMSettingsPath)),
		dbus.WithMatchInterface(dbusNMSettingsConnectionInterface),
		dbus.WithMatchMember("Updated"),
	)
	b.dbusConn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMPath)),
		dbus.WithMatchInterface(dbusNMInterface),
		dbus.WithMatchMember("DeviceAdded"),
	)
	b.dbusConn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusNMPath)),
		dbus.WithMatchInterface(dbusNMInterface),
		dbus.WithMatchMember("DeviceRemoved"),
	)
	b.dbusConn.RemoveMatchSignal(
		dbus.WithMatchPathNamespace(dbus.ObjectPath(dbusNMActiveConnPath)),
		dbus.WithMatchInterface(dbusNMVPNConnInterface),
		dbus.WithMatchMember("VpnStateChanged"),
	)
	b.dbusConn.RemoveMatchSignal(
		dbus.WithMatchPathNamespace(dbus.ObjectPath(dbusNMActiveConnPath)),
		dbus.WithMatchInterface(dbusNMActiveConnInterface),
		dbus.WithMatchMember("StateChanged"),
	)

	for _, info := range b.wifiDevicesSnapshot() {
		b.dbusConn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(info.device.GetPath())),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
	}

	for _, info := range b.ethernetDevicesSnapshot() {
		b.dbusConn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(info.device.GetPath())),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
	}

	for _, info := range b.cellularDevicesSnapshot() {
		b.dbusConn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(info.device.GetPath())),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
	}

	b.dbusConn.RemoveMatchSignal(
		dbus.WithMatchPathNamespace(dbus.ObjectPath(dbusMMPath)),
		dbus.WithMatchInterface(dbusPropsInterface),
		dbus.WithMatchMember("PropertiesChanged"),
	)
	b.dbusConn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusMMPath)),
		dbus.WithMatchInterface(dbusObjectManagerInterface),
	)

	if b.signals != nil {
		b.dbusConn.RemoveSignal(b.signals)
		close(b.signals)
	}

	b.sigWG.Wait()
	b.cancelWiFiNetworksUpdate()
	b.wifiRefreshWG.Wait()
}

func (b *NetworkManagerBackend) handleDBusSignal(sig *dbus.Signal) {
	if sig.Name == dbusNMSettingsInterface+".NewConnection" ||
		sig.Name == dbusNMSettingsInterface+".ConnectionRemoved" ||
		sig.Name == dbusNMSettingsConnectionInterface+".Updated" {
		b.ListVPNProfiles()
		if err := b.updateSavedWiFiNetworks(); err != nil {
			b.updateWiFiNetworks()
		}
		b.updateHotspotState()
		b.listCellularConnections()
		// Device state does not change when an inactive wired profile is
		// added or deleted, so the profile list must be refreshed here too.
		b.listEthernetConnections()
		if b.onStateChange != nil {
			b.onStateChange()
		}
		return
	}

	if sig.Name == dbusNMVPNConnInterface+".VpnStateChanged" {
		if len(sig.Body) >= 2 {
			state, _ := sig.Body[0].(uint32)
			reason, _ := sig.Body[1].(uint32)
			b.handleVPNStateChange(state, reason)
		}
		return
	}

	if sig.Name == dbusNMActiveConnInterface+".StateChanged" {
		b.handleActiveConnectionStateChange()
		return
	}

	if sig.Name == "org.freedesktop.NetworkManager.DeviceAdded" {
		if len(sig.Body) >= 1 {
			if devicePath, ok := sig.Body[0].(dbus.ObjectPath); ok {
				b.handleDeviceAdded(devicePath)
			}
		}
		return
	}

	if sig.Name == "org.freedesktop.NetworkManager.DeviceRemoved" {
		if len(sig.Body) >= 1 {
			if devicePath, ok := sig.Body[0].(dbus.ObjectPath); ok {
				b.handleDeviceRemoved(devicePath)
			}
		}
		return
	}

	if sig.Name == dbusObjectManagerInterface+".InterfacesAdded" ||
		sig.Name == dbusObjectManagerInterface+".InterfacesRemoved" {
		// BlueZ and UDisks watch ObjectManager unscoped on the same shared bus,
		// so their signals land here too.
		if sig.Path == dbus.ObjectPath(dbusMMPath) {
			b.handleModemObjectsChange()
		}
		return
	}

	if len(sig.Body) < 2 {
		return
	}

	iface, ok := sig.Body[0].(string)
	if !ok {
		return
	}

	changes, ok := sig.Body[1].(map[string]dbus.Variant)
	if !ok {
		return
	}

	switch iface {
	case dbusNMInterface:
		b.handleNetworkManagerChange(changes)

	case dbusNMDeviceInterface:
		b.handleDeviceChange(sig.Path, changes)

	case dbusNMWiredInterface:
		b.handleWiredChange(changes)

	case dbusNMWirelessInterface:
		b.handleWiFiChange(changes)

	case dbusNMAccessPointInterface:
		b.handleAccessPointChange(changes)

	case dbusMMModemInterface:
		b.handleModemChange(sig.Path, changes)
	}
}

func (b *NetworkManagerBackend) handleNetworkManagerChange(changes map[string]dbus.Variant) {
	var needsUpdate bool

	for key := range changes {
		switch key {
		case "PrimaryConnection", "State", "ActiveConnections":
			needsUpdate = true
		case "WirelessEnabled":
			nm := b.nmConn.(gonetworkmanager.NetworkManager)
			if enabled, err := nm.GetPropertyWirelessEnabled(); err == nil {
				b.stateMutex.Lock()
				b.state.WiFiEnabled = enabled
				b.stateMutex.Unlock()
				needsUpdate = true
			}
		case "WwanEnabled", "WwanHardwareEnabled":
			b.updateCellularRadioState()
			b.updateAllCellularDevices()
			b.updateCellularState()
			needsUpdate = true
		default:
			continue
		}
	}

	if needsUpdate {
		b.updatePrimaryConnection()
		if _, exists := changes["State"]; exists {
			b.updateEthernetState()
			b.updateWiFiState()
			b.updateCellularState()
		}
		if _, exists := changes["ActiveConnections"]; exists {
			b.updateVPNConnectionState()
			b.ListActiveVPN()
			b.updateHotspotState()
		}
		if b.onStateChange != nil {
			b.onStateChange()
		}
	}
}

func (b *NetworkManagerBackend) handleActiveConnectionStateChange() {
	b.updateVPNConnectionState()
	b.ListActiveVPN()
	b.updateHotspotState()
	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *NetworkManagerBackend) handleVPNStateChange(state, reason uint32) {
	if state == nmVPNStateFailed {
		b.stateMutex.Lock()
		if uuid := b.state.ConnectingVPNUUID; uuid != "" {
			b.state.VPNError = vpnFailureMessage(reason)
			b.state.VPNErrorUuid = uuid
		}
		b.stateMutex.Unlock()
	}

	b.handleActiveConnectionStateChange()
}

func (b *NetworkManagerBackend) handleDeviceChange(devicePath dbus.ObjectPath, changes map[string]dbus.Variant) {
	var needsUpdate bool
	var stateChanged bool
	var managedChanged bool

	for key := range changes {
		switch key {
		case "State":
			stateChanged = true
			needsUpdate = true
		case "Ip4Config":
			needsUpdate = true
		case "Managed":
			managedChanged = true
		default:
			continue
		}
	}

	if managedChanged {
		if managedVariant, ok := changes["Managed"]; ok {
			if managed, ok := managedVariant.Value().(bool); ok {
				if managed {
					b.handleDeviceAdded(devicePath)
					return
				}
				// Newly unmanaged devices stay tracked (matching Initialize),
				// but capability-dependent state such as hotspotAvailable
				// must be recomputed and broadcast.
				needsUpdate = true
			}
		}
	}

	if !needsUpdate {
		return
	}

	b.updateAllEthernetDevices()
	b.updateEthernetState()
	b.updateAllCellularDevices()
	b.updateCellularState()
	b.updateAllWiFiDevices()
	b.updateWiFiState()
	b.updateHotspotState()
	if stateChanged {
		b.listEthernetConnections()
		b.listCellularConnections()
		b.updatePrimaryConnection()
	}
	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *NetworkManagerBackend) handleWiredChange(changes map[string]dbus.Variant) {
	var needsUpdate bool

	for key := range changes {
		switch key {
		case "Carrier", "Speed", "HwAddress":
			needsUpdate = true
		default:
			continue
		}
	}

	if !needsUpdate {
		return
	}

	b.updateAllEthernetDevices()
	b.updateEthernetState()
	b.updatePrimaryConnection()
	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *NetworkManagerBackend) handleWiFiChange(changes map[string]dbus.Variant) {
	var needsStateUpdate bool
	var needsNetworkUpdate bool

	for key := range changes {
		switch key {
		case "ActiveAccessPoint":
			needsStateUpdate = true
			needsNetworkUpdate = true
		case "AccessPoints":
			b.scheduleWiFiNetworksUpdate()
		default:
			continue
		}
	}

	if needsStateUpdate {
		b.updateWiFiState()
	}
	if needsNetworkUpdate {
		b.cancelWiFiNetworksUpdate()
		b.updateWiFiNetworks()
	}
	if needsStateUpdate || needsNetworkUpdate {
		if b.onStateChange != nil {
			b.onStateChange()
		}
	}
}

// A scan announces each new access point on its own, so rebuild the list
// once per burst instead of once per access point.
func (b *NetworkManagerBackend) scheduleWiFiNetworksUpdate() {
	b.wifiRefreshMu.Lock()
	defer b.wifiRefreshMu.Unlock()

	if b.wifiRefreshTimer != nil {
		return
	}
	b.wifiRefreshWG.Add(1)
	b.wifiRefreshTimer = time.AfterFunc(wifiNetworksUpdateDelay, func() {
		defer b.wifiRefreshWG.Done()

		b.wifiRefreshMu.Lock()
		b.wifiRefreshTimer = nil
		b.wifiRefreshMu.Unlock()

		b.updateWiFiNetworks()
		if b.onStateChange != nil {
			b.onStateChange()
		}
	})
}

func (b *NetworkManagerBackend) cancelWiFiNetworksUpdate() {
	b.wifiRefreshMu.Lock()
	defer b.wifiRefreshMu.Unlock()

	if b.wifiRefreshTimer == nil || !b.wifiRefreshTimer.Stop() {
		return
	}
	b.wifiRefreshTimer = nil
	b.wifiRefreshWG.Done()
}

func (b *NetworkManagerBackend) handleAccessPointChange(changes map[string]dbus.Variant) {
	_, hasStrength := changes["Strength"]
	if !hasStrength {
		return
	}

	b.stateMutex.RLock()
	oldSignal := b.state.WiFiSignal
	b.stateMutex.RUnlock()

	b.updateWiFiState()

	b.stateMutex.RLock()
	newSignal := b.state.WiFiSignal
	b.stateMutex.RUnlock()

	if signalChangeSignificant(oldSignal, newSignal) {
		if b.onStateChange != nil {
			b.onStateChange()
		}
	}
}

func (b *NetworkManagerBackend) handleDeviceAdded(devicePath dbus.ObjectPath) {
	dev, err := gonetworkmanager.NewDevice(devicePath)
	if err != nil {
		return
	}

	devType, err := dev.GetPropertyDeviceType()
	if err != nil {
		return
	}

	if devType != gonetworkmanager.NmDeviceTypeEthernet && devType != gonetworkmanager.NmDeviceTypeWifi && devType != gonetworkmanager.NmDeviceTypeModem {
		return
	}

	if b.dbusConn != nil && devType != gonetworkmanager.NmDeviceTypeWifi {
		b.dbusConn.AddMatchSignal(
			dbus.WithMatchObjectPath(devicePath),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
	}

	managed, _ := dev.GetPropertyManaged()
	if !managed && devType != gonetworkmanager.NmDeviceTypeWifi {
		return
	}

	iface, err := dev.GetPropertyInterface()
	if err != nil {
		return
	}

	switch devType {
	case gonetworkmanager.NmDeviceTypeEthernet:
		w, err := gonetworkmanager.NewDeviceWired(devicePath)
		if err != nil {
			return
		}
		hwAddr, _ := w.GetPropertyHwAddress()

		b.setEthernetDeviceInfo(iface, &ethernetDeviceInfo{
			device:    dev,
			wired:     w,
			name:      iface,
			hwAddress: hwAddr,
		})

		if b.ethernetDevice == nil {
			b.ethernetDevice = dev
		}

		b.updateAllEthernetDevices()
		b.updateEthernetState()
		b.listEthernetConnections()
		b.updatePrimaryConnection()

	case gonetworkmanager.NmDeviceTypeModem:
		hwAddr := ""
		description := "Mobile broadband"
		if g, err := gonetworkmanager.NewDeviceGeneric(devicePath); err == nil {
			hwAddr, _ = g.GetPropertyHwAddress()
			if desc, err := g.GetPropertyTypeDescription(); err == nil && desc != "" {
				description = desc
			}
		}

		b.setCellularDeviceInfo(iface, &cellularDeviceInfo{
			device:      dev,
			name:        iface,
			hwAddress:   hwAddr,
			description: description,
		})

		if b.cellularDevice == nil {
			b.cellularDevice = dev
		}

		b.updateAllCellularDevices()
		b.updateCellularState()
		b.listCellularConnections()
		b.updatePrimaryConnection()

	case gonetworkmanager.NmDeviceTypeWifi:
		w, err := gonetworkmanager.NewDeviceWireless(devicePath)
		if err != nil {
			return
		}
		hwAddr, _ := w.GetPropertyHwAddress()

		b.setWifiDeviceInfo(iface, &wifiDeviceInfo{
			device:    dev,
			wireless:  w,
			name:      iface,
			hwAddress: hwAddr,
		})

		b.updateAllWiFiDevices()
		b.updateWiFiState()
		b.updateHotspotState()
	}

	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *NetworkManagerBackend) handleDeviceRemoved(devicePath dbus.ObjectPath) {
	if _, _, found := b.removeWifiDeviceByPath(devicePath); found {
		b.updateAllWiFiDevices()
		b.updateWiFiState()
		b.updateHotspotState()

		if b.onStateChange != nil {
			b.onStateChange()
		}
		return
	}

	if b.dbusConn != nil {
		b.dbusConn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(devicePath),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
	}

	if _, remaining, found := b.removeEthernetDeviceByPath(devicePath); found {
		if b.ethernetDevice != nil {
			dev := b.ethernetDevice.(gonetworkmanager.Device)
			if dev.GetPath() == devicePath {
				b.ethernetDevice = nil
				for _, r := range remaining {
					b.ethernetDevice = r.device
					break
				}
			}
		}

		b.updateAllEthernetDevices()
		b.updateEthernetState()
		b.listEthernetConnections()
		b.updatePrimaryConnection()

		if b.onStateChange != nil {
			b.onStateChange()
		}
		return
	}

	if _, remaining, found := b.removeCellularDeviceByPath(devicePath); found {
		if b.cellularDevice != nil {
			dev := b.cellularDevice.(gonetworkmanager.Device)
			if dev.GetPath() == devicePath {
				b.cellularDevice = nil
				for _, r := range remaining {
					b.cellularDevice = r.device
					break
				}
			}
		}

		b.refreshCellularState()
		return
	}
}
