package network

import (
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

const hwEnp6s0, hwEnp5s0 = "AA:BB:CC:00:00:06", "AA:BB:CC:00:00:05"

type ethernetFixture struct {
	backend  *NetworkManagerBackend
	nm       *mock_gonetworkmanager.MockNetworkManager
	settings *mock_gonetworkmanager.MockSettings
}

func newEthernetFixture(t *testing.T, profiles ...gonetworkmanager.Connection) *ethernetFixture {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockNM.EXPECT().GetPropertyActiveConnections().Return(nil, nil).Maybe()
	mockNM.EXPECT().GetPropertyPrimaryConnection().Return(nil, nil).Maybe()
	settings := mock_gonetworkmanager.NewMockSettings(t)
	settings.EXPECT().ListConnections().Return(profiles, nil).Maybe()
	backend, err := NewNetworkManagerBackend(mockNM)
	require.NoError(t, err)
	backend.settings = settings
	return &ethernetFixture{backend, mockNM, settings}
}

func (f *ethernetFixture) addDevice(t *testing.T, name, hw string, state gonetworkmanager.NmDeviceState, active gonetworkmanager.ActiveConnection) *mock_gonetworkmanager.MockDevice {
	dev := mock_gonetworkmanager.NewMockDevice(t)
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
	ac.EXPECT().GetPropertyUUID().Return(uuid, nil).Maybe()
	return ac
}

func mockWiredProfile(t *testing.T, uuid, ifaceName string, mac []byte) *mock_gonetworkmanager.MockConnection {
	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetPath().Return(dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/" + uuid)).Maybe()
	conn.EXPECT().GetSettings().Return(gonetworkmanager.ConnectionSettings{"802-3-ethernet": {"mac-address": mac},
		"connection": {"id": "Wired " + uuid, "uuid": uuid, "type": "802-3-ethernet", "interface-name": ifaceName}}, nil).Maybe()
	return conn
}

func isAutoConnection(c gonetworkmanager.Connection) bool { return c != nil && c.GetPath() == "/" }

func TestNetworkManagerBackend_EthernetConnectDisconnectPerDevice(t *testing.T) {
	tests := []struct {
		name, iface, want string
		connect           bool
	}{
		{"disconnect deactivates the device", "", "disconnect", false},
		{"connect lets NM pick a fitting profile", "enp5s0", "auto", true},
		{"connect creates a profile when none fits", "enp6s0", "create", true},
		{"connect to an unknown device fails", "", "missing", true},
		{"disconnect with nothing active is a no-op", "", "idle", false},
	}
	for _, tt := range tests {
		f := newEthernetFixture(t, mockWiredProfile(t, "wired-a", tt.iface, nil))
		var active gonetworkmanager.ActiveConnection = activeConnection(t, "wired-a")
		if tt.want == "idle" {
			active = nil
		}
		dev := f.addDevice(t, "enp5s0", hwEnp5s0, gonetworkmanager.NmDeviceStateDisconnected, active)
		switch tt.want {
		case "missing":
			assert.ErrorContains(t, f.backend.ConnectEthernetDevice("nope"), "not found", tt.name)
			continue
		case "disconnect":
			dev.EXPECT().Disconnect().Return(nil).Once()
		case "auto":
			f.nm.EXPECT().ActivateConnection(mock.MatchedBy(isAutoConnection), dev, (*dbus.Object)(nil)).Return(nil, nil).Once()
		case "create":
			f.nm.EXPECT().AddAndActivateConnection(mock.Anything, dev).Return(nil, nil).Once()
		}
		act := f.backend.DisconnectEthernetDevice
		if tt.connect {
			act = f.backend.ConnectEthernetDevice
		}
		assert.NoError(t, act("enp5s0"), tt.name)
	}
}

func TestNetworkManagerBackend_EthernetRefreshSortedWithProfileFit(t *testing.T) {
	perm := []byte{0xaa, 0xbb, 0xcc, 0, 0, 5}
	for _, scanFirst := range []bool{false, true} {
		f := newEthernetFixture(t, mockWiredProfile(t, "wired-a", "enp6s0", nil), mockWiredProfile(t, "wired-b", "", perm), mockWiredProfile(t, "wired-c", "enp6s0", perm))
		f.addDevice(t, "enp6s0", hwEnp6s0, gonetworkmanager.NmDeviceStateActivated, activeConnection(t, "wired-a"))
		spoofed := f.addDevice(t, "enp5s0", "02:00:00:00:00:99", gonetworkmanager.NmDeviceStateUnavailable, nil)
		f.addDevice(t, "enp4s0", "AA:BB:CC:00:00:04", gonetworkmanager.NmDeviceStateUnavailable, nil)
		f.backend.setEthernetDeviceInfo("enp5s0", &ethernetDeviceInfo{device: spoofed, name: "enp5s0", hwAddress: "02:00:00:00:00:99", permHwAddress: hwEnp5s0})
		if scanFirst {
			_, _ = f.backend.listEthernetConnections()
		}
		f.backend.updateAllEthernetDevices()
		_, _ = f.backend.listEthernetConnections()
		f.backend.updateAllEthernetDevices()
		devices := f.backend.GetEthernetDevices()
		require.Len(t, devices, 3)
		assert.Equal(t, "enp4s0", devices[0].Name)
		assert.Equal(t, []string{}, devices[0].ProfileUUIDs)
		assert.Equal(t, []string{"wired-b"}, devices[1].ProfileUUIDs)
		assert.Equal(t, []string{"wired-a"}, devices[2].ProfileUUIDs)
	}
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
	wiredA := mockWiredProfile(t, "wired-a", "", nil)
	f := newEthernetFixture(t,
		mockPortProfile(t, "port-legacy", "master"),
		mockPortProfile(t, "port-modern", "controller"),
		wiredA,
	)
	dev := f.addDevice(t, "enp5s0", hwEnp5s0, gonetworkmanager.NmDeviceStateDisconnected, nil)

	f.backend.updateAllEthernetDevices()
	wired, err := f.backend.listEthernetConnections()
	require.NoError(t, err)
	assert.Len(t, wired, 3)
	assert.Equal(t, []string{"wired-a"}, f.backend.GetEthernetDevices()[0].ProfileUUIDs)

	f.nm.EXPECT().ActivateConnection(mock.MatchedBy(isAutoConnection), dev, (*dbus.Object)(nil)).Return(nil, nil).Once()
	require.NoError(t, f.backend.ConnectEthernetDevice("enp5s0"))
	f.settings.EXPECT().GetConnectionByUUID("wired-a").Return(wiredA, nil).Twice()
	f.nm.EXPECT().ActivateConnection(wiredA, dev, (*dbus.Object)(nil)).Return(nil, nil).Once()
	f.nm.EXPECT().ActivateConnection(wiredA, nil, (*dbus.Object)(nil)).Return(nil, nil).Once()
	require.NoError(t, f.backend.ActivateWiredConnection("wired-a", "enp5s0"))
	require.NoError(t, f.backend.ActivateWiredConnection("wired-a", ""))
	assert.ErrorContains(t, f.backend.ActivateWiredConnection("wired-a", "enp9s0"), "not found")
}
