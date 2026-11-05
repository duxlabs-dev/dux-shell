package network

import (
	"errors"
	"testing"

	mock_gonetworkmanager "github.com/AvengeMedia/DankMaterialShell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStoredOpenConnectSecretReadScope(t *testing.T) {
	const service = "org.freedesktop.NetworkManager.openconnect"
	const path = dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/999")
	for _, tt := range []struct {
		name, uuid, service, passwordFlags, protocol, authType string
		marked                                                 bool
	}{
		{name: "system owned", uuid: "test-uuid", service: service, passwordFlags: "0", marked: true},
		{name: "fortinet", uuid: "test-uuid", service: service, passwordFlags: "0", protocol: "fortinet", authType: "password", marked: true},
		{name: "agent owned", uuid: "test-uuid", service: service, passwordFlags: "1"},
		{name: "not saved", uuid: "test-uuid", service: service, passwordFlags: "2"},
		{name: "not required", uuid: "test-uuid", service: service, passwordFlags: "4"},
		{name: "unspecified", uuid: "test-uuid", service: service},
		{name: "malformed", uuid: "test-uuid", service: service, passwordFlags: "bad"},
		{name: "no uuid", service: service, passwordFlags: "0"},
		{name: "other service", uuid: "test-uuid", service: "org.freedesktop.NetworkManager.openvpn", passwordFlags: "0"},
		{name: "other protocol", uuid: "test-uuid", service: service, passwordFlags: "0", protocol: "gp"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			b := &NetworkManagerBackend{}
			conn := mock_gonetworkmanager.NewMockConnection(t)
			if tt.marked {
				conn.EXPECT().GetPath().Return(path).Once()
			}
			lookupErr := errors.New("synthetic read failure")
			conn.EXPECT().GetSecrets("vpn").RunAndReturn(func(string) (gonetworkmanager.ConnectionSettings, error) {
				assert.Equal(t, tt.marked, b.isReadingOpenConnectSecrets(tt.uuid, path))
				assert.False(t, b.isReadingOpenConnectSecrets("unrelated", path))
				assert.False(t, b.isReadingOpenConnectSecrets(tt.uuid, path+"1"))
				return nil, lookupErr
			}).Once()
			_, err := b.readStoredOpenConnectSecrets(conn, tt.uuid, tt.service, map[string]string{
				"password-flags": tt.passwordFlags, "protocol": tt.protocol, "authtype": tt.authType,
			})
			require.ErrorIs(t, err, lookupErr)
			assert.False(t, b.isReadingOpenConnectSecrets(tt.uuid, path))
			assert.Empty(t, b.openConnectSecretReads)
		})
	}
}

func TestStoredOpenConnectSecretReadOverlap(t *testing.T) {
	b := &NetworkManagerBackend{}
	const path = dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/999")
	started := make(chan struct{}, 2)
	release := make(chan struct{})
	done := make(chan error, 2)
	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetPath().Return(path).Twice()
	conn.EXPECT().GetSecrets("vpn").RunAndReturn(func(string) (gonetworkmanager.ConnectionSettings, error) {
		started <- struct{}{}
		<-release
		return nil, errors.New("synthetic read failure")
	}).Twice()
	for range 2 {
		go func() {
			_, err := b.readStoredOpenConnectSecrets(conn, "test-uuid", "org.freedesktop.NetworkManager.openconnect", map[string]string{"password-flags": "0"})
			done <- err
		}()
	}
	<-started
	<-started
	assert.True(t, b.isReadingOpenConnectSecrets("test-uuid", path))
	release <- struct{}{}
	require.Error(t, <-done)
	assert.True(t, b.isReadingOpenConnectSecrets("test-uuid", path), "one completed read must not clear the other's marker")
	release <- struct{}{}
	require.Error(t, <-done)
	assert.False(t, b.isReadingOpenConnectSecrets("test-uuid", path))
	assert.Empty(t, b.openConnectSecretReads)
}

func TestSecretAgentStoredOpenConnectRead(t *testing.T) {
	// Never contact the host's Secret Service for the nonmatching hinted case.
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-dms-test-session-bus")
	const path = dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/999")
	const service = "org.freedesktop.NetworkManager.openconnect"
	for _, tt := range []struct {
		name                            string
		uuid                            string
		path                            dbus.ObjectPath
		service, setting, passwordFlags string
		hints                           []string
		flags                           uint32
		wantSuccess                     bool
	}{
		{name: "matching", flags: 4, wantSuccess: true},
		{name: "uuid mismatch", uuid: "unrelated", flags: 4},
		{name: "path mismatch", path: path + "1", flags: 4},
		{name: "protocol service mismatch", service: "org.freedesktop.NetworkManager.openvpn", flags: 4},
		{name: "setting mismatch", setting: "unrelated", flags: 4},
		{name: "agent owned", passwordFlags: "1", flags: 4, wantSuccess: true},
		{name: "not saved", passwordFlags: "2", flags: 4, wantSuccess: true},
		{name: "hints", hints: []string{"password"}, flags: 4},
		{name: "no flags", flags: 0},
		{name: "unknown flags", flags: 0x14},
		{name: "allow interaction", flags: 5},
		{name: "request new", flags: 6},
		{name: "interactive new", flags: 7},
		{name: "only system", flags: 0x80000004},
	} {
		t.Run(tt.name, func(t *testing.T) {
			if tt.uuid == "" {
				tt.uuid = "test-uuid"
			}
			if tt.path == "" {
				tt.path = path
			}
			if tt.service == "" {
				tt.service = service
			}
			if tt.setting == "" {
				tt.setting = "vpn"
			}
			if tt.passwordFlags == "" {
				tt.passwordFlags = "0"
			}
			b := &NetworkManagerBackend{state: &BackendState{}, openConnectSecretReads: map[openConnectSecretRead]uint{{uuid: "test-uuid", path: path}: 1}}
			a := &SecretAgent{backend: b}
			conn := map[string]nmVariantMap{
				"connection": {"uuid": dbus.MakeVariant(tt.uuid), "type": dbus.MakeVariant("vpn")},
				"vpn":        {"service-type": dbus.MakeVariant(tt.service), "data": dbus.MakeVariant(map[string]string{"password-flags": tt.passwordFlags})},
			}
			out, err := a.GetSecrets(conn, tt.path, tt.setting, tt.hints, tt.flags)
			if !tt.wantSuccess {
				require.NotNil(t, err)
				assert.Nil(t, out)
				return
			}
			require.Nil(t, err)
			assert.Equal(t, nmSettingMap{"vpn": {"secrets": dbus.MakeVariant(map[string]string{})}}, out)
			delete(b.openConnectSecretReads, openConnectSecretRead{uuid: "test-uuid", path: path})
			_, err = a.GetSecrets(conn, path, "vpn", nil, 4)
			require.NotNil(t, err, "unmarked external request must still be rejected")
		})
	}
}

func TestSecretAgentStoredOpenConnectReadPreservesInteractiveRequest(t *testing.T) {
	const path = dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/999")
	broker := &fakePromptBroker{asked: make(chan PromptRequest, 1), reply: PromptReply{Secrets: map[string]string{"password": "DUMMY-PROMPTED-PASSWORD"}}}
	b := &NetworkManagerBackend{
		state:                  &BackendState{IsConnectingVPN: true, ConnectingVPNUUID: "test-uuid"},
		openConnectSecretReads: map[openConnectSecretRead]uint{{uuid: "test-uuid", path: path}: 1},
	}
	a := &SecretAgent{backend: b, prompts: broker}
	conn := map[string]nmVariantMap{
		"connection": {"uuid": dbus.MakeVariant("test-uuid"), "type": dbus.MakeVariant("vpn")},
		"vpn":        {"service-type": dbus.MakeVariant("org.freedesktop.NetworkManager.openconnect"), "data": dbus.MakeVariant(map[string]string{"protocol": "gp", "username": "dummy-user", "password-flags": "0"})},
	}
	out, err := a.GetSecrets(conn, path, "vpn", nil, 7)
	require.Nil(t, err)
	assert.Equal(t, map[string]string{"password": "DUMMY-PROMPTED-PASSWORD"}, out["vpn"]["secrets"].Value())
	assert.Equal(t, "wrong-password", (<-broker.asked).Reason)

	cached := &cachedOpenConnectAuth{ConnectionUUID: "test-uuid", Cookie: "DUMMY-COOKIE", Host: "invalid.example"}
	b.cachedOpenConnectAuth = cached
	out, err = a.GetSecrets(conn, path, "vpn", []string{"cookie"}, 4)
	require.NotNil(t, err)
	assert.Equal(t, "org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", err.Name)
	assert.Nil(t, out)
	assert.Same(t, cached, b.cachedOpenConnectAuth, "noninteractive request must preserve one-shot authentication")
	out, err = a.GetSecrets(conn, path, "vpn", []string{"cookie"}, 5)
	require.Nil(t, err)
	assert.Equal(t, "DUMMY-COOKIE", out["vpn"]["secrets"].Value().(map[string]string)["cookie"])
	assert.Nil(t, b.cachedOpenConnectAuth, "interactive request must consume one-shot authentication")
	assert.Empty(t, broker.asked)
}
