package network

import (
	"bytes"
	"encoding/json"
	"net"
	"testing"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-go/ipc"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type e2eConn struct {
	net.Conn
	out bytes.Buffer
}

func (c *e2eConn) Write(b []byte) (int, error)      { return c.out.Write(b) }
func (c *e2eConn) Close() error                     { return nil }
func (c *e2eConn) SetWriteDeadline(time.Time) error { return nil }

// e2eRequest sends one request through HandleRequest and decodes the response.
func e2eRequest(t *testing.T, b Backend, method string, params map[string]any) ipc.Response[json.RawMessage] {
	t.Helper()
	c := &e2eConn{}
	HandleRequest(ipc.NewConnWriter(c), ipc.Request{ID: 1, Method: method, Params: params}, NewTestManager(b, &NetworkState{}))
	var resp ipc.Response[json.RawMessage]
	require.NoError(t, json.NewDecoder(&c.out).Decode(&resp))
	return resp
}

func manualIPProfile(typ string, extra nmSettings) nmSettings {
	s := connSection("u1", "Home", typ, map[string]dbus.Variant{"autoconnect": dbus.MakeVariant(true)})
	s["ipv4"] = map[string]dbus.Variant{
		"method":       dbus.MakeVariant("manual"),
		"addresses":    dbus.MakeVariant([][]uint32{{0x0100a8c0, 24, 0x0101a8c0}}),
		"address-data": dbus.MakeVariant([]map[string]dbus.Variant{{"address": dbus.MakeVariant("192.168.0.1"), "prefix": dbus.MakeVariant(uint32(24))}}),
		"gateway":      dbus.MakeVariant("192.168.1.1"),
		"dns":          dbus.MakeVariant([]uint32{0x01010101}),
		"dns-data":     dbus.MakeVariant([]string{"1.1.1.1"}),
	}
	s["ipv6"] = map[string]dbus.Variant{
		"method":       dbus.MakeVariant("manual"),
		"addresses":    dbus.MakeVariant([]legacyIP6Addr{{Addr: make([]byte, 16), Prefix: 64, Gateway: make([]byte, 16)}}),
		"address-data": dbus.MakeVariant([]map[string]dbus.Variant{{"address": dbus.MakeVariant("fd00::1"), "prefix": dbus.MakeVariant(uint32(64))}}),
		"dns-data":     dbus.MakeVariant([]string{"2001:db8::53"}),
	}
	for k, v := range extra {
		s[k] = v
	}
	return s
}

func TestE2E_ConnectionUpdate_KeepsDNSGatewayAndSecrets(t *testing.T) {
	f := newEditorFixture(t)
	obj := f.profile(t, "u1", "/s/1")
	expectGetSettings(obj, manualIPProfile("802-11-wireless", nmSettings{
		"802-11-wireless-security": {"key-mgmt": dbus.MakeVariant("wpa-psk")},
	}))
	expectPSKSecret(obj)
	got := captureUpdate2(obj, 0, nil)

	resp := e2eRequest(t, f.backend, "network.connection.update", map[string]any{
		"uuid":     "u1",
		"settings": map[string]any{"connection": map[string]any{"autoconnect": false}},
	})

	require.Empty(t, resp.Error)
	s := *got
	assert.Equal(t, false, s["connection"]["autoconnect"].Value())
	assert.Equal(t, "hunter22", s["802-11-wireless-security"]["psk"].Value())
	assert.Equal(t, "192.168.1.1", s["ipv4"]["gateway"].Value())
	assert.Equal(t, []string{"1.1.1.1"}, s["ipv4"]["dns-data"].Value())
	assert.Contains(t, s["ipv4"], "address-data")
	assert.Contains(t, s["ipv6"], "address-data")
	for _, key := range []string{"addresses", "dns"} {
		assert.NotContains(t, s["ipv4"], key)
	}
	assert.NotContains(t, s["ipv6"], "addresses")
}

func TestE2E_ConnectionUpdate_NMRejectionSurfacesVerbatim(t *testing.T) {
	f := newEditorFixture(t)
	obj := f.profile(t, "u1", "/s/1")
	pskProfile(obj)
	expectPSKSecret(obj)
	// captureUpdate2 expects exactly one call, so a retry would fail the test.
	captureUpdate2(obj, 0, dbus.Error{
		Name: "org.freedesktop.NetworkManager.Settings.Connection.InvalidProperty",
		Body: []any{"ipv4.method: property is invalid"},
	})

	resp := e2eRequest(t, f.backend, "network.connection.update", map[string]any{
		"uuid":     "u1",
		"settings": map[string]any{"ipv4": map[string]any{"method": "bogus"}},
	})

	assert.Contains(t, resp.Error, "ipv4.method: property is invalid")
}

func TestE2E_ConnectionDuplicateThenDelete(t *testing.T) {
	f := newEditorFixture(t)
	obj := f.profile(t, "u1", "/s/1")
	expectFlags(obj, 0)
	pskProfile(obj)
	expectPSKSecret(obj)
	added := captureAddConnection(f.object(t, nmSettingsPath), nmSettingsAddConnection)

	resp := e2eRequest(t, f.backend, "network.connection.duplicate", map[string]any{"uuid": "u1", "name": "Copy"})
	require.Empty(t, resp.Error)
	var res struct{ UUID string }
	require.NoError(t, json.Unmarshal(*resp.Result, &res))

	s := *added
	assert.NotEqual(t, "u1", res.UUID)
	assert.Equal(t, res.UUID, s["connection"]["uuid"].Value())
	assert.Equal(t, "Copy", s["connection"]["id"].Value())

	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().Delete().Return(nil).Once()
	f.settings.EXPECT().GetConnectionByUUID(res.UUID).Return(conn, nil).Once()

	resp = e2eRequest(t, f.backend, "network.connection.delete", map[string]any{"uuid": res.UUID})
	assert.Empty(t, resp.Error)
}

func TestE2E_EthernetConnectAndDisconnectPerDevice(t *testing.T) {
	f := newEthernetFixture(t, mockWiredProfile(t, "wired-a", "enp6s0", nil))
	ac := activeConnection(t, "wired-a")
	dev := f.addDevice(t, "enp6s0", hwEnp6s0, gonetworkmanager.NmDeviceStateActivated, ac)
	f.nm.EXPECT().ActivateConnection(mock.MatchedBy(isAutoConnection), dev, (*dbus.Object)(nil)).Return(nil, nil).Once()
	dev.EXPECT().Disconnect().Return(nil).Once()

	resp := e2eRequest(t, f.backend, "network.ethernet.connect", map[string]any{"device": "enp6s0"})
	assert.Empty(t, resp.Error)
	resp = e2eRequest(t, f.backend, "network.ethernet.disconnect", map[string]any{"device": "enp6s0"})
	assert.Empty(t, resp.Error)
}

func TestE2E_VPNAutoconnectToggle_KeepsDNSAndAddresses(t *testing.T) {
	f := newEditorFixture(t)
	const path = dbus.ObjectPath("/s/wg")
	obj := f.object(t, path)

	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetPath().Return(path).Maybe()
	conn.EXPECT().GetSettings().Return(gonetworkmanager.ConnectionSettings{
		"connection": {"id": "wg0", "uuid": "wg-uuid", "type": "wireguard"},
	}, nil)
	f.settings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{conn}, nil)

	s := manualIPProfile("wireguard", nmSettings{
		"wireguard": {"private-key-flags": dbus.MakeVariant(uint32(0))},
	})
	s["connection"]["uuid"] = dbus.MakeVariant("wg-uuid")
	expectGetSettings(obj, s)
	expectGetSecrets(obj, "wireguard", nmSettings{"wireguard": {"private-key": dbus.MakeVariant("KEY")}})
	got := captureUpdate2(obj, nmUpdate2FlagToDisk, nil)

	resp := e2eRequest(t, f.backend, "network.vpn.updateConfig", map[string]any{"uuid": "wg-uuid", "autoconnect": false})

	require.Empty(t, resp.Error)
	p := *got
	assert.Equal(t, false, p["connection"]["autoconnect"].Value())
	assert.Equal(t, []string{"1.1.1.1"}, p["ipv4"]["dns-data"].Value())
	assert.Equal(t, []string{"2001:db8::53"}, p["ipv6"]["dns-data"].Value())
	assert.Contains(t, p["ipv6"], "address-data")
	assert.Equal(t, "KEY", p["wireguard"]["private-key"].Value())
}
