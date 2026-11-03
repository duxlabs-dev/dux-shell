package network

import (
	"sort"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

func (b *NetworkManagerBackend) updatePrimaryConnection() error {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)

	activeConns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return err
	}

	hasActiveVPN := false
	for _, activeConn := range activeConns {
		connType, err := activeConn.GetPropertyType()
		if err != nil {
			continue
		}
		if connType == "vpn" || connType == "wireguard" {
			state, _ := activeConn.GetPropertyState()
			if state == 2 {
				hasActiveVPN = true
				break
			}
		}
	}

	if hasActiveVPN {
		b.stateMutex.Lock()
		b.state.NetworkStatus = StatusVPN
		b.stateMutex.Unlock()
		return nil
	}

	primaryConn, err := nm.GetPropertyPrimaryConnection()
	if err != nil {
		return err
	}

	if primaryConn == nil || primaryConn.GetPath() == "/" {
		b.stateMutex.Lock()
		b.state.NetworkStatus = StatusDisconnected
		b.stateMutex.Unlock()
		return nil
	}

	connType, err := primaryConn.GetPropertyType()
	if err != nil {
		return err
	}

	b.stateMutex.Lock()
	switch connType {
	// Link aggregates carry the default route while the member NIC has no IP (#1581).
	case "802-3-ethernet", "bridge", "bond", "team", "vlan":
		b.state.NetworkStatus = StatusEthernet
	case "802-11-wireless":
		b.state.NetworkStatus = StatusWiFi
	case "gsm", "cdma":
		b.state.NetworkStatus = StatusCellular
	case "vpn", "wireguard":
		b.state.NetworkStatus = StatusVPN
	default:
		b.state.NetworkStatus = StatusDisconnected
	}
	b.stateMutex.Unlock()

	return nil
}

func (b *NetworkManagerBackend) updateEthernetState() error {
	var connectedDevice string
	var connectedIP string
	var anyConnected bool

	for name, info := range b.ethernetDevicesSnapshot() {
		state, err := info.device.GetPropertyState()
		if err != nil {
			continue
		}

		if state == gonetworkmanager.NmDeviceStateActivated {
			anyConnected = true
			connectedDevice = name
			connectedIP = b.getDeviceIP(info.device)
			break
		}
	}

	if !anyConnected && b.ethernetDevice != nil {
		dev := b.ethernetDevice.(gonetworkmanager.Device)
		iface, _ := dev.GetPropertyInterface()
		connectedDevice = iface
	}

	b.stateMutex.Lock()
	b.state.EthernetDevice = connectedDevice
	b.state.EthernetConnected = anyConnected
	b.state.EthernetIP = connectedIP
	b.stateMutex.Unlock()

	return nil
}

func (b *NetworkManagerBackend) updateCellularState() error {
	var connectedDevice string
	var connectedIP string
	var anyConnected bool

	for name, info := range b.cellularDevicesSnapshot() {
		state, err := info.device.GetPropertyState()
		if err != nil {
			continue
		}

		if state == gonetworkmanager.NmDeviceStateActivated {
			anyConnected = true
			connectedDevice = name
			connectedIP = b.getDeviceIP(info.device)
			break
		}
	}

	if !anyConnected && b.cellularDevice != nil {
		dev := b.cellularDevice.(gonetworkmanager.Device)
		iface, _ := dev.GetPropertyInterface()
		connectedDevice = iface
	}

	b.stateMutex.Lock()
	b.state.CellularDevice = connectedDevice
	b.state.CellularConnected = anyConnected
	b.state.CellularIP = connectedIP
	b.stateMutex.Unlock()

	return nil
}

func (b *NetworkManagerBackend) getDeviceStateReason(dev gonetworkmanager.Device) uint32 {
	path := dev.GetPath()
	obj := b.dbusConn.Object("org.freedesktop.NetworkManager", path)

	variant, err := obj.GetProperty(dbusNMDeviceInterface + ".StateReason")
	if err != nil {
		return 0
	}

	if stateReasonStruct, ok := variant.Value().([]any); ok && len(stateReasonStruct) >= 2 {
		if reason, ok := stateReasonStruct[1].(uint32); ok {
			return reason
		}
	}

	return 0
}

func (b *NetworkManagerBackend) classifyNMStateReason(reason uint32) string {
	switch reason {
	case NmDeviceStateReasonWrongPassword,
		NmDeviceStateReasonSupplicantTimeout,
		NmDeviceStateReasonSupplicantFailed,
		NmDeviceStateReasonSecretsRequired:
		return errdefs.ErrBadCredentials
	case NmDeviceStateReasonNoSecrets:
		return errdefs.ErrUserCanceled
	case NmDeviceStateReasonNoSsid:
		return errdefs.ErrNoSuchSSID
	case NmDeviceStateReasonDhcpClientFailed,
		NmDeviceStateReasonIpConfigUnavailable:
		return errdefs.ErrDhcpTimeout
	case NmDeviceStateReasonSupplicantDisconnect,
		NmDeviceStateReasonCarrier:
		return errdefs.ErrAssocTimeout
	default:
		return errdefs.ErrConnectionFailed
	}
}

// NM raises NO_SECRETS once auth retries run out on a saved profile too, not only
// on a dismissed prompt (nm-device-wifi.c handle_8021x_or_psk_auth_fail, #3313).
func forgetOnConnectFailure(reasonCode string, preExisting bool) bool {
	return reasonCode == errdefs.ErrUserCanceled && !preExisting
}

// With several adapters, state must follow the associated device, not whichever
// enumerated first (#2460).
func (b *NetworkManagerBackend) wifiDeviceForState() (gonetworkmanager.Device, gonetworkmanager.DeviceWireless) {
	fallbackDev, fallbackWireless := b.selectedWiFiDevice()

	snapshot := b.wifiDevicesSnapshot()
	if len(snapshot) < 2 {
		return fallbackDev, fallbackWireless
	}

	apMode := b.activeAPModeWiFiDevicePaths()
	names := make([]string, 0, len(snapshot))
	for name := range snapshot {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		info := snapshot[name]
		if info.device == nil {
			continue
		}
		state, err := info.device.GetPropertyState()
		if err != nil || state != gonetworkmanager.NmDeviceStateActivated {
			continue
		}
		if apMode[string(info.device.GetPath())] {
			continue
		}
		return info.device, info.wireless
	}
	return fallbackDev, fallbackWireless
}

func (b *NetworkManagerBackend) updateWiFiState() error {
	dev, wireless := b.wifiDeviceForState()
	if dev == nil {
		return nil
	}

	iface, err := dev.GetPropertyInterface()
	if err != nil {
		return err
	}

	state, err := dev.GetPropertyState()
	if err != nil {
		return err
	}

	connected := state == gonetworkmanager.NmDeviceStateActivated
	if connected {
		apModeDevicePaths := b.activeAPModeWiFiDevicePaths()
		if apModeDevicePaths[string(dev.GetPath())] {
			connected = false
		}
	}
	failed := state == gonetworkmanager.NmDeviceStateFailed
	disconnected := state == gonetworkmanager.NmDeviceStateDisconnected

	var ip, ssid, bssid string
	var signal uint8

	if connected {
		if wireless == nil {
			wireless, _ = b.ensureWiFiDevice()
		}
		if wireless != nil {
			activeAP, err := wireless.GetPropertyActiveAccessPoint()
			if err == nil && activeAP != nil && activeAP.GetPath() != "/" {
				ssid, _ = activeAP.GetPropertySSID()
				signal, _ = activeAP.GetPropertyStrength()
				bssid, _ = activeAP.GetPropertyHWAddress()
			}
		}

		ip = b.getDeviceIP(dev)
	}

	b.stateMutex.RLock()
	wasConnecting := b.state.IsConnecting
	connectingSSID := b.state.ConnectingSSID
	b.stateMutex.RUnlock()

	var reasonCode string
	if wasConnecting && connectingSSID != "" && (failed || (disconnected && !connected)) {
		reason := b.getDeviceStateReason(dev)

		if reason == NmDeviceStateReasonNewActivation || reason == 0 {
			return nil
		}

		log.Warnf("[updateWiFiState] Connection failed: SSID=%s, state=%d, reason=%d", connectingSSID, state, reason)

		reasonCode = b.classifyNMStateReason(reason)

		if reasonCode == errdefs.ErrConnectionFailed {
			b.failedMutex.RLock()
			if b.lastFailedSSID == connectingSSID {
				elapsed := time.Now().Unix() - b.lastFailedTime
				if elapsed < 5 {
					reasonCode = errdefs.ErrBadCredentials
				}
			}
			b.failedMutex.RUnlock()
		}
	}

	var forgetSSID string
	var doneSSID string

	b.stateMutex.Lock()

	wasConnecting = b.state.IsConnecting
	connectingSSID = b.state.ConnectingSSID

	if wasConnecting && connectingSSID != "" {
		switch {
		case connected && ssid == connectingSSID:
			log.Infof("[updateWiFiState] Connection successful: %s", ssid)
			b.state.IsConnecting = false
			b.state.ConnectingSSID = ""
			b.state.LastError = ""
			doneSSID = connectingSSID
		case failed || (disconnected && !connected):
			log.Warnf("[updateWiFiState] Connection failed: SSID=%s, state=%d", connectingSSID, state)
			b.state.IsConnecting = false
			b.state.ConnectingSSID = ""
			b.state.LastError = reasonCode

			if forgetOnConnectFailure(reasonCode, b.state.ConnectingPreExisting) {
				forgetSSID = connectingSSID
			}

			b.failedMutex.Lock()
			b.lastFailedSSID = connectingSSID
			b.lastFailedTime = time.Now().Unix()
			b.failedMutex.Unlock()

			doneSSID = connectingSSID
		}
	}

	b.state.WiFiDevice = iface
	b.state.WiFiConnected = connected
	b.state.WiFiIP = ip
	b.state.WiFiSSID = ssid
	b.state.WiFiBSSID = bssid
	b.state.WiFiSignal = signal

	b.stateMutex.Unlock()

	if doneSSID != "" {
		b.clearCachedWiFiSecretBySSID(doneSSID)
	}

	if forgetSSID != "" {
		log.Infof("[updateWiFiState] User cancelled authentication, removing connection profile for %s", forgetSSID)
		if err := b.ForgetWiFiNetwork(forgetSSID); err != nil {
			log.Warnf("[updateWiFiState] Failed to remove cancelled connection: %v", err)
		}
	}

	return nil
}

func (b *NetworkManagerBackend) getDeviceIP(dev gonetworkmanager.Device) string {
	ip4Config, err := dev.GetPropertyIP4Config()
	if err != nil || ip4Config == nil {
		return ""
	}

	addresses, err := ip4Config.GetPropertyAddressData()
	if err != nil || len(addresses) == 0 {
		return ""
	}

	return addresses[0].Address
}
