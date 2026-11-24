package network

import (
	"cmp"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
)

// generateWireGuardKeyPair returns a base64 key pair; the private key is
// clamped the way `wg genkey` does it.
func generateWireGuardKeyPair() (privateKey, publicKey string, err error) {
	k := make([]byte, 32)
	if _, err := rand.Read(k); err != nil {
		return "", "", err
	}
	k[0] &= 248
	k[31] = (k[31] & 127) | 64
	priv, err := ecdh.X25519().NewPrivateKey(k)
	if err != nil {
		return "", "", err
	}
	return base64.StdEncoding.EncodeToString(k),
		base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes()), nil
}

func wireGuardPublicKey(privateKey string) (string, error) {
	k, err := base64.StdEncoding.DecodeString(privateKey)
	if err != nil || len(k) != 32 {
		return "", errors.New("invalid WireGuard key")
	}
	priv, err := ecdh.X25519().NewPrivateKey(k)
	if err != nil {
		return "", errors.New("invalid WireGuard key")
	}
	return base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes()), nil
}

// wgQuickConfig renders decoded settings, secrets included, as a wg-quick file.
func wgQuickConfig(s map[string]map[string]any) (string, error) {
	wg := s["wireguard"]
	key, _ := wg["private-key"].(string)
	if key == "" {
		return "", errors.New("private key not available")
	}

	var b strings.Builder
	var broken string
	// A line break in a value would let a profile inject e.g. PostUp commands.
	line := func(name, v string) {
		if strings.ContainsAny(v, "\r\n") {
			broken = cmp.Or(broken, name)
			return
		}
		b.WriteString(name + " = " + v + "\n")
	}

	b.WriteString("[Interface]\n")
	line("PrivateKey", key)
	for _, f := range []struct{ key, name string }{
		{"listen-port", "ListenPort"}, {"fwmark", "FwMark"}, {"mtu", "MTU"},
	} {
		if n, _ := wg[f.key].(uint32); n != 0 {
			fmt.Fprintf(&b, "%s = %d\n", f.name, n)
		}
	}

	var addrs, dns []string
	for _, fam := range []string{"ipv4", "ipv6"} {
		addrData, _ := s[fam]["address-data"].([]map[string]any)
		for _, a := range addrData {
			addr, _ := a["address"].(string)
			if addr == "" {
				continue
			}
			if prefix, ok := a["prefix"].(uint32); ok {
				addr = fmt.Sprintf("%s/%d", addr, prefix)
			}
			addrs = append(addrs, addr)
		}
		servers, _ := s[fam]["dns-data"].([]string)
		dns = append(dns, servers...)
	}
	for _, fam := range []string{"ipv4", "ipv6"} {
		search, _ := s[fam]["dns-search"].([]string)
		dns = append(dns, search...)
	}
	if len(addrs) > 0 {
		line("Address", strings.Join(addrs, ", "))
	}
	if len(dns) > 0 {
		line("DNS", strings.Join(dns, ", "))
	}

	peers, _ := wg["peers"].([]map[string]any)
	for _, p := range peers {
		b.WriteString("\n[Peer]\n")
		if v, _ := p["public-key"].(string); v != "" {
			line("PublicKey", v)
		}
		if v, _ := p["preshared-key"].(string); v != "" {
			line("PresharedKey", v)
		}
		if ips, _ := p["allowed-ips"].([]string); len(ips) > 0 {
			line("AllowedIPs", strings.Join(ips, ", "))
		}
		if v, _ := p["endpoint"].(string); v != "" {
			line("Endpoint", v)
		}
		if n, _ := p["persistent-keepalive"].(uint32); n != 0 {
			fmt.Fprintf(&b, "PersistentKeepalive = %d\n", n)
		}
	}
	if broken != "" {
		return "", fmt.Errorf("%s contains a line break", broken)
	}
	return b.String(), nil
}
