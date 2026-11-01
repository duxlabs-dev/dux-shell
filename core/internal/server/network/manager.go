package network

import (
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/yeqown/go-qrcode/v2"
	"github.com/yeqown/go-qrcode/writer/standard"
)

// ErrNoNetworkBackend is returned when no supported network management daemon
// (NetworkManager, iwd, systemd-networkd, ConnMan, wpa_supplicant) is present
// on the system.
var ErrNoNetworkBackend = errors.New("no supported network backend found")

// ErrHotspotNotSupported is returned when the active backend does not implement
// hotspot operations.
var ErrHotspotNotSupported = errors.New("hotspot not supported by active network backend")

func NewManager() (*Manager, error) {
	detection, err := DetectNetworkStack()
	if err != nil {
		return nil, fmt.Errorf("failed to detect network stack: %w", err)
	}

	log.Infof("Network backend detection: %s", detection.ChosenReason)

	var backend Backend
	switch detection.Backend {
	case BackendNetworkManager:
		nm, err := NewNetworkManagerBackend()
		if err != nil {
			return nil, fmt.Errorf("failed to create NetworkManager backend: %w", err)
		}
		backend = nm

	case BackendIwd:
		iwd, err := NewIWDBackend()
		if err != nil {
			return nil, fmt.Errorf("failed to create iwd backend: %w", err)
		}
		backend = iwd

	case BackendNetworkd:
		if detection.HasIwd && !detection.HasNM {
			wifi, err := NewIWDBackend()
			if err != nil {
				return nil, fmt.Errorf("failed to create iwd backend: %w", err)
			}
			l3, err := NewSystemdNetworkdBackend()
			if err != nil {
				return nil, fmt.Errorf("failed to create networkd backend: %w", err)
			}
			hybrid, err := NewHybridIwdNetworkdBackend(wifi, l3)
			if err != nil {
				return nil, fmt.Errorf("failed to create hybrid backend: %w", err)
			}
			backend = hybrid
		} else {
			nd, err := NewSystemdNetworkdBackend()
			if err != nil {
				return nil, fmt.Errorf("failed to create networkd backend: %w", err)
			}
			backend = nd
		}

	case BackendWpaSupplicant:
		wpa, err := NewWpaSupplicantBackend()
		if err != nil {
			return nil, fmt.Errorf("failed to create wpa_supplicant backend: %w", err)
		}
		backend = wpa

	default:
		return nil, fmt.Errorf("%w: %s", ErrNoNetworkBackend, detection.ChosenReason)
	}

	m := &Manager{
		backend: backend,
		state: &NetworkState{
			NetworkStatus:     StatusDisconnected,
			Preference:        PreferenceAuto,
			WiFiNetworks:      []WiFiNetwork{},
			SavedWiFiNetworks: []WiFiNetwork{},
			CellularDevices:   []CellularDevice{},
		},
		stateMutex: sync.RWMutex{},

		stopChan: make(chan struct{}),
		dirty:    make(chan struct{}, 1),
	}

	broker := NewSubscriptionBroker(m.broadcastCredentialPrompt)
	if err := backend.SetPromptBroker(broker); err != nil {
		return nil, fmt.Errorf("failed to set prompt broker: %w", err)
	}

	if err := backend.Initialize(); err != nil {
		return nil, fmt.Errorf("failed to initialize backend: %w", err)
	}

	if err := m.syncStateFromBackend(); err != nil {
		return nil, fmt.Errorf("failed to sync initial state: %w", err)
	}

	m.notifierWg.Add(1)
	go m.notifier()

	if err := backend.StartMonitoring(m.onBackendStateChange); err != nil {
		m.Close()
		return nil, fmt.Errorf("failed to start monitoring: %w", err)
	}

	return m, nil
}

func (m *Manager) hotspotBackend() (HotspotBackend, bool) {
	backend, ok := m.backend.(HotspotBackend)
	return backend, ok
}

func (m *Manager) syncStateFromBackend() error {
	backendState, err := m.backend.GetCurrentState()
	if err != nil {
		return err
	}
	_, hotspotSupported := m.hotspotBackend()

	m.stateMutex.Lock()
	m.state.Backend = backendState.Backend
	m.state.NetworkStatus = backendState.NetworkStatus
	m.state.EthernetIP = backendState.EthernetIP
	m.state.EthernetDevice = backendState.EthernetDevice
	m.state.EthernetConnected = backendState.EthernetConnected
	m.state.EthernetConnectionUuid = backendState.EthernetConnectionUuid
	m.state.EthernetDevices = backendState.EthernetDevices
	m.state.CellularIP = backendState.CellularIP
	m.state.CellularDevice = backendState.CellularDevice
	m.state.CellularConnected = backendState.CellularConnected
	m.state.CellularEnabled = backendState.CellularEnabled
	m.state.CellularHardwareEnabled = backendState.CellularHardwareEnabled
	m.state.CellularConnectionUuid = backendState.CellularConnectionUuid
	m.state.CellularDevices = backendState.CellularDevices
	m.state.CellularConnections = backendState.CellularConnections
	m.state.WiFiIP = backendState.WiFiIP
	m.state.WiFiDevice = backendState.WiFiDevice
	m.state.WiFiConnected = backendState.WiFiConnected
	m.state.WiFiEnabled = backendState.WiFiEnabled
	m.state.WiFiSSID = backendState.WiFiSSID
	m.state.WiFiBSSID = backendState.WiFiBSSID
	m.state.WiFiSignal = backendState.WiFiSignal
	m.state.WiFiNetworks = backendState.WiFiNetworks
	m.state.SavedWiFiNetworks = backendState.SavedWiFiNetworks
	m.state.WiFiDevices = backendState.WiFiDevices
	m.state.HotspotSupported = hotspotSupported
	if hotspotSupported {
		m.state.HotspotAvailable = backendState.HotspotAvailable
		m.state.HotspotConfigured = backendState.HotspotConfigured
		m.state.HotspotEnabled = backendState.HotspotEnabled
		m.state.HotspotActivating = backendState.HotspotActivating
		m.state.HotspotSecured = backendState.HotspotSecured
		m.state.HotspotSSID = backendState.HotspotSSID
		m.state.HotspotDevice = backendState.HotspotDevice
		m.state.HotspotBand = backendState.HotspotBand
		m.state.HotspotLastError = backendState.HotspotLastError
	} else {
		m.state.HotspotAvailable = false
		m.state.HotspotConfigured = false
		m.state.HotspotEnabled = false
		m.state.HotspotActivating = false
		m.state.HotspotSecured = false
		m.state.HotspotSSID = ""
		m.state.HotspotDevice = ""
		m.state.HotspotBand = ""
		m.state.HotspotLastError = ""
	}
	m.state.WiredConnections = backendState.WiredConnections
	m.state.VPNProfiles = backendState.VPNProfiles
	m.state.VPNActive = backendState.VPNActive
	m.state.IsConnecting = backendState.IsConnecting
	m.state.ConnectingSSID = backendState.ConnectingSSID
	m.state.ConnectingDevice = backendState.ConnectingDevice
	m.state.LastError = backendState.LastError
	m.state.VPNError = backendState.VPNError
	m.state.VPNErrorUuid = backendState.VPNErrorUuid
	m.stateMutex.Unlock()

	return nil
}

func (m *Manager) onBackendStateChange() {
	if err := m.syncStateFromBackend(); err != nil {
		log.Errorf("failed to sync state from backend: %v", err)
	}
	m.notifySubscribers()
}

func signalChangeSignificant(old, new uint8) bool {
	if old == 0 || new == 0 {
		return true
	}
	diff := int(new) - int(old)
	if diff < 0 {
		diff = -diff
	}
	return diff >= 5
}

func (m *Manager) snapshotState() NetworkState {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	s := *m.state
	s.WiFiNetworks = append([]WiFiNetwork(nil), m.state.WiFiNetworks...)
	s.SavedWiFiNetworks = append([]WiFiNetwork(nil), m.state.SavedWiFiNetworks...)
	s.WiFiDevices = append([]WiFiDevice(nil), m.state.WiFiDevices...)
	s.WiredConnections = append([]WiredConnection(nil), m.state.WiredConnections...)
	s.EthernetDevices = append([]EthernetDevice(nil), m.state.EthernetDevices...)
	s.CellularConnections = append([]WiredConnection(nil), m.state.CellularConnections...)
	s.CellularDevices = append([]CellularDevice(nil), m.state.CellularDevices...)
	s.VPNProfiles = append([]VPNProfile(nil), m.state.VPNProfiles...)
	s.VPNActive = append([]VPNActive(nil), m.state.VPNActive...)
	return s
}

func stateChangedMeaningfully(old, new *NetworkState) bool {
	if old.NetworkStatus != new.NetworkStatus {
		return true
	}
	if old.Preference != new.Preference {
		return true
	}
	if old.EthernetConnected != new.EthernetConnected {
		return true
	}
	if old.EthernetIP != new.EthernetIP {
		return true
	}
	if old.CellularConnected != new.CellularConnected {
		return true
	}
	if old.CellularEnabled != new.CellularEnabled {
		return true
	}
	if old.CellularHardwareEnabled != new.CellularHardwareEnabled {
		return true
	}
	if old.CellularIP != new.CellularIP {
		return true
	}
	if old.WiFiConnected != new.WiFiConnected {
		return true
	}
	if old.WiFiEnabled != new.WiFiEnabled {
		return true
	}
	if old.WiFiSSID != new.WiFiSSID {
		return true
	}
	if old.WiFiBSSID != new.WiFiBSSID {
		return true
	}
	if old.WiFiIP != new.WiFiIP {
		return true
	}
	if old.HotspotSupported != new.HotspotSupported {
		return true
	}
	if old.HotspotAvailable != new.HotspotAvailable {
		return true
	}
	if old.HotspotConfigured != new.HotspotConfigured {
		return true
	}
	if old.HotspotEnabled != new.HotspotEnabled {
		return true
	}
	if old.HotspotActivating != new.HotspotActivating {
		return true
	}
	if old.HotspotSecured != new.HotspotSecured {
		return true
	}
	if old.HotspotLastError != new.HotspotLastError {
		return true
	}
	if old.HotspotSSID != new.HotspotSSID {
		return true
	}
	if old.HotspotDevice != new.HotspotDevice {
		return true
	}
	if old.HotspotBand != new.HotspotBand {
		return true
	}
	if old.WiFiSignal != new.WiFiSignal && signalChangeSignificant(old.WiFiSignal, new.WiFiSignal) {
		return true
	}
	if old.IsConnecting != new.IsConnecting {
		return true
	}
	if old.ConnectingSSID != new.ConnectingSSID {
		return true
	}
	if old.LastError != new.LastError {
		return true
	}
	if old.VPNError != new.VPNError || old.VPNErrorUuid != new.VPNErrorUuid {
		return true
	}
	if len(old.WiFiNetworks) != len(new.WiFiNetworks) {
		return true
	}
	if len(old.SavedWiFiNetworks) != len(new.SavedWiFiNetworks) {
		return true
	}
	if len(old.WiFiDevices) != len(new.WiFiDevices) {
		return true
	}
	if len(old.WiredConnections) != len(new.WiredConnections) {
		return true
	}
	if len(old.EthernetDevices) != len(new.EthernetDevices) {
		return true
	}
	if len(old.CellularDevices) != len(new.CellularDevices) {
		return true
	}
	if len(old.CellularConnections) != len(new.CellularConnections) {
		return true
	}

	for i := range old.WiFiNetworks {
		oldNet := &old.WiFiNetworks[i]
		newNet := &new.WiFiNetworks[i]
		if oldNet.SSID != newNet.SSID {
			return true
		}
		if oldNet.Connected != newNet.Connected {
			return true
		}
		if oldNet.Saved != newNet.Saved {
			return true
		}
		if oldNet.Autoconnect != newNet.Autoconnect {
			return true
		}
	}

	for i := range old.SavedWiFiNetworks {
		oldNet := &old.SavedWiFiNetworks[i]
		newNet := &new.SavedWiFiNetworks[i]
		if oldNet.SSID != newNet.SSID {
			return true
		}
		if oldNet.Connected != newNet.Connected {
			return true
		}
		if oldNet.Autoconnect != newNet.Autoconnect {
			return true
		}
		if oldNet.OutOfRange != newNet.OutOfRange {
			return true
		}
	}

	// Per-device signal strength is intentionally not compared: it churns
	// constantly and the primary device's signal is already debounced above.
	for i := range old.WiFiDevices {
		oldDev := &old.WiFiDevices[i]
		newDev := &new.WiFiDevices[i]
		if oldDev.Name != newDev.Name {
			return true
		}
		if oldDev.State != newDev.State {
			return true
		}
		if oldDev.Connected != newDev.Connected {
			return true
		}
		if oldDev.APCapable != newDev.APCapable {
			return true
		}
		if oldDev.SSID != newDev.SSID {
			return true
		}
	}

	for i := range old.WiredConnections {
		oldNet := &old.WiredConnections[i]
		newNet := &new.WiredConnections[i]
		if oldNet.ID != newNet.ID {
			return true
		}
		if oldNet.IsActive != newNet.IsActive {
			return true
		}
	}

	for i := range old.EthernetDevices {
		oldDev := &old.EthernetDevices[i]
		newDev := &new.EthernetDevices[i]
		if oldDev.Name != newDev.Name {
			return true
		}
		if oldDev.Connected != newDev.Connected {
			return true
		}
		if oldDev.State != newDev.State {
			return true
		}
		if oldDev.IP != newDev.IP {
			return true
		}
	}

	for i := range old.CellularConnections {
		oldNet := &old.CellularConnections[i]
		newNet := &new.CellularConnections[i]
		if oldNet.ID != newNet.ID {
			return true
		}
		if oldNet.IsActive != newNet.IsActive {
			return true
		}
	}

	for i := range old.CellularDevices {
		oldDev := &old.CellularDevices[i]
		newDev := &new.CellularDevices[i]
		if oldDev.Name != newDev.Name {
			return true
		}
		if oldDev.Connected != newDev.Connected {
			return true
		}
		if oldDev.State != newDev.State {
			return true
		}
		if oldDev.IP != newDev.IP {
			return true
		}
		if oldDev.AccessTech != newDev.AccessTech {
			return true
		}
		if oldDev.SignalQuality != newDev.SignalQuality &&
			signalChangeSignificant(uint8(oldDev.SignalQuality), uint8(newDev.SignalQuality)) {
			return true
		}
	}

	// Check VPN profiles count
	if len(old.VPNProfiles) != len(new.VPNProfiles) {
		return true
	}

	// Check active VPN connections count or state
	if len(old.VPNActive) != len(new.VPNActive) {
		return true
	}

	// Check if any active VPN changed
	for i := range old.VPNActive {
		oldVPN := &old.VPNActive[i]
		newVPN := &new.VPNActive[i]
		if oldVPN.UUID != newVPN.UUID {
			return true
		}
		if oldVPN.State != newVPN.State {
			return true
		}
	}

	return false
}

func (m *Manager) GetState() NetworkState {
	return m.snapshotState()
}

func (m *Manager) Subscribe(id string) chan NetworkState {
	ch := make(chan NetworkState, 64)
	m.subscribers.Store(id, ch)
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)
	}
}

func (m *Manager) SubscribeCredentials(id string) chan CredentialPrompt {
	ch := make(chan CredentialPrompt, 16)
	m.credentialSubscribers.Store(id, ch)
	return ch
}

func (m *Manager) UnsubscribeCredentials(id string) {
	if ch, ok := m.credentialSubscribers.LoadAndDelete(id); ok {
		close(ch)
	}
}

func (m *Manager) broadcastCredentialPrompt(prompt CredentialPrompt) {
	m.credentialSubscribers.Range(func(key string, ch chan CredentialPrompt) bool {
		select {
		case ch <- prompt:
		default:
		}
		return true
	})
}

func (m *Manager) notifier() {
	defer m.notifierWg.Done()
	const minGap = 100 * time.Millisecond
	timer := time.NewTimer(minGap)
	timer.Stop()
	var pending bool
	for {
		select {
		case <-m.stopChan:
			timer.Stop()
			return
		case <-m.dirty:
			if pending {
				continue
			}
			pending = true
			timer.Reset(minGap)
		case <-timer.C:
			if !pending {
				continue
			}

			currentState := m.snapshotState()

			if m.lastNotifiedState != nil && !stateChangedMeaningfully(m.lastNotifiedState, &currentState) {
				pending = false
				continue
			}

			m.subscribers.Range(func(key string, ch chan NetworkState) bool {
				select {
				case ch <- currentState:
				default:
				}
				return true
			})

			stateCopy := currentState
			m.lastNotifiedState = &stateCopy
			pending = false
		}
	}
}

func (m *Manager) notifySubscribers() {
	select {
	case m.dirty <- struct{}{}:
	default:
	}
}

func (m *Manager) SetPromptBroker(broker PromptBroker) error {
	return m.backend.SetPromptBroker(broker)
}

func (m *Manager) SubmitCredentials(token string, secrets map[string]string, save bool) error {
	return m.backend.SubmitCredentials(token, secrets, save)
}

func (m *Manager) CancelCredentials(token string) error {
	return m.backend.CancelCredentials(token)
}

func (m *Manager) GetPromptBroker() PromptBroker {
	return m.backend.GetPromptBroker()
}

func (m *Manager) Close() {
	close(m.stopChan)
	m.notifierWg.Wait()

	if m.backend != nil {
		m.backend.Close()
	}

	m.subscribers.Range(func(key string, ch chan NetworkState) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})
}

func (m *Manager) ScanWiFi() error {
	return m.backend.ScanWiFi()
}

func (m *Manager) GetWiFiNetworks() []WiFiNetwork {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	networks := make([]WiFiNetwork, len(m.state.WiFiNetworks))
	copy(networks, m.state.WiFiNetworks)
	return networks
}

func (m *Manager) GetNetworkInfo(ssid string) (*WiFiNetwork, error) {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()

	for _, network := range m.state.WiFiNetworks {
		if network.SSID == ssid {
			return &network, nil
		}
	}

	return nil, fmt.Errorf("network not found: %s", ssid)
}

func (m *Manager) GetNetworkInfoDetailed(ssid string) (*NetworkInfoResponse, error) {
	return m.backend.GetWiFiNetworkDetails(ssid)
}

func (m *Manager) GetWiFiQRContent(ssid string) (string, error) {
	return m.backend.GetWiFiQRCodeContent(ssid)
}

func (m *Manager) GetNetworkQRCode(ssid string) ([2]string, error) {
	content, err := m.backend.GetWiFiQRCodeContent(ssid)
	if err != nil {
		return [2]string{}, err
	}

	qrc, err := qrcode.New(content)
	if err != nil {
		return [2]string{}, fmt.Errorf("failed to create QR code for `%s`: %w", ssid, err)
	}

	pathThemed, pathNormal := qrCodePaths(ssid)

	wThemed, err := standard.New(
		pathThemed,
		standard.WithBuiltinImageEncoder(standard.PNG_FORMAT),
		standard.WithBgTransparent(),
		standard.WithFgColorRGBHex("#ffffff"),
	)
	if err != nil {
		return [2]string{}, fmt.Errorf("failed to create QR code writer: %w", err)
	}
	if err := qrc.Save(wThemed); err != nil {
		return [2]string{}, fmt.Errorf("failed to save QR code for `%s`: %w", ssid, err)
	}

	wNormal, err := standard.New(pathNormal, standard.WithBuiltinImageEncoder(standard.PNG_FORMAT))
	if err != nil {
		return [2]string{}, fmt.Errorf("failed to create QR code writer: %w", err)
	}
	if err := qrc.Save(wNormal); err != nil {
		return [2]string{}, fmt.Errorf("failed to save QR code for `%s`: %w", ssid, err)
	}

	return [2]string{pathThemed, pathNormal}, nil
}

func (m *Manager) ToggleWiFi() error {
	enabled, err := m.backend.GetWiFiEnabled()
	if err != nil {
		return fmt.Errorf("failed to get WiFi state: %w", err)
	}

	err = m.backend.SetWiFiEnabled(!enabled)
	if err != nil {
		return fmt.Errorf("failed to toggle WiFi: %w", err)
	}

	return nil
}

func (m *Manager) EnableWiFi() error {
	err := m.backend.SetWiFiEnabled(true)
	if err != nil {
		return fmt.Errorf("failed to enable WiFi: %w", err)
	}

	return nil
}

func (m *Manager) DisableWiFi() error {
	err := m.backend.SetWiFiEnabled(false)
	if err != nil {
		return fmt.Errorf("failed to disable WiFi: %w", err)
	}

	return nil
}

func (m *Manager) ToggleCellular() error {
	enabled, err := m.backend.GetCellularEnabled()
	if err != nil {
		return fmt.Errorf("failed to get cellular state: %w", err)
	}

	err = m.backend.SetCellularEnabled(!enabled)
	if err != nil {
		return fmt.Errorf("failed to toggle cellular: %w", err)
	}

	return nil
}

func (m *Manager) EnableCellular() error {
	err := m.backend.SetCellularEnabled(true)
	if err != nil {
		return fmt.Errorf("failed to enable cellular: %w", err)
	}

	return nil
}

func (m *Manager) DisableCellular() error {
	err := m.backend.SetCellularEnabled(false)
	if err != nil {
		return fmt.Errorf("failed to disable cellular: %w", err)
	}

	return nil
}

func (m *Manager) ConnectWiFi(req ConnectionRequest) error {
	return m.backend.ConnectWiFi(req)
}

func (m *Manager) DisconnectWiFi() error {
	return m.backend.DisconnectWiFi()
}

func (m *Manager) ConfigureHotspot(req HotspotRequest) error {
	backend, ok := m.hotspotBackend()
	if !ok {
		return ErrHotspotNotSupported
	}

	if err := backend.ConfigureHotspot(req); err != nil {
		return err
	}

	if err := m.syncStateFromBackend(); err != nil {
		return err
	}
	m.notifySubscribers()

	return nil
}

func (m *Manager) StartHotspot() error {
	backend, ok := m.hotspotBackend()
	if !ok {
		return ErrHotspotNotSupported
	}

	if err := backend.StartHotspot(); err != nil {
		return err
	}

	if err := m.syncStateFromBackend(); err != nil {
		return err
	}
	m.notifySubscribers()

	return nil
}

func (m *Manager) StopHotspot() error {
	backend, ok := m.hotspotBackend()
	if !ok {
		return ErrHotspotNotSupported
	}

	if err := backend.StopHotspot(); err != nil {
		return err
	}

	if err := m.syncStateFromBackend(); err != nil {
		return err
	}
	m.notifySubscribers()

	return nil
}

func (m *Manager) GetHotspotSecrets() (string, error) {
	backend, ok := m.hotspotBackend()
	if !ok {
		return "", ErrHotspotNotSupported
	}

	return backend.GetHotspotSecrets()
}

func (m *Manager) ForgetWiFiNetwork(ssid string) error {
	return m.backend.ForgetWiFiNetwork(ssid)
}

func (m *Manager) GetWiredConfigs() []WiredConnection {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	configs := make([]WiredConnection, len(m.state.WiredConnections))
	copy(configs, m.state.WiredConnections)
	return configs
}

func (m *Manager) GetWiredNetworkInfoDetailed(uuid string) (*WiredNetworkInfoResponse, error) {
	return m.backend.GetWiredNetworkDetails(uuid)
}

func (m *Manager) ConnectEthernet() error {
	return m.backend.ConnectEthernet()
}

func (m *Manager) DisconnectEthernet() error {
	return m.backend.DisconnectEthernet()
}

func (m *Manager) DisconnectEthernetDevice(device string) error {
	return m.backend.DisconnectEthernetDevice(device)
}

func (m *Manager) GetEthernetDevices() []EthernetDevice {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	devices := make([]EthernetDevice, len(m.state.EthernetDevices))
	copy(devices, m.state.EthernetDevices)
	return devices
}

func (m *Manager) ConnectCellular() error {
	return m.backend.ConnectCellular()
}

func (m *Manager) DisconnectCellular() error {
	return m.backend.DisconnectCellular()
}

func (m *Manager) DisconnectCellularDevice(device string) error {
	return m.backend.DisconnectCellularDevice(device)
}

func (m *Manager) GetCellularDevices() []CellularDevice {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	devices := make([]CellularDevice, len(m.state.CellularDevices))
	copy(devices, m.state.CellularDevices)
	return devices
}

func (m *Manager) activateConnection(uuid string) error {
	return m.backend.ActivateWiredConnection(uuid)
}

func (m *Manager) activateCellularConnection(uuid string) error {
	return m.backend.ActivateCellularConnection(uuid)
}

func (m *Manager) ListVPNProfiles() ([]VPNProfile, error) {
	return m.backend.ListVPNProfiles()
}

func (m *Manager) ListActiveVPN() ([]VPNActive, error) {
	return m.backend.ListActiveVPN()
}

func (m *Manager) ConnectVPN(uuidOrName string, singleActive bool) error {
	return m.backend.ConnectVPN(uuidOrName, singleActive)
}

func (m *Manager) DisconnectVPN(uuidOrName string) error {
	return m.backend.DisconnectVPN(uuidOrName)
}

func (m *Manager) DisconnectAllVPN() error {
	return m.backend.DisconnectAllVPN()
}

func (m *Manager) ClearVPNCredentials(uuidOrName string) error {
	return m.backend.ClearVPNCredentials(uuidOrName)
}

func (m *Manager) ListVPNPlugins() ([]VPNPlugin, error) {
	return m.backend.ListVPNPlugins()
}

func (m *Manager) ImportVPN(filePath string, name string) (*VPNImportResult, error) {
	return m.backend.ImportVPN(filePath, name)
}

func (m *Manager) GetVPNConfig(uuidOrName string) (*VPNConfig, error) {
	return m.backend.GetVPNConfig(uuidOrName)
}

func (m *Manager) UpdateVPNConfig(uuid string, updates map[string]any) error {
	return m.backend.UpdateVPNConfig(uuid, updates)
}

func (m *Manager) DeleteVPN(uuidOrName string) error {
	return m.backend.DeleteVPN(uuidOrName)
}

func (m *Manager) SetVPNCredentials(uuid, username, password string, save bool) error {
	return m.backend.SetVPNCredentials(uuid, username, password, save)
}

func (m *Manager) SetWiFiAutoconnect(ssid string, autoconnect bool) error {
	return m.backend.SetWiFiAutoconnect(ssid, autoconnect)
}

func (m *Manager) GetWiFiDevices() []WiFiDevice {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	devices := make([]WiFiDevice, len(m.state.WiFiDevices))
	copy(devices, m.state.WiFiDevices)
	return devices
}

func (m *Manager) ScanWiFiDevice(device string) error {
	return m.backend.ScanWiFiDevice(device)
}

func (m *Manager) DisconnectWiFiDevice(device string) error {
	return m.backend.DisconnectWiFiDevice(device)
}
