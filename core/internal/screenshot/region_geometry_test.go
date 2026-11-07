package screenshot

import (
	"testing"
)

func TestSelectedLogicalGeometry(t *testing.T) {
	mockSurface := &OutputSurface{
		logicalW: 3840,
		logicalH: 2160,
		output: &WaylandOutput{
			name:            "DP-1",
			x:               0,
			y:               0,
			fractionalScale: 1.0,
		},
		screenBuf: &ShmBuffer{
			Width:  3840,
			Height: 2160,
			Stride: 3840 * 4,
		},
	}

	tests := []struct {
		name          string
		anchorX       float64
		anchorY       float64
		currentX      float64
		currentY      float64
		shiftHeld     bool
		hasSelection  bool
		wantX         int
		wantY         int
		wantW         int
		wantH         int
		wantOK        bool
		wantFormatted string
	}{
		{
			name:          "standard drag inclusive edges",
			anchorX:       2263,
			anchorY:       118,
			currentX:      2776,
			currentY:      431,
			hasSelection:  true,
			wantX:         2263,
			wantY:         118,
			wantW:         514,
			wantH:         314,
			wantOK:        true,
			wantFormatted: "2263,118 514x314",
		},
		{
			name:          "inverted drag bottom-right to top-left",
			anchorX:       1000,
			anchorY:       800,
			currentX:      400,
			currentY:      300,
			hasSelection:  true,
			wantX:         400,
			wantY:         300,
			wantW:         601,
			wantH:         501,
			wantOK:        true,
			wantFormatted: "400,300 601x501",
		},
		{
			name:          "shift held square constraint",
			anchorX:       100,
			anchorY:       100,
			currentX:      500,
			currentY:      300,
			shiftHeld:     true,
			hasSelection:  true,
			wantX:         100,
			wantY:         100,
			wantW:         201,
			wantH:         201,
			wantOK:        true,
			wantFormatted: "100,100 201x201",
		},
		{
			name:         "no selection",
			hasSelection: false,
			wantOK:       false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := &RegionSelector{
				shiftHeld: tc.shiftHeld,
				selection: SelectionState{
					hasSelection: tc.hasSelection,
					surface:      mockSurface,
					anchorX:      tc.anchorX,
					anchorY:      tc.anchorY,
					currentX:     tc.currentX,
					currentY:     tc.currentY,
				},
			}

			reg, ok := r.selectedLogicalGeometry()
			if ok != tc.wantOK {
				t.Fatalf("selectedLogicalGeometry() ok = %v, want %v", ok, tc.wantOK)
			}
			if !tc.wantOK {
				return
			}

			if int(reg.X) != tc.wantX || int(reg.Y) != tc.wantY || int(reg.Width) != tc.wantW || int(reg.Height) != tc.wantH {
				t.Errorf("got (%d, %d, %d, %d), want (%d, %d, %d, %d)",
					reg.X, reg.Y, reg.Width, reg.Height, tc.wantX, tc.wantY, tc.wantW, tc.wantH)
			}

			formatted := reg.GeometryString()
			if formatted != tc.wantFormatted {
				t.Errorf("formatted = %q, want %q", formatted, tc.wantFormatted)
			}
		})
	}
}

func TestSelectedLogicalGeometryPreSelection(t *testing.T) {
	mockSurface := &OutputSurface{
		logicalW: 1920,
		logicalH: 1080,
		output: &WaylandOutput{
			name:            "eDP-1",
			x:               0,
			y:               0,
			fractionalScale: 1.0,
		},
		screenBuf: &ShmBuffer{
			Width:  1920,
			Height: 1080,
			Stride: 1920 * 4,
		},
	}

	r := &RegionSelector{
		preSelect: Region{
			X:      2263,
			Y:      118,
			Width:  513,
			Height: 313,
			Output: "eDP-1",
		},
	}

	r.applyPreSelection(mockSurface)
	reg, ok := r.selectedLogicalGeometry()
	if !ok {
		t.Fatal("expected preselection to produce valid geometry")
	}

	if reg.X != 2263 || reg.Y != 118 || reg.Width != 513 || reg.Height != 313 {
		t.Errorf("got (%d, %d, %d, %d), want (2263, 118, 513, 313)",
			reg.X, reg.Y, reg.Width, reg.Height)
	}
	if got := reg.GeometryString(); got != "2263,118 513x313" {
		t.Errorf("GeometryString() = %q, want %q", got, "2263,118 513x313")
	}
}

func TestSelectedLogicalGeometryPreSelectionScaled(t *testing.T) {
	surface := &OutputSurface{
		logicalW: 1920,
		logicalH: 1080,
		output: &WaylandOutput{
			name:            "eDP-1",
			fractionalScale: 2,
		},
		screenBuf: &ShmBuffer{
			Width:  3840,
			Height: 2160,
			Stride: 3840 * 4,
		},
	}
	r := &RegionSelector{
		preSelect: Region{
			X:      200,
			Y:      100,
			Width:  400,
			Height: 300,
			Output: "eDP-1",
		},
	}

	r.applyPreSelection(surface)
	got, ok := r.selectedLogicalGeometry()
	if !ok {
		t.Fatal("expected scaled preselection to produce valid geometry")
	}
	if got.X != 200 || got.Y != 100 || got.Width != 400 || got.Height != 300 {
		t.Fatalf("got (%d, %d, %d, %d), want (200, 100, 400, 300)",
			got.X, got.Y, got.Width, got.Height)
	}
}

func TestLogicalRegionFromDevicePixels(t *testing.T) {
	out := &WaylandOutput{
		name:            "eDP-1",
		x:               0,
		y:               0,
		fractionalScale: 2.0,
	}

	reg := logicalRegionFromDevicePixels(out, 3155, 50, 640, 442)
	if reg.X != 1578 || reg.Y != 25 || reg.Width != 320 || reg.Height != 221 {
		t.Fatalf("logicalRegionFromDevicePixels() = (%d, %d, %d, %d), want (1578, 25, 320, 221)",
			reg.X, reg.Y, reg.Width, reg.Height)
	}
	if reg.Output != "eDP-1" {
		t.Fatalf("Output = %q, want %q", reg.Output, "eDP-1")
	}
}

func TestRegionCaptureScales(t *testing.T) {
	tests := []struct {
		name                    string
		compositor              Compositor
		wantCapture, wantResult float64
	}{
		{"protocol compositor", CompositorNiri, 1, 2},
		{"Mango", CompositorMango, 2, 2},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			captureScale, resultScale := regionCaptureScales(tc.compositor, 2)
			if captureScale != tc.wantCapture || resultScale != tc.wantResult {
				t.Fatalf("regionCaptureScales() = (%v, %v), want (%v, %v)",
					captureScale, resultScale, tc.wantCapture, tc.wantResult)
			}
		})
	}
}

func TestWaylandOutputBoundsScaled(t *testing.T) {
	// DetectCompositor caches its result, so inside a live Hyprland session the test would exec hyprctl
	prev := detectedCompositor
	detectedCompositor = CompositorUnknown
	t.Cleanup(func() { detectedCompositor = prev })
	out := &WaylandOutput{
		name:            "DP-2",
		x:               1920,
		y:               0,
		width:           3840,
		height:          2160,
		scale:           2,
		fractionalScale: 2.0,
	}

	b := out.bounds()
	if b.X != 1920 || b.Y != 0 || b.Width != 1920 || b.Height != 1080 {
		t.Errorf("bounds() = (%d, %d, %d, %d), want (1920, 0, 1920, 1080)",
			b.X, b.Y, b.Width, b.Height)
	}
}
