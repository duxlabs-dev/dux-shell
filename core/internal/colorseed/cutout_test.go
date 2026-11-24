package colorseed

import (
	"image"
	imgcolor "image/color"
	"math"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func gray(v uint8) imgcolor.NRGBA {
	return imgcolor.NRGBA{R: v, G: v, B: v, A: 255}
}

// alphaAt reads the cut-out at a point given as a fraction of its side.
func alphaAt(img *image.NRGBA, fx, fy float64) uint8 {
	return img.NRGBAAt(int(fx*float64(CutoutDim)), int(fy*float64(CutoutDim))).A
}

// markBounds is the box of the cut-out's at least half opaque pixels.
func markBounds(img *image.NRGBA) image.Rectangle {
	box := image.Rectangle{}
	for y := range CutoutDim {
		for x := range CutoutDim {
			if img.NRGBAAt(x, y).A >= 128 {
				box = box.Union(image.Rect(x, y, x+1, y+1))
			}
		}
	}
	return box
}

func TestCutout(t *testing.T) {
	plus := func(ex, ey float64) bool {
		return (math.Abs(ex) < 0.4 && math.Abs(ey) < 0.1) || (math.Abs(ex) < 0.1 && math.Abs(ey) < 0.4)
	}
	tests := []struct {
		name  string
		draw  func(ex, ey float64) (imgcolor.NRGBA, bool)
		stage string
		// Points of the cut-out, as fractions of its side, that must be the mark and that must be clear.
		mark, clear [][2]float64
	}{
		{
			name: "a plus on a round plate keeps the plus alone",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				if plus(ex, ey) {
					return white, true
				}
				return blue, math.Hypot(ex, ey) <= 1
			},
			stage: StagePlateStrip,
			mark:  [][2]float64{{0.5, 0.5}, {0.1, 0.5}, {0.5, 0.9}},
			clear: [][2]float64{{0.2, 0.2}, {0.8, 0.8}, {0.02, 0.02}},
		},
		{
			// A flat plate color is up to 60 away from the plate at its top and bottom.
			name: "a plate shaded top to bottom strips as cleanly",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				if plus(ex, ey) {
					return white, true
				}
				shade := uint8(90 + 35*ey)
				return imgcolor.NRGBA{R: shade / 3, G: shade / 2, B: shade + 60, A: 255}, math.Hypot(ex, ey) <= 1
			},
			stage: StagePlateStrip,
			mark:  [][2]float64{{0.5, 0.5}, {0.5, 0.9}},
			clear: [][2]float64{{0.2, 0.2}, {0.8, 0.8}, {0.2, 0.8}, {0.8, 0.2}},
		},
		{
			name: "an open silhouette keeps its shape, its dark half fainter",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				if math.Abs(ex-ey) < 0.3 {
					return imgcolor.NRGBA{R: 0x1e, G: 0x88, B: 0xe5, A: 255}, true
				}
				return imgcolor.NRGBA{R: 0x0b, G: 0x34, B: 0x58, A: 255}, math.Abs(ex+ey) < 0.3
			},
			stage: StageDepthSil,
			mark:  [][2]float64{{0.5, 0.5}, {0.15, 0.15}},
			clear: [][2]float64{{0.5, 0.1}, {0.1, 0.5}},
		},
		{
			name: "a full-bleed circle of two colors loses its white ring and the seam between them",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				r := math.Hypot(ex, ey)
				switch {
				case r > 1:
					return imgcolor.NRGBA{}, false
				case r > 0.35 && r < 0.5:
					return white, true
				case r <= 0.35:
					return blue, true
				case ex < 0:
					return red, true
				}
				return green, true
			},
			stage: StageCutoutSil,
			mark:  [][2]float64{{0.5, 0.5}, {0.2, 0.5}, {0.8, 0.5}},
			clear: [][2]float64{{0.31, 0.5}, {0.69, 0.5}, {0.5, 0.1}, {0.5, 0.9}},
		},
		{
			// Ghostty: a bevel too uneven to be a plate around a dark screen with a bright ghost.
			name: "a framed dark tile keeps its bright marks and its frame",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				if max(math.Abs(ex), math.Abs(ey)) > 0.85 {
					return gray(uint8(120 + 100*(ex+ey)/2)), true
				}
				if math.Abs(ex) < 0.25 && math.Abs(ey) < 0.25 {
					return white, true
				}
				return imgcolor.NRGBA{R: 0x10, G: 0x18, B: 0x40 + uint8(10*ex), A: 255}, true
			},
			stage: StageTileLuma,
			mark:  [][2]float64{{0.5, 0.5}},
			clear: [][2]float64{{0.25, 0.5}, {0.5, 0.75}},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			img := image.NewNRGBA(image.Rect(0, 0, 200, 200))
			paint(img, tc.draw)
			cut, stage, ok := Cutout(img)
			require.True(t, ok)
			assert.Equal(t, tc.stage, stage)
			require.Equal(t, image.Rect(0, 0, CutoutDim, CutoutDim), cut.Bounds())
			for i := 0; i < len(cut.Pix); i += 4 {
				require.Equal(t, []uint8{255, 255, 255}, cut.Pix[i:i+3], "white, the mark all in alpha")
			}
			for _, p := range tc.mark {
				assert.Greater(t, alphaAt(cut, p[0], p[1]), uint8(128), "mark at %v", p)
			}
			for _, p := range tc.clear {
				assert.Less(t, alphaAt(cut, p[0], p[1]), uint8(16), "clear at %v", p)
			}

			box := markBounds(cut)
			long := max(box.Dx(), box.Dy())
			assert.InDelta(t, float64(CutoutDim)/(1+2*cutoutMargin), float64(long), 6)
			assert.InDelta(t, CutoutDim/2, (box.Min.X+box.Max.X)/2, 3)
			assert.InDelta(t, CutoutDim/2, (box.Min.Y+box.Max.Y)/2, 3)
		})
	}

	_, _, ok := Cutout(image.NewNRGBA(image.Rect(0, 0, 64, 64)))
	assert.False(t, ok, "nothing drawn")
}

// The darker of two parts of an open logo keeps less alpha, so a fold still reads.
func TestCutoutDepthShades(t *testing.T) {
	img := image.NewNRGBA(image.Rect(0, 0, 200, 200))
	paint(img, func(ex, ey float64) (imgcolor.NRGBA, bool) {
		if math.Abs(ex-ey) < 0.3 {
			return imgcolor.NRGBA{R: 0x1e, G: 0x88, B: 0xe5, A: 255}, true
		}
		return imgcolor.NRGBA{R: 0x0b, G: 0x34, B: 0x58, A: 255}, math.Abs(ex+ey) < 0.3
	})
	cut, _, ok := Cutout(img)
	require.True(t, ok)
	light, dark := alphaAt(cut, 0.15, 0.15), alphaAt(cut, 0.85, 0.15)
	assert.Equal(t, uint8(255), light)
	assert.InDelta(t, depthFloor*255, float64(dark), 8)
}

// A face one pixel across has no radius to measure the inner square by, so it is no tile.
func TestTileLumaNeedsAFace(t *testing.T) {
	img := image.NewNRGBA(image.Rect(0, 0, 3, 10))
	for y := range 10 {
		v := uint8(0)
		if y >= 8 {
			v = 255
		}
		img.SetNRGBA(1, y, gray(v))
	}
	_, ok := tileLuma(img)
	assert.False(t, ok)
}
