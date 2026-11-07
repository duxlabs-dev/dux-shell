package network

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

const (
	nmAgentManagerPath  = "/org/freedesktop/NetworkManager/AgentManager"
	nmAgentManagerIface = "org.freedesktop.NetworkManager.AgentManager"
	nmSecretAgentIface  = "org.freedesktop.NetworkManager.SecretAgent"
	agentObjectPath     = "/org/freedesktop/NetworkManager/SecretAgent"
	agentIdentifier     = "dev.duxlabs.NMAgent"
)

const (
	nmSecretAgentFlagAllowInteraction = 0x1
	nmSecretAgentFlagRequestNew       = 0x2
	nmSecretAgentFlagOnlySystem       = 0x80000000
)

type SecretAgent struct {
	conn    *dbus.Conn
	objPath dbus.ObjectPath
	id      string
	prompts PromptBroker
	manager *Manager
	backend *NetworkManagerBackend
}

type (
	nmVariantMap map[string]dbus.Variant
	nmSettingMap map[string]nmVariantMap
)

const introspectXML = `
<node>
	<interface name="org.freedesktop.NetworkManager.SecretAgent">
		<method name="GetSecrets">
			<arg type="a{sa{sv}}" name="connection" direction="in"/>
			<arg type="o" name="connection_path" direction="in"/>
			<arg type="s" name="setting_name" direction="in"/>
			<arg type="as" name="hints" direction="in"/>
			<arg type="u" name="flags" direction="in"/>
			<arg type="a{sa{sv}}" name="secrets" direction="out"/>
		</method>
		<method name="SaveSecrets">
			<arg type="a{sa{sv}}" name="connection" direction="in"/>
			<arg type="o" name="connection_path" direction="in"/>
		</method>
		<method name="DeleteSecrets">
			<arg type="a{sa{sv}}" name="connection" direction="in"/>
			<arg type="o" name="connection_path" direction="in"/>
		</method>
		<method name="DeleteSecrets2">
			<arg type="o" name="connection_path" direction="in"/>
			<arg type="s" name="setting" direction="in"/>
		</method>
		<method name="CancelGetSecrets">
			<arg type="o" name="connection_path" direction="in"/>
			<arg type="s" name="setting_name" direction="in"/>
		</method>
	</interface>
	<interface name="org.freedesktop.DBus.Introspectable">
		<method name="Introspect">
			<arg name="data" type="s" direction="out"/>
		</method>
	</interface>
</node>`

func NewSecretAgent(prompts PromptBroker, manager *Manager, backend *NetworkManagerBackend) (*SecretAgent, error) {
	c, err := dbus.SystemBus()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to system bus: %w", err)
	}

	sa := &SecretAgent{
		conn:    c,
		objPath: dbus.ObjectPath(agentObjectPath),
		id:      agentIdentifier,
		prompts: prompts,
		manager: manager,
		backend: backend,
	}

	if err := c.Export(sa, sa.objPath, nmSecretAgentIface); err != nil {
		return nil, fmt.Errorf("failed to export secret agent: %w", err)
	}

	if err := c.Export(sa, sa.objPath, "org.freedesktop.DBus.Introspectable"); err != nil {
		sa.unexport()
		return nil, fmt.Errorf("failed to export introspection: %w", err)
	}

	mgr := c.Object("org.freedesktop.NetworkManager", dbus.ObjectPath(nmAgentManagerPath))
	call := mgr.Call(nmAgentManagerIface+".Register", 0, sa.id)
	if call.Err != nil {
		sa.unexport()
		return nil, fmt.Errorf("failed to register agent with NetworkManager: %w", call.Err)
	}

	log.Infof("[SecretAgent] Registered with NetworkManager (id=%s, unique name=%s, fixed path=%s)", sa.id, c.Names()[0], sa.objPath)
	return sa, nil
}

func (a *SecretAgent) Close() {
	if a.conn == nil {
		return
	}
	mgr := a.conn.Object("org.freedesktop.NetworkManager", dbus.ObjectPath(nmAgentManagerPath))
	mgr.Call(nmAgentManagerIface+".Unregister", 0, a.id)
	a.unexport()
}

func (a *SecretAgent) unexport() {
	_ = a.conn.Export(nil, a.objPath, nmSecretAgentIface)
	_ = a.conn.Export(nil, a.objPath, "org.freedesktop.DBus.Introspectable")
}

func (a *SecretAgent) GetSecrets(
	conn map[string]nmVariantMap,
	path dbus.ObjectPath,
	settingName string,
	hints []string,
	flags uint32,
) (nmSettingMap, *dbus.Error) {
	log.Infof("[SecretAgent] GetSecrets called: path=%s, setting=%s, hints=%v, flags=%d",
		path, settingName, hints, flags)

	connType, displayName, vpnSvc := readConnTypeAndName(conn)
	ssid := readSSID(conn)
	fields := fieldsNeeded(settingName, hints, conn)
	vpnPasswordFlags := readVPNPasswordFlags(conn, settingName)

	log.Infof("[SecretAgent] connType=%s, name=%s, vpnSvc=%s, fields=%v, flags=%d, vpnPasswordFlags=%d", connType, displayName, vpnSvc, fields, flags, vpnPasswordFlags)

	if flags&nmSecretAgentFlagOnlySystem != 0 {
		log.Infof("[SecretAgent] ONLY_SYSTEM flag set, deferring to system secret storage")
		return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil)
	}

	connUuid := readConnUUID(conn)

	// Phase 1: Determine if this connection is ours and what fields we need.
	if a.backend != nil {
		a.backend.stateMutex.RLock()
		isConnecting := a.backend.state.IsConnecting
		connectingSSID := a.backend.state.ConnectingSSID
		isConnectingVPN := a.backend.state.IsConnectingVPN
		connectingVPNUUID := a.backend.state.ConnectingVPNUUID
		a.backend.stateMutex.RUnlock()

		switch connType {
		case "802-11-wireless":
			// If we're connecting to a WiFi network, only respond if it's the one we're connecting to
			if isConnecting && connectingSSID != ssid {
				log.Infof("[SecretAgent] Ignoring WiFi request for SSID '%s' - we're connecting to '%s'", ssid, connectingSSID)
				return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil)
			}
		case "vpn", "wireguard":
			// If we're connecting to a VPN, only respond if it's the one we're connecting to
			// This prevents interfering with nmcli/other tools when our app isn't connecting
			if isConnectingVPN && connUuid != connectingVPNUUID {
				log.Infof("[SecretAgent] Ignoring VPN request for UUID '%s' - we're connecting to '%s'", connUuid, connectingVPNUUID)
				return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil)
			}
		}
	}

	// Phase 2: Resolve fields from hints or password-flags.
	if len(fields) == 0 {
		if settingName == "vpn" {
			if a.backend != nil {
				a.backend.stateMutex.RLock()
				isConnectingVPN := a.backend.state.IsConnectingVPN
				a.backend.stateMutex.RUnlock()

				if !isConnectingVPN {
					log.Infof("[SecretAgent] VPN with empty hints - deferring to other agents for %s", vpnSvc)
					return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil)
				}

				fields = inferVPNFields(conn, vpnSvc)
				log.Infof("[SecretAgent] VPN with empty hints but we're connecting - inferred fields: %v", fields)
			} else {
				log.Infof("[SecretAgent] VPN with empty hints - deferring to other agents for %s", vpnSvc)
				return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil)
			}
		}

		if len(fields) == 0 {
			const (
				NM_SETTING_SECRET_FLAG_NONE         = 0
				NM_SETTING_SECRET_FLAG_AGENT_OWNED  = 1
				NM_SETTING_SECRET_FLAG_NOT_SAVED    = 2
				NM_SETTING_SECRET_FLAG_NOT_REQUIRED = 4
			)

			var passwordFlags uint32 = 0xFFFF
			switch settingName {
			case "802-11-wireless-security":
				if wifiSecSettings, ok := conn["802-11-wireless-security"]; ok {
					if flagsVariant, ok := wifiSecSettings["psk-flags"]; ok {
						if pwdFlags, ok := flagsVariant.Value().(uint32); ok {
							passwordFlags = pwdFlags
						}
					}
				}
			case "802-1x":
				if dot1xSettings, ok := conn["802-1x"]; ok {
					if flagsVariant, ok := dot1xSettings["password-flags"]; ok {
						if pwdFlags, ok := flagsVariant.Value().(uint32); ok {
							passwordFlags = pwdFlags
						}
					}
				}
			}

			if passwordFlags == 0xFFFF {
				log.Warnf("[SecretAgent] Could not determine password-flags for empty hints - returning NoSecrets error")
				return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil)
			} else if passwordFlags&NM_SETTING_SECRET_FLAG_NOT_REQUIRED != 0 {
				log.Infof("[SecretAgent] Secrets not required (flags=%d)", passwordFlags)
				out := nmSettingMap{}
				out[settingName] = nmVariantMap{}
				return out, nil
			} else if passwordFlags&NM_SETTING_SECRET_FLAG_AGENT_OWNED != 0 {
				switch settingName {
				case "802-11-wireless-security":
					fields = []string{"psk"}
				case "802-1x":
					fields = infer8021xFields(conn)
				default:
					log.Warnf("[SecretAgent] Agent-owned secrets for unhandled setting %s (flags=%d)", settingName, passwordFlags)
					return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil)
				}
				log.Infof("[SecretAgent] Agent-owned secrets, inferred fields: %v", fields)
			} else if passwordFlags&NM_SETTING_SECRET_FLAG_NOT_SAVED != 0 {
				log.Infof("[SecretAgent] Secrets not saved, will need to prompt (flags=%d)", passwordFlags)
				// Fall through — fields remain empty, prompt will be required.
			} else {
				log.Infof("[SecretAgent] Secrets stored in NM config (flags=%d), deferring to system", passwordFlags)
				return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil)
			}
		}
	}

	// Phase 3: Cached VPN credentials — user-provided, take priority.
	if settingName == "vpn" && a.backend != nil {
		if isPKCS11Request := len(fields) == 1 && fields[0] == "key_pass"; isPKCS11Request {
			a.backend.cachedPKCS11Mu.Lock()
			cached := a.backend.cachedPKCS11PIN
			if cached != nil && cached.ConnectionUUID == connUuid {
				a.backend.cachedPKCS11PIN = nil
				a.backend.cachedPKCS11Mu.Unlock()

				log.Infof("[SecretAgent] Using cached PKCS11 PIN")

				out := nmSettingMap{}
				vpnSec := nmVariantMap{}
				vpnSec["secrets"] = dbus.MakeVariant(map[string]string{"key_pass": cached.PIN})
				out[settingName] = vpnSec

				return out, nil
			}
			a.backend.cachedPKCS11Mu.Unlock()
		}

		a.backend.cachedVPNCredsMu.Lock()
		cached := a.backend.cachedVPNCreds
		if cached != nil && cached.ConnectionUUID == connUuid && slices.Contains(fields, "password") {
			a.backend.cachedVPNCreds = nil
			a.backend.cachedVPNCredsMu.Unlock()

			log.Infof("[SecretAgent] Using cached password from pre-activation prompt")

			out := nmSettingMap{}
			vpnSec := nmVariantMap{}
			vpnSec["secrets"] = dbus.MakeVariant(map[string]string{"password": cached.Password})
			out[settingName] = vpnSec

			if cached.SavePassword {
				a.backend.pendingVPNSaveMu.Lock()
				a.backend.pendingVPNSave = &pendingVPNCredentials{
					ConnectionPath: string(path),
					Password:       cached.Password,
					SavePassword:   true,
				}
				a.backend.pendingVPNSaveMu.Unlock()
			}

			return out, nil
		}
		a.backend.cachedVPNCredsMu.Unlock()

		a.backend.cachedOpenConnectMu.Lock()
		cachedOpenConnect := a.backend.cachedOpenConnectAuth
		if cachedOpenConnect != nil && cachedOpenConnect.ConnectionUUID == connUuid {
			a.backend.cachedOpenConnectAuth = nil
			a.backend.cachedOpenConnectMu.Unlock()

			log.Infof("[SecretAgent] Using cached OpenConnect authentication for %s", connUuid)

			return buildOpenConnectSecretsResponse(settingName, cachedOpenConnect.Cookie, cachedOpenConnect.Host, cachedOpenConnect.Fingerprint), nil
		}
		a.backend.cachedOpenConnectMu.Unlock()

		if len(fields) == 1 && fields[0] == "fortinet-saml" {
			data := vpnDataFromSettings(conn)

			log.Infof("[SecretAgent] Starting Fortinet SAML authentication for gateway=%s", data["gateway"])

			samlCtx, samlCancel := context.WithTimeout(context.Background(), 5*time.Minute)
			defer samlCancel()

			authResult, err := a.backend.authenticateFortinetSAML(samlCtx, fortinetAuthTarget{
				ConnName:       displayName,
				ConnUUID:       connUuid,
				ConnectionPath: string(path),
				VpnService:     vpnSvc,
				Data:           data,
			})
			if err != nil {
				log.Warnf("[SecretAgent] Fortinet SAML authentication failed: %v", err)
				return nil, dbus.MakeFailedError(fmt.Errorf("SAML authentication failed for the Fortinet gateway: %w", err))
			}

			a.backend.cachedOpenConnectMu.Lock()
			a.backend.cachedOpenConnectAuth = &cachedOpenConnectAuth{
				ConnectionUUID: connUuid,
				Cookie:         authResult.Cookie,
				Host:           authResult.Host,
				Fingerprint:    authResult.Fingerprint,
			}
			a.backend.cachedOpenConnectMu.Unlock()

			return buildOpenConnectSecretsResponse(settingName, authResult.Cookie, authResult.Host, authResult.Fingerprint), nil
		}

		if len(fields) == 1 && fields[0] == "gp-saml" {
			gateway := ""
			protocol := ""
			if vpnSettings, ok := conn["vpn"]; ok {
				if dataVariant, ok := vpnSettings["data"]; ok {
					if dataMap, ok := dataVariant.Value().(map[string]string); ok {
						if gw, ok := dataMap["gateway"]; ok {
							gateway = gw
						}
						if proto, ok := dataMap["protocol"]; ok && proto != "" {
							protocol = proto
						}
					}
				}
			}

			if protocol != "gp" {
				return nil, dbus.MakeFailedError(fmt.Errorf("gp-saml auth only supported for GlobalProtect (protocol=gp), got: %s", protocol))
			}

			log.Infof("[SecretAgent] Starting GlobalProtect SAML authentication for gateway=%s", gateway)

			samlCtx, samlCancel := context.WithTimeout(context.Background(), 5*time.Minute)
			defer samlCancel()

			authResult, err := a.backend.runGlobalProtectSAMLAuth(samlCtx, gateway, protocol)
			if err != nil {
				log.Warnf("[SecretAgent] GlobalProtect SAML authentication failed: %v", err)
				return nil, dbus.MakeFailedError(fmt.Errorf("GlobalProtect SAML authentication failed: %w", err))
			}

			log.Infof("[SecretAgent] GlobalProtect SAML authentication successful, returning cookie to NetworkManager")

			a.backend.cachedOpenConnectMu.Lock()
			a.backend.cachedOpenConnectAuth = &cachedOpenConnectAuth{
				ConnectionUUID: connUuid,
				Cookie:         authResult.Cookie,
				Host:           authResult.Host,
				User:           authResult.User,
				Fingerprint:    authResult.Fingerprint,
			}
			a.backend.cachedOpenConnectMu.Unlock()

			return buildOpenConnectSecretsResponse(settingName, authResult.Cookie, authResult.Host, authResult.Fingerprint), nil
		}
	}

	// Phase 4: Non-interactive secret retrieval. REQUEST_NEW means NM thinks the
	// secret is wrong, so force a prompt; otherwise reuse keyring then cached secret.
	requestNew := flags&nmSecretAgentFlagRequestNew != 0
	if requestNew {
		if a.backend != nil {
			a.backend.clearCachedWiFiSecret(connUuid)
		}
	} else {
		if secretOut := a.trySecretService(connUuid, settingName, fields); secretOut != nil {
			return secretOut, nil
		}

		switch settingName {
		case "802-11-wireless-security", "802-1x":
			if a.backend != nil {
				if cached := a.backend.lookupCachedWiFiSecret(connUuid, settingName); cached != nil {
					log.Infof("[SecretAgent] Reusing cached WiFi secret for %s (no REQUEST_NEW)", connUuid)
					return buildWiFiSecretsResponse(settingName, cached), nil
				}
			}
		}
	}

	// Phase 5: If interaction is not allowed, we're done.
	if flags&nmSecretAgentFlagAllowInteraction == 0 {
		log.Infof("[SecretAgent] ALLOW_INTERACTION not set, cannot prompt user")
		return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil)
	}

	// Phase 6: Prepare prompt.
	reason := reasonFromFlags(flags)
	if a.manager != nil && connType == "802-11-wireless" && a.manager.WasRecentlyFailed(ssid) {
		reason = "wrong-password"
	}
	if settingName == "vpn" && isPKCS11Auth(conn, vpnSvc) {
		reason = "pkcs11"
	}

	var connId string
	if c, ok := conn["connection"]; ok {
		if v, ok := c["id"]; ok {
			if s, ok2 := v.Value().(string); ok2 {
				connId = s
			}
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	token, err := a.prompts.Ask(ctx, PromptRequest{
		Name:           displayName,
		SSID:           ssid,
		ConnType:       connType,
		VpnService:     vpnSvc,
		SettingName:    settingName,
		Fields:         fields,
		FieldsInfo:     buildFieldsInfo(settingName, fields, hints, vpnSvc),
		Hints:          hints,
		Reason:         reason,
		ConnectionId:   connId,
		ConnectionUuid: connUuid,
		ConnectionPath: string(path),
	})
	if err != nil {
		log.Warnf("[SecretAgent] Failed to create prompt: %v", err)
		return nil, dbus.MakeFailedError(err)
	}

	log.Infof("[SecretAgent] Waiting for user input (token=%s)", token)
	reply, err := a.prompts.Wait(ctx, token)
	if err != nil {
		log.Warnf("[SecretAgent] Prompt failed or cancelled: %v", err)

		// Clear connecting state immediately on cancellation
		if a.backend != nil {
			a.backend.stateMutex.Lock()
			wasConnecting := a.backend.state.IsConnecting
			wasConnectingVPN := a.backend.state.IsConnectingVPN
			cancelledSSID := a.backend.state.ConnectingSSID
			cancelledVPNUUID := a.backend.state.ConnectingVPNUUID
			connPreExisting := a.backend.state.ConnectingPreExisting
			if wasConnecting || wasConnectingVPN {
				log.Infof("[SecretAgent] Clearing connecting state due to cancelled prompt")
				a.backend.state.IsConnecting = false
				a.backend.state.ConnectingSSID = ""
				a.backend.state.IsConnectingVPN = false
				a.backend.state.ConnectingVPNUUID = ""
			}
			a.backend.stateMutex.Unlock()

			a.backend.clearCachedWiFiSecret(connUuid)

			// If this was a WiFi connection that was just cancelled, remove the connection profile
			// (it was created with AddConnection but activation was cancelled)
			// Only do this for newly created connections, not pre-existing ones.
			if wasConnecting && cancelledSSID != "" && connType == "802-11-wireless" && !connPreExisting {
				log.Infof("[SecretAgent] Removing connection profile for cancelled WiFi connection: %s", cancelledSSID)
				if err := a.backend.ForgetWiFiNetwork(cancelledSSID); err != nil {
					log.Warnf("[SecretAgent] Failed to remove cancelled connection profile: %v", err)
				}
			}

			// If this was a VPN connection that was cancelled, deactivate it
			if wasConnectingVPN && cancelledVPNUUID != "" {
				log.Infof("[SecretAgent] Deactivating cancelled VPN connection: %s", cancelledVPNUUID)
				if err := a.backend.DisconnectVPN(cancelledVPNUUID); err != nil {
					log.Warnf("[SecretAgent] Failed to deactivate cancelled VPN: %v", err)
				}
			}

			if (wasConnecting || wasConnectingVPN) && a.backend.onStateChange != nil {
				a.backend.onStateChange()
			}
		}

		if reply.Cancel || errors.Is(err, errdefs.ErrSecretPromptCancelled) {
			return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.UserCanceled", nil)
		}

		if errors.Is(err, errdefs.ErrSecretPromptTimeout) {
			return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.Failed", nil)
		}
		return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.Failed", nil)
	}

	log.Infof("[SecretAgent] User provided secrets, save=%v", reply.Save)

	out := nmSettingMap{}
	sec := nmVariantMap{}

	var vpnUsername string
	for k, v := range reply.Secrets {
		if settingName == "vpn" && k == "username" {
			vpnUsername = v
		}
		sec[k] = dbus.MakeVariant(v)
	}

	// Check if this is PKCS11 auth (key_pass)
	pin, isPKCS11 := reply.Secrets["key_pass"]

	switch settingName {
	case "vpn":
		// VPN secrets must be wrapped in a "secrets" key per NM spec
		secretsDict := make(map[string]string)
		for k, v := range reply.Secrets {
			if k != "username" {
				secretsDict[k] = v
			}
		}
		vpnSec := nmVariantMap{}
		vpnSec["secrets"] = dbus.MakeVariant(secretsDict)
		out[settingName] = vpnSec
		log.Infof("[SecretAgent] Returning VPN secrets with %d fields for %s", len(secretsDict), vpnSvc)

		// Cache PKCS11 PIN in case GetSecrets is called again during activation
		if isPKCS11 && a.backend != nil {
			a.backend.cachedPKCS11Mu.Lock()
			a.backend.cachedPKCS11PIN = &cachedPKCS11PIN{
				ConnectionUUID: connUuid,
				PIN:            pin,
			}
			a.backend.cachedPKCS11Mu.Unlock()
			log.Infof("[SecretAgent] Cached PKCS11 PIN for potential re-request")
		}
	case "802-1x":
		secretsOnly := nmVariantMap{}
		for k, v := range reply.Secrets {
			switch k {
			case "password", "private-key-password", "phase2-private-key-password", "pin":
				secretsOnly[k] = dbus.MakeVariant(v)
			}
		}
		out[settingName] = secretsOnly

		if identity, ok := reply.Secrets["identity"]; ok && identity != "" {
			a.save8021xIdentity(path, identity)
		}
		log.Infof("[SecretAgent] Returning 802-1x enterprise secrets with %d fields", len(secretsOnly))
	default:
		out[settingName] = sec
	}
	secrets := make(map[string]string)
	for k, v := range reply.Secrets {
		if k != "username" && k != "challenge-response" {
			secrets[k] = v
		}
	}
	if settingName == "vpn" && a.backend != nil && !isPKCS11 && (vpnUsername != "" || (reply.Save && len(secrets) > 0)) {
		a.backend.pendingVPNSaveMu.Lock()
		a.backend.pendingVPNSave = &pendingVPNCredentials{
			ConnectionPath: string(path),
			Username:       vpnUsername,
			Password:       reply.Secrets["password"],
			Secrets:        secrets,
			SavePassword:   reply.Save,
		}
		a.backend.pendingVPNSaveMu.Unlock()
		log.Infof("[SecretAgent] Queued credentials persist for after connection succeeds")
	}

	if a.backend != nil {
		switch settingName {
		case "802-11-wireless-security", "802-1x":
			a.backend.cacheWiFiSecret(connUuid, ssid, settingName, reply.Secrets)
		}
	}

	return out, nil
}

// SaveSecrets persists agent-owned secrets to the Secret Service keyring using
// the attribute schema trySecretService reads back. NM calls this after
// activation for secrets with NM_SETTING_SECRET_FLAG_AGENT_OWNED; without it
// those secrets are lost and every reconnect re-prompts.
func (a *SecretAgent) SaveSecrets(conn map[string]nmVariantMap, path dbus.ObjectPath) *dbus.Error {
	_, displayName, _ := readConnTypeAndName(conn)
	connUuid := readConnUUID(conn)
	log.Infof("[SecretAgent] SaveSecrets called: path=%s, name=%s", path, displayName)

	if connUuid == "" {
		return nil
	}

	owned := agentOwnedSecrets(conn)
	if len(owned) == 0 {
		return nil
	}

	sess, err := openSecretService()
	if err != nil {
		log.Warnf("[SecretAgent] SaveSecrets: failed to open secret service: %v", err)
		return nil
	}
	defer sess.close()

	for setting, secrets := range owned {
		for key, value := range secrets {
			label := fmt.Sprintf("Network secret for %s/%s/%s", displayName, setting, key)
			if err := sess.store(connUuid, setting, key, label, value); err != nil {
				log.Warnf("[SecretAgent] SaveSecrets: failed to store %s/%s: %v", setting, key, err)
				continue
			}
			log.Infof("[SecretAgent] SaveSecrets: stored %s/%s for %s", setting, key, connUuid)
		}
	}

	return nil
}

func (a *SecretAgent) DeleteSecrets(conn map[string]nmVariantMap, path dbus.ObjectPath) *dbus.Error {
	connUuid := readConnUUID(conn)
	log.Infof("[SecretAgent] DeleteSecrets called: path=%s, uuid=%s", path, connUuid)

	if connUuid == "" {
		return nil
	}

	sess, err := openSecretService()
	if err != nil {
		log.Debugf("[SecretAgent] DeleteSecrets: failed to open secret service: %v", err)
		return nil
	}
	defer sess.close()

	sess.deleteAll(connUuid)
	return nil
}

func (a *SecretAgent) DeleteSecrets2(path dbus.ObjectPath, setting string) *dbus.Error {
	log.Infof("[SecretAgent] DeleteSecrets2 (alternate) called: path=%s, setting=%s", path, setting)
	return nil
}

func (a *SecretAgent) CancelGetSecrets(path dbus.ObjectPath, settingName string) *dbus.Error {
	log.Infof("[SecretAgent] CancelGetSecrets called: path=%s, setting=%s", path, settingName)

	if a.prompts != nil {
		if err := a.prompts.Cancel(string(path), settingName); err != nil {
			log.Warnf("[SecretAgent] Failed to cancel prompt: %v", err)
		}
	}

	return nil
}

func (a *SecretAgent) Introspect() (string, *dbus.Error) {
	return introspectXML, nil
}

// save8021xIdentity persists a prompted identity into the profile. Update2
// replaces the whole connection, so the full settings must round-trip with
// stored secrets merged back, or system-owned passwords would be wiped.
func (a *SecretAgent) save8021xIdentity(path dbus.ObjectPath, identity string) {
	connObj := a.conn.Object("org.freedesktop.NetworkManager", path)
	var settings map[string]map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.GetSettings", 0).Store(&settings); err != nil {
		log.Warnf("[SecretAgent] Failed to get settings for identity save: %v", err)
		return
	}

	dot1x, ok := settings["802-1x"]
	if !ok {
		dot1x = make(map[string]dbus.Variant)
		settings["802-1x"] = dot1x
	}
	dot1x["identity"] = dbus.MakeVariant(identity)

	mergeStoredSecretsRaw(connObj, settings)

	var result map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.Update2", 0,
		settings, uint32(0x1), map[string]dbus.Variant{}).Store(&result); err != nil {
		log.Warnf("[SecretAgent] Failed to save 802.1x identity: %v", err)
		return
	}
	log.Infof("[SecretAgent] Saved 802.1x identity to connection profile")
}

func mergeStoredSecretsRaw(connObj dbus.BusObject, settings map[string]map[string]dbus.Variant) {
	for _, setting := range []string{"802-11-wireless-security", "802-1x", "vpn"} {
		section, ok := settings[setting]
		if !ok {
			continue
		}

		var secrets map[string]map[string]dbus.Variant
		if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.GetSecrets", 0, setting).Store(&secrets); err != nil {
			continue
		}

		for k, v := range secrets[setting] {
			if _, exists := section[k]; exists {
				continue
			}
			section[k] = v
		}
	}
}

func readConnUUID(conn map[string]nmVariantMap) string {
	c, ok := conn["connection"]
	if !ok {
		return ""
	}
	v, ok := c["uuid"]
	if !ok {
		return ""
	}
	s, _ := v.Value().(string)
	return s
}

// agentOwnedSecrets extracts secrets flagged NM_SETTING_SECRET_FLAG_AGENT_OWNED.
// Secret properties are identified by their "<name>-flags" sibling key.
func agentOwnedSecrets(conn map[string]nmVariantMap) map[string]map[string]string {
	const nmSecretFlagAgentOwned = 0x1

	out := make(map[string]map[string]string)
	for _, setting := range []string{"802-11-wireless-security", "802-1x"} {
		section, ok := conn[setting]
		if !ok {
			continue
		}

		for key, v := range section {
			if strings.HasSuffix(key, "-flags") {
				continue
			}
			value, ok := v.Value().(string)
			if !ok || value == "" {
				continue
			}
			flagsVariant, ok := section[key+"-flags"]
			if !ok {
				continue
			}
			flags, ok := flagsVariant.Value().(uint32)
			if !ok || flags&nmSecretFlagAgentOwned == 0 {
				continue
			}
			if out[setting] == nil {
				out[setting] = make(map[string]string)
			}
			out[setting][key] = value
		}
	}
	return out
}

func readSSID(conn map[string]nmVariantMap) string {
	if w, ok := conn["802-11-wireless"]; ok {
		if v, ok := w["ssid"]; ok {
			if b, ok := v.Value().([]byte); ok {
				return string(b)
			}
			if s, ok := v.Value().(string); ok {
				return s
			}
		}
	}
	return ""
}

func readConnTypeAndName(conn map[string]nmVariantMap) (string, string, string) {
	var connType, name, svc string
	if c, ok := conn["connection"]; ok {
		if v, ok := c["type"]; ok {
			if s, ok2 := v.Value().(string); ok2 {
				connType = s
			}
		}
		if v, ok := c["id"]; ok {
			if s, ok2 := v.Value().(string); ok2 {
				name = s
			}
		}
	}
	if vpn, ok := conn["vpn"]; ok {
		if v, ok := vpn["service-type"]; ok {
			if s, ok2 := v.Value().(string); ok2 {
				svc = s
			}
		}
	}
	if name == "" && connType == "802-11-wireless" {
		name = readSSID(conn)
	}
	return connType, name, svc
}

func fieldsNeeded(setting string, hints []string, conn map[string]nmVariantMap) []string {
	switch setting {
	case "802-11-wireless-security":
		return []string{"psk"}
	case "802-1x":
		if len(hints) > 0 {
			return hints
		}
		return infer8021xFields(conn)
	case "vpn":
		return parseVPNHints(hints).fields
	case "wireguard":
		return hints
	default:
		return []string{}
	}
}

const (
	vpnHintMessagePrefix       = "x-vpn-message:"
	vpnHintChallengePrefix     = "x-dynamic-challenge:"
	vpnHintChallengeEchoPrefix = "x-dynamic-challenge-echo:"
)

type vpnPromptHints struct {
	fields []string
	echo   map[string]bool
}

// NM-openvpn asks for a CRV1 challenge answer as x-dynamic-challenge[-echo]:<secret>
// and NM appends the plugin's prompt text as x-vpn-message:<text>, which the modal shows.
func parseVPNHints(hints []string) vpnPromptHints {
	parsed := vpnPromptHints{echo: map[string]bool{}}
	for _, hint := range hints {
		switch {
		case strings.HasPrefix(hint, vpnHintMessagePrefix):
		case strings.HasPrefix(hint, vpnHintChallengeEchoPrefix):
			field := strings.TrimPrefix(hint, vpnHintChallengeEchoPrefix)
			parsed.echo[field] = true
			parsed.fields = append(parsed.fields, field)
		case strings.HasPrefix(hint, vpnHintChallengePrefix):
			parsed.fields = append(parsed.fields, strings.TrimPrefix(hint, vpnHintChallengePrefix))
		default:
			parsed.fields = append(parsed.fields, hint)
		}
	}
	return parsed
}

func infer8021xFields(conn map[string]nmVariantMap) []string {
	dot1x, ok := conn["802-1x"]
	if !ok {
		return []string{"identity", "password"}
	}

	var fields []string

	if v, ok := dot1x["identity"]; ok {
		if id, ok := v.Value().(string); ok && id != "" {
			// identity already stored, don't ask again
		} else {
			fields = append(fields, "identity")
		}
	} else {
		fields = append(fields, "identity")
	}

	var eapMethods []string
	if v, ok := dot1x["eap"]; ok {
		if methods, ok := v.Value().([]string); ok {
			eapMethods = methods
		}
	}

	switch {
	case len(eapMethods) > 0 && eapMethods[0] == "tls":
		fields = append(fields, "private-key-password")
	default:
		fields = append(fields, "password")
	}

	return fields
}

func buildFieldsInfo(setting string, fields []string, hints []string, vpnService string) []FieldInfo {
	echo := parseVPNHints(hints).echo
	result := make([]FieldInfo, 0, len(fields))
	for _, f := range fields {
		info := FieldInfo{Name: f}
		switch setting {
		case "802-11-wireless-security":
			info.Label = "Password"
			info.IsSecret = true
		case "802-1x":
			switch f {
			case "identity":
				info.Label = "Username"
				info.IsSecret = false
			case "password":
				info.Label = "Password"
				info.IsSecret = true
			default:
				info.Label = f
				info.IsSecret = true
			}
		case "vpn":
			info.Label, info.IsSecret = vpnFieldMeta(f, vpnService)
			if echo[f] {
				info.IsSecret = false
			}
		default:
			info.Label = f
			info.IsSecret = true
		}
		result = append(result, info)
	}
	return result
}

func vpnDataFromSettings(conn map[string]nmVariantMap) map[string]string {
	vpnSettings, ok := conn["vpn"]
	if !ok {
		return map[string]string{}
	}
	dataVariant, ok := vpnSettings["data"]
	if !ok {
		return map[string]string{}
	}
	dataMap, ok := dataVariant.Value().(map[string]string)
	if !ok {
		return map[string]string{}
	}
	return dataMap
}

func inferVPNFields(conn map[string]nmVariantMap, vpnService string) []string {
	fields := []string{"password"}

	vpnSettings, ok := conn["vpn"]
	if !ok {
		return fields
	}

	dataVariant, ok := vpnSettings["data"]
	if !ok {
		return fields
	}

	dataMap, ok := dataVariant.Value().(map[string]string)
	if !ok {
		return fields
	}

	connType := dataMap["connection-type"]

	switch {
	case strings.Contains(vpnService, "openconnect"):
		protocol := dataMap["protocol"]
		authType := dataMap["authtype"]
		username := dataMap["username"]

		if authType == "cert" && strings.HasPrefix(dataMap["usercert"], "pkcs11:") {
			return []string{"key_pass"}
		}

		if needsExternalBrowserAuth(protocol, authType, username, dataMap) {
			switch protocol {
			case "gp":
				log.Infof("[SecretAgent] GlobalProtect SAML auth detected")
				return []string{"gp-saml"}
			case "fortinet":
				log.Infof("[SecretAgent] Fortinet SAML auth detected")
				return []string{"fortinet-saml"}
			default:
				log.Infof("[SecretAgent] External browser auth detected for protocol '%s' but only GlobalProtect (gp) and Fortinet SAML are currently supported, falling back to credentials", protocol)
			}
		}

		if username == "" {
			fields = []string{"username", "password"}
		}
	case strings.Contains(vpnService, "openvpn"):
		switch connType {
		case "tls":
			// Cert auth wants the private-key passphrase, not a password.
			if secretFlagsNotRequired(dataMap["cert-pass-flags"]) {
				return nil
			}
			return []string{"cert-pass"}
		case "password-tls":
			fields = []string{}
			if dataMap["username"] == "" {
				fields = append(fields, "username")
			}
			fields = append(fields, "password")
			if !secretFlagsNotRequired(dataMap["cert-pass-flags"]) {
				fields = append(fields, "cert-pass")
			}
		case "password":
			if dataMap["username"] == "" {
				fields = []string{"username", "password"}
			}
		}
	case strings.Contains(vpnService, "vpnc"), strings.Contains(vpnService, "l2tp"),
		strings.Contains(vpnService, "pptp"):
		if dataMap["username"] == "" {
			fields = []string{"username", "password"}
		}
	}

	return fields
}

// NetworkManager secret flags: bit 1 (value 2) marks a secret as not-saved,
// bit 2 (value 4) as not-required. A not-required secret must not be prompted.
func secretFlagsNotRequired(flags string) bool {
	if flags == "" {
		return false
	}
	n, err := strconv.Atoi(flags)
	if err != nil {
		return false
	}
	return n&0x4 != 0
}

func needsExternalBrowserAuth(protocol, authType, username string, data map[string]string) bool {
	if method, ok := data["saml-auth-method"]; ok {
		if method == "REDIRECT" || method == "POST" {
			return true
		}
	}

	if authType != "" && authType != "password" && authType != "cert" {
		return true
	}

	switch protocol {
	case "gp":
		if authType == "" && username == "" {
			return true
		}
	}

	return false
}

func vpnFieldMeta(field, _ string) (label string, isSecret bool) {
	switch field {
	case "gp-saml":
		return "GlobalProtect SAML/SSO", false
	case "fortinet-saml":
		return "Fortinet SAML/SSO", false
	case "key_pass":
		return "PIN", true
	case "password":
		return "Password", true
	case "Xauth password":
		return "IPSec Password", true
	case "IPSec secret":
		return "IPSec Pre-Shared Key", true
	case "cert-pass":
		return "Certificate Password", true
	case "challenge-response":
		return "Challenge Response", true
	case "http-proxy-password":
		return "HTTP Proxy Password", true
	case "username":
		return "Username", false
	case "Xauth username":
		return "IPSec Username", false
	case "proxy-password":
		return "Proxy Password", true
	case "private-key-password":
		return "Private Key Password", true
	}
	titleCaser := cases.Title(language.English)
	if strings.HasSuffix(field, "password") || strings.HasSuffix(field, "secret") ||
		strings.HasSuffix(field, "pass") || strings.HasSuffix(field, "psk") {
		return titleCaser.String(strings.ReplaceAll(field, "-", " ")), true
	}
	return titleCaser.String(strings.ReplaceAll(field, "-", " ")), false
}

func isPKCS11Auth(conn map[string]nmVariantMap, vpnService string) bool {
	if !strings.Contains(vpnService, "openconnect") {
		return false
	}
	vpnSettings, ok := conn["vpn"]
	if !ok {
		return false
	}
	dataVariant, ok := vpnSettings["data"]
	if !ok {
		return false
	}
	dataMap, ok := dataVariant.Value().(map[string]string)
	if !ok {
		return false
	}
	return dataMap["authtype"] == "cert" && strings.HasPrefix(dataMap["usercert"], "pkcs11:")
}

func readVPNPasswordFlags(conn map[string]nmVariantMap, settingName string) uint32 {
	if settingName != "vpn" {
		return 0xFFFF
	}

	vpnSettings, ok := conn["vpn"]
	if !ok {
		return 0xFFFF
	}

	dataVariant, ok := vpnSettings["data"]
	if !ok {
		return 0xFFFF
	}

	dataMap, ok := dataVariant.Value().(map[string]string)
	if !ok {
		return 0xFFFF
	}

	flagsStr, ok := dataMap["password-flags"]
	if !ok {
		return 0xFFFF
	}

	flags64, err := strconv.ParseUint(flagsStr, 10, 32)
	if err != nil {
		return 0xFFFF
	}

	return uint32(flags64)
}

func reasonFromFlags(flags uint32) string {
	const (
		NM_SECRET_AGENT_GET_SECRETS_FLAG_NONE              = 0x0
		NM_SECRET_AGENT_GET_SECRETS_FLAG_ALLOW_INTERACTION = 0x1
		NM_SECRET_AGENT_GET_SECRETS_FLAG_REQUEST_NEW       = 0x2
		NM_SECRET_AGENT_GET_SECRETS_FLAG_USER_REQUESTED    = 0x4
		NM_SECRET_AGENT_GET_SECRETS_FLAG_WPS_PBC_ACTIVE    = 0x8
		NM_SECRET_AGENT_GET_SECRETS_FLAG_ONLY_SYSTEM       = 0x80000000
		NM_SECRET_AGENT_GET_SECRETS_FLAG_NO_ERRORS         = 0x40000000
	)

	if flags&NM_SECRET_AGENT_GET_SECRETS_FLAG_REQUEST_NEW != 0 {
		return "wrong-password"
	}
	if flags&NM_SECRET_AGENT_GET_SECRETS_FLAG_USER_REQUESTED != 0 {
		return "user-requested"
	}
	return "required"
}

func buildWiFiSecretsResponse(settingName string, secrets map[string]string) nmSettingMap {
	sec := nmVariantMap{}
	switch settingName {
	case "802-1x":
		for k, v := range secrets {
			switch k {
			case "password", "private-key-password", "phase2-private-key-password", "pin":
				sec[k] = dbus.MakeVariant(v)
			}
		}
	default:
		for k, v := range secrets {
			sec[k] = dbus.MakeVariant(v)
		}
	}

	out := nmSettingMap{}
	out[settingName] = sec
	return out
}

func buildOpenConnectSecretsResponse(settingName, cookie, host, fingerprint string) nmSettingMap {
	out := nmSettingMap{}
	vpnSec := nmVariantMap{}

	secrets := map[string]string{
		"cookie":  cookie,
		"gateway": host,
		"gwcert":  fingerprint,
	}
	vpnSec["secrets"] = dbus.MakeVariant(secrets)

	out[settingName] = vpnSec
	return out
}
