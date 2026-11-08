package screenshot

import "testing"

func TestHyprlandMonitorGeometryFollowsRotation(t *testing.T) {
	monitors := []byte(`[
		{"name": "DP-1", "x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1.25, "transform": 0},
		{"name": "DP-2", "x": 2048, "y": 0, "width": 2560, "height": 1440, "scale": 1.25, "transform": 1},
		{"name": "DP-3", "x": 3200, "y": 0, "width": 2560, "height": 1440, "scale": 1, "transform": 7}
	]`)
	cases := []struct {
		name string
		want [4]int32
	}{
		{"DP-1", [4]int32{0, 0, 2048, 1152}},
		{"DP-2", [4]int32{2048, 0, 1152, 2048}},
		{"DP-3", [4]int32{3200, 0, 1440, 2560}},
	}
	for _, c := range cases {
		x, y, w, h, ok := hyprlandMonitorGeometry(monitors, c.name)
		if got := [4]int32{x, y, w, h}; !ok || got != c.want {
			t.Errorf("%s: got %v ok=%v want %v", c.name, got, ok, c.want)
		}
	}
}
