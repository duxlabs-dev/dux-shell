package screenshot

import "testing"

// Hyprland scales the region by the monitor scale itself; device pixels here
// captured a box offset and enlarged by the scale on fractional outputs
func TestScrollCaptureRect(t *testing.T) {
	cases := []struct {
		comp  Compositor
		scale float64
		want  [4]int
	}{
		{CompositorHyprland, 1.25, [4]int{1230, 160, 642, 480}},
		{CompositorMango, 1.25, [4]int{1538, 200, 802, 600}},
		{CompositorHyprland, 1, [4]int{1538, 200, 802, 600}},
	}
	for _, c := range cases {
		x, y, w, h := scrollCaptureRect(c.comp, c.scale, 1538, 200, 802, 600)
		if got := [4]int{x, y, w, h}; got != c.want {
			t.Errorf("compositor %d scale %v: got %v want %v", c.comp, c.scale, got, c.want)
		}
	}
}
