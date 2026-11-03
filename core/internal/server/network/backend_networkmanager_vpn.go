package network

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const nmVPNStateFailed = 6

// vpnFailureMessage maps NMVpnConnectionStateReason to a user-facing message.
func vpnFailureMessage(reason uint32) string {
	switch reason {
	case 9: // NO_SECRETS
		return "Authentication required"
	case 10: // LOGIN_FAILED
		return "Authentication failed"
	case 6: // CONNECT_TIMEOUT
		return "Connection timed out"
	case 7, 8: // SERVICE_START_TIMEOUT, SERVICE_START_FAILED
		return "VPN service failed to start"
	default:
		return "VPN connection failed"
	}
}

func (b *NetworkManagerBackend) ListVPNProfiles() ([]VPNProfile, error) {
	s := b.settings
	if s == nil {
		var err error
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

	profiles := []VPNProfile{}
	for _, conn := range connections {
		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}

		connMeta, ok := settings["connection"]
		if !ok {
			continue
		}

		connType, _ := connMeta["type"].(string)
		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		connID, _ := connMeta["id"].(string)
		connUUID, _ := connMeta["uuid"].(string)
		autoconnect, _ := connMeta["autoconnect"].(bool)

		profile := VPNProfile{
			Name:        connID,
			UUID:        connUUID,
			Type:        connType,
			Autoconnect: autoconnect,
		}

		if connType == "vpn" {
			if vpnSettings, ok := settings["vpn"]; ok {
				if svcType, ok := vpnSettings["service-type"].(string); ok {
					profile.ServiceType = svcType
				}
				// Get full data map
				if data, ok := vpnSettings["data"].(map[string]string); ok {
					profile.Data = data
					if remote, ok := data["remote"]; ok {
						profile.RemoteHost = remote
					}
					if username, ok := data["username"]; ok {
						profile.Username = username
					}
				}
			}
		}

		profiles = append(profiles, profile)
	}

	sort.Slice(profiles, func(i, j int) bool {
		return strings.ToLower(profiles[i].Name) < strings.ToLower(profiles[j].Name)
	})

	b.stateMutex.Lock()
	b.state.VPNProfiles = profiles
	b.stateMutex.Unlock()

	return profiles, nil
}

func (b *NetworkManagerBackend) ListActiveVPN() ([]VPNActive, error) {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)

	activeConns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to get active connections: %w", err)
	}

	active := []VPNActive{}
	for _, activeConn := range activeConns {
		connType, err := activeConn.GetPropertyType()
		if err != nil {
			continue
		}

		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		uuid, _ := activeConn.GetPropertyUUID()
		id, _ := activeConn.GetPropertyID()
		state, _ := activeConn.GetPropertyState()

		var stateStr string
		switch state {
		case 0:
			stateStr = "unknown"
		case 1:
			stateStr = "activating"
		case 2:
			stateStr = "activated"
		case 3:
			stateStr = "deactivating"
		case 4:
			stateStr = "deactivated"
		}

		vpnActive := VPNActive{
			Name:   id,
			UUID:   uuid,
			State:  stateStr,
			Type:   connType,
			Plugin: "",
		}

		// Get VPN device
		devices, _ := activeConn.GetPropertyDevices()
		if len(devices) > 0 {
			if iface, err := devices[0].GetPropertyInterface(); err == nil {
				vpnActive.Device = iface
			}
		}

		// Get VPN IP from IP4Config
		if ip4Config, err := activeConn.GetPropertyIP4Config(); err == nil && ip4Config != nil {
			if addrData, err := ip4Config.GetPropertyAddressData(); err == nil && len(addrData) > 0 {
				vpnActive.IP = addrData[0].Address
			}
			if gw, err := ip4Config.GetPropertyGateway(); err == nil {
				vpnActive.Gateway = gw
			}
		}

		// Get MTU from device
		if len(devices) > 0 {
			if mtu, err := devices[0].GetPropertyMtu(); err == nil {
				vpnActive.MTU = mtu
			}
		}

		if connType == "vpn" {
			conn, _ := activeConn.GetPropertyConnection()
			if conn != nil {
				connSettings, err := conn.GetSettings()
				if err == nil {
					if vpnSettings, ok := connSettings["vpn"]; ok {
						if svcType, ok := vpnSettings["service-type"].(string); ok {
							vpnActive.Plugin = svcType
						}
						// Get full data map
						if data, ok := vpnSettings["data"].(map[string]string); ok {
							vpnActive.Data = data
							if remote, ok := data["remote"]; ok {
								vpnActive.RemoteHost = remote
							}
							if username, ok := data["username"]; ok {
								vpnActive.Username = username
							}
						}
					}
				}
			}
		}

		active = append(active, vpnActive)
	}

	b.stateMutex.Lock()
	b.state.VPNActive = active
	b.stateMutex.Unlock()

	return active, nil
}

func (b *NetworkManagerBackend) ConnectVPN(uuidOrName string, singleActive bool) error {
	// Drop any stale connecting state from a prior attempt that never resolved;
	// a leftover flag makes the secret agent refuse secrets for other VPNs.
	b.stateMutex.Lock()
	b.state.IsConnectingVPN = false
	b.state.ConnectingVPNUUID = ""
	b.state.VPNError = ""
	b.state.VPNErrorUuid = ""
	b.stateMutex.Unlock()

	if singleActive {
		active, err := b.ListActiveVPN()
		if err == nil && len(active) > 0 {
			alreadyConnected := false
			for _, vpn := range active {
				if vpn.UUID != uuidOrName && vpn.Name != uuidOrName {
					continue
				}
				switch vpn.State {
				case "activated", "activating":
					alreadyConnected = true
				}
				break
			}

			if alreadyConnected {
				return nil
			}

			if err := b.DisconnectAllVPN(); err != nil {
				log.Warnf("Failed to disconnect existing VPNs: %v", err)
			}
			time.Sleep(500 * time.Millisecond)
		}
	}

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

	var targetConn gonetworkmanager.Connection
	for _, conn := range connections {
		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}

		connMeta, ok := settings["connection"]
		if !ok {
			continue
		}

		connType, _ := connMeta["type"].(string)
		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		connID, _ := connMeta["id"].(string)
		connUUID, _ := connMeta["uuid"].(string)

		if connUUID == uuidOrName || connID == uuidOrName {
			targetConn = conn
			break
		}
	}

	if targetConn == nil {
		return fmt.Errorf("VPN connection not found: %s", uuidOrName)
	}

	targetSettings, err := targetConn.GetSettings()
	if err != nil {
		return fmt.Errorf("failed to get connection settings: %w", err)
	}

	var targetUUID string
	var connName string
	if connMeta, ok := targetSettings["connection"]; ok {
		if uuid, ok := connMeta["uuid"].(string); ok {
			targetUUID = uuid
		}
		if id, ok := connMeta["id"].(string); ok {
			connName = id
		}
	}

	var vpnServiceType string
	var vpnData map[string]string
	if vpnSettings, ok := targetSettings["vpn"]; ok {
		if svc, ok := vpnSettings["service-type"].(string); ok {
			vpnServiceType = svc
		}
		if data, ok := vpnSettings["data"].(map[string]string); ok {
			vpnData = data
		}
	}

	authAction := detectVPNAuthAction(vpnServiceType, vpnData)
	var openConnectAuth *openConnectAuthResult

	switch authAction {
	case "openvpn_username":
		if b.promptBroker == nil {
			return fmt.Errorf("OpenVPN password authentication requires interactive prompt")
		}
		if err := b.handleOpenVPNUsernameAuth(targetConn, connName, targetUUID, vpnServiceType); err != nil {
			return err
		}
	case "openconnect_password":
		if err := b.ensureOpenConnectAgentFlags(targetConn, vpnData); err != nil {
			return fmt.Errorf("failed to prepare OpenConnect connection: %w", err)
		}

		authCtx, authCancel := context.WithTimeout(context.Background(), 5*time.Minute)
		openConnectAuth, err = b.handleOpenConnectPasswordAuth(
			authCtx, targetConn, connName, targetUUID, vpnServiceType, vpnData,
		)
		authCancel()
		if err != nil {
			return fmt.Errorf("OpenConnect authentication failed: %w", err)
		}
	case "fortinet_saml":
		if err := b.ensureOpenConnectAgentFlags(targetConn, vpnData); err != nil {
			return fmt.Errorf("failed to prepare Fortinet connection: %w", err)
		}

		log.Infof("[ConnectVPN] Fortinet SAML/SSO authentication required for %s (gateway=%s)", connName, vpnData["gateway"])

		samlCtx, samlCancel := context.WithTimeout(context.Background(), 5*time.Minute)
		openConnectAuth, err = b.authenticateFortinetSAML(samlCtx, fortinetAuthTarget{
			ConnName:       connName,
			ConnUUID:       targetUUID,
			ConnectionPath: string(targetConn.GetPath()),
			VpnService:     vpnServiceType,
			Data:           vpnData,
		})
		samlCancel()
		if err != nil {
			return fmt.Errorf("SAML authentication failed for the Fortinet gateway: %w", err)
		}
	case "gp_saml":
		gateway := vpnData["gateway"]
		protocol := vpnData["protocol"]
		if protocol != "gp" {
			return fmt.Errorf("GlobalProtect SAML authentication only supported for protocol=gp, got: %s", protocol)
		}

		log.Infof("[ConnectVPN] GlobalProtect SAML/SSO authentication required for %s (gateway=%s)", connName, gateway)

		samlCtx, samlCancel := context.WithTimeout(context.Background(), 5*time.Minute)
		openConnectAuth, err = b.runGlobalProtectSAMLAuth(samlCtx, gateway, protocol)
		samlCancel()
		if err != nil {
			errMsg := err.Error()
			switch {
			case strings.Contains(errMsg, "not installed"):
				return fmt.Errorf("gp-saml-gui is not installed (required for GlobalProtect SAML/SSO VPN)")
			case strings.Contains(errMsg, "timed out") || strings.Contains(errMsg, "cancelled"):
				return fmt.Errorf("GlobalProtect SAML authentication timed out — please try again")
			case strings.Contains(errMsg, "no cookie"):
				return fmt.Errorf("GlobalProtect SAML login did not complete — browser was closed before authentication finished")
			case strings.Contains(errMsg, "convert prelogin-cookie"):
				return fmt.Errorf("GlobalProtect VPN authentication succeeded but cookie exchange failed: %w", err)
			default:
				return fmt.Errorf("GlobalProtect SAML authentication failed: %w", err)
			}
		}

		if err := targetConn.ClearSecrets(); err != nil {
			log.Warnf("[ConnectVPN] ClearSecrets failed (non-fatal): %v", err)
		} else {
			log.Infof("[ConnectVPN] Cleared stale stored secrets for %s", connName)
		}

		log.Infof("[ConnectVPN] GlobalProtect SAML cookie cached for %s, proceeding with activation", connName)
	}

	if openConnectAuth != nil {
		b.cachedOpenConnectMu.Lock()
		b.cachedOpenConnectAuth = &cachedOpenConnectAuth{
			ConnectionUUID: targetUUID,
			Cookie:         openConnectAuth.Cookie,
			Host:           openConnectAuth.Host,
			User:           openConnectAuth.User,
			Fingerprint:    openConnectAuth.Fingerprint,
		}
		b.cachedOpenConnectMu.Unlock()
		log.Infof("[ConnectVPN] OpenConnect authentication cached for %s, proceeding with activation", connName)
	}

	b.stateMutex.Lock()
	b.state.IsConnectingVPN = true
	b.state.ConnectingVPNUUID = targetUUID
	b.stateMutex.Unlock()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	_, err = nm.ActivateConnection(targetConn, nil, nil)
	if err != nil {
		b.cachedOpenConnectMu.Lock()
		b.cachedOpenConnectAuth = nil
		b.cachedOpenConnectMu.Unlock()
		b.pendingVPNSaveMu.Lock()
		b.pendingVPNSave = nil
		b.pendingVPNSaveMu.Unlock()

		b.stateMutex.Lock()
		b.state.IsConnectingVPN = false
		b.state.ConnectingVPNUUID = ""
		b.stateMutex.Unlock()

		if b.onStateChange != nil {
			b.onStateChange()
		}

		return fmt.Errorf("failed to activate VPN: %w", err)
	}

	return nil
}

func detectVPNAuthAction(serviceType string, data map[string]string) string {
	if data == nil {
		return ""
	}

	switch {
	case strings.Contains(serviceType, "openconnect"):
		protocol := data["protocol"]
		if needsExternalBrowserAuth(protocol, data["authtype"], data["username"], data) {
			switch protocol {
			case "gp":
				return "gp_saml"
			case "fortinet":
				return "fortinet_saml"
			default:
				log.Infof("[VPN] External browser auth detected for protocol '%s' but only GlobalProtect (gp) and Fortinet are currently supported", protocol)
			}
		}
		if protocol == "fortinet" && data["authtype"] == "password" {
			return "openconnect_password"
		}
	case strings.Contains(serviceType, "openvpn"):
		connType := data["connection-type"]
		username := data["username"]
		if (connType == "password" || connType == "password-tls") && username == "" {
			return "openvpn_username"
		}
	}
	return ""
}

func setOpenConnectAgentFlags(data map[string]string) bool {
	changed := false
	for _, field := range []string{"cookie", "gateway", "gwcert"} {
		key := field + "-flags"
		if data[key] != "2" {
			data[key] = "2"
			changed = true
		}
	}
	return changed
}

func (b *NetworkManagerBackend) ensureOpenConnectAgentFlags(conn gonetworkmanager.Connection, data map[string]string) error {
	if !setOpenConnectAgentFlags(data) {
		return nil
	}
	if b.dbusConn == nil {
		return fmt.Errorf("NetworkManager D-Bus connection is unavailable")
	}

	connObj := b.dbusConn.Object("org.freedesktop.NetworkManager", conn.GetPath())
	var existingSettings map[string]map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.GetSettings", 0).Store(&existingSettings); err != nil {
		return fmt.Errorf("failed to get connection settings: %w", err)
	}

	vpn, ok := existingSettings["vpn"]
	if !ok {
		return fmt.Errorf("VPN settings are missing")
	}
	vpn["data"] = dbus.MakeVariant(data)

	var stored map[string]map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.GetSecrets", 0, "vpn").Store(&stored); err != nil {
		return fmt.Errorf("failed to preserve VPN secrets: %w", err)
	}
	if storedVPN, ok := stored["vpn"]; ok {
		if secrets, ok := storedVPN["secrets"]; ok {
			vpn["secrets"] = secrets
		}
	}

	settings := map[string]map[string]dbus.Variant{"vpn": vpn}
	if connection, ok := existingSettings["connection"]; ok {
		settings["connection"] = connection
	}

	var result map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.Update2", 0,
		settings, uint32(0x1), map[string]dbus.Variant{}).Store(&result); err != nil {
		return fmt.Errorf("failed to set NetworkManager secret-agent flags: %w", err)
	}
	return nil
}

func (b *NetworkManagerBackend) handleOpenConnectPasswordAuth(
	ctx context.Context,
	targetConn gonetworkmanager.Connection,
	connName, targetUUID, vpnServiceType string,
	data map[string]string,
) (*openConnectAuthResult, error) {
	username := data["username"]
	secrets := map[string]string{}
	if stored, err := targetConn.GetSecrets("vpn"); err == nil {
		if vpn, ok := stored["vpn"]; ok {
			if saved, ok := vpn["secrets"].(map[string]string); ok {
				secrets = saved
			}
		}
	}

	password := secrets["password"]
	serverCert := secrets["certificate:"+data["gateway"]]
	if serverCert == "" {
		serverCert = secrets["gwcert"]
	}

	var reply PromptReply
	if username == "" || password == "" {
		if b.promptBroker == nil {
			return nil, fmt.Errorf("password authentication requires an interactive prompt")
		}

		fields := []string{}
		fieldsInfo := []FieldInfo{}
		if username == "" {
			fields = append(fields, "username")
			fieldsInfo = append(fieldsInfo, FieldInfo{Name: "username", Label: "Username", IsSecret: false})
		}
		if password == "" {
			fields = append(fields, "password")
			fieldsInfo = append(fieldsInfo, FieldInfo{Name: "password", Label: "Password", IsSecret: true})
		}

		token, err := b.promptBroker.Ask(ctx, PromptRequest{
			Name:           connName,
			ConnType:       "vpn",
			VpnService:     vpnServiceType,
			SettingName:    "vpn",
			Fields:         fields,
			FieldsInfo:     fieldsInfo,
			Reason:         "required",
			ConnectionId:   connName,
			ConnectionUuid: targetUUID,
			ConnectionPath: string(targetConn.GetPath()),
		})
		if err != nil {
			return nil, fmt.Errorf("failed to request credentials: %w", err)
		}

		reply, err = b.promptBroker.Wait(ctx, token)
		if err != nil {
			return nil, fmt.Errorf("credentials prompt failed: %w", err)
		}
		if username == "" {
			username = reply.Secrets["username"]
		}
		if password == "" {
			password = reply.Secrets["password"]
		}
	}

	auth, err := runOpenConnectPasswordAuth(ctx, data, username, password, serverCert)
	persistentSecrets := map[string]string{}
	var authErr *openConnectAuthError
	if err != nil && errors.As(err, &authErr) && authErr.serverCert != "" && authErr.serverCert != serverCert {
		if b.promptBroker == nil {
			return nil, fmt.Errorf("VPN server certificate is untrusted: %s", authErr.serverCert)
		}

		reason := "server-certificate"
		if serverCert != "" {
			reason = "server-certificate-changed"
		}

		token, promptErr := b.promptBroker.Ask(ctx, PromptRequest{
			Name:           connName,
			ConnType:       "vpn",
			VpnService:     vpnServiceType,
			SettingName:    "vpn",
			Hints:          []string{authErr.serverCert},
			Reason:         reason,
			ConnectionId:   connName,
			ConnectionUuid: targetUUID,
			ConnectionPath: string(targetConn.GetPath()),
		})
		if promptErr != nil {
			return nil, fmt.Errorf("failed to request certificate confirmation: %w", promptErr)
		}
		if _, promptErr = b.promptBroker.Wait(ctx, token); promptErr != nil {
			return nil, fmt.Errorf("certificate confirmation failed: %w", promptErr)
		}

		auth, err = runOpenConnectPasswordAuth(ctx, data, username, password, authErr.serverCert)
		if err == nil {
			persistentSecrets["certificate:"+data["gateway"]] = authErr.serverCert
		}
	}
	if err != nil {
		return nil, err
	}

	if len(reply.Secrets) > 0 || len(persistentSecrets) > 0 {
		creds := &pendingVPNCredentials{
			ConnectionPath:    string(targetConn.GetPath()),
			PersistentSecrets: persistentSecrets,
		}
		if _, ok := reply.Secrets["username"]; ok {
			creds.Username = username
		}
		if reply.Save {
			creds.Username = username
			creds.Password = password
			creds.Secrets = map[string]string{"password": password}
			creds.SavePassword = true
		}
		b.pendingVPNSaveMu.Lock()
		b.pendingVPNSave = creds
		b.pendingVPNSaveMu.Unlock()
	}

	return auth, nil
}

func suggestedOpenConnectServerCert(output string) string {
	for field := range strings.FieldsSeq(output) {
		field = strings.Trim(field, "'\".,")
		if strings.HasPrefix(field, "pin-sha256:") {
			return field
		}
	}
	return ""
}

func (b *NetworkManagerBackend) handleOpenVPNUsernameAuth(targetConn gonetworkmanager.Connection, connName, targetUUID, vpnServiceType string) error {
	log.Infof("[ConnectVPN] OpenVPN requires username in vpn.data - prompting before activation")

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	token, err := b.promptBroker.Ask(ctx, PromptRequest{
		Name:           connName,
		ConnType:       "vpn",
		VpnService:     vpnServiceType,
		SettingName:    "vpn",
		Fields:         []string{"username", "password"},
		FieldsInfo:     []FieldInfo{{Name: "username", Label: "Username", IsSecret: false}, {Name: "password", Label: "Password", IsSecret: true}},
		Reason:         "required",
		ConnectionId:   connName,
		ConnectionUuid: targetUUID,
		ConnectionPath: string(targetConn.GetPath()),
	})
	if err != nil {
		return fmt.Errorf("failed to request credentials: %w", err)
	}

	reply, err := b.promptBroker.Wait(ctx, token)
	if err != nil {
		return fmt.Errorf("credentials prompt failed: %w", err)
	}

	if reply.Cancel {
		return fmt.Errorf("user cancelled authentication")
	}

	username := reply.Secrets["username"]
	password := reply.Secrets["password"]
	if username == "" {
		return nil
	}

	connObj := b.dbusConn.Object("org.freedesktop.NetworkManager", targetConn.GetPath())
	var existingSettings map[string]map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.GetSettings", 0).Store(&existingSettings); err != nil {
		return fmt.Errorf("failed to get settings for username save: %w", err)
	}

	settings := make(map[string]map[string]dbus.Variant)
	if connSection, ok := existingSettings["connection"]; ok {
		settings["connection"] = connSection
	}
	vpn := existingSettings["vpn"]
	var data map[string]string
	if dataVariant, ok := vpn["data"]; ok {
		if dm, ok := dataVariant.Value().(map[string]string); ok {
			data = make(map[string]string)
			maps.Copy(data, dm)
		} else {
			data = make(map[string]string)
		}
	} else {
		data = make(map[string]string)
	}
	data["username"] = username

	vpn["data"] = dbus.MakeVariant(data)
	settings["vpn"] = vpn

	var result map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.Update2", 0,
		settings, uint32(0x1), map[string]dbus.Variant{}).Store(&result); err != nil {
		return fmt.Errorf("failed to save username: %w", err)
	}
	log.Infof("[ConnectVPN] Username saved to connection")

	if password != "" {
		b.cachedVPNCredsMu.Lock()
		b.cachedVPNCreds = &cachedVPNCredentials{
			ConnectionUUID: targetUUID,
			Password:       password,
			SavePassword:   reply.Save,
		}
		b.cachedVPNCredsMu.Unlock()
		log.Infof("[ConnectVPN] Cached password for GetSecrets")
	}

	return nil
}

func (b *NetworkManagerBackend) DisconnectVPN(uuidOrName string) error {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)

	activeConns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return fmt.Errorf("failed to get active connections: %w", err)
	}

	log.Debugf("[DisconnectVPN] Looking for VPN: %s", uuidOrName)

	for _, activeConn := range activeConns {
		connType, err := activeConn.GetPropertyType()
		if err != nil {
			continue
		}

		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		uuid, _ := activeConn.GetPropertyUUID()
		id, _ := activeConn.GetPropertyID()
		state, _ := activeConn.GetPropertyState()

		log.Debugf("[DisconnectVPN] Found active VPN: uuid=%s id=%s state=%d", uuid, id, state)

		if uuid == uuidOrName || id == uuidOrName {
			log.Infof("[DisconnectVPN] Deactivating VPN: %s (state=%d)", id, state)
			if err := nm.DeactivateConnection(activeConn); err != nil {
				return fmt.Errorf("failed to deactivate VPN: %w", err)
			}
			b.ListActiveVPN()
			if b.onStateChange != nil {
				b.onStateChange()
			}
			return nil
		}
	}

	log.Warnf("[DisconnectVPN] VPN not found in active connections: %s", uuidOrName)

	s := b.settings
	if s == nil {
		var err error
		s, err = gonetworkmanager.NewSettings()
		if err != nil {
			return fmt.Errorf("VPN connection not active and cannot access settings: %w", err)
		}
		b.settings = s
	}

	settingsMgr := s.(gonetworkmanager.Settings)
	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return fmt.Errorf("VPN connection not active: %s", uuidOrName)
	}

	for _, conn := range connections {
		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}

		connMeta, ok := settings["connection"]
		if !ok {
			continue
		}

		connType, _ := connMeta["type"].(string)
		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		connID, _ := connMeta["id"].(string)
		connUUID, _ := connMeta["uuid"].(string)

		if connUUID == uuidOrName || connID == uuidOrName {
			log.Infof("[DisconnectVPN] VPN connection exists but not active: %s", connID)
			return nil
		}
	}

	return fmt.Errorf("VPN connection not found: %s", uuidOrName)
}

func (b *NetworkManagerBackend) DisconnectAllVPN() error {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)

	activeConns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return fmt.Errorf("failed to get active connections: %w", err)
	}

	var lastErr error
	var disconnected bool
	for _, activeConn := range activeConns {
		connType, err := activeConn.GetPropertyType()
		if err != nil {
			continue
		}

		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		if err := nm.DeactivateConnection(activeConn); err != nil {
			lastErr = err
			log.Warnf("Failed to deactivate VPN connection: %v", err)
		} else {
			disconnected = true
		}
	}

	if disconnected {
		b.ListActiveVPN()
		if b.onStateChange != nil {
			b.onStateChange()
		}
	}

	return lastErr
}

func (b *NetworkManagerBackend) ClearVPNCredentials(uuidOrName string) error {
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

	for _, conn := range connections {
		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}

		connMeta, ok := settings["connection"]
		if !ok {
			continue
		}

		connType, _ := connMeta["type"].(string)
		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		connID, _ := connMeta["id"].(string)
		connUUID, _ := connMeta["uuid"].(string)

		if connUUID == uuidOrName || connID == uuidOrName {
			if connType == "vpn" {
				if vpnSettings, ok := settings["vpn"]; ok {
					delete(vpnSettings, "secrets")

					if dataMap, ok := vpnSettings["data"].(map[string]string); ok {
						dataMap["password-flags"] = "1"
						vpnSettings["data"] = dataMap
					}
				}
			}

			if err := conn.Update(settings); err != nil {
				return fmt.Errorf("failed to update connection: %w", err)
			}

			if err := conn.ClearSecrets(); err != nil {
				log.Warnf("ClearSecrets call failed (may not be critical): %v", err)
			}

			log.Infof("Cleared credentials for VPN: %s", connID)
			return nil
		}
	}

	return fmt.Errorf("VPN connection not found: %s", uuidOrName)
}

func (b *NetworkManagerBackend) updateVPNConnectionState() {
	b.stateMutex.RLock()
	isConnectingVPN := b.state.IsConnectingVPN
	connectingVPNUUID := b.state.ConnectingVPNUUID
	b.stateMutex.RUnlock()

	if !isConnectingVPN || connectingVPNUUID == "" {
		return
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	activeConns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return
	}

	foundConnection := false
	for _, activeConn := range activeConns {
		connType, err := activeConn.GetPropertyType()
		if err != nil {
			continue
		}

		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		connUUID, err := activeConn.GetPropertyUUID()
		if err != nil {
			continue
		}

		state, _ := activeConn.GetPropertyState()
		stateReason, _ := activeConn.GetPropertyStateFlags()

		if connUUID == connectingVPNUUID {
			foundConnection = true

			switch state {
			case 2:
				log.Infof("[updateVPNConnectionState] VPN connection successful: %s", connUUID)
				b.stateMutex.Lock()
				b.state.IsConnectingVPN = false
				b.state.ConnectingVPNUUID = ""
				b.state.LastError = ""
				b.state.VPNError = ""
				b.state.VPNErrorUuid = ""
				b.stateMutex.Unlock()

				// Clear cached one-shot authentication values on success.
				b.cachedPKCS11Mu.Lock()
				b.cachedPKCS11PIN = nil
				b.cachedPKCS11Mu.Unlock()
				b.cachedOpenConnectMu.Lock()
				b.cachedOpenConnectAuth = nil
				b.cachedOpenConnectMu.Unlock()

				b.pendingVPNSaveMu.Lock()
				pending := b.pendingVPNSave
				b.pendingVPNSave = nil
				b.pendingVPNSaveMu.Unlock()

				if pending != nil {
					go b.saveVPNCredentials(pending)
				}
				return
			case 4:
				log.Warnf("[updateVPNConnectionState] VPN connection failed/deactivated: %s (state=%d, flags=%d)", connUUID, state, stateReason)
				b.stateMutex.Lock()
				b.state.IsConnectingVPN = false
				b.state.ConnectingVPNUUID = ""
				b.state.LastError = "VPN connection failed"
				if b.state.VPNError == "" {
					b.state.VPNError = "VPN connection failed"
				}
				b.state.VPNErrorUuid = connectingVPNUUID
				b.stateMutex.Unlock()

				// Clear cached one-shot authentication values on failure.
				b.cachedPKCS11Mu.Lock()
				b.cachedPKCS11PIN = nil
				b.cachedPKCS11Mu.Unlock()
				b.cachedOpenConnectMu.Lock()
				b.cachedOpenConnectAuth = nil
				b.cachedOpenConnectMu.Unlock()
				b.pendingVPNSaveMu.Lock()
				b.pendingVPNSave = nil
				b.pendingVPNSaveMu.Unlock()
				return
			}
		}
	}

	if !foundConnection {
		log.Warnf("[updateVPNConnectionState] VPN connection no longer exists: %s", connectingVPNUUID)
		b.stateMutex.Lock()
		b.state.IsConnectingVPN = false
		b.state.ConnectingVPNUUID = ""
		b.state.LastError = "VPN connection failed"
		if b.state.VPNError == "" {
			b.state.VPNError = "VPN connection failed"
		}
		b.state.VPNErrorUuid = connectingVPNUUID
		b.stateMutex.Unlock()

		// Clear cached one-shot authentication values.
		b.cachedPKCS11Mu.Lock()
		b.cachedPKCS11PIN = nil
		b.cachedPKCS11Mu.Unlock()
		b.cachedOpenConnectMu.Lock()
		b.cachedOpenConnectAuth = nil
		b.cachedOpenConnectMu.Unlock()
		b.pendingVPNSaveMu.Lock()
		b.pendingVPNSave = nil
		b.pendingVPNSaveMu.Unlock()
	}
}

func (b *NetworkManagerBackend) saveVPNCredentials(creds *pendingVPNCredentials) {
	log.Infof("[saveVPNCredentials] Saving credentials for %s (username=%v, savePassword=%v)",
		creds.ConnectionPath, creds.Username != "", creds.SavePassword)

	connObj := b.dbusConn.Object("org.freedesktop.NetworkManager", dbus.ObjectPath(creds.ConnectionPath))
	var existingSettings map[string]map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.GetSettings", 0).Store(&existingSettings); err != nil {
		log.Warnf("[saveVPNCredentials] GetSettings failed: %v", err)
		return
	}

	settings := make(map[string]map[string]dbus.Variant)
	if connSection, ok := existingSettings["connection"]; ok {
		settings["connection"] = connSection
	}

	vpn, ok := existingSettings["vpn"]
	if !ok {
		vpn = make(map[string]dbus.Variant)
	}

	// Get existing data map
	var data map[string]string
	if dataVariant, ok := vpn["data"]; ok {
		if dm, ok := dataVariant.Value().(map[string]string); ok {
			data = make(map[string]string)
			maps.Copy(data, dm)
		} else {
			data = make(map[string]string)
		}
	} else {
		data = make(map[string]string)
	}

	// Always save username if provided
	if creds.Username != "" {
		data["username"] = creds.Username
		log.Infof("[saveVPNCredentials] Saving username")
	}

	maps.Copy(data, creds.PersistentData)

	secs := map[string]string{}
	if len(creds.PersistentSecrets) > 0 {
		var stored map[string]map[string]dbus.Variant
		if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.GetSecrets", 0, "vpn").Store(&stored); err != nil {
			log.Warnf("[saveVPNCredentials] GetSecrets failed: %v", err)
			return
		}
		if storedVPN, ok := stored["vpn"]; ok {
			if storedSecrets, ok := storedVPN["secrets"]; ok {
				saved, _ := storedSecrets.Value().(map[string]string)
				maps.Copy(secs, saved)
			}
		}
		for field, value := range creds.PersistentSecrets {
			secs[field] = value
			data[field+"-flags"] = "0"
		}
	}

	if creds.SavePassword {
		toSave := creds.Secrets
		if len(toSave) == 0 {
			toSave = map[string]string{"password": creds.Password}
		}
		for field, value := range toSave {
			secs[field] = value
			data[field+"-flags"] = "0"
		}
	}
	if len(secs) > 0 {
		vpn["secrets"] = dbus.MakeVariant(secs)
		log.Infof("[saveVPNCredentials] Saving %d secret field(s)", len(secs))
	}

	vpn["data"] = dbus.MakeVariant(data)
	settings["vpn"] = vpn

	var result map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.Update2", 0,
		settings, uint32(0x1), map[string]dbus.Variant{}).Store(&result); err != nil {
		log.Warnf("[saveVPNCredentials] Update2 failed: %v", err)
	} else {
		log.Infof("[saveVPNCredentials] Successfully saved credentials")
	}
}

func (b *NetworkManagerBackend) ListVPNPlugins() ([]VPNPlugin, error) {
	plugins := []VPNPlugin{}
	pluginDirs := []string{
		"/usr/lib/NetworkManager/VPN",
		"/usr/lib64/NetworkManager/VPN",
		"/etc/NetworkManager/VPN",
	}

	seen := make(map[string]bool)

	for _, dir := range pluginDirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}

		for _, entry := range entries {
			if !strings.HasSuffix(entry.Name(), ".name") {
				continue
			}

			filePath := filepath.Join(dir, entry.Name())
			plugin, err := parseVPNPluginFile(filePath)
			if err != nil {
				log.Debugf("Failed to parse VPN plugin file %s: %v", filePath, err)
				continue
			}

			if seen[plugin.ServiceType] {
				continue
			}
			seen[plugin.ServiceType] = true
			plugins = append(plugins, *plugin)
		}
	}

	sort.Slice(plugins, func(i, j int) bool {
		return strings.ToLower(plugins[i].Name) < strings.ToLower(plugins[j].Name)
	})

	return plugins, nil
}

func parseVPNPluginFile(path string) (*VPNPlugin, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	plugin := &VPNPlugin{}
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "[") {
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		switch key {
		case "name":
			plugin.Name = value
		case "service":
			plugin.ServiceType = value
		case "program":
			plugin.Program = value
		case "supports":
			plugin.Supports = strings.Split(value, ",")
			for i := range plugin.Supports {
				plugin.Supports[i] = strings.TrimSpace(plugin.Supports[i])
			}
		}
	}

	if plugin.ServiceType == "" {
		return nil, fmt.Errorf("plugin file missing service type")
	}

	plugin.FileExtensions = getVPNFileExtensions(plugin.ServiceType)

	return plugin, nil
}

func getVPNFileExtensions(serviceType string) []string {
	switch {
	case strings.Contains(serviceType, "openvpn"):
		return []string{".ovpn", ".conf"}
	case strings.Contains(serviceType, "wireguard"):
		return []string{".conf"}
	case strings.Contains(serviceType, "vpnc"), strings.Contains(serviceType, "cisco"):
		return []string{".pcf", ".conf"}
	case strings.Contains(serviceType, "openconnect"):
		return []string{".conf"}
	case strings.Contains(serviceType, "pptp"):
		return []string{".conf"}
	case strings.Contains(serviceType, "l2tp"):
		return []string{".conf"}
	case strings.Contains(serviceType, "strongswan"), strings.Contains(serviceType, "ipsec"):
		return []string{".conf", ".sswan"}
	default:
		return []string{".conf"}
	}
}

func (b *NetworkManagerBackend) ImportVPN(filePath string, name string) (*VPNImportResult, error) {
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		return &VPNImportResult{
			Success: false,
			Error:   fmt.Sprintf("file not found: %s", filePath),
		}, nil
	}

	if cfg := readOpenfortivpnConfig(filePath); cfg != nil {
		if name == "" {
			name = vpnNameFromPath(filePath)
		}
		return b.importOpenfortivpnConfig(cfg, name)
	}

	return b.importVPNWithNmcli(filePath, name)
}

func (b *NetworkManagerBackend) importVPNWithNmcli(filePath string, name string) (*VPNImportResult, error) {
	vpnTypes := []string{"openvpn", "wireguard", "vpnc", "pptp", "l2tp", "openconnect", "strongswan"}

	var allErrors []error
	var outputStr string
	for _, vpnType := range vpnTypes {
		cmd := exec.Command("nmcli", "connection", "import", "type", vpnType, "file", filePath)
		output, err := cmd.CombinedOutput()
		if err == nil {
			outputStr = string(output)
			break
		}
		allErrors = append(allErrors, fmt.Errorf("%s: %s", vpnType, strings.TrimSpace(string(output))))
	}

	if len(allErrors) == len(vpnTypes) {
		return &VPNImportResult{
			Success: false,
			Error:   errors.Join(allErrors...).Error(),
		}, nil
	}
	var connUUID, connName string

	lines := strings.SplitSeq(outputStr, "\n")
	for line := range lines {
		if strings.Contains(line, "successfully added") {
			parts := strings.Fields(line)
			for i, part := range parts {
				if part == "(" && i+1 < len(parts) {
					connUUID = strings.TrimSuffix(parts[i+1], ")")
					break
				}
			}
		}
	}

	if name != "" && connUUID != "" {
		renameCmd := exec.Command("nmcli", "connection", "modify", connUUID, "connection.id", name)
		if err := renameCmd.Run(); err != nil {
			log.Warnf("Failed to rename imported VPN: %v", err)
		} else {
			connName = name
		}
	}

	if connUUID == "" {
		s := b.settings
		if s == nil {
			var settingsErr error
			s, settingsErr = gonetworkmanager.NewSettings()
			if settingsErr == nil {
				b.settings = s
			}
		}

		if s != nil {
			settingsMgr := s.(gonetworkmanager.Settings)
			connections, _ := settingsMgr.ListConnections()
			baseName := strings.TrimSuffix(filepath.Base(filePath), filepath.Ext(filePath))

			for _, conn := range connections {
				settings, err := conn.GetSettings()
				if err != nil {
					continue
				}
				connMeta, ok := settings["connection"]
				if !ok {
					continue
				}
				connType, _ := connMeta["type"].(string)
				if connType != "vpn" && connType != "wireguard" {
					continue
				}
				connID, _ := connMeta["id"].(string)
				if strings.Contains(connID, baseName) || (name != "" && connID == name) {
					connUUID, _ = connMeta["uuid"].(string)
					connName = connID
					break
				}
			}
		}
	}

	b.ListVPNProfiles()

	if b.onStateChange != nil {
		b.onStateChange()
	}

	return &VPNImportResult{
		Success: true,
		UUID:    connUUID,
		Name:    connName,
	}, nil
}

func (b *NetworkManagerBackend) GetVPNConfig(uuidOrName string) (*VPNConfig, error) {
	s := b.settings
	if s == nil {
		var err error
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

	for _, conn := range connections {
		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}

		connMeta, ok := settings["connection"]
		if !ok {
			continue
		}

		connType, _ := connMeta["type"].(string)
		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		connID, _ := connMeta["id"].(string)
		connUUID, _ := connMeta["uuid"].(string)

		if connUUID != uuidOrName && connID != uuidOrName {
			continue
		}

		autoconnect := true
		if ac, ok := connMeta["autoconnect"].(bool); ok {
			autoconnect = ac
		}

		config := &VPNConfig{
			UUID:        connUUID,
			Name:        connID,
			Type:        connType,
			Autoconnect: autoconnect,
			Data:        make(map[string]string),
		}

		if connType == "vpn" {
			if vpnSettings, ok := settings["vpn"]; ok {
				if svcType, ok := vpnSettings["service-type"].(string); ok {
					config.ServiceType = svcType
				}
				if dataMap, ok := vpnSettings["data"].(map[string]string); ok {
					for k, v := range dataMap {
						if !strings.Contains(strings.ToLower(k), "password") &&
							!strings.Contains(strings.ToLower(k), "secret") &&
							!strings.Contains(strings.ToLower(k), "key") {
							config.Data[k] = v
						}
					}
				}
			}
		}

		return config, nil
	}

	return nil, fmt.Errorf("VPN connection not found: %s", uuidOrName)
}

func (b *NetworkManagerBackend) UpdateVPNConfig(connUUID string, updates map[string]any) error {
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

	for _, conn := range connections {
		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}

		connMeta, ok := settings["connection"]
		if !ok {
			continue
		}

		connType, _ := connMeta["type"].(string)
		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		existingUUID, _ := connMeta["uuid"].(string)
		if existingUUID != connUUID {
			continue
		}

		if name, ok := updates["name"].(string); ok && name != "" {
			connMeta["id"] = name
		}

		if autoconnect, ok := updates["autoconnect"].(bool); ok {
			connMeta["autoconnect"] = autoconnect
		}

		if data, ok := updates["data"].(map[string]any); ok {
			if vpnSettings, ok := settings["vpn"]; ok {
				existingData, _ := vpnSettings["data"].(map[string]string)
				if existingData == nil {
					existingData = make(map[string]string)
				}
				for k, v := range data {
					if strVal, ok := v.(string); ok {
						existingData[k] = strVal
					}
				}
				vpnSettings["data"] = existingData
			}
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

		if err := conn.Update(settings); err != nil {
			return fmt.Errorf("failed to update connection: %w", err)
		}

		b.ListVPNProfiles()

		if b.onStateChange != nil {
			b.onStateChange()
		}

		return nil
	}

	return fmt.Errorf("VPN connection not found: %s", connUUID)
}

func (b *NetworkManagerBackend) SetVPNCredentials(connUUID string, username string, password string, saveToKeyring bool) error {
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

	for _, conn := range connections {
		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}

		connMeta, ok := settings["connection"]
		if !ok {
			continue
		}

		connType, _ := connMeta["type"].(string)
		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		existingUUID, _ := connMeta["uuid"].(string)
		if existingUUID != connUUID {
			continue
		}

		vpnSettings, ok := settings["vpn"]
		if !ok {
			vpnSettings = make(map[string]any)
			settings["vpn"] = vpnSettings
		}

		existingData, _ := vpnSettings["data"].(map[string]string)
		if existingData == nil {
			existingData = make(map[string]string)
		}

		if username != "" {
			existingData["username"] = username
		}

		if saveToKeyring {
			existingData["password-flags"] = "0"
		} else {
			existingData["password-flags"] = "2"
		}

		vpnSettings["data"] = existingData

		if password != "" {
			secrets := make(map[string]string)
			secrets["password"] = password
			vpnSettings["secrets"] = secrets
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

		if err := conn.Update(settings); err != nil {
			return fmt.Errorf("failed to update connection: %w", err)
		}

		log.Infof("Updated VPN credentials for %s (save=%v)", connUUID, saveToKeyring)

		if b.onStateChange != nil {
			b.onStateChange()
		}

		return nil
	}

	return fmt.Errorf("VPN connection not found: %s", connUUID)
}

func (b *NetworkManagerBackend) DeleteVPN(uuidOrName string) error {
	active, _ := b.ListActiveVPN()
	for _, vpn := range active {
		if vpn.UUID == uuidOrName || vpn.Name == uuidOrName {
			if err := b.DisconnectVPN(uuidOrName); err != nil {
				log.Warnf("Failed to disconnect VPN before deletion: %v", err)
			}
			time.Sleep(200 * time.Millisecond)
			break
		}
	}

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

	for _, conn := range connections {
		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}

		connMeta, ok := settings["connection"]
		if !ok {
			continue
		}

		connType, _ := connMeta["type"].(string)
		if connType != "vpn" && connType != "wireguard" {
			continue
		}

		connID, _ := connMeta["id"].(string)
		connUUID, _ := connMeta["uuid"].(string)

		if connUUID == uuidOrName || connID == uuidOrName {
			if err := conn.Delete(); err != nil {
				return fmt.Errorf("failed to delete VPN: %w", err)
			}

			b.ListVPNProfiles()

			if b.onStateChange != nil {
				b.onStateChange()
			}

			log.Infof("Deleted VPN connection: %s (%s)", connID, connUUID)
			return nil
		}
	}

	return fmt.Errorf("VPN connection not found: %s", uuidOrName)
}
