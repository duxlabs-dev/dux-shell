package network

import (
	"bufio"
	"errors"
	"maps"
	"os/exec"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	mock_dbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
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
	mockOfficeConn := mock_gonetworkmanager.NewMockConnection(t)
	mockCafeConn := mock_gonetworkmanager.NewMockConnection(t)

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
	// wlan0's device snapshot is stale (Cafe is gone, Home was stronger);
	// Office is only in range of the second radio.
	backend.state.WiFiDevice = "wlan0"
	backend.state.WiFiDevices = []WiFiDevice{
		{Name: "wlan0", Networks: []WiFiNetwork{{SSID: "Home", Signal: 90, Device: "wlan0"}, {SSID: "Cafe", Signal: 60, Device: "wlan0"}}},
		{Name: "wlan1", Networks: []WiFiNetwork{{SSID: "Office", Signal: 40, Device: "wlan1"}}},
	}
	backend.stateMutex.Unlock()

	wifiSettings := func(ssid string) gonetworkmanager.ConnectionSettings {
		return gonetworkmanager.ConnectionSettings{
			"connection": {
				"type":        "802-11-wireless",
				"autoconnect": true,
			},
			"802-11-wireless": {
				"ssid": []byte(ssid),
			},
			"802-11-wireless-security": {},
		}
	}
	mockSettings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{mockConn, mockOfficeConn, mockCafeConn}, nil)
	mockConn.EXPECT().GetSettings().Return(wifiSettings("Home"), nil)
	mockOfficeConn.EXPECT().GetSettings().Return(wifiSettings("Office"), nil)
	mockCafeConn.EXPECT().GetSettings().Return(wifiSettings("Cafe"), nil)

	err = backend.updateSavedWiFiNetworks()
	assert.NoError(t, err)

	backend.stateMutex.RLock()
	savedNetworks := append([]WiFiNetwork(nil), backend.state.SavedWiFiNetworks...)
	wifiNetworks := append([]WiFiNetwork(nil), backend.state.WiFiNetworks...)
	backend.stateMutex.RUnlock()

	assert.Len(t, wifiNetworks, 1)
	assert.True(t, wifiNetworks[0].Saved)
	require.Len(t, savedNetworks, 3)
	assert.Equal(t, "Home", savedNetworks[0].SSID)
	assert.True(t, savedNetworks[0].Saved)
	assert.False(t, savedNetworks[0].OutOfRange)
	assert.Equal(t, uint8(76), savedNetworks[0].Signal)
	assert.Empty(t, savedNetworks[0].Device)
	assert.Equal(t, "Office", savedNetworks[1].SSID)
	assert.False(t, savedNetworks[1].OutOfRange)
	assert.Equal(t, "wlan1", savedNetworks[1].Device)
	assert.Equal(t, "Cafe", savedNetworks[2].SSID)
	assert.True(t, savedNetworks[2].OutOfRange)
}

func TestNetworkManagerBackend_FindConnection_NoSettings(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.settings = nil
	_, err = backend.findConnection("NonExistentNetwork")
	assert.Error(t, err)
}

func TestAPNeedsCredentials(t *testing.T) {
	const (
		privacy = uint32(gonetworkmanager.Nm80211APFlagsPrivacy)
		ccmp    = uint32(gonetworkmanager.Nm80211APSecPairCCMP) | uint32(gonetworkmanager.Nm80211APSecGroupCCMP)
		psk     = uint32(gonetworkmanager.Nm80211APSecKeyMgmtPSK)
		sae     = uint32(gonetworkmanager.Nm80211APSecKeyMgmtSAE)
		owe     = uint32(gonetworkmanager.Nm80211APSecKeyMgmtOWE)
		oweTM   = uint32(gonetworkmanager.Nm80211APSecKeyMgmtOWETM)
	)

	tests := []struct {
		name                      string
		flags, wpaFlags, rsnFlags uint32
		want                      bool
	}{
		{"open", 0, 0, 0, false},
		{"owe", privacy, 0, owe | ccmp, false},
		{"owe transition open bss", 0, 0, oweTM, false},
		{"wep", privacy, 0, 0, true},
		{"wpa2 psk", privacy, 0, psk | ccmp, true},
		{"wpa3 transition", privacy, 0, psk | sae | ccmp, true},
		{"sae with owe", privacy, 0, sae | owe | ccmp, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, apNeedsCredentials(tt.flags, tt.wpaFlags, tt.rsnFlags))
		})
	}
}

func wifiWriteFixture(t *testing.T) (*NetworkManagerBackend, *mock_gonetworkmanager.MockConnection, *mock_dbus.MockBusObject) {
	conn := mock_gonetworkmanager.NewMockConnection(t)
	conn.EXPECT().GetPath().Return(dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings/7")).Maybe()
	conn.EXPECT().GetSettings().Return(gonetworkmanager.ConnectionSettings{"connection": {"type": "802-11-wireless"},
		"802-11-wireless": {"ssid": []byte("home")}}, nil).Maybe()
	settings := mock_gonetworkmanager.NewMockSettings(t)
	settings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{conn}, nil).Maybe()
	backend, err := NewNetworkManagerBackend(mock_gonetworkmanager.NewMockNetworkManager(t))
	require.NoError(t, err)
	backend.settings = settings
	obj := mock_dbus.NewMockBusObject(t)
	backend.nmObjectFn = func(dbus.ObjectPath) dbus.BusObject { return obj }
	return backend, conn, obj
}

func ttlsConfig(t *testing.T, ca []byte, pw string) *EnterpriseConfig {
	return &EnterpriseConfig{EAP: "ttls", Phase2: "pap", Identity: "u@example.org", Password: pw, CA: "file", CACertPEM: string(pemCert(ca)), ServerDomain: "radius.example.org"}
}

func TestBuildWiFiSettings(t *testing.T) {
	ca := testCertDER(t, "ca")
	const sec = "802-11-wireless-security"
	for _, tc := range []struct {
		name, wantErr string
		ap            apSecurity
		req           ConnectionRequest
		want          map[string]any // "section.key"; a nil value means absent
	}{
		{"hidden ttls", "", apSecurity{}, ConnectionRequest{SSID: "h", Hidden: true, Enterprise: ttlsConfig(t, ca, "pw")},
			map[string]any{sec + ".key-mgmt": "wpa-eap", "802-1x.eap": []string{"ttls"}, "802-1x.ca-cert": ca, "802-1x.ca-path": nil}},
		{"unknown security", "wep", apSecurity{}, ConnectionRequest{SSID: "x", Security: "wep"}, nil},
		{"owe ap has no psk or pmf", "", apSecurity{owe: true, secured: true}, ConnectionRequest{SSID: "o"}, map[string]any{sec + ".key-mgmt": "owe", sec + ".psk": nil, sec + ".pmf": nil}},
		{"psk ap without password", "password required", apSecurity{psk: true, secured: true}, ConnectionRequest{SSID: "p"}, nil},
		{"interactive psk omits the key", "", apSecurity{psk: true, secured: true}, ConnectionRequest{SSID: "p", Interactive: true},
			map[string]any{sec + ".key-mgmt": "wpa-psk", sec + ".psk-flags": uint32(0), sec + ".psk": nil}},
		{"explicit eap over a psk ap", "", apSecurity{psk: true, secured: true},
			ConnectionRequest{SSID: "e", Security: "wpa-eap", Enterprise: ttlsConfig(t, ca, "pw")},
			map[string]any{sec + ".key-mgmt": "wpa-eap", sec + ".psk": nil}},
		{"enterprise ap without config", "802.1X settings required", apSecurity{enterprise: true, secured: true}, ConnectionRequest{SSID: "e"}, nil},
		{"sae ap", "", apSecurity{sae: true, secured: true}, ConnectionRequest{SSID: "s", Password: "pw"},
			map[string]any{sec + ".key-mgmt": "sae", sec + ".pmf": int32(3), sec + ".psk": "pw"}},
		{"secured but unsupported ap", "not OWE/SAE/PSK/802.1X", apSecurity{secured: true}, ConnectionRequest{SSID: "w"}, nil},
		{"hidden with password", "", apSecurity{}, ConnectionRequest{SSID: "h", Hidden: true, Password: "pw"}, map[string]any{sec + ".key-mgmt": "wpa-psk", sec + ".psk": "pw"}},
		{"hidden without password", "", apSecurity{}, ConnectionRequest{SSID: "h", Hidden: true},
			map[string]any{sec + ".key-mgmt": nil, "802-11-wireless.security": nil, "802-11-wireless.hidden": true}},
		{"invalid enterprise config", "identity", apSecurity{enterprise: true, secured: true},
			ConnectionRequest{SSID: "e", Enterprise: &EnterpriseConfig{EAP: "ttls", Phase2: "pap"}}, nil},
		{"open network defaults", "", apSecurity{}, ConnectionRequest{SSID: "net"},
			map[string]any{"connection.id": "net", "connection.autoconnect": true, "ipv4.method": "auto", "ipv6.method": "auto", "802-11-wireless.hidden": nil}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, err := buildWiFiSettings(tc.req, tc.ap)
			if tc.wantErr != "" {
				assert.ErrorContains(t, err, tc.wantErr)
				return
			}
			require.NoError(t, err)
			for k, want := range tc.want {
				i := strings.LastIndex(k, ".")
				assert.Equal(t, want, s[k[:i]][k[i+1:]], k)
			}
		})
	}
}

func TestStoredWiFiProfileWrites(t *testing.T) {
	const sec = "802-11-wireless-security"
	v := dbus.MakeVariant
	psk := func(keyMgmt string) nmSettings { return nmSettings{sec: {"key-mgmt": v(keyMgmt)}} }
	ent := ttlsConfig(t, testCertDER(t, "ca"), "")
	sysEnt := *ent
	sysEnt.CA, sysEnt.CACertPEM = "system", ""
	for _, tc := range []struct {
		name, wantErr  string
		creds          bool // updateConnectionCredentials instead of a save-only ConnectWiFi
		stored, secret nmSettings
		req            ConnectionRequest
		want           map[string]any // nil map: no write; a nil value: key absent
	}{
		{"new psk replaces stored", "", true, nmSettings{sec: {"key-mgmt": v("wpa-psk"), "psk-flags": v(uint32(1))}},
			nmSettings{sec: {"psk": v("old")}}, ConnectionRequest{Password: "new"},
			map[string]any{sec + ".psk": "new", sec + ".psk-flags": uint32(0)}},
		{"empty password writes nothing", "", true, psk("wpa-psk"), nmSettings{sec: {"psk": v("old")}}, ConnectionRequest{SSID: "home"}, nil},
		{"sae to enterprise drops psk and pmf", "", true,
			nmSettings{sec: {"key-mgmt": v("sae"), "pmf": v(int32(3)), "auth-alg": v("open"), "psk-flags": v(uint32(0))}},
			nmSettings{sec: {"psk": v("old")}}, ConnectionRequest{SSID: "home", Enterprise: ent},
			map[string]any{sec + ".key-mgmt": "wpa-eap", sec + ".psk": nil, sec + ".psk-flags": nil, sec + ".pmf": nil, sec + ".auth-alg": nil}},
		{"hidden and autoconnect on a psk profile", "", false,
			nmSettings{"connection": {"autoconnect": v(false)}, sec: {"key-mgmt": v("wpa-psk")}}, nmSettings{sec: {"psk": v("old")}},
			ConnectionRequest{SSID: "home", Password: "new", Hidden: true, Security: "wpa-psk"},
			map[string]any{"802-11-wireless.hidden": true, "connection.autoconnect": true, sec + ".psk": "new"}},
		{"open profile save-only autoconnects", "", false, nil, nil, ConnectionRequest{SSID: "home", Security: "none"},
			map[string]any{"connection.autoconnect": true}},
		{"owe profile save-only autoconnects", "", false, psk("owe"), nmSettings{sec: {}}, ConnectionRequest{SSID: "home", Security: "owe"},
			map[string]any{"connection.autoconnect": true}},
		{"security mismatch", "security", false, nil, nil, ConnectionRequest{SSID: "home", Password: "pw", Security: "wpa-psk"}, nil},
		{"enterprise updated in place", "", false,
			nmSettings{"ipv4": {"dns-data": v([]string{"9.9.9.9"})}, sec: {"key-mgmt": v("wpa-eap")}, "802-1x": {"eap": v([]string{"peap"}), "password-flags": v(uint32(1))}},
			nmSettings{sec: {}, "802-1x": {"password": v("stored")}}, ConnectionRequest{SSID: "home", Security: "wpa-eap", Enterprise: ent},
			map[string]any{"802-1x.eap": []string{"ttls"}, "802-1x.password": "stored", "802-1x.password-flags": uint32(0), "ipv4.dns-data": []string{"9.9.9.9"}}},
		{"enterprise keeps the stored ca-path next to system certificates", "", false,
			nmSettings{sec: {"key-mgmt": v("wpa-eap")}, "802-1x": {"eap": v([]string{"peap"}), "system-ca-certs": v(true), "ca-path": v("/etc/ssl/certs")}},
			nmSettings{sec: {}, "802-1x": {"password": v("stored")}}, ConnectionRequest{SSID: "home", Security: "wpa-eap", Enterprise: &sysEnt},
			map[string]any{"802-1x.ca-path": "/etc/ssl/certs"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			backend, conn, obj := wifiWriteFixture(t)
			backend.wifiDevice = nil
			stored := nmSettings{"connection": {"id": v("home")}, "802-11-wireless": {"ssid": v([]byte("home"))}}
			maps.Copy(stored, tc.stored)
			expectGetSettings(obj, stored)
			for s, x := range tc.secret {
				expectGetSecrets(obj, s, nmSettings{s: x})
			}
			var got *nmSettings
			if tc.want != nil {
				got = captureUpdate2(obj, nmUpdate2FlagToDisk, nil)
			}
			var err error
			if tc.creds {
				err = updateConnectionCredentials(backend, conn, tc.req)
			} else {
				tc.req.SaveOnly = true
				err = backend.ConnectWiFi(tc.req)
			}
			if tc.wantErr != "" {
				assert.ErrorContains(t, err, tc.wantErr)
				return
			}
			require.NoError(t, err)
			for k, want := range tc.want {
				i := strings.LastIndex(k, ".")
				assert.Equal(t, want, (*got)[k[:i]][k[i+1:]].Value(), k)
			}
		})
	}
}

func TestSaveOnly_AddsNewProfileWithoutActivating(t *testing.T) {
	settings := mock_gonetworkmanager.NewMockSettings(t)
	settings.EXPECT().ListConnections().Return(nil, nil)
	var added gonetworkmanager.ConnectionSettings
	settings.EXPECT().AddConnection(mock.Anything).RunAndReturn(func(s gonetworkmanager.ConnectionSettings) (gonetworkmanager.Connection, error) {
		added = s
		return nil, nil
	}).Once()
	backend, err := NewNetworkManagerBackend(mock_gonetworkmanager.NewMockNetworkManager(t))
	require.NoError(t, err)
	backend.settings, backend.wifiDevice = settings, nil
	nm := mock_dbus.NewMockBusObject(t)
	backend.nmObjectFn = func(dbus.ObjectPath) dbus.BusObject { return nm }
	nm.EXPECT().Call(gonetworkmanager.NetworkManagerGetPermissions, dbus.Flags(0)).
		Return(&dbus.Call{Body: []any{map[string]string{nmPermModifySystem: "auth"}}}).Once()
	require.NoError(t, backend.ConnectWiFi(ConnectionRequest{SSID: "eduroam", Security: "wpa-eap", SaveOnly: true, Enterprise: ttlsConfig(t, testCertDER(t, "ca"), "pw")}))
	assert.False(t, backend.state.IsConnecting)
	assert.NotEmpty(t, added["connection"]["permissions"], "a user who can't modify system profiles gets a user-owned one")
}

func TestConnectWiFi_ExistingEnterpriseUpdateFailureBlocksActivation(t *testing.T) {
	backend, _, obj := wifiWriteFixture(t)
	wireless := mock_gonetworkmanager.NewMockDeviceWireless(t)
	wireless.EXPECT().GetPropertyInterface().Return("wlan0", nil).Maybe()
	backend.wifiDevice, backend.wifiDev = wireless, wireless
	backend.wifiDevices = map[string]*wifiDeviceInfo{"wlan0": {wireless: wireless, name: "wlan0"}}
	expectGetSettings(obj, nmSettings{"802-1x": {"eap": dbus.MakeVariant([]string{"peap"})}})
	obj.EXPECT().Call(nmConnGetSecrets, dbus.Flags(0), "802-1x").Return(&dbus.Call{Err: errors.New("denied")}).Once()
	err := backend.ConnectWiFi(ConnectionRequest{SSID: "home", Enterprise: ttlsConfig(t, testCertDER(t, "ca"), "")})
	assert.ErrorContains(t, err, "denied")
	assert.False(t, backend.state.IsConnecting)
}
