package network

import (
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
)

func TestNeedsExternalBrowserAuth(t *testing.T) {
	tests := []struct {
		name     string
		protocol string
		authType string
		username string
		data     map[string]string
		expected bool
	}{
		{
			name:     "GP with saml-auth-method REDIRECT",
			protocol: "gp",
			authType: "password",
			username: "user",
			data:     map[string]string{"saml-auth-method": "REDIRECT"},
			expected: true,
		},
		{
			name:     "GP with no authtype and no username",
			protocol: "gp",
			authType: "",
			username: "",
			data:     map[string]string{},
			expected: true,
		},
		{
			name:     "GP with username and password authtype",
			protocol: "gp",
			authType: "password",
			username: "john",
			data:     map[string]string{},
			expected: false,
		},
		{
			name:     "fortinet with non-password authtype",
			protocol: "fortinet",
			authType: "saml",
			username: "",
			data:     map[string]string{},
			expected: true,
		},
		{
			name:     "anyconnect with cert",
			protocol: "anyconnect",
			authType: "cert",
			username: "",
			data:     map[string]string{},
			expected: false,
		},
		{
			name:     "GP with cert authtype",
			protocol: "gp",
			authType: "cert",
			username: "",
			data:     map[string]string{},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := needsExternalBrowserAuth(tt.protocol, tt.authType, tt.username, tt.data)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestBuildOpenConnectSecretsResponse(t *testing.T) {
	tests := []struct {
		name        string
		settingName string
		cookie      string
		host        string
		fingerprint string
		resolve     string
	}{
		{
			name:        "all fields populated",
			settingName: "vpn",
			cookie:      "authcookie=abc123&portal=GATE",
			host:        "vpn.example.com",
			fingerprint: "pin-sha256:ABCD1234",
			resolve:     "vpn.example.com:192.0.2.10",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := buildOpenConnectSecretsResponse(tt.settingName, tt.cookie, tt.host, tt.fingerprint, tt.resolve)

			assert.NotNil(t, result)
			assert.Contains(t, result, tt.settingName)

			vpnSec := result[tt.settingName]
			assert.NotNil(t, vpnSec)

			secretsVariant, ok := vpnSec["secrets"]
			assert.True(t, ok, "secrets key should exist")

			secrets, ok := secretsVariant.Value().(map[string]string)
			assert.True(t, ok, "secrets should be map[string]string")

			assert.Equal(t, tt.cookie, secrets["cookie"])
			assert.Equal(t, tt.host, secrets["gateway"])
			assert.Equal(t, tt.fingerprint, secrets["gwcert"])
			assert.Contains(t, secrets, "resolve")
			assert.Equal(t, tt.resolve, secrets["resolve"])
		})
	}
}

func TestSecretAgentCachedOpenConnectFullHandoff(t *testing.T) {
	for _, tt := range []struct {
		name     string
		protocol string
		authtype string
		resolve  string
	}{
		{name: "GP resolved endpoint", protocol: "gp", resolve: "redirect.example.test:192.0.2.10"},
		{name: "GP clear stale resolve", protocol: "gp"},
		{name: "Fortinet SAML resolved endpoint", protocol: "fortinet", authtype: "saml", resolve: "redirect.example.test:192.0.2.10"},
		{name: "Fortinet SAML clear stale resolve", protocol: "fortinet", authtype: "saml"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			backend := &NetworkManagerBackend{
				state: &BackendState{IsConnectingVPN: true, ConnectingVPNUUID: "test-uuid"},
			}
			backend.cacheOpenConnectAuthentication("/test/path", "test-uuid", &openConnectAuthResult{
				Cookie:      "COOKIE-VALUE",
				Host:        "https://redirect.example.test/ssl-vpn",
				Resolve:     tt.resolve,
				Fingerprint: "pin-sha256:FINGERPRINT",
			})
			assert.Equal(t, dbus.ObjectPath("/test/path"), backend.cachedOpenConnectAuth.ConnectionPath)
			agent := &SecretAgent{backend: backend}
			conn := map[string]nmVariantMap{
				"connection": {
					"id":   dbus.MakeVariant("Test VPN"),
					"type": dbus.MakeVariant("vpn"),
					"uuid": dbus.MakeVariant("test-uuid"),
				},
				"vpn": {
					"service-type": dbus.MakeVariant("org.freedesktop.NetworkManager.openconnect"),
					"data":         dbus.MakeVariant(map[string]string{"protocol": tt.protocol, "authtype": tt.authtype}),
					"secrets": dbus.MakeVariant(map[string]string{
						"resolve": "redirect.example.test:192.0.2.99",
					}),
				},
			}

			_, dbusErr := agent.GetSecrets(conn, "/test/path", "vpn", nil, nmSecretAgentFlagUserRequested)
			if assert.NotNil(t, dbusErr) {
				assert.Equal(t, "org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", dbusErr.Name)
			}
			assert.NotNil(t, backend.cachedOpenConnectAuth, "noninteractive pass must preserve the handoff")
			result, dbusErr := agent.GetSecrets(conn, "/test/path", "vpn", nil, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagUserRequested)
			if !assert.Nil(t, dbusErr) {
				return
			}
			secrets := result["vpn"]["secrets"].Value().(map[string]string)
			assert.Equal(t, map[string]string{
				"cookie":  "COOKIE-VALUE",
				"gateway": "https://redirect.example.test/ssl-vpn",
				"gwcert":  "pin-sha256:FINGERPRINT",
				"resolve": tt.resolve,
			}, secrets)
			assert.Nil(t, backend.cachedOpenConnectAuth)
		})
	}
}

func TestSecretAgentExternalGPLegacyCacheOneShot(t *testing.T) {
	backend := &NetworkManagerBackend{
		state:                 &BackendState{}, // Authentication was started externally, not through DMS.
		cachedOpenConnectAuth: &cachedOpenConnectAuth{ConnectionUUID: "one", Cookie: "handoff", Host: "vpn.example"},
	}
	broker := &fakePromptBroker{asked: make(chan PromptRequest, 1), reply: PromptReply{Secrets: map[string]string{"cookie": "fresh"}}}
	agent := &SecretAgent{backend: backend, prompts: broker}
	conn := helperAgentConnection("one")
	conn["vpn"]["data"] = dbus.MakeVariant(map[string]string{"protocol": "gp"})
	_, err := agent.GetSecrets(conn, "/settings/one", "vpn", []string{"cookie"}, nmSecretAgentFlagUserRequested)
	if assert.NotNil(t, err) {
		assert.Equal(t, "org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", err.Name)
	}
	if assert.NotNil(t, backend.cachedOpenConnectAuth) {
		assert.Equal(t, dbus.ObjectPath("/settings/one"), backend.cachedOpenConnectAuth.ConnectionPath)
	}
	out, err := agent.GetSecrets(conn, "/settings/one", "vpn", []string{"cookie"}, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagUserRequested)
	if !assert.Nil(t, err) {
		return
	}
	assert.Equal(t, "handoff", out["vpn"]["secrets"].Value().(map[string]string)["cookie"])
	assert.Nil(t, backend.cachedOpenConnectAuth, "external activation must not retain the legacy cache")
	// REQUEST_NEW skips keyring access and deterministically exercises fresh authentication.
	out, err = agent.GetSecrets(conn, "/settings/one", "vpn", []string{"cookie"}, nmSecretAgentFlagAllowInteraction|nmSecretAgentFlagRequestNew)
	if assert.Nil(t, err) {
		assert.Equal(t, "fresh", out["vpn"]["secrets"].Value().(map[string]string)["cookie"])
	}
	assert.Len(t, broker.asked, 1)
}

func TestSecretAgentLegacyRequestNewInvalidatesOnlyMatchingCache(t *testing.T) {
	for _, cachedUUID := range []string{"one", "other"} {
		for _, interactive := range []bool{false, true} {
			t.Run(cachedUUID+map[bool]string{false: "/noninteractive", true: "/interactive"}[interactive], func(t *testing.T) {
				cached := &cachedOpenConnectAuth{ConnectionUUID: cachedUUID, Cookie: "stale"}
				backend := &NetworkManagerBackend{state: &BackendState{}, cachedOpenConnectAuth: cached}
				broker := &fakePromptBroker{asked: make(chan PromptRequest, 1), reply: PromptReply{Secrets: map[string]string{"cookie": "fresh"}}}
				agent := &SecretAgent{backend: backend, prompts: broker}
				conn := helperAgentConnection("one")
				conn["vpn"]["data"] = dbus.MakeVariant(map[string]string{"protocol": "gp"})
				flags := uint32(nmSecretAgentFlagRequestNew)
				hints := []string{"gp-saml"}
				if interactive {
					flags |= nmSecretAgentFlagAllowInteraction
					hints = []string{"cookie"}
				}
				out, err := agent.GetSecrets(conn, "/settings/one", "vpn", hints, flags)
				if interactive {
					if assert.Nil(t, err) {
						assert.Equal(t, "fresh", out["vpn"]["secrets"].Value().(map[string]string)["cookie"])
					}
					assert.Len(t, broker.asked, 1)
				} else if assert.NotNil(t, err) {
					assert.Equal(t, "org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", err.Name)
					assert.Empty(t, broker.asked)
				}
				if cachedUUID == "one" {
					assert.Nil(t, backend.cachedOpenConnectAuth)
				} else {
					assert.Same(t, cached, backend.cachedOpenConnectAuth)
				}
			})
		}
	}
}

func TestSecretAgentCancelLegacyCacheMatchesKnownPath(t *testing.T) {
	for _, path := range []dbus.ObjectPath{"/settings/one", "/settings/other", "", "/"} {
		t.Run(string(path), func(t *testing.T) {
			cached := &cachedOpenConnectAuth{ConnectionUUID: "one", ConnectionPath: path, Cookie: "handoff"}
			backend := &NetworkManagerBackend{state: &BackendState{}, cachedOpenConnectAuth: cached}
			agent := &SecretAgent{backend: backend}
			agent.CancelGetSecrets("/settings/one", "802-11-wireless-security")
			assert.Same(t, cached, backend.cachedOpenConnectAuth)
			agent.CancelGetSecrets("/settings/one", "vpn")
			if path == "/settings/one" {
				assert.Nil(t, backend.cachedOpenConnectAuth)
			} else {
				assert.Same(t, cached, backend.cachedOpenConnectAuth)
			}
		})
	}
}

func TestInferVPNFields_GPSaml(t *testing.T) {
	tests := []struct {
		name        string
		vpnService  string
		dataMap     map[string]string
		expectedLen int
		shouldHave  []string
	}{
		{
			name:       "GP with no authtype and no username - should require SAML",
			vpnService: "org.freedesktop.NetworkManager.openconnect",
			dataMap: map[string]string{
				"protocol": "gp",
				"gateway":  "vpn.example.com",
			},
			expectedLen: 1,
			shouldHave:  []string{"gp-saml"},
		},
		{
			name:       "GP with saml-auth-method REDIRECT",
			vpnService: "org.freedesktop.NetworkManager.openconnect",
			dataMap: map[string]string{
				"protocol":         "gp",
				"gateway":          "vpn.example.com",
				"saml-auth-method": "REDIRECT",
				"username":         "john",
			},
			expectedLen: 1,
			shouldHave:  []string{"gp-saml"},
		},
		{
			name:       "GP with username and password authtype - should use credentials",
			vpnService: "org.freedesktop.NetworkManager.openconnect",
			dataMap: map[string]string{
				"protocol": "gp",
				"gateway":  "vpn.example.com",
				"authtype": "password",
				"username": "john",
			},
			expectedLen: 1,
			shouldHave:  []string{"password"},
		},
		{
			name:       "GP with PKCS11 cert",
			vpnService: "org.freedesktop.NetworkManager.openconnect",
			dataMap: map[string]string{
				"protocol": "gp",
				"gateway":  "vpn.example.com",
				"authtype": "cert",
				"usercert": "pkcs11:model=PKCS%2315%20emulated;manufacturer=piv_II",
			},
			expectedLen: 1,
			shouldHave:  []string{"key_pass"},
		},
		{
			name:       "non-GP protocol (anyconnect)",
			vpnService: "org.freedesktop.NetworkManager.openconnect",
			dataMap: map[string]string{
				"protocol": "anyconnect",
				"gateway":  "vpn.example.com",
			},
			expectedLen: 2,
			shouldHave:  []string{"username", "password"},
		},
		{
			name:       "OpenVPN with username",
			vpnService: "org.freedesktop.NetworkManager.openvpn",
			dataMap: map[string]string{
				"connection-type": "password",
				"username":        "john",
			},
			expectedLen: 1,
			shouldHave:  []string{"password"},
		},
		{
			name:       "OpenVPN cert auth (tls) - private-key passphrase",
			vpnService: "org.freedesktop.NetworkManager.openvpn",
			dataMap: map[string]string{
				"connection-type": "tls",
			},
			expectedLen: 1,
			shouldHave:  []string{"cert-pass"},
		},
		{
			name:       "OpenVPN cert auth (tls) with passphrase-less key",
			vpnService: "org.freedesktop.NetworkManager.openvpn",
			dataMap: map[string]string{
				"connection-type": "tls",
				"cert-pass-flags": "4",
			},
			expectedLen: 0,
		},
		{
			name:       "OpenVPN password-tls no username",
			vpnService: "org.freedesktop.NetworkManager.openvpn",
			dataMap: map[string]string{
				"connection-type": "password-tls",
			},
			expectedLen: 3,
			shouldHave:  []string{"username", "password", "cert-pass"},
		},
		{
			name:       "OpenVPN password-tls with username, passphrase-less key",
			vpnService: "org.freedesktop.NetworkManager.openvpn",
			dataMap: map[string]string{
				"connection-type": "password-tls",
				"username":        "john",
				"cert-pass-flags": "4",
			},
			expectedLen: 1,
			shouldHave:  []string{"password"},
		},
		{
			name:       "Fortinet SAML",
			vpnService: "org.freedesktop.NetworkManager.openconnect",
			dataMap: map[string]string{
				"protocol": "fortinet",
				"authtype": "saml",
				"gateway":  "vpn.example.com",
			},
			expectedLen: 1,
			shouldHave:  []string{"fortinet-saml"},
		},
		{
			name:       "Fortinet password auth is not SAML",
			vpnService: "org.freedesktop.NetworkManager.openconnect",
			dataMap: map[string]string{
				"protocol": "fortinet",
				"authtype": "password",
				"username": "john",
				"gateway":  "vpn.example.com",
			},
			expectedLen: 1,
			shouldHave:  []string{"password"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Convert dataMap to nmVariantMap
			vpnSettings := make(nmVariantMap)
			vpnSettings["data"] = dbus.MakeVariant(tt.dataMap)
			vpnSettings["service-type"] = dbus.MakeVariant(tt.vpnService)

			conn := make(map[string]nmVariantMap)
			conn["vpn"] = vpnSettings

			fields := inferVPNFields(conn, tt.vpnService)

			assert.Len(t, fields, tt.expectedLen, "unexpected number of fields")
			if len(tt.shouldHave) > 0 {
				for _, expected := range tt.shouldHave {
					assert.Contains(t, fields, expected, "should contain field: %s", expected)
				}
			}
		})
	}
}

func TestSecretAgent_GetSecrets_OnlySystemFlag(t *testing.T) {
	agent := &SecretAgent{}
	conn := map[string]nmVariantMap{
		"connection": {
			"id":   dbus.MakeVariant("TestWiFi"),
			"type": dbus.MakeVariant("802-11-wireless"),
		},
		"802-11-wireless": {
			"ssid": dbus.MakeVariant("TestSSID"),
		},
	}

	_, err := agent.GetSecrets(conn, "/test/path", "802-11-wireless-security", nil, 0x80000000)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "NoSecrets")
}

func TestSecretAgent_GetSecrets_NoInteractionFlag(t *testing.T) {
	agent := &SecretAgent{}
	conn := map[string]nmVariantMap{
		"connection": {
			"id":   dbus.MakeVariant("TestWiFi"),
			"type": dbus.MakeVariant("802-11-wireless"),
		},
		"802-11-wireless": {
			"ssid": dbus.MakeVariant("TestSSID"),
		},
	}

	// flags=0 means ALLOW_INTERACTION is not set
	_, err := agent.GetSecrets(conn, "/test/path", "802-11-wireless-security", nil, 0x0)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "NoSecrets")
}

func TestSecretAgent_GetSecrets_OpenVPNDynamicChallenge(t *testing.T) {
	conn := map[string]nmVariantMap{
		"connection": {
			"id":   dbus.MakeVariant("Work VPN"),
			"type": dbus.MakeVariant("vpn"),
		},
		"vpn": {
			"service-type": dbus.MakeVariant("org.freedesktop.NetworkManager.openvpn"),
		},
	}

	tests := []struct {
		name     string
		hint     string
		isSecret bool
	}{
		{"noecho", "x-dynamic-challenge:challenge-response", true},
		{"echo", "x-dynamic-challenge-echo:challenge-response", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			broker := &fakePromptBroker{
				asked: make(chan PromptRequest, 1),
				reply: PromptReply{Secrets: map[string]string{"challenge-response": "123456"}},
			}
			agent := &SecretAgent{prompts: broker}
			hints := []string{tt.hint, "x-vpn-message:Enter your OTP"}

			out, err := agent.GetSecrets(conn, "/test/path", "vpn", hints, nmSecretAgentFlagAllowInteraction)
			assert.Nil(t, err)

			req := <-broker.asked
			assert.Equal(t, []string{"challenge-response"}, req.Fields)
			assert.Equal(t, []FieldInfo{{Name: "challenge-response", Label: "Challenge Response", IsSecret: tt.isSecret}}, req.FieldsInfo)

			secrets, _ := out["vpn"]["secrets"].Value().(map[string]string)
			assert.Equal(t, map[string]string{"challenge-response": "123456"}, secrets)
		})
	}
}

func TestBuildWiFiSecretsResponse(t *testing.T) {
	t.Run("wpa-psk returns psk", func(t *testing.T) {
		out := buildWiFiSecretsResponse("802-11-wireless-security", map[string]string{"psk": "hunter2"})

		sec, ok := out["802-11-wireless-security"]
		assert.True(t, ok)
		assert.Equal(t, "hunter2", sec["psk"].Value())
	})

	t.Run("802-1x keeps secrets and drops identity", func(t *testing.T) {
		out := buildWiFiSecretsResponse("802-1x", map[string]string{
			"identity": "john",
			"password": "hunter2",
		})

		sec := out["802-1x"]
		assert.Equal(t, "hunter2", sec["password"].Value())
		_, hasIdentity := sec["identity"]
		assert.False(t, hasIdentity, "identity is persisted separately, not returned as a secret")
	})
}

func TestAgentOwnedSecrets(t *testing.T) {
	t.Run("agent-owned password extracted", func(t *testing.T) {
		conn := map[string]nmVariantMap{
			"802-1x": {
				"identity":       dbus.MakeVariant("john"),
				"password":       dbus.MakeVariant("hunter2"),
				"password-flags": dbus.MakeVariant(uint32(1)),
			},
		}

		owned := agentOwnedSecrets(conn)
		assert.Equal(t, map[string]map[string]string{
			"802-1x": {"password": "hunter2"},
		}, owned)
	})

	t.Run("system-owned and flagless secrets skipped", func(t *testing.T) {
		conn := map[string]nmVariantMap{
			"802-11-wireless-security": {
				"key-mgmt":  dbus.MakeVariant("wpa-psk"),
				"psk":       dbus.MakeVariant("hunter2"),
				"psk-flags": dbus.MakeVariant(uint32(0)),
			},
			"802-1x": {
				"password": dbus.MakeVariant("hunter2"),
			},
		}

		assert.Empty(t, agentOwnedSecrets(conn))
	})

	t.Run("not-saved flag skipped", func(t *testing.T) {
		conn := map[string]nmVariantMap{
			"802-1x": {
				"password":       dbus.MakeVariant("hunter2"),
				"password-flags": dbus.MakeVariant(uint32(2)),
			},
		}

		assert.Empty(t, agentOwnedSecrets(conn))
	})
}

func TestWiFiSecretCache(t *testing.T) {
	b := &NetworkManagerBackend{}

	b.cacheWiFiSecret("uuid-1", "HomeNet", "802-11-wireless-security", map[string]string{"psk": "hunter2"})

	got := b.lookupCachedWiFiSecret("uuid-1", "802-11-wireless-security")
	assert.Equal(t, map[string]string{"psk": "hunter2"}, got)

	assert.Nil(t, b.lookupCachedWiFiSecret("uuid-1", "802-1x"), "setting mismatch must miss")
	assert.Nil(t, b.lookupCachedWiFiSecret("uuid-2", "802-11-wireless-security"), "uuid mismatch must miss")
	assert.Nil(t, b.lookupCachedWiFiSecret("", "802-11-wireless-security"), "empty uuid must miss")

	// REQUEST_NEW path clears by uuid.
	b.clearCachedWiFiSecret("uuid-1")
	assert.Nil(t, b.lookupCachedWiFiSecret("uuid-1", "802-11-wireless-security"))

	// Returned map is a copy: mutating it must not affect the cache.
	b.cacheWiFiSecret("uuid-1", "HomeNet", "802-11-wireless-security", map[string]string{"psk": "hunter2"})
	got = b.lookupCachedWiFiSecret("uuid-1", "802-11-wireless-security")
	got["psk"] = "tampered"
	assert.Equal(t, "hunter2", b.lookupCachedWiFiSecret("uuid-1", "802-11-wireless-security")["psk"])

	// Terminal-state path clears by SSID.
	b.clearCachedWiFiSecretBySSID("OtherNet")
	assert.NotNil(t, b.lookupCachedWiFiSecret("uuid-1", "802-11-wireless-security"), "ssid mismatch must not clear")
	b.clearCachedWiFiSecretBySSID("HomeNet")
	assert.Nil(t, b.lookupCachedWiFiSecret("uuid-1", "802-11-wireless-security"))
}
