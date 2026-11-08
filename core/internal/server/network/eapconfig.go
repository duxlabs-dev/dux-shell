package network

import (
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"encoding/xml"
	"fmt"
	"slices"
	"strconv"
	"strings"
)

// EAPConfigProfile is the part of an eduroam CAT ".eap-config" file the
// 802.1X form can use.
type EAPConfigProfile struct {
	ProviderName   string           `json:"providerName"`
	SSIDs          []string         `json:"ssids"`
	UsernameSuffix string           `json:"usernameSuffix,omitempty"`
	UsernameHint   bool             `json:"usernameHint"`
	Enterprise     EnterpriseConfig `json:"enterprise"`
}

type eapXMLFile struct {
	Providers []eapXMLProvider `xml:"EAPIdentityProvider"`
}

type eapXMLProvider struct {
	ID          string         `xml:"ID,attr"`
	Methods     []eapXMLMethod `xml:"AuthenticationMethods>AuthenticationMethod"`
	Networks    []eapXMLWifi   `xml:"CredentialApplicability>IEEE80211"`
	DisplayName []string       `xml:"ProviderInfo>DisplayName"`
}

type eapXMLWifi struct {
	SSID string `xml:"SSID"`
}

type eapXMLMethod struct {
	Type    int      `xml:"EAPMethod>Type"`
	CAs     []string `xml:"ServerSideCredential>CA"`
	Servers []string `xml:"ServerSideCredential>ServerID"`
	Outer   string   `xml:"ClientSideCredential>OuterIdentity"`
	Suffix  string   `xml:"ClientSideCredential>InnerIdentitySuffix"`
	Hint    string   `xml:"ClientSideCredential>InnerIdentityHint"`
	Inner   []struct {
		EAP    string `xml:"EAPMethod>Type"`
		NonEAP string `xml:"NonEAPAuthMethod>Type"`
	} `xml:"InnerAuthenticationMethod"`
}

var (
	eapTTLSInnerNonEAP = map[string]string{"1": "pap", "2": "mschap", "3": "mschapv2"}
	eapPEAPInnerEAP    = map[string]string{"26": "mschapv2", "6": "gtc", "4": "md5"}
)

// parseEAPConfig reads the first provider and its first authentication
// method that the form supports.
func parseEAPConfig(data []byte) (EAPConfigProfile, error) {
	var f eapXMLFile
	if err := xml.Unmarshal(data, &f); err != nil {
		return EAPConfigProfile{}, fmt.Errorf("invalid .eap-config: %w", err)
	}
	if len(f.Providers) == 0 {
		return EAPConfigProfile{}, fmt.Errorf("invalid .eap-config: no EAPIdentityProvider")
	}
	prov := f.Providers[0]

	var ssids []string
	for _, n := range prov.Networks {
		if s := strings.TrimSpace(n.SSID); s != "" && !slices.Contains(ssids, s) {
			ssids = append(ssids, s)
		}
	}

	var found []string
	for _, m := range prov.Methods {
		found = append(found, strconv.Itoa(m.Type))
		cfg, ok := m.enterprise()
		if !ok {
			continue
		}
		if len(ssids) == 0 {
			return EAPConfigProfile{}, fmt.Errorf("profile has no Wi-Fi network name (Passpoint-only profiles are not supported)")
		}
		if err := m.applyServer(&cfg); err != nil {
			return EAPConfigProfile{}, err
		}
		name := prov.ID
		if len(prov.DisplayName) > 0 && strings.TrimSpace(prov.DisplayName[0]) != "" {
			name = strings.TrimSpace(prov.DisplayName[0])
		}
		return EAPConfigProfile{
			ProviderName:   name,
			SSIDs:          ssids,
			UsernameSuffix: strings.TrimSpace(m.Suffix),
			UsernameHint:   strings.EqualFold(strings.TrimSpace(m.Hint), "true"),
			Enterprise:     cfg,
		}, nil
	}
	return EAPConfigProfile{}, fmt.Errorf("no supported authentication method (found types %s)", strings.Join(found, ", "))
}

// enterprise maps the method to an EnterpriseConfig; ok is false when the
// EAP type or its inner method can't be expressed.
func (m eapXMLMethod) enterprise() (cfg EnterpriseConfig, ok bool) {
	outer := strings.TrimSpace(m.Outer)
	switch m.Type {
	case 21:
		cfg = EnterpriseConfig{EAP: "ttls", AnonymousIdentity: outer}
		for _, in := range m.Inner {
			if p, found := eapTTLSInnerNonEAP[strings.TrimSpace(in.NonEAP)]; found {
				cfg.Phase2 = p
			} else if strings.TrimSpace(in.EAP) == "26" {
				cfg.Phase2 = "eap-mschapv2"
			}
			if cfg.Phase2 != "" {
				return cfg, true
			}
		}
	case 25:
		cfg = EnterpriseConfig{EAP: "peap", Phase2: "mschapv2", AnonymousIdentity: outer}
		if len(m.Inner) == 0 {
			return cfg, true
		}
		for _, in := range m.Inner {
			if p, found := eapPEAPInnerEAP[strings.TrimSpace(in.EAP)]; found {
				cfg.Phase2 = p
				return cfg, true
			}
		}
	case 13:
		return EnterpriseConfig{EAP: "tls", Identity: outer}, true
	case 52:
		return EnterpriseConfig{EAP: "pwd", AnonymousIdentity: outer}, true
	}
	return cfg, false
}

// applyServer sets the CA bundle (PEM) and the server names.
func (m eapXMLMethod) applyServer(cfg *EnterpriseConfig) error {
	var bundle []byte
	for _, c := range m.CAs {
		der, err := base64.StdEncoding.DecodeString(strings.Join(strings.Fields(c), ""))
		if err != nil {
			return fmt.Errorf("invalid CA certificate: %w", err)
		}
		if _, err := x509.ParseCertificate(der); err != nil {
			return fmt.Errorf("invalid CA certificate: %w", err)
		}
		bundle = append(bundle, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})...)
	}
	cfg.CA = "system"
	if len(bundle) > 0 {
		cfg.CA = "file"
		cfg.CACertPEM = string(bundle)
	}

	var names []string
	for _, s := range m.Servers {
		if s = strings.TrimSpace(s); s != "" {
			names = append(names, s)
		}
	}
	cfg.ServerDomain = strings.Join(names, ";")
	return nil
}
