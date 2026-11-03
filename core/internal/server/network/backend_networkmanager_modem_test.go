package network

import (
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
)

func TestAccessTechLabel(t *testing.T) {
	tests := []struct {
		name string
		mask uint32
		want string
	}{
		{"unknown", 0, ""},
		{"gprs", 1 << 3, "G"},
		{"edge", 1 << 4, "E"},
		{"umts", 1 << 5, "3G"},
		{"hspa plus", 1 << 9, "H"},
		{"lte", 1 << 14, "LTE"},
		{"5gnr", 1 << 15, "5G"},
		{"highest generation wins", 1<<3 | 1<<5 | 1<<14, "LTE"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, accessTechLabel(tt.mask))
		})
	}
}

func TestParseModemProps(t *testing.T) {
	type signalQuality struct {
		Percent uint32
		Recent  bool
	}
	t.Run("full", func(t *testing.T) {
		info := parseModemProps(map[string]dbus.Variant{
			"SignalQuality":      dbus.MakeVariant(signalQuality{72, true}),
			"AccessTechnologies": dbus.MakeVariant(uint32(1 << 14)),
			"PrimaryPort":        dbus.MakeVariant("qrtr0"),
		})

		assert.Equal(t, modemInfo{primaryPort: "qrtr0", signalQuality: 72, accessTech: "LTE"}, info)
	})

	t.Run("cached quality is kept", func(t *testing.T) {
		info := parseModemProps(map[string]dbus.Variant{
			"SignalQuality": dbus.MakeVariant(signalQuality{67, false}),
		})

		assert.EqualValues(t, 67, info.signalQuality)
	})
}

func TestModemForIface(t *testing.T) {
	b := &NetworkManagerBackend{
		modems: map[dbus.ObjectPath]modemInfo{
			"/org/freedesktop/ModemManager1/Modem/0": {primaryPort: "qrtr0", signalQuality: 40},
		},
	}

	info, ok := b.modemForIface("qrtr0", 1)
	assert.True(t, ok)
	assert.EqualValues(t, 40, info.signalQuality)

	// Unmatched port name still resolves while there is exactly one of each.
	info, ok = b.modemForIface("wwan0", 1)
	assert.True(t, ok)
	assert.EqualValues(t, 40, info.signalQuality)

	_, ok = b.modemForIface("ppp0", 2)
	assert.False(t, ok)
}
