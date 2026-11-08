package network

import (
	"encoding/binary"
	"errors"
	"github.com/Wifx/gonetworkmanager/v2"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	mock_dbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"maps"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const nmConnFlagsProp = dbusNMSettingsConnectionInterface + ".Flags"

type editorFixture struct {
	backend  *NetworkManagerBackend
	nm       *mock_gonetworkmanager.MockNetworkManager
	settings *mock_gonetworkmanager.MockSettings
	objects  map[dbus.ObjectPath]*mock_dbus.MockBusObject
}

func newEditorFixture(t *testing.T) *editorFixture {
	f := &editorFixture{
		nm:       mock_gonetworkmanager.NewMockNetworkManager(t),
		settings: mock_gonetworkmanager.NewMockSettings(t),
		objects:  map[dbus.ObjectPath]*mock_dbus.MockBusObject{},
	}
	var err error
	f.backend, err = NewNetworkManagerBackend(f.nm)
	require.NoError(t, err)
	f.backend.settings = f.settings
	f.backend.nmObjectFn = func(p dbus.ObjectPath) dbus.BusObject {
		obj, ok := f.objects[p]
		require.True(t, ok, "unexpected object %s", p)
		return obj
	}
	return f
}

func (f *editorFixture) object(t *testing.T, path dbus.ObjectPath) *mock_dbus.MockBusObject {
	f.objects[path] = mock_dbus.NewMockBusObject(t)
	return f.objects[path]
}

func (f *editorFixture) profile(t *testing.T, uuid string, path dbus.ObjectPath) *mock_dbus.MockBusObject {
	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetPath().Return(path).Maybe()
	f.settings.EXPECT().GetConnectionByUUID(uuid).Return(conn, nil).Maybe()
	return f.object(t, path)
}

func listedConnection(t *testing.T, f *editorFixture, path dbus.ObjectPath, flags uint32, s nmSettings) gonetworkmanager.Connection {
	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetPath().Return(path).Maybe()
	obj := f.object(t, path)
	obj.EXPECT().GetProperty(nmConnFlagsProp).Return(dbus.MakeVariant(flags), nil).Maybe()
	obj.EXPECT().Call(nmConnGetSettings, dbus.Flags(0)).Return(&dbus.Call{Body: []any{s}}).Maybe()
	return conn
}

func connSection(uuid, id, typ string, extra map[string]dbus.Variant) nmSettings {
	c := map[string]dbus.Variant{"uuid": dbus.MakeVariant(uuid), "id": dbus.MakeVariant(id), "type": dbus.MakeVariant(typ)}
	maps.Copy(c, extra)
	return nmSettings{"connection": c}
}

func TestListConnectionProfiles(t *testing.T) {
	str := func(v any) dbus.Variant { return dbus.MakeVariant(v) }
	wifi := func(uuid, id string, ssid []byte) nmSettings {
		s := connSection(uuid, id, "802-11-wireless", nil)
		s["802-11-wireless"] = map[string]dbus.Variant{"ssid": str(ssid)}
		return s
	}
	f := newEditorFixture(t)
	bad := mock_gonetworkmanager.NewMockConnection(t)
	bad.EXPECT().GetPath().Return(dbus.ObjectPath("/s/6")).Maybe()
	f.object(t, "/s/6").EXPECT().GetProperty(nmConnFlagsProp).Return(dbus.Variant{}, errors.New("gone")).Once()
	f.settings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{
		listedConnection(t, f, "/s/1", 15, connSection("u-docker", "docker0", "bridge", nil)),
		listedConnection(t, f, "/s/2", 1, connSection("u-wired", "Wired connection 1", "802-3-ethernet", map[string]dbus.Variant{
			"interface-name": str("enp5s0"), "timestamp": str(uint64(1700000000)),
		})),
		listedConnection(t, f, "/s/3", 0, connSection("u-own", "b", "802-3-ethernet", map[string]dbus.Variant{
			"permissions": str([]string{"user:marlon:"}), "autoconnect": str(false),
		})),
		listedConnection(t, f, "/s/4", 0, wifi("u-wifi", "c", []byte("eduroam"))),
		listedConnection(t, f, "/s/5", 0, wifi("u-bad", "d", []byte{0xff, 0xfe})),
		bad,
	}, nil)
	dev := mock_gonetworkmanager.NewMockDevice(t)
	dev.EXPECT().GetPropertyInterface().Return("enp5s0", nil)
	ac := mock_gonetworkmanager.NewMockActiveConnection(t)
	ac.EXPECT().GetPropertyUUID().Return("u-wired", nil)
	ac.EXPECT().GetPropertyState().Return(gonetworkmanager.NmActiveConnectionStateActivated, nil)
	ac.EXPECT().GetPropertyDevices().Return([]gonetworkmanager.Device{dev}, nil)
	f.nm.EXPECT().GetPropertyActiveConnections().Return([]gonetworkmanager.ActiveConnection{ac}, nil)
	modify := "org.freedesktop.NetworkManager.settings.modify."
	expectPermissions(t, f, map[string]string{modify + "system": "no", modify + "own": "yes"}, nil)
	profiles, err := f.backend.ListConnectionProfiles()
	require.NoError(t, err)
	assert.Equal(t, []ConnectionProfile{
		{UUID: "u-own", ID: "b", Type: "802-3-ethernet", CanModify: true},
		{UUID: "u-wifi", ID: "c", Type: "802-11-wireless", Autoconnect: true, SSID: "eduroam"},
		{UUID: "u-bad", ID: "d", Type: "802-11-wireless", Autoconnect: true},
		{
			UUID: "u-wired", ID: "Wired connection 1", Type: "802-3-ethernet", Device: "enp5s0", InterfaceName: "enp5s0",
			Active: true, ActiveState: "activated", Autoconnect: true, Timestamp: 1700000000, Unsaved: true,
		},
	}, profiles)
}

func TestListConnectionProfiles_ReportsPortRelation(t *testing.T) {
	f := newEditorFixture(t)
	legacy := connSection("u-a", "a", "802-3-ethernet", map[string]dbus.Variant{
		"master": dbus.MakeVariant("ctrl-1"), "slave-type": dbus.MakeVariant("bond"),
	})
	modern := connSection("u-b", "b", "802-3-ethernet", map[string]dbus.Variant{
		"controller": dbus.MakeVariant("ctrl-2"), "port-type": dbus.MakeVariant("bridge"),
	})
	plain := connSection("u-c", "c", "802-3-ethernet", nil)
	f.settings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{
		listedConnection(t, f, "/s/1", 0, legacy),
		listedConnection(t, f, "/s/2", 0, modern),
		listedConnection(t, f, "/s/3", 0, plain),
	}, nil)
	f.nm.EXPECT().GetPropertyActiveConnections().Return(nil, nil)
	expectPermissions(t, f, nil, nil)
	profiles, err := f.backend.ListConnectionProfiles()
	require.NoError(t, err)
	require.Len(t, profiles, 3)
	assert.Equal(t, "ctrl-1", profiles[0].Controller)
	assert.Equal(t, "bond", profiles[0].PortType)
	assert.Equal(t, "ctrl-2", profiles[1].Controller)
	assert.Equal(t, "bridge", profiles[1].PortType)
	assert.Empty(t, profiles[2].Controller)
	assert.Empty(t, profiles[2].PortType)
}

func TestUpdateConnectionSettings(t *testing.T) {
	ip := func(a, b, c, d byte) uint32 { return binary.NativeEndian.Uint32([]byte{a, b, c, d}) }
	method := map[string]dbus.Variant{"method": dbus.MakeVariant("auto")}
	legacy := map[string]dbus.Variant{"method": method["method"], "dns": dbus.MakeVariant([]uint32{ip(198, 51, 100, 1)})}
	modern := map[string]dbus.Variant{"method": method["method"], "dns": legacy["dns"], "dns-data": dbus.MakeVariant([]string{"198.51.100.1"})}
	dnsPatch := SettingsPatch{"ipv4": {"dns-data": []any{"192.0.2.53"}}}
	doT := map[string]dbus.Variant{"dns-data": dbus.MakeVariant([]string{"dns+tls://[2001:db8::1]"})}
	tests := []struct {
		name     string
		version  string
		stored   map[string]dbus.Variant
		v6       map[string]dbus.Variant
		patch    SettingsPatch
		err      string
		wantDNS  any
		wantData any
	}{
		{"other edit keeps dns-data and drops legacy dns", "", modern, nil, SettingsPatch{"connection": {"autoconnect-priority": float64(5)}}, "", nil, []string{"198.51.100.1"}},
		{"old NM gets legacy dns, DoT in another family does not block", "1.46.0", legacy, doT, dnsPatch, "", []uint32{ip(192, 0, 2, 53)}, nil},
		{"old NM rejects DoT before any write", "1.46.0", method, nil, SettingsPatch{"ipv4": {"dns-data": []any{"1.1.1.1#one.one.one.one"}}}, "ipv4.dns-data", nil, nil},
		{"old NM rejects IPv6 address under ipv4", "1.46.0", method, nil, SettingsPatch{"ipv4": {"dns-data": []any{"2001:db8::1"}}}, "ipv4.dns-data", nil, nil},
		{"new NM gets dns-data and no legacy dns", "1.58.1", legacy, nil, dnsPatch, "", nil, []string{"192.0.2.53"}},
		{"old NM rejects zoned IPv6", "1.46.0", method, method, SettingsPatch{"ipv6": {"dns-data": []any{"fe80::1%eth0"}}}, "ipv6.dns-data", nil, nil},
		{"old NM rejects v4-mapped IPv6", "1.46.0", method, method, SettingsPatch{"ipv6": {"dns-data": []any{"::ffff:192.0.2.1"}}}, "ipv6.dns-data", nil, nil},
		{"uuid is immutable", "", method, nil, SettingsPatch{"connection": {"uuid": "other"}}, "cannot be changed", nil, nil},
		{"type is immutable", "", method, nil, SettingsPatch{"connection": {"type": "802-11-wireless"}}, "cannot be changed", nil, nil},
		{"clear removes legacy and dns-data", "", modern, nil, SettingsPatch{"ipv4": {"dns-data": nil}}, "", nil, nil},
	}
	assert.ErrorContains(t, newEditorFixture(t).backend.UpdateConnectionSettings("u1", SettingsPatch{}, false), "no changes")
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f := newEditorFixture(t)
			if tt.version != "" {
				f.nm.EXPECT().GetPropertyVersion().Return(tt.version, nil).Once()
			}
			s := connSection("u1", "Wired", "802-3-ethernet", nil)
			s["ipv4"], s["ipv6"] = tt.stored, tt.v6
			obj := f.profile(t, "u1", "/s/1")
			expectGetSettings(obj, s)
			var got *nmSettings
			if tt.err == "" {
				got = captureUpdate2(obj, 0, nil)
			}
			err := f.backend.UpdateConnectionSettings("u1", tt.patch, false)
			if tt.err != "" {
				require.ErrorContains(t, err, tt.err)
				return
			}
			require.NoError(t, err)
			val := func(k string) any {
				if v, ok := (*got)["ipv4"][k]; ok {
					return v.Value()
				}
				return nil
			}
			assert.Equal(t, tt.wantDNS, val("dns"))
			assert.Equal(t, tt.wantData, val("dns-data"))
		})
	}
}

func pskProfile(obj *mock_dbus.MockBusObject) {
	s := connSection("u1", "Home", "802-11-wireless", map[string]dbus.Variant{"timestamp": dbus.MakeVariant(uint64(1700000000))})
	s["802-11-wireless-security"] = map[string]dbus.Variant{"key-mgmt": dbus.MakeVariant("wpa-psk")}
	s["ipv4"] = map[string]dbus.Variant{"method": dbus.MakeVariant("auto"), "dns": dbus.MakeVariant([]uint32{0x01010101}), "dns-data": dbus.MakeVariant([]string{"1.1.1.1"})}
	expectGetSettings(obj, s)
}

func expectPSKSecret(obj *mock_dbus.MockBusObject) {
	expectGetSecrets(obj, "802-11-wireless-security", nmSettings{"802-11-wireless-security": {"psk": dbus.MakeVariant("hunter22")}})
}

func captureAddConnection(obj *mock_dbus.MockBusObject, method string) *nmSettings {
	var got nmSettings
	obj.EXPECT().Call(method, dbus.Flags(0), mock.Anything).
		Run(func(_ string, _ dbus.Flags, args ...any) { got = args[0].(nmSettings) }).
		Return(&dbus.Call{Body: []any{dbus.ObjectPath("/s/new")}}).Once()
	return &got
}

func expectFlags(obj *mock_dbus.MockBusObject, flags uint32) {
	obj.EXPECT().GetProperty(nmConnFlagsProp).Return(dbus.MakeVariant(flags), nil).Once()
}

func expectPermissions(t *testing.T, f *editorFixture, perms map[string]string, err error) {
	call := &dbus.Call{Body: []any{perms}, Err: err}
	f.object(t, dbusNMPath).EXPECT().Call(gonetworkmanager.NetworkManagerGetPermissions, dbus.Flags(0)).Return(call).Once()
}

func TestDuplicateConnectionProfile(t *testing.T) {
	for _, tc := range []struct {
		flags  uint32
		method string
	}{{0, nmSettingsAddConnection}, {nmConnFlagUnsaved, nmSettingsAddConnectionUnsaved}} {
		f := newEditorFixture(t)
		obj := f.profile(t, "u1", "/s/1")
		expectFlags(obj, tc.flags)
		pskProfile(obj)
		expectPSKSecret(obj)
		got := captureAddConnection(f.object(t, nmSettingsPath), tc.method)
		uuid, err := f.backend.DuplicateConnectionProfile("u1", "Home copy")
		require.NoError(t, err)
		assert.NotEqual(t, "u1", uuid)
		assert.Equal(t, uuid, (*got)["connection"]["uuid"].Value())
		assert.Equal(t, "Home copy", (*got)["connection"]["id"].Value())
		assert.Equal(t, "hunter22", (*got)["802-11-wireless-security"]["psk"].Value())
		assert.NotContains(t, (*got)["connection"], "timestamp")
		assert.NotContains(t, (*got)["ipv4"], "dns")
	}
}

func TestConnectionProfileActions(t *testing.T) {
	f := newEditorFixture(t)
	conn := mock_gonetworkmanager.NewMockConnection(t)
	f.settings.EXPECT().GetConnectionByUUID("u1").Return(conn, nil)
	conn.EXPECT().Delete().Return(nil).Once()
	require.NoError(t, f.backend.DeleteConnectionProfile("u1"))
	dev := mock_gonetworkmanager.NewMockDevice(t)
	f.nm.EXPECT().GetDeviceByIpIface("wlan0").Return(dev, nil).Once()
	f.nm.EXPECT().ActivateConnection(conn, dev, (*dbus.Object)(nil)).Return(nil, nil).Once()
	require.NoError(t, f.backend.ActivateConnectionProfile("u1", "wlan0"))
	other, target := mock_gonetworkmanager.NewMockActiveConnection(t), mock_gonetworkmanager.NewMockActiveConnection(t)
	other.EXPECT().GetPropertyUUID().Return("u2", nil)
	target.EXPECT().GetPropertyUUID().Return("u1", nil)
	f.nm.EXPECT().GetPropertyActiveConnections().Return([]gonetworkmanager.ActiveConnection{other, target}, nil).Once()
	f.nm.EXPECT().DeactivateConnection(target).Return(nil).Once()
	require.NoError(t, f.backend.DeactivateConnectionProfile("u1"))
}

func TestGetConnectionSettings_SecretsOnRequest(t *testing.T) {
	psk := func(m map[string]map[string]any) any { return m["802-11-wireless-security"]["psk"] }
	f := newEditorFixture(t)
	obj := f.profile(t, "u1", "/s/1")
	pskProfile(obj)
	got, err := f.backend.GetConnectionSettings("u1", false)
	require.NoError(t, err)
	assert.Nil(t, psk(got))
	pskProfile(obj)
	expectPSKSecret(obj)
	got, err = f.backend.GetConnectionSettings("u1", true)
	require.NoError(t, err)
	assert.Equal(t, "hunter22", psk(got))
}

func TestAddConnectionProfile(t *testing.T) {
	f := newEditorFixture(t)
	_, err := f.backend.AddConnectionProfile(SettingsPatch{"connection": {"id": "x"}}, true)
	require.ErrorContains(t, err, "connection.type")
	got := captureAddConnection(f.object(t, nmSettingsPath), nmSettingsAddConnection)
	f.nm.EXPECT().GetPropertyVersion().Return("1.42.4", nil).Once()
	uuid, err := f.backend.AddConnectionProfile(SettingsPatch{
		"connection": {"id": "Lab", "type": "802-3-ethernet"},
		"ipv6":       {"method": "manual", "dns-data": []any{"2001:db8::53"}},
	}, true)
	require.NoError(t, err)
	assert.Equal(t, uuid, (*got)["connection"]["uuid"].Value())
	assert.Equal(t, [][]byte{netip.MustParseAddr("2001:db8::53").AsSlice()}, (*got)["ipv6"]["dns"].Value())
	assert.NotContains(t, (*got)["ipv6"], "dns-data")

	got = captureAddConnection(f.object(t, nmSettingsPath), nmSettingsAddConnectionUnsaved)
	uuid, err = f.backend.AddConnectionProfile(SettingsPatch{"connection": {"id": "Tmp", "type": "802-3-ethernet", "uuid": "fixed-uuid"}}, false)
	require.NoError(t, err)
	assert.Equal(t, "fixed-uuid", uuid)
	assert.Equal(t, "fixed-uuid", (*got)["connection"]["uuid"].Value())
}

func TestFirewallZones(t *testing.T) {
	dbusErr := func(name string) dbus.Call {
		return dbus.Call{Err: dbus.Error{Name: "org.freedesktop.DBus.Error." + name}}
	}
	for _, tc := range []struct {
		call  dbus.Call
		zones []string
		err   bool
	}{
		{dbusErr("ServiceUnknown"), []string{}, false},
		{dbus.Call{Body: []any{[]string{"public", "home"}}}, []string{"home", "public"}, false},
		{dbusErr("AccessDenied"), nil, true},
	} {
		f := newEditorFixture(t)
		fw := mock_dbus.NewMockBusObject(t)
		f.backend.firewalldObjectFn = func() dbus.BusObject { return fw }
		fw.EXPECT().Call(firewalldGetZones, dbus.Flags(0)).Return(&tc.call).Once()
		zones, err := f.backend.FirewallZones()
		assert.Equal(t, tc.err, err != nil)
		assert.Equal(t, tc.zones, zones)
	}
}

func TestExportConnectionProfile_WireGuard(t *testing.T) {
	export := func(t *testing.T, path string) error {
		f := newEditorFixture(t)
		s := connSection("u1", "wg", "wireguard", nil)
		s["wireguard"] = map[string]dbus.Variant{"private-key-flags": dbus.MakeVariant(uint32(0)), "peers": dbus.MakeVariant([]map[string]dbus.Variant{
			{"public-key": dbus.MakeVariant("PUB1"), "allowed-ips": dbus.MakeVariant([]string{"10.0.0.0/24"})},
		})}
		obj := f.profile(t, "u1", "/s/1")
		expectGetSettings(obj, s)
		expectGetSecrets(obj, "wireguard", nmSettings{"wireguard": {"private-key": dbus.MakeVariant("PRIV")}})
		return f.backend.ExportConnectionProfile("u1", path)
	}
	dir := t.TempDir()
	path := filepath.Join(dir, "wg0.conf")
	require.NoError(t, os.WriteFile(path, []byte(strings.Repeat("old", 100)), 0o644))
	require.NoError(t, os.Chmod(path, 0o644))
	require.NoError(t, export(t, path))
	info, err := os.Stat(path)
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0o600), info.Mode().Perm(), "existing 0644 file is tightened")
	content, err := os.ReadFile(path)
	require.NoError(t, err)
	assert.Equal(t, "[Interface]\nPrivateKey = PRIV\n\n[Peer]\nPublicKey = PUB1\nAllowedIPs = 10.0.0.0/24\n", string(content))
	link := filepath.Join(dir, "link.conf")
	require.NoError(t, os.Symlink(filepath.Join(dir, "target"), link))
	assert.Error(t, export(t, link))
	assert.NoFileExists(t, filepath.Join(dir, "target"))
}

func TestExportConnectionProfile_VPNAndRejections(t *testing.T) {
	var argv []string
	var runErr error
	stdout, stderr := "remote vpn.example.com\n", ""
	orig := nmcliRun
	t.Cleanup(func() { nmcliRun = orig })
	nmcliRun = func(args ...string) ([]byte, []byte, error) {
		argv = args
		return []byte(stdout), []byte(stderr), runErr
	}
	profile := func(typ string) *NetworkManagerBackend {
		f := newEditorFixture(t)
		expectGetSettings(f.profile(t, "u1", "/s/1"), connSection("u1", "x", typ, nil))
		return f.backend
	}
	path := filepath.Join(t.TempDir(), "v.ovpn")
	require.NoError(t, profile("vpn").ExportConnectionProfile("u1", path))
	assert.Equal(t, []string{"connection", "export", "uuid", "u1"}, argv)
	written, err := os.ReadFile(path)
	require.NoError(t, err)
	assert.Equal(t, stdout, string(written))
	runErr, stdout, stderr = errors.New("exit status 1"), "", "export not supported\n"
	missing := filepath.Join(t.TempDir(), "x.ovpn")
	assert.ErrorContains(t, profile("vpn").ExportConnectionProfile("u1", missing), "nmcli: export not supported")
	assert.NoFileExists(t, missing)
	assert.ErrorContains(t, profile("802-3-ethernet").ExportConnectionProfile("u1", missing), "VPN and WireGuard")
	assert.Error(t, newEditorFixture(t).backend.ExportConnectionProfile("u1", "rel.conf"))
}
