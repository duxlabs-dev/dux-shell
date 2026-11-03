package network

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSplitGatewayHostPort(t *testing.T) {
	tests := []struct {
		name     string
		gateway  string
		wantHost string
		wantPort int
		wantErr  bool
	}{
		{name: "bare host", gateway: "vpn.example.com", wantHost: "vpn.example.com", wantPort: 443},
		{name: "host and port", gateway: "vpn.example.com:10443", wantHost: "vpn.example.com", wantPort: 10443},
		{name: "https url", gateway: "https://vpn.example.com:10443/", wantHost: "vpn.example.com", wantPort: 10443},
		{name: "surrounding space", gateway: "  vpn.example.com  ", wantHost: "vpn.example.com", wantPort: 443},
		{name: "ipv6 with port", gateway: "[2001:db8::1]:10443", wantHost: "2001:db8::1", wantPort: 10443},
		{name: "bracketed ipv6 without port", gateway: "[2001:db8::1]", wantHost: "2001:db8::1", wantPort: 443},
		{name: "bare ipv6", gateway: "2001:db8::1", wantHost: "2001:db8::1", wantPort: 443},
		{name: "empty", gateway: "", wantErr: true},
		{name: "port out of range", gateway: "vpn.example.com:99999", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			host, port, err := splitGatewayHostPort(tt.gateway)
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.wantHost, host)
			assert.Equal(t, tt.wantPort, port)
		})
	}
}

func TestFortinetSAMLStartURL(t *testing.T) {
	assert.Equal(t,
		"https://vpn.example.com:443/remote/saml/start?redirect=1",
		fortinetSAMLStartURL("vpn.example.com", 443, ""))

	assert.Equal(t,
		"https://vpn.example.com:10443/remote/saml/start?redirect=1&realm=my+realm%2Fone",
		fortinetSAMLStartURL("vpn.example.com", 10443, "my realm/one"))
}

func TestFortinetSAMLListenPort(t *testing.T) {
	tests := []struct {
		name string
		data map[string]string
		want int
	}{
		{name: "unset", data: map[string]string{}, want: fortinetSAMLDefaultListenPort},
		{name: "custom", data: map[string]string{"saml-port": "9000"}, want: 9000},
		{name: "out of range", data: map[string]string{"saml-port": "70000"}, want: fortinetSAMLDefaultListenPort},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, fortinetSAMLListenPort(tt.data))
		})
	}
}

func TestCertDigestTrusted(t *testing.T) {
	digest := "aa11bb22cc33dd44ee55ff6600778899aabbccddeeff00112233445566778899"

	tests := []struct {
		name    string
		trusted string
		want    bool
	}{
		{name: "case insensitive", trusted: "AA11BB22CC33DD44EE55FF6600778899AABBCCDDEEFF00112233445566778899", want: true},
		{name: "one of several", trusted: "0000,  " + digest + " ,1111", want: true},
		{name: "different digest", trusted: "0000", want: false},
		{name: "empty trust list", trusted: "", want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, certDigestTrusted(tt.trusted, digest))
		})
	}

	assert.False(t, certDigestTrusted(digest, ""), "an empty digest never matches")
}

func TestAppendTrustedCert(t *testing.T) {
	digest := "aa11bb22cc33dd44ee55ff6600778899aabbccddeeff00112233445566778899"

	tests := []struct {
		name    string
		trusted string
		want    string
	}{
		{name: "empty list", trusted: "", want: digest},
		{name: "keeps existing entries", trusted: "0000,1111", want: "0000,1111," + digest},
		{name: "drops blank entries", trusted: " 0000 , ,", want: "0000," + digest},
		{name: "already trusted in another case", trusted: strings.ToUpper(digest), want: strings.ToUpper(digest)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, appendTrustedCert(tt.trusted, digest))
		})
	}
}

func TestWaitForFortinetSAMLSession(t *testing.T) {
	t.Run("keeps waiting when a request carries no session id", func(t *testing.T) {
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		require.NoError(t, err)
		defer listener.Close()

		go func() {
			base := "http://" + listener.Addr().String()
			if resp, err := http.Get(base + "/favicon.ico"); err == nil {
				resp.Body.Close()
			}
			if resp, err := http.Get(base + "/?id=session-42"); err == nil {
				resp.Body.Close()
			}
		}()

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		id, err := waitForFortinetSAMLSession(ctx, listener)
		require.NoError(t, err)
		assert.Equal(t, "session-42", id)
	})

	t.Run("the browser gets the success page before the listener goes away", func(t *testing.T) {
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		require.NoError(t, err)
		defer listener.Close()

		bodies := make(chan string, 1)
		go func() {
			resp, err := http.Get("http://" + listener.Addr().String() + "/?id=session-42")
			if err != nil {
				bodies <- "request failed: " + err.Error()
				return
			}
			defer resp.Body.Close()
			body, err := io.ReadAll(resp.Body)
			if err != nil {
				bodies <- "read failed: " + err.Error()
				return
			}
			bodies <- string(body)
		}()

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		id, err := waitForFortinetSAMLSession(ctx, listener)
		require.NoError(t, err)
		assert.Equal(t, "session-42", id)

		select {
		case body := <-bodies:
			assert.Contains(t, body, "VPN login complete.")
		case <-time.After(5 * time.Second):
			t.Fatal("the browser never received a response")
		}
	})

	t.Run("gives up when the browser login never completes", func(t *testing.T) {
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		require.NoError(t, err)
		defer listener.Close()

		ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
		defer cancel()

		_, err = waitForFortinetSAMLSession(ctx, listener)
		assert.ErrorIs(t, err, context.DeadlineExceeded)
	})
}

func TestBuildFortinetSettings(t *testing.T) {
	const service = "org.freedesktop.NetworkManager.openconnect"

	t.Run("builds a fortinet SAML openconnect profile", func(t *testing.T) {
		settings := buildFortinetSettings(fortinetProfile{
			Host:         "vpn.example.com",
			Port:         10443,
			Username:     "jdoe",
			Realm:        "contractors",
			SAML:         true,
			SAMLPort:     9000,
			TrustedCerts: []string{"aa", "bb"},
		}, "Work VPN", service)

		assert.Equal(t, "Work VPN", settings["connection"]["id"])
		assert.Equal(t, "vpn", settings["connection"]["type"])
		assert.Equal(t, false, settings["connection"]["autoconnect"])
		assert.Equal(t, service, settings["vpn"]["service-type"])

		data, ok := settings["vpn"]["data"].(map[string]string)
		require.True(t, ok)
		assert.Equal(t, "vpn.example.com:10443", data["gateway"])
		assert.Equal(t, "fortinet", data["protocol"])
		assert.Equal(t, "saml", data["authtype"])
		assert.Equal(t, "jdoe", data["username"])
		assert.Equal(t, "contractors", data["usergroup"])
		assert.Equal(t, "9000", data["saml-port"])
		assert.Equal(t, "aa,bb", data["trusted-cert"])

		// The secret agent supplies these at connect time, so NM must not store them.
		assert.Equal(t, "2", data["cookie-flags"])
		assert.Equal(t, "2", data["gateway-flags"])
		assert.Equal(t, "2", data["gwcert-flags"])
	})

	t.Run("brackets an ipv6 gateway", func(t *testing.T) {
		settings := buildFortinetSettings(fortinetProfile{
			Host: "2001:db8::1",
			Port: 10443,
			SAML: true,
		}, "Work VPN", service)

		data := settings["vpn"]["data"].(map[string]string)
		assert.Equal(t, "[2001:db8::1]:10443", data["gateway"])

		host, port, err := splitGatewayHostPort(data["gateway"])
		require.NoError(t, err)
		assert.Equal(t, "2001:db8::1", host)
		assert.Equal(t, 10443, port)
	})

	t.Run("omits optional fields", func(t *testing.T) {
		settings := buildFortinetSettings(fortinetProfile{
			Host: "vpn.example.com",
			Port: 443,
			SAML: true,
		}, "Work VPN", service)

		data := settings["vpn"]["data"].(map[string]string)
		assert.NotContains(t, data, "username")
		assert.NotContains(t, data, "usergroup")
		assert.NotContains(t, data, "saml-port")
		assert.NotContains(t, data, "trusted-cert")
		assert.Equal(t, fortinetSAMLDefaultListenPort, fortinetSAMLListenPort(data))
	})

	t.Run("builds a password profile when SAML is not selected", func(t *testing.T) {
		settings := buildFortinetSettings(fortinetProfile{
			Host:     "vpn.example.com",
			Port:     443,
			Username: "jdoe",
			Password: "hunter2",
		}, "Work VPN", service)

		data := settings["vpn"]["data"].(map[string]string)
		assert.Equal(t, "fortinet", data["protocol"])
		assert.Equal(t, "password", data["authtype"])
		assert.Equal(t, "jdoe", data["username"])
		assert.Equal(t, "openconnect_password", detectVPNAuthAction(service, data))

		assert.NotContains(t, data, "saml-port")
		assert.NotContains(t, data, "cookie-flags")

		// NM only keeps the password when it is not flagged agent-supplied.
		assert.Equal(t, "0", data["password-flags"])
		secrets, ok := settings["vpn"]["secrets"].(map[string]string)
		require.True(t, ok)
		assert.Equal(t, "hunter2", secrets["password"])
	})

	t.Run("leaves the password to the connect prompt when the config had none", func(t *testing.T) {
		settings := buildFortinetSettings(fortinetProfile{
			Host:     "vpn.example.com",
			Port:     443,
			Username: "jdoe",
		}, "Work VPN", service)

		data := settings["vpn"]["data"].(map[string]string)
		assert.Equal(t, "jdoe", data["username"])
		assert.Equal(t, "openconnect_password", detectVPNAuthAction(service, data))

		assert.NotContains(t, data, "password-flags")
		assert.NotContains(t, settings["vpn"], "secrets")
	})
}

func TestExchangeFortinetSAMLSession(t *testing.T) {
	newGateway := func(t *testing.T, handler http.HandlerFunc) (string, int, *x509.Certificate) {
		t.Helper()
		server := httptest.NewTLSServer(handler)
		t.Cleanup(server.Close)

		host, portStr, err := net.SplitHostPort(server.Listener.Addr().String())
		require.NoError(t, err)
		port, err := strconv.Atoi(portStr)
		require.NoError(t, err)

		return host, port, server.Certificate()
	}

	t.Run("returns the SVPNCOOKIE", func(t *testing.T) {
		var gotPath, gotUserAgent string
		host, port, cert := newGateway(t, func(w http.ResponseWriter, r *http.Request) {
			gotPath = r.URL.Path + "?" + r.URL.RawQuery
			gotUserAgent = r.Header.Get("User-Agent")
			http.SetCookie(w, &http.Cookie{Name: "SVPNCOOKIE", Value: "cookie-value"})
			w.WriteHeader(http.StatusOK)
		})

		cookie, err := exchangeFortinetSAMLSession(context.Background(), host, port, "session-42", certificatePin(cert))
		require.NoError(t, err)
		assert.Equal(t, "cookie-value", cookie)
		assert.Equal(t, "/remote/saml/auth_id?id=session-42", gotPath)
		assert.Equal(t, fortinetUserAgent, gotUserAgent)
	})

	t.Run("fails when the gateway sets no cookie", func(t *testing.T) {
		host, port, cert := newGateway(t, func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		})

		_, err := exchangeFortinetSAMLSession(context.Background(), host, port, "session-42", certificatePin(cert))
		assert.ErrorIs(t, err, errFortinetSAMLNoCookie)
	})

	t.Run("fails when the gateway rejects the session", func(t *testing.T) {
		host, port, cert := newGateway(t, func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusForbidden)
		})

		_, err := exchangeFortinetSAMLSession(context.Background(), host, port, "session-42", certificatePin(cert))
		assert.ErrorContains(t, err, "HTTP 403")
	})

	t.Run("refuses a certificate that does not match the pin", func(t *testing.T) {
		host, port, _ := newGateway(t, func(w http.ResponseWriter, r *http.Request) {
			http.SetCookie(w, &http.Cookie{Name: "SVPNCOOKIE", Value: "cookie-value"})
		})

		otherPin := certificatePin(selfSignedCert(t))

		_, err := exchangeFortinetSAMLSession(context.Background(), host, port, "session-42", otherPin)
		assert.ErrorContains(t, err, "does not match the trusted fingerprint")
	})
}

func TestProbeGatewayCert(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer server.Close()

	host, portStr, err := net.SplitHostPort(server.Listener.Addr().String())
	require.NoError(t, err)
	port, err := strconv.Atoi(portStr)
	require.NoError(t, err)

	cert, err := probeGatewayCert(context.Background(), host, port)
	require.NoError(t, err)

	assert.False(t, cert.Verified, "the httptest CA is not in the system trust store")
	assert.Equal(t, certificatePin(server.Certificate()), cert.Pin)
	assert.Equal(t, certificateDigest(server.Certificate()), cert.Digest)
}

func TestCertificateDigestMatchesOpenfortivpnFormat(t *testing.T) {
	assert.Len(t, certificateDigest(selfSignedCert(t)), 64, "digest is a hex sha256, matching openfortivpn trusted-cert")
}

func selfSignedCert(t *testing.T) *x509.Certificate {
	t.Helper()

	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)

	template := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()),
		Subject:      pkix.Name{CommonName: "vpn.example.com"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
	}

	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	require.NoError(t, err)

	cert, err := x509.ParseCertificate(der)
	require.NoError(t, err)
	return cert
}

func TestPinnedTLSConfigWithoutPinVerifiesNormally(t *testing.T) {
	cfg := pinnedTLSConfig("vpn.example.com", "")

	assert.False(t, cfg.InsecureSkipVerify)
	assert.Nil(t, cfg.VerifyPeerCertificate)
	assert.Equal(t, "vpn.example.com", cfg.ServerName)
}

func TestPinnedTLSConfigRejectsUnparsableCertificate(t *testing.T) {
	cfg := pinnedTLSConfig("vpn.example.com", "pin-sha256:whatever")
	require.NotNil(t, cfg.VerifyPeerCertificate)

	assert.Error(t, cfg.VerifyPeerCertificate(nil, nil))
	assert.Error(t, cfg.VerifyPeerCertificate([][]byte{{0x01, 0x02}}, nil))
}

func TestWriteFortinetSAMLPage(t *testing.T) {
	t.Run("the success page closes itself and degrades to a hint", func(t *testing.T) {
		rec := httptest.NewRecorder()
		writeFortinetSAMLPage(rec, "VPN login complete.", true)

		body := rec.Body.String()
		assert.Contains(t, body, "VPN login complete.")
		assert.Contains(t, body, "window.close()")
		assert.Contains(t, body, "You can close this tab.")
		assert.Equal(t, "text/html; charset=utf-8", rec.Header().Get("Content-Type"))
	})

	t.Run("the holding page does not close itself", func(t *testing.T) {
		rec := httptest.NewRecorder()
		writeFortinetSAMLPage(rec, "Waiting for the VPN login to complete.", false)

		body := rec.Body.String()
		assert.Contains(t, body, "Waiting for the VPN login to complete.")
		assert.NotContains(t, body, "window.close()")
	})
}
