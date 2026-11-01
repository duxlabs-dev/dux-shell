package network

import (
	"testing"

	mock_gonetworkmanager "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/stretchr/testify/assert"
)

func TestNetworkManagerBackend_SetPromptBroker_Nil(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	err = backend.SetPromptBroker(nil)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "cannot be nil")
}

func TestNetworkManagerBackend_SubmitCredentials_NoBroker(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.promptBroker = nil
	err = backend.SubmitCredentials("token", map[string]string{"password": "test"}, false)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not initialized")
}

func TestNetworkManagerBackend_StartSecretAgent_NoBroker(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.promptBroker = nil
	err = backend.startSecretAgent()
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "prompt broker not set")
}
