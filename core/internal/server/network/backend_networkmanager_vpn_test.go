package network

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/Wifx/gonetworkmanager/v2"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	mock_dbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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
	assert.Empty(t, detectVPNAuthAction(service, map[string]string{
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

func TestEnsureOpenConnectAgentFlags(t *testing.T) {
	data := map[string]string{"protocol": "fortinet"}
	assert.True(t, setOpenConnectAgentFlags(data))
	assert.Equal(t, "2", data["cookie-flags"])
	assert.Equal(t, "2", data["gateway-flags"])
	assert.Equal(t, "2", data["gwcert-flags"])
	assert.False(t, setOpenConnectAgentFlags(data))
}

func TestOpenConnectCertificateConfirmation(t *testing.T) {
	binDir := t.TempDir()
	openConnectPath := filepath.Join(binDir, "openconnect")
	script := `#!/bin/sh
case "$*" in
  *--servercert=pin-sha256:TEST-FINGERPRINT*)
    printf '%s\n' "COOKIE='SVPNCOOKIE=test'" "HOST='vpn.example.test'" "FINGERPRINT='pin-sha256:TEST-FINGERPRINT'"
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

	broker := &fakePromptBroker{
		asked: make(chan PromptRequest, 1),
		reply: PromptReply{},
	}
	backend := &NetworkManagerBackend{promptBroker: broker}
	data := map[string]string{
		"gateway":  "vpn.example.test:443",
		"protocol": "fortinet",
		"authtype": "password",
		"username": "test-user",
	}

	result, err := backend.handleOpenConnectPasswordAuth(
		context.Background(), conn, "Test VPN", "test-uuid",
		"org.freedesktop.NetworkManager.openconnect", data,
	)
	assert.NoError(t, err)
	assert.Equal(t, "SVPNCOOKIE=test", result.Cookie)
	assert.Equal(t, "vpn.example.test:443", result.Host)

	prompt := <-broker.asked
	assert.Equal(t, "server-certificate", prompt.Reason)
	assert.Equal(t, []string{"pin-sha256:TEST-FINGERPRINT"}, prompt.Hints)

	assert.Equal(t, map[string]string{
		"certificate:vpn.example.test:443": "pin-sha256:TEST-FINGERPRINT",
	}, backend.pendingVPNSave.PersistentSecrets)
}

func TestOpenConnectCertificateRotationReprompts(t *testing.T) {
	binDir := t.TempDir()
	openConnectPath := filepath.Join(binDir, "openconnect")
	script := `#!/bin/sh
case "$*" in
  *--servercert=pin-sha256:NEW-FINGERPRINT*)
    printf '%s\n' "COOKIE='SVPNCOOKIE=test'" "HOST='vpn.example.test'" "FINGERPRINT='pin-sha256:NEW-FINGERPRINT'"
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

	broker := &fakePromptBroker{
		asked: make(chan PromptRequest, 1),
		reply: PromptReply{},
	}
	backend := &NetworkManagerBackend{promptBroker: broker}
	data := map[string]string{
		"gateway":  "vpn.example.test:443",
		"protocol": "fortinet",
		"authtype": "password",
		"username": "test-user",
	}

	result, err := backend.handleOpenConnectPasswordAuth(
		context.Background(), conn, "Test VPN", "test-uuid",
		"org.freedesktop.NetworkManager.openconnect", data,
	)
	assert.NoError(t, err)
	assert.Equal(t, "SVPNCOOKIE=test", result.Cookie)

	prompt := <-broker.asked
	assert.Equal(t, "server-certificate-changed", prompt.Reason)
	assert.Equal(t, []string{"pin-sha256:NEW-FINGERPRINT"}, prompt.Hints)

	assert.Equal(t, map[string]string{
		"certificate:vpn.example.test:443": "pin-sha256:OLD-FINGERPRINT,pin-sha256:NEW-FINGERPRINT",
	}, backend.pendingVPNSave.PersistentSecrets)
	assert.False(t, backend.pendingVPNSave.SavePassword)
	assert.Empty(t, backend.pendingVPNSave.Secrets)
}

func TestParseNmcliAddedUUID(t *testing.T) {
	const uuid = "0e1f2a3b-4c5d-6e7f-8091-a2b3c4d5e6f7"
	name, got := parseNmcliAddedUUID("Connection 'old' (11111111-1111-1111-1111-111111111111) successfully added.\nConnection 'my vpn (work)' (" + uuid + ") successfully added.\n")
	assert.Equal(t, "my vpn (work)", name)
	assert.Equal(t, uuid, got)
	name, got = parseNmcliAddedUUID("Error: failed to import\n")
	assert.Empty(t, name+got)
}

func storedVPNProfile() nmSettings {
	return nmSettings{
		"connection": {"id": dbus.MakeVariant("office"), "uuid": dbus.MakeVariant("vpn-uuid"), "type": dbus.MakeVariant("vpn")},
		"vpn":        {"data": dbus.MakeVariant(map[string]string{"remote": "vpn.example.com"})},
		"ipv4":       {"dns-data": dbus.MakeVariant([]string{"10.0.0.53"})},
		"ipv6":       {"method": dbus.MakeVariant("auto")},
	}
}

func TestVPNProfileWritesKeepIPSectionsAndSecrets(t *testing.T) {
	const path = dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/7")
	tests := []struct {
		name    string
		run     func(b *NetworkManagerBackend) error
		secrets map[string]string
		data    map[string]string
		noWrite bool // a wireguard profile has no stored credentials to clear
	}{
		{"config update", func(b *NetworkManagerBackend) error {
			return b.UpdateVPNConfig("vpn-uuid", map[string]any{"data": map[string]any{"remote": "vpn2.example.com"}})
		}, map[string]string{"cert-pass": "b", "password": "hunter2"}, map[string]string{"remote": "vpn2.example.com"}, false},
		{"save credentials", func(b *NetworkManagerBackend) error {
			b.saveVPNCredentials(&pendingVPNCredentials{ConnectionPath: string(path), Username: "alice", Password: "pw", SavePassword: true})
			return nil
		}, map[string]string{"cert-pass": "b", "password": "pw"}, map[string]string{"remote": "vpn.example.com", "username": "alice", "password-flags": "0"}, false},
		{"clear credentials", func(b *NetworkManagerBackend) error { return b.ClearVPNCredentials("vpn-uuid") },
			nil, map[string]string{"remote": "vpn.example.com", "password-flags": "1"}, false},
		{"clear wireguard credentials", func(b *NetworkManagerBackend) error { return b.ClearVPNCredentials("vpn-uuid") },
			nil, nil, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			obj := mock_dbus.NewMockBusObject(t)
			backend, err := NewNetworkManagerBackend(mock_gonetworkmanager.NewMockNetworkManager(t))
			require.NoError(t, err)
			backend.nmObjectFn = func(dbus.ObjectPath) dbus.BusObject { return obj }
			conn := mock_gonetworkmanager.NewMockConnection(t)
			conn.EXPECT().GetPath().Return(path).Maybe()
			conn.EXPECT().ClearSecrets().Return(nil).Maybe()
			conn.EXPECT().GetSettings().Return(gonetworkmanager.ConnectionSettings{"connection": {"id": "office", "uuid": "vpn-uuid", "type": map[bool]string{false: "vpn", true: "wireguard"}[tt.noWrite]}}, nil).Maybe()
			settings := mock_gonetworkmanager.NewMockSettings(t)
			settings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{conn}, nil).Maybe()
			backend.settings = settings
			if tt.noWrite {
				require.NoError(t, tt.run(backend))
				return
			}
			expectGetSettings(obj, storedVPNProfile())
			expectGetSecrets(obj, "vpn", nmSettings{"vpn": {"secrets": dbus.MakeVariant(map[string]string{"cert-pass": "b", "password": "hunter2"})}})
			got := captureUpdate2(obj, nmUpdate2FlagToDisk, nil)

			require.NoError(t, tt.run(backend))

			s := *got
			assert.Equal(t, []string{"10.0.0.53"}, s["ipv4"]["dns-data"].Value())
			assert.Contains(t, s, "ipv6")
			assert.Equal(t, tt.data, s["vpn"]["data"].Value())
			if tt.secrets == nil {
				assert.NotContains(t, s["vpn"], "secrets")
			} else {
				assert.Equal(t, tt.secrets, s["vpn"]["secrets"].Value())
			}
		})
	}
}

func TestWireGuardImport(t *testing.T) {
	name, cp := wireGuardImportName("/x/protonvpn-DE-523.conf")
	assert.Equal(t, "protonvpn-DE-52", name)
	assert.True(t, cp)
	_, cp = wireGuardImportName("/x/wg0.conf")
	assert.False(t, cp)
	assert.True(t, looksLikeWireGuardConfig([]byte("[Interface]\nprivatekey = abc\n[Peer]\n")))
	assert.False(t, looksLikeWireGuardConfig([]byte("client\ndev tun\n")))

	src := filepath.Join(t.TempDir(), "My VPN.conf")
	require.NoError(t, os.WriteFile(src, []byte("[Interface]\nPrivateKey=abc\n"), 0o600))
	staged, cleanup, err := stageWireGuardImport(src)
	require.NoError(t, err)
	assert.Equal(t, "MyVPN.conf", filepath.Base(staged))
	cleanup()
	_, err = os.Stat(staged)
	assert.True(t, os.IsNotExist(err))
}

// A FortiGate HA cluster answers from either node; once both pins are trusted, neither may prompt.
func TestOpenConnectTrustedPinsForEveryNode(t *testing.T) {
	binDir := t.TempDir()
	openConnectPath := filepath.Join(binDir, "openconnect")
	script := `#!/bin/sh
case "$*" in
  *--servercert=pin-sha256:NODE-A*--servercert=pin-sha256:NODE-B*)
    printf '%s\n' "COOKIE='SVPNCOOKIE=test'" "HOST='vpn.example.test'" "FINGERPRINT='pin-sha256:NODE-B'"
    exit 0
    ;;
esac
printf '%s\n' 'Add --servercert pin-sha256:NODE-B' >&2
exit 1
`
	assert.NoError(t, os.WriteFile(openConnectPath, []byte(script), 0o755))
	t.Setenv("PATH", binDir)

	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetSecrets("vpn").Return(gonetworkmanager.ConnectionSettings{
		"vpn": {"secrets": map[string]string{
			"password":                         "test-password",
			"certificate:vpn.example.test:443": "pin-sha256:NODE-A,pin-sha256:NODE-B",
		}},
	}, nil)

	broker := &fakePromptBroker{asked: make(chan PromptRequest, 1)}
	backend := &NetworkManagerBackend{promptBroker: broker}
	data := map[string]string{
		"gateway":  "vpn.example.test:443",
		"protocol": "fortinet",
		"authtype": "password",
		"username": "test-user",
	}

	result, err := backend.handleOpenConnectPasswordAuth(
		context.Background(), conn, "Test VPN", "test-uuid",
		"org.freedesktop.NetworkManager.openconnect", data,
	)
	assert.NoError(t, err)
	assert.Equal(t, "SVPNCOOKIE=test", result.Cookie)
	assert.Equal(t, "pin-sha256:NODE-B", result.Fingerprint)
	assert.Empty(t, broker.asked)
	assert.Nil(t, backend.pendingVPNSave)
}

func TestAppendServerCertPin(t *testing.T) {
	tests := []struct {
		name    string
		trusted string
		pin     string
		want    string
	}{
		{"empty list", "", "pin-sha256:A", "pin-sha256:A"},
		{"new pin is appended", "pin-sha256:A", "pin-sha256:B", "pin-sha256:A,pin-sha256:B"},
		{"known pin is not duplicated", "pin-sha256:A,pin-sha256:B", "pin-sha256:B", "pin-sha256:A,pin-sha256:B"},
		{"blank entries are dropped", " pin-sha256:A ,, ", "pin-sha256:B", "pin-sha256:A,pin-sha256:B"},
		{"pins are case sensitive", "pin-sha256:abc", "pin-sha256:ABC", "pin-sha256:abc,pin-sha256:ABC"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, appendServerCertPin(tt.trusted, tt.pin))
		})
	}
}
