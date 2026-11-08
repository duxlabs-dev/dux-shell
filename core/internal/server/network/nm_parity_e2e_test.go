package network

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestE2E_VlanAdd(t *testing.T) {
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
