package network

import (
	"bytes"
	"encoding/json"
	"encoding/pem"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-go/ipc"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	mock_dbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// e2eRequest sends one request through HandleRequest and decodes the response.
func e2eRequest(t *testing.T, b Backend, method string, params map[string]any) ipc.Response[json.RawMessage] {
	t.Helper()
	c := newMockNetConn()
	HandleRequest(ipc.NewConnWriter(c), ipc.Request{ID: 1, Method: method, Params: params}, NewTestManager(b, &NetworkState{}))
	var resp ipc.Response[json.RawMessage]
	require.NoError(t, json.NewDecoder(c.writeBuf).Decode(&resp))
	return resp
}

type jm = map[string]any

// assertKeys checks "section.key" values in settings sent to NM; a nil value means the key is absent.
func assertKeys(t *testing.T, s any, want jm) {
	t.Helper()
	for k, w := range want {
		i := strings.LastIndex(k, ".")
		got := reflect.ValueOf(s).MapIndex(reflect.ValueOf(k[:i]))
		if got.IsValid() {
			got = got.MapIndex(reflect.ValueOf(k[i+1:]))
		}
		if !got.IsValid() {
			assert.Nil(t, w, k)
			continue
		}
		g := got.Interface()
		if v, ok := g.(dbus.Variant); ok {
			g = v.Value()
		}
		assert.Equal(t, w, g, k)
	}
}

func storedWireGuard() nmSettings {
	v := dbus.MakeVariant
	s := connSection("u1", "wg", "wireguard", nil)
	s["wireguard"] = map[string]dbus.Variant{"peers": v([]map[string]dbus.Variant{{
		"public-key": v("PEER"), "endpoint": v("192.0.2.1:51820"), "allowed-ips": v([]string{"10.99.0.0/24"}),
	}})}
	s["ipv4"] = map[string]dbus.Variant{"method": v("auto"), "dns-data": v([]string{"192.0.2.53"})}
	return s
}

var wgSecrets = nmSettings{"wireguard": {"private-key": dbus.MakeVariant("PRIV"), "peers": dbus.MakeVariant(
	[]map[string]dbus.Variant{{"public-key": dbus.MakeVariant("PEER"), "preshared-key": dbus.MakeVariant("stored-psk")}})}}

func TestE2E_EditorWrites(t *testing.T) {
	v := dbus.MakeVariant
	eth := connSection("u1", "Corp", "802-3-ethernet", nil)
	eth["ipv4"] = map[string]dbus.Variant{"method": v("auto"), "dns-data": v([]string{"192.0.2.53"})}
	eth["802-1x"] = map[string]dbus.Variant{"eap": v([]string{"ttls"}), "phase2-auth": v("pap"), "identity": v("old"), "ca-cert": v([]byte("der"))}
	eth["proxy"] = map[string]dbus.Variant{"method": v(int32(1)), "pac-url": v("http://192.0.2.1/p.pac")}
	ovpn := connSection("u1", "ovpn", "vpn", nil)
	ovpn["vpn"] = map[string]dbus.Variant{"service-type": v("org.freedesktop.NetworkManager.openvpn"), "data": v(map[string]string{"remote": "vpn.example.com"})}
	allowed := v([]string{"10.99.0.0/24"})

	for _, tc := range []struct {
		name, wantErr   string
		stored, secrets nmSettings
		nmErr           error
		flags           uint32
		req             jm
		want            jm
	}{
		{name: "nm rejection is surfaced", stored: eth, secrets: nmSettings{"802-1x": {}}, wantErr: "ipv4.method: property is invalid",
			nmErr: dbus.Error{Name: "org.freedesktop.NetworkManager.Settings.Connection.InvalidProperty", Body: []any{"ipv4.method: property is invalid"}},
			req:   jm{"settings": jm{"ipv4": jm{"method": "bogus"}}}},
		{name: "enterprise edit keeps stored certificate and proxy", stored: eth, secrets: nmSettings{"802-1x": {}},
			req:  jm{"settings": jm{"802-3-ethernet": jm{"mtu": float64(1400)}, "802-1x": jm{"identity": "stale"}}, "enterprise": jm{"eap": "ttls", "phase2": "pap", "identity": "new", "ca": "file"}},
			want: jm{"802-1x.ca-cert": []byte("der"), "802-1x.identity": "new", "802-3-ethernet.mtu": uint32(1400), "ipv4.dns-data": []string{"192.0.2.53"}, "proxy.pac-url": "http://192.0.2.1/p.pac", "proxy.method": int32(1)}},
		{name: "persist true writes to disk", stored: eth, secrets: nmSettings{"802-1x": {}}, flags: nmUpdate2FlagToDisk,
			req:  jm{"settings": jm{"802-3-ethernet": jm{"mtu": float64(1400)}}, "persist": true},
			want: jm{"802-3-ethernet.mtu": uint32(1400), "802-1x.ca-cert": []byte("der")}},
		{name: "null removes only that vpn secret", stored: ovpn, secrets: nmSettings{"vpn": {"secrets": v(map[string]string{"password": "pw", "cert-pass": "cp"})}},
			req:  jm{"settings": jm{"vpn": jm{"secrets": jm{"password": nil}}}},
			want: jm{"vpn.secrets": map[string]string{"cert-pass": "cp"}}},
		{name: "wireguard peer edit keeps psk and private key", stored: storedWireGuard(), secrets: wgSecrets,
			req:  jm{"settings": jm{"wireguard": jm{"peers": []any{jm{"public-key": "PEER", "allowed-ips": []any{"10.99.0.0/24"}, "endpoint": "198.51.100.7:51820"}}}}},
			want: jm{"wireguard.private-key": "PRIV", "ipv4.dns-data": []string{"192.0.2.53"}, "wireguard.peers": []map[string]dbus.Variant{{"public-key": v("PEER"), "allowed-ips": allowed, "endpoint": v("198.51.100.7:51820"), "preshared-key": v("stored-psk")}}}},
		{name: "wireguard added",
			req: jm{"settings": jm{"connection": jm{"id": "wg", "type": "wireguard", "interface-name": "dmstest0"}, "wireguard": jm{"private-key": "PRIV", "listen-port": float64(51820),
				"peers": []any{jm{"public-key": "PEER", "allowed-ips": []any{"10.99.0.0/24"}, "persistent-keepalive": float64(25)}}}, "ipv6": jm{"method": "ignore"}}},
			want: jm{"wireguard.private-key": "PRIV", "wireguard.listen-port": uint32(51820), "ipv6.method": "ignore",
				"wireguard.peers": []map[string]dbus.Variant{{"public-key": v("PEER"), "allowed-ips": allowed, "persistent-keepalive": v(uint32(25))}}}},
		{name: "gsm added",
			req:  jm{"settings": jm{"connection": jm{"id": "gsm", "type": "gsm"}, "gsm": jm{"apn": "internet.example", "auto-config": false, "password-flags": float64(2)}}},
			want: jm{"gsm.apn": "internet.example", "gsm.auto-config": false, "gsm.password-flags": uint32(2), "gsm.password": nil}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newEditorFixture(t)
			method := "network.connection.add"
			var got *nmSettings
			if tc.stored == nil {
				got = captureAddConnection(f.object(t, nmSettingsPath), nmSettingsAddConnection)
			} else {
				method = "network.connection.update"
				tc.req["uuid"] = "u1"
				obj := f.profile(t, "u1", "/s/1")
				expectGetSettings(obj, tc.stored)
				for sec, x := range tc.secrets {
					expectGetSecrets(obj, sec, nmSettings{sec: x})
				}
				got = captureUpdate2(obj, tc.flags, tc.nmErr)
			}

			resp := e2eRequest(t, f.backend, method, tc.req)

			if tc.wantErr != "" {
				assert.Contains(t, resp.Error, tc.wantErr)
				return
			}
			require.Empty(t, resp.Error)
			assertKeys(t, *got, tc.want)
		})
	}
}

func TestE2E_EAPConfigImportToNewProfile(t *testing.T) {
	resp := e2eRequest(t, newEditorFixture(t).backend, "network.eapconfig.parse", jm{"file": "testdata/uhh.eap-config"})
	require.Empty(t, resp.Error)
	var parsed struct{ Enterprise jm }
	require.NoError(t, json.Unmarshal(*resp.Result, &parsed))
	block, _ := pem.Decode([]byte(parsed.Enterprise["caCertPem"].(string)))
	require.NotNil(t, block)
	parsed.Enterprise["identity"], parsed.Enterprise["password"] = "stine@uni-hamburg.de", "s3cret"
	eduroam := jm{"ssid": "eduroam", "security": "wpa-eap", "saveOnly": true, "hidden": true, "enterprise": parsed.Enterprise}
	f := newEditorFixture(t)
	f.settings.EXPECT().ListConnections().Return(nil, nil).Once()
	f.object(t, dbusNMPath).EXPECT().Call(gonetworkmanager.NetworkManagerGetPermissions, dbus.Flags(0)).
		Return(&dbus.Call{Body: []any{map[string]string{nmPermModifySystem: "yes"}}}).Once()
	var added gonetworkmanager.ConnectionSettings
	f.settings.EXPECT().AddConnection(mock.Anything).Run(func(s gonetworkmanager.ConnectionSettings) { added = s }).Return(nil, nil).Once()
	require.Empty(t, e2eRequest(t, f.backend, "network.wifi.connect", eduroam).Error)
	assertKeys(t, added, jm{"802-1x.eap": []string{"ttls"}, "802-1x.phase2-auth": "pap", "802-1x.domain-match": "roamrad.rrz.uni-hamburg.de",
		"802-1x.ca-cert": block.Bytes, "802-1x.identity": "stine@uni-hamburg.de", "802-1x.system-ca-certs": nil,
		"802-11-wireless.ssid": []byte("eduroam"), "802-11-wireless.hidden": true, "802-1x.password": "s3cret"})
}

func TestE2E_EthernetDisconnectUsesDevice(t *testing.T) {
	e := newEthernetFixture(t, mockWiredProfile(t, "wired-a", "enp6s0", nil))
	dev := e.addDevice(t, "enp6s0", hwEnp6s0, gonetworkmanager.NmDeviceStateActivated, activeConnection(t, "wired-a"))
	e.nm.EXPECT().ActivateConnection(mock.MatchedBy(isAutoConnection), dev, (*dbus.Object)(nil)).Return(nil, nil).Once()
	dev.EXPECT().Disconnect().Return(nil).Once()
	assert.Empty(t, e2eRequest(t, e.backend, "network.ethernet.connect", map[string]any{"device": "enp6s0"}).Error)
	assert.Empty(t, e2eRequest(t, e.backend, "network.ethernet.disconnect", map[string]any{"device": "enp6s0"}).Error)
}

func TestE2E_ActivateProfileUsesDevice(t *testing.T) {
	f := newEditorFixture(t)
	conn, dev := mock_gonetworkmanager.NewMockConnection(t), mock_gonetworkmanager.NewMockDevice(t)
	f.settings.EXPECT().GetConnectionByUUID("u1").Return(conn, nil)
	f.nm.EXPECT().GetDeviceByIpIface("wlan0").Return(dev, nil).Once()
	f.nm.EXPECT().ActivateConnection(conn, dev, (*dbus.Object)(nil)).Return(nil, nil).Once()
	assert.Empty(t, e2eRequest(t, f.backend, "network.connection.activate", jm{"uuid": "u1", "device": "wlan0"}).Error)
}

func TestE2E_HotspotCardOwnsProfileAndQRCode(t *testing.T) {
	f := newEditorFixture(t)
	hotspotActive := false
	current := storedHotspotSettings()
	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetSettings().RunAndReturn(func() (gonetworkmanager.ConnectionSettings, error) { return current, nil }).Maybe()
	conn.EXPECT().Update(mock.Anything).RunAndReturn(func(s gonetworkmanager.ConnectionSettings) error { current = s; return nil }).Once()
	conn.EXPECT().GetSecrets("802-11-wireless-security").Return(gonetworkmanager.ConnectionSettings{"802-11-wireless-security": {"psk": testHotspotPSK}}, nil).Maybe()
	client := mock_gonetworkmanager.NewMockConnection(t)
	client.EXPECT().GetSettings().Return(gonetworkmanager.ConnectionSettings{"connection": {"uuid": "client-uuid", "type": "802-11-wireless"}, "802-11-wireless": {"ssid": []byte("dms-ap"), "mode": "infrastructure"}, "802-11-wireless-security": {"key-mgmt": "wpa-psk"}}, nil).Maybe()
	client.EXPECT().GetSecrets("802-11-wireless-security").Return(gonetworkmanager.ConnectionSettings{"802-11-wireless-security": {"psk": "client-psk"}}, nil).Maybe()
	f.settings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{conn, client}, nil).Maybe()
	ac := mock_gonetworkmanager.NewMockActiveConnection(t)
	ac.EXPECT().GetPropertyType().Return("802-11-wireless", nil).Maybe()
	ac.EXPECT().GetPropertyConnection().Return(conn, nil).Maybe()
	ac.EXPECT().GetPropertyState().Return(gonetworkmanager.NmActiveConnectionStateActivated, nil).Maybe()
	f.nm.EXPECT().GetPropertyActiveConnections().RunAndReturn(func() ([]gonetworkmanager.ActiveConnection, error) {
		if hotspotActive {
			return []gonetworkmanager.ActiveConnection{ac}, nil
		}
		return nil, nil
	}).Maybe()

	resp := e2eRequest(t, f.backend, "network.hotspot.configure", jm{"ssid": "dms-ap", "password": testHotspotPSK, "security": "sae", "hidden": true})
	require.Empty(t, resp.Error)
	assertKeys(t, current, jm{"connection.uuid": "hotspot-uuid", "802-11-wireless-security.key-mgmt": "sae", "connection.metered": nil})
	resp = e2eRequest(t, f.backend, "network.qrcode-content", map[string]any{"ssid": "dms-ap"})
	require.Empty(t, resp.Error)
	assert.JSONEq(t, `"WIFI:T:WPA;S:dms-ap;P:client-psk;;"`, string(*resp.Result), "the client profile answers while the hotspot is off")

	hotspotActive = true
	resp = e2eRequest(t, f.backend, "network.qrcode-content", map[string]any{"ssid": "dms-ap"})
	require.Empty(t, resp.Error)
	assert.JSONEq(t, `"WIFI:T:WPA;S:dms-ap;P:`+testHotspotPSK+`;H:true;;"`, string(*resp.Result))
}

func TestE2E_ReadOnlyListWithoutFirewalld(t *testing.T) {
	f := newEditorFixture(t)
	system := listedConnection(t, f, "/s/1", 0, connSection("u-sys", "Corp", "802-3-ethernet", nil))
	f.settings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{system}, nil).Once()
	f.nm.EXPECT().GetPropertyActiveConnections().Return(nil, nil).Once()
	f.object(t, dbusNMPath).EXPECT().Call(gonetworkmanager.NetworkManagerGetPermissions, dbus.Flags(0)).
		Return(&dbus.Call{Body: []any{map[string]string{"org.freedesktop.NetworkManager.settings.modify.system": "no"}}}).Once()
	fw := mock_dbus.NewMockBusObject(t)
	f.backend.firewalldObjectFn = func() dbus.BusObject { return fw }
	fw.EXPECT().Call(firewalldGetZones, dbus.Flags(0)).Return(&dbus.Call{Err: dbus.Error{Name: "org.freedesktop.DBus.Error.ServiceUnknown"}}).Once()
	resp := e2eRequest(t, f.backend, "network.connection.list", nil)
	require.Empty(t, resp.Error)
	assert.Contains(t, string(*resp.Result), `"canModify":false`)
	resp = e2eRequest(t, f.backend, "network.connection.firewallZones", nil)
	assert.JSONEq(t, `[]`, string(*resp.Result))
}

func TestE2E_EnterpriseRead(t *testing.T) {
	v := dbus.MakeVariant
	f := newEditorFixture(t)
	eth := connSection("u1", "Corp", "802-3-ethernet", nil)
	eth["802-1x"] = map[string]dbus.Variant{"eap": v([]string{"ttls"}), "identity": v("bob"), "ca-cert": v([]byte("der"))}
	expectGetSettings(f.profile(t, "u1", "/s/1"), eth)
	expectGetSettings(f.profile(t, "u2", "/s/2"), connSection("u2", "Home", "802-3-ethernet", nil))

	resp := e2eRequest(t, f.backend, "network.connection.getEnterprise", jm{"uuid": "u1"})
	require.Empty(t, resp.Error)
	assert.Contains(t, string(*resp.Result), `"ca":"file"`)
	assert.Contains(t, string(*resp.Result), `"identity":"bob"`)
	assert.Equal(t, "connection has no 802.1X settings", e2eRequest(t, f.backend, "network.connection.getEnterprise", jm{"uuid": "u2"}).Error)
}

func TestE2E_EnterpriseInputRejected(t *testing.T) {
	f := newEditorFixture(t)
	_, err := decodeEnterpriseConfig(jm{"eap": "ttls", "phase2": "pap", "identity": "bob", "bogus": 1})
	assert.ErrorContains(t, err, "bogus")
	ent := jm{"eap": "nope", "identity": "bob"}
	assert.NotEmpty(t, e2eRequest(t, f.backend, "network.connection.update", jm{"uuid": "u1", "settings": jm{}, "enterprise": ent}).Error)
	big := filepath.Join(t.TempDir(), "big.eap-config")
	require.NoError(t, os.WriteFile(big, bytes.Repeat([]byte("a"), 4<<20+1), 0o600))
	assert.Contains(t, e2eRequest(t, f.backend, "network.eapconfig.parse", jm{"file": big}).Error, "too large")
}

func TestE2E_WireGuardKeys(t *testing.T) {
	b := newEditorFixture(t).backend
	var pair, derived map[string]string
	require.NoError(t, json.Unmarshal(*e2eRequest(t, b, "network.wireguard.keys", nil).Result, &pair))
	require.NoError(t, json.Unmarshal(*e2eRequest(t, b, "network.wireguard.keys", jm{"privateKey": pair["privateKey"]}).Result, &derived))
	assert.Equal(t, pair, derived)
	assert.Equal(t, "invalid WireGuard key", e2eRequest(t, b, "network.wireguard.keys", jm{"privateKey": "abc"}).Error)
}

func TestE2E_GetConnectionReturnsSecretsOnlyWhenAsked(t *testing.T) {
	v := dbus.MakeVariant
	f := newEditorFixture(t)
	ovpn := func(uuid string) nmSettings {
		s := connSection(uuid, "ovpn", "vpn", nil)
		s["vpn"] = map[string]dbus.Variant{"service-type": v("org.freedesktop.NetworkManager.openvpn"), "data": v(map[string]string{"remote": "vpn.example.com"})}
		return s
	}
	expectGetSettings(f.profile(t, "u1", "/s/1"), ovpn("u1"))
	withSecrets := f.profile(t, "u2", "/s/2")
	expectGetSettings(withSecrets, ovpn("u2"))
	expectGetSecrets(withSecrets, "vpn", nmSettings{"vpn": {"secrets": v(map[string]string{"password": "pw"})}})

	resp := e2eRequest(t, f.backend, "network.connection.get", jm{"uuid": "u1"})
	require.Empty(t, resp.Error)
	assert.NotContains(t, string(*resp.Result), "pw")
	resp = e2eRequest(t, f.backend, "network.connection.get", jm{"uuid": "u2", "secrets": true})
	require.Empty(t, resp.Error)
	assert.Contains(t, string(*resp.Result), `"password":"pw"`)
}
