package network

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"maps"
	"math"
	"net"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/godbus/dbus/v5"
)

// SettingsPatch is a JSON-shaped change to an NM profile. A nil section
// removes the section; a nil key removes the key.
type SettingsPatch map[string]map[string]any

// GetSettings omits keys at their default, so a stored value can't always
// supply the D-Bus type; these rows do.
var settingSignatures = func() map[string]string {
	sigs := map[string]string{
		"connection.id":                   "s",
		"connection.uuid":                 "s",
		"connection.type":                 "s",
		"connection.interface-name":       "s",
		"connection.autoconnect":          "b",
		"connection.autoconnect-priority": "i",
		"connection.autoconnect-retries":  "i",
		"connection.metered":              "i",
		"connection.zone":                 "s",
		"connection.secondaries":          "as",
		"connection.permissions":          "as",
		"connection.stable-id":            "s",
		"connection.timestamp":            "t",
		"ipv6.ip6-privacy":                "i",
		"ipv6.addr-gen-mode":              "i",
		"ipv4.dhcp-client-id":             "s",
		"ipv6.token":                      "s",

		"802-3-ethernet.mac-address":               "ay",
		"802-3-ethernet.cloned-mac-address":        "ay",
		"802-3-ethernet.assigned-mac-address":      "s",
		"802-3-ethernet.generate-mac-address-mask": "s",
		"802-3-ethernet.mac-address-denylist":      "as",
		"802-3-ethernet.mtu":                       "u",
		"802-3-ethernet.wake-on-lan":               "u",
		"802-3-ethernet.wake-on-lan-password":      "s",
		"802-3-ethernet.auto-negotiate":            "b",
		"802-3-ethernet.speed":                     "u",
		"802-3-ethernet.duplex":                    "s",
		"802-3-ethernet.port":                      "s",
		"802-3-ethernet.accept-all-mac-addresses":  "i",

		"802-11-wireless.ssid":                      "ay",
		"802-11-wireless.mode":                      "s",
		"802-11-wireless.hidden":                    "b",
		"802-11-wireless.band":                      "s",
		"802-11-wireless.channel":                   "u",
		"802-11-wireless.channel-width":             "i",
		"802-11-wireless.bssid":                     "ay",
		"802-11-wireless.mac-address":               "ay",
		"802-11-wireless.cloned-mac-address":        "ay",
		"802-11-wireless.assigned-mac-address":      "s",
		"802-11-wireless.generate-mac-address-mask": "s",
		"802-11-wireless.mac-address-randomization": "u",
		"802-11-wireless.mac-address-denylist":      "as",
		"802-11-wireless.mtu":                       "u",
		"802-11-wireless.powersave":                 "u",
		"802-11-wireless.seen-bssids":               "as",
		"802-11-wireless.wake-on-wlan":              "u",
		"802-11-wireless.ap-isolation":              "i",

		"802-1x.eap":                         "as",
		"802-1x.identity":                    "s",
		"802-1x.anonymous-identity":          "s",
		"802-1x.password":                    "s",
		"802-1x.password-flags":              "u",
		"802-1x.phase2-auth":                 "s",
		"802-1x.phase2-autheap":              "s",
		"802-1x.ca-cert":                     "ay",
		"802-1x.ca-path":                     "s",
		"802-1x.system-ca-certs":             "b",
		"802-1x.domain-match":                "s",
		"802-1x.domain-suffix-match":         "s",
		"802-1x.client-cert":                 "ay",
		"802-1x.private-key":                 "ay",
		"802-1x.private-key-password":        "s",
		"802-1x.private-key-password-flags":  "u",
		"802-1x.phase1-peapver":              "s",
		"802-1x.phase1-peaplabel":            "s",
		"802-1x.phase1-auth-flags":           "u",
		"802-1x.openssl-ciphers":             "s",
		"802-1x.altsubject-matches":          "as",
		"802-1x.auth-timeout":                "i",
		"802-1x.optional":                    "b",
		"802-11-wireless-security.key-mgmt":  "s",
		"802-11-wireless-security.psk":       "s",
		"802-11-wireless-security.psk-flags": "u",
		"802-11-wireless-security.pmf":       "i",
		"802-11-wireless-security.proto":     "as",
		"802-11-wireless-security.pairwise":  "as",
		"802-11-wireless-security.group":     "as",

		"wireguard.private-key":            "s",
		"wireguard.private-key-flags":      "u",
		"wireguard.listen-port":            "u",
		"wireguard.fwmark":                 "u",
		"wireguard.peer-routes":            "b",
		"wireguard.mtu":                    "u",
		"wireguard.ip4-auto-default-route": "i",
		"wireguard.ip6-auto-default-route": "i",
		"wireguard.peers":                  "aa{sv}",

		"vpn.service-type": "s",
		"vpn.user-name":    "s",
		"vpn.persistent":   "b",
		"vpn.timeout":      "u",
		"vpn.data":         "a{ss}",
		"vpn.secrets":      "a{ss}",

		"gsm.apn":                          "s",
		"gsm.auto-config":                  "b",
		"gsm.username":                     "s",
		"gsm.password":                     "s",
		"gsm.password-flags":               "u",
		"gsm.pin":                          "s",
		"gsm.pin-flags":                    "u",
		"gsm.home-only":                    "b",
		"gsm.network-id":                   "s",
		"gsm.number":                       "s",
		"gsm.mtu":                          "u",
		"gsm.device-id":                    "s",
		"gsm.sim-id":                       "s",
		"gsm.sim-operator-id":              "s",
		"gsm.initial-eps-bearer-apn":       "s",
		"gsm.initial-eps-bearer-configure": "b",

		"cdma.number":         "s",
		"cdma.username":       "s",
		"cdma.password":       "s",
		"cdma.password-flags": "u",
		"cdma.mtu":            "u",

		"pppoe.parent":         "s",
		"pppoe.service":        "s",
		"pppoe.username":       "s",
		"pppoe.password":       "s",
		"pppoe.password-flags": "u",

		"ppp.refuse-eap":        "b",
		"ppp.refuse-pap":        "b",
		"ppp.refuse-chap":       "b",
		"ppp.refuse-mschap":     "b",
		"ppp.refuse-mschapv2":   "b",
		"ppp.require-mppe":      "b",
		"ppp.require-mppe-128":  "b",
		"ppp.mppe-stateful":     "b",
		"ppp.nobsdcomp":         "b",
		"ppp.nodeflate":         "b",
		"ppp.no-vj-comp":        "b",
		"ppp.noauth":            "b",
		"ppp.lcp-echo-interval": "u",
		"ppp.lcp-echo-failure":  "u",
		"ppp.mtu":               "u",
		"ppp.mru":               "u",
		"ppp.baud":              "u",
		"ppp.crtscts":           "b",

		"bluetooth.bdaddr": "ay",
		"bluetooth.type":   "s",
	}
	ip := map[string]string{
		"method":             "s",
		"address-data":       "aa{sv}",
		"gateway":            "s",
		"route-data":         "aa{sv}",
		"dns-data":           "as",
		"dns-search":         "as",
		"dns-options":        "as",
		"dns-priority":       "i",
		"route-metric":       "x",
		"route-table":        "u",
		"never-default":      "b",
		"ignore-auto-dns":    "b",
		"ignore-auto-routes": "b",
		"may-fail":           "b",
		"dhcp-hostname":      "s",
		"dhcp-send-hostname": "b",
		// NM 1.52+ ignores the boolean once this is set (-1 default, 0 no, 1 yes).
		"dhcp-send-hostname-v2": "i",
	}
	for k, sig := range ip {
		sigs["ipv4."+k] = sig
		sigs["ipv6."+k] = sig
	}
	return sigs
}()

const (
	kindCert = "cert"
	kindMAC  = "mac"
	kindSSID = "ssid"

	certBlobToken  = "blob"
	certFileScheme = "file://"
)

// settingKinds marks keys whose JSON form differs from their D-Bus type.
var settingKinds = map[string]string{
	"802-1x.ca-cert":            kindCert,
	"802-1x.client-cert":        kindCert,
	"802-1x.private-key":        kindCert,
	"802-1x.phase2-ca-cert":     kindCert,
	"802-1x.phase2-client-cert": kindCert,
	"802-1x.phase2-private-key": kindCert,

	"802-3-ethernet.mac-address":         kindMAC,
	"802-3-ethernet.cloned-mac-address":  kindMAC,
	"802-11-wireless.bssid":              kindMAC,
	"802-11-wireless.mac-address":        kindMAC,
	"802-11-wireless.cloned-mac-address": kindMAC,
	"802-11-wireless.ssid":               kindSSID,
	"bluetooth.bdaddr":                   kindMAC,
}

var nestedDictSignatures = func() map[string]map[string]string {
	addr := map[string]string{"address": "s", "prefix": "u"}
	addr["label"] = "s"
	route := map[string]string{
		"dest": "s", "prefix": "u", "next-hop": "s", "metric": "u", "table": "u",
		"src": "s", "from": "s", "tos": "y", "onlink": "b", "scope": "y", "type": "s",
		"weight": "u", "window": "u", "cwnd": "u", "initcwnd": "u", "initrwnd": "u",
		"mtu": "u", "advmss": "u", "rto_min": "u", "quickack": "b",
		"lock-advmss": "b", "lock-cwnd": "b", "lock-initcwnd": "b", "lock-initrwnd": "b",
		"lock-mtu": "b", "lock-window": "b",
	}
	return map[string]map[string]string{
		"ipv4.address-data": addr,
		"ipv6.address-data": addr,
		"ipv4.route-data":   route,
		"ipv6.route-data":   route,
		"wireguard.peers": {
			"public-key": "s", "endpoint": "s", "allowed-ips": "as", "preshared-key": "s",
			"preshared-key-flags": "u", "persistent-keepalive": "u",
		},
	}
}()

// secretTombstones are the nested entries where an explicit null deletes a
// stored secret; the null itself is never encoded.
var secretTombstones = map[string]bool{"vpn.secrets": true, "wireguard.peers.preshared-key": true}

// Half-open [min, max) bounds, exact in float64.
var integerBounds = map[string][2]float64{
	"y": {0, 1 << 8},
	"n": {-(1 << 15), 1 << 15},
	"q": {0, 1 << 16},
	"i": {-(1 << 31), 1 << 31},
	"u": {0, 1 << 32},
	"x": {-(1 << 63), 1 << 63},
	"t": {0, 1 << 64},
}

func decodeSettingsForJSON(s map[string]map[string]dbus.Variant) map[string]map[string]any {
	out := make(map[string]map[string]any, len(s))
	for section, keys := range s {
		decoded := make(map[string]any, len(keys))
		for key, v := range keys {
			switch settingKinds[section+"."+key] {
			case kindCert:
				decoded[key] = decodeCert(v)
			case kindMAC:
				if b, ok := v.Value().([]byte); ok && len(b) == 6 {
					decoded[key] = strings.ToUpper(net.HardwareAddr(b).String())
				}
			case kindSSID:
				if b, ok := v.Value().([]byte); ok && utf8.Valid(b) {
					decoded[key] = string(b)
				}
			default:
				if val, ok := decodeVariant(v); ok {
					decoded[key] = val
				}
			}
		}
		if section == "ipv4" || section == "ipv6" {
			decodeLegacyDNS(decoded, keys["dns"])
		}
		out[section] = decoded
	}
	return out
}

// decodeLegacyDNS replaces the pre-1.52 "dns" key (au for IPv4, aay for IPv6)
// with dns-data strings; an existing dns-data wins.
func decodeLegacyDNS(decoded map[string]any, legacy dbus.Variant) {
	delete(decoded, "dns")
	if _, ok := decoded["dns-data"]; ok || legacy.Value() == nil {
		return
	}
	var servers []string
	switch val := legacy.Value().(type) {
	case []uint32:
		for _, u := range val {
			ip := make(net.IP, 4)
			binary.NativeEndian.PutUint32(ip, u)
			servers = append(servers, ip.String())
		}
	case [][]byte:
		for _, b := range val {
			if len(b) == 16 {
				servers = append(servers, net.IP(b).String())
			}
		}
	default:
		return
	}
	if len(servers) > 0 {
		decoded["dns-data"] = servers
	}
}

// decodeVariant reports false for shapes JSON can't carry faithfully, such as
// the legacy aau/aay/a(ayuay) IP keys.
func decodeVariant(v dbus.Variant) (any, bool) {
	switch val := v.Value().(type) {
	case string, bool, byte, int16, uint16, int32, uint32, int64, uint64, float64,
		[]byte, []string, []uint32, map[string]string:
		return val, true
	case []map[string]dbus.Variant:
		out := make([]map[string]any, len(val))
		for i, dict := range val {
			m := make(map[string]any, len(dict))
			for k, inner := range dict {
				if x, ok := decodeVariant(inner); ok {
					m[k] = x
				}
			}
			out[i] = m
		}
		return out, true
	default:
		return nil, false
	}
}

// decodeCert never returns key or certificate bytes: a path-scheme value
// becomes its path, anything else the token "blob".
func decodeCert(v dbus.Variant) string {
	b, ok := v.Value().([]byte)
	if !ok || !bytes.HasPrefix(b, []byte(certFileScheme)) || !bytes.HasSuffix(b, []byte{0}) {
		return certBlobToken
	}
	if p := string(b[len(certFileScheme) : len(b)-1]); p != "" {
		return p
	}
	return certBlobToken
}

func encodeCert(name string, value any, stored *dbus.Variant) (any, error) {
	s, ok := value.(string)
	switch {
	case !ok:
		return nil, fmt.Errorf("%s: expected absolute path or %q, got %T", name, certBlobToken, value)
	case s == certBlobToken:
		if stored == nil {
			return nil, fmt.Errorf("%s: no stored certificate to keep", name)
		}
		return stored.Value(), nil
	case filepath.IsAbs(s) && !strings.ContainsRune(s, 0):
		return append([]byte(certFileScheme+s), 0), nil
	}
	return nil, fmt.Errorf("%s: %q is not an absolute path", name, s)
}

func encodeMAC(name string, value any) ([]byte, error) {
	s, ok := value.(string)
	if !ok {
		return nil, fmt.Errorf("%s: expected MAC address string, got %T", name, value)
	}
	hw, err := net.ParseMAC(s)
	if err != nil || len(hw) != 6 {
		return nil, fmt.Errorf("%s: %q is not a 6-byte MAC address", name, s)
	}
	return hw, nil
}

func encodeSettingValue(section, key string, value any, stored *dbus.Variant) (dbus.Variant, error) {
	name := section + "." + key
	sig, ok := settingSignatures[name]
	switch {
	case ok:
	case stored != nil:
		sig = stored.Signature().String()
	default:
		return dbus.Variant{}, fmt.Errorf("unsupported setting %s", name)
	}
	if !isJSONValue(value) {
		if got := dbus.SignatureOf(value).String(); got != sig {
			return dbus.Variant{}, fmt.Errorf("%s: expected %s, got %s", name, sig, got)
		}
		return dbus.MakeVariant(value), nil
	}
	var encoded any
	var err error
	switch settingKinds[name] {
	case kindCert:
		encoded, err = encodeCert(name, value, stored)
	case kindMAC:
		encoded, err = encodeMAC(name, value)
	case kindSSID:
		s, ok := value.(string)
		if !ok {
			return dbus.Variant{}, fmt.Errorf("%s: expected string, got %T", name, value)
		}
		if n := len(s); n == 0 || n > 32 {
			return dbus.Variant{}, fmt.Errorf("%s: SSID must be 1 to 32 bytes, got %d", name, n)
		}
		encoded = []byte(s)
	default:
		encoded, err = encodeAs(name, sig, value)
	}
	if err != nil {
		return dbus.Variant{}, err
	}
	return dbus.MakeVariant(encoded), nil
}

// isJSONValue reports whether value is a type encoding/json produces; anything
// else is a native Go value from in-process callers.
func isJSONValue(value any) bool {
	switch value.(type) {
	case nil, float64, string, bool, []any, map[string]any:
		return true
	}
	return false
}

func encodeAs(name, sig string, value any) (any, error) {
	mismatch := func() error { return fmt.Errorf("%s: expected %s, got %T", name, sig, value) }
	switch sig {
	case "s":
		if s, ok := value.(string); ok {
			return s, nil
		}
	case "b":
		if b, ok := value.(bool); ok {
			return b, nil
		}
	case "y", "n", "q", "i", "u", "x", "t":
		f, ok := value.(float64)
		if !ok {
			return nil, mismatch()
		}
		return encodeInteger(name, sig, f)
	case "ay":
		s, ok := value.(string)
		if !ok {
			return nil, mismatch()
		}
		b, err := base64.StdEncoding.DecodeString(s)
		if err != nil {
			return nil, fmt.Errorf("%s: invalid base64: %w", name, err)
		}
		return b, nil
	case "as":
		list, ok := value.([]any)
		if !ok {
			return nil, mismatch()
		}
		out := make([]string, len(list))
		for i, item := range list {
			if out[i], ok = item.(string); !ok {
				return nil, fmt.Errorf("%s: expected strings, got %T", name, item)
			}
		}
		return out, nil
	case "a{ss}":
		dict, ok := value.(map[string]any)
		if !ok {
			return nil, mismatch()
		}
		out := make(map[string]string, len(dict))
		for k, item := range dict {
			if item == nil && secretTombstones[name] {
				continue
			}
			s, ok := item.(string)
			if !ok {
				return nil, fmt.Errorf("%s.%s: expected string, got %T", name, k, item)
			}
			out[k] = s
		}
		return out, nil
	case "aa{sv}":
		return encodeDictList(name, value)
	default:
		return nil, fmt.Errorf("%s: unsupported signature %s", name, sig)
	}
	return nil, mismatch()
}

func encodeInteger(name, sig string, f float64) (any, error) {
	bounds := integerBounds[sig]
	if f != math.Trunc(f) || f < bounds[0] || f >= bounds[1] {
		return nil, fmt.Errorf("%s: %v is not a valid %s", name, f, sig)
	}
	switch sig {
	case "y":
		return byte(f), nil
	case "n":
		return int16(f), nil
	case "q":
		return uint16(f), nil
	case "i":
		return int32(f), nil
	case "u":
		return uint32(f), nil
	case "x":
		return int64(f), nil
	default:
		return uint64(f), nil
	}
}

func encodeDictList(name string, value any) (any, error) {
	list, ok := value.([]any)
	if !ok {
		return nil, fmt.Errorf("%s: expected aa{sv}, got %T", name, value)
	}
	inner := nestedDictSignatures[name]
	out := make([]map[string]dbus.Variant, len(list))
	for i, item := range list {
		dict, ok := item.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("%s: expected objects, got %T", name, item)
		}
		encoded := make(map[string]dbus.Variant, len(dict))
		for k, v := range dict {
			innerName := name + "." + k
			if v == nil && secretTombstones[innerName] {
				continue
			}
			sig, ok := inner[k]
			if !ok {
				return nil, fmt.Errorf("unsupported setting %s", innerName)
			}
			x, err := encodeAs(innerName, sig, v)
			if err != nil {
				return nil, err
			}
			encoded[k] = dbus.MakeVariant(x)
		}
		out[i] = encoded
	}
	return out, nil
}

// applySettingsPatch encodes into a copy and only replaces s's contents once
// every value has encoded, so a failed patch leaves s untouched.
func applySettingsPatch(s map[string]map[string]dbus.Variant, patch SettingsPatch) error {
	if s == nil {
		return fmt.Errorf("no settings to patch")
	}
	next := make(map[string]map[string]dbus.Variant, len(s))
	for section, keys := range s {
		next[section] = maps.Clone(keys)
	}
	for section, keys := range patch {
		if keys == nil {
			delete(next, section)
			continue
		}
		target := next[section]
		if target == nil && len(keys) == 0 {
			next[section] = map[string]dbus.Variant{}
			continue
		}
		for key, value := range keys {
			if value == nil {
				delete(target, key)
				continue
			}
			if target == nil {
				target = make(map[string]dbus.Variant, len(keys))
				next[section] = target
			}
			var stored *dbus.Variant
			if v, ok := target[key]; ok {
				stored = &v
			}
			encoded, err := encodeSettingValue(section, key, value, stored)
			if err != nil {
				return err
			}
			target[key] = encoded
		}
	}
	clear(s)
	maps.Copy(s, next)
	return nil
}

func encodeNewSettings(settings SettingsPatch) (map[string]map[string]dbus.Variant, error) {
	s := map[string]map[string]dbus.Variant{}
	if err := applySettingsPatch(s, settings); err != nil {
		return nil, err
	}
	return s, nil
}
