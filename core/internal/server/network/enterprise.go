package network

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io"
	"os"
	"slices"
	"strings"

	"github.com/godbus/dbus/v5"
)

// EnterpriseConfig is the 802.1X setup as edited in the UI.
type EnterpriseConfig struct {
	EAP                string `json:"eap"`              // peap | ttls | tls | pwd
	Phase2             string `json:"phase2,omitempty"` // eap-mschapv2 maps to phase2-autheap
	Identity           string `json:"identity"`
	Password           string `json:"password,omitempty"`
	AskPassword        bool   `json:"askPassword,omitempty"`
	AnonymousIdentity  string `json:"anonymousIdentity,omitempty"`
	CA                 string `json:"ca"` // file | system | none
	CACertPath         string `json:"caCertPath,omitempty"`
	CACertPEM          string `json:"caCertPem,omitempty"`
	ServerDomain       string `json:"serverDomain,omitempty"` // ";"-separated
	ServerDomainSuffix bool   `json:"serverDomainSuffix,omitempty"`
	ClientCertPath     string `json:"clientCertPath,omitempty"`
	PrivateKeyPath     string `json:"privateKeyPath,omitempty"`
	PrivateKeyPassword string `json:"privateKeyPassword,omitempty"`
	PeapVersion        string `json:"peapVersion,omitempty"` // "" | "0" | "1"
	AuthFlags          uint32 `json:"authFlags,omitempty"`   // phase1-auth-flags
	OpenSSLCiphers     string `json:"opensslCiphers,omitempty"`
}

const (
	maxEnterpriseFileSize = 1 << 20
	secretFlagNotSaved    = uint32(2)
)

var enterpriseManagedKeys = []string{
	"eap", "identity", "anonymous-identity", "password", "password-flags",
	"phase2-auth", "phase2-autheap", "ca-cert", "ca-path", "system-ca-certs",
	"domain-match", "domain-suffix-match", "client-cert", "private-key",
	"private-key-password", "private-key-password-flags", "phase1-peapver",
	"phase1-auth-flags", "openssl-ciphers",
}

var enterprisePhase2 = map[string][]string{
	"peap": {"mschapv2", "gtc", "md5"},
	"ttls": {"pap", "mschap", "mschapv2", "chap", "eap-mschapv2"},
	"tls":  nil,
	"pwd":  nil,
}

// enterprise8021xPatch builds the 802-1x section for cfg. A nil value removes
// the key; an absent key keeps what the profile stores (update only).
func enterprise8021xPatch(cfg EnterpriseConfig, isNew bool) (map[string]any, error) {
	phase2s, ok := enterprisePhase2[cfg.EAP]
	if !ok {
		return nil, fmt.Errorf("eap: unsupported method %q", cfg.EAP)
	}
	if phase2s != nil && !slices.Contains(phase2s, cfg.Phase2) {
		return nil, fmt.Errorf("phase2: %q is not valid for %s", cfg.Phase2, cfg.EAP)
	}
	if cfg.Identity == "" {
		return nil, fmt.Errorf("identity: required")
	}
	if !slices.Contains([]string{"", "0", "1"}, cfg.PeapVersion) {
		return nil, fmt.Errorf("peapVersion: %q is not 0 or 1", cfg.PeapVersion)
	}

	p := make(map[string]any, len(enterpriseManagedKeys))
	for _, k := range enterpriseManagedKeys {
		p[k] = nil
	}
	p["eap"] = []string{cfg.EAP}
	p["identity"] = cfg.Identity
	setIfNonEmpty(p, "anonymous-identity", cfg.AnonymousIdentity)

	switch {
	case phase2s == nil:
	case cfg.Phase2 == "eap-mschapv2":
		p["phase2-autheap"] = "mschapv2"
	default:
		p["phase2-auth"] = cfg.Phase2
	}

	if cfg.EAP == "tls" {
		if err := applyTLSKeys(p, cfg, isNew); err != nil {
			return nil, err
		}
	} else if err := applySecret(p, "password", "password", cfg.Password, cfg.AskPassword, isNew); err != nil {
		return nil, err
	}

	if cfg.EAP != "pwd" {
		if err := applyCAKeys(p, cfg, isNew); err != nil {
			return nil, err
		}
	}

	if cfg.EAP == "peap" {
		setIfNonEmpty(p, "phase1-peapver", cfg.PeapVersion)
	}
	if cfg.AuthFlags != 0 {
		p["phase1-auth-flags"] = cfg.AuthFlags
	}
	setIfNonEmpty(p, "openssl-ciphers", cfg.OpenSSLCiphers)
	return p, nil
}

func setIfNonEmpty(p map[string]any, key, value string) {
	if value != "" {
		p[key] = value
	}
}

// applySecret sets key and key-flags. Flags 2 makes NM ask the agent at every
// activation instead of storing the secret.
func applySecret(p map[string]any, key, field, value string, ask, isNew bool) error {
	switch {
	case ask:
		p[key+"-flags"] = secretFlagNotSaved
	case value != "":
		p[key] = value
		p[key+"-flags"] = uint32(0)
	case isNew:
		return fmt.Errorf("%s: required", field)
	default:
		delete(p, key)
		p[key+"-flags"] = uint32(0)
	}
	return nil
}

func applyTLSKeys(p map[string]any, cfg EnterpriseConfig, isNew bool) error {
	var cert []byte
	switch {
	case cfg.ClientCertPath != "":
		var err error
		if cert, err = readEnterpriseFile("clientCertPath", cfg.ClientCertPath); err != nil {
			return err
		}
		if block, _ := pem.Decode(cert); block != nil && block.Type == "CERTIFICATE" {
			cert = block.Bytes
		}
		p["client-cert"] = cert
	case isNew:
		return fmt.Errorf("clientCertPath: required")
	default:
		delete(p, "client-cert")
	}

	switch {
	case cfg.PrivateKeyPath != "":
		key, err := readEnterpriseFile("privateKeyPath", cfg.PrivateKeyPath)
		if err != nil {
			return err
		}
		p["private-key"] = key
		if isPlainPEMKey(key) {
			p["private-key-password-flags"] = uint32(0)
			return nil
		}
	case cert == nil || (!isNew && isX509(cert)):
		// Keep the stored key.
		delete(p, "private-key")
	case isX509(cert):
		return fmt.Errorf("privateKeyPath: private key required")
	default:
		// PKCS#12 holds the key next to the certificate.
		p["private-key"] = cert
	}
	return applySecret(p, "private-key-password", "privateKeyPassword", cfg.PrivateKeyPassword, cfg.AskPassword, isNew)
}

// isPlainPEMKey reports an unencrypted PEM private key, which NM loads without
// a password.
func isPlainPEMKey(data []byte) bool {
	block, _ := pem.Decode(data)
	return block != nil && block.Type != "ENCRYPTED PRIVATE KEY" &&
		!strings.Contains(block.Headers["Proc-Type"], "ENCRYPTED")
}

func applyCAKeys(p map[string]any, cfg EnterpriseConfig, isNew bool) error {
	switch cfg.CA {
	case "file":
		switch {
		case len(cfg.CACertPEM) > maxEnterpriseFileSize:
			return fmt.Errorf("caCertPem: larger than 1 MiB")
		case cfg.CACertPEM != "":
			ca, err := parseCACerts([]byte(cfg.CACertPEM))
			if err != nil {
				return fmt.Errorf("caCertPem: %w", err)
			}
			p["ca-cert"] = ca
		case cfg.CACertPath != "":
			data, err := readEnterpriseFile("caCertPath", cfg.CACertPath)
			if err != nil {
				return err
			}
			ca, err := parseCACerts(data)
			if err != nil {
				return fmt.Errorf("caCertPath %s: %w", cfg.CACertPath, err)
			}
			p["ca-cert"] = ca
		case isNew:
			return fmt.Errorf("caCertPath: required")
		default:
			// No new CA chosen: keep whatever the profile stores (ca-cert and/or ca-path).
			delete(p, "ca-cert")
			delete(p, "ca-path")
		}
	case "system":
		if cfg.ServerDomain == "" {
			return fmt.Errorf("serverDomain: required with system certificates")
		}
		p["system-ca-certs"] = true
	case "none":
	default:
		return fmt.Errorf("ca: unsupported value %q", cfg.CA)
	}

	if cfg.ServerDomain != "" {
		key := "domain-match"
		if cfg.ServerDomainSuffix {
			key = "domain-suffix-match"
		}
		p[key] = cfg.ServerDomain
	}
	return nil
}

// keepUnmodelledEnterpriseKeys drops delete markers from section for stored
// keys the form can't show, as long as the setting they sit beside is unchanged:
// ca-cert/ca-path next to system-ca-certs, and domain-suffix-match when
// domain-match is also stored.
func keepUnmodelledEnterpriseKeys(section map[string]any, stored map[string]dbus.Variant) {
	del := func(k string) bool { v, ok := section[k]; return ok && v == nil }

	if sys, _ := stored["system-ca-certs"].Value().(bool); sys && section["system-ca-certs"] == true {
		for _, k := range []string{"ca-cert", "ca-path"} {
			if del(k) {
				delete(section, k)
			}
		}
	}
	if d, _ := stored["domain-match"].Value().(string); d != "" && section["domain-match"] == d && del("domain-suffix-match") {
		delete(section, "domain-suffix-match")
	}
}

// parseCACerts returns DER for a single certificate (the blob format NM
// documents) and a PEM bundle for several.
func parseCACerts(data []byte) ([]byte, error) {
	var ders [][]byte
	sawPEM := false
	for rest := data; ; {
		var block *pem.Block
		block, rest = pem.Decode(rest)
		if block == nil {
			break
		}
		sawPEM = true
		if block.Type == "CERTIFICATE" {
			ders = append(ders, block.Bytes)
		}
	}
	if !sawPEM {
		ders = [][]byte{data}
	}
	if len(ders) == 0 {
		return nil, fmt.Errorf("not a certificate")
	}
	for _, der := range ders {
		if !isX509(der) {
			return nil, fmt.Errorf("not a certificate")
		}
	}
	if len(ders) == 1 {
		return ders[0], nil
	}
	var bundle []byte
	for _, der := range ders {
		bundle = append(bundle, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})...)
	}
	return bundle, nil
}

func isX509(der []byte) bool {
	_, err := x509.ParseCertificate(der)
	return err == nil
}

func readEnterpriseFile(field, path string) ([]byte, error) {
	// Stat before opening: opening a FIFO blocks until a writer appears.
	if fi, err := os.Stat(path); err != nil {
		return nil, fmt.Errorf("%s: %w", field, err)
	} else if !fi.Mode().IsRegular() {
		return nil, fmt.Errorf("%s %s: not a regular file", field, path)
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", field, err)
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, maxEnterpriseFileSize+1))
	if err != nil {
		return nil, fmt.Errorf("%s: %w", field, err)
	}
	if len(data) > maxEnterpriseFileSize {
		return nil, fmt.Errorf("%s %s: larger than 1 MiB", field, path)
	}
	return data, nil
}

// enterpriseConfigFromSettings rebuilds the form config from decoded profile
// settings (decodeSettingsForJSON output). Passwords are never included, and
// stored certificates ("blob") come back with an empty path.
func enterpriseConfigFromSettings(s map[string]map[string]any) (EnterpriseConfig, bool) {
	x, ok := s["802-1x"]
	if !ok {
		return EnterpriseConfig{}, false
	}
	str := func(k string) string { v, _ := x[k].(string); return v }
	flags := func(k string) uint32 { v, _ := x[k].(uint32); return v }
	path := func(k string) string {
		if v := str(k); v != certBlobToken {
			return v
		}
		return ""
	}

	var cfg EnterpriseConfig
	if eap, _ := x["eap"].([]string); len(eap) > 0 {
		cfg.EAP = eap[0]
	}
	cfg.Phase2 = str("phase2-auth")
	if cfg.EAP == "ttls" && str("phase2-autheap") == "mschapv2" {
		cfg.Phase2 = "eap-mschapv2"
	}
	cfg.Identity = str("identity")
	cfg.AnonymousIdentity = str("anonymous-identity")

	secretFlags := "password-flags"
	if cfg.EAP == "tls" {
		secretFlags = "private-key-password-flags"
	}
	cfg.AskPassword = flags(secretFlags)&secretFlagNotSaved != 0

	switch sys, _ := x["system-ca-certs"].(bool); {
	case sys:
		cfg.CA = "system"
	case str("ca-cert") != "":
		cfg.CA = "file"
		cfg.CACertPath = path("ca-cert")
	case str("ca-path") != "":
		cfg.CA = "file"
	default:
		cfg.CA = "none"
	}
	if d := str("domain-match"); d != "" {
		cfg.ServerDomain = d
	} else if d := str("domain-suffix-match"); d != "" {
		cfg.ServerDomain, cfg.ServerDomainSuffix = d, true
	}

	cfg.ClientCertPath = path("client-cert")
	cfg.PrivateKeyPath = path("private-key")
	cfg.PeapVersion = str("phase1-peapver")
	cfg.AuthFlags = flags("phase1-auth-flags")
	cfg.OpenSSLCiphers = str("openssl-ciphers")
	return cfg, true
}
