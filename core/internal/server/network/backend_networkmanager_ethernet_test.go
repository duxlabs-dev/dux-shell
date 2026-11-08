package network

import (
	"encoding/json"
	"net"
	"testing"

	"github.com/Wifx/gonetworkmanager/v2"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestNetworkManagerBackend_ConnectEthernet_NoDevice(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.ethernetDevice = nil
	err = backend.ConnectEthernet()
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "no ethernet device available")
}

func TestNetworkManagerBackend_DisconnectEthernetDevice_NotFound(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	err = backend.DisconnectEthernetDevice("nonexistent")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not found")
}

const (
	hwEnp6s0 = "AA:BB:CC:00:00:06"
	hwEnp5s0 = "AA:BB:CC:00:00:05"
)

func TestProfileFitsEthernetDevice(t *testing.T) {
	mac := func(s string) []byte {
		hw, err := net.ParseMAC(s)
		require.NoError(t, err)
		return hw
	}

	tests := []struct {
		name      string
		ifaceName string
		mac       []byte
		fits6     bool
		fits5     bool
		isPort    bool
	}{
		{name: "unbound", fits6: true, fits5: true},
		{name: "interface-name", ifaceName: "enp6s0", fits6: true},
		{name: "mac, lower case", mac: mac("aa:bb:cc:00:00:05"), fits5: true},
		{name: "interface and conflicting mac", ifaceName: "enp6s0", mac: mac(hwEnp5s0)},
		{name: "unbound bond or bridge port", isPort: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := wiredProfile{ifaceName: tt.ifaceName, mac: tt.mac, isPort: tt.isPort}
			assert.Equal(t, tt.fits6, p.fits("enp6s0", hwEnp6s0))
			assert.Equal(t, tt.fits5, p.fits("enp5s0", hwEnp5s0))
		})
	}
}

type ethernetFixture struct {
	backend  *NetworkManagerBackend
	nm       *mock_gonetworkmanager.MockNetworkManager
	settings *mock_gonetworkmanager.MockSettings
}

// newEthernetFixture allows the read-only calls a post-action state refresh makes.
func newEthernetFixture(t *testing.T, profiles ...gonetworkmanager.Connection) *ethernetFixture {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockNM.EXPECT().GetPropertyActiveConnections().Return(nil, nil).Maybe()
	mockNM.EXPECT().GetPropertyPrimaryConnection().Return(nil, nil).Maybe()

	mockSettings := mock_gonetworkmanager.NewMockSettings(t)
	mockSettings.EXPECT().ListConnections().Return(profiles, nil).Maybe()

	backend, err := NewNetworkManagerBackend(mockNM)
	require.NoError(t, err)
	backend.settings = mockSettings

	return &ethernetFixture{backend: backend, nm: mockNM, settings: mockSettings}
}

func (f *ethernetFixture) addDevice(t *testing.T, name, hw string, state gonetworkmanager.NmDeviceState, active gonetworkmanager.ActiveConnection) *mock_gonetworkmanager.MockDevice {
	dev := mock_gonetworkmanager.NewMockDevice(t)
	dev.EXPECT().GetPath().Return(dbus.ObjectPath("/org/freedesktop/NetworkManager/Devices/" + name)).Maybe()
	dev.EXPECT().GetPropertyInterface().Return(name, nil).Maybe()
	dev.EXPECT().GetPropertyState().Return(state, nil).Maybe()
	dev.EXPECT().GetPropertyDriver().Return("r8169", nil).Maybe()
	dev.EXPECT().GetPropertyIP4Config().Return(nil, nil).Maybe()
	dev.EXPECT().GetPropertyActiveConnection().Return(active, nil).Maybe()

	f.backend.setEthernetDeviceInfo(name, &ethernetDeviceInfo{device: dev, name: name, hwAddress: hw})
	if f.backend.ethernetDevice == nil {
		f.backend.ethernetDevice = dev
	}
	return dev
}

func activeConnection(t *testing.T, uuid string) *mock_gonetworkmanager.MockActiveConnection {
	ac := mock_gonetworkmanager.NewMockActiveConnection(t)
	ac.EXPECT().GetPath().Return(dbus.ObjectPath("/org/freedesktop/NetworkManager/ActiveConnection/" + uuid)).Maybe()
	ac.EXPECT().GetPropertyUUID().Return(uuid, nil).Maybe()
	return ac
}

func mockWiredProfile(t *testing.T, uuid, ifaceName string, mac []byte) *mock_gonetworkmanager.MockConnection {
	conn := mock_gonetworkmanager.NewMockConnection(t)
	ethernet := map[string]any{}
	if mac != nil {
		ethernet["mac-address"] = mac
	}
	conn.EXPECT().GetPath().Return(dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/" + uuid)).Maybe()
	conn.EXPECT().GetSettings().Return(gonetworkmanager.ConnectionSettings{
		"connection":     {"id": "Wired " + uuid, "uuid": uuid, "type": "802-3-ethernet", "interface-name": ifaceName},
		"802-3-ethernet": ethernet,
	}, nil).Maybe()
	return conn
}

func isAutoConnection(c gonetworkmanager.Connection) bool {
	return c != nil && c.GetPath() == "/"
}

func TestNetworkManagerBackend_DisconnectEthernetDevice_DeactivatesActiveConnection(t *testing.T) {
	f := newEthernetFixture(t)
	ac := activeConnection(t, "wired-a")
	dev := f.addDevice(t, "enp6s0", hwEnp6s0, gonetworkmanager.NmDeviceStateActivated, ac)
	dev.EXPECT().Disconnect().Return(nil).Once()

	require.NoError(t, f.backend.DisconnectEthernetDevice("enp6s0"))
}

func TestNetworkManagerBackend_DisconnectEthernetDevice_NoActiveConnection(t *testing.T) {
	f := newEthernetFixture(t)
	f.addDevice(t, "enp5s0", hwEnp5s0, gonetworkmanager.NmDeviceStateUnavailable, nil)

	require.NoError(t, f.backend.DisconnectEthernetDevice("enp5s0"))
}

func TestNetworkManagerBackend_ConnectEthernetDevice_LetsNMPickProfile(t *testing.T) {
	f := newEthernetFixture(t, mockWiredProfile(t, "wired-a", "enp6s0", nil))
	dev := f.addDevice(t, "enp6s0", hwEnp6s0, gonetworkmanager.NmDeviceStateDisconnected, nil)
	f.nm.EXPECT().ActivateConnection(mock.MatchedBy(isAutoConnection), dev, (*dbus.Object)(nil)).Return(nil, nil).Once()

	require.NoError(t, f.backend.ConnectEthernetDevice("enp6s0"))
}

func TestNetworkManagerBackend_ConnectEthernetDevice_CreatesProfileWhenNoneFits(t *testing.T) {
	f := newEthernetFixture(t, mockWiredProfile(t, "wired-a", "enp6s0", nil))
	dev := f.addDevice(t, "enp5s0", hwEnp5s0, gonetworkmanager.NmDeviceStateDisconnected, nil)
	f.nm.EXPECT().AddAndActivateConnection(mock.Anything, dev).Return(nil, nil).Once()

	require.NoError(t, f.backend.ConnectEthernetDevice("enp5s0"))
}

func TestNetworkManagerBackend_ConnectEthernetDevice_UnknownDevice(t *testing.T) {
	f := newEthernetFixture(t)

	err := f.backend.ConnectEthernetDevice("enp9s0")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "ethernet device enp9s0 not found")
}

func TestNetworkManagerBackend_ActivateWiredConnection_Device(t *testing.T) {
	profile := mockWiredProfile(t, "wired-a", "", nil)

	t.Run("empty device lets NM pick", func(t *testing.T) {
		f := newEthernetFixture(t, profile)
		f.addDevice(t, "enp5s0", hwEnp5s0, gonetworkmanager.NmDeviceStateDisconnected, nil)
		f.settings.EXPECT().GetConnectionByUUID("wired-a").Return(profile, nil)
		f.nm.EXPECT().ActivateConnection(profile, gonetworkmanager.Device(nil), (*dbus.Object)(nil)).Return(nil, nil).Once()

		require.NoError(t, f.backend.ActivateWiredConnection("wired-a", ""))
	})

	t.Run("named device", func(t *testing.T) {
		f := newEthernetFixture(t, profile)
		dev := f.addDevice(t, "enp5s0", hwEnp5s0, gonetworkmanager.NmDeviceStateDisconnected, nil)
		f.settings.EXPECT().GetConnectionByUUID("wired-a").Return(profile, nil)
		f.nm.EXPECT().ActivateConnection(profile, dev, (*dbus.Object)(nil)).Return(nil, nil).Once()

		require.NoError(t, f.backend.ActivateWiredConnection("wired-a", "enp5s0"))
	})
}

func TestNetworkManagerBackend_EthernetRefresh_SortedWithProfileFit(t *testing.T) {
	f := newEthernetFixture(t,
		mockWiredProfile(t, "wired-a", "enp6s0", nil),
		mockWiredProfile(t, "wired-b", "", nil),
	)
	f.addDevice(t, "enp6s0", hwEnp6s0, gonetworkmanager.NmDeviceStateActivated, activeConnection(t, "wired-a"))
	f.addDevice(t, "enp5s0", hwEnp5s0, gonetworkmanager.NmDeviceStateUnavailable, nil)

	f.backend.updateAllEthernetDevices()
	_, err := f.backend.listEthernetConnections()
	require.NoError(t, err)
	// A device refresh after the profile scan must keep the fit.
	f.backend.updateAllEthernetDevices()

	devices := f.backend.GetEthernetDevices()
	require.Len(t, devices, 2)
	assert.Equal(t, "enp5s0", devices[0].Name)
	assert.Equal(t, []string{"wired-b"}, devices[0].ProfileUUIDs)
	assert.Empty(t, devices[0].ConnectionUUID)
	assert.Equal(t, "enp6s0", devices[1].Name)
	assert.Equal(t, []string{"wired-a", "wired-b"}, devices[1].ProfileUUIDs)
	assert.Equal(t, "wired-a", devices[1].ConnectionUUID)

	wired := f.backend.state.WiredConnections
	require.Len(t, wired, 2)
	assert.Equal(t, "enp6s0", wired[0].Device)
	assert.Empty(t, wired[1].Device)
}

func TestNetworkManagerBackend_EthernetProfileFitSurvivesStartupOrder(t *testing.T) {
	f := newEthernetFixture(t, mockWiredProfile(t, "wired-a", "", nil))
	f.addDevice(t, "enp5s0", hwEnp5s0, gonetworkmanager.NmDeviceStateDisconnected, nil)

	// Initialize scans profiles before the device list exists.
	_, err := f.backend.listEthernetConnections()
	require.NoError(t, err)
	f.backend.updateAllEthernetDevices()

	assert.Equal(t, []string{"wired-a"}, f.backend.GetEthernetDevices()[0].ProfileUUIDs)
}

func TestNetworkManagerBackend_EthernetProfileFitUsesPermanentMAC(t *testing.T) {
	const spoofed = "02:00:00:00:00:99"
	perm, err := net.ParseMAC(hwEnp6s0)
	require.NoError(t, err)
	f := newEthernetFixture(t, mockWiredProfile(t, "wired-a", "", perm))
	dev := f.addDevice(t, "enp6s0", spoofed, gonetworkmanager.NmDeviceStateDisconnected, nil)
	f.backend.setEthernetDeviceInfo("enp6s0", &ethernetDeviceInfo{device: dev, name: "enp6s0", hwAddress: spoofed, permHwAddress: hwEnp6s0})

	f.backend.updateAllEthernetDevices()
	_, err = f.backend.listEthernetConnections()
	require.NoError(t, err)
	assert.Equal(t, []string{"wired-a"}, f.backend.GetEthernetDevices()[0].ProfileUUIDs)

	f.nm.EXPECT().ActivateConnection(mock.MatchedBy(isAutoConnection), dev, (*dbus.Object)(nil)).Return(nil, nil).Once()
	require.NoError(t, f.backend.ConnectEthernetDevice("enp6s0"))
}

func TestNetworkManagerBackend_EthernetProfileUUIDsSerializeAsEmptyList(t *testing.T) {
	f := newEthernetFixture(t, mockWiredProfile(t, "wired-a", "enp6s0", nil))
	f.addDevice(t, "enp5s0", hwEnp5s0, gonetworkmanager.NmDeviceStateDisconnected, nil)

	f.backend.updateAllEthernetDevices()
	raw, err := json.Marshal(f.backend.GetEthernetDevices())
	require.NoError(t, err)
	assert.Contains(t, string(raw), `"profileUuids":[]`)

	_, err = f.backend.listEthernetConnections()
	require.NoError(t, err)
	raw, err = json.Marshal(f.backend.GetEthernetDevices())
	require.NoError(t, err)
	assert.Contains(t, string(raw), `"profileUuids":[]`)
}

func mockPortProfile(t *testing.T, uuid, key string) *mock_gonetworkmanager.MockConnection {
	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetPath().Return(dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/" + uuid)).Maybe()
	conn.EXPECT().GetSettings().Return(gonetworkmanager.ConnectionSettings{
		"connection":     {"id": uuid, "uuid": uuid, "type": "802-3-ethernet", key: "ctrl-uuid"},
		"802-3-ethernet": {},
	}, nil).Maybe()
	return conn
}

func TestNetworkManagerBackend_PortProfilesDoNotFitAdapter(t *testing.T) {
	f := newEthernetFixture(t,
		mockPortProfile(t, "port-legacy", "master"),
		mockPortProfile(t, "port-modern", "controller"),
		mockWiredProfile(t, "wired-a", "", nil),
	)
	dev := f.addDevice(t, "enp5s0", hwEnp5s0, gonetworkmanager.NmDeviceStateDisconnected, nil)

	f.backend.updateAllEthernetDevices()
	wired, err := f.backend.listEthernetConnections()
	require.NoError(t, err)
	assert.Len(t, wired, 3)
	assert.Equal(t, []string{"wired-a"}, f.backend.GetEthernetDevices()[0].ProfileUUIDs)

	f.nm.EXPECT().ActivateConnection(mock.MatchedBy(isAutoConnection), dev, (*dbus.Object)(nil)).Return(nil, nil).Once()
	require.NoError(t, f.backend.ConnectEthernetDevice("enp5s0"))
}
