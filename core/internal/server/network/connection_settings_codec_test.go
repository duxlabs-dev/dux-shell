package network

import (
	"encoding/binary"
	"encoding/json"
	"strings"
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSettingSignaturesMatchNMSettingsDBus(t *testing.T) {
	for key, sig := range map[string]string{"ipv4.route-metric": "x", "ipv6.route-metric": "x", "ipv4.address-data": "aa{sv}", "802-1x.ca-cert": "ay", "802-11-wireless.ssid": "ay"} {
		assert.Equal(t, sig, settingSignatures[key], key)
	}
}

func TestSettingsCodecRoundTripKeepsSignatures(t *testing.T) {
	stored := map[string]map[string]dbus.Variant{
		"connection": {"id": dbus.MakeVariant("Wired connection 1"), "autoconnect": dbus.MakeVariant(false), "autoconnect-priority": dbus.MakeVariant(int32(-999)),
			"timestamp": dbus.MakeVariant(uint64(1759400000)), "permissions": dbus.MakeVariant([]string{"user:marlon"})},
		"ipv4": {"method": dbus.MakeVariant("manual"), "route-metric": dbus.MakeVariant(int64(-1)), "dns-data": dbus.MakeVariant([]string{"192.0.2.53"}),
			"address-data": dbus.MakeVariant([]map[string]dbus.Variant{{"address": dbus.MakeVariant("192.0.2.10"), "prefix": dbus.MakeVariant(uint32(24))}}),
			"addresses":    dbus.MakeVariant([][]uint32{{1, 24, 2}})},
		"vpn":             {"data": dbus.MakeVariant(map[string]string{"remote": "vpn.example.com"})},
		"802-3-ethernet":  {"mac-address": dbus.MakeVariant([]byte{0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff})},
		"802-11-wireless": {"ssid": dbus.MakeVariant([]byte("eduroam"))},
		"802-1x":          {"ca-cert": dbus.MakeVariant(append([]byte("file:///etc/x.pem"), 0)), "client-cert": dbus.MakeVariant([]byte{0x30, 0x82, 0x01})},
	}
	raw, err := json.Marshal(decodeSettingsForJSON(stored))
	var fromJSON map[string]map[string]any
	require.NoError(t, err)
	require.NoError(t, json.Unmarshal(raw, &fromJSON))
	assert.NotContains(t, fromJSON["ipv4"], "addresses")
	for section, keys := range fromJSON {
		for key, value := range keys {
			orig := stored[section][key]
			got, err := encodeSettingValue(section, key, value, &orig)
			require.NoError(t, err, section+"."+key)
			assert.Equal(t, orig, got, section+"."+key)
		}
	}
}

func TestEncodeSettingValue(t *testing.T) {
	blob, nested := []byte{0x30, 0x82, 0x01}, func(m map[string]any) []any { return []any{m} }
	prio, addr, cert := "connection.autoconnect-priority", "ipv4.address-data", "802-1x.ca-cert"
	for _, tc := range []struct {
		name, sk string
		value    any
		want     any
		stored   *dbus.Variant
		fail     bool
	}{
		{"uint max", "ipv4.route-table", 4294967295.0, uint32(4294967295), nil, false},
		{"fraction", prio, 1.5, nil, nil, true},
		{"int32 overflow", prio, 2147483648.0, nil, nil, true},
		{"nested unknown key", addr, nested(map[string]any{"bogus": "x"}), nil, nil, true},
		{"vpn secret tombstone", "vpn.secrets", map[string]any{"password": nil, "cert-pass": "x"}, map[string]string{"cert-pass": "x"}, nil, false},
		{"peer psk tombstone", "wireguard.peers", nested(map[string]any{"public-key": "A", "preshared-key": nil}), []map[string]dbus.Variant{{"public-key": dbus.MakeVariant("A")}}, nil, false},
		{"vpn data null", "vpn.data", map[string]any{"remote": nil}, nil, nil, true},
		{"cert path", cert, "/etc/x.pem", append([]byte("file:///etc/x.pem"), 0), nil, false},
		{"cert relative path", cert, "relative.pem", nil, nil, true},
		{"cert path with NUL", cert, "/etc/a\x00b.pem", nil, nil, true},
		{"cert blob keeps stored", "802-1x.client-cert", "blob", blob, &[]dbus.Variant{dbus.MakeVariant(blob)}[0], false},
		{"cert blob without stored", "802-1x.client-cert", "blob", nil, nil, true},
		{"mac garbage", "802-3-ethernet.mac-address", "zz", nil, nil, true},
		{"ssid empty", "802-11-wireless.ssid", "", nil, nil, true},
		{"ssid too long", "802-11-wireless.ssid", strings.Repeat("a", 33), nil, nil, true},
		{"native passes", "802-1x.eap", []string{"ttls"}, []string{"ttls"}, nil, false},
		{"native wrong int", "802-1x.password-flags", 2, nil, nil, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			section, key, _ := strings.Cut(tc.sk, ".")
			v, err := encodeSettingValue(section, key, tc.value, tc.stored)
			if tc.fail {
				assert.ErrorContains(t, err, tc.sk)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tc.want, v.Value())
		})
	}
}

func TestDecodeSettingsForJSON(t *testing.T) {
	au, v6 := binary.NativeEndian.Uint32([]byte{192, 0, 2, 53}), []byte{0x20, 0x01, 0x0d, 0xb8, 15: 0x53} // NM stores IPv4 as network-order bytes
	type sec = map[string]map[string]dbus.Variant
	for _, tc := range []struct {
		name string
		in   sec
		want map[string]map[string]any
	}{
		{"cert path, blob, empty path, no NUL", sec{"802-1x": {"phase2-ca-cert": dbus.MakeVariant(append([]byte("file:///etc/inner.pem"), 0)),
			"phase2-private-key": dbus.MakeVariant([]byte{0x30}), "ca-cert": dbus.MakeVariant(append([]byte("file://"), 0)), "client-cert": dbus.MakeVariant([]byte("file:///etc/x.pem"))}},
			map[string]map[string]any{"802-1x": {"phase2-ca-cert": "/etc/inner.pem", "phase2-private-key": "blob", "ca-cert": "blob", "client-cert": "blob"}}},
		{"mac, bad cloned mac dropped", sec{"802-3-ethernet": {"mac-address": dbus.MakeVariant([]byte{0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff}), "cloned-mac-address": dbus.MakeVariant([]byte{1, 2, 3})}},
			map[string]map[string]any{"802-3-ethernet": {"mac-address": "AA:BB:CC:DD:EE:FF"}}},
		{"non-UTF-8 ssid dropped", sec{"802-11-wireless": {"ssid": dbus.MakeVariant([]byte{0xff, 0xfe}), "mode": dbus.MakeVariant("ap")}}, map[string]map[string]any{"802-11-wireless": {"mode": "ap"}}},
		{"legacy dns", sec{"ipv4": {"dns": dbus.MakeVariant([]uint32{au})}, "ipv6": {"dns": dbus.MakeVariant([][]byte{v6})}},
			map[string]map[string]any{"ipv4": {"dns-data": []string{"192.0.2.53"}}, "ipv6": {"dns-data": []string{"2001:db8::53"}}}},
		{"dns-data wins over legacy dns", sec{"ipv4": {"dns": dbus.MakeVariant([]uint32{au}), "dns-data": dbus.MakeVariant([]string{"198.51.100.1"})}},
			map[string]map[string]any{"ipv4": {"dns-data": []string{"198.51.100.1"}}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.want, map[string]map[string]any(decodeSettingsForJSON(tc.in)))
		})
	}
}

func TestApplySettingsPatch(t *testing.T) {
	newSettings := func() map[string]map[string]dbus.Variant {
		return map[string]map[string]dbus.Variant{"proxy": {"method": dbus.MakeVariant(int32(0))},
			"connection": {"id": dbus.MakeVariant("home"), "zone": dbus.MakeVariant("public"), "custom-key": dbus.MakeVariant("old"), "autoconnect": dbus.MakeVariant(true)}}
	}
	s := newSettings()
	require.NoError(t, applySettingsPatch(s, SettingsPatch{"connection": {"zone": nil, "custom-key": "new", "autoconnect-priority": 5.0}, "proxy": nil, "ipv6": {"dns-data": nil}}))
	assert.Equal(t, map[string]map[string]dbus.Variant{"connection": {"id": dbus.MakeVariant("home"), "custom-key": dbus.MakeVariant("new"),
		"autoconnect": dbus.MakeVariant(true), "autoconnect-priority": dbus.MakeVariant(int32(5))}}, s, "delete-only patch creates no section")
	require.NoError(t, applySettingsPatch(s, SettingsPatch{"ipv6": {"dns-data": nil, "method": "auto"}}))
	assert.Equal(t, map[string]dbus.Variant{"method": dbus.MakeVariant("auto")}, s["ipv6"])
	// Map order is random; repeat so an in-place apply can't pass by luck.
	for range 20 {
		s = newSettings()
		err := applySettingsPatch(s, SettingsPatch{"connection": {"id": "renamed", "zone": nil, "not-a-key": "x"}, "proxy": nil})
		require.ErrorContains(t, err, "connection.not-a-key")
		require.Equal(t, newSettings(), s)
	}
	assert.Error(t, applySettingsPatch(nil, SettingsPatch{"connection": {"id": "x"}}))
}

func TestEncodeNewSettings(t *testing.T) {
	var patch SettingsPatch
	require.NoError(t, json.Unmarshal([]byte(`{
		"connection": {"id": "office", "autoconnect": false}, "802-1x": {"identity": "u", "password": null},
		"ipv4": {"route-data": [{"dest": "10.0.0.0", "prefix": 8, "onlink": true, "table": 100}]},
		"wireguard": {"peers": [{"public-key": "k", "allowed-ips": ["10.0.0.0/24", "::/0"], "persistent-keepalive": 25}]}}`), &patch))
	s, err := encodeNewSettings(patch)
	require.NoError(t, err)
	assert.Equal(t, dbus.MakeVariant(false), s["connection"]["autoconnect"])
	assert.Contains(t, s["802-1x"], "identity")
	assert.NotContains(t, s["802-1x"], "password", "null key is skipped")
	assert.Equal(t, []map[string]dbus.Variant{{"dest": dbus.MakeVariant("10.0.0.0"), "prefix": dbus.MakeVariant(uint32(8)),
		"onlink": dbus.MakeVariant(true), "table": dbus.MakeVariant(uint32(100))}}, s["ipv4"]["route-data"].Value())
	assert.Equal(t, []map[string]dbus.Variant{{"public-key": dbus.MakeVariant("k"), "allowed-ips": dbus.MakeVariant([]string{"10.0.0.0/24", "::/0"}),
		"persistent-keepalive": dbus.MakeVariant(uint32(25))}}, s["wireguard"]["peers"].Value())

	for _, bad := range []SettingsPatch{{"connection": {"custom-key": "x"}}, {"wireguard": {"listen-port": -1.0}}, {"wireguard": {"peers": []any{map[string]any{"bogus": "x"}}}}} {
		_, err = encodeNewSettings(bad)
		assert.Error(t, err)
	}
}

func TestPortConnectionRowsEncode(t *testing.T) {
	s, err := encodeNewSettings(SettingsPatch{"connection": {"autoconnect-slaves": 1.0, "master": "u", "slave-type": "bond"}})
	require.NoError(t, err)
	assert.Equal(t, "i", s["connection"]["autoconnect-slaves"].Signature().String())
}

func TestVlanRowsEncode(t *testing.T) {
	s, err := encodeNewSettings(SettingsPatch{"vlan": {"id": 100.0, "flags": 3.0, "parent": "enp5s0"}})
	require.NoError(t, err)
	assert.Equal(t, "u", s["vlan"]["id"].Signature().String())
	assert.Equal(t, "u", s["vlan"]["flags"].Signature().String())
	assert.Equal(t, "s", s["vlan"]["parent"].Signature().String())

	_, err = encodeNewSettings(SettingsPatch{"vlan": {"id": -1.0}})
	require.ErrorContains(t, err, "vlan.id")
}

func TestBondRowsEncode(t *testing.T) {
	s, err := encodeNewSettings(SettingsPatch{"bond": {"options": map[string]any{"mode": "active-backup", "miimon": "100"}}})
	require.NoError(t, err)
	assert.Equal(t, "a{ss}", s["bond"]["options"].Signature().String())
}

func TestBridgeRowsEncode(t *testing.T) {
	s, err := encodeNewSettings(SettingsPatch{"bridge": {"mac-address": "aa:bb:cc:dd:ee:ff", "stp": true, "priority": 4096.0}})
	require.NoError(t, err)
	assert.Equal(t, []byte{0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff}, s["bridge"]["mac-address"].Value())
}

func TestLinkTypeSignaturesMatchNMSettingsDBus(t *testing.T) {
	want := map[string]string{
		"connection.master": "s", "connection.slave-type": "s", "connection.controller": "s",
		"connection.port-type": "s", "connection.autoconnect-slaves": "i", "connection.autoconnect-ports": "i",
		"vlan.parent": "s", "vlan.id": "u", "vlan.flags": "u", "vlan.protocol": "s",
		"vlan.ingress-priority-map": "as", "vlan.egress-priority-map": "as",
		"bond.options": "a{ss}", "bond.interface-name": "s",
		"bridge.stp": "b", "bridge.priority": "u", "bridge.forward-delay": "u", "bridge.hello-time": "u",
		"bridge.max-age": "u", "bridge.ageing-time": "u", "bridge.mac-address": "ay",
		"bridge.multicast-snooping": "b", "bridge.vlan-filtering": "b", "bridge.vlan-default-pvid": "u",
		"bridge.group-forward-mask": "u", "bridge.multicast-router": "s",
		"bridge-port.priority": "u", "bridge-port.path-cost": "u", "bridge-port.hairpin-mode": "b",
		"gsm.apn": "s", "gsm.auto-config": "b", "gsm.username": "s", "gsm.password": "s",
		"gsm.password-flags": "u", "gsm.pin": "s", "gsm.pin-flags": "u", "gsm.home-only": "b",
		"gsm.network-id": "s", "gsm.number": "s", "gsm.mtu": "u", "gsm.device-id": "s", "gsm.sim-id": "s",
		"gsm.sim-operator-id": "s", "gsm.initial-eps-bearer-apn": "s", "gsm.initial-eps-bearer-configure": "b",
		"cdma.number": "s", "cdma.username": "s", "cdma.password": "s", "cdma.password-flags": "u", "cdma.mtu": "u",
		"pppoe.parent": "s", "pppoe.service": "s", "pppoe.username": "s", "pppoe.password": "s",
		"pppoe.password-flags": "u",
		"ppp.refuse-eap":       "b", "ppp.refuse-pap": "b", "ppp.refuse-chap": "b", "ppp.refuse-mschap": "b",
		"ppp.refuse-mschapv2": "b", "ppp.require-mppe": "b", "ppp.require-mppe-128": "b",
		"ppp.mppe-stateful": "b", "ppp.nobsdcomp": "b", "ppp.nodeflate": "b", "ppp.no-vj-comp": "b",
		"ppp.noauth": "b", "ppp.lcp-echo-interval": "u", "ppp.lcp-echo-failure": "u", "ppp.mtu": "u",
		"ppp.mru": "u", "ppp.baud": "u", "ppp.crtscts": "b",
		"bluetooth.bdaddr": "ay", "bluetooth.type": "s",
	}
	for name, sig := range want {
		assert.Equal(t, sig, settingSignatures[name], name)
	}
}
