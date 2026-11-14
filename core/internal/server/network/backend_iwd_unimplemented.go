package network

import (
	"fmt"
	"os"
)

func (b *IWDBackend) GetWiredConnections() ([]WiredConnection, error) {
	return nil, fmt.Errorf("wired connections not supported by iwd")
}

func (b *IWDBackend) GetWiredNetworkDetails(uuid string) (*WiredNetworkInfoResponse, error) {
	return nil, fmt.Errorf("wired connections not supported by iwd")
}

func (b *IWDBackend) ConnectEthernet() error {
	return fmt.Errorf("wired connections not supported by iwd")
}

func (b *IWDBackend) ConnectEthernetDevice(device string) error {
	return fmt.Errorf("wired connections not supported by iwd")
}

func (b *IWDBackend) DisconnectEthernet() error {
	return fmt.Errorf("wired connections not supported by iwd")
}

func (b *IWDBackend) DisconnectEthernetDevice(device string) error {
	return fmt.Errorf("wired connections not supported by iwd")
}

func (b *IWDBackend) GetEthernetDevices() []EthernetDevice {
	return []EthernetDevice{}
}

func (b *IWDBackend) ActivateWiredConnection(uuid, device string) error {
	return fmt.Errorf("wired connections not supported by iwd")
}

func (b *IWDBackend) GetCellularDevices() []CellularDevice {
	return []CellularDevice{}
}

func (b *IWDBackend) GetCellularEnabled() (bool, error) {
	return false, fmt.Errorf("cellular radio control not supported by iwd")
}

func (b *IWDBackend) SetCellularEnabled(enabled bool) error {
	return fmt.Errorf("cellular radio control not supported by iwd")
}

func (b *IWDBackend) GetCellularConnections() ([]WiredConnection, error) {
	return nil, fmt.Errorf("cellular connections not supported by iwd")
}

func (b *IWDBackend) ConnectCellular() error {
	return fmt.Errorf("cellular connections not supported by iwd")
}

func (b *IWDBackend) DisconnectCellular() error {
	return fmt.Errorf("cellular connections not supported by iwd")
}

func (b *IWDBackend) DisconnectCellularDevice(device string) error {
	return fmt.Errorf("cellular connections not supported by iwd")
}

func (b *IWDBackend) ActivateCellularConnection(uuid string) error {
	return fmt.Errorf("cellular connections not supported by iwd")
}

func (b *IWDBackend) ListVPNProfiles() ([]VPNProfile, error) {
	return nil, fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) ListActiveVPN() ([]VPNActive, error) {
	return nil, fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) ConnectVPN(uuidOrName string, singleActive bool) error {
	return fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) DisconnectVPN(uuidOrName string) error {
	return fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) DisconnectAllVPN() error {
	return fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) ClearVPNCredentials(uuidOrName string) error {
	return fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) ListVPNPlugins() ([]VPNPlugin, error) {
	return nil, fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) ImportVPN(filePath string, name string) (*VPNImportResult, error) {
	return nil, fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) GetVPNConfig(uuidOrName string) (*VPNConfig, error) {
	return nil, fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) UpdateVPNConfig(uuid string, updates map[string]any) error {
	return fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) DeleteVPN(uuidOrName string) error {
	return fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) SetVPNCredentials(uuid, username, password string, save bool) error {
	return fmt.Errorf("VPN not supported by iwd backend")
}

func (b *IWDBackend) ScanWiFiDevice(device string) error {
	return b.ScanWiFi()
}

func (b *IWDBackend) DisconnectWiFiDevice(device string) error {
	return b.DisconnectWiFi()
}

func (b *IWDBackend) GetWiFiDevices() []WiFiDevice {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()
	return b.getWiFiDevicesLocked()
}

func (b *IWDBackend) getWiFiDevicesLocked() []WiFiDevice {
	if b.state.WiFiDevice == "" {
		return nil
	}

	stateStr := "disconnected"
	if b.state.WiFiConnected {
		stateStr = "connected"
	}

	return []WiFiDevice{{
		Name:      b.state.WiFiDevice,
		State:     stateStr,
		Connected: b.state.WiFiConnected,
		SSID:      b.state.WiFiSSID,
		Signal:    b.state.WiFiSignal,
		IP:        b.state.WiFiIP,
		Networks:  b.state.WiFiNetworks,
	}}
}

func (b *IWDBackend) GetWiFiQRCodeContent(ssid string) (string, error) {
	path := iwdConfigPath(ssid)

	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("no saved iwd config for `%s`: %w", ssid, err)
	}

	passphrase, err := parseIWDPassphrase(string(data))
	if err != nil {
		return "", fmt.Errorf("failed to read passphrase for `%s`: %w", ssid, err)
	}

	return FormatWiFiQRString("WPA", ssid, passphrase), nil
}
