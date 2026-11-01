package network

import (
	"testing"

	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/stretchr/testify/assert"
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
