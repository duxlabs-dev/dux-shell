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

func TestVPNAuthRouting(t *testing.T) {
	const nm = "org.freedesktop.NetworkManager."
	tests := []struct {
		name, service string
		data          map[string]string
		action        string
		pluginLogin   bool
	}{
		{"openvpn", nm + "openvpn", map[string]string{"connection-type": "password", "username": "u"}, "", false},
		{"anyconnect password", nm + "openconnect", map[string]string{"protocol": "anyconnect", "authtype": "password"}, "openconnect_password", false},
		{"openconnect no authtype", nm + "openconnect", map[string]string{}, "openconnect_password", false},
		{"fortinet password", nm + "openconnect", map[string]string{"protocol": "fortinet", "authtype": "password"}, "openconnect_password", false},
		{"openconnect cert", nm + "openconnect", map[string]string{"authtype": "cert", "usercert": "/home/u/cert.pem"}, "", true},
		{"pkcs11", nm + "openconnect", map[string]string{"authtype": "cert", "usercert": "pkcs11:id=1"}, "", false},
		{"gp saml", nm + "openconnect", map[string]string{"protocol": "gp"}, "gp_saml", false},
		{"fortinet saml", nm + "openconnect", map[string]string{"protocol": "fortinet", "saml-auth-method": "REDIRECT"}, "fortinet_saml", false},
		{"anyconnect saml", nm + "openconnect", map[string]string{"protocol": "anyconnect", "saml-auth-method": "REDIRECT"}, "", true},
		{"vpnc", nm + "vpnc", map[string]string{"IPSec gateway": "vpn.example.com"}, "", true},
		{"gpclient", nm + "gpclient", map[string]string{"protocol": "gp"}, "", true},
		{"no data", nm + "vpnc", nil, "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.action, detectVPNAuthAction(tt.service, tt.data))
			assert.Equal(t, tt.pluginLogin, vpnPluginLogin(tt.service, tt.data))
		})
	}
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
	stored := map[string]string{"password": "test-password"}
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
		"org.freedesktop.NetworkManager.openconnect", data, stored,
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
	stored := map[string]string{
		"password":                         "test-password",
		"certificate:vpn.example.test:443": "pin-sha256:OLD-FINGERPRINT",
	}
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
		"org.freedesktop.NetworkManager.openconnect", data, stored,
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
	stored := map[string]string{
		"password":                         "test-password",
		"certificate:vpn.example.test:443": "pin-sha256:NODE-A,pin-sha256:NODE-B",
	}

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
		"org.freedesktop.NetworkManager.openconnect", data, stored,
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

// useFakeVPNPlugins writes an executable auth dialog and a .name file per
// service into dir, points vpnPluginDirs at it, and returns the dialog path.
func useFakeVPNPlugins(t *testing.T, dir string, services ...string) string {
	dialog := filepath.Join(dir, "dialog")
	assert.NoError(t, os.WriteFile(dialog, []byte("#!/bin/sh\n"), 0o755))
	for _, svc := range services {
		content := "[VPN Connection]\nservice=org.freedesktop.NetworkManager." + svc + "\n[GNOME]\nauth-dialog=" + dialog + "\n"
		assert.NoError(t, os.WriteFile(filepath.Join(dir, svc+".name"), []byte(content), 0o644))
	}
	orig := vpnPluginDirs
	vpnPluginDirs = []string{dir}
	t.Cleanup(func() { vpnPluginDirs = orig })
	return dialog
}

func TestAuthDialogPlugin(t *testing.T) {
	dir := t.TempDir()
	exe := useFakeVPNPlugins(t, dir)
	noexec := filepath.Join(dir, "noexec")
	assert.NoError(t, os.WriteFile(noexec, []byte("#!/bin/sh\n"), 0o644))

	nameFile := func(service, body string) {
		content := "[VPN Connection]\nname=x\nservice=" + service + "\n" + body
		assert.NoError(t, os.WriteFile(filepath.Join(dir, service+".name"), []byte(content), 0o644))
	}
	nameFile("org.freedesktop.NetworkManager.good", "[GNOME]\nauth-dialog = "+exe+"\nsupports-external-ui-mode=true\n")
	nameFile("org.freedesktop.NetworkManager.legacy", "supports-external-ui-mode=true\n[GNOME]\nauth-dialog="+exe+"\n")
	nameFile("org.freedesktop.NetworkManager.noexec", "[GNOME]\nauth-dialog="+noexec+"\n")
	nameFile("org.freedesktop.NetworkManager.relative", "[GNOME]\nauth-dialog=dialog\n")

	t.Chdir(dir)

	tests := []struct {
		service string
		wantNil bool
		wantExt bool
	}{
		{"org.freedesktop.NetworkManager.good", false, true},
		{"legacy", false, false},
		{"noexec", true, false},
		{"relative", true, false},
		{"unknown", true, false},
	}
	for _, tt := range tests {
		t.Run(tt.service, func(t *testing.T) {
			p := authDialogPlugin(scanVPNPlugins(), tt.service)
			if tt.wantNil {
				assert.Nil(t, p)
				return
			}
			assert.Equal(t, exe, p.AuthDialog)
			assert.Equal(t, tt.wantExt, p.ExternalUIMode)
		})
	}
}

func TestListVPNProfilesPluginLogin(t *testing.T) {
	useFakeVPNPlugins(t, t.TempDir(), "vpnc", "l2tp")

	profile := func(name string, data map[string]string) gonetworkmanager.Connection {
		conn := mock_gonetworkmanager.NewMockConnection(t)
		conn.EXPECT().GetSettings().Return(gonetworkmanager.ConnectionSettings{
			"connection": {"id": name, "uuid": name, "type": "vpn"},
			"vpn":        {"service-type": "org.freedesktop.NetworkManager." + name, "data": data},
		}, nil)
		return conn
	}
	settings := mock_gonetworkmanager.NewMockSettings(t)
	settings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{
		profile("vpnc", map[string]string{"Xauth password-flags": "1"}),
		profile("l2tp", map[string]string{"password-flags": "1"}),
	}, nil)

	profiles, err := (&NetworkManagerBackend{settings: settings, state: &BackendState{}}).ListVPNProfiles()
	assert.NoError(t, err)
	got := map[string]bool{}
	for _, p := range profiles {
		got[p.Name] = p.PluginLogin
	}
	assert.Equal(t, map[string]bool{"vpnc": true, "l2tp": false}, got)
}

func TestMarkSecretsNotSaved(t *testing.T) {
	data := map[string]string{"IPSec secret-flags": "1"}
	secrets := map[string]string{"Xauth password": "x", "IPSec secret": "y", "password": "saved", "group": "new"}
	stored := map[string]string{"password": "saved", "group": "old"}
	assert.True(t, markSecretsNotSaved(data, secrets, stored))
	assert.Equal(t, map[string]string{"IPSec secret-flags": "1", "Xauth password-flags": "2", "group-flags": "2"}, data)
	assert.False(t, markSecretsNotSaved(data, map[string]string{"Xauth password": "x"}, nil))
}
