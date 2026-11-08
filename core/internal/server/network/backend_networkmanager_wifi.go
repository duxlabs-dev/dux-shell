package network

import (
	"bytes"
	"errors"
	"fmt"
	"maps"
	"os/user"
	"sort"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

func (b *NetworkManagerBackend) GetWiFiEnabled() (bool, error) {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	return nm.GetPropertyWirelessEnabled()
}

func (b *NetworkManagerBackend) SetWiFiEnabled(enabled bool) error {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	err := nm.SetPropertyWirelessEnabled(enabled)
	if err != nil {
		return fmt.Errorf("failed to set WiFi enabled: %w", err)
	}

	b.stateMutex.Lock()
	b.state.WiFiEnabled = enabled
	b.stateMutex.Unlock()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

func (b *NetworkManagerBackend) ScanWiFi() error {
	b.stateMutex.RLock()
	enabled := b.state.WiFiEnabled
	b.stateMutex.RUnlock()

	if !enabled {
		return fmt.Errorf("WiFi is disabled")
	}

	changed, err := b.refreshWiFiDevices()
	if err != nil {
		return err
	}
	if changed {
		b.updateWiFiState()
		b.updateAllWiFiDevices()
	}
	w, err := b.ensureWiFiDevice()
	if err != nil {
		return err
	}

	err = w.RequestScan()
	if err != nil {
		return fmt.Errorf("scan request failed: %w", err)
	}

	_, err = b.updateWiFiNetworks()
	return err
}

func (b *NetworkManagerBackend) GetWiFiNetworkDetails(ssid string) (*NetworkInfoResponse, error) {
	w, err := b.ensureWiFiDevice()
	if err != nil {
		return nil, err
	}
	apPaths, err := w.GetAccessPoints()
	if err != nil {
		return nil, fmt.Errorf("failed to get access points: %w", err)
	}

	s := b.settings
	if s == nil {
		s, err = gonetworkmanager.NewSettings()
		if err != nil {
			return nil, fmt.Errorf("failed to get settings: %w", err)
		}
		b.settings = s
	}

	settingsMgr := s.(gonetworkmanager.Settings)
	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to get connections: %w", err)
	}

	savedSSIDs := make(map[string]bool)
	autoconnectMap := make(map[string]bool)
	for _, conn := range connections {
		connSettings, err := conn.GetSettings()
		if err != nil || !isClientWiFiConnection(connSettings) {
			continue
		}

		connMeta, wifiSettings, _ := wifiConnectionSettings(connSettings)
		ssidBytes, ok := wifiSettings["ssid"].([]byte)
		if !ok {
			continue
		}

		savedSSID := string(ssidBytes)
		savedSSIDs[savedSSID] = true
		autoconnect := true
		if ac, ok := connMeta["autoconnect"].(bool); ok {
			autoconnect = ac
		}
		autoconnectMap[savedSSID] = autoconnect
	}

	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	currentBSSID := b.state.WiFiBSSID
	b.stateMutex.RUnlock()

	var bands []WiFiNetwork

	for _, ap := range apPaths {
		apSSID, err := ap.GetPropertySSID()
		if err != nil || apSSID != ssid {
			continue
		}

		mode, _ := ap.GetPropertyMode()
		if mode == gonetworkmanager.Nm80211ModeAp {
			continue
		}

		strength, _ := ap.GetPropertyStrength()
		flags, _ := ap.GetPropertyFlags()
		wpaFlags, _ := ap.GetPropertyWPAFlags()
		rsnFlags, _ := ap.GetPropertyRSNFlags()
		freq, _ := ap.GetPropertyFrequency()
		maxBitrate, _ := ap.GetPropertyMaxBitrate()
		bssid, _ := ap.GetPropertyHWAddress()

		secured := apNeedsCredentials(flags, wpaFlags, rsnFlags)

		enterprise := (rsnFlags&uint32(gonetworkmanager.Nm80211APSecKeyMgmt8021X) != 0) ||
			(wpaFlags&uint32(gonetworkmanager.Nm80211APSecKeyMgmt8021X) != 0)

		var modeStr string
		switch mode {
		case gonetworkmanager.Nm80211ModeAdhoc:
			modeStr = "adhoc"
		case gonetworkmanager.Nm80211ModeInfra:
			modeStr = "infrastructure"
		case gonetworkmanager.Nm80211ModeAp:
			modeStr = "ap"
		default:
			modeStr = "unknown"
		}

		channel := frequencyToChannel(freq)

		isConnected := ssid == currentSSID && bssid == currentBSSID
		rate := maxBitrate / 1000
		if isConnected {
			if devBitrate, err := w.GetPropertyBitrate(); err == nil && devBitrate > 0 {
				rate = devBitrate / 1000
			}
		}

		network := WiFiNetwork{
			SSID:        ssid,
			BSSID:       bssid,
			Signal:      strength,
			Secured:     secured,
			Enterprise:  enterprise,
			Connected:   isConnected,
			Saved:       savedSSIDs[ssid],
			Autoconnect: autoconnectMap[ssid],
			Frequency:   freq,
			Mode:        modeStr,
			Rate:        rate,
			Channel:     channel,
		}

		bands = append(bands, network)
	}

	if len(bands) == 0 {
		return nil, fmt.Errorf("network not found: %s", ssid)
	}

	sort.Slice(bands, func(i, j int) bool {
		if bands[i].Connected && !bands[j].Connected {
			return true
		}
		if !bands[i].Connected && bands[j].Connected {
			return false
		}
		return bands[i].Signal > bands[j].Signal
	})

	return &NetworkInfoResponse{
		SSID:  ssid,
		Bands: bands,
	}, nil
}

func (b *NetworkManagerBackend) GetWiFiQRCodeContent(ssid string) (string, error) {
	if conn, settings := b.activeHotspotProfile(ssid); conn != nil {
		return qrContentForConnection(conn, settings, ssid)
	}

	conn, err := b.findConnection(ssid)
	if err != nil {
		return "", fmt.Errorf("no saved connection for `%s`: %w", ssid, err)
	}
	settings, err := conn.GetSettings()
	if err != nil {
		return "", fmt.Errorf("failed to get settings for `%s`: %w", ssid, err)
	}
	return qrContentForConnection(conn, settings, ssid)
}

// activeHotspotProfile returns the running DMS hotspot's profile when its SSID
// matches; findConnection skips AP-mode profiles by design.
func (b *NetworkManagerBackend) activeHotspotProfile(ssid string) (gonetworkmanager.Connection, gonetworkmanager.ConnectionSettings) {
	active, conn, settings, err := b.findActiveDMSHotspot()
	if err != nil || active == nil {
		return nil, nil
	}
	_, wifiSettings, _ := wifiConnectionSettings(settings)
	if ssidBytes, ok := wifiSettings["ssid"].([]byte); !ok || string(ssidBytes) != ssid {
		return nil, nil
	}
	return conn, settings
}

func qrContentForConnection(conn gonetworkmanager.Connection, connSettings gonetworkmanager.ConnectionSettings, ssid string) (string, error) {
	secSettings, ok := connSettings["802-11-wireless-security"]
	if !ok {
		return "", fmt.Errorf("network `%s` has no security settings", ssid)
	}

	keyMgmt, ok := secSettings["key-mgmt"].(string)
	if !ok {
		return "", fmt.Errorf("failed to identify security type of network `%s`", ssid)
	}

	switch keyMgmt {
	case "none":
		return "", fmt.Errorf("QR code generation only supports WPA-PSK connections, `%s` is open or WEP", ssid)
	case "ieee8021x":
		return "", fmt.Errorf("QR code generation only supports WPA-PSK connections, `%s` is enterprise", ssid)
	case "wpa-psk", "sae", "wpa-psk-sae":
	default:
		return "", fmt.Errorf("QR code generation only supports WPA-PSK connections, `%s` uses %s", ssid, keyMgmt)
	}

	var psk string

	secrets, err := conn.GetSecrets("802-11-wireless-security")
	if err != nil {
		log.Debugf("[GetWiFiQRCodeContent] conn.GetSecrets failed: %v, falling back to secret service", err)
	} else if secSecrets, ok := secrets["802-11-wireless-security"]; ok {
		if s, ok := secSecrets["psk"].(string); ok {
			psk = s
		}
	}

	if psk == "" {
		uuid := ""
		if connMeta, ok := connSettings["connection"]; ok {
			if u, ok := connMeta["uuid"].(string); ok {
				uuid = u
			}
		}
		if uuid != "" {
			sess, err := openSecretService()
			if err == nil {
				psk = sess.lookup(uuid, "802-11-wireless-security", "psk")
				sess.close()
			}
		}
	}

	if psk == "" {
		return "", fmt.Errorf("failed to retrieve password for `%s`", ssid)
	}

	return FormatWiFiQRString("WPA", ssid, psk), nil
}

func (b *NetworkManagerBackend) ConnectWiFi(req ConnectionRequest) error {
	if req.SaveOnly {
		return b.saveWiFiProfile(req)
	}

	devInfo, err := b.getWifiDeviceForConnection(req.Device)
	if err != nil {
		return err
	}

	b.stateMutex.RLock()
	alreadyConnected := b.state.WiFiConnected && b.state.WiFiSSID == req.SSID
	b.stateMutex.RUnlock()

	if alreadyConnected && !req.Interactive && req.Device == "" {
		return nil
	}

	b.stateMutex.Lock()
	b.state.IsConnecting = true
	b.state.ConnectingSSID = req.SSID
	b.state.ConnectingDevice = req.Device
	b.state.ConnectingPreExisting = false
	b.state.LastError = ""
	b.stateMutex.Unlock()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)

	existingConn, err := b.findConnection(req.SSID)
	if err == nil && existingConn != nil {
		if req.Password != "" || req.Enterprise != nil {
			if err := updateConnectionCredentials(b, existingConn, req); err != nil {
				if req.Enterprise != nil {
					b.failConnecting(err.Error())
					return err
				}
				log.Warnf("[ConnectWiFi] Failed to update credentials on existing profile: %v", err)
			}
		}
		b.stateMutex.Lock()
		b.state.ConnectingPreExisting = true
		b.stateMutex.Unlock()
		_, err := nm.ActivateConnection(existingConn, devInfo.device, nil)
		if err != nil {
			log.Warnf("[ConnectWiFi] Failed to activate existing connection: %v", err)
			b.failConnecting(fmt.Sprintf("failed to activate connection: %v", err))
			return fmt.Errorf("failed to activate connection: %w", err)
		}

		return nil
	}

	if err := b.createAndConnectWiFiOnDevice(req, devInfo); err != nil {
		log.Warnf("[ConnectWiFi] Failed to create and connect: %v", err)
		b.failConnecting(err.Error())
		return err
	}

	return nil
}

func (b *NetworkManagerBackend) failConnecting(msg string) {
	b.stateMutex.Lock()
	b.state.IsConnecting = false
	b.state.ConnectingSSID = ""
	b.state.ConnectingDevice = ""
	b.state.LastError = msg
	b.stateMutex.Unlock()
	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *NetworkManagerBackend) DisconnectWiFi() error {
	dev, _ := b.wifiDeviceForState()
	if dev == nil {
		return fmt.Errorf("no WiFi device available")
	}

	err := dev.Disconnect()
	if err != nil {
		return fmt.Errorf("failed to disconnect: %w", err)
	}

	b.updateWiFiState()
	b.updatePrimaryConnection()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

func (b *NetworkManagerBackend) abortInFlightConnection(ssid string) {
	b.stateMutex.Lock()
	if !b.state.IsConnecting || b.state.ConnectingSSID != ssid {
		b.stateMutex.Unlock()
		return
	}
	b.state.IsConnecting = false
	b.state.ConnectingSSID = ""
	b.state.LastError = ""
	b.stateMutex.Unlock()

	b.clearCachedWiFiSecretBySSID(ssid)

	if err := b.DisconnectWiFi(); err != nil {
		log.Warnf("[abortInFlightConnection] failed to abort connection to %s: %v", ssid, err)
	}
}

func (b *NetworkManagerBackend) ForgetWiFiNetwork(ssid string) error {
	conn, err := b.findConnection(ssid)
	if err != nil {
		return fmt.Errorf("connection not found: %w", err)
	}

	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	isConnected := b.state.WiFiConnected
	b.stateMutex.RUnlock()

	err = conn.Delete()
	if err != nil {
		return fmt.Errorf("failed to delete connection: %w", err)
	}

	if isConnected && currentSSID == ssid {
		b.stateMutex.Lock()
		b.state.WiFiConnected = false
		b.state.WiFiSSID = ""
		b.state.WiFiBSSID = ""
		b.state.WiFiSignal = 0
		b.state.WiFiIP = ""
		b.state.NetworkStatus = StatusDisconnected
		b.stateMutex.Unlock()
	}

	b.updateWiFiNetworks()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

func apNeedsCredentials(flags, wpaFlags, rsnFlags uint32) bool {
	const (
		keyMgmtOwe        = uint32(gonetworkmanager.Nm80211APSecKeyMgmtOWE) | uint32(gonetworkmanager.Nm80211APSecKeyMgmtOWETM)
		keyMgmtCredential = uint32(gonetworkmanager.Nm80211APSecKeyMgmtPSK) | uint32(gonetworkmanager.Nm80211APSecKeyMgmtSAE) | uint32(gonetworkmanager.Nm80211APSecKeyMgmt8021X)
	)

	keyMgmt := wpaFlags | rsnFlags
	if keyMgmt&keyMgmtOwe != 0 && keyMgmt&keyMgmtCredential == 0 {
		return false
	}
	return flags&uint32(gonetworkmanager.Nm80211APFlagsPrivacy) != 0 ||
		wpaFlags != uint32(gonetworkmanager.Nm80211APSecNone) ||
		rsnFlags != uint32(gonetworkmanager.Nm80211APSecNone)
}

func getSavedWiFiProfiles(connections []gonetworkmanager.Connection) map[string]savedWiFiProfile {
	profiles := make(map[string]savedWiFiProfile)

	for _, conn := range connections {
		connSettings, err := conn.GetSettings()
		if err != nil || !isClientWiFiConnection(connSettings) {
			continue
		}

		connMeta, wifiSettings, _ := wifiConnectionSettings(connSettings)

		ssidBytes, ok := wifiSettings["ssid"].([]byte)
		if !ok || len(ssidBytes) == 0 {
			continue
		}

		ssid := string(ssidBytes)
		profile := savedWiFiProfile{
			Autoconnect: true,
			Mode:        "infrastructure",
		}

		if ac, ok := connMeta["autoconnect"].(bool); ok {
			profile.Autoconnect = ac
		}
		if hidden, ok := wifiSettings["hidden"].(bool); ok {
			profile.Hidden = hidden
		}
		if mode, ok := wifiSettings["mode"].(string); ok && mode != "" {
			profile.Mode = mode
		}
		if sec, ok := connSettings["802-11-wireless-security"]; ok {
			profile.Secured = sec["key-mgmt"] != "owe"
		}
		if _, ok := connSettings["802-1x"]; ok {
			profile.Enterprise = true
			profile.Secured = true
		}

		if existing, ok := profiles[ssid]; ok {
			profile.Autoconnect = profile.Autoconnect || existing.Autoconnect
			profile.Hidden = profile.Hidden || existing.Hidden
			profile.Secured = profile.Secured || existing.Secured
			profile.Enterprise = profile.Enterprise || existing.Enterprise
			if profile.Mode == "" {
				profile.Mode = existing.Mode
			}
		}

		profiles[ssid] = profile
	}

	return profiles
}

func (b *NetworkManagerBackend) IsConnectingTo(ssid string) bool {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()
	return b.state.IsConnecting && b.state.ConnectingSSID == ssid
}

func (b *NetworkManagerBackend) updateWiFiNetworks() ([]WiFiNetwork, error) {
	w, err := b.ensureWiFiDevice()
	if err != nil {
		return nil, err
	}
	apPaths, err := w.GetAccessPoints()
	if err != nil {
		return nil, fmt.Errorf("failed to get access points: %w", err)
	}

	s := b.settings
	if s == nil {
		s, err = gonetworkmanager.NewSettings()
		if err != nil {
			return nil, fmt.Errorf("failed to get settings: %w", err)
		}
		b.settings = s
	}

	settingsMgr := s.(gonetworkmanager.Settings)
	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to get connections: %w", err)
	}

	savedProfiles := getSavedWiFiProfiles(connections)

	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	wifiConnected := b.state.WiFiConnected
	wifiSignal := b.state.WiFiSignal
	wifiBSSID := b.state.WiFiBSSID
	b.stateMutex.RUnlock()

	seenSSIDs := make(map[string]int)
	networks := make([]WiFiNetwork, 0, len(apPaths)+1)

	for _, ap := range apPaths {
		ssid, err := ap.GetPropertySSID()
		if err != nil || ssid == "" {
			continue
		}
		mode, _ := ap.GetPropertyMode()
		if mode == gonetworkmanager.Nm80211ModeAp {
			continue
		}

		if existingIndex, exists := seenSSIDs[ssid]; exists {
			existing := &networks[existingIndex]
			strength, _ := ap.GetPropertyStrength()
			if strength > existing.Signal {
				existing.Signal = strength
				freq, _ := ap.GetPropertyFrequency()
				existing.Frequency = freq
				bssid, _ := ap.GetPropertyHWAddress()
				existing.BSSID = bssid
			}
			continue
		}

		strength, _ := ap.GetPropertyStrength()
		flags, _ := ap.GetPropertyFlags()
		wpaFlags, _ := ap.GetPropertyWPAFlags()
		rsnFlags, _ := ap.GetPropertyRSNFlags()
		freq, _ := ap.GetPropertyFrequency()
		maxBitrate, _ := ap.GetPropertyMaxBitrate()
		bssid, _ := ap.GetPropertyHWAddress()

		secured := apNeedsCredentials(flags, wpaFlags, rsnFlags)

		enterprise := (rsnFlags&uint32(gonetworkmanager.Nm80211APSecKeyMgmt8021X) != 0) ||
			(wpaFlags&uint32(gonetworkmanager.Nm80211APSecKeyMgmt8021X) != 0)

		var modeStr string
		switch mode {
		case gonetworkmanager.Nm80211ModeAdhoc:
			modeStr = "adhoc"
		case gonetworkmanager.Nm80211ModeInfra:
			modeStr = "infrastructure"
		case gonetworkmanager.Nm80211ModeAp:
			modeStr = "ap"
		default:
			modeStr = "unknown"
		}

		channel := frequencyToChannel(freq)

		isConnected := ssid == currentSSID
		rate := maxBitrate / 1000
		if isConnected {
			if devBitrate, err := w.GetPropertyBitrate(); err == nil && devBitrate > 0 {
				rate = devBitrate / 1000
			}
		}

		profile, saved := savedProfiles[ssid]
		network := WiFiNetwork{
			SSID:        ssid,
			BSSID:       bssid,
			Signal:      strength,
			Secured:     secured,
			Enterprise:  enterprise,
			Connected:   isConnected,
			Saved:       saved,
			Autoconnect: profile.Autoconnect,
			Hidden:      profile.Hidden,
			Frequency:   freq,
			Mode:        modeStr,
			Rate:        rate,
			Channel:     channel,
		}

		networks = append(networks, network)
		seenSSIDs[ssid] = len(networks) - 1
	}

	if wifiConnected && currentSSID != "" {
		if _, exists := seenSSIDs[currentSSID]; !exists {
			profile, saved := savedProfiles[currentSSID]
			hiddenNetwork := WiFiNetwork{
				SSID:        currentSSID,
				BSSID:       wifiBSSID,
				Signal:      wifiSignal,
				Secured:     true,
				Connected:   true,
				Saved:       saved,
				Autoconnect: profile.Autoconnect,
				Hidden:      true,
				Mode:        "infrastructure",
			}
			networks = append(networks, hiddenNetwork)
			seenSSIDs[currentSSID] = len(networks) - 1
		}
	}

	visibleNetworks := wiFiNetworksBySSID(networks, true)
	savedNetworks := savedWiFiNetworksFromProfiles(savedProfiles, visibleNetworks, currentSSID, wifiConnected)

	sortWiFiNetworks(networks)

	b.stateMutex.Lock()
	b.state.WiFiNetworks = networks
	b.state.SavedWiFiNetworks = savedNetworks
	b.stateMutex.Unlock()

	return networks, nil
}

func (b *NetworkManagerBackend) updateSavedWiFiNetworks() error {
	s := b.settings
	if s == nil {
		var err error
		s, err = gonetworkmanager.NewSettings()
		if err != nil {
			return fmt.Errorf("failed to get settings: %w", err)
		}
		b.settings = s
	}

	settingsMgr := s.(gonetworkmanager.Settings)
	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return fmt.Errorf("failed to get connections: %w", err)
	}

	savedProfiles := getSavedWiFiProfiles(connections)

	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	wifiConnected := b.state.WiFiConnected
	wifiNetworks := append([]WiFiNetwork(nil), b.state.WiFiNetworks...)
	b.stateMutex.RUnlock()

	wifiNetworks, savedNetworks := refreshSavedWiFiState(wifiNetworks, savedProfiles, currentSSID, wifiConnected)

	b.stateMutex.Lock()
	b.state.WiFiNetworks = wifiNetworks
	b.state.SavedWiFiNetworks = savedNetworks
	b.stateMutex.Unlock()

	return nil
}

func (b *NetworkManagerBackend) findConnection(ssid string) (gonetworkmanager.Connection, error) {
	s := b.settings
	if s == nil {
		var err error
		s, err = gonetworkmanager.NewSettings()
		if err != nil {
			return nil, err
		}
		b.settings = s
	}

	settings := s.(gonetworkmanager.Settings)
	connections, err := settings.ListConnections()
	if err != nil {
		return nil, err
	}

	ssidBytes := []byte(ssid)
	for _, conn := range connections {
		connSettings, err := conn.GetSettings()
		if err != nil || !isClientWiFiConnection(connSettings) {
			continue
		}

		_, wifiSettings, _ := wifiConnectionSettings(connSettings)
		if candidateSSID, ok := wifiSettings["ssid"].([]byte); ok {
			if bytes.Equal(candidateSSID, ssidBytes) {
				return conn, nil
			}
			log.Debugf("[findConnection] SSID mismatch: stored=%q, request=%q", string(candidateSSID), ssid)
		}
	}

	return nil, fmt.Errorf("connection not found")
}

func (b *NetworkManagerBackend) createAndConnectWiFiOnDevice(req ConnectionRequest, devInfo *wifiDeviceInfo) error {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	dev := devInfo.device

	var targetAP gonetworkmanager.AccessPoint
	var ap apSecurity

	if !req.Hidden {
		apPaths, err := devInfo.wireless.GetAccessPoints()
		if err != nil {
			return fmt.Errorf("failed to get access points: %w", err)
		}

		for _, candidate := range apPaths {
			ssid, err := candidate.GetPropertySSID()
			if err != nil || ssid != req.SSID {
				continue
			}
			targetAP = candidate
			break
		}

		if targetAP == nil {
			return fmt.Errorf("access point not found: %s", req.SSID)
		}
		ap = accessPointSecurity(targetAP)
	}

	settings, err := buildWiFiSettings(req, ap)
	if err != nil {
		return err
	}
	if !b.canModifySystemConnections() {
		restrictConnectionToCurrentUser(settings["connection"])
	}

	if req.Interactive {
		settingsMgr, err := b.networkManagerSettings()
		if err != nil {
			return err
		}
		conn, err := settingsMgr.AddConnection(settings)
		if err != nil {
			return fmt.Errorf("failed to add connection: %w", err)
		}

		if req.Hidden {
			_, err = nm.ActivateConnection(conn, dev, nil)
		} else {
			_, err = nm.ActivateWirelessConnection(conn, dev, targetAP)
		}
		if err != nil {
			return fmt.Errorf("failed to activate connection: %w", err)
		}
	} else {
		if req.Hidden {
			_, err = nm.AddAndActivateConnection(settings, dev)
		} else {
			_, err = nm.AddAndActivateWirelessConnection(settings, dev, targetAP)
		}
		if err != nil {
			return fmt.Errorf("failed to connect: %w", err)
		}
	}

	log.Infof("[createAndConnectWiFi] Connection activation initiated, waiting for NetworkManager state changes...")
	return nil
}

const nmPermissionModifySystem = dbusNMInterface + ".settings.modify.system"

// GetPermissions never prompts. Short of a silent yes, a shared profile prompts on
// creation and on every secret-agent request (NM re-checks the agent), so own it
// per user like gnome-control-center does.
func (b *NetworkManagerBackend) canModifySystemConnections() bool {
	conn := b.dbusConn
	if conn == nil {
		var err error
		conn, err = dbus.ConnectSystemBus()
		if err != nil {
			return false
		}
		defer conn.Close()
	}

	var permissions map[string]string
	obj := conn.Object(dbusNMInterface, dbus.ObjectPath(dbusNMPath))
	if err := obj.Call(dbusNMInterface+".GetPermissions", 0).Store(&permissions); err != nil {
		log.Warnf("[createAndConnectWiFi] GetPermissions failed, creating a user-owned profile: %v", err)
		return false
	}
	return permissions[nmPermissionModifySystem] == "yes"
}

func restrictConnectionToCurrentUser(connMeta map[string]any) {
	current, err := user.Current()
	if err != nil || current.Username == "" {
		return
	}
	connMeta["permissions"] = []string{"user:" + current.Username + ":"}
}

// apSecurity is what an access point advertises. The zero value means the AP
// is open or unknown.
type apSecurity struct {
	enterprise, psk, sae, owe, secured bool
}

func accessPointSecurity(ap gonetworkmanager.AccessPoint) apSecurity {
	const (
		keyMgmt8021x = uint32(gonetworkmanager.Nm80211APSecKeyMgmt8021X)
		keyMgmtPsk   = uint32(gonetworkmanager.Nm80211APSecKeyMgmtPSK)
		keyMgmtSae   = uint32(gonetworkmanager.Nm80211APSecKeyMgmtSAE)
		// OWE_TM sits on the open BSS of a mixed network, which still wants key-mgmt=owe.
		keyMgmtOwe = uint32(gonetworkmanager.Nm80211APSecKeyMgmtOWE) | uint32(gonetworkmanager.Nm80211APSecKeyMgmtOWETM)
	)
	flags, _ := ap.GetPropertyFlags()
	wpaFlags, _ := ap.GetPropertyWPAFlags()
	rsnFlags, _ := ap.GetPropertyRSNFlags()
	keyMgmt := wpaFlags | rsnFlags
	return apSecurity{
		enterprise: keyMgmt&keyMgmt8021x != 0,
		psk:        keyMgmt&keyMgmtPsk != 0,
		sae:        keyMgmt&keyMgmtSae != 0,
		owe:        keyMgmt&keyMgmtOwe != 0,
		secured: flags&uint32(gonetworkmanager.Nm80211APFlagsPrivacy) != 0 ||
			keyMgmt != uint32(gonetworkmanager.Nm80211APSecNone),
	}
}

// wifiSecurityType picks the key management for a new profile. An explicit
// request wins; without an AP to look at it is inferred from the credentials.
func wifiSecurityType(req ConnectionRequest, ap apSecurity) (string, error) {
	switch {
	case req.Security != "":
		return req.Security, nil
	case req.Hidden || req.SaveOnly:
		switch {
		case req.Enterprise != nil:
			return "wpa-eap", nil
		case req.Password != "":
			return "wpa-psk", nil
		}
		return "none", nil
	case ap.enterprise:
		return "wpa-eap", nil
	case ap.psk:
		return "wpa-psk", nil
	case ap.sae:
		return "sae", nil
	case ap.owe:
		return "owe", nil
	case ap.secured:
		return "", fmt.Errorf("secured network but not OWE/SAE/PSK/802.1X")
	}
	return "none", nil
}

func buildWiFiSettings(req ConnectionRequest, ap apSecurity) (map[string]map[string]any, error) {
	security, err := wifiSecurityType(req, ap)
	if err != nil {
		return nil, err
	}

	wifi := map[string]any{
		"ssid": []byte(req.SSID),
		"mode": "infrastructure",
	}
	if req.Hidden {
		wifi["hidden"] = true
	}
	settings := map[string]map[string]any{
		"connection":      {"id": req.SSID, "type": "802-11-wireless", "autoconnect": true},
		"802-11-wireless": wifi,
		"ipv4":            {"method": "auto"},
		"ipv6":            {"method": "auto"},
	}

	var sec map[string]any
	switch security {
	case "none":
		return settings, nil
	case "owe":
		// No pmf unlike sae: OWE mandates PMF and NM applies it itself.
		sec = map[string]any{"key-mgmt": "owe"}
	case "wpa-psk", "sae":
		sec = map[string]any{"key-mgmt": security, "psk-flags": uint32(0)}
		if security == "sae" {
			sec["pmf"] = int32(3)
		}
		if !req.Interactive {
			if req.Password == "" {
				return nil, fmt.Errorf("password required")
			}
			sec["psk"] = req.Password
		}
	case "wpa-eap":
		if req.Enterprise == nil {
			return nil, fmt.Errorf("802.1X settings required")
		}
		patch, err := enterprise8021xPatch(*req.Enterprise, true)
		if err != nil {
			return nil, err
		}
		maps.DeleteFunc(patch, func(_ string, v any) bool { return v == nil })
		settings["802-1x"] = patch
		sec = map[string]any{"key-mgmt": "wpa-eap"}
	default:
		return nil, fmt.Errorf("unsupported security %q", security)
	}

	wifi["security"] = "802-11-wireless-security"
	settings["802-11-wireless-security"] = sec
	return settings, nil
}

// saveWiFiProfile stores req without activating it: an existing profile for
// the SSID is updated in place, otherwise a new one is written to disk.
func (b *NetworkManagerBackend) saveWiFiProfile(req ConnectionRequest) error {
	if conn, err := b.findConnection(req.SSID); err == nil && conn != nil {
		return updateConnectionCredentials(b, conn, req)
	}
	settings, err := buildWiFiSettings(req, apSecurity{})
	if err != nil {
		return err
	}
	settingsMgr, err := b.networkManagerSettings()
	if err != nil {
		return err
	}
	if _, err := settingsMgr.AddConnection(settings); err != nil {
		return fmt.Errorf("failed to add connection: %w", err)
	}
	return nil
}

var errNoCredentialChange = errors.New("no credential change")

// updateConnectionCredentials applies user-supplied credentials to a saved
// profile; without this a retype after a password change is silently ignored
// in favor of the stored (stale) secret. A save-only request also marks the
// profile autoconnect (and hidden when asked), and errors when its explicit
// security can't be applied to the stored profile.
func updateConnectionCredentials(b *NetworkManagerBackend, conn gonetworkmanager.Connection, req ConnectionRequest) error {
	var patch map[string]any
	if req.Enterprise != nil {
		var err error
		if patch, err = enterprise8021xPatch(*req.Enterprise, false); err != nil {
			return err
		}
	}

	applyCredentials := func(s nmSettings) error {
		if patch != nil {
			keepUnmodelledEnterpriseKeys(patch, s["802-1x"])
			for k, v := range patch {
				if v == nil {
					deleteSettingValue(s, "802-1x", k)
				} else {
					setSettingValue(s, "802-1x", k, v)
				}
			}
			setSettingValue(s, "802-11-wireless", "security", "802-11-wireless-security")
			setSettingValue(s, "802-11-wireless-security", "key-mgmt", "wpa-eap")
			for _, k := range []string{"psk", "psk-flags", "pmf", "auth-alg"} {
				deleteSettingValue(s, "802-11-wireless-security", k)
			}
			return nil
		}

		if req.Password == "" {
			return errNoCredentialChange
		}
		if _, ok := s["802-1x"]; ok {
			setSettingValue(s, "802-1x", "password", req.Password)
			setSettingValue(s, "802-1x", "password-flags", uint32(0))
			return nil
		}

		keyMgmt, _ := s["802-11-wireless-security"]["key-mgmt"].Value().(string)
		switch keyMgmt {
		case "wpa-psk", "sae", "wpa-psk-sae":
			setSettingValue(s, "802-11-wireless-security", "psk", req.Password)
			setSettingValue(s, "802-11-wireless-security", "psk-flags", uint32(0))
			return nil
		default:
			return errNoCredentialChange
		}
	}

	err := updateConnectionSettings(b.nmObject(conn.GetPath()), true, func(s nmSettings) error {
		err := applyCredentials(s)
		if !req.SaveOnly {
			return err
		}
		if err != nil && req.Security != "" {
			stored, _ := s["802-11-wireless-security"]["key-mgmt"].Value().(string)
			if stored == "" {
				stored = "none"
			}
			if stored != req.Security && (!isPSKFamily(stored) || !isPSKFamily(req.Security)) {
				return fmt.Errorf("saved profile %q uses %s security, not %s", req.SSID, stored, req.Security)
			}
		}
		if req.Hidden {
			setSettingValue(s, "802-11-wireless", "hidden", true)
		}
		setSettingValue(s, "connection", "autoconnect", true)
		return nil
	})
	if errors.Is(err, errNoCredentialChange) {
		return nil
	}
	return err
}

// isPSKFamily reports key-mgmt values that share one passphrase.
func isPSKFamily(keyMgmt string) bool {
	return keyMgmt == "wpa-psk" || keyMgmt == "sae" || keyMgmt == "wpa-psk-sae"
}

func (b *NetworkManagerBackend) SetWiFiAutoconnect(ssid string, autoconnect bool) error {
	conn, err := b.findConnection(ssid)
	if err != nil {
		return fmt.Errorf("connection not found: %w", err)
	}

	obj := b.nmObject(conn.GetPath())
	if obj == nil {
		return fmt.Errorf("D-Bus connection unavailable")
	}

	err = updateConnectionSettings(obj, true, func(s nmSettings) error {
		if _, ok := s["connection"]; !ok {
			return fmt.Errorf("connection metadata not found")
		}
		setSettingValue(s, "connection", "autoconnect", autoconnect)
		return nil
	})
	if err != nil {
		return err
	}

	if !autoconnect {
		b.abortInFlightConnection(ssid)
	}

	b.updateWiFiNetworks()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

func (b *NetworkManagerBackend) ScanWiFiDevice(device string) error {
	b.stateMutex.RLock()
	enabled := b.state.WiFiEnabled
	b.stateMutex.RUnlock()

	if !enabled {
		return fmt.Errorf("WiFi is disabled")
	}

	changed, err := b.refreshWiFiDevices()
	if err != nil {
		return err
	}
	if changed {
		b.updateWiFiState()
	}
	devInfo, ok := b.wifiDeviceByIface(device)
	if !ok {
		return fmt.Errorf("WiFi device not found: %s", device)
	}

	if err := devInfo.wireless.RequestScan(); err != nil {
		return fmt.Errorf("scan request failed: %w", err)
	}

	b.updateAllWiFiDevices()
	return nil
}

func (b *NetworkManagerBackend) DisconnectWiFiDevice(device string) error {
	devInfo, ok := b.wifiDeviceByIface(device)
	if !ok {
		return fmt.Errorf("WiFi device not found: %s", device)
	}

	if err := devInfo.device.Disconnect(); err != nil {
		return fmt.Errorf("failed to disconnect: %w", err)
	}

	b.updateWiFiState()
	b.updateAllWiFiDevices()
	b.updatePrimaryConnection()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

func (b *NetworkManagerBackend) GetWiFiDevices() []WiFiDevice {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()
	return append([]WiFiDevice(nil), b.state.WiFiDevices...)
}

func (b *NetworkManagerBackend) updateAllWiFiDevices() {
	s := b.settings
	if s == nil {
		var err error
		s, err = gonetworkmanager.NewSettings()
		if err != nil {
			return
		}
		b.settings = s
	}

	settingsMgr := s.(gonetworkmanager.Settings)
	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return
	}

	savedProfiles := getSavedWiFiProfiles(connections)

	var devices []WiFiDevice
	visibleNetworks := make(map[string]WiFiNetwork)
	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	wifiConnected := b.state.WiFiConnected
	b.stateMutex.RUnlock()

	var apModeDevicePaths map[string]bool
	for name, devInfo := range b.wifiDevicesSnapshot() {
		state, _ := devInfo.device.GetPropertyState()
		connected := state == gonetworkmanager.NmDeviceStateActivated
		if connected {
			if apModeDevicePaths == nil {
				apModeDevicePaths = b.activeAPModeWiFiDevicePaths()
			}
			if apModeDevicePaths[string(devInfo.device.GetPath())] {
				connected = false
			}
		}

		var ssid, bssid, ip string
		var signal uint8

		if connected {
			if activeAP, err := devInfo.wireless.GetPropertyActiveAccessPoint(); err == nil && activeAP != nil && activeAP.GetPath() != "/" {
				ssid, _ = activeAP.GetPropertySSID()
				signal, _ = activeAP.GetPropertyStrength()
				bssid, _ = activeAP.GetPropertyHWAddress()
			}
			ip = b.getDeviceIP(devInfo.device)
		}

		stateStr := "disconnected"
		switch state {
		case gonetworkmanager.NmDeviceStateActivated:
			if connected {
				stateStr = "connected"
			}
		case gonetworkmanager.NmDeviceStateConfig, gonetworkmanager.NmDeviceStateIpConfig:
			stateStr = "connecting"
		case gonetworkmanager.NmDeviceStatePrepare:
			stateStr = "preparing"
		case gonetworkmanager.NmDeviceStateDeactivating:
			stateStr = "disconnecting"
		}

		apPaths, err := devInfo.wireless.GetAccessPoints()
		var networks []WiFiNetwork
		if err == nil {
			seenSSIDs := make(map[string]int)
			networks = make([]WiFiNetwork, 0, len(apPaths)+1)
			for _, ap := range apPaths {
				apSSID, err := ap.GetPropertySSID()
				if err != nil || apSSID == "" {
					continue
				}
				mode, _ := ap.GetPropertyMode()
				if mode == gonetworkmanager.Nm80211ModeAp {
					continue
				}

				if existingIndex, exists := seenSSIDs[apSSID]; exists {
					existing := &networks[existingIndex]
					strength, _ := ap.GetPropertyStrength()
					if strength > existing.Signal {
						existing.Signal = strength
						freq, _ := ap.GetPropertyFrequency()
						existing.Frequency = freq
						apBSSID, _ := ap.GetPropertyHWAddress()
						existing.BSSID = apBSSID
					}
					continue
				}

				strength, _ := ap.GetPropertyStrength()
				flags, _ := ap.GetPropertyFlags()
				wpaFlags, _ := ap.GetPropertyWPAFlags()
				rsnFlags, _ := ap.GetPropertyRSNFlags()
				freq, _ := ap.GetPropertyFrequency()
				maxBitrate, _ := ap.GetPropertyMaxBitrate()
				apBSSID, _ := ap.GetPropertyHWAddress()

				secured := apNeedsCredentials(flags, wpaFlags, rsnFlags)

				enterprise := (rsnFlags&uint32(gonetworkmanager.Nm80211APSecKeyMgmt8021X) != 0) ||
					(wpaFlags&uint32(gonetworkmanager.Nm80211APSecKeyMgmt8021X) != 0)

				var modeStr string
				switch mode {
				case gonetworkmanager.Nm80211ModeAdhoc:
					modeStr = "adhoc"
				case gonetworkmanager.Nm80211ModeInfra:
					modeStr = "infrastructure"
				case gonetworkmanager.Nm80211ModeAp:
					modeStr = "ap"
				default:
					modeStr = "unknown"
				}

				channel := frequencyToChannel(freq)

				isConnected := connected && apSSID == ssid
				rate := maxBitrate / 1000
				if isConnected {
					if devBitrate, err := devInfo.wireless.GetPropertyBitrate(); err == nil && devBitrate > 0 {
						rate = devBitrate / 1000
					}
				}

				profile, saved := savedProfiles[apSSID]
				network := WiFiNetwork{
					SSID:        apSSID,
					BSSID:       apBSSID,
					Signal:      strength,
					Secured:     secured,
					Enterprise:  enterprise,
					Connected:   isConnected,
					Saved:       saved,
					Autoconnect: profile.Autoconnect,
					Hidden:      profile.Hidden,
					Frequency:   freq,
					Mode:        modeStr,
					Rate:        rate,
					Channel:     channel,
					Device:      name,
				}

				networks = append(networks, network)
				seenSSIDs[apSSID] = len(networks) - 1
				if existing, ok := visibleNetworks[apSSID]; !ok || network.Signal > existing.Signal {
					visibleNetworks[apSSID] = network
				}
			}

			if connected && ssid != "" {
				if _, exists := seenSSIDs[ssid]; !exists {
					profile, saved := savedProfiles[ssid]
					hiddenNetwork := WiFiNetwork{
						SSID:        ssid,
						BSSID:       bssid,
						Signal:      signal,
						Secured:     true,
						Connected:   true,
						Saved:       saved,
						Autoconnect: profile.Autoconnect,
						Hidden:      true,
						Mode:        "infrastructure",
						Device:      name,
					}
					networks = append(networks, hiddenNetwork)
					seenSSIDs[ssid] = len(networks) - 1
					visibleNetworks[ssid] = hiddenNetwork
				}
			}

			sortWiFiNetworks(networks)
		}

		apCapable, _ := isAPCapableWiFiDevice(devInfo)

		devices = append(devices, WiFiDevice{
			Name:      name,
			HwAddress: devInfo.hwAddress,
			State:     stateStr,
			Connected: connected,
			APCapable: apCapable,
			SSID:      ssid,
			BSSID:     bssid,
			Signal:    signal,
			IP:        ip,
			Networks:  networks,
		})
	}

	sort.Slice(devices, func(i, j int) bool {
		return devices[i].Name < devices[j].Name
	})

	b.stateMutex.Lock()
	b.state.WiFiDevices = devices
	b.state.SavedWiFiNetworks = savedWiFiNetworksFromProfiles(savedProfiles, visibleNetworks, currentSSID, wifiConnected)
	b.stateMutex.Unlock()
}

func (b *NetworkManagerBackend) getWifiDeviceForConnection(deviceName string) (*wifiDeviceInfo, error) {
	if deviceName != "" {
		devInfo, ok := b.wifiDeviceByIface(deviceName)
		if !ok {
			return nil, fmt.Errorf("WiFi device not found: %s", deviceName)
		}
		return devInfo, nil
	}

	dev, _ := b.selectedWiFiDevice()
	if dev == nil {
		return nil, fmt.Errorf("no WiFi device available")
	}
	iface, _ := dev.GetPropertyInterface()
	if devInfo, ok := b.wifiDeviceByIface(iface); ok {
		return devInfo, nil
	}

	return nil, fmt.Errorf("no WiFi device available")
}
