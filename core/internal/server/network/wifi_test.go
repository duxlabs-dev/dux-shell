package network

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestFrequencyToChannel(t *testing.T) {
	tests := []struct {
		name      string
		frequency uint32
		channel   uint32
	}{
		{"2.4 GHz channel 1", 2412, 1},
		{"2.4 GHz channel 14", 2484, 14},
		{"5 GHz channel 36", 5180, 36},
		{"6 GHz channel 1", 5955, 1},
		{"Unknown frequency", 1000, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := frequencyToChannel(tt.frequency)
			assert.Equal(t, tt.channel, result)
		})
	}
}

func TestSortWiFiNetworks(t *testing.T) {
	t.Run("connected network comes first", func(t *testing.T) {
		networks := []WiFiNetwork{
			{SSID: "Network1", Signal: 90, Connected: false},
			{SSID: "Network2", Signal: 80, Connected: true},
			{SSID: "Network3", Signal: 70, Connected: false},
		}

		sortWiFiNetworks(networks)

		assert.Equal(t, "Network2", networks[0].SSID)
		assert.True(t, networks[0].Connected)
	})

	t.Run("sorts by signal strength", func(t *testing.T) {
		networks := []WiFiNetwork{
			{SSID: "Weak", Signal: 40, Secured: true},
			{SSID: "Strong", Signal: 90, Secured: true},
			{SSID: "Medium", Signal: 60, Secured: true},
		}

		sortWiFiNetworks(networks)

		assert.Equal(t, "Strong", networks[0].SSID)
		assert.Equal(t, "Medium", networks[1].SSID)
		assert.Equal(t, "Weak", networks[2].SSID)
	})

	t.Run("prioritizes open networks with good signal", func(t *testing.T) {
		networks := []WiFiNetwork{
			{SSID: "SecureWeak", Signal: 40, Secured: true},
			{SSID: "OpenStrong", Signal: 60, Secured: false},
			{SSID: "SecureStrong", Signal: 90, Secured: true},
		}

		sortWiFiNetworks(networks)

		assert.Equal(t, "OpenStrong", networks[0].SSID)

		openIdx := -1
		weakSecureIdx := -1
		for i, n := range networks {
			if n.SSID == "OpenStrong" {
				openIdx = i
			}
			if n.SSID == "SecureWeak" {
				weakSecureIdx = i
			}
		}
		assert.Less(t, openIdx, weakSecureIdx, "OpenStrong should come before SecureWeak")
	})

	t.Run("prioritizes saved networks after connected", func(t *testing.T) {
		networks := []WiFiNetwork{
			{SSID: "UnsavedStrong", Signal: 95, Saved: false},
			{SSID: "SavedMedium", Signal: 60, Saved: true},
			{SSID: "SavedWeak", Signal: 50, Saved: true},
			{SSID: "UnsavedMedium", Signal: 70, Saved: false},
		}

		sortWiFiNetworks(networks)

		assert.Equal(t, "SavedMedium", networks[0].SSID)
		assert.Equal(t, "SavedWeak", networks[1].SSID)
		assert.Equal(t, "UnsavedStrong", networks[2].SSID)
		assert.Equal(t, "UnsavedMedium", networks[3].SSID)
	})
}
