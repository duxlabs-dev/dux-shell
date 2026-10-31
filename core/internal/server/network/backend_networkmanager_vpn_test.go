package network

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/Wifx/gonetworkmanager/v2"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
)

func TestNetworkManagerBackend_ConnectVPN_NotFound(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockSettings := mock_gonetworkmanager.NewMockSettings(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)
	backend.settings = mockSettings

	mockSettings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{}, nil)

	err = backend.ConnectVPN("non-existent-vpn-12345", false)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not found")
}

func TestNetworkManagerBackend_DisconnectVPN_NotActive(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	mockNM.EXPECT().GetPropertyActiveConnections().Return([]gonetworkmanager.ActiveConnection{}, nil)

	err = backend.DisconnectVPN("non-existent-vpn-12345")
	assert.Error(t, err)
}

func TestDetectVPNAuthAction_Fortinet(t *testing.T) {
	service := "org.freedesktop.NetworkManager.openconnect"

	assert.Equal(t, "openconnect_password", detectVPNAuthAction(service, map[string]string{
		"protocol": "fortinet",
		"authtype": "password",
	}))
	assert.Equal(t, "openconnect_helper", detectVPNAuthAction(service, map[string]string{
		"protocol": "anyconnect",
		"authtype": "password",
	}))
	assert.Equal(t, "fortinet_saml", detectVPNAuthAction(service, map[string]string{
		"protocol": "fortinet",
		"authtype": "saml",
	}))
	assert.Equal(t, "fortinet_saml", detectVPNAuthAction(service, map[string]string{
		"protocol":         "fortinet",
		"saml-auth-method": "REDIRECT",
	}))
}

func TestOpenConnectAuthCacheActivationLifecycle(t *testing.T) {
	for _, tt := range []struct {
		name   string
		state  gonetworkmanager.NmActiveConnectionState
		absent bool
		retain bool
	}{
		{name: "activating", state: 1, retain: true},
		{name: "connected", state: 2},
		{name: "failed", state: 4},
		{name: "disappeared", absent: true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			nm := mock_gonetworkmanager.NewMockNetworkManager(t)
			backend := &NetworkManagerBackend{
				nmConn: nm,
				state:  &BackendState{IsConnectingVPN: true, ConnectingVPNUUID: "test-uuid"},
				cachedOpenConnectAuth: &cachedOpenConnectAuth{
					ConnectionUUID: "test-uuid",
					Cookie:         "COOKIE-VALUE",
				},
			}
			var active []gonetworkmanager.ActiveConnection
			if !tt.absent {
				conn := mock_gonetworkmanager.NewMockActiveConnection(t)
				conn.EXPECT().GetPropertyType().Return("vpn", nil)
				conn.EXPECT().GetPropertyUUID().Return("test-uuid", nil)
				conn.EXPECT().GetPropertyState().Return(tt.state, nil)
				conn.EXPECT().GetPropertyStateFlags().Return(0, nil)
				active = append(active, conn)
			}
			nm.EXPECT().GetPropertyActiveConnections().Return(active, nil)

			backend.updateVPNConnectionState()

			assert.Equal(t, tt.retain, backend.state.IsConnectingVPN)
			if tt.retain {
				assert.NotNil(t, backend.cachedOpenConnectAuth)
			} else {
				assert.Nil(t, backend.cachedOpenConnectAuth)
			}
		})
	}
}

func TestDetectVPNAuthAction(t *testing.T) {
	tests := []struct {
		name        string
		serviceType string
		data        map[string]string
		expected    string
	}{
		{name: "AnyConnect password", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "anyconnect", "authtype": "password"}, expected: "openconnect_helper"},
		{name: "AnyConnect absent auth type", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "anyconnect"}, expected: "openconnect_helper"},
		{name: "default protocol", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{}, expected: "openconnect_helper"},
		{name: "Fortinet password preserved", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "fortinet", "authtype": "password"}, expected: "openconnect_password"},
		{name: "Fortinet absent auth type remains unsupported", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "fortinet"}},
		{name: "GlobalProtect browser preserved", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "gp", "saml-auth-method": "REDIRECT"}, expected: "gp_saml"},
		{name: "AnyConnect detected browser does not fall through", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "anyconnect", "saml-auth-method": "POST"}},
		{name: "AnyConnect certificate auth", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "anyconnect", "authtype": "cert"}},
		{name: "AnyConnect user certificate", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "anyconnect", "usercert": "/tmp/user.pem"}},
		{name: "AnyConnect private key", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "anyconnect", "userkey": "/tmp/user.key"}},
		{name: "AnyConnect multi certificate", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "anyconnect", "mcacert": "/tmp/machine.pem"}},
		{name: "AnyConnect PKCS11", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "anyconnect", "usercert": "pkcs11:token=test"}},
		{name: "AnyConnect software token", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "anyconnect", "stoken_source": "totp"}},
		{name: "AnyConnect disabled token", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "anyconnect", "stoken_source": "disabled"}, expected: "openconnect_helper"},
		{name: "unsupported OpenConnect protocol", serviceType: "org.freedesktop.NetworkManager.openconnect", data: map[string]string{"protocol": "pulse", "authtype": "password"}},
		{name: "OpenVPN behavior preserved", serviceType: "org.freedesktop.NetworkManager.openvpn", data: map[string]string{"connection-type": "password"}, expected: "openvpn_username"},
		{name: "nil data", serviceType: "org.freedesktop.NetworkManager.openconnect", data: nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, detectVPNAuthAction(tt.serviceType, tt.data))
		})
	}
}

func TestUpdateOpenConnectAgentFlagsUsesFreshNonSecretSettings(t *testing.T) {
	data := map[string]string{
		"protocol":      "stale-protocol",
		"caller-only":   "must-not-be-written",
		"cookie-flags":  "2",
		"gateway-flags": "2",
		"gwcert-flags":  "2",
		"resolve-flags": "2",
	}
	connection := map[string]dbus.Variant{
		"id":   dbus.MakeVariant("Test VPN"),
		"uuid": dbus.MakeVariant("test-uuid"),
	}
	ipv4 := map[string]dbus.Variant{"method": dbus.MakeVariant("auto")}
	ipv6 := map[string]dbus.Variant{"method": dbus.MakeVariant("disabled")}
	proxy := map[string]dbus.Variant{"method": dbus.MakeVariant("none")}
	vpn := map[string]dbus.Variant{
		"service-type": dbus.MakeVariant("org.freedesktop.NetworkManager.openconnect"),
		"persistent":   dbus.MakeVariant(true),
		"data": dbus.MakeVariant(map[string]string{
			"protocol":       "anyconnect",
			"cookie-flags":   "2",
			"gateway":        "fresh.example.test",
			"unrelated-data": "preserved",
		}),
	}
	methods := []string{}

	err := updateOpenConnectAgentFlags(data, func(method string, result any, args ...any) error {
		methods = append(methods, method)
		switch method {
		case "org.freedesktop.NetworkManager.Settings.Connection.GetSettings":
			settings := result.(*map[string]map[string]dbus.Variant)
			*settings = map[string]map[string]dbus.Variant{
				"connection": connection,
				"vpn":        vpn,
				"ipv4":       ipv4,
				"ipv6":       ipv6,
				"proxy":      proxy,
			}
		case "org.freedesktop.NetworkManager.Settings.Connection.Update2":
			if len(args) != 3 {
				t.Fatalf("Update2 received %d arguments, want 3", len(args))
			}
			settings, ok := args[0].(map[string]map[string]dbus.Variant)
			if !ok {
				t.Fatalf("Update2 settings have type %T", args[0])
			}
			assert.Equal(t, connection, settings["connection"])
			assert.Equal(t, ipv4, settings["ipv4"])
			assert.Equal(t, ipv6, settings["ipv6"])
			assert.Equal(t, proxy, settings["proxy"])
			assert.Equal(t, vpn["service-type"], settings["vpn"]["service-type"])
			assert.Equal(t, vpn["persistent"], settings["vpn"]["persistent"])
			for _, setting := range settings {
				assert.NotContains(t, setting, "secrets")
			}
			assert.Equal(t, uint32(0x1), args[1])
			assert.Equal(t, map[string]dbus.Variant{}, args[2])

			updatedData, ok := settings["vpn"]["data"].Value().(map[string]string)
			if !ok {
				t.Fatalf("updated VPN data has type %T", settings["vpn"]["data"].Value())
			}
			assert.Equal(t, map[string]string{
				"protocol":       "anyconnect",
				"cookie-flags":   "2",
				"gateway-flags":  "2",
				"gwcert-flags":   "2",
				"resolve-flags":  "2",
				"gateway":        "fresh.example.test",
				"unrelated-data": "preserved",
			}, updatedData)
		default:
			t.Fatalf("unexpected D-Bus method %q", method)
		}
		return nil
	})

	assert.NoError(t, err)
	assert.Equal(t, []string{
		"org.freedesktop.NetworkManager.Settings.Connection.GetSettings",
		"org.freedesktop.NetworkManager.Settings.Connection.Update2",
	}, methods)
	assert.Equal(t, map[string]string{
		"protocol":       "anyconnect",
		"cookie-flags":   "2",
		"gateway-flags":  "2",
		"gwcert-flags":   "2",
		"resolve-flags":  "2",
		"gateway":        "fresh.example.test",
		"unrelated-data": "preserved",
	}, data)
}

func TestUpdateOpenConnectAgentFlagsIsIdempotentFromFreshSettings(t *testing.T) {
	data := map[string]string{"protocol": "stale", "caller-only": "removed"}
	freshData := map[string]string{
		"protocol":      "anyconnect",
		"cookie-flags":  "2",
		"gateway-flags": "2",
		"gwcert-flags":  "2",
		"resolve-flags": "2",
	}
	methods := []string{}

	err := updateOpenConnectAgentFlags(data, func(method string, result any, _ ...any) error {
		methods = append(methods, method)
		if method != "org.freedesktop.NetworkManager.Settings.Connection.GetSettings" {
			t.Fatalf("unexpected D-Bus method %q", method)
		}
		settings := result.(*map[string]map[string]dbus.Variant)
		*settings = map[string]map[string]dbus.Variant{
			"vpn": {"data": dbus.MakeVariant(freshData)},
		}
		return nil
	})

	assert.NoError(t, err)
	assert.Equal(t, []string{"org.freedesktop.NetworkManager.Settings.Connection.GetSettings"}, methods)
	assert.Equal(t, freshData, data)
}

func TestUpdateOpenConnectAgentFlagsPropagatesReadAndUpdateFailures(t *testing.T) {
	for _, tt := range []struct {
		name            string
		failedMethod    string
		expectedMethods []string
	}{
		{
			name:            "read",
			failedMethod:    "org.freedesktop.NetworkManager.Settings.Connection.GetSettings",
			expectedMethods: []string{"org.freedesktop.NetworkManager.Settings.Connection.GetSettings"},
		},
		{
			name:         "update",
			failedMethod: "org.freedesktop.NetworkManager.Settings.Connection.Update2",
			expectedMethods: []string{
				"org.freedesktop.NetworkManager.Settings.Connection.GetSettings",
				"org.freedesktop.NetworkManager.Settings.Connection.Update2",
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			original := map[string]string{"protocol": "stale", "cookie-flags": "1"}
			data := map[string]string{"protocol": "stale", "cookie-flags": "1"}
			methods := []string{}
			err := updateOpenConnectAgentFlags(data, func(method string, result any, _ ...any) error {
				methods = append(methods, method)
				if method == tt.failedMethod {
					return errors.New(tt.name + " failed")
				}
				if method != "org.freedesktop.NetworkManager.Settings.Connection.GetSettings" {
					t.Fatalf("unexpected D-Bus method %q", method)
				}
				settings := result.(*map[string]map[string]dbus.Variant)
				*settings = map[string]map[string]dbus.Variant{
					"vpn": {"data": dbus.MakeVariant(map[string]string{
						"protocol":     "anyconnect",
						"cookie-flags": "2",
					})},
				}
				return nil
			})

			assert.ErrorContains(t, err, tt.name+" failed")
			assert.Equal(t, tt.expectedMethods, methods)
			assert.Equal(t, original, data)
		})
	}
}

func TestOpenConnectPasswordHandlerRejectsAnyConnectBeforeReadingSecrets(t *testing.T) {
	for _, protocol := range []string{"anyconnect", ""} {
		t.Run("protocol="+protocol, func(t *testing.T) {
			conn := mock_gonetworkmanager.NewMockConnection(t)
			broker := &fakePromptBroker{asked: make(chan PromptRequest, 1)}
			backend := &NetworkManagerBackend{promptBroker: broker}
			result, err := backend.handleOpenConnectPasswordAuth(context.Background(), conn, "Synthetic VPN", "test-uuid",
				"org.freedesktop.NetworkManager.openconnect", map[string]string{
					"protocol": protocol, "authtype": "password", "gateway": "invalid.example", "username": "synthetic-user",
				})
			assert.ErrorContains(t, err, "not supported for protocol")
			assert.Nil(t, result)
			assert.Empty(t, broker.asked)
		})
	}
}

func TestFortinetCertificateConfirmation(t *testing.T) {
	for _, tt := range []struct {
		protocol     string
		expectedHost string
	}{
		{protocol: "fortinet", expectedHost: "vpn.example.test:443"},
	} {
		t.Run(tt.protocol, func(t *testing.T) {
			binDir := t.TempDir()
			openConnectPath := filepath.Join(binDir, "openconnect")
			script := `#!/bin/sh
case "$*" in
  *--servercert=pin-sha256:TEST-FINGERPRINT*)
    printf '%s\n' "COOKIE='SVPNCOOKIE=test'" "HOST='192.0.2.10'" "CONNECT_URL='https://redirect.example.test/ssl-vpn'" "FINGERPRINT='pin-sha256:TEST-FINGERPRINT'"
    exit 0
    ;;
esac
printf '%s\n' 'Add --servercert pin-sha256:TEST-FINGERPRINT' >&2
exit 1
`
			assert.NoError(t, os.WriteFile(openConnectPath, []byte(script), 0o755))
			t.Setenv("PATH", binDir)

			conn := mock_gonetworkmanager.NewMockConnection(t)
			connPath := dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/999")
			conn.EXPECT().GetSecrets("vpn").Return(gonetworkmanager.ConnectionSettings{
				"vpn": {"secrets": map[string]string{"password": "test-password"}},
			}, nil)
			conn.EXPECT().GetPath().Return(connPath).Twice()

			broker := &fakePromptBroker{asked: make(chan PromptRequest, 1)}
			backend := &NetworkManagerBackend{promptBroker: broker}
			data := map[string]string{
				"gateway":  "vpn.example.test:443",
				"protocol": tt.protocol,
				"authtype": "password",
				"username": "test-user",
			}

			result, err := backend.handleOpenConnectPasswordAuth(
				context.Background(), conn, "Test VPN", "test-uuid",
				"org.freedesktop.NetworkManager.openconnect", data,
			)
			assert.NoError(t, err)
			assert.Equal(t, "SVPNCOOKIE=test", result.Cookie)
			assert.Equal(t, tt.expectedHost, result.Host)

			prompt := <-broker.asked
			assert.Equal(t, "server-certificate", prompt.Reason)
			assert.Equal(t, []string{"pin-sha256:TEST-FINGERPRINT"}, prompt.Hints)
			assert.Equal(t, map[string]string{
				"certificate:vpn.example.test:443": "pin-sha256:TEST-FINGERPRINT",
			}, backend.pendingVPNSave.PersistentSecrets)
		})
	}
}

func TestFortinetCertificateRotationReprompts(t *testing.T) {
	for _, tt := range []struct {
		protocol     string
		expectedHost string
	}{
		{protocol: "fortinet", expectedHost: "vpn.example.test:443"},
	} {
		t.Run(tt.protocol, func(t *testing.T) {
			binDir := t.TempDir()
			openConnectPath := filepath.Join(binDir, "openconnect")
			script := `#!/bin/sh
case "$*" in
  *--servercert=pin-sha256:NEW-FINGERPRINT*)
    printf '%s\n' "COOKIE='SVPNCOOKIE=test'" "HOST='192.0.2.10'" "CONNECT_URL='https://redirect.example.test/ssl-vpn'" "FINGERPRINT='pin-sha256:NEW-FINGERPRINT'"
    exit 0
    ;;
esac
printf '%s\n' 'Add --servercert pin-sha256:NEW-FINGERPRINT' >&2
exit 1
`
			assert.NoError(t, os.WriteFile(openConnectPath, []byte(script), 0o755))
			t.Setenv("PATH", binDir)

			conn := mock_gonetworkmanager.NewMockConnection(t)
			connPath := dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/999")
			conn.EXPECT().GetSecrets("vpn").Return(gonetworkmanager.ConnectionSettings{
				"vpn": {"secrets": map[string]string{
					"password":                         "test-password",
					"certificate:vpn.example.test:443": "pin-sha256:OLD-FINGERPRINT",
				}},
			}, nil)
			conn.EXPECT().GetPath().Return(connPath).Twice()

			broker := &fakePromptBroker{asked: make(chan PromptRequest, 1)}
			backend := &NetworkManagerBackend{promptBroker: broker}
			data := map[string]string{
				"gateway":  "vpn.example.test:443",
				"protocol": tt.protocol,
				"authtype": "password",
				"username": "test-user",
			}

			result, err := backend.handleOpenConnectPasswordAuth(
				context.Background(), conn, "Test VPN", "test-uuid",
				"org.freedesktop.NetworkManager.openconnect", data,
			)
			assert.NoError(t, err)
			assert.Equal(t, "SVPNCOOKIE=test", result.Cookie)
			assert.Equal(t, tt.expectedHost, result.Host)

			prompt := <-broker.asked
			assert.Equal(t, "server-certificate-changed", prompt.Reason)
			assert.Equal(t, []string{"pin-sha256:NEW-FINGERPRINT"}, prompt.Hints)
			assert.Equal(t, map[string]string{
				"certificate:vpn.example.test:443": "pin-sha256:NEW-FINGERPRINT",
			}, backend.pendingVPNSave.PersistentSecrets)
			assert.False(t, backend.pendingVPNSave.SavePassword)
			assert.Empty(t, backend.pendingVPNSave.Secrets)
		})
	}
}

func TestFortinetStrictPKIRejectsCertificateExceptions(t *testing.T) {
	binDir := t.TempDir()
	argsPath := filepath.Join(binDir, "args")
	openConnectPath := filepath.Join(binDir, "openconnect")
	script := `#!/bin/sh
: > "$ARGS_FILE"
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$ARGS_FILE"
done
printf '%s\n' 'Add --servercert pin-sha256:NEW-FINGERPRINT' >&2
exit 1
`
	assert.NoError(t, os.WriteFile(openConnectPath, []byte(script), 0o755))
	t.Setenv("PATH", binDir)
	t.Setenv("ARGS_FILE", argsPath)

	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetSecrets("vpn").Return(gonetworkmanager.ConnectionSettings{
		"vpn": {"secrets": map[string]string{
			"password":                         "test-password",
			"certificate:vpn.example.test:443": "pin-sha256:OLD-FINGERPRINT",
		}},
	}, nil)
	broker := &fakePromptBroker{asked: make(chan PromptRequest, 1)}
	backend := &NetworkManagerBackend{promptBroker: broker}

	result, err := backend.handleOpenConnectPasswordAuth(
		context.Background(), conn, "Test VPN", "test-uuid",
		"org.freedesktop.NetworkManager.openconnect", map[string]string{
			"gateway":              "vpn.example.test:443",
			"protocol":             "fortinet",
			"authtype":             "password",
			"username":             "test-user",
			"cacert":               "/etc/ssl/test-ca.pem",
			"prevent_invalid_cert": "yes",
		},
	)
	assert.Error(t, err)
	assert.Nil(t, result)
	assert.Nil(t, backend.pendingVPNSave)
	select {
	case <-broker.asked:
		t.Fatal("strict PKI must not prompt for a certificate exception")
	default:
	}

	argsBytes, readErr := os.ReadFile(argsPath)
	assert.NoError(t, readErr)
	assert.Contains(t, string(argsBytes), "--cafile=/etc/ssl/test-ca.pem\n")
	assert.NotContains(t, string(argsBytes), "--servercert=")
}

func TestFortinetCertificatePromptCancellationStopsAuthentication(t *testing.T) {
	binDir := t.TempDir()
	attemptsPath := filepath.Join(binDir, "attempts")
	openConnectPath := filepath.Join(binDir, "openconnect")
	script := `#!/bin/sh
printf 'attempt\n' >> "$ATTEMPTS_FILE"
case "$*" in
  *--servercert=*)
    printf '%s\n' "COOKIE='must-not-be-returned'"
    exit 0
    ;;
esac
printf '%s\n' 'Add --servercert pin-sha256:TEST-FINGERPRINT' >&2
exit 1
`
	assert.NoError(t, os.WriteFile(openConnectPath, []byte(script), 0o755))
	t.Setenv("PATH", binDir)
	t.Setenv("ATTEMPTS_FILE", attemptsPath)

	conn := mock_gonetworkmanager.NewMockConnection(t)
	connPath := dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/999")
	conn.EXPECT().GetSecrets("vpn").Return(gonetworkmanager.ConnectionSettings{
		"vpn": {"secrets": map[string]string{"password": "test-password"}},
	}, nil)
	conn.EXPECT().GetPath().Return(connPath).Once()
	broker := &fakePromptBroker{
		asked: make(chan PromptRequest, 1),
		reply: PromptReply{Cancel: true},
	}
	backend := &NetworkManagerBackend{promptBroker: broker}

	result, err := backend.handleOpenConnectPasswordAuth(
		context.Background(), conn, "Test VPN", "test-uuid",
		"org.freedesktop.NetworkManager.openconnect", map[string]string{
			"gateway":  "vpn.example.test:443",
			"protocol": "fortinet",
			"authtype": "password",
			"username": "test-user",
		},
	)
	assert.ErrorContains(t, err, "certificate confirmation was cancelled")
	assert.Nil(t, result)
	assert.Nil(t, backend.pendingVPNSave)
	attempts, readErr := os.ReadFile(attemptsPath)
	assert.NoError(t, readErr)
	assert.Equal(t, "attempt\n", string(attempts))
}

func TestFortinetPasswordSaveChoice(t *testing.T) {
	for _, save := range []bool{false, true} {
		t.Run(fmt.Sprintf("save=%t", save), func(t *testing.T) {
			binDir := t.TempDir()
			openConnectPath := filepath.Join(binDir, "openconnect")
			script := "#!/bin/sh\nprintf '%s\\n' \"COOKIE='COOKIE-VALUE'\" \"HOST='vpn.example.test'\"\n"
			assert.NoError(t, os.WriteFile(openConnectPath, []byte(script), 0o755))
			t.Setenv("PATH", binDir)

			conn := mock_gonetworkmanager.NewMockConnection(t)
			connPath := dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/999")
			conn.EXPECT().GetSecrets("vpn").Return(gonetworkmanager.ConnectionSettings{
				"vpn": {"secrets": map[string]string{}},
			}, nil)
			conn.EXPECT().GetPath().Return(connPath).Twice()

			broker := &fakePromptBroker{
				asked: make(chan PromptRequest, 1),
				reply: PromptReply{
					Secrets: map[string]string{"username": "test-user", "password": "test-password"},
					Save:    save,
				},
			}
			backend := &NetworkManagerBackend{promptBroker: broker}
			result, err := backend.handleOpenConnectPasswordAuth(
				context.Background(), conn, "Test VPN", "test-uuid",
				"org.freedesktop.NetworkManager.openconnect", map[string]string{
					"gateway":  "vpn.example.test",
					"protocol": "fortinet",
					"authtype": "password",
				},
			)
			assert.NoError(t, err)
			assert.Equal(t, "COOKIE-VALUE", result.Cookie)

			prompt := <-broker.asked
			assert.Equal(t, []string{"username", "password"}, prompt.Fields)
			assert.Equal(t, "test-user", backend.pendingVPNSave.Username)
			assert.Equal(t, save, backend.pendingVPNSave.SavePassword)
			if save {
				assert.Equal(t, "test-password", backend.pendingVPNSave.Password)
				assert.Equal(t, map[string]string{"password": "test-password"}, backend.pendingVPNSave.Secrets)
			} else {
				assert.Empty(t, backend.pendingVPNSave.Password)
				assert.Empty(t, backend.pendingVPNSave.Secrets)
			}
		})
	}
}
