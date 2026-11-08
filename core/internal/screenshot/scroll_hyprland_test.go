package screenshot

import (
	"slices"
	"testing"
)

func TestHyprlandScrollCommands(t *testing.T) {
	focus := []string{"dispatch", `hl.dsp.focus({ window = "address:0x55f56b093cf0" })`}
	bind := []string{"eval", `hl.bind("Return", hl.dsp.exec_cmd("kill -USR1 4242")); hl.bind("Escape", hl.dsp.exec_cmd("kill -USR2 4242"))`}
	unbind := []string{"eval", `hl.unbind("Return"); hl.unbind("Escape")`}
	if got := hyprlandFocusArgs("0x55f56b093cf0"); !slices.Equal(got, focus) {
		t.Errorf("focus: got %q want %q", got, focus)
	}
	if got := hyprlandBindScrollKeysArgs(4242); !slices.Equal(got, bind) {
		t.Errorf("bind: got %q want %q", got, bind)
	}
	if got := hyprlandUnbindScrollKeysArgs(); !slices.Equal(got, unbind) {
		t.Errorf("unbind: got %q want %q", got, unbind)
	}
}

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
