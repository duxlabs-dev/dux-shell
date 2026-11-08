package network

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const nmSettingsPath dbus.ObjectPath = "/org/freedesktop/NetworkManager/Settings"

const firewalldPath dbus.ObjectPath = "/org/fedoraproject/FirewallD1"

const (
	nmSettingsAddConnection        = "org.freedesktop.NetworkManager.Settings.AddConnection"
	nmSettingsAddConnectionUnsaved = "org.freedesktop.NetworkManager.Settings.AddConnectionUnsaved"
	nmSettingsErrInvalidConnection = "org.freedesktop.NetworkManager.Settings.InvalidConnection"

	nmConnFlagUnsaved  uint32 = 0x1
	nmConnFlagExternal uint32 = 0x8

	nmPermModifySystem = "org.freedesktop.NetworkManager.settings.modify.system"
	nmPermModifyOwn    = "org.freedesktop.NetworkManager.settings.modify.own"

	firewalldService  = "org.fedoraproject.FirewallD1"
	firewalldGetZones = "org.fedoraproject.FirewallD1.zone.getZones"
)

var _ ConnectionEditorBackend = (*NetworkManagerBackend)(nil)

type activeProfile struct {
	device string
	state  gonetworkmanager.NmActiveConnectionState
}

func (b *NetworkManagerBackend) ListConnectionProfiles() ([]ConnectionProfile, error) {
	settingsMgr, err := b.networkManagerSettings()
	if err != nil {
		return nil, err
	}
	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to list connections: %w", err)
	}
	active, err := b.activeProfiles()
	if err != nil {
		return nil, err
	}
	perms := b.nmPermissions()

	profiles := make([]ConnectionProfile, 0, len(connections))
	for _, conn := range connections {
		obj := b.nmObject(conn.GetPath())
		if obj == nil {
			return nil, fmt.Errorf("D-Bus connection unavailable")
		}

		flags, err := connectionFlags(obj)
		if err != nil {
			log.Warnf("unable to read flags of %s: %v", conn.GetPath(), err)
			continue
		}
		// NM generates these for interfaces it doesn't manage (docker0, lo, ...).
		if flags&nmConnFlagExternal != 0 {
			continue
		}

		settings, err := readConnectionSettings(obj, false)
		if err != nil {
			log.Errorf("unable to get settings for %s: %v", conn.GetPath(), err)
			continue
		}
		c := settings["connection"]
		p := ConnectionProfile{Autoconnect: true, Unsaved: flags&nmConnFlagUnsaved != 0}
		p.UUID, _ = c["uuid"].Value().(string)
		p.ID, _ = c["id"].Value().(string)
		p.Type, _ = c["type"].Value().(string)
		p.InterfaceName, _ = c["interface-name"].Value().(string)
		p.Timestamp, _ = c["timestamp"].Value().(uint64)
		if v, ok := c["autoconnect"].Value().(bool); ok {
			p.Autoconnect = v
		}
		p.Controller = firstString(c, "controller", "master")
		p.PortType = firstString(c, "port-type", "slave-type")
		p.CanModify = canModifyProfile(perms, c)
		if ssid, ok := settings["802-11-wireless"]["ssid"].Value().([]byte); ok && utf8.Valid(ssid) {
			p.SSID = string(ssid)
		}
		if a, ok := active[p.UUID]; ok {
			p.Device = a.device
			p.Active = a.state == gonetworkmanager.NmActiveConnectionStateActivating ||
				a.state == gonetworkmanager.NmActiveConnectionStateActivated
			p.ActiveState = activeStateName(a.state)
		}
		profiles = append(profiles, p)
	}

	slices.SortFunc(profiles, func(a, b ConnectionProfile) int {
		if c := strings.Compare(strings.ToLower(a.ID), strings.ToLower(b.ID)); c != 0 {
			return c
		}
		return strings.Compare(a.UUID, b.UUID)
	})
	return profiles, nil
}

func firstString(sec map[string]dbus.Variant, keys ...string) string {
	for _, k := range keys {
		if v, _ := sec[k].Value().(string); v != "" {
			return v
		}
	}
	return ""
}

// nmPermissions returns nil when NM can't be asked, which allows every edit.
func (b *NetworkManagerBackend) nmPermissions() map[string]string {
	obj := b.nmObject(dbusNMPath)
	if obj == nil {
		log.Warnf("unable to read NetworkManager permissions: D-Bus connection unavailable")
		return nil
	}
	var perms map[string]string
	if err := obj.Call(gonetworkmanager.NetworkManagerGetPermissions, 0).Store(&perms); err != nil {
		log.Warnf("unable to read NetworkManager permissions: %v", err)
		return nil
	}
	return perms
}

// canModifyProfile treats "auth" as allowed, since the polkit agent can prompt.
func canModifyProfile(perms map[string]string, conn map[string]dbus.Variant) bool {
	if perms == nil {
		return true
	}
	key := nmPermModifySystem
	if users, _ := conn["permissions"].Value().([]string); len(users) > 0 {
		key = nmPermModifyOwn
	}
	return perms[key] != "no"
}

func (b *NetworkManagerBackend) activeProfiles() (map[string]activeProfile, error) {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	conns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to get active connections: %w", err)
	}
	out := make(map[string]activeProfile, len(conns))
	for _, ac := range conns {
		uuid, err := ac.GetPropertyUUID()
		if err != nil {
			continue
		}
		state, _ := ac.GetPropertyState()
		a := activeProfile{state: state}
		if devs, err := ac.GetPropertyDevices(); err == nil && len(devs) > 0 {
			a.device, _ = devs[0].GetPropertyInterface()
		}
		out[uuid] = a
	}
	return out, nil
}

func activeStateName(s gonetworkmanager.NmActiveConnectionState) string {
	switch s {
	case gonetworkmanager.NmActiveConnectionStateActivating:
		return "activating"
	case gonetworkmanager.NmActiveConnectionStateActivated:
		return "activated"
	case gonetworkmanager.NmActiveConnectionStateDeactivating:
		return "deactivating"
	default:
		return ""
	}
}

func (b *NetworkManagerBackend) findConnectionByUUID(uuid string) (gonetworkmanager.Connection, error) {
	settingsMgr, err := b.networkManagerSettings()
	if err != nil {
		return nil, err
	}
	conn, err := settingsMgr.GetConnectionByUUID(uuid)
	var dbusErr dbus.Error
	switch {
	case err == nil && conn != nil:
		return conn, nil
	case err == nil, errors.As(err, &dbusErr) && dbusErr.Name == nmSettingsErrInvalidConnection:
		return nil, fmt.Errorf("connection %s not found", uuid)
	default:
		return nil, fmt.Errorf("failed to find connection %s: %w", uuid, err)
	}
}

func (b *NetworkManagerBackend) connectionObject(uuid string) (dbus.BusObject, error) {
	conn, err := b.findConnectionByUUID(uuid)
	if err != nil {
		return nil, err
	}
	obj := b.nmObject(conn.GetPath())
	if obj == nil {
		return nil, fmt.Errorf("D-Bus connection unavailable")
	}
	return obj, nil
}

func (b *NetworkManagerBackend) GetConnectionSettings(uuid string, withSecrets bool) (map[string]map[string]any, error) {
	obj, err := b.connectionObject(uuid)
	if err != nil {
		return nil, err
	}
	settings, err := readConnectionSettings(obj, withSecrets)
	if err != nil {
		return nil, err
	}
	dropLegacyIPKeys(settings)
	return decodeSettingsForJSON(settings), nil
}

func (b *NetworkManagerBackend) UpdateConnectionSettings(uuid string, patch SettingsPatch, persist bool) error {
	if len(patch) == 0 {
		return errors.New("no changes")
	}
	obj, err := b.connectionObject(uuid)
	if err != nil {
		return err
	}
	return updateConnectionSettingsRemoving(obj, persist, secretRemovalsFromPatch(patch), func(s nmSettings) error {
		before := s["connection"]
		identity := [2]any{before["uuid"].Value(), before["type"].Value()}
		if section, ok := patch["802-1x"]; ok {
			// Applies to raw patches too: while system-ca-certs or domain-match stays
			// unchanged, ca-cert, ca-path and domain-suffix-match can't be deleted.
			keepUnmodelledEnterpriseKeys(section, s["802-1x"])
		}
		if err := applySettingsPatch(s, patch); err != nil {
			return err
		}
		after := s["connection"]
		if identity != [2]any{after["uuid"].Value(), after["type"].Value()} {
			return errors.New("connection.uuid and connection.type cannot be changed")
		}
		return b.applyLegacyDNS(patch, s)
	})
}

// applyLegacyDNS makes a patched dns-data authoritative: the stored legacy dns
// is dropped (so clearing dns-data clears DNS), and on NM before 1.52 the new
// dns-data is rewritten as legacy dns.
func (b *NetworkManagerBackend) applyLegacyDNS(patch SettingsPatch, s nmSettings) error {
	var convert []string
	for _, family := range []string{"ipv4", "ipv6"} {
		v, ok := patch[family]["dns-data"]
		if !ok {
			continue
		}
		delete(s[family], "dns")
		if v != nil {
			convert = append(convert, family)
		}
	}
	if len(convert) == 0 || !b.legacyDNS() {
		return nil
	}
	return convertDNSDataToLegacy(s, convert)
}

// convertDNSDataToLegacy replaces dns-data with dns (ipv4 "au" in network byte
// order, ipv6 "aay") for the given families. Entries the legacy key can't
// express are an error.
func convertDNSDataToLegacy(s nmSettings, families []string) error {
	for _, family := range families {
		v, ok := s[family]["dns-data"]
		if !ok {
			continue
		}
		entries, _ := v.Value().([]string)
		v4 := make([]uint32, 0, len(entries))
		v6 := make([][]byte, 0, len(entries))
		for _, e := range entries {
			addr, err := netip.ParseAddr(e)
			switch {
			case err != nil || addr.Zone() != "":
				return fmt.Errorf("%s.dns-data: %q needs NetworkManager 1.52 or newer", family, e)
			case family == "ipv4" && addr.Is4():
				a := addr.As4()
				v4 = append(v4, binary.NativeEndian.Uint32(a[:]))
			case family == "ipv6" && addr.Is6() && !addr.Is4In6():
				v6 = append(v6, addr.AsSlice())
			default:
				return fmt.Errorf("%s.dns-data: %q is the wrong address family", family, e)
			}
		}
		delete(s[family], "dns-data")
		if family == "ipv4" {
			setSettingValue(s, family, "dns", v4)
		} else {
			setSettingValue(s, family, "dns", v6)
		}
	}
	return nil
}

func (b *NetworkManagerBackend) ActivateConnectionProfile(uuid, device string) error {
	var dev gonetworkmanager.Device
	if device != "" {
		var err error
		if dev, err = b.nmConn.(gonetworkmanager.NetworkManager).GetDeviceByIpIface(device); err != nil || dev == nil {
			return fmt.Errorf("device %s not found", device)
		}
	}
	return b.activateProfile(uuid, dev)
}

// activateProfile activates a saved profile; a nil dev lets NM pick the device.
func (b *NetworkManagerBackend) activateProfile(uuid string, dev gonetworkmanager.Device) error {
	conn, err := b.findConnectionByUUID(uuid)
	if err != nil {
		return err
	}
	if _, err := b.nmConn.(gonetworkmanager.NetworkManager).ActivateConnection(conn, dev, nil); err != nil {
		return fmt.Errorf("failed to activate connection: %w", err)
	}
	return nil
}

func (b *NetworkManagerBackend) DeactivateConnectionProfile(uuid string) error {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	conns, err := nm.GetPropertyActiveConnections()
	if err != nil {
		return fmt.Errorf("failed to get active connections: %w", err)
	}
	for _, ac := range conns {
		if id, err := ac.GetPropertyUUID(); err != nil || id != uuid {
			continue
		}
		if err := nm.DeactivateConnection(ac); err != nil {
			return fmt.Errorf("failed to deactivate connection: %w", err)
		}
		return nil
	}
	return nil
}

func (b *NetworkManagerBackend) FirewallZones() ([]string, error) {
	obj := b.firewalldObject()
	if obj == nil {
		return nil, fmt.Errorf("D-Bus connection unavailable")
	}
	var zones []string
	err := obj.Call(firewalldGetZones, 0).Store(&zones)
	var dbusErr dbus.Error
	if errors.As(err, &dbusErr) && (dbusErr.Name == "org.freedesktop.DBus.Error.ServiceUnknown" ||
		dbusErr.Name == "org.freedesktop.DBus.Error.NameHasNoOwner") {
		return []string{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to list firewall zones: %w", err)
	}
	slices.Sort(zones)
	return zones, nil
}

func (b *NetworkManagerBackend) AddConnectionProfile(settings SettingsPatch, persist bool) (string, error) {
	s, err := encodeNewSettings(settings)
	if err != nil {
		return "", err
	}
	if t, _ := s["connection"]["type"].Value().(string); t == "" {
		return "", errors.New("connection.type is required")
	}
	if err := b.applyLegacyDNS(settings, s); err != nil {
		return "", err
	}
	uuid, _ := s["connection"]["uuid"].Value().(string)
	if uuid == "" {
		uuid = newUUIDv4()
		setSettingValue(s, "connection", "uuid", uuid)
	}
	method := nmSettingsAddConnectionUnsaved
	if persist {
		method = nmSettingsAddConnection
	}
	if err := b.addConnection(method, s); err != nil {
		return "", err
	}
	return uuid, nil
}

func (b *NetworkManagerBackend) DeleteConnectionProfile(uuid string) error {
	conn, err := b.findConnectionByUUID(uuid)
	if err != nil {
		return err
	}
	if err := conn.Delete(); err != nil {
		return fmt.Errorf("failed to delete connection: %w", err)
	}
	return nil
}

func (b *NetworkManagerBackend) DuplicateConnectionProfile(uuid, name string) (string, error) {
	if name == "" {
		return "", errors.New("name is required")
	}
	obj, err := b.connectionObject(uuid)
	if err != nil {
		return "", err
	}
	method := nmSettingsAddConnection
	if flags, err := connectionFlags(obj); err != nil {
		log.Warnf("unable to read flags of %s, saving duplicate to disk: %v", uuid, err)
	} else if flags&nmConnFlagUnsaved != 0 {
		method = nmSettingsAddConnectionUnsaved
	}
	s, err := readConnectionSettings(obj, true)
	if err != nil {
		return "", err
	}
	dropLegacyIPKeys(s)
	newUUID := newUUIDv4()
	setSettingValue(s, "connection", "uuid", newUUID)
	setSettingValue(s, "connection", "id", name)
	deleteSettingValue(s, "connection", "timestamp")
	if err := b.addConnection(method, s); err != nil {
		return "", err
	}
	return newUUID, nil
}

func connectionFlags(obj dbus.BusObject) (uint32, error) {
	v, err := obj.GetProperty(dbusNMSettingsConnectionInterface + ".Flags")
	if err != nil {
		return 0, err
	}
	flags, _ := v.Value().(uint32)
	return flags, nil
}

func (b *NetworkManagerBackend) addConnection(method string, s nmSettings) error {
	obj := b.nmObject(nmSettingsPath)
	if obj == nil {
		return fmt.Errorf("D-Bus connection unavailable")
	}
	if err := obj.Call(method, 0, s).Err; err != nil {
		return fmt.Errorf("failed to add connection: %w", err)
	}
	return nil
}

func newUUIDv4() string {
	var u [16]byte
	_, _ = rand.Read(u[:])
	u[6] = u[6]&0x0f | 0x40
	u[8] = u[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", u[0:4], u[4:6], u[6:8], u[8:10], u[10:])
}

var nmcliTimeout = 10 * time.Second

// nmcliRun runs nmcli with a C locale and returns stdout and stderr separately.
var nmcliRun = func(args ...string) ([]byte, []byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), nmcliTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "nmcli", args...)
	cmd.WaitDelay = time.Second
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		err = fmt.Errorf("timed out after %s", nmcliTimeout)
	}
	return stdout.Bytes(), stderr.Bytes(), err
}

func (b *NetworkManagerBackend) ExportConnectionProfile(uuid, path string) error {
	if !filepath.IsAbs(path) {
		return errors.New("export path must be absolute")
	}
	obj, err := b.connectionObject(uuid)
	if err != nil {
		return err
	}
	s, err := readConnectionSettings(obj, false)
	if err != nil {
		return err
	}

	var content []byte
	switch typ, _ := s["connection"]["type"].Value().(string); typ {
	case "wireguard":
		if err := mergeConnectionSecrets(obj, s); err != nil {
			return err
		}
		dropLegacyIPKeys(s)
		conf, err := wgQuickConfig(decodeSettingsForJSON(s))
		if err != nil {
			return err
		}
		content = []byte(conf)
	case "vpn":
		out, errOut, err := nmcliRun("connection", "export", "uuid", uuid)
		if err != nil {
			msg := strings.TrimSpace(string(errOut))
			if msg == "" {
				msg = strings.TrimSpace(string(out))
			}
			if msg == "" {
				msg = err.Error()
			}
			return fmt.Errorf("nmcli: %s", msg)
		}
		content = out
	default:
		return errors.New("export supports VPN and WireGuard connections only")
	}

	return writeFileAtomic(path, content)
}

// writeFileAtomic replaces path with a new 0600 file, refusing an existing
// non-regular target so a FIFO or symlink is never opened.
func writeFileAtomic(path string, content []byte) error {
	if info, err := os.Lstat(path); err == nil && !info.Mode().IsRegular() {
		return fmt.Errorf("%s is not a regular file", path)
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".dms-export-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	_, err = f.Write(content)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = os.Rename(tmp, path)
	}
	if err != nil {
		os.Remove(tmp)
	}
	return err
}
