package network

import (
	"net"
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestUpdateOpenConnectAgentFlagsLegacyIPv6(t *testing.T) {
	address := []byte(net.ParseIP("2001:db8::2").To16())
	gateway := []byte(net.ParseIP("2001:db8::1").To16())
	destination := []byte(net.ParseIP("2001:db8:1::").To16())
	for _, populated := range []bool{false, true} {
		name := "empty"
		addresses := [][]any{}
		routes := [][]any{}
		wantAddresses := []nmLegacyIPv6Address{}
		wantRoutes := []nmLegacyIPv6Route{}
		if populated {
			name = "populated"
			addresses = append(addresses, []any{address, uint32(64), gateway})
			routes = append(routes, []any{destination, uint32(64), gateway, uint32(37)})
			wantAddresses = append(wantAddresses, nmLegacyIPv6Address{address, 64, gateway})
			wantRoutes = append(wantRoutes, nmLegacyIPv6Route{destination, 64, gateway, 37})
		}
		t.Run(name, func(t *testing.T) {
			ipv6 := map[string]dbus.Variant{
				"addresses":    dbus.MakeVariantWithSignature(addresses, dbus.ParseSignatureMust("a(ayuay)")),
				"routes":       dbus.MakeVariantWithSignature(routes, dbus.ParseSignatureMust("a(ayuayu)")),
				"method":       dbus.MakeVariant("manual"),
				"dns":          dbus.MakeVariant([][]byte{gateway}),
				"route-metric": dbus.MakeVariant(int64(123)),
			}
			updated := false
			err := updateOpenConnectAgentFlags(map[string]string{}, func(method string, result any, args ...any) error {
				switch method {
				case "org.freedesktop.NetworkManager.Settings.Connection.GetSettings":
					*result.(*map[string]map[string]dbus.Variant) = map[string]map[string]dbus.Variant{
						"vpn":  {"data": dbus.MakeVariant(map[string]string{"gateway": "invalid.example"})},
						"ipv6": ipv6,
					}
				case "org.freedesktop.NetworkManager.Settings.Connection.Update2":
					updated = true
					settings := args[0].(map[string]map[string]dbus.Variant)
					v6 := settings["ipv6"]
					assert.Equal(t, "a(ayuay)", v6["addresses"].Signature().String())
					assert.Equal(t, "a(ayuayu)", v6["routes"].Signature().String())
					assert.Equal(t, "a(ayuay)", dbus.SignatureOf(v6["addresses"].Value()).String())
					assert.Equal(t, "a(ayuayu)", dbus.SignatureOf(v6["routes"].Value()).String())
					assert.Equal(t, wantAddresses, v6["addresses"].Value())
					assert.Equal(t, wantRoutes, v6["routes"].Value())
					assert.Equal(t, dbus.MakeVariant("manual"), v6["method"])
					assert.Equal(t, dbus.MakeVariant([][]byte{gateway}), v6["dns"])
					assert.Equal(t, dbus.MakeVariant(int64(123)), v6["route-metric"])
					assert.Len(t, v6, 5)
					assert.NotContains(t, settings["vpn"], "secrets")
				default:
					t.Fatalf("unexpected method %s", method)
				}
				return nil
			})
			require.NoError(t, err)
			require.True(t, updated)
		})
	}
}

func TestUpdateOpenConnectAgentFlagsRejectsInvalidLegacyIPv6(t *testing.T) {
	for _, field := range []string{"addresses", "routes"} {
		for _, value := range []any{"invalid", [][]any{{[]byte{1}, "invalid-prefix", []byte{2}}}} {
			t.Run(field, func(t *testing.T) {
				data := map[string]string{"unchanged": "yes"}
				err := updateOpenConnectAgentFlags(data, func(method string, result any, args ...any) error {
					require.Equal(t, "org.freedesktop.NetworkManager.Settings.Connection.GetSettings", method)
					*result.(*map[string]map[string]dbus.Variant) = map[string]map[string]dbus.Variant{
						"vpn":  {"data": dbus.MakeVariant(map[string]string{})},
						"ipv6": {field: dbus.MakeVariant(value)},
					}
					return nil
				})
				require.ErrorContains(t, err, "failed to convert ipv6."+field)
				assert.Equal(t, map[string]string{"unchanged": "yes"}, data)
			})
		}
	}
}
