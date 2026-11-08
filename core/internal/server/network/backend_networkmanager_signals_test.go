package network

import (
	"sync/atomic"
	"testing"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
)

// emptySettingsMock keeps tests hermetic: without it, networkManagerSettings()
// falls back to the real system D-Bus and picks up whatever profiles exist on
// the developer's machine.
func emptySettingsMock(t *testing.T) *mock_gonetworkmanager.MockSettings {
	mockSettings := mock_gonetworkmanager.NewMockSettings(t)
	mockSettings.EXPECT().ListConnections().Return(nil, nil).Maybe()
	return mockSettings
}

func TestNetworkManagerBackend_ProfilesRevisionBumps(t *testing.T) {
	backend, _ := NewNetworkManagerBackend(mock_gonetworkmanager.NewMockNetworkManager(t))
	for _, n := range []string{"Settings.NewConnection", "Settings.ConnectionRemoved", "Settings.Connection.Updated"} {
		before := backend.state.ConnectionProfilesRevision
		backend.handleDBusSignal(&dbus.Signal{Name: "org.freedesktop.NetworkManager." + n})
		assert.Equal(t, before+1, backend.state.ConnectionProfilesRevision, n)
	}
}

func TestNetworkManagerBackend_HandleDBusSignal_InvalidBody(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	sig := &dbus.Signal{
		Name: "org.freedesktop.DBus.Properties.PropertiesChanged",
		Body: []any{"only-one-element"},
	}

	assert.NotPanics(t, func() {
		backend.handleDBusSignal(sig)
	})
}

func TestNetworkManagerBackend_HandleDBusSignal_InvalidInterface(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	sig := &dbus.Signal{
		Name: "org.freedesktop.DBus.Properties.PropertiesChanged",
		Body: []any{123, map[string]dbus.Variant{}},
	}

	assert.NotPanics(t, func() {
		backend.handleDBusSignal(sig)
	})
}

func TestNetworkManagerBackend_HandleDBusSignal_InvalidChanges(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	sig := &dbus.Signal{
		Name: "org.freedesktop.DBus.Properties.PropertiesChanged",
		Body: []any{dbusNMInterface, "not-a-map"},
	}

	assert.NotPanics(t, func() {
		backend.handleDBusSignal(sig)
	})
}

func TestNetworkManagerBackend_HandleDeviceChange_UnmanagedRefreshesHotspotState(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockWiFi := mock_gonetworkmanager.NewMockDeviceWireless(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)
	backend.settings = emptySettingsMock(t)
	backend.wifiDevices = map[string]*wifiDeviceInfo{
		"wlan0": {device: mockWiFi, wireless: mockWiFi, name: "wlan0"},
	}
	backend.state.HotspotAvailable = true

	stateChangeCalls := 0
	backend.onStateChange = func() {
		stateChangeCalls++
	}

	mockWiFi.EXPECT().GetPropertyState().Return(gonetworkmanager.NmDeviceStateUnavailable, nil)
	mockWiFi.EXPECT().GetAccessPoints().Return([]gonetworkmanager.AccessPoint{}, nil)
	mockWiFi.EXPECT().GetPropertyManaged().Return(false, nil)

	changes := map[string]dbus.Variant{
		"Managed": dbus.MakeVariant(false),
	}
	backend.handleDeviceChange("/org/freedesktop/NetworkManager/Devices/1", changes)

	assert.Equal(t, 1, stateChangeCalls, "unmanaged transition must notify subscribers")

	backend.stateMutex.RLock()
	defer backend.stateMutex.RUnlock()
	assert.False(t, backend.state.HotspotAvailable, "availability must be recomputed when the only AP-capable radio becomes unmanaged")
}

func TestNetworkManagerBackend_HandleWiFiChange_CoalescesAccessPointBurst(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockWiFi := mock_gonetworkmanager.NewMockDeviceWireless(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)
	backend.settings = emptySettingsMock(t)
	backend.wifiDevice = mockWiFi
	backend.wifiDev = mockWiFi

	var stateChangeCalls atomic.Int32
	backend.onStateChange = func() {
		stateChangeCalls.Add(1)
	}

	mockWiFi.EXPECT().GetAccessPoints().Return([]gonetworkmanager.AccessPoint{}, nil).Once()

	changes := map[string]dbus.Variant{
		"AccessPoints": dbus.MakeVariant([]dbus.ObjectPath{}),
	}
	for range 5 {
		backend.handleWiFiChange(changes)
	}
	assert.Zero(t, stateChangeCalls.Load(), "the list must not be rebuilt per access point")

	assert.Eventually(t, func() bool {
		return stateChangeCalls.Load() == 1
	}, 4*wifiNetworksUpdateDelay, 10*time.Millisecond)
}

func TestNetworkManagerBackend_HandleDBusSignal_ConnectionRemovedRefreshesWiredConnections(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockNM.EXPECT().GetPropertyActiveConnections().Return([]gonetworkmanager.ActiveConnection{}, nil).Maybe()

	remaining := mock_gonetworkmanager.NewMockConnection(t)
	remaining.EXPECT().GetPath().Return(dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/1")).Maybe()
	remaining.EXPECT().GetSettings().Return(gonetworkmanager.ConnectionSettings{
		"connection": {
			"id":   "Wired connection 1",
			"uuid": "uuid-1",
			"type": "802-3-ethernet",
		},
	}, nil).Maybe()

	mockSettings := mock_gonetworkmanager.NewMockSettings(t)
	mockSettings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{remaining}, nil).Maybe()

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)
	backend.settings = mockSettings
	dev := mock_gonetworkmanager.NewMockDevice(t)
	dev.EXPECT().GetPropertyActiveConnection().Return(nil, nil).Maybe()
	backend.ethernetDevices["enp5s0"] = &ethernetDeviceInfo{device: dev, name: "enp5s0"}

	backend.stateMutex.Lock()
	backend.state.WiredConnections = []WiredConnection{
		{ID: "Wired connection 1", UUID: "uuid-1", Type: "802-3-ethernet"},
		{ID: "Wired connection 2", UUID: "uuid-2", Type: "802-3-ethernet"},
	}
	backend.stateMutex.Unlock()

	backend.handleDBusSignal(&dbus.Signal{
		Name: "org.freedesktop.NetworkManager.Settings.ConnectionRemoved",
		Body: []any{dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/2")},
	})

	backend.stateMutex.RLock()
	defer backend.stateMutex.RUnlock()
	assert.Len(t, backend.state.WiredConnections, 1)
	assert.Equal(t, "uuid-1", backend.state.WiredConnections[0].UUID)
}

func TestNetworkManagerBackend_ListEthernetConnections_InvalidSettingsHandle(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)
	backend.settings = "not a settings handle"
	backend.ethernetDevice = mock_gonetworkmanager.NewMockDevice(t)

	assert.NotPanics(t, func() {
		_, err = backend.listEthernetConnections()
	})
	assert.Error(t, err)
}

func nameOwnerChanged(name, oldOwner, newOwner string) *dbus.Signal {
	return &dbus.Signal{
		Name: "org.freedesktop.DBus.NameOwnerChanged",
		Body: []any{name, oldOwner, newOwner},
	}
}

// Replays the order captured on a real "systemctl restart NetworkManager":
// DeviceAdded arrives ~180 ms before the daemon owns org.freedesktop.NetworkManager,
// so the device lookup fails; the ethernet device must come back once the name
// has a new owner.
func TestNetworkManagerBackend_EthernetDeviceSurvivesNetworkManagerRestart(t *testing.T) {
	const path = dbus.ObjectPath("/org/freedesktop/NetworkManager/Devices/16")

	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockNM.EXPECT().GetPropertyActiveConnections().Return(nil, nil).Maybe()
	mockNM.EXPECT().GetPropertyPrimaryConnection().Return(nil, nil).Maybe()

	dev := mock_gonetworkmanager.NewMockDevice(t)
	dev.EXPECT().GetPath().Return(path).Maybe()
	dev.EXPECT().GetPropertyDeviceType().Return(gonetworkmanager.NmDeviceTypeEthernet, nil)
	dev.EXPECT().GetPropertyManaged().Return(true, nil)
	dev.EXPECT().GetPropertyInterface().Return("enp5s0", nil)
	dev.EXPECT().GetPropertyState().Return(gonetworkmanager.NmDeviceStateActivated, nil).Maybe()
	dev.EXPECT().GetPropertyDriver().Return("r8169", nil).Maybe()
	dev.EXPECT().GetPropertyIP4Config().Return(nil, nil).Maybe()
	dev.EXPECT().GetPropertyActiveConnection().Return(nil, nil).Maybe()

	wired := mock_gonetworkmanager.NewMockDeviceWired(t)
	wired.EXPECT().GetPropertyHwAddress().Return("94:e2:3c:c1:8d:ba", nil)
	wired.EXPECT().GetPropertyPermHwAddress().Return("94:e2:3c:c1:8d:ba", nil)
	wired.EXPECT().GetPropertySpeed().Return(uint32(1000), nil).Maybe()

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)
	backend.settings = emptySettingsMock(t)

	nameOwned := false
	backend.newDevice = func(p dbus.ObjectPath) (gonetworkmanager.Device, error) {
		if !nameOwned {
			return nil, dbus.Error{Name: "org.freedesktop.DBus.Error.ServiceUnknown"}
		}
		assert.Equal(t, path, p)
		return dev, nil
	}
	backend.newDeviceWired = func(dbus.ObjectPath) (gonetworkmanager.DeviceWired, error) { return wired, nil }

	backend.handleDBusSignal(&dbus.Signal{Name: "org.freedesktop.NetworkManager.DeviceAdded", Body: []any{path}})
	backend.handleDBusSignal(nameOwnerChanged("org.freedesktop.NetworkManager", ":1.10928", ""))
	assert.NotContains(t, backend.trackedDevicePaths(), path, "lookup during the restart window must fail")

	nameOwned = true
	mockNM.EXPECT().GetDevices().Return([]gonetworkmanager.Device{dev}, nil).Once()
	backend.handleDBusSignal(nameOwnerChanged("org.freedesktop.NetworkManager", "", ":1.10987"))

	assert.Contains(t, backend.trackedDevicePaths(), path)
	state, err := backend.GetCurrentState()
	assert.NoError(t, err)
	assert.Equal(t, "enp5s0", state.EthernetDevice)
	assert.True(t, state.EthernetConnected)
}

func TestNetworkManagerBackend_NameOwnerChangedIgnoresOtherNames(t *testing.T) {
	// A strict mock fails the test if GetDevices is called.
	backend, err := NewNetworkManagerBackend(mock_gonetworkmanager.NewMockNetworkManager(t))
	assert.NoError(t, err)

	backend.handleDBusSignal(nameOwnerChanged("org.bluez", "", ":1.2"))
	backend.handleDBusSignal(nameOwnerChanged("org.freedesktop.NetworkManager", ":1.1", ""))
}

// A restarted NetworkManager may give the same interface a new object path, and
// the dead instance never emits DeviceRemoved for the old one.
func TestNetworkManagerBackend_RestartDropsDevicesOfDeadInstance(t *testing.T) {
	const (
		oldPath = dbus.ObjectPath("/org/freedesktop/NetworkManager/Devices/7")
		newPath = dbus.ObjectPath("/org/freedesktop/NetworkManager/Devices/16")
	)

	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockNM.EXPECT().GetPropertyActiveConnections().Return(nil, nil).Maybe()
	mockNM.EXPECT().GetPropertyPrimaryConnection().Return(nil, nil).Maybe()

	oldDev := mock_gonetworkmanager.NewMockDevice(t)
	oldDev.EXPECT().GetPath().Return(oldPath).Maybe()

	newDev := mock_gonetworkmanager.NewMockDevice(t)
	newDev.EXPECT().GetPath().Return(newPath).Maybe()
	newDev.EXPECT().GetPropertyDeviceType().Return(gonetworkmanager.NmDeviceTypeEthernet, nil)
	newDev.EXPECT().GetPropertyManaged().Return(true, nil)
	newDev.EXPECT().GetPropertyInterface().Return("enp5s0", nil)
	newDev.EXPECT().GetPropertyState().Return(gonetworkmanager.NmDeviceStateActivated, nil).Maybe()
	newDev.EXPECT().GetPropertyDriver().Return("r8169", nil).Maybe()
	newDev.EXPECT().GetPropertyIP4Config().Return(nil, nil).Maybe()
	newDev.EXPECT().GetPropertyActiveConnection().Return(nil, nil).Maybe()

	wired := mock_gonetworkmanager.NewMockDeviceWired(t)
	wired.EXPECT().GetPropertyHwAddress().Return("94:e2:3c:c1:8d:ba", nil)
	wired.EXPECT().GetPropertyPermHwAddress().Return("94:e2:3c:c1:8d:ba", nil)
	wired.EXPECT().GetPropertySpeed().Return(uint32(1000), nil).Maybe()

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)
	backend.settings = emptySettingsMock(t)
	backend.ethernetDevices["enp5s0"] = &ethernetDeviceInfo{device: oldDev, name: "enp5s0"}
	backend.ethernetDevice = oldDev
	backend.newDevice = func(p dbus.ObjectPath) (gonetworkmanager.Device, error) {
		assert.Equal(t, newPath, p)
		return newDev, nil
	}
	backend.newDeviceWired = func(dbus.ObjectPath) (gonetworkmanager.DeviceWired, error) { return wired, nil }

	mockNM.EXPECT().GetDevices().Return([]gonetworkmanager.Device{newDev}, nil).Once()
	backend.handleDBusSignal(nameOwnerChanged("org.freedesktop.NetworkManager", "", ":1.10987"))

	tracked := backend.trackedDevicePaths()
	assert.NotContains(t, tracked, oldPath)
	assert.Contains(t, tracked, newPath)
	assert.Equal(t, newPath, backend.ethernetDevice.(gonetworkmanager.Device).GetPath())
}
