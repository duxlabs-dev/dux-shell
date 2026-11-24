// Package colorseed samples image files and picks the color that best stands for them.
// matugen seeds wallpapers with it and iconfolders seeds per-app icon tiles.
package colorseed

import (
	"cmp"
	"compress/gzip"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"math"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/duxlabs-dev/dux-go/material/dislike"
	"github.com/duxlabs-dev/dux-go/material/num"
	"github.com/srwiley/oksvg"
	"github.com/srwiley/rasterx"
	_ "golang.org/x/image/bmp"
	xdraw "golang.org/x/image/draw"
	_ "golang.org/x/image/tiff"
	_ "golang.org/x/image/webp"
)

// Opaque keeps only fully opaque pixels; HalfOpaque also keeps antialiased and translucent ones.
const (
	Opaque     uint32 = 0xffff
	HalfOpaque uint32 = 0x8000
)

// Scoring weights, ported from caelestia-cli's Score class.
const (
	scoreTargetChroma      = 48.0
	scoreWeightProportion  = 0.7
	scoreWeightChromaAbove = 0.3
	scoreWeightChromaBelow = 0.1
)

// DecodePixels decodes a raster image and returns its pixels, downscaled to at most maxDim on the long edge.
func DecodePixels(r io.Reader, name string, maxDim int, minAlpha uint32) ([]color.ARGB, error) {
	img, _, err := image.Decode(r)
	if err != nil {
		return nil, fmt.Errorf("decode %s: %w", name, err)
	}
	return Pixels(img, maxDim, minAlpha), nil
}

// Pixels downscales img so the quantizer works on a bounded number of pixels, dropping those below minAlpha.
func Pixels(img image.Image, maxDim int, minAlpha uint32) []color.ARGB {
	bounds := img.Bounds()
	if w, h := bounds.Dx(), bounds.Dy(); w > maxDim || h > maxDim {
		scale := float64(maxDim) / math.Max(float64(w), float64(h))
		scaled := image.NewRGBA(image.Rect(0, 0, max(int(float64(w)*scale), 1), max(int(float64(h)*scale), 1)))
		xdraw.ApproxBiLinear.Scale(scaled, scaled.Bounds(), img, bounds, xdraw.Src, nil)
		img, bounds = scaled, scaled.Bounds()
	}

	pixels := make([]color.ARGB, 0, bounds.Dx()*bounds.Dy())
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r, g, b, a := img.At(x, y).RGBA()
			if a < minAlpha || a == 0 {
				continue
			}
			if a < 0xffff {
				// RGBA is premultiplied.
				r, g, b = r*0xffff/a, g*0xffff/a, b*0xffff/a
			}
			pixels = append(pixels, color.NewARGB(255, uint8(r>>8), uint8(g>>8), uint8(b>>8)))
		}
	}
	return pixels
}

// RasterizeSVG draws the SVG with its long edge at maxDim pixels.
func RasterizeSVG(path string, maxDim int) (image.Image, error) {
	icon, err := oksvg.ReadIcon(path, oksvg.IgnoreErrorMode)
	if err != nil {
		return nil, err
	}
	vw, vh := icon.ViewBox.W, icon.ViewBox.H
	if vw <= 0 || vh <= 0 {
		return nil, fmt.Errorf("no usable viewBox")
	}
	scale := float64(maxDim) / math.Max(vw, vh)
	w, h := max(int(vw*scale), 1), max(int(vh*scale), 1)
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	drawSVG(icon, img, 0, 0, scale)
	return img, nil
}

// drawSVG maps the viewBox origin to (x, y). oksvg's SetTarget scales before it translates,
// which shifts a viewBox that does not start at 0,0.
func drawSVG(icon *oksvg.SvgIcon, img *image.RGBA, x, y, scale float64) {
	icon.Transform = rasterx.Identity.Translate(x, y).Scale(scale, scale).Translate(-icon.ViewBox.X, -icon.ViewBox.Y)
	w, h := img.Bounds().Dx(), img.Bounds().Dy()
	icon.Draw(rasterx.NewDasher(w, h, rasterx.NewScannerGV(w, h, img, img.Bounds())), 1)
}

// IconImage draws an icon centered in an n×n square, aspect kept (SVG's xMidYMid meet),
// as an icon theme renders it.
func IconImage(path string, n int) (*image.RGBA, error) {
	img := image.NewRGBA(image.Rect(0, 0, n, n))
	if ext := strings.ToLower(filepath.Ext(path)); ext == ".svg" || ext == ".svgz" {
		icon, err := readIcon(path, ext == ".svgz")
		if err != nil {
			return nil, fmt.Errorf("rasterize %s: %w", path, err)
		}
		vw, vh := icon.ViewBox.W, icon.ViewBox.H
		if vw <= 0 || vh <= 0 {
			return nil, fmt.Errorf("rasterize %s: no usable viewBox", path)
		}
		scale := float64(n) / math.Max(vw, vh)
		drawSVG(icon, img, (float64(n)-vw*scale)/2, (float64(n)-vh*scale)/2, scale)
		return img, nil
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	src, _, err := image.Decode(f)
	if err != nil {
		return nil, fmt.Errorf("decode %s: %w", path, err)
	}
	b := src.Bounds()
	if b.Empty() {
		return img, nil
	}
	scale := float64(n) / float64(max(b.Dx(), b.Dy()))
	w, h := max(int(math.Round(float64(b.Dx())*scale)), 1), max(int(math.Round(float64(b.Dy())*scale)), 1)
	x, y := (n-w)/2, (n-h)/2
	xdraw.BiLinear.Scale(img, image.Rect(x, y, x+w, y+h), src, b, xdraw.Src, nil)
	return img, nil
}

// readIcon parses an SVG, gunzipping an .svgz first.
func readIcon(path string, zipped bool) (*oksvg.SvgIcon, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var r io.Reader = f
	if zipped {
		zr, err := gzip.NewReader(f)
		if err != nil {
			return nil, fmt.Errorf("gzip: %w", err)
		}
		defer zr.Close()
		r = zr
	}
	return oksvg.ReadIconStream(r, oksvg.IgnoreErrorMode)
}

// sortedKeys orders the population so ties resolve the same way every run; map order is randomized.
func sortedKeys(population map[color.ARGB]int) []color.ARGB {
	keys := make([]color.ARGB, 0, len(population))
	for argb := range population {
		keys = append(keys, argb)
	}
	slices.Sort(keys)
	return keys
}

// Score ports caelestia-cli's Score.score. Unlike stock Material scoring it does no
// filtering, and its descending cutoff loop pushes the pick toward a colorful, well-lit
// color instead of the muted one that covers the most pixels.
func Score(population map[color.ARGB]int) (color.Hct, bool) {
	keys := sortedKeys(population)

	huePopulation := make([]int, 360)
	total := 0
	colors := make([]color.Hct, 0, len(keys))
	for _, argb := range keys {
		hct := argb.ToHct()
		colors = append(colors, hct)
		huePopulation[num.NormalizeDegreeInt(int(hct.Hue))] += population[argb]
		total += population[argb]
	}
	if total == 0 {
		return color.Hct{}, false
	}

	// Hues with more usage in a neighboring 30 degree slice score higher.
	excited := make([]float64, 360)
	for hue := range 360 {
		proportion := float64(huePopulation[hue]) / float64(total)
		for i := hue - 14; i < hue+16; i++ {
			excited[num.NormalizeDegreeInt(i)] += proportion
		}
	}

	type scoredColor struct {
		hct   color.Hct
		score float64
	}
	scored := make([]scoredColor, 0, len(colors))
	for _, hct := range colors {
		proportion := excited[num.NormalizeDegreeInt(int(math.Round(hct.Hue)))]
		chromaWeight := scoreWeightChromaAbove
		if hct.Chroma < scoreTargetChroma {
			chromaWeight = scoreWeightChromaBelow
		}
		scored = append(scored, scoredColor{
			hct:   hct,
			score: proportion*100.0*scoreWeightProportion + (hct.Chroma-scoreTargetChroma)*chromaWeight,
		})
	}
	slices.SortStableFunc(scored, func(a, b scoredColor) int { return cmp.Compare(b.score, a.score) })

	for cutoff := 20.0; cutoff >= 0; cutoff-- {
		for _, s := range scored {
			if s.hct.Chroma > cutoff && s.hct.Tone > cutoff*3 {
				return dislike.FixIfDisliked(s.hct), true
			}
		}
	}
	return color.Hct{}, false
}

// Common returns the most populous cluster with at least minChroma, the color that covers the most of the image.
func Common(population map[color.ARGB]int, minChroma float64) (color.Hct, bool) {
	var best color.Hct
	bestCount := 0
	for _, argb := range sortedKeys(population) {
		count := population[argb]
		if count <= bestCount {
			continue
		}
		if hct := argb.ToHct(); hct.Chroma >= minChroma {
			best, bestCount = hct, count
		}
	}
	return best, bestCount > 0
}
