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
	"strings"
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
	tmpl := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: cn}, NotBefore: time.Now(), NotAfter: time.Now().Add(time.Hour)}
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

func with(c EnterpriseConfig, f func(*EnterpriseConfig)) EnterpriseConfig {
	f(&c)
	return c
}

type entFiles struct {
	caDER                                         []byte
	ca, cert, p12, key, encKey, legacyKey, notPEM string
}

func newEntFiles(t *testing.T) entFiles {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	require.NoError(t, err)
	blk := func(typ string, h map[string]string) []byte {
		return pem.EncodeToMemory(&pem.Block{Type: typ, Headers: h, Bytes: keyDER})
	}
	der := testCertDER(t, "ca")
	return entFiles{caDER: der,
		ca:        writeTemp(t, "ca.pem", pemCert(der)),
		cert:      writeTemp(t, "client.pem", pemCert(testCertDER(t, "client"))),
		p12:       writeTemp(t, "client.p12", []byte("not-an-x509-pkcs12-blob")),
		key:       writeTemp(t, "plain.key", blk("PRIVATE KEY", nil)),
		encKey:    writeTemp(t, "enc.key", blk("ENCRYPTED PRIVATE KEY", nil)),
		legacyKey: writeTemp(t, "legacy.key", blk("EC PRIVATE KEY", map[string]string{"Proc-Type": "4,ENCRYPTED", "DEK-Info": "AES-128-CBC,00"})),
		notPEM:    writeTemp(t, "bad.pem", []byte("hello"))}
}

var (
	ttlsPAP = EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u", Password: "pw", CA: "none"}
	peapMS  = EnterpriseConfig{EAP: "peap", Phase2: "mschapv2", Identity: "u", Password: "pw", CA: "none"}
	tlsBase = EnterpriseConfig{EAP: "tls", Identity: "u", CA: "none"}
)

func tlsWith(cert, key, pw string) EnterpriseConfig {
	return with(tlsBase, func(c *EnterpriseConfig) { c.ClientCertPath, c.PrivateKeyPath, c.PrivateKeyPassword = cert, key, pw })
}

func caFile(path, pem string) EnterpriseConfig {
	return with(ttlsPAP, func(c *EnterpriseConfig) { c.CA, c.CACertPath, c.CACertPEM = "file", path, pem })
}

func TestEnterprise8021xPatchMethods(t *testing.T) {
	f := newEntFiles(t)
	for name, tt := range map[string]struct {
		cfg  EnterpriseConfig
		want map[string]any
	}{
		"ttls pap file ca exact domain": {with(caFile(f.ca, ""), func(c *EnterpriseConfig) { c.ServerDomain = "radius.example.org" }),
			map[string]any{"eap": []string{"ttls"}, "phase2-auth": "pap", "ca-cert": f.caDER, "system-ca-certs": nil, "domain-match": "radius.example.org", "domain-suffix-match": nil, "password": "pw", "password-flags": uint32(0)}},
		"ask password stores nothing": {with(peapMS, func(c *EnterpriseConfig) { c.AskPassword = true }), map[string]any{"password": nil, "password-flags": uint32(2)}},
		"tls pkcs12 ignores phase 2": {with(tlsWith(f.p12, "", "kp"), func(c *EnterpriseConfig) { c.Phase2 = "eap-mschapv2" }),
			map[string]any{"client-cert": []byte("not-an-x509-pkcs12-blob"), "private-key": []byte("not-an-x509-pkcs12-blob"), "private-key-password": "kp", "password": nil, "phase2-auth": nil, "phase2-autheap": nil}},
	} {
		p, err := enterprise8021xPatch(tt.cfg, true)
		require.NoError(t, err, name)
		for k, v := range tt.want {
			assert.Equal(t, v, p[k], name+" "+k)
		}
	}
}

func TestEnterprise8021xPatchRejects(t *testing.T) {
	f := newEntFiles(t)
	huge := writeTemp(t, "big.p12", make([]byte, maxEnterpriseFileSize+1))
	for name, tt := range map[string]struct {
		cfg   EnterpriseConfig
		field string
	}{
		"system without server":                 {with(peapMS, func(c *EnterpriseConfig) { c.CA = "system" }), "serverDomain"},
		"no password":                           {with(peapMS, func(c *EnterpriseConfig) { c.Password = "" }), "password"},
		"tls without client cert":               {tlsBase, "clientCertPath"},
		"tls x509 without key":                  {tlsWith(f.cert, "", "k"), "privateKeyPath"},
		"pkcs12 without key password":           {tlsWith(f.p12, "", ""), "privateKeyPassword"},
		"legacy encrypted key without password": {tlsWith(f.cert, f.legacyKey, ""), "privateKeyPassword"},
		"pkcs8 encrypted key without password":  {tlsWith(f.cert, f.encKey, ""), "privateKeyPassword"},
		"client cert over size cap":             {tlsWith(huge, "", "k"), "clientCertPath"},
		"ca not a certificate":                  {caFile(f.notPEM, ""), "caCertPath"},
		"missing ca file":                       {caFile("/nonexistent/ca.pem", ""), "/nonexistent/ca.pem"},
		"ca is a directory":                     {caFile(t.TempDir(), ""), "not a regular file"},
		"junk caCertPem":                        {caFile("", "junk"), "not a certificate"},
		"caCertPem over size cap":               {caFile("", strings.Repeat(string(pemCert(f.caDER)), maxEnterpriseFileSize/400+1)), "caCertPem"},
	} {
		_, err := enterprise8021xPatch(tt.cfg, true)
		assert.ErrorContains(t, err, tt.field, name)
	}
}

func TestEnterpriseCABundle(t *testing.T) {
	a, b := testCertDER(t, "a"), testCertDER(t, "b")
	bundle := string(pemCert(a)) + "# comment\n" + string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: []byte{1}})) + string(pemCert(b))
	der := writeTemp(t, "ca.der", a)
	for name, tt := range map[string]struct {
		path, pem string
		want      []byte
	}{
		"bundle keeps only certificates": {"", bundle, append(pemCert(a), pemCert(b)...)},
		"caCertPem wins over caCertPath": {der, string(pemCert(b)), b},
		"DER file":                       {der, "", a},
	} {
		p, err := enterprise8021xPatch(caFile(tt.path, tt.pem), true)
		require.NoError(t, err, name)
		assert.Equal(t, tt.want, p["ca-cert"], name)
	}
}

// Edits only send what the user changed; stored certs, keys and passwords stay.
func TestEnterprise8021xPatchUpdateSafety(t *testing.T) {
	f := newEntFiles(t)
	for name, tt := range map[string]struct {
		cfg        EnterpriseConfig
		has, lacks []string
	}{
		"no password keeps stored":                       {with(peapMS, func(c *EnterpriseConfig) { c.Password = "" }), []string{"password-flags"}, []string{"password"}},
		"file ca without path keeps stored":              {with(peapMS, func(c *EnterpriseConfig) { c.CA = "file" }), []string{"system-ca-certs"}, []string{"ca-cert"}},
		"picked ca replaces ca-path":                     {caFile(f.ca, ""), []string{"ca-cert", "ca-path"}, nil},
		"tls without files keeps both":                   {tlsBase, nil, []string{"client-cert", "private-key"}},
		"tls new x509 cert without key keeps stored key": {tlsWith(f.cert, "", "k"), []string{"client-cert"}, []string{"private-key"}},
		"tls new key keeps stored cert":                  {tlsWith("", f.key, ""), []string{"private-key"}, []string{"client-cert"}},
		"plain key clears stale password":                {tlsWith(f.cert, f.key, "stale"), []string{"private-key-password"}, nil},
		"encrypted key keeps stored password":            {tlsWith(f.cert, f.encKey, ""), nil, []string{"private-key-password"}},
		"pkcs12 keeps stored password":                   {tlsWith(f.p12, "", ""), nil, []string{"private-key-password"}},
	} {
		p, err := enterprise8021xPatch(tt.cfg, false)
		require.NoError(t, err, name)
		for _, k := range tt.has {
			assert.Contains(t, p, k, name)
		}
		for _, k := range tt.lacks {
			assert.NotContains(t, p, k, name)
		}
	}
}

func TestEnterpriseConfigRoundTrip(t *testing.T) {
	f := newEntFiles(t)
	cfg := EnterpriseConfig{EAP: "tls", Identity: "u", CA: "file", CACertPath: f.ca, ClientCertPath: f.cert, PrivateKeyPath: f.key}
	p, err := enterprise8021xPatch(cfg, true)
	require.NoError(t, err)
	x := map[string]dbus.Variant{}
	for k, path := range map[string]string{"ca-cert": cfg.CACertPath, "client-cert": cfg.ClientCertPath, "private-key": cfg.PrivateKeyPath} {
		x[k] = dbus.MakeVariant(append([]byte(certFileScheme+path), 0))
	}
	x["eap"], x["identity"] = dbus.MakeVariant(p["eap"]), dbus.MakeVariant(p["identity"])
	got, ok := enterpriseConfigFromSettings(decodeSettingsForJSON(map[string]map[string]dbus.Variant{"802-1x": x}))
	require.True(t, ok)
	assert.Equal(t, cfg, got)
}

// Profiles that hold blobs or a ca-path decode without a file path, and an edit leaves those keys alone.
func TestEnterpriseBlobProfileSurvivesResave(t *testing.T) {
	v := dbus.MakeVariant
	for name, tt := range map[string]struct {
		eap, ca string
		stored  map[string]dbus.Variant
		lacks   []string
	}{
		"blob ca":      {"peap", "file", map[string]dbus.Variant{"ca-cert": v([]byte{1})}, []string{"ca-cert"}},
		"ca-path only": {"peap", "file", map[string]dbus.Variant{"ca-path": v("/etc/ssl/certs")}, []string{"ca-cert", "ca-path"}},
		"blob tls":     {"tls", "none", map[string]dbus.Variant{"client-cert": v([]byte{1}), "private-key": v([]byte{2})}, []string{"client-cert", "private-key"}},
	} {
		tt.stored["identity"], tt.stored["eap"] = v("u"), v([]string{tt.eap})
		cfg, ok := enterpriseConfigFromSettings(decodeSettingsForJSON(map[string]map[string]dbus.Variant{"802-1x": tt.stored}))
		require.True(t, ok, name)
		assert.Equal(t, tt.ca, cfg.CA, name)
		assert.Empty(t, cfg.CACertPath+cfg.ClientCertPath+cfg.PrivateKeyPath, name)
		cfg.Identity, cfg.Phase2 = "new", "mschapv2"
		p, err := enterprise8021xPatch(cfg, false)
		require.NoError(t, err, name)
		assert.Equal(t, "new", p["identity"], name)
		for _, k := range tt.lacks {
			assert.NotContains(t, p, k, name)
		}
	}
}

// Keys the form doesn't model are kept, unless the choice they belong to changed.
func TestKeepUnmodelledEnterpriseKeys(t *testing.T) {
	stored := map[string]dbus.Variant{
		"system-ca-certs": dbus.MakeVariant(true), "ca-cert": dbus.MakeVariant([]byte{1}),
		"domain-match": dbus.MakeVariant("a.example"), "domain-suffix-match": dbus.MakeVariant("example.org"),
	}
	base := with(peapMS, func(c *EnterpriseConfig) { c.CA, c.ServerDomain = "system", "a.example" })
	for name, tt := range map[string]struct {
		drop string
		cfg  EnterpriseConfig
	}{
		"changed domain drops the other":           {"domain-suffix-match", with(base, func(c *EnterpriseConfig) { c.ServerDomain = "b.example" })},
		"switching away from system drops ca-cert": {"ca-cert", with(base, func(c *EnterpriseConfig) { c.CA = "none" })},
	} {
		p, err := enterprise8021xPatch(tt.cfg, false)
		require.NoError(t, err, name)
		keepUnmodelledEnterpriseKeys(p, stored)
		assert.Contains(t, p, tt.drop, name)
		assert.Nil(t, p[tt.drop], name)
	}
}

func TestEnterpriseUpdatesKeepUnmodelledKeys(t *testing.T) {
	v := dbus.MakeVariant
	f := newEditorFixture(t)
	obj := f.profile(t, "u1", "/s/1")
	s := connSection("u1", "Wired", "802-3-ethernet", nil)
	s["802-1x"] = map[string]dbus.Variant{
		"eap": v([]string{"peap"}), "phase2-auth": v("mschapv2"), "system-ca-certs": v(true),
		"ca-cert": v([]byte{1}), "ca-path": v("/etc/ssl/certs"), "domain-match": v("a.example"), "domain-suffix-match": v("example.org"),
	}
	expectGetSettings(obj, s)
	expectGetSecrets(obj, "802-1x", nmSettings{"802-1x": {"password": v("pw")}})
	got := captureUpdate2(obj, 0, nil)
	patch, err := enterprise8021xPatch(EnterpriseConfig{EAP: "peap", Phase2: "mschapv2", Identity: "u", CA: "system", ServerDomain: "a.example"}, false)
	require.NoError(t, err)
	require.NoError(t, f.backend.UpdateConnectionSettings("u1", SettingsPatch{"802-1x": patch}, false))
	for k, want := range map[string]any{"ca-cert": []byte{1}, "ca-path": "/etc/ssl/certs", "domain-suffix-match": "example.org"} {
		assert.Equal(t, want, (*got)["802-1x"][k].Value(), k)
	}
}
