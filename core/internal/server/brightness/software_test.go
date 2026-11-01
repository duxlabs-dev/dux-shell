package brightness

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestUncoveredOutputs(t *testing.T) {
	tests := []struct {
		name         string
		outputs      []string
		hasBacklight bool
		ddc          []string
		want         []string
	}{
		{"internal panel with backlight", []string{"eDP-1"}, true, nil, []string{}},
		{"oled panel without backlight", []string{"eDP-1"}, false, nil, []string{"eDP-1"}},
		{"external monitor with ddc", []string{"DP-1"}, false, []string{"DP-1"}, []string{}},
		{"external monitor without ddc", []string{"DP-1"}, true, nil, []string{"DP-1"}},
		{"headless output", []string{"HEADLESS-1"}, false, nil, []string{}},
		{
			"laptop with mixed monitors",
			[]string{"DP-1", "HDMI-A-1", "eDP-1"}, true, []string{"HDMI-A-1"},
			[]string{"DP-1"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, uncoveredOutputs(tt.outputs, tt.hasBacklight, tt.ddc))
		})
	}
}

func TestTakenOverOutputs(t *testing.T) {
	dimmed := map[string]int{"DP-1": 40}
	tests := []struct {
		name      string
		outputs   []string
		uncovered []string
		levels    map[string]int
		want      []string
	}{
		{"ddc took over a dimmed output", []string{"DP-1"}, []string{}, dimmed, []string{"DP-1"}},
		{"dimmed output still uncovered", []string{"DP-1"}, []string{"DP-1"}, dimmed, []string{}},
		{"dimmed output disconnected", []string{"HDMI-A-1"}, []string{"HDMI-A-1"}, dimmed, []string{}},
		{"covered output without a level", []string{"DP-1"}, []string{}, nil, []string{}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, takenOverOutputs(tt.outputs, tt.uncovered, tt.levels))
		})
	}
}
