package network

import (
	"errors"
	"fmt"
	"maps"
	"reflect"
	"slices"
	"strings"

	"github.com/godbus/dbus/v5"
)

type nmSettings = map[string]map[string]dbus.Variant

const (
	nmConnGetSettings = dbusNMSettingsConnectionInterface + ".GetSettings"
	nmConnGetSecrets  = dbusNMSettingsConnectionInterface + ".GetSecrets"
	nmConnUpdate2     = dbusNMSettingsConnectionInterface + ".Update2"

	nmUpdate2FlagToDisk uint32 = 0x1
)

// nmSecretKeys lists each section's secret properties; NM has no API for it.
var nmSecretKeys = map[string][]string{
	"802-11-wireless-security": {"psk", "wep-key0", "wep-key1", "wep-key2", "wep-key3", "leap-password"},
	"802-1x": {"password", "password-raw", "pin", "private-key-password", "phase2-private-key-password",
		"ca-cert-password", "client-cert-password", "phase2-ca-cert-password", "phase2-client-cert-password"},
	"vpn":       {"secrets"},
	"wireguard": {"private-key"},
	"gsm":       {"password", "pin", "initial-eps-bearer-password"},
	"cdma":      {"password"},
	"pppoe":     {"password"},
	"adsl":      {"password"},
	"macsec":    {"mka-cak"},
}

var nmSecretSettings = slices.Sorted(maps.Keys(nmSecretKeys))

// NM answers GetSecrets with one of these when only a secret agent holds the
// section's secrets and none provided them.
var nmNoSecretsErrors = []string{
	"org.freedesktop.NetworkManager.AgentManager.NoSecrets",
	"org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets",
}

// legacyIPKeys maps each legacy ipv4/ipv6 key to its modern twin. NM ignores
// the modern key when the legacy one is sent.
var legacyIPKeys = map[string]string{
	"addresses": "address-data",
	"routes":    "route-data",
	"dns":       "dns-data",
}

func readConnectionSettings(obj dbus.BusObject, withSecrets bool) (nmSettings, map[string]error, error) {
	var settings nmSettings
	if err := obj.Call(nmConnGetSettings, 0).Store(&settings); err != nil {
		return nil, nil, fmt.Errorf("failed to get connection settings: %w", err)
	}
	if !withSecrets {
		return settings, nil, nil
	}
	unreadable, err := mergeConnectionSecrets(obj, settings, nmSecretSettings)
	if err != nil {
		return nil, nil, err
	}
	return settings, unreadable, nil
}

// nestedSecrets are containers holding several secrets. A mutation that
// replaces one wholesale would drop the stored entries it doesn't mention.
var nestedSecrets = [][2]string{{"vpn", "secrets"}, {"wireguard", "peers"}}

// secretRemovals lists stored nested secrets a patch deletes with an explicit
// null: vpn.secrets keys, and public keys of peers losing their preshared-key.
type secretRemovals struct {
	vpnSecrets, peerPSKs []string
}

func secretRemovalsFromPatch(patch SettingsPatch) secretRemovals {
	var r secretRemovals
	if secrets, ok := patch["vpn"]["secrets"].(map[string]any); ok {
		for k, v := range secrets {
			if v == nil {
				r.vpnSecrets = append(r.vpnSecrets, k)
			}
		}
	}
	peers, _ := patch["wireguard"]["peers"].([]any)
	for _, p := range peers {
		peer, _ := p.(map[string]any)
		key, ok := peer["public-key"].(string)
		if psk, has := peer["preshared-key"]; ok && has && psk == nil {
			r.peerPSKs = append(r.peerPSKs, key)
		}
	}
	return r
}

// updateConnectionSettings is the single write path for NM profiles. NM keeps
// its stored secrets only when an update carries none; otherwise it drops every
// secret the update omits. So stored secrets are merged in. A section only an
// agent can supply is read again while DMS's agent offers the secrets mutate
// enters there; if it stays unreadable, all secrets are left out and mutate
// may not change any. Entries of nested secret containers that mutate omits
// are merged back afterwards.
// persist=false keeps the profile in whatever storage it already lives in.
func updateConnectionSettings(obj dbus.BusObject, persist bool, mutate func(nmSettings) error) error {
	return updateConnectionSettingsRemoving(obj, persist, secretRemovals{}, mutate)
}

// updateConnectionSettingsRemoving is updateConnectionSettings, except the
// nested secrets in removed are not merged back, so they are deleted.
func updateConnectionSettingsRemoving(obj dbus.BusObject, persist bool, removed secretRemovals, mutate func(nmSettings) error) error {
	if obj == nil {
		return fmt.Errorf("D-Bus connection unavailable")
	}
	settings, unreadable, err := readConnectionSettings(obj, true)
	if err != nil {
		return err
	}
	if uuid, _ := settings["connection"]["uuid"].Value().(string); len(unreadable) > 0 && uuid != "" {
		if entered := enteredSecrets(settings, unreadable, mutate); len(entered) > 0 {
			name := slices.Min(slices.Collect(maps.Keys(entered)))
			defer offerAgentSecrets(uuid, entered)()
			again, err := mergeConnectionSecrets(obj, settings, slices.Collect(maps.Keys(entered)))
			if err != nil {
				return err
			}
			for name := range entered {
				if again[name] == nil {
					delete(unreadable, name)
				}
			}
			// An update that leaves the held sections out can't carry the entered secrets either.
			if len(unreadable) > 0 {
				return heldSecretsError(name, unreadable)
			}
		}
	}
	if len(unreadable) > 0 {
		return updateWithoutSecrets(obj, persist, settings, unreadable, removed, mutate)
	}
	stored := map[[2]string]dbus.Variant{}
	for _, k := range nestedSecrets {
		if v, ok := settings[k[0]][k[1]]; ok {
			stored[k] = v
		}
	}
	if err := mutate(settings); err != nil {
		return err
	}
	for k, v := range stored {
		if cur, ok := settings[k[0]][k[1]]; ok {
			settings[k[0]][k[1]] = mergeNestedSecret(k[0], k[1], dropRemovedSecrets(k[0], v, removed), cur)
		}
	}
	return sendConnectionUpdate(obj, persist, settings)
}

// enteredSecrets returns the secrets mutate sets in the unreadable sections,
// which carry none yet.
func enteredSecrets(settings nmSettings, unreadable map[string]error, mutate func(nmSettings) error) nmSettingMap {
	plain := make(nmSettings, len(settings))
	for section, keys := range settings {
		plain[section] = maps.Clone(keys)
	}
	out := nmSettingMap{}
	if mutate(plain) != nil {
		return out
	}
	for section, values := range collectSecrets(plain, false) {
		if unreadable[section] == nil {
			continue
		}
		for k, v := range values {
			if strings.HasPrefix(k, "peers/") {
				continue
			}
			if out[section] == nil {
				out[section] = nmVariantMap{}
			}
			out[section][k] = dbus.MakeVariant(v)
		}
	}
	return out
}

func updateWithoutSecrets(obj dbus.BusObject, persist bool, settings nmSettings, unreadable map[string]error, removed secretRemovals, mutate func(nmSettings) error) error {
	before := collectSecrets(settings, false)
	if err := mutate(settings); err != nil {
		return err
	}
	after := collectSecrets(settings, true)
	for _, name := range nmSecretSettings {
		removedHere := name == "vpn" && len(removed.vpnSecrets) > 0 || name == "wireguard" && len(removed.peerPSKs) > 0
		if removedHere || !reflect.DeepEqual(before[name], after[name]) {
			return heldSecretsError(name, unreadable)
		}
	}
	return sendConnectionUpdate(obj, persist, settings)
}

func heldSecretsError(name string, unreadable map[string]error) error {
	return fmt.Errorf("%s secrets can't be changed here while the %s secrets are held by a secret agent",
		name, strings.Join(slices.Sorted(maps.Keys(unreadable)), ", "))
}

func sendConnectionUpdate(obj dbus.BusObject, persist bool, settings nmSettings) error {
	dropLegacyIPKeys(settings)
	var flags uint32
	if persist {
		flags = nmUpdate2FlagToDisk
	}
	if err := obj.Call(nmConnUpdate2, 0, settings, flags, map[string]dbus.Variant{}).Err; err != nil {
		return fmt.Errorf("failed to update connection: %w", err)
	}
	return nil
}

// collectSecrets returns s's secrets per section; strip removes them from s.
func collectSecrets(s nmSettings, strip bool) map[string]map[string]any {
	out := map[string]map[string]any{}
	add := func(section, key string, v dbus.Variant) {
		if out[section] == nil {
			out[section] = map[string]any{}
		}
		out[section][key] = v.Value()
	}
	for section, keys := range nmSecretKeys {
		for _, k := range keys {
			if v, ok := s[section][k]; ok {
				add(section, k, v)
				if strip {
					delete(s[section], k)
				}
			}
		}
	}
	peers, _ := s["wireguard"]["peers"].Value().([]map[string]dbus.Variant)
	kept := make([]map[string]dbus.Variant, len(peers))
	for i, p := range peers {
		kept[i] = p
		if psk, ok := p["preshared-key"]; ok {
			key, _ := p["public-key"].Value().(string)
			add("wireguard", "peers/"+key, psk)
			kept[i] = maps.Clone(p)
			delete(kept[i], "preshared-key")
		}
	}
	if strip && peers != nil {
		s["wireguard"]["peers"] = dbus.MakeVariant(kept)
	}
	return out
}

// mergeConnectionSecrets returns the sections whose secrets only an agent
// holds, with NM's error, instead of merging them.
func mergeConnectionSecrets(obj dbus.BusObject, settings nmSettings, sections []string) (map[string]error, error) {
	unreadable := map[string]error{}
	for _, name := range sections {
		section, ok := settings[name]
		if !ok {
			continue
		}

		var stored nmSettings
		if err := obj.Call(nmConnGetSecrets, 0, name).Store(&stored); err != nil {
			var dbusErr dbus.Error
			if errors.As(err, &dbusErr) && slices.Contains(nmNoSecretsErrors, dbusErr.Name) {
				unreadable[name] = err
				continue
			}
			return nil, fmt.Errorf("failed to get secrets for %s: %w", name, err)
		}

		for k, v := range stored[name] {
			if cur, exists := section[k]; exists {
				section[k] = mergeNestedSecret(name, k, v, cur)
			} else {
				section[k] = v
			}
		}
	}
	return unreadable, nil
}

// mergeNestedSecret fills entries missing from cur with stored ones; entries in cur win.
func mergeNestedSecret(section, key string, stored, cur dbus.Variant) dbus.Variant {
	switch {
	case section == "vpn" && key == "secrets":
		return mergeVPNSecrets(stored, cur)
	case section == "wireguard" && key == "peers":
		return mergeWireGuardPeers(stored, cur)
	}
	return cur
}

func dropRemovedSecrets(section string, stored dbus.Variant, r secretRemovals) dbus.Variant {
	switch val := stored.Value().(type) {
	case map[string]string:
		if section != "vpn" || len(r.vpnSecrets) == 0 {
			return stored
		}
		out := maps.Clone(val)
		for _, k := range r.vpnSecrets {
			delete(out, k)
		}
		return dbus.MakeVariant(out)
	case []map[string]dbus.Variant:
		if section != "wireguard" || len(r.peerPSKs) == 0 {
			return stored
		}
		out := make([]map[string]dbus.Variant, len(val))
		for i, p := range val {
			out[i] = p
			if key, ok := p["public-key"].Value().(string); ok && slices.Contains(r.peerPSKs, key) {
				out[i] = maps.Clone(p)
				delete(out[i], "preshared-key")
			}
		}
		return dbus.MakeVariant(out)
	}
	return stored
}

func mergeVPNSecrets(stored, cur dbus.Variant) dbus.Variant {
	s, ok1 := stored.Value().(map[string]string)
	c, ok2 := cur.Value().(map[string]string)
	if !ok1 || !ok2 {
		return cur
	}
	out := maps.Clone(s)
	maps.Copy(out, c)
	return dbus.MakeVariant(out)
}

func mergeWireGuardPeers(stored, cur dbus.Variant) dbus.Variant {
	s, ok1 := stored.Value().([]map[string]dbus.Variant)
	c, ok2 := cur.Value().([]map[string]dbus.Variant)
	if !ok1 || !ok2 {
		return cur
	}
	psk := make(map[string]dbus.Variant, len(s))
	for _, p := range s {
		if key, ok := p["public-key"].Value().(string); ok {
			if v, ok := p["preshared-key"]; ok {
				psk[key] = v
			}
		}
	}
	out := make([]map[string]dbus.Variant, len(c))
	for i, p := range c {
		out[i] = maps.Clone(p)
		if _, has := p["preshared-key"]; has {
			continue
		}
		if key, ok := p["public-key"].Value().(string); ok {
			if v, ok := psk[key]; ok {
				out[i]["preshared-key"] = v
			}
		}
	}
	return dbus.MakeVariant(out)
}

func dropLegacyIPKeys(s nmSettings) {
	for _, family := range []string{"ipv4", "ipv6"} {
		section := s[family]
		for legacy, modern := range legacyIPKeys {
			if _, ok := section[modern]; ok {
				delete(section, legacy)
			}
		}
	}
}

func setSettingValue(s nmSettings, section, key string, value any) {
	if s[section] == nil {
		s[section] = make(map[string]dbus.Variant)
	}
	v, ok := value.(dbus.Variant)
	if !ok {
		v = dbus.MakeVariant(value)
	}
	s[section][key] = v
}

func deleteSettingValue(s nmSettings, section, key string) {
	delete(s[section], key)
}
