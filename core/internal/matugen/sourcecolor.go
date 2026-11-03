package matugen

import (
	"cmp"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"math"
	"os"
	"slices"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/duxlabs-dev/dux-go/material/dislike"
	"github.com/duxlabs-dev/dux-go/material/num"
	"github.com/duxlabs-dev/dux-go/material/quantizer"
	_ "golang.org/x/image/bmp"
	xdraw "golang.org/x/image/draw"
	_ "golang.org/x/image/tiff"
	_ "golang.org/x/image/webp"
)

// Source color modes. Anything else, including the empty string, means
// "dominant": let matugen pick, which is what DMS has always done.
const (
	SourceModeDominant = "dominant"
	SourceModeColorful = "colorful"
)

// matugenPreferValues are the --prefer values DMS forwards to matugen. Kept as
// an allowlist so a stale or hand-edited setting can't inject arbitrary args.
// matugen's closest-to-fallback is left out: DMS never sets --fallback-color,
// so there is nothing meaningful for it to be close to.
var matugenPreferValues = map[string]bool{
	"darkness":        true,
	"lightness":       true,
	"saturation":      true,
	"less-saturation": true,
	"value":           true,
}

// sourceSelectionArgs are the matugen v4 flags that decide which extracted
// color seeds the palette. Every build passes through here, including hex
// sources and stock color themes: --prefer on a hex source is a no-op that
// produces byte-identical output to --source-color-index 0, so there is
// nothing to gate on. SourceModeColorful is resolved to a hex before matugen
// runs and so lands on the --source-color-index 0 fallback like any other
// non-prefer mode.
//
// supportsPrefer is false on matugen 4.0.x, which has --source-color-index but
// not --prefer. matugen aborts on an unknown argument, so a --prefer mode there
// has to degrade to the dominant color rather than fail the theme build.
func sourceSelectionArgs(sourceMode string, supportsPrefer bool) []string {
	if supportsPrefer && matugenPreferValues[sourceMode] {
		return []string{"--prefer", sourceMode}
	}
	return []string{"--source-color-index", "0"}
}

const (
	// Longest edge the quantizer sees. Full-resolution wallpapers cost about a
	// second and the extra pixels move the result by less than the sampling
	// noise already present.
	sourceSampleMaxDim = 512
	// Palette size, matching Caelestia's ImageQuantizeCelebi(image, 1, 128).
	sourceMaxColors = 128

	// Scoring weights, ported from caelestia-cli's Score class.
	scoreTargetChroma      = 48.0
	scoreWeightProportion  = 0.7
	scoreWeightChromaAbove = 0.3
	scoreWeightChromaBelow = 0.1
)

// ExtractSourceColor picks a wallpaper's seed color the way caelestia-cli does:
// quantize the image, then prefer the most colorful prominent color rather than
// the most common one. matugen's own extraction tends to land on a large, dull
// region (a sky, a wall), which is why a warm image can still produce a cold
// palette. Returns a "#RRGGBB" hex to hand back to matugen as a color source.
//
// Formats are whatever image.Decode handles: jpeg, png, gif, bmp, tiff and
// webp. DMS also accepts jxl, avif, heif and exr wallpapers, which fail here
// with a decode error; callers are expected to fall back to matugen's own
// extraction rather than fail the theme build.
//
// The same file always yields the same string. DMS compares generated colors
// byte-for-byte to detect "no changes", so a seed that varied between runs
// would retheme the desktop on every wallpaper event.
func ExtractSourceColor(imagePath string) (string, error) {
	pixels, err := samplePixels(imagePath)
	if err != nil {
		return "", err
	}
	if len(pixels) == 0 {
		return "", fmt.Errorf("no opaque pixels in %s", imagePath)
	}

	population := quantizer.QuantizeCelebi(pixels, sourceMaxColors)
	seed, ok := scoreColors(population)
	if !ok {
		return "", fmt.Errorf("no usable color in %s", imagePath)
	}
	return seed.ToARGB().HexRGB(), nil
}

// samplePixels decodes the image and downscales it so the quantizer works on a
// bounded number of pixels regardless of wallpaper resolution.
func samplePixels(path string) ([]color.ARGB, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open wallpaper: %w", err)
	}
	defer f.Close()

	img, _, err := image.Decode(f)
	if err != nil {
		return nil, fmt.Errorf("decode %s: %w", path, err)
	}

	bounds := img.Bounds()
	if w, h := bounds.Dx(), bounds.Dy(); w > sourceSampleMaxDim || h > sourceSampleMaxDim {
		scale := float64(sourceSampleMaxDim) / math.Max(float64(w), float64(h))
		scaled := image.NewRGBA(image.Rect(0, 0, max(int(float64(w)*scale), 1), max(int(float64(h)*scale), 1)))
		xdraw.ApproxBiLinear.Scale(scaled, scaled.Bounds(), img, bounds, xdraw.Src, nil)
		img, bounds = scaled, scaled.Bounds()
	}

	pixels := make([]color.ARGB, 0, bounds.Dx()*bounds.Dy())
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r, g, b, a := img.At(x, y).RGBA()
			if a < 0xffff {
				continue
			}
			pixels = append(pixels, color.NewARGB(255, uint8(r>>8), uint8(g>>8), uint8(b>>8)))
		}
	}
	return pixels, nil
}

// scoreColors ports caelestia-cli's Score.score. It differs from stock Material
// scoring in two ways that matter: no filtering, and the descending cutoff loop
// at the end, which walks the chroma/tone bar down until something clears it.
// That bar is what pushes the pick toward a colorful, well-lit color instead of
// whichever muted color covers the most pixels.
func scoreColors(population map[color.ARGB]int) (color.Hct, bool) {
	// Sorted so the stable sort below and the cutoff scan resolve ties the same
	// way every run; Go map iteration order is randomized.
	keys := make([]color.ARGB, 0, len(population))
	for argb := range population {
		keys = append(keys, argb)
	}
	slices.Sort(keys)

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
