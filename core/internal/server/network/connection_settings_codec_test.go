package network

import (
	"encoding/json"
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

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
