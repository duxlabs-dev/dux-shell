package network

import (
	"context"
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
		"certificate:vpn.example.test:443": "pin-sha256:NEW-FINGERPRINT",
	}, backend.pendingVPNSave.PersistentSecrets)
	assert.False(t, backend.pendingVPNSave.SavePassword)
	assert.Empty(t, backend.pendingVPNSave.Secrets)
}
