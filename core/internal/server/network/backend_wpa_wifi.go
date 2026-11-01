package network

import (
	"encoding/hex"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

type wpaScanResult struct {
	BSSID     string
	Frequency uint32
	Level     int
	Flags     string
	SSID      string
}

type wpaStatus struct {
	wpaState  string
	ssid      string
	bssid     string
	ipAddress string
	keyMgmt   string
	networkID int
}

type wpaSavedNetwork struct {
	id           int
	ssid         string
	bssid        string
	current      bool
	disabled     bool
	tempDisabled bool
}

func signalPercentFromDbm(dbm int) uint8 {
	switch {
	case dbm > 0:
		return 100
	case dbm < -100:
		return 0
	default:
		return uint8(dbm + 100)
	}
}

// decodeWpaSSIDText reverses printf_encode from contrib/wpa/src/utils/common.c
// (freebsd-src), which wpa_supplicant applies to SSIDs in ctrl replies/events.
func decodeWpaSSIDText(s string) string {
	if !strings.ContainsRune(s, '\\') {
		return s
	}

	var out strings.Builder
	out.Grow(len(s))
	for i := 0; i < len(s); i++ {
		if s[i] != '\\' || i+1 >= len(s) {
			out.WriteByte(s[i])
			continue
		}
		i++
		switch s[i] {
		case '"':
			out.WriteByte('"')
		case '\\':
			out.WriteByte('\\')
		case 'e':
			out.WriteByte(0x1b)
		case 'n':
			out.WriteByte('\n')
		case 'r':
			out.WriteByte('\r')
		case 't':
			out.WriteByte('\t')
		case 'x':
			if i+2 < len(s) {
				if v, err := strconv.ParseUint(s[i+1:i+3], 16, 8); err == nil {
					out.WriteByte(byte(v))
					i += 2
					continue
				}
			}
			out.WriteByte('\\')
			out.WriteByte('x')
		default:
			out.WriteByte('\\')
			out.WriteByte(s[i])
		}
	}
	return out.String()
}

// SET_NETWORK string values are either quoted literals (no escape handling,
// content runs to the last '"') or unquoted hex; see wpa_config_parse_string
// in contrib/wpa/src/utils/common.c (freebsd-src).
func wpaQuotedString(s string) (string, error) {
	if strings.ContainsAny(s, "\"\n\r") {
		return "", fmt.Errorf("value cannot contain quotes or newlines")
	}
	return `"` + s + `"`, nil
}

func wpaHexString(s string) string {
	return hex.EncodeToString([]byte(s))
}

func parseWpaScanResults(text string) []wpaScanResult {
	var results []wpaScanResult
	for line := range strings.SplitSeq(text, "\n") {
		if line == "" || strings.HasPrefix(line, "bssid /") {
			continue
		}

		fields := strings.SplitN(line, "\t", 5)
		if len(fields) < 4 {
			continue
		}

		freq, err := strconv.ParseUint(fields[1], 10, 32)
		if err != nil {
			continue
		}
		level, err := strconv.Atoi(fields[2])
		if err != nil {
			continue
		}

		ssid := ""
		if len(fields) == 5 {
			ssid = decodeWpaSSIDText(fields[4])
		}

		results = append(results, wpaScanResult{
			BSSID:     fields[0],
			Frequency: uint32(freq),
			Level:     level,
			Flags:     fields[3],
			SSID:      ssid,
		})
	}
	return results
}

func wpaFlagsSecured(flags string) bool {
	return strings.Contains(flags, "WPA") || strings.Contains(flags, "WEP")
}

func wpaFlagsEnterprise(flags string) bool {
	return strings.Contains(flags, "-EAP")
}

func wpaWiFiNetworksFromScanResults(results []wpaScanResult) []WiFiNetwork {
	best := make(map[string]WiFiNetwork, len(results))
	for _, result := range results {
		if result.SSID == "" {
			continue
		}

		mode := "infrastructure"
		if strings.Contains(result.Flags, "[IBSS]") {
			mode = "adhoc"
		}

		network := WiFiNetwork{
			SSID:       result.SSID,
			BSSID:      result.BSSID,
			Signal:     signalPercentFromDbm(result.Level),
			Secured:    wpaFlagsSecured(result.Flags),
			Enterprise: wpaFlagsEnterprise(result.Flags),
			Frequency:  result.Frequency,
			Channel:    frequencyToChannel(result.Frequency),
			Mode:       mode,
		}

		if existing, ok := best[result.SSID]; ok && existing.Signal >= network.Signal {
			continue
		}
		best[result.SSID] = network
	}

	networks := make([]WiFiNetwork, 0, len(best))
	for _, network := range best {
		networks = append(networks, network)
	}
	return networks
}

func parseWpaStatus(text string) wpaStatus {
	st := wpaStatus{networkID: -1}
	for line := range strings.SplitSeq(text, "\n") {
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}

		switch key {
		case "wpa_state":
			st.wpaState = value
		case "ssid":
			st.ssid = decodeWpaSSIDText(value)
		case "bssid":
			st.bssid = value
		case "ip_address":
			st.ipAddress = value
		case "key_mgmt":
			st.keyMgmt = value
		case "id":
			if id, err := strconv.Atoi(value); err == nil {
				st.networkID = id
			}
		}
	}
	return st
}

func parseWpaSignalPollRSSI(text string) (int, bool) {
	for line := range strings.SplitSeq(text, "\n") {
		value, ok := strings.CutPrefix(line, "RSSI=")
		if !ok {
			continue
		}
		rssi, err := strconv.Atoi(value)
		if err != nil {
			return 0, false
		}
		return rssi, true
	}
	return 0, false
}

func parseWpaListNetworks(text string) []wpaSavedNetwork {
	var networks []wpaSavedNetwork
	for line := range strings.SplitSeq(text, "\n") {
		if line == "" || strings.HasPrefix(line, "network id /") {
			continue
		}

		fields := strings.SplitN(line, "\t", 4)
		if len(fields) < 3 {
			continue
		}

		id, err := strconv.Atoi(fields[0])
		if err != nil {
			continue
		}

		flags := ""
		if len(fields) == 4 {
			flags = fields[3]
		}

		networks = append(networks, wpaSavedNetwork{
			id:           id,
			ssid:         decodeWpaSSIDText(fields[1]),
			bssid:        fields[2],
			current:      strings.Contains(flags, "[CURRENT]"),
			disabled:     strings.Contains(flags, "[DISABLED]"),
			tempDisabled: strings.Contains(flags, "[TEMP-DISABLED]"),
		})
	}
	return networks
}

func (b *WpaSupplicantBackend) requestOK(cmd string) error {
	reply, err := b.cmd.request(cmd)
	if err != nil {
		return err
	}
	if reply != "OK" {
		return fmt.Errorf("%s failed: %s", strings.Fields(cmd)[0], reply)
	}
	return nil
}

func (b *WpaSupplicantBackend) setNetworkValue(id int, name, value string) error {
	return b.requestOK(fmt.Sprintf("SET_NETWORK %d %s %s", id, name, value))
}

func (b *WpaSupplicantBackend) getNetworkValue(id int, name string) (string, error) {
	reply, err := b.cmd.request(fmt.Sprintf("GET_NETWORK %d %s", id, name))
	if err != nil {
		return "", err
	}
	if reply == "FAIL" {
		return "", fmt.Errorf("GET_NETWORK %d %s failed", id, name)
	}
	return reply, nil
}

// SAVE_CONFIG is refused unless the daemon config sets update_config=1
// (wpa_supplicant_ctrl_iface_save_config in contrib/wpa/wpa_supplicant/
// ctrl_iface.c, freebsd-src); runtime changes still apply, so only warn.
func (b *WpaSupplicantBackend) saveConfig() {
	reply, err := b.cmd.request("SAVE_CONFIG")
	if err != nil {
		log.Warnf("wpa_supplicant SAVE_CONFIG failed: %v", err)
		return
	}
	if reply != "OK" {
		log.Warnf("wpa_supplicant SAVE_CONFIG rejected (requires update_config=1): %s", reply)
	}
}

func (b *WpaSupplicantBackend) removeNetworkQuiet(id int) {
	if err := b.requestOK(fmt.Sprintf("REMOVE_NETWORK %d", id)); err != nil {
		log.Warnf("failed to remove wpa network %d: %v", id, err)
		return
	}
	b.saveConfig()
}

func (b *WpaSupplicantBackend) updateState() error {
	if b.cmd == nil {
		return nil
	}

	reply, err := b.cmd.request("STATUS")
	if err != nil {
		return fmt.Errorf("STATUS failed: %w", err)
	}
	st := parseWpaStatus(reply)
	connected := st.wpaState == "COMPLETED"

	var signal uint8
	if connected {
		if pollReply, err := b.cmd.request("SIGNAL_POLL"); err == nil {
			if rssi, ok := parseWpaSignalPollRSSI(pollReply); ok {
				signal = signalPercentFromDbm(rssi)
			}
		}
	}

	wifiIP := interfaceIPv4(b.ifname)
	if wifiIP == "" {
		wifiIP = st.ipAddress
	}

	ethDevices := b.ethernetDevices()
	var ethDevice, ethIP string
	ethConnected := false
	for _, dev := range ethDevices {
		ethDevice = dev.Name
		if dev.Connected {
			ethConnected = true
			ethIP = dev.IP
			break
		}
	}

	b.stateMutex.Lock()
	b.state.WiFiConnected = connected
	b.state.WiFiSignal = signal
	if connected {
		b.state.WiFiSSID = st.ssid
		b.state.WiFiBSSID = st.bssid
		b.state.WiFiIP = wifiIP
	} else {
		b.state.WiFiSSID = ""
		b.state.WiFiBSSID = ""
		b.state.WiFiIP = ""
	}
	b.state.EthernetDevices = ethDevices
	b.state.EthernetDevice = ethDevice
	b.state.EthernetConnected = ethConnected
	b.state.EthernetIP = ethIP
	b.state.WiredConnections = wiredConnectionsFromEthernetDevices(ethDevices)

	switch {
	case ethConnected && ethIP != "":
		b.state.NetworkStatus = StatusEthernet
	case connected:
		b.state.NetworkStatus = StatusWiFi
	default:
		b.state.NetworkStatus = StatusDisconnected
	}
	b.stateMutex.Unlock()

	return nil
}

func (b *WpaSupplicantBackend) GetWiFiEnabled() (bool, error) {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()
	return b.state.WiFiEnabled, nil
}

// Bringing the interface itself up/down needs ifconfig(8) as root on FreeBSD;
// there is no wpa_ctrl command for it, so this backend reports it unsupported.
func (b *WpaSupplicantBackend) SetWiFiEnabled(enabled bool) error {
	if b.cmd == nil {
		return fmt.Errorf("no WiFi device available")
	}

	command := "DISCONNECT"
	if enabled {
		command = "RECONNECT"
	}

	reply, err := b.cmd.request(command)
	if err != nil {
		return fmt.Errorf("%s failed: %w", command, err)
	}

	if reply != "OK" {
		return fmt.Errorf("%s failed: %s", command, reply)
	}

	b.stateMutex.Lock()

	b.state.WiFiEnabled = enabled

	if !enabled {
		b.state.WiFiConnected = false
		b.state.WiFiSSID = ""
		b.state.WiFiBSSID = ""
		b.state.WiFiIP = ""
		b.state.WiFiSignal = 0
	}

	b.stateMutex.Unlock()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

func (b *WpaSupplicantBackend) ScanWiFi() error {
	if b.cmd == nil {
		return fmt.Errorf("no WiFi device available")
	}

	reply, err := b.cmd.request("SCAN")
	if err != nil {
		return fmt.Errorf("scan request failed: %w", err)
	}

	switch reply {
	case "OK":
		return nil
	case "FAIL-BUSY":
		return fmt.Errorf("scan already in progress")
	default:
		return fmt.Errorf("scan request failed: %s", reply)
	}
}

func (b *WpaSupplicantBackend) fetchSavedProfiles() (map[string]savedWiFiProfile, map[string]int, error) {
	reply, err := b.cmd.request("LIST_NETWORKS")
	if err != nil {
		return nil, nil, fmt.Errorf("LIST_NETWORKS failed: %w", err)
	}

	entries := parseWpaListNetworks(reply)
	profiles := make(map[string]savedWiFiProfile, len(entries))
	ids := make(map[string]int, len(entries))

	for _, entry := range entries {
		if entry.ssid == "" {
			continue
		}

		keyMgmt, err := b.getNetworkValue(entry.id, "key_mgmt")
		if err != nil {
			keyMgmt = ""
		}
		scanSSID, _ := b.getNetworkValue(entry.id, "scan_ssid")

		profile := savedWiFiProfile{
			Autoconnect: !entry.disabled,
			Hidden:      scanSSID == "1",
			Secured:     keyMgmt != "" && keyMgmt != "NONE",
			Enterprise:  strings.Contains(keyMgmt, "EAP"),
			Mode:        "infrastructure",
		}

		if existing, ok := profiles[entry.ssid]; ok {
			profile.Autoconnect = profile.Autoconnect || existing.Autoconnect
			profile.Hidden = profile.Hidden || existing.Hidden
			profile.Secured = profile.Secured || existing.Secured
			profile.Enterprise = profile.Enterprise || existing.Enterprise
		} else {
			ids[entry.ssid] = entry.id
		}

		profiles[entry.ssid] = profile
	}

	return profiles, ids, nil
}

func (b *WpaSupplicantBackend) updateWiFiNetworks() ([]WiFiNetwork, error) {
	if b.cmd == nil {
		return nil, fmt.Errorf("no WiFi device available")
	}

	reply, err := b.cmd.request("SCAN_RESULTS")
	if err != nil {
		return nil, fmt.Errorf("SCAN_RESULTS failed: %w", err)
	}
	visibleNetworks := wpaWiFiNetworksFromScanResults(parseWpaScanResults(reply))

	profiles, ids, err := b.fetchSavedProfiles()
	if err != nil {
		profiles = make(map[string]savedWiFiProfile)
	} else {
		b.storeSavedIDs(ids)
	}

	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	wifiConnected := b.state.WiFiConnected
	wifiSignal := b.state.WiFiSignal
	b.stateMutex.RUnlock()

	networks, savedNetworks := refreshSavedWiFiState(visibleNetworks, profiles, currentSSID, wifiConnected)
	networks = appendConnectedHiddenFallback(networks, profiles, currentSSID, wifiConnected, wifiSignal)
	sortWiFiNetworks(networks)

	b.stateMutex.Lock()
	b.state.WiFiNetworks = networks
	b.state.SavedWiFiNetworks = savedNetworks
	b.stateMutex.Unlock()

	now := time.Now()
	b.recentScansMu.Lock()
	for _, network := range networks {
		b.recentScans[network.SSID] = now
	}
	b.recentScansMu.Unlock()

	return networks, nil
}

func appendConnectedHiddenFallback(networks []WiFiNetwork, profiles map[string]savedWiFiProfile, currentSSID string, wifiConnected bool, wifiSignal uint8) []WiFiNetwork {
	if !wifiConnected || currentSSID == "" {
		return networks
	}
	for _, network := range networks {
		if network.SSID == currentSSID {
			return networks
		}
	}

	profile, saved := profiles[currentSSID]
	return append(networks, WiFiNetwork{
		SSID:        currentSSID,
		Signal:      wifiSignal,
		Secured:     profile.Secured || !saved,
		Enterprise:  profile.Enterprise,
		Connected:   true,
		Saved:       saved,
		Autoconnect: profile.Autoconnect,
		Hidden:      true,
		Mode:        "infrastructure",
	})
}

func (b *WpaSupplicantBackend) updateSavedWiFiNetworks() error {
	profiles, ids, err := b.fetchSavedProfiles()
	if err != nil {
		return err
	}
	b.storeSavedIDs(ids)

	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	wifiConnected := b.state.WiFiConnected
	wifiNetworks := append([]WiFiNetwork(nil), b.state.WiFiNetworks...)
	b.stateMutex.RUnlock()

	wifiNetworks, savedNetworks := refreshSavedWiFiState(wifiNetworks, profiles, currentSSID, wifiConnected)

	b.stateMutex.Lock()
	b.state.WiFiNetworks = wifiNetworks
	b.state.SavedWiFiNetworks = savedNetworks
	b.stateMutex.Unlock()

	return nil
}

func (b *WpaSupplicantBackend) GetWiFiNetworkDetails(ssid string) (*NetworkInfoResponse, error) {
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

func (b *WpaSupplicantBackend) visibleNetwork(ssid string) (WiFiNetwork, bool) {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()

	for _, network := range b.state.WiFiNetworks {
		if network.SSID == ssid && !network.OutOfRange {
			return network, true
		}
	}
	return WiFiNetwork{}, false
}

func (b *WpaSupplicantBackend) classifyAttempt(att *wpaConnectAttempt) string {
	att.mu.Lock()
	defer att.mu.Unlock()

	switch {
	case att.sawTempDisabled:
		return errdefs.ErrBadCredentials
	case !b.seenInRecentScan(att.ssid):
		return errdefs.ErrNoSuchSSID
	default:
		return errdefs.ErrAssocTimeout
	}
}

func (b *WpaSupplicantBackend) finalizeAttempt(att *wpaConnectAttempt, code string) {
	att.mu.Lock()
	if att.finalized {
		att.mu.Unlock()
		return
	}
	att.finalized = true
	newlyAdded := att.newlyAdded
	netID := att.netID
	att.mu.Unlock()

	if code != "" && newlyAdded {
		b.removeNetworkQuiet(netID)
	}

	b.stateMutex.Lock()
	b.state.IsConnecting = false
	b.state.ConnectingSSID = ""
	b.state.LastError = code
	b.stateMutex.Unlock()

	if err := b.updateState(); err != nil {
		log.Warnf("failed to update wpa state after connect attempt: %v", err)
	}
	if err := b.updateSavedWiFiNetworks(); err != nil {
		log.Warnf("failed to refresh saved networks after connect attempt: %v", err)
	}

	if b.onStateChange != nil {
		b.onStateChange()
	}

	if code == errdefs.ErrBadCredentials {
		b.maybeReplacePSK(att)
	}
}

func (b *WpaSupplicantBackend) maybeReplacePSK(att *wpaConnectAttempt) {
	if b.promptBroker == nil {
		return
	}

	att.mu.Lock()
	prompted := att.prompted
	ssid := att.ssid
	att.mu.Unlock()
	if prompted {
		return
	}

	b.sigWG.Go(func() {

		psk, ok := b.promptForPSK(ssid, "wrong-password")
		if !ok {
			return
		}

		if err := b.ConnectWiFi(ConnectionRequest{SSID: ssid, Password: psk}); err != nil {
			log.Warnf("failed to reconnect %s with replacement credentials: %v", ssid, err)
		}
	})
}

func (b *WpaSupplicantBackend) startAttemptWatchdog(att *wpaConnectAttempt) {
	b.sigWG.Go(func() {

		timer := time.NewTimer(time.Until(att.deadline))
		defer timer.Stop()

		select {
		case <-timer.C:
			att.mu.Lock()
			finalized := att.finalized
			att.mu.Unlock()
			if finalized {
				return
			}
			b.finalizeAttempt(att, b.classifyAttempt(att))
		case <-b.stopChan:
		}
	})
}

func (b *WpaSupplicantBackend) ConnectWiFi(req ConnectionRequest) error {
	if b.cmd == nil {
		b.setConnectError(errdefs.ErrWifiDisabled)
		if b.onStateChange != nil {
			b.onStateChange()
		}
		return fmt.Errorf("no WiFi device available")
	}

	savedID, saved := b.savedNetworkID(req.SSID)
	visible, inRange := b.visibleNetwork(req.SSID)
	if !saved && !inRange && !req.Hidden {
		b.setConnectError(errdefs.ErrNoSuchSSID)
		if b.onStateChange != nil {
			b.onStateChange()
		}
		return fmt.Errorf("network not found: %s", req.SSID)
	}

	att := &wpaConnectAttempt{
		ssid:     req.SSID,
		netID:    savedID,
		saved:    saved,
		deadline: time.Now().Add(30 * time.Second),
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

	secured := visible.Secured || (req.Hidden && req.Password != "")

	b.sigWG.Go(func() {
		b.runConnectAttempt(att, req, secured)
	})

	return nil
}

func (b *WpaSupplicantBackend) runConnectAttempt(att *wpaConnectAttempt, req ConnectionRequest, secured bool) {
	password := req.Password
	if password == "" && secured && !att.saved {
		psk, ok := b.promptForPSK(req.SSID, "")
		if !ok {
			b.finalizeAttempt(att, errdefs.ErrUserCanceled)
			return
		}
		att.mu.Lock()
		att.prompted = true
		att.mu.Unlock()
		password = psk
	}

	if err := b.applyConnectCommands(att, password, req.Hidden); err != nil {
		log.Warnf("wpa_supplicant connect to %s failed: %v", req.SSID, err)
		b.finalizeAttempt(att, errdefs.ErrConnectionFailed)
		return
	}

	b.startAttemptWatchdog(att)
}

func (b *WpaSupplicantBackend) applyConnectCommands(att *wpaConnectAttempt, password string, hidden bool) error {
	if att.saved {
		if password != "" {
			quoted, err := wpaQuotedString(password)
			if err != nil {
				return fmt.Errorf("invalid passphrase: %w", err)
			}
			if err := b.setNetworkValue(att.netID, "psk", quoted); err != nil {
				return err
			}
		}
		if err := b.requestOK(fmt.Sprintf("SELECT_NETWORK %d", att.netID)); err != nil {
			return err
		}
		if password != "" {
			b.saveConfig()
		}
		return nil
	}

	reply, err := b.cmd.request("ADD_NETWORK")
	if err != nil {
		return fmt.Errorf("ADD_NETWORK failed: %w", err)
	}
	id, err := strconv.Atoi(reply)
	if err != nil {
		return fmt.Errorf("ADD_NETWORK failed: %s", reply)
	}

	att.mu.Lock()
	att.netID = id
	att.newlyAdded = true
	att.mu.Unlock()

	if err := b.setNetworkValue(id, "ssid", wpaHexString(att.ssid)); err != nil {
		b.removeNetworkQuiet(id)
		return err
	}
	if hidden {
		if err := b.setNetworkValue(id, "scan_ssid", "1"); err != nil {
			b.removeNetworkQuiet(id)
			return err
		}
	}

	if password == "" {
		if err := b.setNetworkValue(id, "key_mgmt", "NONE"); err != nil {
			b.removeNetworkQuiet(id)
			return err
		}
	} else {
		quoted, err := wpaQuotedString(password)
		if err != nil {
			b.removeNetworkQuiet(id)
			return fmt.Errorf("invalid passphrase: %w", err)
		}
		if err := b.setNetworkValue(id, "psk", quoted); err != nil {
			b.removeNetworkQuiet(id)
			return err
		}
	}

	if err := b.requestOK(fmt.Sprintf("ENABLE_NETWORK %d", id)); err != nil {
		b.removeNetworkQuiet(id)
		return err
	}
	b.saveConfig()

	return nil
}

// DISCONNECT stays in effect until RECONNECT/REASSOCIATE
// (https://w1.fi/wpa_supplicant/devel/ctrl_iface_page.html); a later
// SELECT_NETWORK from ConnectWiFi also resumes association.
func (b *WpaSupplicantBackend) DisconnectWiFi() error {
	if b.cmd == nil {
		return fmt.Errorf("no WiFi device available")
	}

	if err := b.requestOK("DISCONNECT"); err != nil {
		return fmt.Errorf("failed to disconnect: %w", err)
	}

	if err := b.updateState(); err != nil {
		log.Warnf("failed to update wpa state after disconnect: %v", err)
	}

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

func (b *WpaSupplicantBackend) ForgetWiFiNetwork(ssid string) error {
	id, ok := b.savedNetworkID(ssid)
	if !ok {
		return fmt.Errorf("network not found")
	}

	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	isConnected := b.state.WiFiConnected
	b.stateMutex.RUnlock()

	if err := b.requestOK(fmt.Sprintf("REMOVE_NETWORK %d", id)); err != nil {
		return fmt.Errorf("failed to forget network: %w", err)
	}
	b.saveConfig()

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

	if _, err := b.updateWiFiNetworks(); err != nil {
		log.Warnf("failed to refresh networks after forget: %v", err)
	}

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

func (b *WpaSupplicantBackend) SetWiFiAutoconnect(ssid string, autoconnect bool) error {
	id, ok := b.savedNetworkID(ssid)
	if !ok {
		return fmt.Errorf("network not found")
	}

	cmd := fmt.Sprintf("DISABLE_NETWORK %d", id)
	if autoconnect {
		cmd = fmt.Sprintf("ENABLE_NETWORK %d", id)
	}
	if err := b.requestOK(cmd); err != nil {
		return fmt.Errorf("failed to set autoconnect: %w", err)
	}
	b.saveConfig()

	if err := b.updateSavedWiFiNetworks(); err != nil {
		log.Warnf("failed to refresh saved networks after autoconnect change: %v", err)
	}

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return nil
}

// GET_NETWORK masks secrets (wpa_config_get_no_key), so the passphrase for QR
// codes must come from a readable wpa_supplicant config file.
func (b *WpaSupplicantBackend) GetWiFiQRCodeContent(ssid string) (string, error) {
	for _, path := range wpaConfigCandidatePaths(b.ifname) {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}

		passphrase, err := parseWpaConfigPassphrase(string(data), ssid)
		if err != nil {
			continue
		}

		return FormatWiFiQRString("WPA", ssid, passphrase), nil
	}

	return "", fmt.Errorf("no readable wpa_supplicant config with passphrase for `%s`", ssid)
}

// /etc/wpa_supplicant.conf is the FreeBSD default (wpa_supplicant(8),
// man.freebsd.org); the /etc/wpa_supplicant/ variants are the common Linux
// layout including systemd's wpa_supplicant@<ifname>.service.
func wpaConfigCandidatePaths(ifname string) []string {
	return []string{
		"/etc/wpa_supplicant.conf",
		fmt.Sprintf("/etc/wpa_supplicant/wpa_supplicant-%s.conf", ifname),
		"/etc/wpa_supplicant/wpa_supplicant.conf",
	}
}

func parseWpaConfigPassphrase(data, ssid string) (string, error) {
	inBlock := false
	var blockSSID, blockPSK string

	for line := range strings.SplitSeq(data, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "#") {
			continue
		}

		switch {
		case strings.HasPrefix(line, "network={"):
			inBlock = true
			blockSSID = ""
			blockPSK = ""
		case inBlock && line == "}":
			if blockSSID == ssid && blockPSK != "" {
				return blockPSK, nil
			}
			inBlock = false
		case inBlock:
			key, value, ok := strings.Cut(line, "=")
			if !ok {
				continue
			}
			switch strings.TrimSpace(key) {
			case "ssid":
				blockSSID = parseWpaConfigString(strings.TrimSpace(value))
			case "psk":
				// Unquoted psk is a raw 256-bit key in hex, not a passphrase;
				// only quoted values are usable for QR content.
				trimmed := strings.TrimSpace(value)
				if strings.HasPrefix(trimmed, `"`) {
					blockPSK = parseWpaConfigString(trimmed)
				}
			}
		}
	}

	return "", fmt.Errorf("no passphrase found for `%s`", ssid)
}

func parseWpaConfigString(value string) string {
	if strings.HasPrefix(value, `"`) {
		end := strings.LastIndexByte(value[1:], '"')
		if end < 0 {
			return ""
		}
		return value[1 : end+1]
	}

	decoded, err := hex.DecodeString(value)
	if err != nil {
		return ""
	}
	return string(decoded)
}
