package colorpicker

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSurfaceState_ZeroScale(t *testing.T) {
	s := NewSurfaceState(FormatHex, false)
	s.SetScale(0)
	assert.Equal(t, int32(1), s.Scale())
}

func TestSurfaceState_ZeroDimensionConfigure(t *testing.T) {
	s := NewSurfaceState(FormatHex, false)

	err := s.OnLayerConfigure(0, 100)
	assert.NoError(t, err)

	err = s.OnLayerConfigure(100, 0)
	assert.NoError(t, err)

	err = s.OnLayerConfigure(-1, 100)
	assert.NoError(t, err)

	w, h := s.LogicalSize()
	assert.Equal(t, 0, w)
	assert.Equal(t, 0, h)
}

func TestBlendColors(t *testing.T) {
	bg := Color{R: 0, G: 0, B: 0, A: 255}
	fg := Color{R: 255, G: 255, B: 255, A: 255}

	result := blendColors(bg, fg, 0.0)
	assert.Equal(t, bg.R, result.R)
	assert.Equal(t, bg.G, result.G)
	assert.Equal(t, bg.B, result.B)

	result = blendColors(bg, fg, 1.0)
	assert.Equal(t, fg.R, result.R)
	assert.Equal(t, fg.G, result.G)
	assert.Equal(t, fg.B, result.B)

	result = blendColors(bg, fg, 0.5)
	assert.InDelta(t, 127, int(result.R), 1)
	assert.InDelta(t, 127, int(result.G), 1)
	assert.InDelta(t, 127, int(result.B), 1)

	result = blendColors(bg, fg, -1.0)
	assert.Equal(t, bg.R, result.R)

	result = blendColors(bg, fg, 2.0)
	assert.Equal(t, fg.R, result.R)
}

func newReadyState(t *testing.T, w, h int) *SurfaceState {
	t.Helper()
	s := NewSurfaceState(FormatHex, false)
	if err := s.OnScreencopyBuffer(FormatXRGB8888, w, h, w*4+16); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.Destroy)
	data := s.ScreenBuffer().Data()
	for i := range data {
		data[i] = byte(i*31 + i/7)
	}
	if err := s.OnLayerConfigure(w, h); err != nil {
		t.Fatal(err)
	}
	s.OnScreencopyReady()
	return s
}

func TestSurfaceState_RedrawIncremental(t *testing.T) {
	const w, h = 400, 300
	s := newReadyState(t, w, h)
	screen := s.ScreenBuffer()

	reference := func(px, py int, overlay bool) []byte {
		ref, err := CreateShmBuffer(w, h, screen.Stride)
		if err != nil {
			t.Fatal(err)
		}
		defer ref.Close()
		ref.CopyFrom(screen)
		if overlay {
			c := GetPixelColorWithFormat(screen, px, py, s.screenFormat)
			drawMagnifierWithInversion(ref.Data(), ref.Stride, w, h, screen.Data(), screen.Stride, w, h, px, py, c, false, s.screenFormat)
			drawColorPreview(ref.Data(), ref.Stride, w, h, px, py, c, FormatHex, false, s.screenFormat)
		}
		return append([]byte(nil), ref.Data()...)
	}

	inDamage := func(x, y int, damage []rect) bool {
		for _, r := range damage {
			if x >= r.x && x < r.x+r.w && y >= r.y && y < r.y+r.h {
				return true
			}
		}
		return false
	}

	var onScreen []byte
	positions := [][2]int{{10, 10}, {200, 150}, {205, 152}, {399, 299}, {0, 299}, {-1, -1}, {120, 40}, {125, 40}, {300, 290}}
	for i, pos := range positions {
		hidden := pos[0] < 0
		var buf *ShmBuffer
		var damage []rect
		px, py := pos[0], pos[1]
		switch {
		case hidden:
			buf, damage = s.RedrawScreenOnly()
		default:
			s.OnPointerMotion(float64(px), float64(py))
			buf, damage = s.Redraw()
		}
		if buf == nil {
			t.Fatalf("step %d: no buffer", i)
		}
		want := reference(px, py, !hidden)
		if !bytesEqual(buf.Data(), want) {
			t.Fatalf("step %d: incremental frame differs from full render", i)
		}
		if onScreen != nil {
			for y := range h {
				for x := range w {
					off := y*buf.Stride + x*4
					if bytesEqual(want[off:off+4], onScreen[off:off+4]) || inDamage(x, y, damage) {
						continue
					}
					t.Fatalf("step %d: pixel %d,%d changed outside damage %v", i, x, y, damage)
				}
			}
		}
		onScreen = want
		s.SwapBuffers()
	}
}

func bytesEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
