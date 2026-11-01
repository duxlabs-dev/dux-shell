package network

import (
	"fmt"
	"maps"
	"sync"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	dbusNMPath                 = "/org/freedesktop/NetworkManager"
	dbusNMInterface            = "org.freedesktop.NetworkManager"
	dbusNMDeviceInterface      = "org.freedesktop.NetworkManager.Device"
	dbusNMWiredInterface       = "org.freedesktop.NetworkManager.Device.Wired"
	dbusNMWirelessInterface    = "org.freedesktop.NetworkManager.Device.Wireless"
	dbusNMAccessPointInterface = "org.freedesktop.NetworkManager.AccessPoint"
	dbusNMActiveConnInterface  = "org.freedesktop.NetworkManager.Connection.Active"
	dbusNMVPNConnInterface     = "org.freedesktop.NetworkManager.VPN.Connection"
	dbusNMActiveConnPath       = "/org/freedesktop/NetworkManager/ActiveConnection"
	dbusPropsInterface         = "org.freedesktop.DBus.Properties"

	NmDeviceStateReasonWrongPassword        = 8
	NmDeviceStateReasonSupplicantTimeout    = 24
	NmDeviceStateReasonSupplicantFailed     = 25
	NmDeviceStateReasonSecretsRequired      = 7
	NmDeviceStateReasonNoSecrets            = 6
	NmDeviceStateReasonNoSsid               = 10
	NmDeviceStateReasonDhcpClientFailed     = 14
	NmDeviceStateReasonIpConfigUnavailable  = 18
	NmDeviceStateReasonSupplicantDisconnect = 23
	NmDeviceStateReasonCarrier              = 40
	NmDeviceStateReasonNewActivation        = 60
)

type wifiDeviceInfo struct {
	device    gonetworkmanager.Device
	wireless  gonetworkmanager.DeviceWireless
	name      string
	hwAddress string
}

type ethernetDeviceInfo struct {
	device    gonetworkmanager.Device
	wired     gonetworkmanager.DeviceWired
	name      string
	hwAddress string
}

type cellularDeviceInfo struct {
	device      gonetworkmanager.Device
	name        string
	hwAddress   string
	description string
}

type NetworkManagerBackend struct {
	nmConn          any
	ethernetDevice  any
	ethernetDevices map[string]*ethernetDeviceInfo
	cellularDevice  any
	cellularDevices map[string]*cellularDeviceInfo
	wifiDevice      any
	settings        any
	wifiDev         any
	wifiDevices     map[string]*wifiDeviceInfo

	// devMutex guards the device maps and selected Wi-Fi device pointers.
	// Not reentrant: never hold it across calls into other backend methods.
	devMutex sync.RWMutex

	// modems holds ModemManager radio metrics keyed by modem object path.
	modems     map[dbus.ObjectPath]modemInfo
	modemMutex sync.RWMutex

	dbusConn *dbus.Conn
	signals  chan *dbus.Signal
	sigWG    sync.WaitGroup
	stopChan chan struct{}

	wifiRefreshTimer *time.Timer
	wifiRefreshMu    sync.Mutex
	wifiRefreshWG    sync.WaitGroup

	secretAgent  *SecretAgent
	promptBroker PromptBroker

	state      *BackendState
	stateMutex sync.RWMutex

	lastFailedSSID string
	lastFailedTime int64
	failedMutex    sync.RWMutex

	hotspotPendingDevice string

	pendingVPNSave        *pendingVPNCredentials
	pendingVPNSaveMu      sync.Mutex
	cachedVPNCreds        *cachedVPNCredentials
	cachedVPNCredsMu      sync.Mutex
	cachedPKCS11PIN       *cachedPKCS11PIN
	cachedPKCS11Mu        sync.Mutex
	cachedOpenConnectAuth *cachedOpenConnectAuth
	cachedOpenConnectMu   sync.Mutex
	cachedWiFiSecret      *cachedWiFiSecret
	cachedWiFiSecretMu    sync.Mutex

	onStateChange func()
}

type pendingVPNCredentials struct {
	ConnectionPath string
	Username       string
	Password       string
	// Secrets holds all VPN secret fields keyed by name (e.g. "cert-pass");
	// falls back to Password under the "password" key when empty.
	Secrets           map[string]string
	PersistentSecrets map[string]string
	// PersistentData holds non-secret vpn data entries to merge on success,
	// such as a server certificate the user chose to trust.
	PersistentData map[string]string
	SavePassword   bool
}

type cachedVPNCredentials struct {
	ConnectionUUID string
	Password       string
	SavePassword   bool
}

type cachedPKCS11PIN struct {
	ConnectionUUID string
	PIN            string
}

// cachedWiFiSecret reuses a just-entered WiFi/802.1x secret across repeat
// GetSecrets calls in one activation, so NM retries don't re-prompt.
type cachedWiFiSecret struct {
	ConnectionUUID string
	SSID           string
	SettingName    string
	Secrets        map[string]string
}

type cachedOpenConnectAuth struct {
	ConnectionUUID string
	Cookie         string
	Host           string
	User           string
	Fingerprint    string
}

func NewNetworkManagerBackend(nmConn ...gonetworkmanager.NetworkManager) (*NetworkManagerBackend, error) {
	var nm gonetworkmanager.NetworkManager
	var err error

	if len(nmConn) > 0 && nmConn[0] != nil {
		// Use injected connection (for testing)
		nm = nmConn[0]
	} else {
		// Create real connection
		nm, err = gonetworkmanager.NewNetworkManager()
		if err != nil {
			return nil, fmt.Errorf("failed to connect to NetworkManager: %w", err)
		}
	}

	backend := &NetworkManagerBackend{
		nmConn:          nm,
		stopChan:        make(chan struct{}),
		ethernetDevices: make(map[string]*ethernetDeviceInfo),
		cellularDevices: make(map[string]*cellularDeviceInfo),
		wifiDevices:     make(map[string]*wifiDeviceInfo),
		state: &BackendState{
			Backend: "networkmanager",
		},
	}

	return backend, nil
}

func (b *NetworkManagerBackend) Initialize() error {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)

	if s, err := gonetworkmanager.NewSettings(); err == nil {
		b.settings = s
	}

	devices, err := nm.GetDevices()
	if err != nil {
		return fmt.Errorf("failed to get devices: %w", err)
	}

	for _, dev := range devices {
		devType, err := dev.GetPropertyDeviceType()
		if err != nil {
			continue
		}

		switch devType {
		case gonetworkmanager.NmDeviceTypeEthernet:
			if managed, _ := dev.GetPropertyManaged(); !managed {
				continue
			}
			iface, err := dev.GetPropertyInterface()
			if err != nil {
				continue
			}
			w, err := gonetworkmanager.NewDeviceWired(dev.GetPath())
			if err != nil {
				continue
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
			if err := b.updateEthernetState(); err != nil {
				continue
			}
			_, err = b.listEthernetConnections()
			if err != nil {
				return fmt.Errorf("failed to get wired configurations: %w", err)
			}

		case gonetworkmanager.NmDeviceTypeModem:
			if managed, _ := dev.GetPropertyManaged(); !managed {
				continue
			}
			iface, err := dev.GetPropertyInterface()
			if err != nil {
				continue
			}
			hwAddr := ""
			description := "Mobile broadband"
			if g, err := gonetworkmanager.NewDeviceGeneric(dev.GetPath()); err == nil {
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

		case gonetworkmanager.NmDeviceTypeWifi:
			iface, err := dev.GetPropertyInterface()
			if err != nil {
				continue
			}
			w, err := gonetworkmanager.NewDeviceWireless(dev.GetPath())
			if err != nil {
				continue
			}
			hwAddr, _ := w.GetPropertyHwAddress()

			b.setWifiDeviceInfo(iface, &wifiDeviceInfo{
				device:    dev,
				wireless:  w,
				name:      iface,
				hwAddress: hwAddr,
			})
		}
	}

	wifiEnabled, err := nm.GetPropertyWirelessEnabled()
	if err == nil {
		b.stateMutex.Lock()
		b.state.WiFiEnabled = wifiEnabled
		b.stateMutex.Unlock()
	}
	b.updateCellularRadioState()

	if err := b.updateWiFiState(); err != nil {
		log.Warnf("Failed to update WiFi state: %v", err)
	}

	if err := b.updateSavedWiFiNetworks(); err != nil {
		log.Warnf("Failed to get initial saved WiFi networks: %v", err)
	}

	if err := b.updateHotspotState(); err != nil {
		log.Warnf("Failed to get initial hotspot state: %v", err)
	}

	if wifiEnabled {
		if _, err := b.updateWiFiNetworks(); err != nil {
			log.Warnf("Failed to get initial networks: %v", err)
		}
	}
	// Device metadata (names, AP capability) is needed even while the radio is
	// disabled, e.g. by the hotspot device selector.
	b.updateAllWiFiDevices()

	b.updateAllEthernetDevices()
	b.updateAllCellularDevices()
	if err := b.updateCellularState(); err != nil {
		log.Warnf("Failed to update cellular state: %v", err)
	}
	if _, err := b.listCellularConnections(); err != nil {
		log.Warnf("Failed to get initial cellular configurations: %v", err)
	}

	if err := b.updatePrimaryConnection(); err != nil {
		return err
	}

	if _, err := b.ListVPNProfiles(); err != nil {
		log.Warnf("Failed to get initial VPN profiles: %v", err)
	}

	if _, err := b.ListActiveVPN(); err != nil {
		log.Warnf("Failed to get initial active VPNs: %v", err)
	}

	return nil
}

func (b *NetworkManagerBackend) ethernetDevicesSnapshot() map[string]*ethernetDeviceInfo {
	b.devMutex.RLock()
	defer b.devMutex.RUnlock()
	out := make(map[string]*ethernetDeviceInfo, len(b.ethernetDevices))
	maps.Copy(out, b.ethernetDevices)
	return out
}

func (b *NetworkManagerBackend) wifiDevicesSnapshot() map[string]*wifiDeviceInfo {
	b.devMutex.RLock()
	defer b.devMutex.RUnlock()
	out := make(map[string]*wifiDeviceInfo, len(b.wifiDevices))
	maps.Copy(out, b.wifiDevices)
	return out
}

func (b *NetworkManagerBackend) cellularDevicesSnapshot() map[string]*cellularDeviceInfo {
	b.devMutex.RLock()
	defer b.devMutex.RUnlock()
	out := make(map[string]*cellularDeviceInfo, len(b.cellularDevices))
	maps.Copy(out, b.cellularDevices)
	return out
}

func (b *NetworkManagerBackend) ethernetDeviceByIface(iface string) (*ethernetDeviceInfo, bool) {
	b.devMutex.RLock()
	defer b.devMutex.RUnlock()
	info, ok := b.ethernetDevices[iface]
	return info, ok
}

func (b *NetworkManagerBackend) wifiDeviceByIface(iface string) (*wifiDeviceInfo, bool) {
	b.devMutex.RLock()
	defer b.devMutex.RUnlock()
	info, ok := b.wifiDevices[iface]
	return info, ok
}

func (b *NetworkManagerBackend) cellularDeviceByIface(iface string) (*cellularDeviceInfo, bool) {
	b.devMutex.RLock()
	defer b.devMutex.RUnlock()
	info, ok := b.cellularDevices[iface]
	return info, ok
}

func (b *NetworkManagerBackend) setEthernetDeviceInfo(iface string, info *ethernetDeviceInfo) {
	b.devMutex.Lock()
	b.ethernetDevices[iface] = info
	b.devMutex.Unlock()
}

func (b *NetworkManagerBackend) setWifiDeviceInfo(iface string, info *wifiDeviceInfo) {
	b.devMutex.Lock()
	defer b.devMutex.Unlock()
	previous := b.wifiDevices[iface]
	if b.dbusConn != nil && (previous == nil || previous.device.GetPath() != info.device.GetPath()) {
		if err := b.dbusConn.AddMatchSignal(
			dbus.WithMatchObjectPath(info.device.GetPath()),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		); err != nil {
			log.Warnf("Failed to watch WiFi device: %v", err)
			return
		}
		if previous != nil {
			b.dbusConn.RemoveMatchSignal(
				dbus.WithMatchObjectPath(previous.device.GetPath()),
				dbus.WithMatchInterface(dbusPropsInterface),
				dbus.WithMatchMember("PropertiesChanged"),
			)
		}
	}
	b.wifiDevices[iface] = info
	if b.wifiDevice == nil || (previous != nil && b.wifiDevice.(gonetworkmanager.Device).GetPath() == previous.device.GetPath()) {
		b.wifiDevice, b.wifiDev = info.device, info.wireless
	}
}

func (b *NetworkManagerBackend) setCellularDeviceInfo(iface string, info *cellularDeviceInfo) {
	b.devMutex.Lock()
	b.cellularDevices[iface] = info
	b.devMutex.Unlock()
}

// removeEthernetDeviceByPath deletes the device and returns a snapshot of
// what's left so the caller can pick a replacement without holding devMutex
func (b *NetworkManagerBackend) removeEthernetDeviceByPath(path dbus.ObjectPath) (removed *ethernetDeviceInfo, remaining map[string]*ethernetDeviceInfo, found bool) {
	b.devMutex.Lock()
	defer b.devMutex.Unlock()
	for iface, info := range b.ethernetDevices {
		if info.device.GetPath() != path {
			continue
		}
		delete(b.ethernetDevices, iface)
		remaining = make(map[string]*ethernetDeviceInfo, len(b.ethernetDevices))
		maps.Copy(remaining, b.ethernetDevices)
		return info, remaining, true
	}
	return nil, nil, false
}

func (b *NetworkManagerBackend) removeWifiDeviceByPath(path dbus.ObjectPath) (removed *wifiDeviceInfo, remaining map[string]*wifiDeviceInfo, found bool) {
	b.devMutex.Lock()
	defer b.devMutex.Unlock()
	for iface, info := range b.wifiDevices {
		if info.device.GetPath() != path {
			continue
		}
		if b.dbusConn != nil {
			b.dbusConn.RemoveMatchSignal(
				dbus.WithMatchObjectPath(path),
				dbus.WithMatchInterface(dbusPropsInterface),
				dbus.WithMatchMember("PropertiesChanged"),
			)
		}
		delete(b.wifiDevices, iface)
		if b.wifiDevice != nil && b.wifiDevice.(gonetworkmanager.Device).GetPath() == path {
			b.wifiDevice, b.wifiDev = nil, nil
			for _, replacement := range b.wifiDevices {
				b.wifiDevice, b.wifiDev = replacement.device, replacement.wireless
				break
			}
		}
		remaining = make(map[string]*wifiDeviceInfo, len(b.wifiDevices))
		maps.Copy(remaining, b.wifiDevices)
		return info, remaining, true
	}
	return nil, nil, false
}

func (b *NetworkManagerBackend) removeCellularDeviceByPath(path dbus.ObjectPath) (removed *cellularDeviceInfo, remaining map[string]*cellularDeviceInfo, found bool) {
	b.devMutex.Lock()
	defer b.devMutex.Unlock()
	for iface, info := range b.cellularDevices {
		if info.device.GetPath() != path {
			continue
		}
		delete(b.cellularDevices, iface)
		remaining = make(map[string]*cellularDeviceInfo, len(b.cellularDevices))
		maps.Copy(remaining, b.cellularDevices)
		return info, remaining, true
	}
	return nil, nil, false
}

func (b *NetworkManagerBackend) Close() {
	close(b.stopChan)
	b.StopMonitoring()

	if b.secretAgent != nil {
		b.secretAgent.Close()
	}
}

func (b *NetworkManagerBackend) GetCurrentState() (*BackendState, error) {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()

	state := *b.state
	state.WiFiNetworks = append([]WiFiNetwork(nil), b.state.WiFiNetworks...)
	state.SavedWiFiNetworks = append([]WiFiNetwork(nil), b.state.SavedWiFiNetworks...)
	state.WiFiDevices = append([]WiFiDevice(nil), b.state.WiFiDevices...)
	state.WiredConnections = append([]WiredConnection(nil), b.state.WiredConnections...)
	state.EthernetDevices = append([]EthernetDevice(nil), b.state.EthernetDevices...)
	state.CellularConnections = append([]WiredConnection(nil), b.state.CellularConnections...)
	state.CellularDevices = append([]CellularDevice(nil), b.state.CellularDevices...)
	state.VPNProfiles = append([]VPNProfile(nil), b.state.VPNProfiles...)
	state.VPNActive = append([]VPNActive(nil), b.state.VPNActive...)

	return &state, nil
}

func (b *NetworkManagerBackend) StartMonitoring(onStateChange func()) error {
	b.onStateChange = onStateChange

	if err := b.startSecretAgent(); err != nil {
		return fmt.Errorf("failed to start secret agent: %w", err)
	}

	if err := b.startSignalPump(); err != nil {
		return err
	}

	return nil
}

func (b *NetworkManagerBackend) StopMonitoring() {
	b.stopSignalPump()
}

func (b *NetworkManagerBackend) GetPromptBroker() PromptBroker {
	return b.promptBroker
}

func (b *NetworkManagerBackend) SetPromptBroker(broker PromptBroker) error {
	if broker == nil {
		return fmt.Errorf("broker cannot be nil")
	}

	hadAgent := b.secretAgent != nil

	b.promptBroker = broker

	if b.secretAgent != nil {
		b.secretAgent.Close()
		b.secretAgent = nil
	}

	if hadAgent {
		return b.startSecretAgent()
	}

	return nil
}

func (b *NetworkManagerBackend) SubmitCredentials(token string, secrets map[string]string, save bool) error {
	if b.promptBroker == nil {
		return fmt.Errorf("prompt broker not initialized")
	}

	return b.promptBroker.Resolve(token, PromptReply{
		Secrets: secrets,
		Save:    save,
		Cancel:  false,
	})
}

func (b *NetworkManagerBackend) CancelCredentials(token string) error {
	if b.promptBroker == nil {
		return fmt.Errorf("prompt broker not initialized")
	}

	return b.promptBroker.Resolve(token, PromptReply{
		Cancel: true,
	})
}

// mergeStoredSecrets re-fetches stored secrets and folds them into settings
// before an Update. GetSettings never returns secrets and Update replaces the
// whole connection, so a bare GetSettings->Update wipes system-owned passwords
// (e.g. an OpenVPN password with password-flags=0). Only fills keys that aren't
// already being set, so an explicit credential change still wins.
func mergeStoredSecrets(conn gonetworkmanager.Connection, settings gonetworkmanager.ConnectionSettings) {
	for setting := range settings {
		switch setting {
		case "vpn", "802-11-wireless-security", "802-1x":
		default:
			continue
		}

		secrets, err := conn.GetSecrets(setting)
		if err != nil {
			continue
		}

		section, ok := secrets[setting]
		if !ok {
			continue
		}

		for k, v := range section {
			if _, exists := settings[setting][k]; exists {
				continue
			}
			settings[setting][k] = v
		}
	}
}

func (b *NetworkManagerBackend) cacheWiFiSecret(connUUID, ssid, settingName string, secrets map[string]string) {
	if connUUID == "" || len(secrets) == 0 {
		return
	}

	copied := make(map[string]string, len(secrets))
	maps.Copy(copied, secrets)

	b.cachedWiFiSecretMu.Lock()
	b.cachedWiFiSecret = &cachedWiFiSecret{
		ConnectionUUID: connUUID,
		SSID:           ssid,
		SettingName:    settingName,
		Secrets:        copied,
	}
	b.cachedWiFiSecretMu.Unlock()
}

func (b *NetworkManagerBackend) lookupCachedWiFiSecret(connUUID, settingName string) map[string]string {
	if connUUID == "" {
		return nil
	}

	b.cachedWiFiSecretMu.Lock()
	defer b.cachedWiFiSecretMu.Unlock()

	cached := b.cachedWiFiSecret
	if cached == nil || cached.ConnectionUUID != connUUID || cached.SettingName != settingName {
		return nil
	}

	copied := make(map[string]string, len(cached.Secrets))
	maps.Copy(copied, cached.Secrets)
	return copied
}

func (b *NetworkManagerBackend) clearCachedWiFiSecret(connUUID string) {
	b.cachedWiFiSecretMu.Lock()
	defer b.cachedWiFiSecretMu.Unlock()

	if connUUID == "" {
		b.cachedWiFiSecret = nil
		return
	}
	if b.cachedWiFiSecret != nil && b.cachedWiFiSecret.ConnectionUUID == connUUID {
		b.cachedWiFiSecret = nil
	}
}

func (b *NetworkManagerBackend) clearCachedWiFiSecretBySSID(ssid string) {
	if ssid == "" {
		return
	}

	b.cachedWiFiSecretMu.Lock()
	defer b.cachedWiFiSecretMu.Unlock()

	if b.cachedWiFiSecret != nil && b.cachedWiFiSecret.SSID == ssid {
		b.cachedWiFiSecret = nil
	}
}

func (b *NetworkManagerBackend) selectedWiFiDevice() (gonetworkmanager.Device, gonetworkmanager.DeviceWireless) {
	b.devMutex.RLock()
	defer b.devMutex.RUnlock()
	dev, _ := b.wifiDevice.(gonetworkmanager.Device)
	wireless, _ := b.wifiDev.(gonetworkmanager.DeviceWireless)
	return dev, wireless
}

func (b *NetworkManagerBackend) ensureWiFiDevice() (gonetworkmanager.DeviceWireless, error) {
	b.devMutex.Lock()
	defer b.devMutex.Unlock()
	if b.wifiDev != nil {
		return b.wifiDev.(gonetworkmanager.DeviceWireless), nil
	}

	if b.wifiDevice == nil {
		return nil, fmt.Errorf("no WiFi device available")
	}

	dev := b.wifiDevice.(gonetworkmanager.Device)
	wifiDev, err := gonetworkmanager.NewDeviceWireless(dev.GetPath())
	if err != nil {
		return nil, fmt.Errorf("failed to get wireless device: %w", err)
	}
	b.wifiDev = wifiDev
	return wifiDev, nil
}

func (b *NetworkManagerBackend) refreshWiFiDevices() (bool, error) {
	// Serialize discovery with hotplug handlers so an older snapshot cannot
	// overwrite an addition or removal that has already been handled.
	b.devMutex.Lock()
	defer b.devMutex.Unlock()

	devices, err := b.nmConn.(gonetworkmanager.NetworkManager).GetDevices()
	if err != nil {
		return false, fmt.Errorf("failed to get devices: %w", err)
	}

	previousPaths := make(map[dbus.ObjectPath]bool, len(b.wifiDevices))
	for _, info := range b.wifiDevices {
		previousPaths[info.device.GetPath()] = true
	}
	var selectedPath dbus.ObjectPath
	if b.wifiDevice != nil {
		selectedPath = b.wifiDevice.(gonetworkmanager.Device).GetPath()
	}

	wifiDevices := make(map[string]*wifiDeviceInfo)
	var selected *wifiDeviceInfo
	for _, dev := range devices {
		// GetDevices uses DeviceFactory, which returns DeviceWireless for Wi-Fi.
		wireless, ok := dev.(gonetworkmanager.DeviceWireless)
		if !ok {
			continue
		}
		iface, err := dev.GetPropertyInterface()
		if err != nil {
			return false, fmt.Errorf("failed to get WiFi interface: %w", err)
		}
		hwAddress, _ := wireless.GetPropertyHwAddress()
		info := &wifiDeviceInfo{device: dev, wireless: wireless, name: iface, hwAddress: hwAddress}
		wifiDevices[iface] = info
		path := dev.GetPath()
		if selected == nil || path == selectedPath {
			selected = info
		}
	}

	changed := len(wifiDevices) != len(b.wifiDevices)
	for name, info := range wifiDevices {
		previous := b.wifiDevices[name]
		if previous == nil || previous.device.GetPath() != info.device.GetPath() {
			changed = true
		}
	}

	if b.dbusConn != nil {
		var addedPaths []dbus.ObjectPath
		for _, info := range wifiDevices {
			path := info.device.GetPath()
			if previousPaths[path] {
				delete(previousPaths, path)
				continue
			}
			if err := b.dbusConn.AddMatchSignal(
				dbus.WithMatchObjectPath(path),
				dbus.WithMatchInterface(dbusPropsInterface),
				dbus.WithMatchMember("PropertiesChanged"),
			); err != nil {
				for _, added := range addedPaths {
					b.dbusConn.RemoveMatchSignal(
						dbus.WithMatchObjectPath(added),
						dbus.WithMatchInterface(dbusPropsInterface),
						dbus.WithMatchMember("PropertiesChanged"),
					)
				}
				return false, fmt.Errorf("failed to watch WiFi device: %w", err)
			}
			addedPaths = append(addedPaths, path)
		}
		for path := range previousPaths {
			b.dbusConn.RemoveMatchSignal(
				dbus.WithMatchObjectPath(path),
				dbus.WithMatchInterface(dbusPropsInterface),
				dbus.WithMatchMember("PropertiesChanged"),
			)
		}
	}

	b.wifiDevices = wifiDevices
	b.wifiDevice, b.wifiDev = nil, nil
	if selected != nil {
		b.wifiDevice, b.wifiDev = selected.device, selected.wireless
	}
	return changed, nil
}

func (b *NetworkManagerBackend) startSecretAgent() error {
	if b.promptBroker == nil {
		return fmt.Errorf("prompt broker not set")
	}

	agent, err := NewSecretAgent(b.promptBroker, nil, b)
	if err != nil {
		return err
	}

	b.secretAgent = agent
	return nil
}

func (b *NetworkManagerBackend) getActiveConnections() (map[string]bool, error) {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)

	activeUUIDs := make(map[string]bool)

	activeConns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return activeUUIDs, fmt.Errorf("failed to get active connections: %w", err)
	}

	for _, activeConn := range activeConns {
		connType, err := activeConn.GetPropertyType()
		if err != nil {
			continue
		}

		if connType != "802-3-ethernet" && !isCellularConnectionType(connType) {
			continue
		}

		state, err := activeConn.GetPropertyState()
		if err != nil {
			continue
		}
		if state < 1 || state > 2 {
			continue
		}

		uuid, err := activeConn.GetPropertyUUID()
		if err != nil {
			continue
		}
		activeUUIDs[uuid] = true
	}
	return activeUUIDs, nil
}
