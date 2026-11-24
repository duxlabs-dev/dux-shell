package colorseed

import (
	"image"
	imgcolor "image/color"
	"testing"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestPixelsAlpha(t *testing.T) {
	img := image.NewNRGBA(image.Rect(0, 0, 3, 1))
	img.SetNRGBA(0, 0, imgcolor.NRGBA{R: 200, G: 40, B: 40, A: 255})
	img.SetNRGBA(1, 0, imgcolor.NRGBA{R: 200, G: 40, B: 40, A: 160})
	img.SetNRGBA(2, 0, imgcolor.NRGBA{R: 200, G: 40, B: 40, A: 40})

	assert.Len(t, Pixels(img, 64, Opaque), 1, "the wallpaper sampler keeps only opaque pixels")
	half := Pixels(img, 64, HalfOpaque)
	require.Len(t, half, 2)
	for _, p := range half {
		assert.InDelta(t, 200, int(p.Red()), 2, "translucent pixels are unpremultiplied")
		assert.InDelta(t, 40, int(p.Green()), 2)
	}
}

func TestPixelsDownscale(t *testing.T) {
	img := image.NewNRGBA(image.Rect(0, 0, 400, 200))
	for y := range 200 {
		for x := range 400 {
			img.SetNRGBA(x, y, imgcolor.NRGBA{R: 10, G: 120, B: 200, A: 255})
		}
	}
	assert.Len(t, Pixels(img, 100, Opaque), 100*50)
}

func TestScoreAndCommon(t *testing.T) {
	red := color.NewARGB(255, 0xe5, 0x39, 0x35)
	gray := color.NewARGB(255, 0x80, 0x80, 0x80)
	teal := color.NewARGB(255, 0x00, 0x89, 0x7b)
	navy := color.NewARGB(255, 0x0d, 0x1b, 0x4f)
	pink := color.NewARGB(255, 0xf4, 0x8f, 0xb1)
	tests := []struct {
		name       string
		population map[color.ARGB]int
		common     color.ARGB
		commonOK   bool
		score      color.ARGB
		scoreOK    bool
	}{
		{name: "empty", population: map[color.ARGB]int{}},
		{name: "gray dominates, red is the color", population: map[color.ARGB]int{gray: 900, red: 100}, common: red, commonOK: true, score: red, scoreOK: true},
		{name: "the biggest chromatic cluster wins Common, the most colorful Score", population: map[color.ARGB]int{red: 100, teal: 300, gray: 900}, common: teal, commonOK: true, score: red, scoreOK: true},
		{name: "a tie resolves the same way every run", population: map[color.ARGB]int{red: 300, teal: 300}, common: teal, commonOK: true, score: red, scoreOK: true},
		{name: "only gray", population: map[color.ARGB]int{gray: 900}, score: gray, scoreOK: true},
		// Navy scores highest, but at tone 12 it fails the bar until the cutoff walks down past where pink clears it.
		{name: "the cutoff bar prefers a well-lit color", population: map[color.ARGB]int{navy: 900, pink: 50}, common: navy, commonOK: true, score: pink, scoreOK: true},
		{name: "the bar walks down until a dark color clears it", population: map[color.ARGB]int{navy: 900}, common: navy, commonOK: true, score: navy, scoreOK: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			for range 20 {
				common, ok := Common(tc.population, 8)
				assert.Equal(t, tc.commonOK, ok)
				if ok {
					assert.Equal(t, tc.common.ToHct(), common)
				}
				score, ok := Score(tc.population)
				require.Equal(t, tc.scoreOK, ok)
				if ok {
					// No color here is disliked, so FixIfDisliked leaves the pick as it is.
					assert.Equal(t, tc.score.ToHct(), score)
				}
			}
		})
	}
}
