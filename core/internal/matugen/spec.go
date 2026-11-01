package matugen

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/duxlabs-dev/dux-go/material/dynamic"
	"github.com/duxlabs-dev/dux-go/material/palettes"
)

// Palette spec versions. Spec2021 is matugen's own output and the historical
// default. Spec2025 is material-color-utilities' 2025 color spec, which matugen
// 4.x cannot produce: the palette is generated in-process and handed to matugen
// through --import-json-string, the same override path stock themes use.
// SpecDMS is the 2025 palettes with raised accent chroma on Tonal Spot's
// neutral surfaces. Vibrant only loses its tinted surfaces.
const (
	Spec2021 = "2021"
	Spec2025 = "2025"
	SpecDMS  = "dms"
)

var hexColorPattern = regexp.MustCompile(`^#?[0-9a-fA-F]{6}$`)

// NormalizeHexColor returns "#rrggbb" or an error. matugen and the shell both
// compare generated colors as strings, so casing must not vary between runs.
func NormalizeHexColor(value string) (string, error) {
	value = strings.TrimSpace(value)
	if !hexColorPattern.MatchString(value) {
		return "", fmt.Errorf("invalid hex color %q", value)
	}
	return "#" + strings.ToLower(strings.TrimPrefix(value, "#")), nil
}

var schemeVariants = map[string]dynamic.Variant{
	"scheme-tonal-spot":  dynamic.VariantTonalSpot,
	"scheme-vibrant":     dynamic.VariantVibrant,
	"scheme-content":     dynamic.VariantContent,
	"scheme-expressive":  dynamic.VariantExpressive,
	"scheme-fidelity":    dynamic.VariantFidelity,
	"scheme-fruit-salad": dynamic.VariantFruitSalad,
	"scheme-monochrome":  dynamic.VariantMonochrome,
	"scheme-neutral":     dynamic.VariantNeutral,
	"scheme-rainbow":     dynamic.VariantRainbow,
}

// SpecSupportsScheme reports whether the 2025 spec changes the scheme.
// material-color-utilities only defines it for these variants and falls back to
// 2021 for the rest, which matugen already produces. scheme-smart is chosen by
// matugen at run time and is not exposed in its output.
func SpecSupportsScheme(schemeType string) bool {
	switch schemeVariants[schemeType] {
	case dynamic.VariantTonalSpot, dynamic.VariantVibrant, dynamic.VariantExpressive, dynamic.VariantNeutral:
		return true
	default:
		return false
	}
}

// UsesSpecGenerator reports whether the palette comes from the in-process
// generator instead of matugen's own output.
func UsesSpecGenerator(spec, schemeType string) bool {
	return (spec == Spec2025 || spec == SpecDMS) && SpecSupportsScheme(schemeType)
}

// dmsPalettes are the accent chromas per scheme under SpecDMS, with the
// variant whose tone rules run. Vibrant's rules chase the most saturated tone
// and only suit Vibrant and Tonal Spot; Expressive and Neutral keep their own
// fixed tones so low-chroma palettes stay mid-tone instead of washing out.
var dmsPalettes = map[dynamic.Variant]struct {
	rules                        dynamic.Variant
	primary, secondary, tertiary float64
}{
	dynamic.VariantTonalSpot:  {dynamic.VariantVibrant, 40, 28, 36},
	dynamic.VariantExpressive: {dynamic.VariantTonalSpot, 48, 40, 48},
	dynamic.VariantNeutral:    {dynamic.VariantNeutral, 20, 12, 28},
}

func newDMSScheme(seed color.Hct, variant dynamic.Variant, contrast float64, dark bool) *dynamic.Scheme {
	neutral := dynamic.NewDynamicScheme(seed, dynamic.VariantTonalSpot, contrast, dark, dynamic.PlatformPhone, dynamic.Version2025)
	recipe, ok := dmsPalettes[variant]
	if !ok {
		return dynamic.NewDynamicScheme(seed, variant, contrast, dark, dynamic.PlatformPhone, dynamic.Version2025,
			nil, nil, nil, &neutral.NeutralPalette, &neutral.NeutralVariantPalette)
	}
	own := dynamic.NewDynamicScheme(seed, variant, contrast, dark, dynamic.PlatformPhone, dynamic.Version2025)
	secondaryHue, tertiaryHue := own.SecondaryPalette.Hue, own.TertiaryPalette.Hue
	if variant == dynamic.VariantExpressive {
		// 2025 Expressive dropped the rotated secondary and tertiary; they are its identity.
		old := dynamic.NewDynamicScheme(seed, variant, contrast, dark, dynamic.PlatformPhone, dynamic.Version2021)
		secondaryHue, tertiaryHue = old.SecondaryPalette.Hue, old.TertiaryPalette.Hue
	}
	return dynamic.NewDynamicScheme(seed, recipe.rules, contrast, dark, dynamic.PlatformPhone, dynamic.Version2025,
		palettes.FromHueAndChroma(own.PrimaryPalette.Hue, recipe.primary),
		palettes.FromHueAndChroma(secondaryHue, recipe.secondary),
		palettes.FromHueAndChroma(tertiaryHue, recipe.tertiary),
		&neutral.NeutralPalette, &neutral.NeutralVariantPalette)
}

func newScheme(seed color.Hct, variant dynamic.Variant, contrast float64, dark bool, version string) *dynamic.Scheme {
	switch version {
	case SpecDMS:
		return newDMSScheme(seed, variant, contrast, dark)
	case Spec2025:
		return dynamic.NewDynamicScheme(seed, variant, contrast, dark, dynamic.PlatformPhone, dynamic.Version2025)
	default:
		return dynamic.NewDynamicScheme(seed, variant, contrast, dark, dynamic.PlatformPhone, dynamic.Version2021)
	}
}

// GenerateSpecColors builds the full Material color map for a seed under the
// given spec version and returns it in matugen's {"role": {"dark","light",
// "default": {"color"}}} shape. defaultMode picks which side "default" mirrors.
func GenerateSpecColors(seedHex, schemeType string, contrast float64, defaultMode ColorMode, version string) (string, error) {
	variant, ok := schemeVariants[schemeType]
	if !ok {
		return "", fmt.Errorf("scheme %q is not supported by the in-process generator", schemeType)
	}
	seed, err := NormalizeHexColor(seedHex)
	if err != nil {
		return "", err
	}
	if version != Spec2021 {
		// The 2025 spec has no reduced-contrast schemes.
		contrast = max(contrast, 0)
	}

	seedArgb, err := color.ARGBFromHex(seed)
	if err != nil {
		return "", err
	}
	generate := func(dark bool) map[string]string {
		scheme := newScheme(seedArgb.ToHct(), variant, contrast, dark, version)
		roles := scheme.ToColorMap()
		out := make(map[string]string, len(roles)+1)
		for name, role := range roles {
			if role == nil {
				continue
			}
			out[name] = strings.ToLower(role.GetArgb(scheme).HexRGB())
		}
		out["source_color"] = seed
		return out
	}

	dark := generate(true)
	light := generate(false)

	type shade struct {
		Color string `json:"color"`
	}
	type role struct {
		Dark    shade `json:"dark"`
		Light   shade `json:"light"`
		Default shade `json:"default"`
	}
	roles := make(map[string]role, len(dark))
	for name, darkHex := range dark {
		lightHex, ok := light[name]
		if !ok {
			continue
		}
		def := darkHex
		if defaultMode == ColorModeLight {
			def = lightHex
		}
		roles[name] = role{Dark: shade{darkHex}, Light: shade{lightHex}, Default: shade{def}}
	}

	data, err := json.Marshal(roles)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
