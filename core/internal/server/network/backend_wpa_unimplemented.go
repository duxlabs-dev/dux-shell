package network

import "fmt"

func (b *WpaSupplicantBackend) GetCellularDevices() []CellularDevice {
	return []CellularDevice{}
}

func (b *WpaSupplicantBackend) GetCellularEnabled() (bool, error) {
	return false, fmt.Errorf("cellular radio control not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) SetCellularEnabled(enabled bool) error {
	return fmt.Errorf("cellular radio control not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) GetCellularConnections() ([]WiredConnection, error) {
	return nil, fmt.Errorf("cellular connections not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) ConnectCellular() error {
	return fmt.Errorf("cellular connections not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) DisconnectCellular() error {
	return fmt.Errorf("cellular connections not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) DisconnectCellularDevice(device string) error {
	return fmt.Errorf("cellular connections not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) ActivateCellularConnection(uuid string) error {
	return fmt.Errorf("cellular connections not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) ListVPNProfiles() ([]VPNProfile, error) {
	return nil, fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) ListActiveVPN() ([]VPNActive, error) {
	return nil, fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) ConnectVPN(uuidOrName string, singleActive bool) error {
	return fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) DisconnectVPN(uuidOrName string) error {
	return fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) DisconnectAllVPN() error {
	return fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) ClearVPNCredentials(uuidOrName string) error {
	return fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) ListVPNPlugins() ([]VPNPlugin, error) {
	return nil, fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) ImportVPN(filePath string, name string) (*VPNImportResult, error) {
	return nil, fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) GetVPNConfig(uuidOrName string) (*VPNConfig, error) {
	return nil, fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) UpdateVPNConfig(uuid string, updates map[string]any) error {
	return fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) DeleteVPN(uuidOrName string) error {
	return fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) SetVPNCredentials(uuid, username, password string, save bool) error {
	return fmt.Errorf("VPN not supported by wpa_supplicant backend")
}

func (b *WpaSupplicantBackend) ScanWiFiDevice(device string) error {
	return b.ScanWiFi()
}

func (b *WpaSupplicantBackend) DisconnectWiFiDevice(device string) error {
	return b.DisconnectWiFi()
}

func (b *WpaSupplicantBackend) GetWiFiDevices() []WiFiDevice {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()
	return b.getWiFiDevicesLocked()
}

func (b *WpaSupplicantBackend) getWiFiDevicesLocked() []WiFiDevice {
	if b.state.WiFiDevice == "" {
		return nil
	}

	stateStr := "disconnected"

	if b.ifname == "" && b.physicalWiFi != "" {
		stateStr = "unconfigured"
	} else if b.state.WiFiConnected {
		stateStr = "connected"
	}

	return []WiFiDevice{{
		Name:      b.state.WiFiDevice,
		State:     stateStr,
		Connected: b.state.WiFiConnected,
		SSID:      b.state.WiFiSSID,
		BSSID:     b.state.WiFiBSSID,
		Signal:    b.state.WiFiSignal,
		IP:        b.state.WiFiIP,
		Networks:  b.state.WiFiNetworks,
	}}
}
