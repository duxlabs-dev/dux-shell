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
	backend.ethernetDevice = mock_gonetworkmanager.NewMockDevice(t)

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
