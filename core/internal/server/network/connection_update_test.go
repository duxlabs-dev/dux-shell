package network

import (
	"errors"
	"testing"

	mock_dbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type legacyIP6Addr struct {
	Addr    []byte
	Prefix  uint32
	Gateway []byte
}

func expectGetSettings(obj *mock_dbus.MockBusObject, s nmSettings) {
	obj.EXPECT().Call(nmConnGetSettings, dbus.Flags(0)).
		Return(&dbus.Call{Body: []any{s}}).Once()
}

func expectGetSecrets(obj *mock_dbus.MockBusObject, setting string, s nmSettings) {
	obj.EXPECT().Call(nmConnGetSecrets, dbus.Flags(0), setting).
		Return(&dbus.Call{Body: []any{s}}).Once()
}

func captureUpdate2(obj *mock_dbus.MockBusObject, flags uint32, err error) *nmSettings {
	var got nmSettings
	obj.EXPECT().Call(nmConnUpdate2, dbus.Flags(0), mock.Anything, flags, mock.Anything).
		Run(func(_ string, _ dbus.Flags, args ...any) {
			got = args[0].(nmSettings)
		}).
		Return(&dbus.Call{Err: err, Body: []any{map[string]dbus.Variant{}}}).Once()
	return &got
}

func TestUpdateConnectionSettings_ManualDNSAndGatewaySurviveAutoconnectFlip(t *testing.T) {
	obj := mock_dbus.NewMockBusObject(t)
	legacyAddrs := []legacyIP6Addr{{Addr: make([]byte, 16), Prefix: 64, Gateway: make([]byte, 16)}}
	addr := func(a string, p uint32) dbus.Variant {
		return dbus.MakeVariant([]map[string]dbus.Variant{{"address": dbus.MakeVariant(a), "prefix": dbus.MakeVariant(p)}})
	}
	expectGetSettings(obj, nmSettings{
		"connection": {"id": dbus.MakeVariant("Wired"), "autoconnect": dbus.MakeVariant(true)},
		"ipv4": {
			"method": dbus.MakeVariant("manual"), "addresses": dbus.MakeVariant([][]uint32{{0x0100a8c0, 24, 0x0101a8c0}}),
			"address-data": addr("192.168.0.1", 24), "gateway": dbus.MakeVariant("192.168.1.1"),
			"dns": dbus.MakeVariant([]uint32{0x01010101}), "dns-data": dbus.MakeVariant([]string{"1.1.1.1"}),
		},
		"ipv6": {"method": dbus.MakeVariant("manual"), "addresses": dbus.MakeVariant(legacyAddrs), "address-data": addr("fd00::1", 64)},
	})
	got := captureUpdate2(obj, 0, nil)

	require.NoError(t, updateConnectionSettings(obj, false, func(s nmSettings) error {
		setSettingValue(s, "connection", "autoconnect", false)
		return nil
	}))

	s := *got
	assert.Equal(t, false, s["connection"]["autoconnect"].Value())
	assert.NotContains(t, s["ipv4"], "addresses")
	assert.NotContains(t, s["ipv4"], "dns")
	assert.NotContains(t, s["ipv6"], "addresses")
	assert.Equal(t, "192.168.1.1", s["ipv4"]["gateway"].Value())
	assert.Equal(t, "as", s["ipv4"]["dns-data"].Signature().String())
	assert.Equal(t, "aa{sv}", s["ipv4"]["address-data"].Signature().String())

	legacy := nmSettings{"ipv4": {"dns": dbus.MakeVariant([]uint32{1}), "addresses": dbus.MakeVariant([][]uint32{{1, 24, 0}})}}
	dropLegacyIPKeys(legacy)
	assert.Contains(t, legacy["ipv4"], "dns", "legacy key without a modern twin is kept")
	assert.Contains(t, legacy["ipv4"], "addresses")
}

func secretsFixture() nmSettings {
	return nmSettings{
		"connection":               {"id": dbus.MakeVariant("x")},
		"802-11-wireless-security": {"key-mgmt": dbus.MakeVariant("wpa-psk")},
		"vpn": {
			"service-type": dbus.MakeVariant("org.freedesktop.NetworkManager.openvpn"),
		},
		"wireguard": {
			"peers": dbus.MakeVariant([]map[string]dbus.Variant{
				{"public-key": dbus.MakeVariant("PEER_A"), "endpoint": dbus.MakeVariant("a:51820")},
				{"public-key": dbus.MakeVariant("PEER_B")},
			}),
		},
	}
}

func expectStoredSecrets(obj *mock_dbus.MockBusObject) {
	expectGetSecrets(obj, "802-11-wireless-security", nmSettings{
		"802-11-wireless-security": {"psk": dbus.MakeVariant("old")},
	})
	expectGetSecrets(obj, "vpn", nmSettings{
		"vpn": {"secrets": dbus.MakeVariant(map[string]string{"password": "a", "cert-pass": "b"})},
	})
	expectGetSecrets(obj, "wireguard", nmSettings{"wireguard": {
		"peers": dbus.MakeVariant([]map[string]dbus.Variant{
			{"public-key": dbus.MakeVariant("PEER_B"), "preshared-key": dbus.MakeVariant("PSK_B")},
		}),
	}})
}

func TestUpdateConnectionSettings_SecretsMergedAndPatchWins(t *testing.T) {
	peerPatch := func(peer map[string]any) SettingsPatch { return SettingsPatch{"wireguard": {"peers": []any{peer}}} }
	for _, tc := range []struct {
		name  string
		patch SettingsPatch
		psk   string
		vpn   map[string]string
		peers map[string]string // public-key -> preshared-key; nil when the section is gone
	}{
		{"stored secrets kept", SettingsPatch{}, "old", map[string]string{"password": "a", "cert-pass": "b"},
			map[string]string{"PEER_A": "", "PEER_B": "PSK_B"}},
		{"patch wins, unmentioned kept", SettingsPatch{
			"802-11-wireless-security": {"psk": "new"}, "vpn": {"secrets": map[string]any{"password": "c"}},
		}, "new", map[string]string{"password": "c", "cert-pass": "b"}, map[string]string{"PEER_A": "", "PEER_B": "PSK_B"}},
		{"null vpn secret removed", SettingsPatch{"vpn": {"secrets": map[string]any{"password": nil}}},
			"old", map[string]string{"cert-pass": "b"}, map[string]string{"PEER_A": "", "PEER_B": "PSK_B"}},
		{"null peer psk removes it", peerPatch(map[string]any{"public-key": "PEER_B", "preshared-key": nil}),
			"old", map[string]string{"password": "a", "cert-pass": "b"}, map[string]string{"PEER_B": ""}},
		{"omitted peer psk kept", peerPatch(map[string]any{"public-key": "PEER_B", "endpoint": "b:1"}),
			"old", map[string]string{"password": "a", "cert-pass": "b"}, map[string]string{"PEER_B": "PSK_B"}},
		{"explicit peer psk wins", peerPatch(map[string]any{"public-key": "PEER_B", "preshared-key": "NEW"}),
			"old", map[string]string{"password": "a", "cert-pass": "b"}, map[string]string{"PEER_B": "NEW"}},
		{"null containers stay deleted", SettingsPatch{"vpn": {"secrets": nil}, "wireguard": nil},
			"old", nil, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			obj := mock_dbus.NewMockBusObject(t)
			expectGetSettings(obj, secretsFixture())
			expectStoredSecrets(obj)
			got := captureUpdate2(obj, 0, nil)
			require.NoError(t, updateConnectionSettingsRemoving(obj, false, secretRemovalsFromPatch(tc.patch), func(s nmSettings) error {
				return applySettingsPatch(s, tc.patch)
			}))

			s := *got
			assert.Equal(t, tc.psk, s["802-11-wireless-security"]["psk"].Value())
			var vpn map[string]string
			if v, ok := s["vpn"]["secrets"]; ok {
				vpn = v.Value().(map[string]string)
			}
			assert.Equal(t, tc.vpn, vpn)
			var peers map[string]string
			if v, ok := s["wireguard"]["peers"]; ok {
				peers = map[string]string{}
				for _, p := range v.Value().([]map[string]dbus.Variant) {
					psk, _ := p["preshared-key"].Value().(string)
					peers[p["public-key"].Value().(string)] = psk
				}
			}
			assert.Equal(t, tc.peers, peers)
		})
	}
}

func TestUpdateConnectionSettings_FailuresWriteNothing(t *testing.T) {
	// Update2 drops omitted secrets, so a failed read must abort the write.
	obj := mock_dbus.NewMockBusObject(t)
	expectGetSettings(obj, nmSettings{"802-11-wireless-security": {"key-mgmt": dbus.MakeVariant("wpa-psk")}})
	obj.EXPECT().Call(nmConnGetSecrets, dbus.Flags(0), "802-11-wireless-security").
		Return(&dbus.Call{Err: dbus.Error{Name: "org.freedesktop.DBus.Error.NoReply", Body: []any{"timeout"}}}).Once()
	require.ErrorContains(t, updateConnectionSettings(obj, false, func(nmSettings) error { return nil }),
		"failed to get secrets for 802-11-wireless-security: timeout")
	obj.AssertNotCalled(t, "Call", nmConnUpdate2, mock.Anything, mock.Anything, mock.Anything, mock.Anything)

	obj = mock_dbus.NewMockBusObject(t)
	expectGetSettings(obj, nmSettings{"connection": {"id": dbus.MakeVariant("x")}})
	require.ErrorContains(t, updateConnectionSettings(obj, true, func(nmSettings) error { return errors.New("bad value") }), "bad value")
	obj.AssertNotCalled(t, "Call", nmConnUpdate2, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestUpdateConnectionSettings_PersistFlagAndNMError(t *testing.T) {
	obj := mock_dbus.NewMockBusObject(t)
	expectGetSettings(obj, nmSettings{"connection": {"id": dbus.MakeVariant("x")}})
	nmErr := dbus.Error{Name: "org.freedesktop.NetworkManager.Settings.Connection.InvalidProperty", Body: []any{"ipv4.dns: invalid IP address"}}
	captureUpdate2(obj, 0x1, nmErr)

	err := updateConnectionSettings(obj, true, func(nmSettings) error { return nil })
	require.EqualError(t, err, "failed to update connection: ipv4.dns: invalid IP address")
}
