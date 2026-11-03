package network

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMergeSavedProfilesIntoWiFiNetworks(t *testing.T) {
	networks := []WiFiNetwork{
		{
			SSID:        "Home",
			Signal:      80,
			Secured:     false,
			Autoconnect: false,
		},
		{
			SSID:        "Cafe",
			Signal:      50,
			Secured:     false,
			Autoconnect: true,
		},
	}
	profiles := map[string]savedWiFiProfile{
		"Home": {
			Autoconnect: true,
			Hidden:      true,
			Secured:     true,
			Mode:        "infrastructure",
		},
	}

	merged := mergeSavedProfilesIntoWiFiNetworks(networks, profiles, "Home", true)

	assert.Len(t, merged, 2)
	assert.Equal(t, "Home", merged[0].SSID)
	assert.True(t, merged[0].Connected)
	assert.True(t, merged[0].Saved)
	assert.True(t, merged[0].Autoconnect)
	assert.True(t, merged[0].Hidden)
	assert.True(t, merged[0].Secured)
	assert.Equal(t, "infrastructure", merged[0].Mode)

	assert.Equal(t, "Cafe", merged[1].SSID)
	assert.False(t, merged[1].Saved)
	assert.False(t, merged[1].Autoconnect)
}

func TestSavedWiFiNetworksFromProfilesKeepsConnectedCurrentNetworkInRange(t *testing.T) {
	profiles := map[string]savedWiFiProfile{
		"Home": {
			Autoconnect: true,
			Secured:     true,
		},
	}

	networks := savedWiFiNetworksFromProfiles(profiles, nil, "Home", true)

	assert.Len(t, networks, 1)
	assert.Equal(t, "Home", networks[0].SSID)
	assert.True(t, networks[0].Connected)
	assert.False(t, networks[0].OutOfRange)
}

func TestSavedWiFiNetworksFromProfilesIncludesOutOfRange(t *testing.T) {
	profiles := map[string]savedWiFiProfile{
		"Home": {
			Autoconnect: true,
			Hidden:      true,
			Secured:     true,
			Mode:        "infrastructure",
		},
		"Office": {
			Autoconnect: false,
			Secured:     true,
			Enterprise:  true,
			Mode:        "infrastructure",
		},
	}
	visible := map[string]WiFiNetwork{
		"Home": {
			SSID:      "Home",
			Signal:    72,
			Secured:   true,
			Connected: true,
		},
	}

	networks := savedWiFiNetworksFromProfiles(profiles, visible, "Home", true)

	assert.Len(t, networks, 2)
	assert.Equal(t, "Home", networks[0].SSID)
	assert.True(t, networks[0].Saved)
	assert.True(t, networks[0].Connected)
	assert.False(t, networks[0].OutOfRange)
	assert.True(t, networks[0].Hidden)
	assert.Equal(t, uint8(72), networks[0].Signal)

	assert.Equal(t, "Office", networks[1].SSID)
	assert.True(t, networks[1].Saved)
	assert.False(t, networks[1].Autoconnect)
	assert.True(t, networks[1].Enterprise)
	assert.True(t, networks[1].OutOfRange)
}

func TestWiFiNetworksBySSIDVisibleOnlySkipsOutOfRange(t *testing.T) {
	visible := wiFiNetworksBySSID([]WiFiNetwork{
		{SSID: "Home", Signal: 70},
		{SSID: "Office", Signal: 0, OutOfRange: true},
	}, true)

	assert.Contains(t, visible, "Home")
	assert.NotContains(t, visible, "Office")
}

func TestRefreshSavedWiFiStatePreservesVisibleSavedNetworks(t *testing.T) {
	networks := []WiFiNetwork{
		{
			SSID:   "Home",
			Signal: 82,
		},
	}
	profiles := map[string]savedWiFiProfile{
		"Home": {
			Autoconnect: true,
			Secured:     true,
			Mode:        "infrastructure",
		},
		"Office": {
			Autoconnect: false,
			Secured:     true,
			Mode:        "infrastructure",
		},
	}

	mergedNetworks, savedNetworks := refreshSavedWiFiState(networks, profiles, "", false)

	assert.Len(t, mergedNetworks, 1)
	assert.Equal(t, "Home", mergedNetworks[0].SSID)
	assert.True(t, mergedNetworks[0].Saved)
	assert.True(t, mergedNetworks[0].Autoconnect)

	assert.Len(t, savedNetworks, 2)
	assert.Equal(t, "Home", savedNetworks[0].SSID)
	assert.True(t, savedNetworks[0].Saved)
	assert.False(t, savedNetworks[0].OutOfRange)
	assert.Equal(t, uint8(82), savedNetworks[0].Signal)

	assert.Equal(t, "Office", savedNetworks[1].SSID)
	assert.True(t, savedNetworks[1].Saved)
	assert.True(t, savedNetworks[1].OutOfRange)
}
