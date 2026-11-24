package colorseed

import (
	"bytes"
	"compress/gzip"
	"image"
	imgcolor "image/color"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"testing"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testDim = 128

// paint fills every pixel whose center fn colors; fn gets the offset from the canvas center as a fraction of half its size.
func paint(img *image.NRGBA, fn func(ex, ey float64) (imgcolor.NRGBA, bool)) {
	half := float64(img.Bounds().Dx()) / 2
	for y := range img.Bounds().Dy() {
		for x := range img.Bounds().Dx() {
			if c, ok := fn((float64(x)+0.5-half)/half, (float64(y)+0.5-half)/half); ok {
				img.SetNRGBA(x, y, c)
			}
		}
	}
}

var (
	blue   = imgcolor.NRGBA{R: 0x1e, G: 0x88, B: 0xe5, A: 255}
	white  = imgcolor.NRGBA{R: 255, G: 255, B: 255, A: 255}
	red    = imgcolor.NRGBA{R: 0xe5, G: 0x39, B: 0x35, A: 255}
	green  = imgcolor.NRGBA{R: 0x2e, G: 0x7d, B: 0x32, A: 255}
	yellow = imgcolor.NRGBA{R: 0xfd, G: 0xd8, B: 0x35, A: 255}
)

func TestPlateAndReach(t *testing.T) {
	tests := []struct {
		name  string
		draw  func(ex, ey float64) (imgcolor.NRGBA, bool)
		plate bool
		reach float64
	}{
		{
			name: "a round plate under a small logo",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				r := math.Hypot(ex, ey)
				if r < 0.3 {
					return white, true
				}
				return blue, r <= 1
			},
			plate: true, reach: 1,
		},
		{
			name: "a lone logo of many colors",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				quadrant := []imgcolor.NRGBA{red, green, blue, yellow}[btoi(ex > 0)+2*btoi(ey > 0)]
				return quadrant, math.Hypot(ex, ey) <= 0.9
			},
			reach: 0.9,
		},
		{
			name: "an outline around a body of another color covers too little",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				r := math.Hypot(ex, ey)
				if r > 0.8 && r < 0.94 {
					return blue, true
				}
				return red, r <= 1
			},
			reach: 1,
		},
		{
			name: "a full square",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				if math.Hypot(ex, ey) < 0.3 {
					return white, true
				}
				return blue, true
			},
			plate: true, reach: math.Sqrt2,
		},
		{
			name: "one color all over is the logo, not a plate",
			draw: func(float64, float64) (imgcolor.NRGBA, bool) {
				return blue, true
			},
			reach: math.Sqrt2,
		},
		{
			name: "a dark rounded square under a light mark",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				if math.Abs(ex) < 0.35 && math.Abs(ey) < 0.35 {
					return white, true
				}
				cx, cy := max(math.Abs(ex)-0.75, 0), max(math.Abs(ey)-0.75, 0)
				return blue, math.Hypot(cx, cy) <= 0.25
			},
			plate: true, reach: 0.75*math.Sqrt2 + 0.25,
		},
		{
			// VS Code: the edge it does reach is all one color, but most of the band is transparent.
			name: "an open silhouette of one color at its edge",
			draw: func(ex, ey float64) (imgcolor.NRGBA, bool) {
				if math.Hypot(ex, ey) < 0.3 {
					return white, true
				}
				return blue, math.Abs(ex-ey) < 0.35 || math.Abs(ex+ey) < 0.35
			},
			reach: math.Sqrt2,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			img := image.NewNRGBA(image.Rect(0, 0, testDim, testDim))
			paint(img, tc.draw)
			plate, ok := Plate(img)
			assert.Equal(t, tc.plate, ok)
			if tc.plate {
				assert.Equal(t, color.NewARGB(255, blue.R, blue.G, blue.B), plate)
			}
			assert.InDelta(t, tc.reach, Reach(img), 0.02)
		})
	}

	assert.Zero(t, Reach(image.NewNRGBA(image.Rect(0, 0, testDim, testDim))))
	_, ok := Plate(image.NewNRGBA(image.Rect(0, 0, testDim, testDim)))
	assert.False(t, ok, "nothing drawn")
}

func btoi(b bool) int {
	if b {
		return 1
	}
	return 0
}

// The generator measures an icon centered in a square, so a tall icon must not stick to the left or top.
func TestIconImageCentersAndKeepsAspect(t *testing.T) {
	dir := t.TempDir()
	svg := filepath.Join(dir, "tall.svg")
	require.NoError(t, os.WriteFile(svg, []byte(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10 -10 20 40"><rect x="-10" y="-10" width="20" height="40" fill="#2e7d32"/></svg>`), 0o644))
	wide := filepath.Join(dir, "wide.png")
	src := image.NewNRGBA(image.Rect(0, 0, 20, 10))
	paint(src, func(float64, float64) (imgcolor.NRGBA, bool) { return green, true })
	f, err := os.Create(wide)
	require.NoError(t, err)
	require.NoError(t, png.Encode(f, src))
	require.NoError(t, f.Close())

	svgz := filepath.Join(dir, "tall.SVGZ")
	data, err := os.ReadFile(svg)
	require.NoError(t, err)
	var zipped bytes.Buffer
	zw := gzip.NewWriter(&zipped)
	_, err = zw.Write(data)
	require.NoError(t, err)
	require.NoError(t, zw.Close())
	require.NoError(t, os.WriteFile(svgz, zipped.Bytes(), 0o644))

	tests := []struct {
		path           string
		x0, y0, x1, y1 int
	}{
		{path: svg, x0: 32, y0: 0, x1: 96, y1: 128},
		{path: svgz, x0: 32, y0: 0, x1: 96, y1: 128},
		{path: wide, x0: 0, y0: 32, x1: 128, y1: 96},
	}
	for _, tc := range tests {
		t.Run(filepath.Base(tc.path), func(t *testing.T) {
			img, err := IconImage(tc.path, testDim)
			require.NoError(t, err)
			require.Equal(t, image.Rect(0, 0, testDim, testDim), img.Bounds())
			drawn := image.Rectangle{}
			for y := range testDim {
				for x := range testDim {
					if img.RGBAAt(x, y).A >= 128 {
						drawn = drawn.Union(image.Rect(x, y, x+1, y+1))
					}
				}
			}
			assert.Equal(t, image.Rect(tc.x0, tc.y0, tc.x1, tc.y1), drawn)
			assert.InDelta(t, math.Hypot(32, 64)/64, Reach(img), 0.01)
		})
	}

	_, err = IconImage(filepath.Join(dir, "missing.png"), testDim)
	require.Error(t, err)
	notZipped := filepath.Join(dir, "plain.svgz")
	require.NoError(t, os.WriteFile(notZipped, data, 0o644))
	_, err = IconImage(notZipped, testDim)
	require.ErrorContains(t, err, "gzip")
	bad := filepath.Join(dir, "bad.png")
	require.NoError(t, os.WriteFile(bad, []byte("not a png"), 0o644))
	_, err = IconImage(bad, testDim)
	require.ErrorContains(t, err, "decode")
	noBox := filepath.Join(dir, "nobox.svg")
	require.NoError(t, os.WriteFile(noBox, []byte(`<svg xmlns="http://www.w3.org/2000/svg"></svg>`), 0o644))
	_, err = IconImage(noBox, testDim)
	require.ErrorContains(t, err, "viewBox")
}
