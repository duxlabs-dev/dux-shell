package network

import (
	"testing"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/stretchr/testify/assert"
)

func TestNetworkManagerBackend_UpdateWiFiState_NoDevice(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.wifiDevice = nil
	err = backend.updateWiFiState()
	assert.NoError(t, err)
}

func TestNetworkManagerBackend_ClassifyNMStateReason(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	testCases := []struct {
		reason   uint32
		expected string
	}{
		{NmDeviceStateReasonWrongPassword, errdefs.ErrBadCredentials},
		{NmDeviceStateReasonNoSecrets, errdefs.ErrUserCanceled},
		{NmDeviceStateReasonDhcpClientFailed, errdefs.ErrDhcpTimeout},
		{NmDeviceStateReasonNoSsid, errdefs.ErrNoSuchSSID},
		{999, errdefs.ErrConnectionFailed},
	}

	for _, tc := range testCases {
		result := backend.classifyNMStateReason(tc.reason)
		assert.Equal(t, tc.expected, result)
	}
}

func TestNetworkManagerBackend_GetDeviceIP_NoConfig(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockDevice := mock_gonetworkmanager.NewMockDevice(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	mockDevice.EXPECT().GetPropertyIP4Config().Return(nil, nil)

	ip := backend.getDeviceIP(mockDevice)
	assert.Empty(t, ip)
}

func TestNetworkManagerBackend_UpdatePrimaryConnection_TypeMapping(t *testing.T) {
	testCases := []struct {
		connType string
		expected NetworkStatus
	}{
		{"802-3-ethernet", StatusEthernet},
		{"bridge", StatusEthernet},
		{"802-11-wireless", StatusWiFi},
		{"tun", StatusDisconnected},
	}

	for _, tc := range testCases {
		t.Run(tc.connType, func(t *testing.T) {
			mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
			mockConn := mock_gonetworkmanager.NewMockActiveConnection(t)

			backend, err := NewNetworkManagerBackend(mockNM)
			assert.NoError(t, err)

			mockNM.EXPECT().GetPropertyActiveConnections().Return([]gonetworkmanager.ActiveConnection{}, nil)
			mockNM.EXPECT().GetPropertyPrimaryConnection().Return(mockConn, nil)
			mockConn.EXPECT().GetPath().Return("/org/freedesktop/NetworkManager/ActiveConnection/1")
			mockConn.EXPECT().GetPropertyType().Return(tc.connType, nil)

			assert.NoError(t, backend.updatePrimaryConnection())
			backend.stateMutex.RLock()
			defer backend.stateMutex.RUnlock()
			assert.Equal(t, tc.expected, backend.state.NetworkStatus)
		})
	}
}

func TestNetworkManagerBackend_UpdateWiFiState_PicksConnectedDevice(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	first := mock_gonetworkmanager.NewMockDevice(t)
	first.EXPECT().GetPropertyState().Return(gonetworkmanager.NmDeviceStateDisconnected, nil)

	second := mock_gonetworkmanager.NewMockDevice(t)
	second.EXPECT().GetPropertyState().Return(gonetworkmanager.NmDeviceStateActivated, nil)
	second.EXPECT().GetPath().Return("/org/freedesktop/NetworkManager/Devices/2")
	second.EXPECT().GetPropertyInterface().Return("wlan1", nil)
	second.EXPECT().GetPropertyIP4Config().Return(nil, nil)

	secondWireless := mock_gonetworkmanager.NewMockDeviceWireless(t)
	secondWireless.EXPECT().GetPropertyActiveAccessPoint().Return(nil, nil)

	mockNM.EXPECT().GetPropertyActiveConnections().Return([]gonetworkmanager.ActiveConnection{}, nil)

	backend.setWifiDeviceInfo("wlan0", &wifiDeviceInfo{device: first, name: "wlan0"})
	backend.setWifiDeviceInfo("wlan1", &wifiDeviceInfo{device: second, wireless: secondWireless, name: "wlan1"})
	backend.wifiDevice = first

	assert.NoError(t, backend.updateWiFiState())

	backend.stateMutex.RLock()
	defer backend.stateMutex.RUnlock()
	assert.True(t, backend.state.WiFiConnected)
	assert.Equal(t, "wlan1", backend.state.WiFiDevice)
}

func TestForgetOnConnectFailure(t *testing.T) {
	tests := []struct {
		name        string
		reasonCode  string
		preExisting bool
		want        bool
	}{
		{"cancelled prompt on freshly created profile", errdefs.ErrUserCanceled, false, true},
		{"no-secrets failure on saved profile", errdefs.ErrUserCanceled, true, false},
		{"bad credentials on freshly created profile", errdefs.ErrBadCredentials, false, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, forgetOnConnectFailure(tt.reasonCode, tt.preExisting))
		})
	}
}
