package network

import (
	"context"
	"fmt"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

func (b *IWDBackend) updateState() error {
	if b.devicePath == "" {
		return nil
	}

	obj := b.conn.Object(iwdBusName, b.devicePath)

	poweredVar, err := obj.GetProperty(iwdDeviceInterface + ".Powered")
	if err == nil {
		if powered, ok := poweredVar.Value().(bool); ok {
			b.stateMutex.Lock()
			b.state.WiFiEnabled = powered
			b.stateMutex.Unlock()
		}
	}

	if b.stationPath == "" {
		return nil
	}

	stationObj := b.conn.Object(iwdBusName, b.stationPath)

	stateVar, err := stationObj.GetProperty(iwdStationInterface + ".State")
	if err == nil {
		if state, ok := stateVar.Value().(string); ok {
			b.stateMutex.Lock()
			b.state.WiFiConnected = (state == "connected")
			if state == "connected" {
				b.state.NetworkStatus = StatusWiFi
			} else {
				b.state.NetworkStatus = StatusDisconnected
			}
			b.stateMutex.Unlock()
		}
	}

	connNetVar, err := stationObj.GetProperty(iwdStationInterface + ".ConnectedNetwork")
	if err == nil && connNetVar.Value() != nil {
		if netPath, ok := connNetVar.Value().(dbus.ObjectPath); ok && netPath != "/" {
			netObj := b.conn.Object(iwdBusName, netPath)

			nameVar, err := netObj.GetProperty(iwdNetworkInterface + ".Name")
			if err == nil {
				if name, ok := nameVar.Value().(string); ok {
					b.stateMutex.Lock()
					b.state.WiFiSSID = name
					b.stateMutex.Unlock()
				}
			}

			var orderedNetworks [][]dbus.Variant
			err = stationObj.Call(iwdStationInterface+".GetOrderedNetworks", 0).Store(&orderedNetworks)
			if err == nil {
				for _, netData := range orderedNetworks {
					if len(netData) < 2 {
						continue
					}
					currentNetPath, ok := netData[0].Value().(dbus.ObjectPath)
					if !ok || currentNetPath != netPath {
						continue
					}
					signalStrength, ok := netData[1].Value().(int16)
					if !ok {
						continue
					}
					signalDbm := signalStrength / 100
					signal := uint8(signalDbm + 100)
					if signalDbm > 0 {
						signal = 100
					} else if signalDbm < -100 {
						signal = 0
					}
					b.stateMutex.Lock()
					b.state.WiFiSignal = signal
					b.stateMutex.Unlock()
					break
				}
			}
		}
	}

	networks, err := b.updateWiFiNetworks()
	if err == nil {
		b.stateMutex.Lock()
		b.state.WiFiNetworks = networks
		b.stateMutex.Unlock()
	}

	return nil
}

func (b *IWDBackend) GetWiFiEnabled() (bool, error) {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()
	return b.state.WiFiEnabled, nil
}

func (b *IWDBackend) SetWiFiEnabled(enabled bool) error {
	if b.devicePath == "" {
		return fmt.Errorf("no WiFi device available")
	}

	obj := b.conn.Object(iwdBusName, b.devicePath)
	call := obj.Call(dbusPropertiesInterface+".Set", 0, iwdDeviceInterface, "Powered", dbus.MakeVariant(enabled))
	if call.Err != nil {
		return fmt.Errorf("failed to set WiFi enabled: %w", call.Err)
	}

	b.stateMutex.Lock()
	b.state.WiFiEnabled = enabled
	b.stateMutex.Unlock()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

func (b *IWDBackend) ScanWiFi() error {
	if b.stationPath == "" {
		return fmt.Errorf("no WiFi device available")
	}

	obj := b.conn.Object(iwdBusName, b.stationPath)

	scanningVar, err := obj.GetProperty(iwdStationInterface + ".Scanning")
	if err != nil {
		return fmt.Errorf("failed to check scanning state: %w", err)
	}

	if scanning, ok := scanningVar.Value().(bool); ok && scanning {
		return fmt.Errorf("scan already in progress")
	}

	call := obj.Call(iwdStationInterface+".Scan", 0)
	if call.Err != nil {
		return fmt.Errorf("scan request failed: %w", call.Err)
	}

	return nil
}

func (b *IWDBackend) updateWiFiNetworks() ([]WiFiNetwork, error) {
	if b.stationPath == "" {
		return nil, fmt.Errorf("no WiFi device available")
	}

	obj := b.conn.Object(iwdBusName, b.stationPath)

	var orderedNetworks [][]dbus.Variant
	err := obj.Call(iwdStationInterface+".GetOrderedNetworks", 0).Store(&orderedNetworks)
	if err != nil {
		return nil, fmt.Errorf("failed to get networks: %w", err)
	}

	savedProfiles, err := b.getIWDSavedWiFiProfiles()
	if err != nil {
		savedProfiles = make(map[string]savedWiFiProfile)
	}

	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	wifiConnected := b.state.WiFiConnected
	wifiSignal := b.state.WiFiSignal
	b.stateMutex.RUnlock()

	visibleNetworks := make([]WiFiNetwork, 0, len(orderedNetworks))
	for _, netData := range orderedNetworks {
		if len(netData) < 2 {
			continue
		}

		networkPath, ok := netData[0].Value().(dbus.ObjectPath)
		if !ok {
			continue
		}

		signalStrength, ok := netData[1].Value().(int16)
		if !ok {
			continue
		}

		netObj := b.conn.Object(iwdBusName, networkPath)

		nameVar, err := netObj.GetProperty(iwdNetworkInterface + ".Name")
		if err != nil {
			continue
		}
		name, ok := nameVar.Value().(string)
		if !ok {
			continue
		}

		typeVar, err := netObj.GetProperty(iwdNetworkInterface + ".Type")
		if err != nil {
			continue
		}
		netType, ok := typeVar.Value().(string)
		if !ok {
			continue
		}

		signalDbm := signalStrength / 100
		signal := uint8(signalDbm + 100)
		if signalDbm > 0 {
			signal = 100
		} else if signalDbm < -100 {
			signal = 0
		}

		secured := netType != "open"

		visibleNetworks = append(visibleNetworks, WiFiNetwork{
			SSID:       name,
			Signal:     signal,
			Secured:    secured,
			Enterprise: netType == "8021x",
		})
	}

	networks := iwdWiFiNetworksFromVisible(visibleNetworks, savedProfiles, currentSSID, wifiConnected, wifiSignal)
	visibleNetworkMap := make(map[string]WiFiNetwork, len(networks))
	for _, network := range networks {
		visibleNetworkMap[network.SSID] = network
	}
	savedNetworks := savedWiFiNetworksFromProfiles(savedProfiles, visibleNetworkMap, currentSSID, wifiConnected)

	sortWiFiNetworks(networks)

	b.stateMutex.Lock()
	b.state.WiFiNetworks = networks
	b.state.SavedWiFiNetworks = savedNetworks
	b.stateMutex.Unlock()

	now := time.Now()
	b.recentScansMu.Lock()
	for _, net := range networks {
		b.recentScans[net.SSID] = now
	}
	b.recentScansMu.Unlock()

	return networks, nil
}

func (b *IWDBackend) updateSavedWiFiNetworks() error {
	savedProfiles, err := b.getIWDSavedWiFiProfiles()
	if err != nil {
		return err
	}

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

func iwdWiFiNetworksFromVisible(visibleNetworks []WiFiNetwork, savedProfiles map[string]savedWiFiProfile, currentSSID string, wifiConnected bool, wifiSignal uint8) []WiFiNetwork {
	networks := make([]WiFiNetwork, 0, len(visibleNetworks)+1)
	seenSSIDs := make(map[string]struct{}, len(visibleNetworks)+1)

	for _, network := range visibleNetworks {
		profile, saved := savedProfiles[network.SSID]
		network.Connected = wifiConnected && network.SSID == currentSSID
		network.Saved = saved
		network.Autoconnect = profile.Autoconnect
		network.Hidden = network.Hidden || profile.Hidden
		network.Secured = network.Secured || profile.Secured
		network.Enterprise = network.Enterprise || profile.Enterprise
		if network.Mode == "" {
			network.Mode = profile.Mode
		}
		networks = append(networks, network)
		seenSSIDs[network.SSID] = struct{}{}
	}

	if wifiConnected && currentSSID != "" {
		if _, exists := seenSSIDs[currentSSID]; !exists {
			profile, saved := savedProfiles[currentSSID]
			secured := profile.Secured
			if !saved {
				secured = true
			}
			mode := profile.Mode
			if mode == "" {
				mode = "infrastructure"
			}

			networks = append(networks, WiFiNetwork{
				SSID:        currentSSID,
				Signal:      wifiSignal,
				Secured:     secured,
				Enterprise:  profile.Enterprise,
				Connected:   true,
				Saved:       saved,
				Autoconnect: profile.Autoconnect,
				Hidden:      true,
				Mode:        mode,
			})
		}
	}

	return networks
}

func iwdSavedWiFiProfilesFromManagedObjects(objects map[dbus.ObjectPath]map[string]map[string]dbus.Variant) map[string]savedWiFiProfile {
	profiles := make(map[string]savedWiFiProfile)

	for _, interfaces := range objects {
		knownProps, ok := interfaces[iwdKnownNetworkInterface]
		if !ok {
			continue
		}

		nameVar, ok := knownProps["Name"]
		if !ok {
			continue
		}
		name, ok := nameVar.Value().(string)
		if !ok || name == "" {
			continue
		}

		profile := savedWiFiProfile{
			Autoconnect: true,
			Mode:        "infrastructure",
		}
		if acVar, ok := knownProps["AutoConnect"]; ok {
			if autoconnect, ok := acVar.Value().(bool); ok {
				profile.Autoconnect = autoconnect
			}
		}
		if hiddenVar, ok := knownProps["Hidden"]; ok {
			if hidden, ok := hiddenVar.Value().(bool); ok {
				profile.Hidden = hidden
			}
		}
		if typeVar, ok := knownProps["Type"]; ok {
			if networkType, ok := typeVar.Value().(string); ok {
				profile.Secured = networkType != "" && networkType != "open"
				profile.Enterprise = networkType == "8021x"
			}
		}

		if existing, ok := profiles[name]; ok {
			profile.Autoconnect = profile.Autoconnect || existing.Autoconnect
			profile.Hidden = profile.Hidden || existing.Hidden
			profile.Secured = profile.Secured || existing.Secured
			profile.Enterprise = profile.Enterprise || existing.Enterprise
		}

		profiles[name] = profile
	}

	return profiles
}

func (b *IWDBackend) getIWDSavedWiFiProfiles() (map[string]savedWiFiProfile, error) {
	obj := b.conn.Object(iwdBusName, iwdObjectPath)

	var objects map[dbus.ObjectPath]map[string]map[string]dbus.Variant
	err := obj.Call(dbusObjectManager+".GetManagedObjects", 0).Store(&objects)
	if err != nil {
		return nil, err
	}

	return iwdSavedWiFiProfilesFromManagedObjects(objects), nil
}

func (b *IWDBackend) GetWiFiNetworkDetails(ssid string) (*NetworkInfoResponse, error) {
	b.stateMutex.RLock()
	networks := b.state.WiFiNetworks
	b.stateMutex.RUnlock()

	var found *WiFiNetwork
	for i := range networks {
		if networks[i].SSID == ssid {
			found = &networks[i]
			break
		}
	}

	if found == nil {
		return nil, fmt.Errorf("network not found: %s", ssid)
	}

	return &NetworkInfoResponse{
		SSID:  ssid,
		Bands: []WiFiNetwork{*found},
	}, nil
}

func (b *IWDBackend) setConnectError(code string) {
	b.stateMutex.Lock()
	b.state.IsConnecting = false
	b.state.ConnectingSSID = ""
	b.state.LastError = code
	b.stateMutex.Unlock()
}

func (b *IWDBackend) seenInRecentScan(ssid string) bool {
	b.recentScansMu.Lock()
	defer b.recentScansMu.Unlock()
	lastSeen, ok := b.recentScans[ssid]
	return ok && time.Since(lastSeen) < 30*time.Second
}

func (b *IWDBackend) classifyAttempt(att *connectAttempt) string {
	att.mu.Lock()
	defer att.mu.Unlock()

	if att.sawPromptRetry {
		return errdefs.ErrBadCredentials
	}

	if !att.connectedAt.IsZero() && !att.sawIPConfig {
		connDuration := time.Since(att.connectedAt)
		if connDuration > 500*time.Millisecond && connDuration < 3*time.Second {
			return errdefs.ErrBadCredentials
		}
	}

	if (att.sawAuthish || !att.connectedAt.IsZero()) && !att.sawIPConfig {
		if time.Since(att.start) > 12*time.Second {
			return errdefs.ErrDhcpTimeout
		}
	}

	if !att.sawAuthish && att.connectedAt.IsZero() {
		if !b.seenInRecentScan(att.ssid) {
			return errdefs.ErrNoSuchSSID
		}
		return errdefs.ErrAssocTimeout
	}

	return errdefs.ErrAssocTimeout
}

func (b *IWDBackend) finalizeAttempt(att *connectAttempt, code string) {
	att.mu.Lock()
	if att.finalized {
		att.mu.Unlock()
		return
	}
	att.finalized = true
	att.mu.Unlock()

	b.stateMutex.Lock()
	b.state.IsConnecting = false
	b.state.ConnectingSSID = ""
	b.state.LastError = code
	b.stateMutex.Unlock()

	b.updateState()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	if code == errdefs.ErrBadCredentials {
		b.maybeReplaceSavedPSK(att)
	}
}

func (b *IWDBackend) maybeReplaceSavedPSK(att *connectAttempt) {
	if b.promptBroker == nil || !att.saved {
		return
	}

	att.mu.Lock()
	prompted := att.sawPromptRetry
	att.mu.Unlock()
	if prompted {
		return
	}

	b.sigWG.Go(func() {
		b.requestReplacementPSK(att.ssid)
	})
}

func (b *IWDBackend) requestReplacementPSK(ssid string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	go func() {
		select {
		case <-b.stopChan:
			cancel()
		case <-ctx.Done():
		}
	}()

	token, err := b.promptBroker.Ask(ctx, PromptRequest{
		SSID:        ssid,
		SettingName: "802-11-wireless-security",
		Fields:      []string{"psk"},
		Reason:      "wrong-password",
	})
	if err != nil {
		log.Warnf("failed to request replacement credentials for %s: %v", ssid, err)
		return
	}

	reply, err := b.promptBroker.Wait(ctx, token)
	if err != nil || reply.Cancel {
		return
	}

	psk, ok := reply.Secrets["psk"]
	if !ok || psk == "" {
		return
	}

	if err := b.ForgetWiFiNetwork(ssid); err != nil {
		log.Warnf("failed to forget %s before credential replacement: %v", ssid, err)
	}

	b.storePendingPSK(ssid, psk)

	if err := b.ConnectWiFi(ConnectionRequest{SSID: ssid}); err != nil {
		log.Warnf("failed to reconnect %s with replacement credentials: %v", ssid, err)
	}
}

func (b *IWDBackend) startAttemptWatchdog(att *connectAttempt) {
	b.sigWG.Go(func() {

		ticker := time.NewTicker(250 * time.Millisecond)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				att.mu.Lock()
				finalized := att.finalized
				att.mu.Unlock()

				if finalized || time.Now().After(att.deadline) {
					if !finalized {
						b.finalizeAttempt(att, b.classifyAttempt(att))
					}
					return
				}

				station := b.conn.Object(iwdBusName, b.stationPath)
				stVar, err := station.GetProperty(iwdStationInterface + ".State")
				if err != nil {
					continue
				}
				state, _ := stVar.Value().(string)

				cnVar, err := station.GetProperty(iwdStationInterface + ".ConnectedNetwork")
				if err != nil {
					continue
				}
				var connPath dbus.ObjectPath
				if cnVar.Value() != nil {
					connPath, _ = cnVar.Value().(dbus.ObjectPath)
				}

				att.mu.Lock()
				if connPath == att.netPath && state == "connected" && att.connectedAt.IsZero() {
					att.connectedAt = time.Now()
				}
				if state == "configuring" {
					att.sawIPConfig = true
				}
				att.mu.Unlock()

			case <-b.stopChan:
				return
			}
		}
	})
}

func (b *IWDBackend) mapIwdDBusError(name string) string {
	switch name {
	case "net.connman.iwd.Error.AlreadyConnected":
		return errdefs.ErrAlreadyConnected
	case "net.connman.iwd.Error.AuthenticationFailed",
		"net.connman.iwd.Error.InvalidKey",
		"net.connman.iwd.Error.IncorrectPassphrase":
		return errdefs.ErrBadCredentials
	case "net.connman.iwd.Error.NotFound":
		return errdefs.ErrNoSuchSSID
	case "net.connman.iwd.Error.NotSupported":
		return errdefs.ErrConnectionFailed
	case "net.connman.iwd.Agent.Error.Canceled":
		return errdefs.ErrUserCanceled
	default:
		return errdefs.ErrConnectionFailed
	}
}

func (b *IWDBackend) ConnectWiFi(req ConnectionRequest) error {
	if b.stationPath == "" {
		b.setConnectError(errdefs.ErrWifiDisabled)
		if b.onStateChange != nil {
			b.onStateChange()
		}
		return fmt.Errorf("no WiFi device available")
	}

	networkPath, saved, err := b.findNetworkPath(req.SSID)
	if err != nil {
		b.setConnectError(errdefs.ErrNoSuchSSID)
		if b.onStateChange != nil {
			b.onStateChange()
		}
		return fmt.Errorf("network not found: %w", err)
	}

	if req.Password != "" {
		b.storePendingPSK(req.SSID, req.Password)
	}

	att := &connectAttempt{
		ssid:     req.SSID,
		netPath:  networkPath,
		saved:    saved,
		start:    time.Now(),
		deadline: time.Now().Add(15 * time.Second),
	}

	b.attemptMutex.Lock()
	b.curAttempt = att
	b.attemptMutex.Unlock()

	b.stateMutex.Lock()
	b.state.IsConnecting = true
	b.state.ConnectingSSID = req.SSID
	b.state.LastError = ""
	b.stateMutex.Unlock()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	netObj := b.conn.Object(iwdBusName, networkPath)
	go func() {
		call := netObj.Call(iwdNetworkInterface+".Connect", 0)
		if call.Err != nil {
			var code string
			if dbusErr, ok := call.Err.(dbus.Error); ok {
				code = b.mapIwdDBusError(dbusErr.Name)
			} else if dbusErrPtr, ok := call.Err.(*dbus.Error); ok {
				code = b.mapIwdDBusError(dbusErrPtr.Name)
			} else {
				code = errdefs.ErrConnectionFailed
			}

			att.mu.Lock()
			if att.sawPromptRetry {
				code = errdefs.ErrBadCredentials
			}
			att.mu.Unlock()

			b.finalizeAttempt(att, code)
			return
		}

		b.startAttemptWatchdog(att)
	}()

	return nil
}

func (b *IWDBackend) findNetworkPath(ssid string) (dbus.ObjectPath, bool, error) {
	obj := b.conn.Object(iwdBusName, iwdObjectPath)

	var objects map[dbus.ObjectPath]map[string]map[string]dbus.Variant
	err := obj.Call(dbusObjectManager+".GetManagedObjects", 0).Store(&objects)
	if err != nil {
		return "", false, err
	}

	var netPath dbus.ObjectPath
	saved := false
	for path, interfaces := range objects {
		if netProps, ok := interfaces[iwdNetworkInterface]; ok {
			if nameVar, ok := netProps["Name"]; ok {
				if name, ok := nameVar.Value().(string); ok && name == ssid {
					netPath = path
				}
			}
		}
		if knownProps, ok := interfaces[iwdKnownNetworkInterface]; ok {
			if nameVar, ok := knownProps["Name"]; ok {
				if name, ok := nameVar.Value().(string); ok && name == ssid {
					saved = true
				}
			}
		}
	}

	if netPath == "" {
		return "", false, fmt.Errorf("network not found")
	}

	return netPath, saved, nil
}

func (b *IWDBackend) DisconnectWiFi() error {
	if b.stationPath == "" {
		return fmt.Errorf("no WiFi device available")
	}

	obj := b.conn.Object(iwdBusName, b.stationPath)
	call := obj.Call(iwdStationInterface+".Disconnect", 0)
	if call.Err != nil {
		return fmt.Errorf("failed to disconnect: %w", call.Err)
	}

	b.updateState()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

func (b *IWDBackend) abortInFlightConnection(ssid string) {
	b.stateMutex.Lock()
	if !b.state.IsConnecting || b.state.ConnectingSSID != ssid {
		b.stateMutex.Unlock()
		return
	}
	b.state.IsConnecting = false
	b.state.ConnectingSSID = ""
	b.state.LastError = ""
	b.stateMutex.Unlock()

	b.attemptMutex.RLock()
	att := b.curAttempt
	b.attemptMutex.RUnlock()

	if att != nil && att.ssid == ssid {
		att.mu.Lock()
		att.finalized = true
		att.mu.Unlock()
	}

	if err := b.DisconnectWiFi(); err != nil {
		log.Warnf("[abortInFlightConnection] failed to abort connection to %s: %v", ssid, err)
	}
}

func (b *IWDBackend) ForgetWiFiNetwork(ssid string) error {
	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	isConnected := b.state.WiFiConnected
	b.stateMutex.RUnlock()

	obj := b.conn.Object(iwdBusName, iwdObjectPath)

	var objects map[dbus.ObjectPath]map[string]map[string]dbus.Variant
	err := obj.Call(dbusObjectManager+".GetManagedObjects", 0).Store(&objects)
	if err != nil {
		return err
	}

	for path, interfaces := range objects {
		if knownProps, ok := interfaces[iwdKnownNetworkInterface]; ok {
			if nameVar, ok := knownProps["Name"]; ok {
				if name, ok := nameVar.Value().(string); ok && name == ssid {
					knownObj := b.conn.Object(iwdBusName, path)
					call := knownObj.Call(iwdKnownNetworkInterface+".Forget", 0)
					if call.Err != nil {
						return fmt.Errorf("failed to forget network: %w", call.Err)
					}

					if isConnected && currentSSID == ssid {
						b.stateMutex.Lock()
						b.state.WiFiConnected = false
						b.state.WiFiSSID = ""
						b.state.WiFiSignal = 0
						b.state.WiFiIP = ""
						b.state.NetworkStatus = StatusDisconnected
						b.stateMutex.Unlock()
					}

					_, _ = b.updateWiFiNetworks()

					if b.onStateChange != nil {
						b.onStateChange()
					}

					return nil
				}
			}
		}
	}

	return fmt.Errorf("network not found")
}

func (b *IWDBackend) SetWiFiAutoconnect(ssid string, autoconnect bool) error {
	obj := b.conn.Object(iwdBusName, iwdObjectPath)

	var objects map[dbus.ObjectPath]map[string]map[string]dbus.Variant
	err := obj.Call(dbusObjectManager+".GetManagedObjects", 0).Store(&objects)
	if err != nil {
		return err
	}

	for path, interfaces := range objects {
		if knownProps, ok := interfaces[iwdKnownNetworkInterface]; ok {
			if nameVar, ok := knownProps["Name"]; ok {
				if name, ok := nameVar.Value().(string); ok && name == ssid {
					knownObj := b.conn.Object(iwdBusName, path)
					call := knownObj.Call(dbusPropertiesInterface+".Set", 0, iwdKnownNetworkInterface, "AutoConnect", dbus.MakeVariant(autoconnect))
					if call.Err != nil {
						return fmt.Errorf("failed to set autoconnect: %w", call.Err)
					}

					if !autoconnect {
						b.abortInFlightConnection(ssid)
					}

					b.updateState()

					if b.onStateChange != nil {
						b.onStateChange()
					}

					return nil
				}
			}
		}
	}

	return fmt.Errorf("network not found")
}
