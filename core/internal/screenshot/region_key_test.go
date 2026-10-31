package screenshot

import "testing"

func TestHandleKeyEscapeCancels(t *testing.T) {
	for _, phase := range []selectorPhase{phaseSelect, phaseScroll} {
		r := &RegionSelector{running: true, phase: phase}
		r.handleKey("Escape", 1)
		if !r.cancelled || r.running {
			t.Errorf("phase %v: cancelled=%v running=%v after Escape", phase, r.cancelled, r.running)
		}
	}
}

func TestHandleKeyIgnoresReleaseAndCapsLock(t *testing.T) {
	r := &RegionSelector{running: true}
	r.handleKey("Escape", 0)
	r.handleKey("Caps_Lock", 1)
	if r.cancelled || !r.running {
		t.Errorf("cancelled=%v running=%v, want untouched", r.cancelled, r.running)
	}
}

func TestHandleKeyTogglesCapturedCursor(t *testing.T) {
	r := &RegionSelector{running: true, showCapturedCursor: true}
	r.handleKey("p", 1)
	if r.showCapturedCursor {
		t.Error("p did not toggle captured cursor off")
	}
	r.handleKey("p", 1)
	if !r.showCapturedCursor {
		t.Error("p did not toggle captured cursor back on")
	}
}

func TestHandleKeyTracksModifiers(t *testing.T) {
	r := &RegionSelector{running: true}
	r.handleKey("Control_R", 1)
	r.handleKey("Alt_L", 1)
	if !r.ctrlHeld || !r.altHeld {
		t.Errorf("ctrl=%v alt=%v after press, want both held", r.ctrlHeld, r.altHeld)
	}
	r.handleKey("Control_R", 0)
	r.handleKey("Alt_L", 0)
	if r.ctrlHeld || r.altHeld {
		t.Errorf("ctrl=%v alt=%v after release, want both released", r.ctrlHeld, r.altHeld)
	}
}

func TestHandleKeyOCRHoveredTarget(t *testing.T) {
	if !HasOCR() {
		t.Skip("tesseract not installed")
	}
	r, os := newOverlayFixture(t, 100, 100)
	r.running = true
	r.activeSurface = os
	target := SnapTarget{Name: "test", X: 10, Y: 10, Width: 40, Height: 40}
	r.hoveredTarget = &target

	r.handleKey("o", 1)
	if !r.ocrOnly || r.running {
		t.Fatalf("ocrOnly=%v running=%v after pressing o on hovered target", r.ocrOnly, r.running)
	}
}
