package screenshot

import (
	"testing"

	"github.com/duxlabs-dev/dux-go/wayland/client"
)

func newTestSurface(id uint32) *client.Surface {
	s := &client.Surface{}
	s.SetID(id)
	return s
}

func TestTouchInputSequence(t *testing.T) {
	surface := newTestSurface(100)

	os := &OutputSurface{
		output: &WaylandOutput{
			x: 0,
			y: 0,
		},
		logicalW:  1920,
		logicalH:  1080,
		wlSurface: surface,
	}

	r := &RegionSelector{
		running:  true,
		surfaces: []*OutputSurface{os},
	}

	// 1. Touch Down
	r.handleTouchDown(surface, 1, 100, 200)

	if !r.hasTouchPoint || r.touchPointId != 1 {
		t.Fatalf("expected hasTouchPoint=true, touchPointId=1, got hasTouchPoint=%v, id=%d", r.hasTouchPoint, r.touchPointId)
	}
	if !r.selection.dragging || !r.selection.hasSelection {
		t.Fatalf("expected dragging=true, hasSelection=true")
	}
	if r.selection.anchorX != 100 || r.selection.anchorY != 200 {
		t.Fatalf("expected anchor (100, 200), got (%.1f, %.1f)", r.selection.anchorX, r.selection.anchorY)
	}

	// 2. Ignore secondary touch point while primary is active
	surface2 := newTestSurface(200)
	r.handleTouchDown(surface2, 2, 500, 600)
	if r.touchPointId != 1 {
		t.Fatalf("expected touchPointId to stay 1, got %d", r.touchPointId)
	}

	// 3. Touch Motion with matching id
	r.handleTouchMotion(1, 400, 500)
	if r.selection.currentX != 400 || r.selection.currentY != 500 {
		t.Fatalf("expected current (400, 500), got (%.1f, %.1f)", r.selection.currentX, r.selection.currentY)
	}

	// 4. Touch Motion with mismatched id should be ignored
	r.handleTouchMotion(2, 900, 900)
	if r.selection.currentX != 400 || r.selection.currentY != 500 {
		t.Fatalf("expected current to remain (400, 500), got (%.1f, %.1f)", r.selection.currentX, r.selection.currentY)
	}

	// 5. Touch Up with mismatched id should not release
	r.handleTouchUp(2)
	if !r.hasTouchPoint || !r.selection.dragging {
		t.Fatalf("expected touch point to remain active on mismatched touch up")
	}

	// 6. Touch Up with matching id
	r.handleTouchUp(1)
	if r.hasTouchPoint || r.selection.dragging {
		t.Fatalf("expected hasTouchPoint=false, dragging=false after touch up")
	}
	if !r.selection.hasSelection {
		t.Fatalf("expected selection to be preserved after touch up")
	}
}

func TestTouchCancel(t *testing.T) {
	surface := newTestSurface(100)

	os := &OutputSurface{
		output: &WaylandOutput{
			x: 0,
			y: 0,
		},
		logicalW:  1920,
		logicalH:  1080,
		wlSurface: surface,
	}

	r := &RegionSelector{
		running:  true,
		surfaces: []*OutputSurface{os},
	}

	r.handleTouchDown(surface, 5, 50, 60)
	if !r.hasTouchPoint || !r.selection.dragging {
		t.Fatalf("expected active touch point")
	}

	r.handleTouchCancel()
	if r.hasTouchPoint || r.selection.dragging {
		t.Fatalf("expected touch point and dragging to be cleared on cancel")
	}
}

func TestTouchUpScrollPhase(t *testing.T) {
	surface := newTestSurface(100)

	os := &OutputSurface{
		output: &WaylandOutput{
			x: 0,
			y: 0,
		},
		logicalW:  1920,
		logicalH:  1080,
		wlSurface: surface,
	}

	sc := &Screenshoter{
		config: Config{NoConfirm: true},
	}

	r := &RegionSelector{
		screenshoter: sc,
		phase:        phaseScroll,
		running:      true,
		surfaces:     []*OutputSurface{os},
		selection: SelectionState{
			hasSelection: true,
			surface:      os,
		},
	}

	r.hasTouchPoint = true
	r.touchPointId = 3
	r.selection.dragging = true

	r.handleTouchUp(3)

	if r.hasTouchPoint || r.selection.dragging {
		t.Fatalf("expected touch point and dragging cleared")
	}

	// In scroll phase with NoConfirm, handleTouchUp must not call finishSelection / change running state
	if !r.running {
		t.Fatalf("expected running to stay true, did not expect finishSelection side-effects")
	}
}
