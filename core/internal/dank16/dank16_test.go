package dank16

import (
	"bytes"
	"encoding/json"
	"math"
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/duxlabs-dev/dux-go/material/num"
)

func TestHexToRGB(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected RGB
	}{
		{
			name:     "black with hash",
			input:    "#000000",
			expected: RGB{R: 0.0, G: 0.0, B: 0.0},
		},
		{
			name:     "red without hash",
			input:    "ff0000",
			expected: RGB{R: 1.0, G: 0.0, B: 0.0},
		},
		{
			name:     "purple",
			input:    "#625690",
			expected: RGB{R: 0.3843137254901961, G: 0.33725490196078434, B: 0.5647058823529412},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := HexToRGB(tt.input)
			if !floatEqual(result.R, tt.expected.R) || !floatEqual(result.G, tt.expected.G) || !floatEqual(result.B, tt.expected.B) {
				t.Errorf("HexToRGB(%s) = %v, expected %v", tt.input, result, tt.expected)
			}
		})
	}
}

func TestRGBToHex(t *testing.T) {
	tests := []struct {
		name     string
		input    RGB
		expected string
	}{
		{
			name:     "red",
			input:    RGB{R: 1.0, G: 0.0, B: 0.0},
			expected: "#ff0000",
		},
		{
			name:     "clamping above 1.0",
			input:    RGB{R: 1.5, G: 0.5, B: 0.5},
			expected: "#ff7f7f",
		},
		{
			name:     "clamping below 0.0",
			input:    RGB{R: -0.5, G: 0.5, B: 0.5},
			expected: "#007f7f",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := RGBToHex(tt.input)
			if result != tt.expected {
				t.Errorf("RGBToHex(%v) = %s, expected %s", tt.input, result, tt.expected)
			}
		})
	}
}

func TestRGBToHSL(t *testing.T) {
	tests := []struct {
		name     string
		input    RGB
		expected HSL
	}{
		{
			name:     "black",
			input:    RGB{R: 0.0, G: 0.0, B: 0.0},
			expected: HSL{H: 0.0, S: 0.0, L: 0.0},
		},
		{
			name:     "red",
			input:    RGB{R: 1.0, G: 0.0, B: 0.0},
			expected: HSL{H: 0.0, S: 1.0, L: 0.5},
		},
		{
			name:     "green",
			input:    RGB{R: 0.0, G: 1.0, B: 0.0},
			expected: HSL{H: 120.0 / 360.0, S: 1.0, L: 0.5},
		},
		{
			name:     "blue",
			input:    RGB{R: 0.0, G: 0.0, B: 1.0},
			expected: HSL{H: 240.0 / 360.0, S: 1.0, L: 0.5},
		},
		{
			name:     "magenta",
			input:    RGB{R: 1.0, G: 0.0, B: 1.0},
			expected: HSL{H: 300 / 360.0, S: 1.0, L: 0.5},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := RGBToHSL(tt.input)
			if !floatEqual(result.H, tt.expected.H) || !floatEqual(result.S, tt.expected.S) || !floatEqual(result.L, tt.expected.L) {
				t.Errorf("RGBToHSL(%v) = %v, expected %v", tt.input, result, tt.expected)
			}
		})
	}
}

func TestRGBToHSV(t *testing.T) {
	tests := []struct {
		name     string
		input    RGB
		expected HSV
	}{
		{
			name:     "black",
			input:    RGB{R: 0.0, G: 0.0, B: 0.0},
			expected: HSV{H: 0.0, S: 0.0, V: 0.0},
		},
		{
			name:     "red",
			input:    RGB{R: 1.0, G: 0.0, B: 0.0},
			expected: HSV{H: 0.0, S: 1.0, V: 1.0},
		},
		{
			name:     "green",
			input:    RGB{R: 0.0, G: 1.0, B: 0.0},
			expected: HSV{H: 0.3333333333333333, S: 1.0, V: 1.0},
		},
		{
			name:     "blue",
			input:    RGB{R: 0.0, G: 0.0, B: 1.0},
			expected: HSV{H: 0.6666666666666666, S: 1.0, V: 1.0},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := RGBToHSV(tt.input)
			if !floatEqual(result.H, tt.expected.H) || !floatEqual(result.S, tt.expected.S) || !floatEqual(result.V, tt.expected.V) {
				t.Errorf("RGBToHSV(%v) = %v, expected %v", tt.input, result, tt.expected)
			}
		})
	}
}

func TestHSVToRGB(t *testing.T) {
	tests := []struct {
		name     string
		input    HSV
		expected RGB
	}{
		{
			name:     "white",
			input:    HSV{H: 0.0, S: 0.0, V: 1.0},
			expected: RGB{R: 1.0, G: 1.0, B: 1.0},
		},
		{
			name:     "red",
			input:    HSV{H: 0.0, S: 1.0, V: 1.0},
			expected: RGB{R: 1.0, G: 0.0, B: 0.0},
		},
		{
			name:     "green",
			input:    HSV{H: 0.3333333333333333, S: 1.0, V: 1.0},
			expected: RGB{R: 0.0, G: 1.0, B: 0.0},
		},
		{
			name:     "blue",
			input:    HSV{H: 0.6666666666666666, S: 1.0, V: 1.0},
			expected: RGB{R: 0.0, G: 0.0, B: 1.0},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := HSVToRGB(tt.input)
			if !floatEqual(result.R, tt.expected.R) || !floatEqual(result.G, tt.expected.G) || !floatEqual(result.B, tt.expected.B) {
				t.Errorf("HSVToRGB(%v) = %v, expected %v", tt.input, result, tt.expected)
			}
		})
	}
}

func TestLuminance(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected float64
	}{
		{
			name:     "red",
			input:    "#ff0000",
			expected: 0.2126,
		},
		{
			name:     "green",
			input:    "#00ff00",
			expected: 0.7152,
		},
		{
			name:     "blue",
			input:    "#0000ff",
			expected: 0.0722,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := Luminance(tt.input)
			if !floatEqual(result, tt.expected) {
				t.Errorf("Luminance(%s) = %f, expected %f", tt.input, result, tt.expected)
			}
		})
	}
}

func TestContrastRatio(t *testing.T) {
	tests := []struct {
		name     string
		fg       string
		bg       string
		expected float64
	}{
		{
			name:     "black on white",
			fg:       "#000000",
			bg:       "#ffffff",
			expected: 21.0,
		},
		{
			name:     "white on black",
			fg:       "#ffffff",
			bg:       "#000000",
			expected: 21.0,
		},
		{
			name:     "same color",
			fg:       "#808080",
			bg:       "#808080",
			expected: 1.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ContrastRatio(tt.fg, tt.bg)
			if !floatEqual(result, tt.expected) {
				t.Errorf("ContrastRatio(%s, %s) = %f, expected %f", tt.fg, tt.bg, result, tt.expected)
			}
		})
	}
}

func TestEnsureContrast(t *testing.T) {
	tests := []struct {
		name        string
		color       string
		bg          string
		minRatio    float64
		isLightMode bool
	}{
		{
			name:        "needs adjustment dark mode",
			color:       "#404040",
			bg:          "#1a1a1a",
			minRatio:    4.5,
			isLightMode: false,
		},
		{
			name:        "needs adjustment light mode",
			color:       "#c0c0c0",
			bg:          "#f8f8f8",
			minRatio:    4.5,
			isLightMode: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := EnsureContrast(tt.color, tt.bg, tt.minRatio, tt.isLightMode)
			actualRatio := ContrastRatio(result, tt.bg)
			if actualRatio < tt.minRatio {
				t.Errorf("EnsureContrast(%s, %s, %f, %t) = %s with ratio %f, expected ratio >= %f",
					tt.color, tt.bg, tt.minRatio, tt.isLightMode, result, actualRatio, tt.minRatio)
			}
		})
	}
}

func TestGeneratePalette(t *testing.T) {
	tests := []struct {
		name          string
		base          string
		backgroundHex string
		backgroundHSL string
		opts          PaletteOptions
	}{
		{
			name:          "dark theme default",
			base:          "#625690",
			backgroundHex: "#1a1a1a",
			backgroundHSL: "hsl(0.0, 0.0%, 10.2%)",
			opts:          PaletteOptions{IsLight: false},
		},
		{
			name:          "light theme with custom background",
			base:          "#625690",
			backgroundHex: "#fafafa",
			backgroundHSL: "hsl(0.0, 0.0%, 98.0%)",
			opts: PaletteOptions{
				IsLight:    true,
				Background: "#fafafa",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GeneratePalette(tt.base, tt.opts)

			colors := []ColorInfo{
				result.Color0, result.Color1, result.Color2, result.Color3,
				result.Color4, result.Color5, result.Color6, result.Color7,
				result.Color8, result.Color9, result.Color10, result.Color11,
				result.Color12, result.Color13, result.Color14, result.Color15,
			}

			for i, color := range colors {
				if len(color.Hex) != 7 || color.Hex[0] != '#' {
					t.Errorf("Color at index %d (%s) is not a valid hex color", i, color.Hex)
				}
			}

			if result.Color0.Hex != tt.backgroundHex {
				t.Errorf("Background color hex = %s, expected %s", result.Color0.Hex, tt.backgroundHex)
			}

			if result.Color0.HSL != tt.backgroundHSL {
				t.Errorf("Background color hsl = %s, expected %s", result.Color0.HSL, tt.backgroundHSL)
			}

			// Color15 is now derived from primary, so just verify it's a valid color
			// and has appropriate luminance for the mode (now theme-tinted, not pure white/black)
			color15Lum := Luminance(result.Color15.Hex)
			if tt.opts.IsLight {
				// Light mode: Color15 should still be relatively light
				if color15Lum < 0.5 {
					t.Errorf("Light mode Color15 = %s (lum %.2f) is too dark", result.Color15.Hex, color15Lum)
				}
			} else {
				// Dark mode: Color15 should be light (but may have theme tint, so lower threshold)
				if color15Lum < 0.5 {
					t.Errorf("Dark mode Color15 = %s (lum %.2f) is too dark", result.Color15.Hex, color15Lum)
				}
			}
		})
	}
}

func TestFormatOutput(t *testing.T) {
	tests := []struct {
		in  string
		out []byte
	}{
		{
			in:  "#000000",
			out: []byte(`{"hex":"#000000","hex_stripped":"000000","hex_alpha":"#000000ff","hex_alpha_stripped":"000000ff","alpha_hex":"#ff000000","alpha_hex_stripped":"ff000000","rgb":"rgb(0, 0, 0)","rgba":"rgba(0, 0, 0, 1.0)","hsl":"hsl(0.0, 0.0%, 0.0%)","hsla":"hsla(0.0, 0.0%, 0.0%, 1.0)","red":"0","green":"0","blue":"0","alpha":"1.0","hue":"0.0","saturation":"0.0%","lightness":"0.0%"}`),
		},
		{
			in:  "#625690",
			out: []byte(`{"hex":"#625690","hex_stripped":"625690","hex_alpha":"#625690ff","hex_alpha_stripped":"625690ff","alpha_hex":"#ff625690","alpha_hex_stripped":"ff625690","rgb":"rgb(98, 86, 144)","rgba":"rgba(98, 86, 144, 1.0)","hsl":"hsl(252.4, 25.2%, 45.1%)","hsla":"hsla(252.4, 25.2%, 45.1%, 1.0)","red":"98","green":"86","blue":"144","alpha":"1.0","hue":"252.4","saturation":"25.2%","lightness":"45.1%"}`),
		},
		{
			in:  "#888888",
			out: []byte(`{"hex":"#888888","hex_stripped":"888888","hex_alpha":"#888888ff","hex_alpha_stripped":"888888ff","alpha_hex":"#ff888888","alpha_hex_stripped":"ff888888","rgb":"rgb(136, 136, 136)","rgba":"rgba(136, 136, 136, 1.0)","hsl":"hsl(0.0, 0.0%, 53.3%)","hsla":"hsla(0.0, 0.0%, 53.3%, 1.0)","red":"136","green":"136","blue":"136","alpha":"1.0","hue":"0.0","saturation":"0.0%","lightness":"53.3%"}`),
		},
	}

	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			ci := NewColorInfo(tt.in)
			out, err := json.Marshal(ci)
			if err != nil {
				t.Error("Failed encoding", err)
			}
			if !bytes.Equal(out, tt.out) {
				t.Errorf("Color output mismatch, got = %s, expected %s", out, tt.out)
			}
		})
	}
}

func TestRoundTripConversion(t *testing.T) {
	testColors := []string{"#625690", "#808080"}

	for _, hex := range testColors {
		t.Run(hex, func(t *testing.T) {
			rgb := HexToRGB(hex)
			result := RGBToHex(rgb)
			if result != hex {
				t.Errorf("Round trip %s -> RGB -> %s failed", hex, result)
			}
		})
	}
}

func TestRGBHSVRoundTrip(t *testing.T) {
	testCases := []RGB{
		{R: 0.5, G: 0.5, B: 0.5},
		{R: 0.3843137254901961, G: 0.33725490196078434, B: 0.5647058823529412},
	}

	for _, rgb := range testCases {
		t.Run("", func(t *testing.T) {
			hsv := RGBToHSV(rgb)
			result := HSVToRGB(hsv)
			if !floatEqual(result.R, rgb.R) || !floatEqual(result.G, rgb.G) || !floatEqual(result.B, rgb.B) {
				t.Errorf("Round trip RGB->HSV->RGB failed: %v -> %v -> %v", rgb, hsv, result)
			}
		})
	}
}

func floatEqual(a, b float64) bool {
	return math.Abs(a-b) < 1e-9
}

func TestDeltaPhiStar(t *testing.T) {
	tests := []struct {
		name             string
		fg               string
		bg               string
		negativePolarity bool
		minExpected      float64
	}{
		{
			name:             "white on black (negative polarity)",
			fg:               "#ffffff",
			bg:               "#000000",
			negativePolarity: true,
			minExpected:      100.0,
		},
		{
			name:             "black on white (positive polarity)",
			fg:               "#000000",
			bg:               "#ffffff",
			negativePolarity: false,
			minExpected:      100.0,
		},
		{
			name:             "low contrast same color",
			fg:               "#808080",
			bg:               "#808080",
			negativePolarity: false,
			minExpected:      -40.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DeltaPhiStar(tt.fg, tt.bg, tt.negativePolarity)
			if result < tt.minExpected {
				t.Errorf("DeltaPhiStar(%s, %s, %v) = %f, expected >= %f",
					tt.fg, tt.bg, tt.negativePolarity, result, tt.minExpected)
			}
		})
	}
}

func TestEnsureContrastDPS(t *testing.T) {
	tests := []struct {
		name        string
		color       string
		bg          string
		minLc       float64
		isLightMode bool
	}{
		{
			name:        "needs adjustment dark mode",
			color:       "#404040",
			bg:          "#1a1a1a",
			minLc:       60.0,
			isLightMode: false,
		},
		{
			name:        "needs adjustment light mode",
			color:       "#c0c0c0",
			bg:          "#f8f8f8",
			minLc:       60.0,
			isLightMode: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := EnsureContrastDPS(tt.color, tt.bg, tt.minLc, tt.isLightMode)
			actualLc := DeltaPhiStarContrast(result, tt.bg, tt.isLightMode)
			if actualLc < tt.minLc {
				t.Errorf("EnsureContrastDPS(%s, %s, %f, %t) = %s with Lc %f, expected Lc >= %f",
					tt.color, tt.bg, tt.minLc, tt.isLightMode, result, actualLc, tt.minLc)
			}
		})
	}
}

func TestGeneratePaletteWithDPS(t *testing.T) {
	tests := []struct {
		name string
		base string
		opts PaletteOptions
	}{
		{
			name: "dark theme with DPS",
			base: "#625690",
			opts: PaletteOptions{IsLight: false, UseDPS: true},
		},
		{
			name: "light theme with DPS",
			base: "#625690",
			opts: PaletteOptions{IsLight: true, UseDPS: true},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GeneratePalette(tt.base, tt.opts)

			colors := []ColorInfo{
				result.Color0, result.Color1, result.Color2, result.Color3,
				result.Color4, result.Color5, result.Color6, result.Color7,
				result.Color8, result.Color9, result.Color10, result.Color11,
				result.Color12, result.Color13, result.Color14, result.Color15,
			}

			for i, color := range colors {
				if len(color.Hex) != 7 || color.Hex[0] != '#' {
					t.Errorf("Color at index %d (%s) is not a valid hex color", i, color.Hex)
				}
			}

			bgColor := result.Color0.Hex
			for i := 1; i < 8; i++ {
				// Color5 is the container and Color6 the exact primary: they pair
				// with each other, not with the background
				if i == 5 || i == 6 {
					continue
				}
				lc := DeltaPhiStarContrast(colors[i].Hex, bgColor, tt.opts.IsLight)
				minLc := 30.0
				if lc < minLc && lc > 0 {
					t.Errorf("Color %d (%s) has insufficient DPS contrast %f with background %s (expected >= %f)",
						i, colors[i].Hex, lc, bgColor, minLc)
				}
			}
		})
	}
}

func TestDeriveContainer(t *testing.T) {
	tests := []struct {
		name     string
		primary  string
		isLight  bool
		expected string
	}{
		{
			name:     "dark mode",
			primary:  "#ccbdff",
			isLight:  false,
			expected: "#4a3e76",
		},
		{
			name:     "light mode",
			primary:  "#625690",
			isLight:  true,
			expected: "#e7deff",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DeriveContainer(tt.primary, tt.isLight)

			resultRGB := HexToRGB(result)
			expectedRGB := HexToRGB(tt.expected)

			rDiff := math.Abs(resultRGB.R - expectedRGB.R)
			gDiff := math.Abs(resultRGB.G - expectedRGB.G)
			bDiff := math.Abs(resultRGB.B - expectedRGB.B)

			tolerance := 0.02
			if rDiff > tolerance || gDiff > tolerance || bDiff > tolerance {
				t.Errorf("DeriveContainer(%s, %v) = %s, expected %s (RGB diff: R:%.4f G:%.4f B:%.4f)",
					tt.primary, tt.isLight, result, tt.expected, rDiff, gDiff, bDiff)
			}
		})
	}
}

func TestEnsureContrastDPSLightModeStaysLight(t *testing.T) {
	tests := []struct {
		name     string
		result   string
		bg       string
		minLstar float64
	}{
		{
			name:     "bidirectional adjustment",
			result:   EnsureContrastDPSBidirectional("#d0ccc6", "#f8f8f8", 17.5, true),
			bg:       "#f8f8f8",
			minLstar: 20.0,
		},
		{
			name:     "lstar adjustment",
			result:   EnsureContrastDPSLstar("#c0c0c0", "#f8f8f8", 30.0, true),
			bg:       "#f8f8f8",
			minLstar: 20.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			lstar := getLstar(tt.result)
			if lstar < tt.minLstar {
				t.Errorf("result %s has L* %.2f on light bg %s, expected >= %.2f (collapsed to near-black)",
					tt.result, lstar, tt.bg, tt.minLstar)
			}
		})
	}
}

func TestGeneratePaletteColor8Dim(t *testing.T) {
	hues := []string{"#e91e63", "#f59e0b", "#22c55e", "#06b6d4", "#8b5cf6", "#ef4444"}

	for _, base := range hues {
		t.Run(base, func(t *testing.T) {
			palette := GeneratePalette(base, PaletteOptions{IsLight: false, UseDPS: true})

			bgRatio := ContrastRatio(palette.Color8.Hex, palette.Color0.Hex)
			if bgRatio < 1.5 || bgRatio > 3.0 {
				t.Errorf("Color8 %s vs bg %s ratio %.2f, expected 1.5-3.0 (bright black stays near bg)",
					palette.Color8.Hex, palette.Color0.Hex, bgRatio)
			}

			sepRatio := ContrastRatio(palette.Color4.Hex, palette.Color8.Hex)
			if sepRatio < 2.0 {
				t.Errorf("Color4 %s vs Color8 %s ratio %.2f, expected >= 2.0 (blue must not collide with bright black)",
					palette.Color4.Hex, palette.Color8.Hex, sepRatio)
			}
		})
	}
}

func TestGeneratePaletteLightColor8StaysLight(t *testing.T) {
	palette := GeneratePalette("#f59e0b", PaletteOptions{IsLight: true, UseDPS: true})

	lstar := getLstar(palette.Color8.Hex)
	if lstar < 60.0 {
		t.Errorf("light mode Color8 %s has L* %.2f, expected >= 60 (dim grey, not near-black)",
			palette.Color8.Hex, lstar)
	}

	bgRatio := ContrastRatio(palette.Color8.Hex, palette.Color0.Hex)
	if bgRatio > 3.0 {
		t.Errorf("light mode Color8 %s vs bg %s ratio %.2f, expected <= 3.0",
			palette.Color8.Hex, palette.Color0.Hex, bgRatio)
	}
}

func TestGeneratePaletteLightYellowMeetsNormalTextContrast(t *testing.T) {
	primaries := []string{"#63568f", "#7d5800", "#116d2b", "#1c5070", "#8b3f68"}

	for _, primary := range primaries {
		t.Run(primary, func(t *testing.T) {
			palette := GeneratePalette(primary, PaletteOptions{IsLight: true, Background: "#f5fafc", UseDPS: true})

			ratio := ContrastRatio(palette.Color3.Hex, palette.Color0.Hex)
			if ratio < 4.5 {
				t.Errorf("light Color3 %s vs bg %s ratio %.2f, expected >= 4.5 (yellow must clear the normal-text target)",
					palette.Color3.Hex, palette.Color0.Hex, ratio)
			}
		})
	}
}

func TestGenerateVariantPaletteUsesPerVariantBackground(t *testing.T) {
	const darkBg = "#0f1417"
	const lightBg = "#f5fafc"

	variants := GenerateVariantPalette(VariantOptions{
		PrimaryDark:     "#8ecff2",
		PrimaryLight:    "#1c5070",
		BackgroundDark:  darkBg,
		BackgroundLight: lightBg,
		UseDPS:          true,
	})

	if variants.Color0.Dark.Hex != darkBg {
		t.Errorf("dark Color0 = %s, expected the dark background %s", variants.Color0.Dark.Hex, darkBg)
	}
	if variants.Color0.Light.Hex != lightBg {
		t.Errorf("light Color0 = %s, expected the light background %s", variants.Color0.Light.Hex, lightBg)
	}

	lightDim := variants.Color8.Light.Hex
	if lstar := getLstar(lightDim); lstar < 60.0 {
		t.Errorf("light Color8 %s has L* %.2f, expected >= 60 (derived from the dark surface it collapses to near-black)",
			lightDim, lstar)
	}
	if ratio := ContrastRatio(lightDim, lightBg); ratio > 3.0 {
		t.Errorf("light Color8 %s vs bg %s ratio %.2f, expected <= 3.0 (bright black stays dim)", lightDim, lightBg, ratio)
	}

	darkDim := variants.Color8.Dark.Hex
	if ratio := ContrastRatio(darkDim, darkBg); ratio > 3.0 {
		t.Errorf("dark Color8 %s vs bg %s ratio %.2f, expected <= 3.0", darkDim, darkBg, ratio)
	}
}

func TestGeneratePaletteColor5PairsWithColor6(t *testing.T) {
	tests := []struct {
		name      string
		primary   string
		container string
		bg        string
		isLight   bool
	}{
		{"violet dark", "#cdbdff", "#4b3e76", "#141318", false},
		{"violet light", "#63568f", "#e8deff", "#fdf7ff", true},
		{"green dark", "#9ed49d", "#1f5027", "#101510", false},
		{"green light", "#38693c", "#b9f0b8", "#f7fbf2", true},
		{"amber light", "#805610", "#ffddb3", "#fff8f4", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			palette := GeneratePalette(tt.primary, PaletteOptions{
				IsLight:    tt.isLight,
				Background: tt.bg,
				Container:  tt.container,
				UseDPS:     true,
			})

			if palette.Color5.Hex != tt.container {
				t.Errorf("Color5 = %s, expected the supplied container %s", palette.Color5.Hex, tt.container)
			}
			if palette.Color6.Hex != tt.primary {
				t.Errorf("Color6 = %s, expected the primary %s", palette.Color6.Hex, tt.primary)
			}

			pair := ContrastRatio(palette.Color5.Hex, palette.Color6.Hex)
			if pair < 4.5 {
				t.Errorf("Color5 %s vs Color6 %s ratio %.2f, expected >= 4.5 (the container/primary pair carries the prompt themes that use ANSI 5 on 6)",
					palette.Color5.Hex, palette.Color6.Hex, pair)
			}

			if palette.Color5.Hex == palette.Color13.Hex {
				t.Errorf("Color5 and Color13 are both %s, expected a distinct bright variant", palette.Color5.Hex)
			}
			if sep := ContrastRatio(palette.Color5.Hex, palette.Color13.Hex); sep < 2.0 {
				t.Errorf("Color5 %s vs Color13 %s ratio %.2f, expected >= 2.0 (normal and bright must be tellable apart)",
					palette.Color5.Hex, palette.Color13.Hex, sep)
			}
		})
	}
}

func TestGeneratePaletteFallsBackToDerivedContainer(t *testing.T) {
	const primary = "#cdbdff"

	palette := GeneratePalette(primary, PaletteOptions{Background: "#141318", UseDPS: true})

	want := DeriveContainer(primary, false)
	if palette.Color5.Hex != want {
		t.Errorf("Color5 = %s with no container supplied, expected the derived %s", palette.Color5.Hex, want)
	}
}

func paletteHexes(p Palette) [16]string {
	return [16]string{
		p.Color0.Hex, p.Color1.Hex, p.Color2.Hex, p.Color3.Hex, p.Color4.Hex, p.Color5.Hex, p.Color6.Hex, p.Color7.Hex,
		p.Color8.Hex, p.Color9.Hex, p.Color10.Hex, p.Color11.Hex, p.Color12.Hex, p.Color13.Hex, p.Color14.Hex, p.Color15.Hex,
	}
}

func hctHue(hex string) float64 {
	return color.ARGBFromHexMust(hex).ToHct().Hue
}

func TestDefaultProfileUnchanged(t *testing.T) {
	tests := []struct {
		name  string
		light bool
		want  [16]string
	}{
		{"dark", false, [16]string{"#1a1a1a", "#ff72a0", "#77ee84", "#fff672", "#70bfe2", "#19546e", "#8ad0ee", "#eaf5f9", "#444b4d", "#ff9fbe", "#a5ffaf", "#fff9a5", "#a3e3ff", "#b3e8ff", "#cef0ff", "#f8fdff"}},
		{"light", true, [16]string{"#f8f8f8", "#c23c6c", "#00811d", "#727300", "#1a7895", "#dcf4ff", "#8ad0ee", "#3f4142", "#b8bbbc", "#dc608a", "#009f29", "#8f8e00", "#3993b4", "#5c90a6", "#c9eeff", "#f9fdff"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for _, profile := range []string{"", "default", "bogus"} {
				got := paletteHexes(GeneratePalette("#8ad0ee", PaletteOptions{UseDPS: true, IsLight: tt.light, Profile: profile}))
				if got != tt.want {
					t.Errorf("profile %q drifted:\n got %v\nwant %v", profile, got, tt.want)
				}
			}
		})
	}
}

func TestProfileGoldens(t *testing.T) {
	tests := []struct {
		profile string
		light   bool
		want    string
	}{
		{ProfileLow, false, "#1a1a1a #ea77d9 #31f2a9 #d6ffa0 #70bfe2 #19546e #8ad0ee #eaf5f9 #444b4d #eca4e1 #98ffce #e4ffbf #a3e3ff #b3e8ff #cef0ff #f8fdff"},
		{ProfileMedium, false, "#1a1a1a #c684ff #00f0ce #c8ffd2 #6fbfe1 #19546e #8ad0ee #eaf5f9 #444b4d #d2abf8 #89ffe6 #daffdf #a3e3ff #b4e8ff #cff0ff #f8fdff"},
		{ProfileHigh, false, "#1a1a1a #879bff #00ecf6 #b8fff6 #6fbfe1 #19546e #8ad0ee #eaf5f9 #444b4d #a7b8ff #a1f9ff #d0fff8 #a3e3ff #b4e8ff #cff0ff #f8fdff"},
		{ProfileLow, true, "#f8f8f8 #b240a4 #007f51 #507a2b #1a7895 #dcf4ff #8ad0ee #3f4142 #b8bbbc #c964bb #009d65 #669737 #3993b4 #5c90a6 #c9eeff #f9fdff"},
		{ProfileMedium, true, "#f8f8f8 #944bcf #007d68 #1d7f4c #1a7895 #dcf4ff #8ad0ee #3f4142 #b8bbbc #ab6fe0 #009b82 #2a9c5f #3993b4 #5c90a6 #c9eeff #f9fdff"},
		{ProfileHigh, true, "#f8f8f8 #4562e9 #007b7f #007d76 #1b7895 #dcf4ff #8ad0ee #3f4142 #b8bbbc #6882f3 #00989d #009a91 #3993b4 #5c90a6 #caeeff #f9fdff"},
	}
	for _, tt := range tests {
		got := paletteHexes(GeneratePalette("#8ad0ee", PaletteOptions{UseDPS: true, IsLight: tt.light, Profile: tt.profile}))
		if s := strings.Join(got[:], " "); s != tt.want {
			t.Errorf("%s light=%v:\n got %s\nwant %s", tt.profile, tt.light, s, tt.want)
		}
	}
}

func TestProfileMalformedPrimaryDoesNotPanic(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("panicked: %v", r)
		}
	}()
	GeneratePalette("not-a-color", PaletteOptions{UseDPS: true, Profile: ProfileHigh})
	GeneratePalette("#12345", PaletteOptions{UseDPS: true, Profile: ProfileHigh})
	GeneratePalette("#8ad0ee", PaletteOptions{UseDPS: true, Container: "steelblue", Profile: ProfileLow})
	GeneratePalette("#8ad0ee", PaletteOptions{UseDPS: true, Container: "#12345", Profile: ProfileLow})
}

var profiles = []string{ProfileLow, ProfileMedium, ProfileHigh}

func TestProfileInvariants(t *testing.T) {
	for _, primary := range []string{"#e91e63", "#f59e0b", "#22c55e", "#06b6d4", "#8b5cf6", "#8ad0ee"} {
		for _, light := range []bool{false, true} {
			def := PaletteOptions{UseDPS: true, IsLight: light}
			dh := paletteHexes(GeneratePalette(primary, def))
			for _, profile := range profiles {
				opts := def
				opts.Profile = profile
				hh := paletteHexes(GeneratePalette(primary, opts))
				for _, i := range []int{0, 5, 6, 7, 8, 15} {
					if dh[i] != hh[i] {
						t.Errorf("%s %s light=%v slot %d: %s != default %s", primary, profile, light, i, hh[i], dh[i])
					}
				}
				for i := 1; i <= 4; i++ {
					if lc := DeltaPhiStarContrast(hh[i], hh[0], light); lc < 30 {
						t.Errorf("%s %s light=%v slot %d Lc %.1f < 30", primary, profile, light, i, lc)
					}
				}
			}
		}
	}
}

func TestProfileHueApproachesPrimaryWithStrength(t *testing.T) {
	const primary = "#1e66f5"
	ph := hctHue(primary)
	for _, light := range []bool{false, true} {
		prev := math.Inf(1)
		for _, profile := range append([]string{""}, profiles...) {
			red := GeneratePalette(primary, PaletteOptions{UseDPS: true, IsLight: light, Profile: profile}).Color1.Hex
			d := num.DifferenceDegrees(hctHue(red), ph)
			if d >= prev {
				t.Errorf("light=%v %q: red hue distance %.1f not below previous %.1f", light, profile, d, prev)
			}
			prev = d
		}
	}
}

func TestHighRotatesByCappedAmount(t *testing.T) {
	def := hctHue(GeneratePalette("#8ad0ee", PaletteOptions{UseDPS: true}).Color1.Hex)
	got := hctHue(GeneratePalette("#8ad0ee", PaletteOptions{UseDPS: true, Profile: ProfileHigh}).Color1.Hex)
	if d := num.DifferenceDegrees(def, got); math.Abs(d-85) > 3 {
		t.Errorf("slot 1 rotated %.1f degrees, want 85 (the 100 degree cap at high strength)", d)
	}
}

func TestProfileGreyPrimaryKeepsDefault(t *testing.T) {
	def := paletteHexes(GeneratePalette("#808080", PaletteOptions{UseDPS: true}))
	high := paletteHexes(GeneratePalette("#808080", PaletteOptions{UseDPS: true, Profile: ProfileHigh}))
	if def != high {
		t.Errorf("grey primary changed by high profile:\n got %v\nwant %v", high, def)
	}
}

func TestGenerateVariantPaletteProfile(t *testing.T) {
	opts := VariantOptions{PrimaryDark: "#8ad0ee", PrimaryLight: "#1c5070", UseDPS: true}
	def := GenerateVariantPalette(opts)
	opts.Profile = ProfileHigh
	high := GenerateVariantPalette(opts)
	if def.Color1.Dark.Hex == high.Color1.Dark.Hex {
		t.Error("dark color1 unchanged by high profile")
	}
	if def.Color1.Light.Hex == high.Color1.Light.Hex {
		t.Error("light color1 unchanged by high profile")
	}
}
