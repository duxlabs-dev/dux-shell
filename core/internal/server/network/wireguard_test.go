package network

import (
	"encoding/base64"
	"encoding/hex"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWireGuardKeys(t *testing.T) {
	priv, _ := hex.DecodeString("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
	want, _ := hex.DecodeString("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
	pub, err := wireGuardPublicKey(base64.StdEncoding.EncodeToString(priv))
	require.NoError(t, err)
	assert.Equal(t, base64.StdEncoding.EncodeToString(want), pub)

	priv64, pub64, err := generateWireGuardKeyPair()
	require.NoError(t, err)
	derived, err := wireGuardPublicKey(priv64)
	require.NoError(t, err)
	assert.Equal(t, pub64, derived)
}

func wgTestSettings() map[string]map[string]any {
	return map[string]map[string]any{
		"wireguard": {
			"private-key": "PRIV",
			"peers": []map[string]any{{
				"public-key": "PUB1", "endpoint": "vpn.example.com:51820",
				"allowed-ips": []string{"0.0.0.0/0", "::/0"},
			}},
		},
		"ipv4": {"address-data": []map[string]any{{"address": "10.0.0.2", "prefix": uint32(32)}}, "dns-data": []string{"10.0.0.1"}},
		"ipv6": {"address-data": []map[string]any{{"address": "fd00::2", "prefix": uint32(128)}}},
	}
}

func TestWgQuickConfig(t *testing.T) {
	got, err := wgQuickConfig(wgTestSettings())
	require.NoError(t, err)
	assert.Equal(t, "[Interface]\nPrivateKey = PRIV\nAddress = 10.0.0.2/32, fd00::2/128\nDNS = 10.0.0.1\n\n"+
		"[Peer]\nPublicKey = PUB1\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = vpn.example.com:51820\n", got)

	for name, mutate := range map[string]func(s map[string]map[string]any){
		"PrivateKey": func(s map[string]map[string]any) { s["wireguard"]["private-key"] = "PRIV\nPostUp = x" },
		"DNS":        func(s map[string]map[string]any) { s["ipv4"]["dns-data"] = []string{"1.1.1.1\nPostUp = x"} },
		"Endpoint": func(s map[string]map[string]any) {
			s["wireguard"]["peers"].([]map[string]any)[0]["endpoint"] = "h:1\nPostUp = x"
		},
		"AllowedIPs": func(s map[string]map[string]any) {
			s["wireguard"]["peers"].([]map[string]any)[0]["allowed-ips"] = []string{"0.0.0.0/0\nPostUp = x"}
		},
	} {
		s := wgTestSettings()
		mutate(s)
		_, err := wgQuickConfig(s)
		assert.ErrorContains(t, err, name)
	}
}
