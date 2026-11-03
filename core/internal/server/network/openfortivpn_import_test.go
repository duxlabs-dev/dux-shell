package network

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseOpenfortivpnConfig(t *testing.T) {
	const digest = "aa11bb22cc33dd44ee55ff6600778899aabbccddeeff00112233445566778899"

	t.Run("reads the fields that map onto a profile", func(t *testing.T) {
		cfg, err := parseOpenfortivpnConfig(strings.NewReader(`
# work VPN
host = vpn.example.com
port = 10443
username = jdoe
realm = contractors
trusted-cert = ` + digest + `
saml-login = 9000
set-dns = 0
pppd-use-peerdns = 1
`))
		require.NoError(t, err)
		assert.Equal(t, "vpn.example.com", cfg.Host)
		assert.Equal(t, 10443, cfg.Port)
		assert.Equal(t, "jdoe", cfg.Username)
		assert.Equal(t, "contractors", cfg.Realm)
		assert.Equal(t, []string{digest}, cfg.TrustedCerts)
		assert.True(t, cfg.SAML)
		assert.Equal(t, 9000, cfg.SAMLPort)
	})

	t.Run("reads the credentials the shipped template carries", func(t *testing.T) {
		cfg, err := parseOpenfortivpnConfig(strings.NewReader(`
host = vpn.example.org
port = 443
username = vpnuser
password = VPNpassw0rd
`))
		require.NoError(t, err)
		assert.Equal(t, "vpnuser", cfg.Username)
		assert.Equal(t, "VPNpassw0rd", cfg.Password)
		assert.False(t, cfg.SAML)
	})

	t.Run("defaults the gateway port", func(t *testing.T) {
		cfg, err := parseOpenfortivpnConfig(strings.NewReader("host=vpn.example.com\n"))
		require.NoError(t, err)
		assert.Equal(t, fortinetDefaultGatewayPort, cfg.Port)
		assert.False(t, cfg.SAML)
		assert.Zero(t, cfg.SAMLPort)
	})

	t.Run("collects several trusted certs and lowercases them", func(t *testing.T) {
		other := strings.Repeat("bb", 32)
		cfg, err := parseOpenfortivpnConfig(strings.NewReader(
			"host = vpn.example.com\ntrusted-cert = " + strings.ToUpper(digest) + "\ntrusted-cert = " + other + "\n"))
		require.NoError(t, err)
		assert.Equal(t, []string{digest, other}, cfg.TrustedCerts)
	})

	t.Run("skips a malformed trusted cert", func(t *testing.T) {
		cfg, err := parseOpenfortivpnConfig(strings.NewReader("host = vpn.example.com\ntrusted-cert = nope\n"))
		require.NoError(t, err)
		assert.Empty(t, cfg.TrustedCerts)
	})

	t.Run("rejects files that are not openfortivpn configs", func(t *testing.T) {
		tests := []struct {
			name  string
			input string
		}{
			{name: "wireguard", input: "[Interface]\nPrivateKey = abc\nAddress = 10.0.0.2/32\n"},
			{name: "no host", input: "port = 443\nusername = jdoe\n"},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				_, err := parseOpenfortivpnConfig(strings.NewReader(tt.input))
				assert.Error(t, err)
			})
		}
	})

	t.Run("rejects out of range ports", func(t *testing.T) {
		_, err := parseOpenfortivpnConfig(strings.NewReader("host = vpn.example.com\nport = 70000\n"))
		assert.ErrorContains(t, err, "invalid port")

		_, err = parseOpenfortivpnConfig(strings.NewReader("host = vpn.example.com\nsaml-login = 0\n"))
		assert.ErrorContains(t, err, "invalid saml-login port")
	})
}

func TestOpenfortivpnConfigProfile(t *testing.T) {
	t.Run("a saml-login config selects SAML and drops the password", func(t *testing.T) {
		cfg := &openfortivpnConfig{
			Host:         "vpn.example.com",
			Port:         10443,
			Username:     "jdoe",
			Password:     "hunter2",
			Realm:        "contractors",
			SAML:         true,
			SAMLPort:     9000,
			TrustedCerts: []string{"aa", "bb"},
		}

		assert.Equal(t, fortinetProfile{
			Host:         "vpn.example.com",
			Port:         10443,
			Username:     "jdoe",
			Realm:        "contractors",
			SAML:         true,
			SAMLPort:     9000,
			TrustedCerts: []string{"aa", "bb"},
		}, cfg.profile())
	})

	t.Run("a config without saml-login carries its credentials", func(t *testing.T) {
		cfg := &openfortivpnConfig{
			Host:     "vpn.example.com",
			Port:     443,
			Username: "jdoe",
			Password: "hunter2",
		}

		assert.Equal(t, fortinetProfile{
			Host:     "vpn.example.com",
			Port:     443,
			Username: "jdoe",
			Password: "hunter2",
		}, cfg.profile())
	})
}
