package network

import (
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestE2E_BridgeWithPort(t *testing.T) {
	f := newEditorFixture(t)
	settingsObj := f.object(t, nmSettingsPath)
	bridge := captureAddConnection(settingsObj, nmSettingsAddConnection)

	resp := e2eRequest(t, f.backend, "network.connection.add", map[string]any{
		"settings": map[string]any{
			"connection": map[string]any{
				"id": "dms-test-br", "type": "bridge", "interface-name": "dmsbr0",
				"autoconnect": false, "autoconnect-slaves": float64(1),
			},
			"bridge": map[string]any{"stp": true, "priority": float64(4096)},
			"ipv4":   map[string]any{"method": "auto"},
			"ipv6":   map[string]any{"method": "auto"},
		},
	})
	require.Empty(t, resp.Error)

	b := *bridge
	assert.Equal(t, "i", b["connection"]["autoconnect-slaves"].Signature().String())
	assert.Equal(t, int32(1), b["connection"]["autoconnect-slaves"].Value())
	assert.Equal(t, "b", b["bridge"]["stp"].Signature().String())
	assert.Equal(t, true, b["bridge"]["stp"].Value())
	assert.Equal(t, "u", b["bridge"]["priority"].Signature().String())
	assert.Equal(t, uint32(4096), b["bridge"]["priority"].Value())
	uuid, ok := b["connection"]["uuid"].Value().(string)
	require.True(t, ok)

	port := captureAddConnection(settingsObj, nmSettingsAddConnection)
	resp = e2eRequest(t, f.backend, "network.connection.add", map[string]any{
		"settings": map[string]any{
			"connection": map[string]any{
				"id": "enp5s0-port-dmsbr0", "type": "802-3-ethernet", "interface-name": "enp5s0",
				"master": uuid, "slave-type": "bridge",
			},
			"802-3-ethernet": map[string]any{},
			"bridge-port":    map[string]any{"priority": float64(16)},
		},
	})
	require.Empty(t, resp.Error)

	p := *port
	assert.Equal(t, "s", p["connection"]["master"].Signature().String())
	assert.Equal(t, uuid, p["connection"]["master"].Value())
	assert.Equal(t, "s", p["connection"]["slave-type"].Signature().String())
	assert.Equal(t, "bridge", p["connection"]["slave-type"].Value())
	assert.Equal(t, "u", p["bridge-port"]["priority"].Signature().String())
	assert.Equal(t, uint32(16), p["bridge-port"]["priority"].Value())
	assert.NotContains(t, p, "ipv4")
	assert.NotContains(t, p, "ipv6")
}

func TestE2E_VlanAddAndBondArpUpdate(t *testing.T) {
	f := newEditorFixture(t)
	added := captureAddConnection(f.object(t, nmSettingsPath), nmSettingsAddConnection)

	resp := e2eRequest(t, f.backend, "network.connection.add", map[string]any{
		"settings": map[string]any{
			"connection": map[string]any{"id": "dms-test-vlan", "type": "vlan", "interface-name": "enp5s0.100", "autoconnect": false},
			"vlan":       map[string]any{"parent": "enp5s0", "id": float64(100), "flags": float64(3)},
			"ipv4":       map[string]any{"method": "auto"},
			"ipv6":       map[string]any{"method": "auto"},
		},
	})
	require.Empty(t, resp.Error)
	v := (*added)["vlan"]
	assert.Equal(t, "s", v["parent"].Signature().String())
	assert.Equal(t, "enp5s0", v["parent"].Value())
	assert.Equal(t, "u", v["id"].Signature().String())
	assert.Equal(t, uint32(100), v["id"].Value())
	assert.Equal(t, "u", v["flags"].Signature().String())
	assert.Equal(t, uint32(3), v["flags"].Value())

	obj := f.profile(t, "u-bond", "/s/bond")
	stored := connSection("u-bond", "dms-test-bond", "bond", map[string]dbus.Variant{
		"interface-name": dbus.MakeVariant("dmsbond0"),
	})
	stored["bond"] = map[string]dbus.Variant{"options": dbus.MakeVariant(map[string]string{
		"mode": "active-backup", "miimon": "100", "primary": "enp5s0",
		"updelay": "200", "downdelay": "200",
	})}
	expectGetSettings(obj, stored)
	got := captureUpdate2(obj, 0, nil)

	resp = e2eRequest(t, f.backend, "network.connection.update", map[string]any{
		"uuid": "u-bond",
		"settings": map[string]any{"bond": map[string]any{"options": map[string]any{
			"mode": "active-backup", "miimon": "0", "arp_interval": "1000",
			"arp_ip_target": "192.0.2.1,192.0.2.2", "primary": "enp5s0",
		}}},
	})
	require.Empty(t, resp.Error)
	opts := (*got)["bond"]["options"]
	assert.Equal(t, "a{ss}", opts.Signature().String())
	assert.Equal(t, map[string]string{
		"mode": "active-backup", "miimon": "0", "arp_interval": "1000",
		"arp_ip_target": "192.0.2.1,192.0.2.2", "primary": "enp5s0",
	}, opts.Value())
}

func TestE2E_DSLAdd(t *testing.T) {
	f := newEditorFixture(t)
	settingsObj := f.object(t, nmSettingsPath)

	pppoe := captureAddConnection(settingsObj, nmSettingsAddConnection)
	resp := e2eRequest(t, f.backend, "network.connection.add", map[string]any{
		"settings": map[string]any{
			"connection":     map[string]any{"id": "dms-test-dsl", "type": "pppoe", "autoconnect": false},
			"pppoe":          map[string]any{"username": "user@isp.example", "service": "isp"},
			"802-3-ethernet": map[string]any{},
			"ppp": map[string]any{
				"refuse-pap": true, "lcp-echo-interval": float64(30), "lcp-echo-failure": float64(5),
			},
			"ipv4": map[string]any{"method": "auto"},
			"ipv6": map[string]any{"method": "auto"},
		},
	})
	require.Empty(t, resp.Error)
	s := *pppoe
	assert.Equal(t, "user@isp.example", s["pppoe"]["username"].Value())
	assert.Equal(t, "isp", s["pppoe"]["service"].Value())
	assert.Equal(t, "b", s["ppp"]["refuse-pap"].Signature().String())
	assert.Equal(t, true, s["ppp"]["refuse-pap"].Value())
	assert.Equal(t, "u", s["ppp"]["lcp-echo-interval"].Signature().String())
	assert.Equal(t, uint32(30), s["ppp"]["lcp-echo-interval"].Value())
	assert.Equal(t, uint32(5), s["ppp"]["lcp-echo-failure"].Value())
}
