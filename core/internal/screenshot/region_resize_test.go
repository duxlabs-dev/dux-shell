package screenshot

import (
	"bytes"
	"math"
	"math/rand"
	"testing"
)

func TestResizeHandleAt(t *testing.T) {
	r := &RegionSelector{}
	r.selectRect(100, 200, 400, 350)

	cases := []struct {
		name     string
		px, py   float64
		expected resizeHandle
	}{
		{"near TopLeft", 108, 206, handleTopLeft},
		{"near TopRight", 392, 196, handleTopRight},
		{"near BottomLeft", 105, 345, handleBottomLeft},
		{"near BottomRight", 406, 354, handleBottomRight},
		{"center", 250, 275, handleNone},
		{"outside", 50, 50, handleNone},
		{"just outside TopLeft", 100 - resizeHitRadius - 2, 200, handleNone},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := r.resizeHandleAt(tc.px, tc.py)
			if got != tc.expected {
				t.Fatalf("resizeHandleAt(%.1f, %.1f) = %v, want %v", tc.px, tc.py, got, tc.expected)
			}
		})
	}

	// When no selection exists
	r.selection.hasSelection = false
	if got := r.resizeHandleAt(100, 200); got != handleNone {
		t.Fatalf("expected handleNone when no selection, got %v", got)
	}
}

func TestBeginSelectionResize(t *testing.T) {
	tests := []struct {
		handle      resizeHandle
		wantAnchorX float64
		wantAnchorY float64
		wantCurX    float64
		wantCurY    float64
	}{
		{handleTopLeft, 400, 350, 100, 200},
		{handleTopRight, 100, 350, 400, 200},
		{handleBottomLeft, 400, 200, 100, 350},
		{handleBottomRight, 100, 200, 400, 350},
	}

	for _, tc := range tests {
		r := &RegionSelector{}
		r.selectRect(100, 200, 400, 350)
		ok := r.beginSelectionResize(tc.handle, 150, 220)
		if !ok {
			t.Fatalf("beginSelectionResize(%v) returned false", tc.handle)
		}
		if r.resizingHandle != tc.handle {
			t.Errorf("resizingHandle = %v, want %v", r.resizingHandle, tc.handle)
		}
		if !r.selection.dragging || r.movingSelection {
			t.Errorf("dragging = %v, moving = %v", r.selection.dragging, r.movingSelection)
		}
		if r.selection.anchorX != tc.wantAnchorX || r.selection.anchorY != tc.wantAnchorY {
			t.Errorf("anchor = (%.1f, %.1f), want (%.1f, %.1f)", r.selection.anchorX, r.selection.anchorY, tc.wantAnchorX, tc.wantAnchorY)
		}
		if r.selection.currentX != tc.wantCurX || r.selection.currentY != tc.wantCurY {
			t.Errorf("current = (%.1f, %.1f), want (%.1f, %.1f)", r.selection.currentX, r.selection.currentY, tc.wantCurX, tc.wantCurY)
		}
	}
}

func TestDrawOverlayIncrementalWithHandles(t *testing.T) {
	const w, h = 160, 120
	r, os := newOverlayFixture(t, w, h)
	incr := newFrameBuffer(t, r, os)
	shown := newFrameBuffer(t, r, os)
	rng := rand.New(rand.NewSource(42))

	var prev *overlay
	for i := range 300 {
		var cur *overlay
		r.ctrlHeld = rng.Intn(2) == 1
		switch rng.Intn(8) {
		case 0:
			r.selection.hasSelection = false
		default:
			r.selectRect(rng.Float64()*w, rng.Float64()*h, rng.Float64()*w, rng.Float64()*h)
			cur = r.overlayFor(os, incr)
		}
		damage := overlayDamage(prev, cur)
		r.drawOverlay(os, incr, prev, cur)

		full := newFrameBuffer(t, r, os)
		r.drawOverlay(os, full, nil, cur)
		if !bytes.Equal(incr.Data(), full.Data()) {
			t.Fatalf("step %d (ctrl=%v): incremental frame differs from full render", i, r.ctrlHeld)
		}

		for y := range h {
			for x := range w {
				off := y*full.Stride + x*4
				if bytes.Equal(full.Data()[off:off+4], shown.Data()[off:off+4]) {
					continue
				}
				if !inRects(x, y, damage) {
					t.Fatalf("step %d (ctrl=%v): pixel %d,%d changed outside damage %v", i, r.ctrlHeld, x, y, damage)
				}
			}
		}
		copy(shown.Data(), full.Data())
		prev = cur
	}
}

func TestResizeInvertedDrag(t *testing.T) {
	r := &RegionSelector{}
	r.selectRect(100, 100, 200, 200)

	// Begin resizing TopLeft
	r.beginSelectionResize(handleTopLeft, 100, 100)
	if r.selection.anchorX != 200 || r.selection.anchorY != 200 {
		t.Fatalf("anchor = (%f, %f), want (200, 200)", r.selection.anchorX, r.selection.anchorY)
	}

	// Drag past opposite corner (anchor) to (300, 300)
	os := &OutputSurface{
		output:   &WaylandOutput{x: 0, y: 0},
		logicalW: 1920,
		logicalH: 1080,
	}
	r.selection.surface = os
	r.updateSelectionCurrent(os, 300, 300)

	minX := math.Min(r.selection.anchorX, r.selection.currentX)
	maxX := math.Max(r.selection.anchorX, r.selection.currentX)
	minY := math.Min(r.selection.anchorY, r.selection.currentY)
	maxY := math.Max(r.selection.anchorY, r.selection.currentY)

	if minX != 200 || maxX != 300 || minY != 200 || maxY != 300 {
		t.Errorf("inverted bounds = (%f, %f, %f, %f), want (200, 200, 300, 300)", minX, minY, maxX, maxY)
	}
}

func TestResizeTinySelectionHitTest(t *testing.T) {
	r := &RegionSelector{}
	// 4x4 tiny selection
	r.selectRect(100, 100, 104, 104)

	// Closer to TopLeft (101, 101)
	if got := r.resizeHandleAt(101, 101); got != handleTopLeft {
		t.Errorf("got %v, want %v", got, handleTopLeft)
	}

	// Closer to BottomRight (103, 103)
	if got := r.resizeHandleAt(103, 103); got != handleBottomRight {
		t.Errorf("got %v, want %v", got, handleBottomRight)
	}
}

func TestOverlayDeltaIdenticalOverlayNoHandleDimming(t *testing.T) {
	o1 := &overlay{
		interior:    dirtyRect{10, 10, 100, 100},
		top:         true,
		bottom:      true,
		left:        true,
		right:       true,
		showHandles: true,
		scaleX:      1.0,
	}
	o2 := &overlay{
		interior:    dirtyRect{10, 10, 100, 100},
		top:         true,
		bottom:      true,
		left:        true,
		right:       true,
		showHandles: true,
		scaleX:      1.0,
	}

	dim, _ := overlayDelta(o1, o2)
	for _, d := range dim {
		for _, h := range o1.handleRects() {
			if d == h {
				t.Errorf("handle rect %v should not be re-dimmed when overlay is identical", h)
			}
		}
	}
}

func TestHUDDimensionsContainText(t *testing.T) {
	const bufW, bufH = 1920, 1080
	stride := bufW * 4

	for _, noConfirm := range []bool{false, true} {
		for _, showCursor := range []bool{false, true} {
			r := &RegionSelector{
				showCapturedCursor: showCursor,
				screenshoter: &Screenshoter{
					config: Config{NoConfirm: noConfirm},
				},
			}

			// When scale <= 0, hudDimensions should return zero
			hx, hy, hw, hh := r.hudDimensions(bufW, bufH, 0)
			if hx != 0 || hy != 0 || hw != 0 || hh != 0 {
				t.Fatalf("expected 0 dimensions for scale 0, got %d, %d, %d, %d", hx, hy, hw, hh)
			}

			for _, scale := range []int{1, 2} {
				hudX, hudY, hudW, hudH := r.hudDimensions(bufW, bufH, scale)
				data := make([]byte, bufH*stride)
				r.drawHUD(data, stride, bufW, bufH, uint32(FormatARGB8888), scale)

				// Assert no lit pixel falls outside the pill boundaries
				for y := range bufH {
					for x := range bufW {
						off := y*stride + x*4
						if data[off] != 0 || data[off+1] != 0 || data[off+2] != 0 || data[off+3] != 0 {
							if x < hudX || x >= hudX+hudW || y < hudY || y >= hudY+hudH {
								t.Fatalf("scale=%d noConfirm=%v showCursor=%v: pixel (%d, %d) is non-zero outside HUD pill [%d..%d, %d..%d]",
									scale, noConfirm, showCursor, x, y, hudX, hudX+hudW, hudY, hudY+hudH)
							}
						}
					}
				}
			}
		}
	}
}

func TestHUDScale(t *testing.T) {
	tests := []struct {
		hudOpt         string
		effectiveScale float64
		expectedScale  int
	}{
		{"auto", 1.8, 2},
		{"auto", 2.4, 2},
		{"OFF", 2.0, 0},
		{"-1", 1.0, 0},
		{"1.5", 1.0, 2},
		{"1000", 1.0, 4},
		{"0.2", 1.0, 1},
		{"invalid", 1.7, 2},
	}

	for _, tc := range tests {
		r := &RegionSelector{
			screenshoter: &Screenshoter{
				config: Config{HUD: tc.hudOpt},
			},
		}
		got := r.hudScale(tc.effectiveScale)
		if got != tc.expectedScale {
			t.Errorf("hudScale(%q, %v) = %d, expected %d", tc.hudOpt, tc.effectiveScale, got, tc.expectedScale)
		}
	}
}

func TestOverlayDeltaHandlesClampedMonitorEdge(t *testing.T) {
	prev := &overlay{
		interior:    dirtyRect{100, 100, 1920, 1080},
		top:         true,
		bottom:      true,
		left:        true,
		right:       true,
		showHandles: true,
		scaleX:      1.0,
	}
	cur := &overlay{
		interior:    dirtyRect{100, 100, 1920, 1080},
		top:         true,
		bottom:      true,
		left:        true,
		right:       false,
		showHandles: true,
		scaleX:      1.0,
	}

	dim, _ := overlayDelta(prev, cur)
	rightTopHandle := prev.handleRects()[1] // TopRight
	for _, piece := range rightTopHandle.minus(cur.interior) {
		found := false
		for _, d := range dim {
			if d == piece {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("expected piece %v of right-top handle in dim rects, got %v", piece, dim)
		}
	}

	damage := overlayDamage(prev, cur)
	foundDamage := false
	for _, d := range damage {
		if d == rightTopHandle {
			foundDamage = true
			break
		}
	}
	if !foundDamage {
		t.Errorf("expected right-top handle %v in damage rects when crossing monitor edge, got %v", rightTopHandle, damage)
	}
}
