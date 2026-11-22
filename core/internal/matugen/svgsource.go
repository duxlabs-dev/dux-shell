package matugen

import (
	"fmt"
	"image/png"
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/colorseed"
)

// stageImageSource returns the absolute path templates see as {{image}} and,
// for an SVG, swaps opts.Value for a one-shot PNG raster matugen can decode.
// !TODO: drop the SVG raster once matugen decodes SVG; matugen 4.2.0 (material-colors 0.4.2) panics on an .svg source
func stageImageSource(opts *Options) (sourceImage string, cleanup func(), err error) {
	noop := func() {}
	if opts.Kind != "image" {
		return "", noop, nil
	}
	sourceImage = opts.Value
	if abs, err := filepath.Abs(sourceImage); err == nil {
		sourceImage = abs
	}
	if !strings.EqualFold(filepath.Ext(opts.Value), ".svg") {
		return sourceImage, noop, nil
	}
	raster, err := rasterizeSVGToPNG(opts.Value)
	if err != nil {
		return "", noop, fmt.Errorf("svg source %s: %w", opts.Value, err)
	}
	opts.Value = raster
	return sourceImage, func() { os.Remove(raster) }, nil
}

func rasterizeSVGToPNG(path string) (string, error) {
	img, err := colorseed.RasterizeSVG(path, sourceSampleMaxDim)
	if err != nil {
		return "", err
	}
	f, err := os.CreateTemp("", "matugen-svg-*.png")
	if err != nil {
		return "", err
	}
	defer f.Close()
	if err := png.Encode(f, img); err != nil {
		os.Remove(f.Name())
		return "", err
	}
	return f.Name(), nil
}
