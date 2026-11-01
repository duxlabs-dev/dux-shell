package network

import (
	"bytes"
	"fmt"
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

		secured := flags&uint32(gonetworkmanager.Nm80211APFlagsPrivacy) != 0 ||
			wpaFlags != uint32(gonetworkmanager.Nm80211APSecNone) ||
			rsnFlags != uint32(gonetworkmanager.Nm80211APSecNone)

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
	conn, err := b.findConnection(ssid)
	if err != nil {
		return "", fmt.Errorf("no saved connection for `%s`: %w", ssid, err)
	}

	connSettings, err := conn.GetSettings()
	if err != nil {
		return "", fmt.Errorf("failed to get settings for `%s`: %w", ssid, err)
	}

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
		if req.Password != "" || req.Username != "" {
			if err := updateConnectionCredentials(existingConn, req); err != nil {
				log.Warnf("[ConnectWiFi] Failed to update credentials on existing profile: %v", err)
			}
		}
		b.stateMutex.Lock()
		b.state.ConnectingPreExisting = true
		b.stateMutex.Unlock()
		_, err := nm.ActivateConnection(existingConn, devInfo.device, nil)
		if err != nil {
			log.Warnf("[ConnectWiFi] Failed to activate existing connection: %v", err)
			b.stateMutex.Lock()
			b.state.IsConnecting = false
			b.state.ConnectingSSID = ""
			b.state.ConnectingDevice = ""
			b.state.LastError = fmt.Sprintf("failed to activate connection: %v", err)
			b.stateMutex.Unlock()
			if b.onStateChange != nil {
				b.onStateChange()
			}
			return fmt.Errorf("failed to activate connection: %w", err)
		}

		return nil
	}

	if err := b.createAndConnectWiFiOnDevice(req, devInfo); err != nil {
		log.Warnf("[ConnectWiFi] Failed to create and connect: %v", err)
		b.stateMutex.Lock()
		b.state.IsConnecting = false
		b.state.ConnectingSSID = ""
		b.state.ConnectingDevice = ""
		b.state.LastError = err.Error()
		b.stateMutex.Unlock()
		if b.onStateChange != nil {
			b.onStateChange()
		}
		return err
	}

	return nil
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
		if _, ok := connSettings["802-11-wireless-security"]; ok {
			profile.Secured = true
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

		secured := flags&uint32(gonetworkmanager.Nm80211APFlagsPrivacy) != 0 ||
			wpaFlags != uint32(gonetworkmanager.Nm80211APSecNone) ||
			rsnFlags != uint32(gonetworkmanager.Nm80211APSecNone)

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
	w := devInfo.wireless

	var targetAP gonetworkmanager.AccessPoint
	var flags, wpaFlags, rsnFlags uint32

	if !req.Hidden {
		apPaths, err := w.GetAccessPoints()
		if err != nil {
			return fmt.Errorf("failed to get access points: %w", err)
		}

		for _, ap := range apPaths {
			ssid, err := ap.GetPropertySSID()
			if err != nil || ssid != req.SSID {
				continue
			}
			targetAP = ap
			break
		}

		if targetAP == nil {
			return fmt.Errorf("access point not found: %s", req.SSID)
		}

		flags, _ = targetAP.GetPropertyFlags()
		wpaFlags, _ = targetAP.GetPropertyWPAFlags()
		rsnFlags, _ = targetAP.GetPropertyRSNFlags()
	}

	const (
		keyMgmt8021x = uint32(gonetworkmanager.Nm80211APSecKeyMgmt8021X)
		keyMgmtPsk   = uint32(gonetworkmanager.Nm80211APSecKeyMgmtPSK)
		keyMgmtSae   = uint32(gonetworkmanager.Nm80211APSecKeyMgmtSAE)
		// OWE_TM sits on the open BSS of a mixed network, which still wants key-mgmt=owe.
		keyMgmtOwe = uint32(gonetworkmanager.Nm80211APSecKeyMgmtOWE) | uint32(gonetworkmanager.Nm80211APSecKeyMgmtOWETM)
	)

	var isEnterprise, isPsk, isSae, isOwe, secured bool

	switch {
	case req.Hidden:
		secured = req.Password != "" || req.Username != ""
		isEnterprise = req.Username != ""
		isPsk = req.Password != "" && !isEnterprise
	default:
		isEnterprise = (wpaFlags&keyMgmt8021x) != 0 || (rsnFlags&keyMgmt8021x) != 0
		isPsk = (wpaFlags&keyMgmtPsk) != 0 || (rsnFlags&keyMgmtPsk) != 0
		isSae = (wpaFlags&keyMgmtSae) != 0 || (rsnFlags&keyMgmtSae) != 0
		isOwe = (wpaFlags&keyMgmtOwe) != 0 || (rsnFlags&keyMgmtOwe) != 0
		secured = flags&uint32(gonetworkmanager.Nm80211APFlagsPrivacy) != 0 ||
			wpaFlags != uint32(gonetworkmanager.Nm80211APSecNone) ||
			rsnFlags != uint32(gonetworkmanager.Nm80211APSecNone)
	}

	if isEnterprise {
		log.Infof("[createAndConnectWiFi] Enterprise network detected (802.1x) - SSID: %s, interactive: %v",
			req.SSID, req.Interactive)
	}

	settings := make(map[string]map[string]any)

	settings["connection"] = map[string]any{
		"id":          req.SSID,
		"type":        "802-11-wireless",
		"autoconnect": true,
	}
	if !b.canModifySystemConnections() {
		restrictConnectionToCurrentUser(settings["connection"])
	}

	settings["ipv4"] = map[string]any{"method": "auto"}
	settings["ipv6"] = map[string]any{"method": "auto"}

	if secured {
		wifiSettings := map[string]any{
			"ssid":     []byte(req.SSID),
			"mode":     "infrastructure",
			"security": "802-11-wireless-security",
		}
		if req.Hidden {
			wifiSettings["hidden"] = true
		}
		settings["802-11-wireless"] = wifiSettings

		switch {
		case isEnterprise || req.Username != "":
			settings["802-11-wireless-security"] = map[string]any{
				"key-mgmt": "wpa-eap",
			}

			eapMethod := "peap"
			if req.EAPMethod != "" {
				eapMethod = req.EAPMethod
			}

			phase2Auth := "mschapv2"
			if req.Phase2Auth != "" {
				phase2Auth = req.Phase2Auth
			}

			useSystemCACerts := false
			if req.UseSystemCACerts != nil {
				useSystemCACerts = *req.UseSystemCACerts
			}

			x := map[string]any{
				"eap":             []string{eapMethod},
				"system-ca-certs": useSystemCACerts,
				"password-flags":  uint32(0),
			}

			switch eapMethod {
			case "peap", "ttls":
				x["phase2-auth"] = phase2Auth
			case "tls":
				if req.ClientCertPath != "" {
					x["client-cert"] = []byte("file://" + req.ClientCertPath)
				}
				if req.PrivateKeyPath != "" {
					x["private-key"] = []byte("file://" + req.PrivateKeyPath)
				}
			}

			if req.Username != "" {
				x["identity"] = req.Username
			}
			if req.Password != "" {
				x["password"] = req.Password
			}
			if req.AnonymousIdentity != "" {
				x["anonymous-identity"] = req.AnonymousIdentity
			}
			if req.DomainSuffixMatch != "" {
				x["domain-suffix-match"] = req.DomainSuffixMatch
			}
			if req.CACertPath != "" {
				x["ca-cert"] = []byte("file://" + req.CACertPath)
			}

			settings["802-1x"] = x

			log.Infof("[createAndConnectWiFi] WPA-EAP settings: eap=%s, phase2-auth=%s, identity=%s, interactive=%v, system-ca-certs=%v, domain-suffix-match=%q",
				eapMethod, phase2Auth, req.Username, req.Interactive, useSystemCACerts, req.DomainSuffixMatch)

		case isPsk:
			sec := map[string]any{
				"key-mgmt":  "wpa-psk",
				"psk-flags": uint32(0),
			}
			if !req.Interactive {
				sec["psk"] = req.Password
			}
			settings["802-11-wireless-security"] = sec

		case isSae:
			sec := map[string]any{
				"key-mgmt":  "sae",
				"pmf":       int32(3),
				"psk-flags": uint32(0),
			}
			if !req.Interactive {
				sec["psk"] = req.Password
			}
			settings["802-11-wireless-security"] = sec

		case isOwe:
			// No pmf unlike the sae case: OWE mandates PMF and NM applies it itself.
			settings["802-11-wireless-security"] = map[string]any{
				"key-mgmt": "owe",
			}

		default:
			return fmt.Errorf("secured network but not OWE/SAE/PSK/802.1X (rsn=0x%x wpa=0x%x)", rsnFlags, wpaFlags)
		}
	} else {
		wifiSettings := map[string]any{
			"ssid": []byte(req.SSID),
			"mode": "infrastructure",
		}
		if req.Hidden {
			wifiSettings["hidden"] = true
		}
		settings["802-11-wireless"] = wifiSettings
	}

	if req.Interactive {
		s := b.settings
		if s == nil {
			var settingsErr error
			s, settingsErr = gonetworkmanager.NewSettings()
			if settingsErr != nil {
				return fmt.Errorf("failed to get settings manager: %w", settingsErr)
			}
			b.settings = s
		}

		settingsMgr := s.(gonetworkmanager.Settings)
		conn, err := settingsMgr.AddConnection(settings)
		if err != nil {
			return fmt.Errorf("failed to add connection: %w", err)
		}

		if isEnterprise {
			log.Infof("[createAndConnectWiFi] Enterprise connection added, activating (secret agent will be called)")
		}

		if req.Hidden {
			_, err = nm.ActivateConnection(conn, dev, nil)
		} else {
			_, err = nm.ActivateWirelessConnection(conn, dev, targetAP)
		}
		if err != nil {
			return fmt.Errorf("failed to activate connection: %w", err)
		}

		log.Infof("[createAndConnectWiFi] Connection activation initiated, waiting for NetworkManager state changes...")
	} else {
		var err error
		if req.Hidden {
			_, err = nm.AddAndActivateConnection(settings, dev)
		} else {
			_, err = nm.AddAndActivateWirelessConnection(settings, dev, targetAP)
		}
		if err != nil {
			return fmt.Errorf("failed to connect: %w", err)
		}
		log.Infof("[createAndConnectWiFi] Connection activation initiated, waiting for NetworkManager state changes...")
	}

	return nil
}

// updateConnectionCredentials applies user-supplied credentials to a saved
// profile before activation; without this a retype after a password change is
// silently ignored in favor of the stored (stale) secret.
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

func updateConnectionCredentials(conn gonetworkmanager.Connection, req ConnectionRequest) error {
	settings, err := conn.GetSettings()
	if err != nil {
		return fmt.Errorf("failed to get connection settings: %w", err)
	}

	for _, section := range []string{"ipv4", "ipv6"} {
		ipCfg, ok := settings[section]
		if !ok {
			continue
		}
		delete(ipCfg, "addresses")
		delete(ipCfg, "routes")
		delete(ipCfg, "dns")
	}

	mergeStoredSecrets(conn, settings)

	if dot1x, ok := settings["802-1x"]; ok {
		if req.Username != "" {
			dot1x["identity"] = req.Username
		}
		if req.Password != "" {
			dot1x["password"] = req.Password
			dot1x["password-flags"] = uint32(0)
		}
		if req.AnonymousIdentity != "" {
			dot1x["anonymous-identity"] = req.AnonymousIdentity
		}
		if req.DomainSuffixMatch != "" {
			dot1x["domain-suffix-match"] = req.DomainSuffixMatch
		}
		return conn.Update(settings)
	}

	sec, ok := settings["802-11-wireless-security"]
	if !ok || req.Password == "" {
		return nil
	}

	keyMgmt, _ := sec["key-mgmt"].(string)
	switch keyMgmt {
	case "wpa-psk", "sae", "wpa-psk-sae":
		sec["psk"] = req.Password
		sec["psk-flags"] = uint32(0)
	default:
		return nil
	}
	return conn.Update(settings)
}

func (b *NetworkManagerBackend) SetWiFiAutoconnect(ssid string, autoconnect bool) error {
	conn, err := b.findConnection(ssid)
	if err != nil {
		return fmt.Errorf("connection not found: %w", err)
	}

	settings, err := conn.GetSettings()
	if err != nil {
		return fmt.Errorf("failed to get connection settings: %w", err)
	}

	if connMeta, ok := settings["connection"]; ok {
		connMeta["autoconnect"] = autoconnect
	} else {
		return fmt.Errorf("connection metadata not found")
	}

	if ipv4, ok := settings["ipv4"]; ok {
		delete(ipv4, "addresses")
		delete(ipv4, "routes")
		delete(ipv4, "dns")
	}

	if ipv6, ok := settings["ipv6"]; ok {
		delete(ipv6, "addresses")
		delete(ipv6, "routes")
		delete(ipv6, "dns")
	}

	mergeStoredSecrets(conn, settings)

	err = conn.Update(settings)
	if err != nil {
		return fmt.Errorf("failed to update connection: %w", err)
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

				secured := flags&uint32(gonetworkmanager.Nm80211APFlagsPrivacy) != 0 ||
					wpaFlags != uint32(gonetworkmanager.Nm80211APSecNone) ||
					rsnFlags != uint32(gonetworkmanager.Nm80211APSecNone)

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
