package network

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func testCertDER(t *testing.T, cn string) []byte {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: cn},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(time.Hour),
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	require.NoError(t, err)
	return der
}

func pemCert(der []byte) []byte {
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
}

func writeTemp(t *testing.T, name string, data []byte) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), name)
	require.NoError(t, os.WriteFile(p, data, 0o600))
	return p
}

func assertManagedOnly(t *testing.T, p map[string]any, isNew bool) {
	t.Helper()
	for k := range p {
		assert.True(t, slices.Contains(enterpriseManagedKeys, k), "unmanaged key %s", k)
	}
	if isNew {
		for _, k := range enterpriseManagedKeys {
			assert.Contains(t, p, k)
		}
	}
	assert.Nil(t, p["ca-path"])
}

func TestEnterprise8021xPatchMethods(t *testing.T) {
	caDER := testCertDER(t, "ca")
	caPath := writeTemp(t, "ca.pem", pemCert(caDER))
	p12 := []byte("not-an-x509-pkcs12-blob")
	p12Path := writeTemp(t, "client.p12", p12)

	tests := []struct {
		name  string
		cfg   EnterpriseConfig
		check func(t *testing.T, p map[string]any)
	}{
		{
			name: "ttls pap ca file exact domain",
			cfg: EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "pw",
				CA: "file", CACertPath: caPath, ServerDomain: "radius.example.org"},
			check: func(t *testing.T, p map[string]any) {
				assert.Equal(t, []string{"ttls"}, p["eap"])
				assert.Equal(t, "pap", p["phase2-auth"])
				assert.Nil(t, p["phase2-autheap"])
				assert.Equal(t, caDER, p["ca-cert"])
				assert.Nil(t, p["system-ca-certs"])
				assert.Equal(t, "radius.example.org", p["domain-match"])
				assert.Nil(t, p["domain-suffix-match"])
				assert.Equal(t, "pw", p["password"])
				assert.Equal(t, uint32(0), p["password-flags"])
				assert.Nil(t, p["client-cert"])
			},
		},
		{
			name: "ttls eap-mschapv2",
			cfg:  EnterpriseConfig{EAP: "ttls", Phase2: "eap-mschapv2", Identity: "u", Password: "pw", CA: "none"},
			check: func(t *testing.T, p map[string]any) {
				assert.Equal(t, "mschapv2", p["phase2-autheap"])
				assert.Nil(t, p["phase2-auth"])
				assert.Nil(t, p["ca-cert"])
				assert.Nil(t, p["system-ca-certs"])
			},
		},
		{
			name: "peap gtc system ca suffix",
			cfg: EnterpriseConfig{EAP: "peap", Phase2: "gtc", Identity: "u", Password: "pw",
				CA: "system", ServerDomain: "example.org", ServerDomainSuffix: true,
				PeapVersion: "1", AuthFlags: 0x10, OpenSSLCiphers: "DEFAULT@SECLEVEL=0"},
			check: func(t *testing.T, p map[string]any) {
				assert.Equal(t, "gtc", p["phase2-auth"])
				assert.Equal(t, true, p["system-ca-certs"])
				assert.Nil(t, p["ca-cert"])
				assert.Equal(t, "example.org", p["domain-suffix-match"])
				assert.Nil(t, p["domain-match"])
				assert.Equal(t, "1", p["phase1-peapver"])
				assert.Equal(t, uint32(0x10), p["phase1-auth-flags"])
				assert.Equal(t, "DEFAULT@SECLEVEL=0", p["openssl-ciphers"])
			},
		},
		{
			name: "tls pkcs12 without key path",
			cfg: EnterpriseConfig{EAP: "tls", Identity: "u", CA: "none",
				ClientCertPath: p12Path, PrivateKeyPassword: "kp"},
			check: func(t *testing.T, p map[string]any) {
				assert.Equal(t, p12, p["client-cert"])
				assert.Equal(t, p["client-cert"], p["private-key"])
				assert.Equal(t, "kp", p["private-key-password"])
				assert.Equal(t, uint32(0), p["private-key-password-flags"])
				assert.Nil(t, p["password"])
				assert.Nil(t, p["password-flags"])
				assert.Nil(t, p["phase2-auth"])
			},
		},
		{
			name: "pwd clears ca and domain",
			cfg: EnterpriseConfig{EAP: "pwd", Identity: "u", Password: "pw",
				CA: "system", ServerDomain: "example.org", PeapVersion: "0"},
			check: func(t *testing.T, p map[string]any) {
				assert.Equal(t, []string{"pwd"}, p["eap"])
				assert.Nil(t, p["system-ca-certs"])
				assert.Nil(t, p["domain-match"])
				assert.Nil(t, p["phase1-peapver"])
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p, err := enterprise8021xPatch(tt.cfg, true)
			require.NoError(t, err)
			assertManagedOnly(t, p, true)
			tt.check(t, p)
		})
	}
}

func TestEnterprise8021xPatchUpdateSafety(t *testing.T) {
	base := EnterpriseConfig{EAP: "peap", Phase2: "mschapv2", Identity: "u", CA: "none"}

	p, err := enterprise8021xPatch(base, false)
	require.NoError(t, err)
	assertManagedOnly(t, p, false)
	assert.NotContains(t, p, "password")
	assert.Equal(t, uint32(0), p["password-flags"])

	_, err = enterprise8021xPatch(base, true)
	assert.ErrorContains(t, err, "password")

	ask := base
	ask.AskPassword = true
	ask.Password = "ignored"
	p, err = enterprise8021xPatch(ask, true)
	require.NoError(t, err)
	assert.Contains(t, p, "password")
	assert.Nil(t, p["password"])
	assert.Equal(t, uint32(2), p["password-flags"])

	file := base
	file.Password = "pw"
	file.CA = "file"
	p, err = enterprise8021xPatch(file, false)
	require.NoError(t, err)
	assert.NotContains(t, p, "ca-cert")
	assert.Contains(t, p, "system-ca-certs")
	assert.Nil(t, p["system-ca-certs"])

	_, err = enterprise8021xPatch(file, true)
	assert.ErrorContains(t, err, "caCertPath")

	tls := EnterpriseConfig{EAP: "tls", Identity: "u", CA: "none", PrivateKeyPassword: "k",
		ClientCertPath: writeTemp(t, "client.pem", pemCert(testCertDER(t, "client")))}
	p, err = enterprise8021xPatch(tls, false)
	require.NoError(t, err)
	assert.Contains(t, p, "client-cert")
	assert.NotContains(t, p, "private-key", "edit keeps the stored key")
}

func TestEnterprise8021xPatchRejects(t *testing.T) {
	x509PEM := writeTemp(t, "client.pem", pemCert(testCertDER(t, "client")))
	notCert := writeTemp(t, "ca.pem", []byte("hello"))

	tests := []struct {
		name  string
		cfg   EnterpriseConfig
		field string
	}{
		{"system without server", EnterpriseConfig{EAP: "peap", Phase2: "mschapv2", Identity: "u", Password: "p", CA: "system"}, "serverDomain"},
		{"empty ca", EnterpriseConfig{EAP: "peap", Phase2: "mschapv2", Identity: "u", Password: "p"}, "ca"},
		{"ttls gtc", EnterpriseConfig{EAP: "ttls", Phase2: "gtc", Identity: "u", Password: "p", CA: "none"}, "phase2"},
		{"tls x509 without key", EnterpriseConfig{EAP: "tls", Identity: "u", CA: "none", ClientCertPath: x509PEM, PrivateKeyPassword: "k"}, "privateKeyPath"},
		{"ca not a certificate", EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "p", CA: "file", CACertPath: notCert}, "caCertPath"},
		{"bad eap", EnterpriseConfig{EAP: "leap", Identity: "u", Password: "p", CA: "none"}, "eap"},
		{"no identity", EnterpriseConfig{EAP: "pwd", Password: "p"}, "identity"},
		{"tls without client cert", EnterpriseConfig{EAP: "tls", Identity: "u", CA: "none"}, "clientCertPath"},
		{"missing ca file", EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "p", CA: "file", CACertPath: "/nonexistent/ca.pem"}, "/nonexistent/ca.pem"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := enterprise8021xPatch(tt.cfg, true)
			require.Error(t, err)
			assert.Contains(t, err.Error(), tt.field)
		})
	}

	_, err := enterprise8021xPatch(EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "p", CA: "file", CACertPEM: "junk"}, true)
	assert.ErrorContains(t, err, "not a certificate")
}

func TestEnterpriseCABundle(t *testing.T) {
	a, b := testCertDER(t, "a"), testCertDER(t, "b")
	bundle := append(pemCert(a), []byte("# comment\n")...)
	bundle = append(bundle, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: []byte{1}})...)
	bundle = append(bundle, pemCert(b)...)

	p, err := enterprise8021xPatch(EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "p",
		CA: "file", CACertPEM: string(bundle)}, true)
	require.NoError(t, err)
	assert.Equal(t, append(pemCert(a), pemCert(b)...), p["ca-cert"])

	der := writeTemp(t, "ca.der", a)
	p, err = enterprise8021xPatch(EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "p",
		CA: "file", CACertPath: der, CACertPEM: string(pemCert(b))}, true)
	require.NoError(t, err)
	assert.Equal(t, b, p["ca-cert"], "caCertPem wins over caCertPath")

	p, err = enterprise8021xPatch(EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "p",
		CA: "file", CACertPath: der}, true)
	require.NoError(t, err)
	assert.Equal(t, a, p["ca-cert"])
}

func TestEnterpriseFileCap(t *testing.T) {
	huge := writeTemp(t, "big.p12", make([]byte, maxEnterpriseFileSize+1))
	_, err := enterprise8021xPatch(EnterpriseConfig{EAP: "tls", Identity: "u", CA: "none",
		ClientCertPath: huge, PrivateKeyPassword: "k"}, true)
	assert.ErrorContains(t, err, "clientCertPath")
}

func plainKeyPEM(t *testing.T) []byte {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)
	der, err := x509.MarshalPKCS8PrivateKey(key)
	require.NoError(t, err)
	return pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
}

func TestEnterpriseTLSPrivateKeyPassword(t *testing.T) {
	certPath := writeTemp(t, "client.pem", pemCert(testCertDER(t, "client")))
	plainPath := writeTemp(t, "plain.key", plainKeyPEM(t))
	legacyEnc := writeTemp(t, "legacy.key", pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY",
		Headers: map[string]string{"Proc-Type": "4,ENCRYPTED", "DEK-Info": "AES-128-CBC,00"}, Bytes: []byte{1}}))
	pkcs8Enc := writeTemp(t, "enc.key", pem.EncodeToMemory(&pem.Block{Type: "ENCRYPTED PRIVATE KEY", Bytes: []byte{1}}))
	p12Path := writeTemp(t, "client.p12", []byte("not-an-x509-pkcs12-blob"))
	tls := func(cert, key string) EnterpriseConfig {
		return EnterpriseConfig{EAP: "tls", Identity: "u", CA: "none", ClientCertPath: cert, PrivateKeyPath: key}
	}

	for _, isNew := range []bool{true, false} {
		cfg := tls(certPath, plainPath)
		if !isNew {
			cfg.PrivateKeyPassword = "stale"
		}
		p, err := enterprise8021xPatch(cfg, isNew)
		require.NoError(t, err, "plain PEM key needs no password (isNew=%v)", isNew)
		assert.Contains(t, p, "private-key-password")
		assert.Nil(t, p["private-key-password"])
		assert.Equal(t, uint32(0), p["private-key-password-flags"])
	}

	for name, cfg := range map[string]EnterpriseConfig{
		"pkcs12":           tls(p12Path, ""),
		"legacy encrypted": tls(certPath, legacyEnc),
		"pkcs8 encrypted":  tls(certPath, pkcs8Enc),
	} {
		_, err := enterprise8021xPatch(cfg, true)
		assert.ErrorContains(t, err, "privateKeyPassword", name)

		p, err := enterprise8021xPatch(cfg, false)
		require.NoError(t, err, name)
		assert.NotContains(t, p, "private-key-password", "update keeps the stored key password (%s)", name)
		assert.Equal(t, uint32(0), p["private-key-password-flags"])

		cfg.AskPassword = true
		cfg.PrivateKeyPassword = "ignored"
		p, err = enterprise8021xPatch(cfg, true)
		require.NoError(t, err, name)
		assert.Contains(t, p, "private-key-password")
		assert.Nil(t, p["private-key-password"])
		assert.Equal(t, uint32(2), p["private-key-password-flags"])
	}
}

func TestEnterprisePhase2IgnoredForTLSAndPWD(t *testing.T) {
	p12Path := writeTemp(t, "client.p12", []byte("not-an-x509-pkcs12-blob"))
	for _, cfg := range []EnterpriseConfig{
		{EAP: "tls", Phase2: "eap-mschapv2", Identity: "u", CA: "none", ClientCertPath: p12Path, PrivateKeyPassword: "k"},
		{EAP: "pwd", Phase2: "eap-mschapv2", Identity: "u", Password: "p"},
		{EAP: "pwd", Phase2: "pap", Identity: "u", Password: "p"},
	} {
		p, err := enterprise8021xPatch(cfg, true)
		require.NoError(t, err)
		assert.Nil(t, p["phase2-auth"], cfg.EAP)
		assert.Nil(t, p["phase2-autheap"], cfg.EAP)
	}
}

func TestEnterpriseFileMustBeRegular(t *testing.T) {
	fifo := filepath.Join(t.TempDir(), "fifo")
	require.NoError(t, syscall.Mkfifo(fifo, 0o600))
	_, err := enterprise8021xPatch(EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "p",
		CA: "file", CACertPath: fifo}, true)
	assert.ErrorContains(t, err, "caCertPath")

	_, err = enterprise8021xPatch(EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "p",
		CA: "file", CACertPath: t.TempDir()}, true)
	assert.ErrorContains(t, err, "caCertPath")
}

func TestEnterpriseCACertPEMCap(t *testing.T) {
	big := strings.Repeat(string(pemCert(testCertDER(t, "ca"))), maxEnterpriseFileSize/400+1)
	require.Greater(t, len(big), maxEnterpriseFileSize)
	_, err := enterprise8021xPatch(EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "p",
		CA: "file", CACertPEM: big}, true)
	assert.ErrorContains(t, err, "caCertPem")
}

// storedAs mimics a saved profile: a patch's values as variants, with files
// stored by path the way the editor leaves them, then decoded for JSON.
func storedAs(t *testing.T, p map[string]any, paths map[string]string) map[string]map[string]any {
	t.Helper()
	x := map[string]dbus.Variant{}
	for k, v := range p {
		if v == nil {
			continue
		}
		if path, ok := paths[k]; ok {
			v = append([]byte(certFileScheme+path), 0)
		}
		x[k] = dbus.MakeVariant(v)
	}
	return decodeSettingsForJSON(map[string]map[string]dbus.Variant{"802-1x": x})
}

func TestEnterpriseConfigRoundTrip(t *testing.T) {
	ca := writeTemp(t, "ca.pem", pemCert(testCertDER(t, "ca")))
	cert := writeTemp(t, "c.pem", pemCert(testCertDER(t, "client")))
	key := writeTemp(t, "k.pem", plainKeyPEM(t))

	cases := map[string]EnterpriseConfig{
		"ttls pap file ca exact domain": {EAP: "ttls", Phase2: "pap", Identity: "u", AnonymousIdentity: "anon", CA: "file", CACertPath: ca, ServerDomain: "a.example;b.example"},
		"peap system ca suffix":         {EAP: "peap", Phase2: "mschapv2", Identity: "u", CA: "system", ServerDomain: "example.org", ServerDomainSuffix: true, PeapVersion: "1", OpenSSLCiphers: "DEFAULT@SECLEVEL=0"},
		"ttls eap-mschapv2 ask":         {EAP: "ttls", Phase2: "eap-mschapv2", Identity: "u", AskPassword: true, CA: "none"},
		"tls paths":                     {EAP: "tls", Identity: "u", CA: "file", CACertPath: ca, ClientCertPath: cert, PrivateKeyPath: key},
		"auth flags":                    {EAP: "peap", Phase2: "gtc", Identity: "u", CA: "none", AuthFlags: 0x8 | 0x10, Password: "dropped"},
	}
	for name, cfg := range cases {
		t.Run(name, func(t *testing.T) {
			if !cfg.AskPassword && cfg.EAP != "tls" {
				cfg.Password = "pw"
			}
			p, err := enterprise8021xPatch(cfg, true)
			require.NoError(t, err)
			got, ok := enterpriseConfigFromSettings(storedAs(t, p, map[string]string{
				"ca-cert": cfg.CACertPath, "client-cert": cfg.ClientCertPath, "private-key": cfg.PrivateKeyPath,
			}))
			require.True(t, ok)
			cfg.Password = ""
			assert.Equal(t, cfg, got)
		})
	}

	_, ok := enterpriseConfigFromSettings(map[string]map[string]any{"ipv4": {}})
	assert.False(t, ok)
}

func TestEnterpriseBlobCAKeepsStoredOnUpdate(t *testing.T) {
	cert := testCertDER(t, "ca")
	p, err := enterprise8021xPatch(EnterpriseConfig{EAP: "peap", Phase2: "mschapv2", Identity: "u", Password: "pw", CA: "file", CACertPath: writeTemp(t, "ca.pem", pemCert(cert))}, true)
	require.NoError(t, err)

	got, ok := enterpriseConfigFromSettings(storedAs(t, p, nil))
	require.True(t, ok)
	assert.Equal(t, "file", got.CA)
	assert.Empty(t, got.CACertPath)

	got.Identity = "new"
	p, err = enterprise8021xPatch(got, false)
	require.NoError(t, err)
	assert.NotContains(t, p, "ca-cert")
	assert.Equal(t, "new", p["identity"])
}

func TestEnterpriseTLSUpdateKeepsStoredFiles(t *testing.T) {
	cfg := EnterpriseConfig{EAP: "tls", Identity: "u", CA: "none"}

	p, err := enterprise8021xPatch(cfg, false)
	require.NoError(t, err)
	assert.NotContains(t, p, "client-cert")
	assert.NotContains(t, p, "private-key")

	_, err = enterprise8021xPatch(cfg, true)
	assert.ErrorContains(t, err, "clientCertPath")

	cfg.PrivateKeyPath = writeTemp(t, "k.pem", plainKeyPEM(t))
	p, err = enterprise8021xPatch(cfg, false)
	require.NoError(t, err)
	assert.NotContains(t, p, "client-cert")
	assert.Contains(t, p, "private-key")
}

func TestEnterpriseCAPathOnlyProfileSurvivesResave(t *testing.T) {
	stored := map[string]dbus.Variant{
		"eap": dbus.MakeVariant([]string{"peap"}), "identity": dbus.MakeVariant("u"),
		"phase2-auth": dbus.MakeVariant("mschapv2"), "ca-path": dbus.MakeVariant("/etc/ssl/certs"),
	}
	cfg, ok := enterpriseConfigFromSettings(decodeSettingsForJSON(map[string]map[string]dbus.Variant{"802-1x": stored}))
	require.True(t, ok)
	assert.Equal(t, "file", cfg.CA)
	assert.Empty(t, cfg.CACertPath)

	p, err := enterprise8021xPatch(cfg, false)
	require.NoError(t, err)
	assert.NotContains(t, p, "ca-cert")
	assert.NotContains(t, p, "ca-path")

	cfg.CACertPath = writeTemp(t, "ca.pem", pemCert(testCertDER(t, "ca")))
	p, err = enterprise8021xPatch(cfg, false)
	require.NoError(t, err)
	assert.NotNil(t, p["ca-cert"])
	assert.Contains(t, p, "ca-path", "a newly picked CA replaces ca-path")
	assert.Nil(t, p["ca-path"])
}

func TestKeepUnmodelledEnterpriseKeys(t *testing.T) {
	stored := map[string]dbus.Variant{
		"system-ca-certs": dbus.MakeVariant(true), "ca-cert": dbus.MakeVariant([]byte{1}),
		"domain-match": dbus.MakeVariant("a.example"), "domain-suffix-match": dbus.MakeVariant("example.org"),
	}
	base := EnterpriseConfig{EAP: "peap", Phase2: "mschapv2", Identity: "u", CA: "system", ServerDomain: "a.example"}

	t.Run("unchanged keeps both", func(t *testing.T) {
		p, err := enterprise8021xPatch(base, false)
		require.NoError(t, err)
		keepUnmodelledEnterpriseKeys(p, stored)
		assert.NotContains(t, p, "ca-cert")
		assert.NotContains(t, p, "ca-path")
		assert.NotContains(t, p, "domain-suffix-match")
	})

	t.Run("changed domain drops the other", func(t *testing.T) {
		cfg := base
		cfg.ServerDomain = "b.example"
		p, err := enterprise8021xPatch(cfg, false)
		require.NoError(t, err)
		keepUnmodelledEnterpriseKeys(p, stored)
		assert.Contains(t, p, "domain-suffix-match")
		assert.Nil(t, p["domain-suffix-match"])
	})

	t.Run("switching away from system drops ca-cert", func(t *testing.T) {
		cfg := base
		cfg.CA = "none"
		p, err := enterprise8021xPatch(cfg, false)
		require.NoError(t, err)
		keepUnmodelledEnterpriseKeys(p, stored)
		assert.Contains(t, p, "ca-cert")
		assert.Nil(t, p["ca-cert"])
	})
}

func TestEnterpriseUpdatesKeepUnmodelledKeys(t *testing.T) {
	peap := func(extra map[string]dbus.Variant) map[string]dbus.Variant {
		s := map[string]dbus.Variant{
			"eap":         dbus.MakeVariant([]string{"peap"}),
			"phase2-auth": dbus.MakeVariant("mschapv2"),
			"identity":    dbus.MakeVariant("u"),
		}
		for k, v := range extra {
			s[k] = v
		}
		return s
	}
	cfg := EnterpriseConfig{EAP: "peap", Phase2: "mschapv2", Identity: "u"}
	cases := map[string]struct {
		stored map[string]dbus.Variant
		ca     string
		domain string
		keep   map[string]any
	}{
		"system CA keeps ca-cert and ca-path": {
			stored: peap(map[string]dbus.Variant{
				"system-ca-certs": dbus.MakeVariant(true),
				"ca-cert":         dbus.MakeVariant([]byte{1}),
				"ca-path":         dbus.MakeVariant("/etc/ssl/certs"),
				"domain-match":    dbus.MakeVariant("a.example"),
			}),
			ca: "system", domain: "a.example",
			keep: map[string]any{"ca-cert": []byte{1}, "ca-path": "/etc/ssl/certs"},
		},
		"domain-match keeps domain-suffix-match": {
			stored: peap(map[string]dbus.Variant{
				"domain-match":        dbus.MakeVariant("a.example"),
				"domain-suffix-match": dbus.MakeVariant("example.org"),
			}),
			ca: "none", domain: "a.example",
			keep: map[string]any{"domain-suffix-match": "example.org"},
		},
		"ca-path only keeps ca-path": {
			stored: peap(map[string]dbus.Variant{"ca-path": dbus.MakeVariant("/etc/ssl/certs")}),
			ca:     "file",
			keep:   map[string]any{"ca-path": "/etc/ssl/certs"},
		},
	}

	assertKept := func(t *testing.T, got nmSettings, keep map[string]any) {
		t.Helper()
		for k, v := range keep {
			assert.Equal(t, v, got["802-1x"][k].Value(), k)
		}
	}

	for name, tc := range cases {
		c := cfg
		c.CA, c.ServerDomain = tc.ca, tc.domain

		t.Run(name+" via editor", func(t *testing.T) {
			f := newEditorFixture(t)
			obj := f.profile(t, "u1", "/s/1")
			s := connSection("u1", "Wired", "802-3-ethernet", nil)
			s["802-1x"] = tc.stored
			expectGetSettings(obj, s)
			expectGetSecrets(obj, "802-1x", nmSettings{"802-1x": {"password": dbus.MakeVariant("pw")}})
			got := captureUpdate2(obj, 0, nil)

			patch, err := enterprise8021xPatch(c, false)
			require.NoError(t, err)
			require.NoError(t, f.backend.UpdateConnectionSettings("u1", SettingsPatch{"802-1x": patch}, false))
			assertKept(t, *got, tc.keep)
		})

		t.Run(name+" via wifi credentials", func(t *testing.T) {
			backend, conn, obj := wifiWriteFixture(t)
			expectGetSettings(obj, nmSettings{
				"802-11-wireless-security": {"key-mgmt": dbus.MakeVariant("wpa-eap")},
				"802-1x":                   tc.stored,
			})
			expectGetSecrets(obj, "802-11-wireless-security", nmSettings{})
			expectGetSecrets(obj, "802-1x", nmSettings{"802-1x": {"password": dbus.MakeVariant("pw")}})
			got := captureUpdate2(obj, nmUpdate2FlagToDisk, nil)

			require.NoError(t, updateConnectionCredentials(backend, conn, ConnectionRequest{SSID: "home", Enterprise: &c}))
			assertKept(t, *got, tc.keep)
		})
	}
}

func TestEnterpriseTLSAskPasswordRoundTrip(t *testing.T) {
	cert := writeTemp(t, "c.pem", pemCert(testCertDER(t, "client")))
	key := writeTemp(t, "k.pem", []byte("-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----END ENCRYPTED PRIVATE KEY-----\n"))
	cfg := EnterpriseConfig{EAP: "tls", Identity: "u", CA: "none", AskPassword: true, ClientCertPath: cert, PrivateKeyPath: key}

	p, err := enterprise8021xPatch(cfg, true)
	require.NoError(t, err)
	assert.Equal(t, secretFlagNotSaved, p["private-key-password-flags"])

	got, ok := enterpriseConfigFromSettings(storedAs(t, p, map[string]string{"client-cert": cert, "private-key": key}))
	require.True(t, ok)
	assert.True(t, got.AskPassword)
	assert.Equal(t, cfg, got)
}

func TestEnterpriseBlobTLSDecodeUpdateKeepsFiles(t *testing.T) {
	x := map[string]dbus.Variant{
		"eap": dbus.MakeVariant([]string{"tls"}), "identity": dbus.MakeVariant("u"),
		"client-cert":                dbus.MakeVariant([]byte{1, 2, 3}),
		"private-key":                dbus.MakeVariant([]byte{4, 5, 6}),
		"private-key-password-flags": dbus.MakeVariant(uint32(0)),
	}
	cfg, ok := enterpriseConfigFromSettings(decodeSettingsForJSON(map[string]map[string]dbus.Variant{"802-1x": x}))
	require.True(t, ok)
	assert.Empty(t, cfg.ClientCertPath)
	assert.Empty(t, cfg.PrivateKeyPath)

	cfg.Identity = "new"
	p, err := enterprise8021xPatch(cfg, false)
	require.NoError(t, err)
	assert.NotContains(t, p, "client-cert")
	assert.NotContains(t, p, "private-key")
	assert.Equal(t, "new", p["identity"])
}
