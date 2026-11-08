package network

import (
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// testdata/uhh.eap-config: https://cat.eduroam.org/user/API.php?action=downloadInstaller&device=eap-generic&profile=10830 (fetched 2026-10-03)

func eapType(n int) string { return fmt.Sprintf(`<EAPMethod><Type>%d</Type></EAPMethod>`, n) }

func eapDoc(method string) string {
	return `<EAPIdentityProviderList><EAPIdentityProvider ID="x"><AuthenticationMethods><AuthenticationMethod>` + method +
		`</AuthenticationMethod></AuthenticationMethods><CredentialApplicability><IEEE80211><SSID>net</SSID></IEEE80211></CredentialApplicability></EAPIdentityProvider></EAPIdentityProviderList>`
}

func TestParseEAPConfigFiles(t *testing.T) {
	for _, want := range [][]string{
		{"uhh.eap-config", "Universität Hamburg - uhh.eduroam2023", "eduroam", "ttls", "pap", "roamrad.rrz.uni-hamburg.de", "anonymous@uni-hamburg.de", "file", "1"},
		{"peap-tls.eap-config", "example.org", "corp,guest", "peap", "mschapv2", "a.example.org;b.example.org", "anon@example.org", "file", "2"},
	} {
		data, _ := os.ReadFile("testdata/" + want[0])
		p, err := parseEAPConfig(data)
		require.NoError(t, err, want[0])
		e := p.Enterprise
		assert.Equal(t, want[1:], []string{p.ProviderName, strings.Join(p.SSIDs, ","), e.EAP, e.Phase2, e.ServerDomain, e.AnonymousIdentity, e.CA, fmt.Sprint(strings.Count(e.CACertPEM, "BEGIN CERTIFICATE"))}, want[0])
		e.Identity, e.Password = "user@example.org", "secret"
		_, err = enterprise8021xPatch(e, true)
		assert.NoError(t, err, want[0]+" result feeds the builder")
	}
}

func TestParseEAPConfigRejects(t *testing.T) {
	ca := func(b64 string) string {
		return eapType(25) + `<ServerSideCredential><CA>` + b64 + `</CA></ServerSideCredential>`
	}
	for name, tt := range map[string]struct {
		data, want string
	}{
		"passpoint only":    {strings.Replace(eapDoc(eapType(25)), "<SSID>net</SSID>", "<ConsortiumOID>001bc50460</ConsortiumOID>", 1), "no Wi-Fi network name"},
		"leap only":         {eapDoc(eapType(17)), "no supported authentication method (found types 17)"},
		"bad base64 CA":     {eapDoc(ca("!!!")), "invalid CA certificate"},
		"not a certificate": {eapDoc(ca("aGVsbG8=")), "invalid CA certificate"},
		"malformed XML":     {`<EAPIdentityProviderList><oops>`, "invalid .eap-config"},
	} {
		_, err := parseEAPConfig([]byte(tt.data))
		assert.ErrorContains(t, err, tt.want, name)
	}
}

func TestParseEAPConfigInnerMethods(t *testing.T) {
	inner := func(outer int, kind string, in int) string {
		return eapType(outer) + fmt.Sprintf(`<InnerAuthenticationMethod><%[1]s><Type>%d</Type></%[1]s></InnerAuthenticationMethod>`, kind, in)
	}
	for method, want := range map[string][4]string{
		inner(25, "EAPMethod", 26): {"peap", "mschapv2", "", "anon@x"}, inner(25, "EAPMethod", 6): {"peap", "gtc", "", "anon@x"}, inner(25, "EAPMethod", 4): {"peap", "md5", "", "anon@x"},
		inner(21, "EAPMethod", 26): {"ttls", "eap-mschapv2", "", "anon@x"}, inner(21, "NonEAPAuthMethod", 2): {"ttls", "mschap", "", "anon@x"}, inner(21, "NonEAPAuthMethod", 3): {"ttls", "mschapv2", "", "anon@x"},
		eapType(13): {"tls", "", "anon@x", ""}, // the outer identity is the certificate identity
	} {
		p, err := parseEAPConfig([]byte(eapDoc(method + `<ClientSideCredential><OuterIdentity>anon@x</OuterIdentity></ClientSideCredential>`)))
		require.NoError(t, err, method)
		e := p.Enterprise
		assert.Equal(t, want, [4]string{e.EAP, e.Phase2, e.Identity, e.AnonymousIdentity}, method)
	}
}
