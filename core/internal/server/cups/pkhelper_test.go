package cups

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParseDevicesMap(t *testing.T) {
	tests := []struct {
		name     string
		input    map[string]string
		wantLen  int
		wantURIs []string
	}{
		{
			name: "multiple_devices",
			input: map[string]string{
				"device-uri:0":   "usb://HP/LaserJet",
				"device-class:0": "direct",
				"device-info:0":  "HP LaserJet",
				"device-uri:1":   "socket://192.168.1.100",
				"device-class:1": "network",
				"device-info:1":  "Network Printer",
			},
			wantLen:  2,
			wantURIs: []string{"usb://HP/LaserJet", "socket://192.168.1.100"},
		},
		{
			name: "malformed_key",
			input: map[string]string{
				"no-colon-here": "value",
			},
			wantLen:  0,
			wantURIs: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseDevicesMap(tt.input)
			assert.Len(t, got, tt.wantLen)

			if tt.wantURIs != nil {
				gotURIs := make(map[string]bool)
				for _, d := range got {
					gotURIs[d.URI] = true
				}
				for _, uri := range tt.wantURIs {
					assert.True(t, gotURIs[uri], "expected URI %s not found", uri)
				}
			}
		})
	}
}

func TestParseDevicesMap_Attributes(t *testing.T) {
	input := map[string]string{
		"device-uri:0":            "usb://HP/LaserJet",
		"device-class:0":          "direct",
		"device-info:0":           "HP LaserJet",
		"device-make-and-model:0": "HP LaserJet 1020",
		"device-id:0":             "MFG:HP;MDL:LaserJet",
		"device-location:0":       "USB Port",
	}

	got := parseDevicesMap(input)
	assert.Len(t, got, 1)

	dev := got[0]
	assert.Equal(t, "usb://HP/LaserJet", dev.URI)
	assert.Equal(t, "direct", dev.Class)
	assert.Equal(t, "HP LaserJet", dev.Info)
	assert.Equal(t, "HP LaserJet 1020", dev.MakeModel)
	assert.Equal(t, "MFG:HP;MDL:LaserJet", dev.ID)
	assert.Equal(t, "USB Port", dev.Location)
}
