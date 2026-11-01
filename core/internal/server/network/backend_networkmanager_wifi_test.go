package network

import (
	"bufio"
	"errors"
	"os/exec"
	"sync"
	"testing"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNetworkManagerBackend_ScanWiFi_RecoversDevice(t *testing.T) {
	for _, tc := range []struct {
		name   string
		stale  bool
		device string
		busy   bool
	}{
		{name: "missing"},
		{name: "replaced", stale: true},
		{name: "missing named device", device: "wlan0"},
		{name: "replaced named device", stale: true, device: "wlan0"},
		{name: "scan initially busy", busy: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			nm := mock_gonetworkmanager.NewMockNetworkManager(t)
			wifi := mock_gonetworkmanager.NewMockDeviceWireless(t)
			backend, err := NewNetworkManagerBackend(nm)
			require.NoError(t, err)
			backend.settings = emptySettingsMock(t)
			backend.state.WiFiEnabled = true
			var signals chan *dbus.Signal
			if tc.name == "replaced" {
				backend.dbusConn = privateNetworkTestBus(t)
				signals = make(chan *dbus.Signal, 4)
				backend.dbusConn.Signal(signals)
				t.Cleanup(func() { backend.dbusConn.RemoveSignal(signals) })
			}
			if tc.stale {
				old := mock_gonetworkmanager.NewMockDeviceWireless(t)
				old.EXPECT().GetPath().Return(dbus.ObjectPath("/org/freedesktop/NetworkManager/Devices/1"))
				backend.setWifiDeviceInfo("wlan0", &wifiDeviceInfo{device: old, wireless: old, name: "wlan0"})
				backend.wifiDevice, backend.wifiDev = old, old
			}

			discovery := nm.EXPECT().GetDevices().Return([]gonetworkmanager.Device{wifi}, nil)
			if tc.busy {
				discovery.Twice()
				wifi.EXPECT().RequestScan().Return(errors.New("scan temporarily unavailable")).Once()
			} else {
				discovery.Once()
			}
			wifi.EXPECT().GetPath().Return(dbus.ObjectPath("/org/freedesktop/NetworkManager/Devices/2"))
			wifi.EXPECT().GetPropertyInterface().Return("wlan0", nil)
			wifi.EXPECT().GetPropertyHwAddress().Return("00:11:22:33:44:55", nil)
			wifi.EXPECT().GetPropertyState().Return(gonetworkmanager.NmDeviceStateDisconnected, nil)
			wifi.EXPECT().GetPropertyManaged().Return(true, nil)
			wifi.EXPECT().GetPropertyWirelessCapabilities().Return(uint32(0), nil)
			wifi.EXPECT().RequestScan().Return(nil).Once()
			ap := mock_gonetworkmanager.NewMockAccessPoint(t)
			wifi.EXPECT().GetAccessPoints().Return([]gonetworkmanager.AccessPoint{ap}, nil)
			ap.EXPECT().GetPropertySSID().Return("Recovered", nil)
			ap.EXPECT().GetPropertyMode().Return(gonetworkmanager.Nm80211ModeInfra, nil)
			ap.EXPECT().GetPropertyStrength().Return(uint8(75), nil)
			ap.EXPECT().GetPropertyFlags().Return(uint32(0), nil)
			ap.EXPECT().GetPropertyWPAFlags().Return(uint32(0), nil)
			ap.EXPECT().GetPropertyRSNFlags().Return(uint32(0), nil)
			ap.EXPECT().GetPropertyFrequency().Return(uint32(2412), nil)
			ap.EXPECT().GetPropertyMaxBitrate().Return(uint32(54000), nil)
			ap.EXPECT().GetPropertyHWAddress().Return("00:11:22:33:44:66", nil)

			if tc.busy {
				require.ErrorContains(t, backend.ScanWiFi(), "scan temporarily unavailable")
			}
			if tc.device == "" {
				require.NoError(t, backend.ScanWiFi())
			} else {
				require.NoError(t, backend.ScanWiFiDevice(tc.device))
			}
			assert.Same(t, wifi, backend.wifiDevice)
			assert.Same(t, wifi, backend.wifiDevices["wlan0"].wireless)
			state, err := backend.GetCurrentState()
			require.NoError(t, err)
			assert.Equal(t, "wlan0", state.WiFiDevice)
			require.Len(t, state.WiFiDevices, 1)
			assert.Equal(t, "wlan0", state.WiFiDevices[0].Name)
			require.Len(t, state.WiFiDevices[0].Networks, 1)
			assert.Equal(t, "Recovered", state.WiFiDevices[0].Networks[0].SSID)
			if tc.device == "" {
				require.Len(t, state.WiFiNetworks, 1)
				assert.Equal(t, "Recovered", state.WiFiNetworks[0].SSID)
			}
			if signals != nil {
				for _, path := range []dbus.ObjectPath{
					"/org/freedesktop/NetworkManager/Devices/1",
					"/org/freedesktop/NetworkManager/Devices/2",
				} {
					require.NoError(t, backend.dbusConn.Emit(path, dbusPropsInterface+".PropertiesChanged", dbusNMWirelessInterface, map[string]dbus.Variant{}, []string{}))
				}
				timeout := time.NewTimer(2 * time.Second)
				defer timeout.Stop()
			waitForProperties:
				for {
					select {
					case signal := <-signals:
						if signal.Name != dbusPropsInterface+".PropertiesChanged" {
							continue
						}
						assert.Equal(t, dbus.ObjectPath("/org/freedesktop/NetworkManager/Devices/2"), signal.Path)
						break waitForProperties
					case <-timeout.C:
						t.Fatal("rediscovered device property changes were not subscribed")
					}
				}
			}
		})
	}
}

func privateNetworkTestBus(t *testing.T) *dbus.Conn {
	t.Helper()
	path, err := exec.LookPath("dbus-daemon")
	if err != nil {
		t.Skip("dbus-daemon is required to verify device subscriptions")
	}
	command := exec.Command(path, "--session", "--nofork", "--print-address=1")
	stdout, err := command.StdoutPipe()
	require.NoError(t, err)
	require.NoError(t, command.Start())
	t.Cleanup(func() {
		command.Process.Kill()
		command.Wait()
	})
	scanner := bufio.NewScanner(stdout)
	require.True(t, scanner.Scan(), "private D-Bus did not provide an address")
	conn, err := dbus.Connect(scanner.Text())
	require.NoError(t, err)
	t.Cleanup(func() { conn.Close() })
	return conn
}

func TestNetworkManagerBackend_ScanWiFi_RetriesDiscovery(t *testing.T) {
	nm := mock_gonetworkmanager.NewMockNetworkManager(t)
	wifi := mock_gonetworkmanager.NewMockDeviceWireless(t)
	backend, err := NewNetworkManagerBackend(nm)
	require.NoError(t, err)
	backend.settings = emptySettingsMock(t)
	backend.state.WiFiEnabled = true

	nm.EXPECT().GetDevices().Return(nil, errors.New("NetworkManager unavailable")).Once()
	require.ErrorContains(t, backend.ScanWiFi(), "NetworkManager unavailable")
	nm.EXPECT().GetDevices().Return(nil, nil).Once()
	require.ErrorContains(t, backend.ScanWiFi(), "no WiFi device available")
	nm.EXPECT().GetDevices().Return([]gonetworkmanager.Device{wifi}, nil).Once()
	wifi.EXPECT().GetPath().Return(dbus.ObjectPath("/org/freedesktop/NetworkManager/Devices/2"))
	wifi.EXPECT().GetPropertyInterface().Return("wlan0", nil)
	wifi.EXPECT().GetPropertyHwAddress().Return("", nil)
	wifi.EXPECT().GetPropertyState().Return(gonetworkmanager.NmDeviceStateDisconnected, nil)
	wifi.EXPECT().GetPropertyManaged().Return(true, nil)
	wifi.EXPECT().GetPropertyWirelessCapabilities().Return(uint32(0), nil)
	wifi.EXPECT().RequestScan().Return(nil).Once()
	wifi.EXPECT().GetAccessPoints().Return(nil, nil)
	require.NoError(t, backend.ScanWiFi())
}

func TestNetworkManagerBackend_WiFiReplacementBeforeRemoval(t *testing.T) {
	nm := mock_gonetworkmanager.NewMockNetworkManager(t)
	old := mock_gonetworkmanager.NewMockDeviceWireless(t)
	wifi := mock_gonetworkmanager.NewMockDeviceWireless(t)
	oldPath := dbus.ObjectPath("/org/freedesktop/NetworkManager/Devices/1")
	newPath := dbus.ObjectPath("/org/freedesktop/NetworkManager/Devices/2")
	old.EXPECT().GetPath().Return(oldPath)
	wifi.EXPECT().GetPath().Return(newPath)
	backend, err := NewNetworkManagerBackend(nm)
	require.NoError(t, err)
	backend.wifiDevice, backend.wifiDev = old, old
	backend.setWifiDeviceInfo("wlan0", &wifiDeviceInfo{device: old, wireless: old, name: "wlan0"})
	backend.setWifiDeviceInfo("wlan0", &wifiDeviceInfo{device: wifi, wireless: wifi, name: "wlan0"})
	backend.removeWifiDeviceByPath(oldPath)
	dev, wireless := backend.selectedWiFiDevice()
	assert.Same(t, wifi, dev)
	assert.Same(t, wifi, wireless)

	var workers sync.WaitGroup
	workers.Go(func() {
		for range 100 {
			backend.removeWifiDeviceByPath(newPath)
			backend.setWifiDeviceInfo("wlan0", &wifiDeviceInfo{device: wifi, wireless: wifi, name: "wlan0"})
		}
	})
	workers.Go(func() {
		for range 100 {
			backend.selectedWiFiDevice()
			backend.wifiDevicesSnapshot()
		}
	})
	workers.Wait()
	dev, wireless = backend.selectedWiFiDevice()
	assert.Same(t, wifi, dev)
	assert.Same(t, wifi, wireless)
}

func TestNetworkManagerBackend_SetWiFiEnabled(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	mockNM.EXPECT().SetPropertyWirelessEnabled(true).Return(nil)

	err = backend.SetWiFiEnabled(true)
	assert.NoError(t, err)

	backend.stateMutex.RLock()
	assert.True(t, backend.state.WiFiEnabled)
	backend.stateMutex.RUnlock()
}

func TestNetworkManagerBackend_ScanWiFi_Disabled(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockDeviceWireless := mock_gonetworkmanager.NewMockDeviceWireless(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.wifiDevice = mockDeviceWireless
	backend.wifiDev = mockDeviceWireless

	backend.stateMutex.Lock()
	backend.state.WiFiEnabled = false
	backend.stateMutex.Unlock()

	err = backend.ScanWiFi()
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "WiFi is disabled")
}

func TestNetworkManagerBackend_ConnectWiFi_NoDevice(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.wifiDevice = nil
	req := ConnectionRequest{SSID: "TestNetwork", Password: "password"}
	err = backend.ConnectWiFi(req)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "no WiFi device available")
}

func TestNetworkManagerBackend_ConnectWiFi_AlreadyConnected(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockDeviceWireless := mock_gonetworkmanager.NewMockDeviceWireless(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.wifiDevice = mockDeviceWireless
	backend.wifiDev = mockDeviceWireless
	backend.wifiDevices = map[string]*wifiDeviceInfo{
		"wlan0": {
			device:    nil,
			wireless:  mockDeviceWireless,
			name:      "wlan0",
			hwAddress: "00:11:22:33:44:55",
		},
	}

	mockDeviceWireless.EXPECT().GetPropertyInterface().Return("wlan0", nil)

	backend.stateMutex.Lock()
	backend.state.WiFiConnected = true
	backend.state.WiFiSSID = "TestNetwork"
	backend.state.WiFiDevice = "wlan0"
	backend.stateMutex.Unlock()

	req := ConnectionRequest{SSID: "TestNetwork", Password: "password"}
	err = backend.ConnectWiFi(req)
	assert.NoError(t, err)
}

func TestNetworkManagerBackend_IsConnectingTo(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.stateMutex.Lock()
	backend.state.IsConnecting = true
	backend.state.ConnectingSSID = "TestNetwork"
	backend.stateMutex.Unlock()

	assert.True(t, backend.IsConnectingTo("TestNetwork"))
	assert.False(t, backend.IsConnectingTo("OtherNetwork"))
}

func TestNetworkManagerBackend_UpdateSavedWiFiNetworksPreservesVisibleSavedNetworks(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockSettings := mock_gonetworkmanager.NewMockSettings(t)
	mockConn := mock_gonetworkmanager.NewMockConnection(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)
	backend.settings = mockSettings

	backend.stateMutex.Lock()
	backend.state.WiFiNetworks = []WiFiNetwork{
		{
			SSID:   "Home",
			Signal: 76,
		},
	}
	backend.stateMutex.Unlock()

	settings := gonetworkmanager.ConnectionSettings{
		"connection": {
			"type":        "802-11-wireless",
			"autoconnect": true,
		},
		"802-11-wireless": {
			"ssid": []byte("Home"),
		},
		"802-11-wireless-security": {},
	}
	mockSettings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{mockConn}, nil)
	mockConn.EXPECT().GetSettings().Return(settings, nil)

	err = backend.updateSavedWiFiNetworks()
	assert.NoError(t, err)

	backend.stateMutex.RLock()
	savedNetworks := append([]WiFiNetwork(nil), backend.state.SavedWiFiNetworks...)
	wifiNetworks := append([]WiFiNetwork(nil), backend.state.WiFiNetworks...)
	backend.stateMutex.RUnlock()

	assert.Len(t, wifiNetworks, 1)
	assert.True(t, wifiNetworks[0].Saved)
	assert.Len(t, savedNetworks, 1)
	assert.Equal(t, "Home", savedNetworks[0].SSID)
	assert.True(t, savedNetworks[0].Saved)
	assert.False(t, savedNetworks[0].OutOfRange)
	assert.Equal(t, uint8(76), savedNetworks[0].Signal)
}

func TestNetworkManagerBackend_FindConnection_NoSettings(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.settings = nil
	_, err = backend.findConnection("NonExistentNetwork")
	assert.Error(t, err)
}
