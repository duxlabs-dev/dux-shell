package matugen

import (
	"fmt"
	"os"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/duxlabs-dev/dux-go/material/quantizer"
	"github.com/duxlabs-dev/dux-shell/core/internal/colorseed"
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
	// The caelestia-cli Score port, which the icon tiles share.
	seed, ok := colorseed.Score(population)
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
	return colorseed.DecodePixels(f, path, sourceSampleMaxDim, colorseed.Opaque)
}
