package network

import (
	"encoding/hex"
	"fmt"
	"sort"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

const (
	nmWiFiDeviceCapAP        uint32 = 0x00000040
	nmWiFiDeviceCapFreqValid uint32 = 0x00000100
	nmWiFiDeviceCapFreq2GHz  uint32 = 0x00000200
	nmWiFiDeviceCapFreq5GHz  uint32 = 0x00000400

	dmsHotspotConnectionID = "DankMaterialShell Hotspot"
	dmsHotspotStableID     = "dms-hotspot"
)

var _ HotspotBackend = (*NetworkManagerBackend)(nil)

func (b *NetworkManagerBackend) ConfigureHotspot(req HotspotRequest) error {
	if req.SSID == "" {
		return fmt.Errorf("hotspot SSID cannot be empty")
	}
	if err := validateHotspotPassword(req.Password); err != nil {
		return err
	}
	if err := validateHotspotBandName(req.Band); err != nil {
		return err
	}

	b.stateMutex.RLock()
	hotspotActive := b.state.HotspotEnabled || b.state.HotspotActivating
	b.stateMutex.RUnlock()
	if hotspotActive {
		return fmt.Errorf("stop the hotspot before changing its configuration")
	}

	if req.Device != "" {
		if _, err := b.getAPCapableWiFiDevice(req.Device, req.Band); err != nil {
			return err
		}
	} else if err := b.validateAutoHotspotBand(req.Band); err != nil {
		return err
	}

	settingsMgr, err := b.networkManagerSettings()
	if err != nil {
		return err
	}

	existing, existingSettings, err := b.findDMSHotspotConnection()
	if err != nil {
		return err
	}

	settings := buildHotspotSettings(req, existingSettings)
	if existing != nil {
		if err := existing.Update(settings); err != nil {
			return fmt.Errorf("failed to update hotspot profile: %w", err)
		}
	} else if _, err := settingsMgr.AddConnection(settings); err != nil {
		return fmt.Errorf("failed to create hotspot profile: %w", err)
	}

	if err := b.updateHotspotState(); err != nil {
		return err
	}

	return nil
}

func (b *NetworkManagerBackend) StartHotspot() error {
	conn, settings, err := b.findDMSHotspotConnection()
	if err != nil {
		return err
	}
	if conn == nil {
		return fmt.Errorf("hotspot is not configured")
	}

	devInfo, err := b.getAPCapableWiFiDevice(hotspotDeviceFromSettings(settings), hotspotBandFromSettings(settings))
	if err != nil {
		return err
	}

	deviceName := ""
	if devInfo.device != nil {
		deviceName, _ = devInfo.device.GetPropertyInterface()
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	if _, err := nm.ActivateConnection(conn, devInfo.device, nil); err != nil {
		return fmt.Errorf("failed to start hotspot: %w", err)
	}

	b.stateMutex.Lock()
	b.state.HotspotActivating = true
	b.state.HotspotLastError = ""
	b.hotspotPendingDevice = deviceName
	b.stateMutex.Unlock()

	if err := b.updateHotspotState(); err != nil {
		return err
	}

	return nil
}

func (b *NetworkManagerBackend) StopHotspot() error {
	b.stateMutex.Lock()
	b.state.HotspotActivating = false
	b.state.HotspotLastError = ""
	b.hotspotPendingDevice = ""
	b.stateMutex.Unlock()

	active, err := b.findActiveDMSHotspotConnection()
	if err != nil {
		return err
	}
	if active == nil {
		return nil
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	if err := nm.DeactivateConnection(active); err != nil {
		return fmt.Errorf("failed to stop hotspot: %w", err)
	}

	if err := b.updateHotspotState(); err != nil {
		return err
	}

	return nil
}

func (b *NetworkManagerBackend) GetHotspotSecrets() (string, error) {
	conn, settings, err := b.findDMSHotspotConnection()
	if err != nil {
		return "", err
	}
	if conn == nil {
		return "", fmt.Errorf("hotspot is not configured")
	}
	if !hotspotSecuredFromSettings(settings) {
		return "", nil
	}

	secrets, err := conn.GetSecrets("802-11-wireless-security")
	if err != nil {
		return "", fmt.Errorf("failed to read hotspot password: %w", err)
	}

	if security, ok := secrets["802-11-wireless-security"]; ok {
		if psk, ok := security["psk"].(string); ok {
			return psk, nil
		}
	}

	return "", nil
}

func (b *NetworkManagerBackend) networkManagerSettings() (gonetworkmanager.Settings, error) {
	s := b.settings
	if s == nil {
		var err error
		s, err = gonetworkmanager.NewSettings()
		if err != nil {
			return nil, fmt.Errorf("failed to get settings: %w", err)
		}
		b.settings = s
	}

	settingsMgr, ok := s.(gonetworkmanager.Settings)
	if !ok {
		return nil, fmt.Errorf("invalid NetworkManager settings handle")
	}
	return settingsMgr, nil
}

func buildHotspotSettings(req HotspotRequest, existing gonetworkmanager.ConnectionSettings) gonetworkmanager.ConnectionSettings {
	connection := map[string]any{
		"id":          dmsHotspotConnectionID,
		"type":        "802-11-wireless",
		"autoconnect": false,
		"stable-id":   dmsHotspotStableID,
	}
	if req.Device != "" {
		connection["interface-name"] = req.Device
	}
	if existingConnection, ok := existing["connection"]; ok {
		if uuid, ok := existingConnection["uuid"].(string); ok && uuid != "" {
			connection["uuid"] = uuid
		}
	}

	wifi := map[string]any{
		"mode": "ap",
		"ssid": []byte(req.SSID),
	}
	if req.Band != "" {
		wifi["band"] = req.Band
	}

	settings := gonetworkmanager.ConnectionSettings{
		"connection":      connection,
		"802-11-wireless": wifi,
		"ipv4":            {"method": "shared"},
		"ipv6":            {"method": "ignore"},
	}

	if req.Password != "" {
		wifi["security"] = "802-11-wireless-security"
		settings["802-11-wireless-security"] = map[string]any{
			"key-mgmt":  "wpa-psk",
			"psk":       req.Password,
			"psk-flags": uint32(0),
		}
	}

	return settings
}

func (b *NetworkManagerBackend) findDMSHotspotConnection() (gonetworkmanager.Connection, gonetworkmanager.ConnectionSettings, error) {
	settingsMgr, err := b.networkManagerSettings()
	if err != nil {
		return nil, nil, err
	}

	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return nil, nil, fmt.Errorf("failed to list connections: %w", err)
	}

	for _, conn := range connections {
		connSettings, err := conn.GetSettings()
		if err != nil {
			continue
		}
		if isDMSHotspotConnection(connSettings) {
			return conn, connSettings, nil
		}
	}

	return nil, nil, nil
}

func (b *NetworkManagerBackend) findActiveDMSHotspotConnection() (gonetworkmanager.ActiveConnection, error) {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	activeConns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to get active connections: %w", err)
	}

	for _, active := range activeConns {
		connType, err := active.GetPropertyType()
		if err != nil || connType != "802-11-wireless" {
			continue
		}

		conn, err := active.GetPropertyConnection()
		if err != nil || conn == nil {
			continue
		}

		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}
		if isDMSHotspotConnection(settings) {
			return active, nil
		}
	}

	return nil, nil
}

func isDMSHotspotConnection(settings gonetworkmanager.ConnectionSettings) bool {
	connMeta, _, ok := wifiConnectionSettings(settings)
	if !ok || !isAPModeWiFiConnection(settings) {
		return false
	}

	stableID, _ := connMeta["stable-id"].(string)
	return stableID == dmsHotspotStableID
}

func wifiConnectionSettings(settings gonetworkmanager.ConnectionSettings) (map[string]any, map[string]any, bool) {
	connMeta, ok := settings["connection"]
	if !ok {
		return nil, nil, false
	}
	connType, _ := connMeta["type"].(string)
	if connType != "802-11-wireless" {
		return nil, nil, false
	}

	wifiSettings, ok := settings["802-11-wireless"]
	if !ok {
		return nil, nil, false
	}

	return connMeta, wifiSettings, true
}

func isAPModeWiFiConnection(settings gonetworkmanager.ConnectionSettings) bool {
	_, wifiSettings, ok := wifiConnectionSettings(settings)
	if !ok {
		return false
	}
	mode, _ := wifiSettings["mode"].(string)
	return mode == "ap"
}

func isClientWiFiConnection(settings gonetworkmanager.ConnectionSettings) bool {
	_, _, ok := wifiConnectionSettings(settings)
	return ok && !isAPModeWiFiConnection(settings)
}

// activeDMSHotspotDevicePaths returns only the devices hosting the DMS-owned
// hotspot, unlike activeAPModeWiFiDevicePaths which matches any AP-mode
// connection (as the client-state isolation requires).
func (b *NetworkManagerBackend) activeDMSHotspotDevicePaths() map[string]bool {
	paths := make(map[string]bool)
	active, err := b.findActiveDMSHotspotConnection()
	if err != nil || active == nil {
		return paths
	}

	devices, err := active.GetPropertyDevices()
	if err != nil {
		return paths
	}
	for _, dev := range devices {
		if dev != nil {
			paths[string(dev.GetPath())] = true
		}
	}

	return paths
}

func (b *NetworkManagerBackend) activeAPModeWiFiDevicePaths() map[string]bool {
	paths := make(map[string]bool)
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	activeConns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return paths
	}

	for _, active := range activeConns {
		connType, err := active.GetPropertyType()
		if err != nil || connType != "802-11-wireless" {
			continue
		}

		conn, err := active.GetPropertyConnection()
		if err != nil || conn == nil {
			continue
		}

		settings, err := conn.GetSettings()
		if err != nil || !isAPModeWiFiConnection(settings) {
			continue
		}

		devices, err := active.GetPropertyDevices()
		if err != nil {
			continue
		}
		for _, dev := range devices {
			if dev != nil {
				paths[string(dev.GetPath())] = true
			}
		}
	}

	return paths
}

func (b *NetworkManagerBackend) getAPCapableWiFiDevice(deviceName string, band string) (*wifiDeviceInfo, error) {
	if err := validateHotspotBandName(band); err != nil {
		return nil, err
	}

	if deviceName != "" {
		devInfo, ok := b.wifiDeviceByIface(deviceName)
		if !ok {
			return nil, fmt.Errorf("WiFi device not found: %s", deviceName)
		}
		if err := validateAPCapableWiFiDevice(devInfo, deviceName, band); err != nil {
			return nil, err
		}
		return devInfo, nil
	}

	wifiDevices := b.wifiDevicesSnapshot()
	deviceNames := make([]string, 0, len(wifiDevices))
	for name := range wifiDevices {
		deviceNames = append(deviceNames, name)
	}
	sort.Strings(deviceNames)

	dmsHotspotDevicePaths := b.activeDMSHotspotDevicePaths()

	// Rank 0: already hosting the DMS hotspot (keep it where it is). Radios
	// hosting foreign AP-mode connections must not get this preference and
	// rank as busy through their Activated state instead.
	// Rank 1: genuinely disconnected, so starting the AP disturbs nothing.
	// Rank 2: client activation in progress; grabbing it kills the attempt.
	// Rank 3: carrying an active connection; only used as a last resort.
	// Rank 4: unavailable, failed, or unknown; activation is unlikely to succeed.
	rankDevice := func(devInfo *wifiDeviceInfo) int {
		if len(dmsHotspotDevicePaths) > 0 && dmsHotspotDevicePaths[string(devInfo.device.GetPath())] {
			return 0
		}
		state, err := devInfo.device.GetPropertyState()
		if err != nil {
			return 4
		}
		switch {
		case state == gonetworkmanager.NmDeviceStateDisconnected:
			return 1
		case state == gonetworkmanager.NmDeviceStateActivated:
			return 3
		case state > gonetworkmanager.NmDeviceStateDisconnected && state < gonetworkmanager.NmDeviceStateActivated:
			return 2
		default:
			return 4
		}
	}

	var lastBandErr error
	var best *wifiDeviceInfo
	bestRank := 5
	for _, name := range deviceNames {
		devInfo := wifiDevices[name]
		ok, err := isAPCapableWiFiDevice(devInfo)
		if err != nil || !ok {
			continue
		}
		if err := validateHotspotBand(devInfo, band); err != nil {
			lastBandErr = err
			continue
		}
		if rank := rankDevice(devInfo); rank < bestRank {
			best = devInfo
			bestRank = rank
		}
	}

	if best != nil {
		return best, nil
	}
	if lastBandErr != nil {
		return nil, lastBandErr
	}
	return nil, fmt.Errorf("no hotspot-capable WiFi device available")
}

func validateAPCapableWiFiDevice(devInfo *wifiDeviceInfo, deviceName string, band string) error {
	ok, err := isAPCapableWiFiDevice(devInfo)
	if err != nil {
		return err
	}
	if !ok {
		return fmt.Errorf("WiFi device is not hotspot-capable: %s", deviceName)
	}
	return validateHotspotBand(devInfo, band)
}

func isAPCapableWiFiDevice(devInfo *wifiDeviceInfo) (bool, error) {
	if devInfo == nil || devInfo.device == nil || devInfo.wireless == nil {
		return false, nil
	}

	managed, err := devInfo.device.GetPropertyManaged()
	if err != nil {
		return false, fmt.Errorf("failed to get WiFi device managed state: %w", err)
	}
	if !managed {
		return false, nil
	}

	caps, err := devInfo.wireless.GetPropertyWirelessCapabilities()
	if err != nil {
		return false, fmt.Errorf("failed to get WiFi device capabilities: %w", err)
	}

	return caps&nmWiFiDeviceCapAP != 0, nil
}

// Mirrors NetworkManager's nm_utils_wpa_psk_valid: byte length, not rune count.
func validateHotspotPassword(password string) error {
	if password == "" {
		return nil
	}
	if len(password) == 64 {
		if _, err := hex.DecodeString(password); err == nil {
			return nil
		}
	}
	if len(password) < 8 || len(password) > 63 {
		return fmt.Errorf("hotspot password must be 8 to 63 characters, or a 64-digit hex key")
	}
	return nil
}

func validateHotspotBandName(band string) error {
	if band != "" && band != "bg" && band != "a" {
		return fmt.Errorf("unsupported hotspot band: %s", band)
	}
	return nil
}

func validateHotspotBand(devInfo *wifiDeviceInfo, band string) error {
	if band == "" || devInfo == nil || devInfo.wireless == nil {
		return nil
	}

	caps, err := devInfo.wireless.GetPropertyWirelessCapabilities()
	if err != nil {
		return fmt.Errorf("failed to get WiFi device capabilities: %w", err)
	}
	if caps&nmWiFiDeviceCapFreqValid == 0 {
		return nil
	}

	switch band {
	case "bg":
		if caps&nmWiFiDeviceCapFreq2GHz == 0 {
			return fmt.Errorf("WiFi device does not support 2.4GHz hotspot band")
		}
	case "a":
		if caps&nmWiFiDeviceCapFreq5GHz == 0 {
			return fmt.Errorf("WiFi device does not support 5GHz hotspot band")
		}
	}

	return nil
}

func (b *NetworkManagerBackend) validateAutoHotspotBand(band string) error {
	if band == "" {
		return nil
	}

	var lastBandErr error
	foundAPCapableDevice := false
	for _, devInfo := range b.wifiDevicesSnapshot() {
		apCapable, err := isAPCapableWiFiDevice(devInfo)
		if err != nil {
			// Capability could not be determined, so defer to NetworkManager.
			return nil
		}
		if !apCapable {
			continue
		}

		foundAPCapableDevice = true
		if err := validateHotspotBand(devInfo, band); err == nil {
			return nil
		} else {
			lastBandErr = err
		}
	}

	if foundAPCapableDevice && lastBandErr != nil {
		return lastBandErr
	}
	return nil
}

func hotspotSSIDFromSettings(settings gonetworkmanager.ConnectionSettings) string {
	wifiSettings, ok := settings["802-11-wireless"]
	if !ok {
		return ""
	}
	ssidBytes, ok := wifiSettings["ssid"].([]byte)
	if !ok {
		return ""
	}
	return string(ssidBytes)
}

func hotspotDeviceFromSettings(settings gonetworkmanager.ConnectionSettings) string {
	connMeta, ok := settings["connection"]
	if !ok {
		return ""
	}
	device, _ := connMeta["interface-name"].(string)
	return device
}

func hotspotBandFromSettings(settings gonetworkmanager.ConnectionSettings) string {
	wifiSettings, ok := settings["802-11-wireless"]
	if !ok {
		return ""
	}
	band, _ := wifiSettings["band"].(string)
	return band
}

func (b *NetworkManagerBackend) updateHotspotState() error {
	available := false
	for _, devInfo := range b.wifiDevicesSnapshot() {
		ok, err := isAPCapableWiFiDevice(devInfo)
		if err != nil {
			continue
		}
		if ok {
			available = true
			break
		}
	}

	_, settings, err := b.findDMSHotspotConnection()
	if err != nil {
		return err
	}

	configured := settings != nil
	enabled := false
	activating := false
	if configured {
		active, err := b.findActiveDMSHotspotConnection()
		if err != nil {
			return err
		}
		if active != nil {
			switch state, _ := active.GetPropertyState(); state {
			case gonetworkmanager.NmActiveConnectionStateActivated:
				enabled = true
			case gonetworkmanager.NmActiveConnectionStateActivating:
				activating = true
			}
		}
	}

	b.stateMutex.RLock()
	wasStarting := b.state.HotspotActivating
	pendingDevice := b.hotspotPendingDevice
	b.stateMutex.RUnlock()

	failureCode := ""
	if wasStarting && !enabled && !activating {
		if devInfo, ok := b.wifiDeviceByIface(pendingDevice); ok && devInfo.device != nil && b.dbusConn != nil {
			reason := b.getDeviceStateReason(devInfo.device)
			// A fresh activation briefly reports no reason; don't misread it as failure.
			if reason == gonetworkmanager.NmDeviceStateReasonNewActivation || reason == gonetworkmanager.NmDeviceStateReasonNone {
				activating = true
			} else {
				failureCode = classifyHotspotStateReason(reason)
				log.Warnf("[updateHotspotState] Hotspot activation failed: device=%s, reason=%d (%s)", pendingDevice, reason, failureCode)
			}
		} else {
			failureCode = errdefs.ErrHotspotFailed
			log.Warnf("[updateHotspotState] Hotspot activation failed: device %q no longer available", pendingDevice)
		}
	}

	b.stateMutex.Lock()
	b.state.HotspotAvailable = available
	b.state.HotspotConfigured = configured
	b.state.HotspotEnabled = enabled
	b.state.HotspotSSID = hotspotSSIDFromSettings(settings)
	b.state.HotspotDevice = hotspotDeviceFromSettings(settings)
	b.state.HotspotBand = hotspotBandFromSettings(settings)
	b.state.HotspotSecured = hotspotSecuredFromSettings(settings)
	if wasStarting {
		switch {
		case enabled:
			b.state.HotspotActivating = false
			b.state.HotspotLastError = ""
			b.hotspotPendingDevice = ""
		case failureCode != "":
			b.state.HotspotActivating = false
			b.state.HotspotLastError = failureCode
			b.hotspotPendingDevice = ""
		}
	} else {
		b.state.HotspotActivating = activating
	}
	b.stateMutex.Unlock()

	return nil
}

func hotspotSecuredFromSettings(settings gonetworkmanager.ConnectionSettings) bool {
	if settings == nil {
		return false
	}
	_, ok := settings["802-11-wireless-security"]
	return ok
}

// classifyHotspotStateReason uses the gonetworkmanager reason constants; the
// same-named package-local aliases in backend_networkmanager.go carry wrong
// values and must not be used here.
func classifyHotspotStateReason(reason uint32) string {
	switch reason {
	case gonetworkmanager.NmDeviceStateReasonIpConfigUnavailable,
		gonetworkmanager.NmDeviceStateReasonDhcpStartFailed,
		gonetworkmanager.NmDeviceStateReasonDhcpError,
		gonetworkmanager.NmDeviceStateReasonDhcpFailed,
		gonetworkmanager.NmDeviceStateReasonSharedStartFailed,
		gonetworkmanager.NmDeviceStateReasonSharedFailed:
		return errdefs.ErrHotspotIPConfigFailed
	case gonetworkmanager.NmDeviceStateReasonSupplicantDisconnect,
		gonetworkmanager.NmDeviceStateReasonSupplicantConfigFailed,
		gonetworkmanager.NmDeviceStateReasonSupplicantFailed,
		gonetworkmanager.NmDeviceStateReasonSupplicantTimeout:
		return errdefs.ErrHotspotSupplicantFailed
	default:
		return errdefs.ErrHotspotFailed
	}
}
