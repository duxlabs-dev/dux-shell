package dank16

import (
	"fmt"
	"math"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/duxlabs-dev/dux-go/material/num"
	"github.com/lucasb-eyer/go-colorful"
)

type RGB struct {
	R, G, B float64
}

type HSL struct {
	H, S, L float64
}

type HSV struct {
	H, S, V float64
}

type ColorInfo struct {
	Hex              string `json:"hex"`
	HexStripped      string `json:"hex_stripped"`
	HexAlpha         string `json:"hex_alpha"`
	HexAlphaStripped string `json:"hex_alpha_stripped"`
	AlphaHex         string `json:"alpha_hex"`
	AlphaHexStripped string `json:"alpha_hex_stripped"`
	RGB              string `json:"rgb"`
	RGBA             string `json:"rgba"`
	HSL              string `json:"hsl"`
	HSLA             string `json:"hsla"`
	R                string `json:"red"`
	G                string `json:"green"`
	B                string `json:"blue"`
	A                string `json:"alpha"`
	H                string `json:"hue"`
	S                string `json:"saturation"`
	L                string `json:"lightness"`
}

type VariantColorInfo struct {
	Dark    ColorInfo `json:"dark"`
	Light   ColorInfo `json:"light"`
	Default ColorInfo `json:"default"`
}

type Palette struct {
	Color0  ColorInfo `json:"color0"`
	Color1  ColorInfo `json:"color1"`
	Color2  ColorInfo `json:"color2"`
	Color3  ColorInfo `json:"color3"`
	Color4  ColorInfo `json:"color4"`
	Color5  ColorInfo `json:"color5"`
	Color6  ColorInfo `json:"color6"`
	Color7  ColorInfo `json:"color7"`
	Color8  ColorInfo `json:"color8"`
	Color9  ColorInfo `json:"color9"`
	Color10 ColorInfo `json:"color10"`
	Color11 ColorInfo `json:"color11"`
	Color12 ColorInfo `json:"color12"`
	Color13 ColorInfo `json:"color13"`
	Color14 ColorInfo `json:"color14"`
	Color15 ColorInfo `json:"color15"`
}

type VariantPalette struct {
	Color0  VariantColorInfo `json:"color0"`
	Color1  VariantColorInfo `json:"color1"`
	Color2  VariantColorInfo `json:"color2"`
	Color3  VariantColorInfo `json:"color3"`
	Color4  VariantColorInfo `json:"color4"`
	Color5  VariantColorInfo `json:"color5"`
	Color6  VariantColorInfo `json:"color6"`
	Color7  VariantColorInfo `json:"color7"`
	Color8  VariantColorInfo `json:"color8"`
	Color9  VariantColorInfo `json:"color9"`
	Color10 VariantColorInfo `json:"color10"`
	Color11 VariantColorInfo `json:"color11"`
	Color12 VariantColorInfo `json:"color12"`
	Color13 VariantColorInfo `json:"color13"`
	Color14 VariantColorInfo `json:"color14"`
	Color15 VariantColorInfo `json:"color15"`
}

func NewColorInfo(hex string) ColorInfo {
	rgb := HexToRGB(hex)
	hsl := RGBToHSL(rgb)

	var r, g, b, a, h, s, l string

	r = strconv.FormatInt(int64(math.Round(rgb.R*255)), 10)
	g = strconv.FormatInt(int64(math.Round(rgb.G*255)), 10)
	b = strconv.FormatInt(int64(math.Round(rgb.B*255)), 10)
	a = "1.0"

	h = strconv.FormatFloat(math.Round(hsl.H*3600)/10, 'f', 1, 64)
	s = fmt.Sprintf("%.1f%%", math.Round(hsl.S*1000.0)/10.0)
	l = fmt.Sprintf("%.1f%%", math.Round(hsl.L*1000.0)/10.0)

	stripped := hex
	if len(hex) > 0 && hex[0] == '#' {
		stripped = hex[1:]
	}
	return ColorInfo{
		Hex:              hex,
		HexStripped:      stripped,
		HexAlpha:         hex + "ff",
		HexAlphaStripped: stripped + "ff",
		AlphaHex:         "#ff" + stripped,
		AlphaHexStripped: "ff" + stripped,
		RGB:              fmt.Sprintf("rgb(%s, %s, %s)", r, g, b),
		RGBA:             fmt.Sprintf("rgba(%s, %s, %s, %s)", r, g, b, a),
		HSL:              fmt.Sprintf("hsl(%s, %s, %s)", h, s, l),
		HSLA:             fmt.Sprintf("hsla(%s, %s, %s, %s)", h, s, l, a),
		R:                r,
		G:                g,
		B:                b,
		A:                a,
		H:                h,
		S:                s,
		L:                l,
	}
}

func HexToRGB(hex string) RGB {
	if hex[0] == '#' {
		hex = hex[1:]
	}
	var r, g, b uint8
	fmt.Sscanf(hex, "%02x%02x%02x", &r, &g, &b)
	return RGB{
		R: float64(r) / 255.0,
		G: float64(g) / 255.0,
		B: float64(b) / 255.0,
	}
}

func RGBToHex(rgb RGB) string {
	r := math.Max(0, math.Min(1, rgb.R))
	g := math.Max(0, math.Min(1, rgb.G))
	b := math.Max(0, math.Min(1, rgb.B))
	return fmt.Sprintf("#%02x%02x%02x", int(r*255), int(g*255), int(b*255))
}

func RGBToHSV(rgb RGB) HSV {
	max := math.Max(math.Max(rgb.R, rgb.G), rgb.B)
	min := math.Min(math.Min(rgb.R, rgb.G), rgb.B)
	delta := max - min

	var h float64
	switch {
	case delta == 0:
		h = 0
	case max == rgb.R:
		h = math.Mod((rgb.G-rgb.B)/delta, 6.0) / 6.0
	case max == rgb.G:
		h = ((rgb.B-rgb.R)/delta + 2.0) / 6.0
	default:
		h = ((rgb.R-rgb.G)/delta + 4.0) / 6.0
	}

	if h < 0 {
		h += 1.0
	}

	var s float64
	if max == 0 {
		s = 0
	} else {
		s = delta / max
	}

	return HSV{H: h, S: s, V: max}
}

func RGBToHSL(rgb RGB) HSL {
	max := math.Max(math.Max(rgb.R, rgb.G), rgb.B)
	min := math.Min(math.Min(rgb.R, rgb.G), rgb.B)
	delta := max - min
	var h, s, l float64

	l = (max + min) / 2
	if delta == 0 {
		return HSL{H: 0, S: 0, L: l}
	}

	switch max {
	case rgb.R:
		h = math.Mod((rgb.G-rgb.B)/delta, 6.0) / 6.0
	case rgb.G:
		h = ((rgb.B-rgb.R)/delta + 2.0) / 6.0
	default:
		h = ((rgb.R-rgb.G)/delta + 4.0) / 6.0
	}

	if h < 0 {
		h += 1.0
	}

	s = delta / (1 - math.Abs((2*l)-1))

	return HSL{H: h, S: s, L: l}
}

func HSVToRGB(hsv HSV) RGB {
	h := hsv.H * 6.0
	c := hsv.V * hsv.S
	x := c * (1.0 - math.Abs(math.Mod(h, 2.0)-1.0))
	m := hsv.V - c

	var r, g, b float64
	switch int(h) {
	case 0:
		r, g, b = c, x, 0
	case 1:
		r, g, b = x, c, 0
	case 2:
		r, g, b = 0, c, x
	case 3:
		r, g, b = 0, x, c
	case 4:
		r, g, b = x, 0, c
	case 5:
		r, g, b = c, 0, x
	default:
		r, g, b = c, 0, x
	}

	return RGB{R: r + m, G: g + m, B: b + m}
}

func sRGBToLinear(c float64) float64 {
	if c <= 0.04045 {
		return c / 12.92
	}
	return math.Pow((c+0.055)/1.055, 2.4)
}

func Luminance(hex string) float64 {
	rgb := HexToRGB(hex)
	return 0.2126*sRGBToLinear(rgb.R) + 0.7152*sRGBToLinear(rgb.G) + 0.0722*sRGBToLinear(rgb.B)
}

func ContrastRatio(hexFg, hexBg string) float64 {
	lumFg := Luminance(hexFg)
	lumBg := Luminance(hexBg)
	lighter := math.Max(lumFg, lumBg)
	darker := math.Min(lumFg, lumBg)
	return (lighter + 0.05) / (darker + 0.05)
}

func getLstar(hex string) float64 {
	rgb := HexToRGB(hex)
	col := colorful.Color{R: rgb.R, G: rgb.G, B: rgb.B}
	L, _, _ := col.Lab()
	return L * 100.0 // go-colorful uses 0-1, we need 0-100 for DPS
}

// Lab to hex, clamping if needed
func labToHex(L, a, b float64) string {
	c := colorful.Lab(L/100.0, a, b) // back to 0-1 for go-colorful
	r, g, b2 := c.Clamped().RGB255()
	return fmt.Sprintf("#%02x%02x%02x", r, g, b2)
}

func DeltaPhiStar(hexFg, hexBg string, negativePolarity bool) float64 {
	Lf := getLstar(hexFg)
	Lb := getLstar(hexBg)

	phi := 1.618
	inv := 0.618
	lc := math.Pow(math.Abs(math.Pow(Lb, phi)-math.Pow(Lf, phi)), inv)*1.414 - 40

	if negativePolarity {
		lc += 5
	}

	return lc
}

func DeltaPhiStarContrast(hexFg, hexBg string, isLightMode bool) float64 {
	negativePolarity := !isLightMode
	return DeltaPhiStar(hexFg, hexBg, negativePolarity)
}

func EnsureContrast(hexColor, hexBg string, minRatio float64, isLightMode bool) string {
	currentRatio := ContrastRatio(hexColor, hexBg)
	if currentRatio >= minRatio {
		return hexColor
	}

	rgb := HexToRGB(hexColor)
	hsv := RGBToHSV(rgb)

	for step := 1; step < 30; step++ {
		delta := float64(step) * 0.02

		if isLightMode {
			newV := math.Max(0, hsv.V-delta)
			candidate := RGBToHex(HSVToRGB(HSV{H: hsv.H, S: hsv.S, V: newV}))
			if ContrastRatio(candidate, hexBg) >= minRatio {
				return candidate
			}

			newV = math.Min(1, hsv.V+delta)
			candidate = RGBToHex(HSVToRGB(HSV{H: hsv.H, S: hsv.S, V: newV}))
			if ContrastRatio(candidate, hexBg) >= minRatio {
				return candidate
			}
		} else {
			newV := math.Min(1, hsv.V+delta)
			candidate := RGBToHex(HSVToRGB(HSV{H: hsv.H, S: hsv.S, V: newV}))
			if ContrastRatio(candidate, hexBg) >= minRatio {
				return candidate
			}

			newV = math.Max(0, hsv.V-delta)
			candidate = RGBToHex(HSVToRGB(HSV{H: hsv.H, S: hsv.S, V: newV}))
			if ContrastRatio(candidate, hexBg) >= minRatio {
				return candidate
			}
		}
	}

	return hexColor
}

func EnsureContrastDPS(hexColor, hexBg string, minLc float64, isLightMode bool) string {
	currentLc := DeltaPhiStarContrast(hexColor, hexBg, isLightMode)
	if currentLc >= minLc {
		return hexColor
	}

	rgb := HexToRGB(hexColor)
	hsv := RGBToHSV(rgb)

	for step := 1; step < 50; step++ {
		delta := float64(step) * 0.015

		if isLightMode {
			newV := math.Max(0, hsv.V-delta)
			candidate := RGBToHex(HSVToRGB(HSV{H: hsv.H, S: hsv.S, V: newV}))
			if DeltaPhiStarContrast(candidate, hexBg, isLightMode) >= minLc {
				return candidate
			}

			newV = math.Min(1, hsv.V+delta)
			candidate = RGBToHex(HSVToRGB(HSV{H: hsv.H, S: hsv.S, V: newV}))
			if DeltaPhiStarContrast(candidate, hexBg, isLightMode) >= minLc {
				return candidate
			}
		} else {
			newV := math.Min(1, hsv.V+delta)
			candidate := RGBToHex(HSVToRGB(HSV{H: hsv.H, S: hsv.S, V: newV}))
			if DeltaPhiStarContrast(candidate, hexBg, isLightMode) >= minLc {
				return candidate
			}

			newV = math.Max(0, hsv.V-delta)
			candidate = RGBToHex(HSVToRGB(HSV{H: hsv.H, S: hsv.S, V: newV}))
			if DeltaPhiStarContrast(candidate, hexBg, isLightMode) >= minLc {
				return candidate
			}
		}
	}

	return hexColor
}

// Nudge L* until contrast is good enough. Keeps hue intact unlike HSV fiddling.
func EnsureContrastDPSLstar(hexColor, hexBg string, minLc float64, isLightMode bool) string {
	current := DeltaPhiStarContrast(hexColor, hexBg, isLightMode)
	if current >= minLc {
		return hexColor
	}

	fg := HexToRGB(hexColor)
	cf := colorful.Color{R: fg.R, G: fg.G, B: fg.B}
	Lf, af, bf := cf.Lab()
	Lf *= 100.0

	dir := 1.0
	if isLightMode {
		dir = -1.0 // light mode = darker text
	}

	step := 0.5
	for range 120 {
		Lf = math.Max(0, math.Min(100, Lf+dir*step))
		cand := labToHex(Lf, af, bf)
		if DeltaPhiStarContrast(cand, hexBg, isLightMode) >= minLc {
			return cand
		}
	}

	return hexColor
}

// Bidirectional contrast - tries both lighter and darker, picks closest to original
func EnsureContrastDPSBidirectional(hexColor, hexBg string, minLc float64, isLightMode bool) string {
	current := DeltaPhiStarContrast(hexColor, hexBg, isLightMode)
	if current >= minLc {
		return hexColor
	}

	fg := HexToRGB(hexColor)
	cf := colorful.Color{R: fg.R, G: fg.G, B: fg.B}
	origL, af, bf := cf.Lab()
	origL *= 100.0

	var darkerResult, lighterResult string
	darkerL, lighterL := origL, origL
	darkerFound, lighterFound := false, false

	step := 0.5
	for i := range 120 {
		if !darkerFound {
			darkerL = math.Max(0, origL-float64(i)*step)
			cand := labToHex(darkerL, af, bf)
			if DeltaPhiStarContrast(cand, hexBg, isLightMode) >= minLc {
				darkerResult = cand
				darkerFound = true
			}
		}
		if !lighterFound {
			lighterL = math.Min(100, origL+float64(i)*step)
			cand := labToHex(lighterL, af, bf)
			if DeltaPhiStarContrast(cand, hexBg, isLightMode) >= minLc {
				lighterResult = cand
				lighterFound = true
			}
		}
		if darkerFound && lighterFound {
			break
		}
	}

	if darkerFound && lighterFound {
		if math.Abs(darkerL-origL) <= math.Abs(lighterL-origL) {
			return darkerResult
		}
		return lighterResult
	}
	if darkerFound {
		return darkerResult
	}
	if lighterFound {
		return lighterResult
	}
	return hexColor
}

const (
	ProfileLow    = "low"
	ProfileMedium = "medium"
	ProfileHigh   = "high"
)

var profileStrength = map[string]float64{ProfileLow: 0.25, ProfileMedium: 0.5, ProfileHigh: 0.85}

type PaletteOptions struct {
	IsLight    bool
	Background string
	Container  string
	UseDPS     bool
	Profile    string
}

func rotateTowardPrimary(hex string, primary color.Hct, strength float64) string {
	argb, err := color.ARGBFromHex(hex)
	if err != nil {
		return hex
	}
	c := argb.ToHct()
	rot := math.Min(num.DifferenceDegrees(c.Hue, primary.Hue)*0.8, 100) * strength
	hue := num.NormalizeDegree(c.Hue + rot*num.RotationDirection(c.Hue, primary.Hue))
	return strings.ToLower(color.NewHct(hue, c.Chroma, c.Tone).ToARGB().HexRGB())
}

func applyProfile(p *Palette, primaryColor, bg string, normalTarget, accentTarget float64, opts PaletteOptions) {
	strength := profileStrength[opts.Profile]
	if strength == 0 {
		return
	}
	argb, err := color.ARGBFromHex(primaryColor)
	if err != nil {
		return
	}
	primary := argb.ToHct()
	// A near-grey primary has no usable hue to rotate toward.
	if primary.Chroma < 5 {
		return
	}
	normal := func(h string) string { return ensureContrastAuto(h, bg, normalTarget, opts) }
	accent := func(h string) string { return ensureContrastBidirectional(h, bg, accentTarget, opts) }
	none := func(h string) string { return h }
	// Same per-slot contrast guards GeneratePalette applies.
	slots := []struct {
		c     *ColorInfo
		guard func(string) string
	}{
		{&p.Color1, normal}, {&p.Color2, normal}, {&p.Color3, normal}, {&p.Color4, normal},
		{&p.Color9, accent}, {&p.Color10, accent}, {&p.Color11, accent}, {&p.Color12, accent}, {&p.Color13, none}, {&p.Color14, none},
	}
	if opts.IsLight {
		slots[8].guard = accent
	}
	for _, s := range slots {
		*s.c = NewColorInfo(s.guard(rotateTowardPrimary(s.c.Hex, primary, strength)))
	}
}

func ensureContrastAuto(hexColor, hexBg string, target float64, opts PaletteOptions) string {
	if opts.UseDPS {
		return EnsureContrastDPSLstar(hexColor, hexBg, target, opts.IsLight)
	}
	return EnsureContrast(hexColor, hexBg, target, opts.IsLight)
}

func ensureContrastBidirectional(hexColor, hexBg string, target float64, opts PaletteOptions) string {
	if opts.UseDPS {
		return EnsureContrastDPSBidirectional(hexColor, hexBg, target, opts.IsLight)
	}
	return EnsureContrast(hexColor, hexBg, target, opts.IsLight)
}

func blendHue(base, target, factor float64) float64 {
	diff := target - base
	if diff > 0.5 {
		diff -= 1.0
	} else if diff < -0.5 {
		diff += 1.0
	}
	result := base + diff*factor
	if result < 0 {
		result += 1.0
	} else if result >= 1.0 {
		result -= 1.0
	}
	return result
}

// color8 sits a fixed L* offset from the background so it keeps its dim role
// regardless of primary brightness (conventional palettes put ANSI bright
// black ~2-2.5:1 from the background, e.g. catppuccin-mocha #585b70 on #1e1e2e)
func DeriveDim(bgHex string, hue, sat float64, isLight bool) string {
	offset := 22.0
	if isLight {
		offset = -offset
	}

	bgL := getLstar(bgHex)
	targetL := math.Max(0, math.Min(100, bgL+offset))

	tint := HSVToRGB(HSV{H: hue, S: sat, V: 0.5})
	c := colorful.Color{R: tint.R, G: tint.G, B: tint.B}
	_, af, bf := c.Lab()
	return labToHex(targetL, af, bf)
}

func DeriveContainer(primary string, isLight bool) string {
	rgb := HexToRGB(primary)
	hsv := RGBToHSV(rgb)

	if isLight {
		containerV := math.Min(hsv.V*1.77, 1.0)
		containerS := hsv.S * 0.32
		return RGBToHex(HSVToRGB(HSV{H: hsv.H, S: containerS, V: containerV}))
	}
	containerV := hsv.V * 0.463
	containerS := math.Min(hsv.S*1.834, 1.0)
	return RGBToHex(HSVToRGB(HSV{H: hsv.H, S: containerS, V: containerV}))
}

// DeriveContainer only approximates the Material tone pairing, so a caller that
// has the real primary_container should pass it: color5 and color6 are the
// primary/container pair and their contrast with each other is the invariant.
func resolveContainer(primaryColor string, opts PaletteOptions) string {
	if opts.Container != "" {
		return opts.Container
	}
	return DeriveContainer(primaryColor, opts.IsLight)
}

func GeneratePalette(primaryColor string, opts PaletteOptions) Palette {
	baseColor := resolveContainer(primaryColor, opts)

	rgb := HexToRGB(baseColor)
	hsv := RGBToHSV(rgb)

	pr := HexToRGB(primaryColor)
	ph := RGBToHSV(pr)

	var palette Palette

	// Delta Phi Star is not symmetric across polarity: on a light background the
	// same Lc buys far less real contrast, so the light targets are the numbers
	// that land on the same measured WCAG ratios the dark ones already deliver.
	var normalTextTarget, accentTarget float64
	switch {
	case opts.UseDPS && opts.IsLight:
		normalTextTarget = 70.0
		accentTarget = 58.0
	case opts.UseDPS:
		normalTextTarget = 40.0
		accentTarget = 24.5
	default:
		normalTextTarget = 4.5
		accentTarget = 2.1
	}

	var bgColor string
	if opts.Background != "" {
		bgColor = opts.Background
	} else if opts.IsLight {
		bgColor = "#f8f8f8"
	} else {
		bgColor = "#1a1a1a"
	}
	palette.Color0 = NewColorInfo(bgColor)

	baseSat := math.Max(ph.S, 0.5)
	baseVal := math.Max(ph.V, 0.5)

	redH := blendHue(0.0, ph.H, 0.12)
	greenH := blendHue(0.33, ph.H, 0.10)
	yellowH := blendHue(0.14, ph.H, 0.04)

	if opts.IsLight {
		redS := math.Min(baseSat*1.2, 1.0)
		redV := baseVal * 0.95
		palette.Color1 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: redH, S: redS, V: redV})), bgColor, normalTextTarget, opts))

		greenS := math.Min(baseSat*1.3, 1.0)
		greenV := baseVal * 0.75
		palette.Color2 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: greenH, S: greenS, V: greenV})), bgColor, normalTextTarget, opts))

		yellowS := math.Min(baseSat*1.5, 1.0)
		yellowV := math.Min(baseVal*1.2, 1.0)
		palette.Color3 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: yellowH, S: yellowS, V: yellowV})), bgColor, normalTextTarget, opts))

		blueS := math.Min(ph.S*1.05, 1.0)
		blueV := math.Min(ph.V*1.05, 1.0)
		palette.Color4 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: ph.H, S: blueS, V: blueV})), bgColor, normalTextTarget, opts))

		palette.Color5 = NewColorInfo(baseColor)

		palette.Color6 = NewColorInfo(primaryColor)

		gray7S := baseSat * 0.08
		gray7V := baseVal * 0.28
		palette.Color7 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: hsv.H, S: gray7S, V: gray7V})), bgColor, normalTextTarget, opts))

		palette.Color8 = NewColorInfo(DeriveDim(bgColor, hsv.H, baseSat*0.05, true))

		brightRedS := math.Min(baseSat*1.0, 1.0)
		brightRedV := math.Min(baseVal*1.2, 1.0)
		palette.Color9 = NewColorInfo(ensureContrastBidirectional(RGBToHex(HSVToRGB(HSV{H: redH, S: brightRedS, V: brightRedV})), bgColor, accentTarget, opts))

		brightGreenS := math.Min(baseSat*1.1, 1.0)
		brightGreenV := math.Min(baseVal*1.1, 1.0)
		palette.Color10 = NewColorInfo(ensureContrastBidirectional(RGBToHex(HSVToRGB(HSV{H: greenH, S: brightGreenS, V: brightGreenV})), bgColor, accentTarget, opts))

		brightYellowS := math.Min(baseSat*1.4, 1.0)
		brightYellowV := math.Min(baseVal*1.3, 1.0)
		palette.Color11 = NewColorInfo(ensureContrastBidirectional(RGBToHex(HSVToRGB(HSV{H: yellowH, S: brightYellowS, V: brightYellowV})), bgColor, accentTarget, opts))

		brightBlueS := math.Min(ph.S*1.1, 1.0)
		brightBlueV := math.Min(ph.V*1.15, 1.0)
		palette.Color12 = NewColorInfo(ensureContrastBidirectional(RGBToHex(HSVToRGB(HSV{H: ph.H, S: brightBlueS, V: brightBlueV})), bgColor, accentTarget, opts))

		color13S := ph.S * 0.7
		color13V := math.Min(ph.V*1.3, 1.0)
		palette.Color13 = NewColorInfo(ensureContrastBidirectional(RGBToHex(HSVToRGB(HSV{H: ph.H, S: color13S, V: color13V})), bgColor, accentTarget, opts))

		brightCyanS := ph.S * 0.5
		brightCyanV := math.Min(ph.V*1.3, 1.0)
		palette.Color14 = NewColorInfo(RGBToHex(HSVToRGB(HSV{H: ph.H, S: brightCyanS, V: brightCyanV})))

		white15S := baseSat * 0.04
		white15V := math.Min(baseVal*1.5, 1.0)
		palette.Color15 = NewColorInfo(RGBToHex(HSVToRGB(HSV{H: hsv.H, S: white15S, V: white15V})))
	} else {
		redS := math.Min(baseSat*1.1, 1.0)
		redV := math.Min(baseVal*1.15, 1.0)
		palette.Color1 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: redH, S: redS, V: redV})), bgColor, normalTextTarget, opts))

		greenS := math.Min(baseSat*1.0, 1.0)
		greenV := math.Min(baseVal*1.0, 1.0)
		palette.Color2 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: greenH, S: greenS, V: greenV})), bgColor, normalTextTarget, opts))

		yellowS := math.Min(baseSat*1.1, 1.0)
		yellowV := math.Min(baseVal*1.25, 1.0)
		palette.Color3 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: yellowH, S: yellowS, V: yellowV})), bgColor, normalTextTarget, opts))

		// Slightly more saturated variant of primary
		blueS := math.Min(ph.S*1.2, 1.0)
		blueV := ph.V * 0.95
		palette.Color4 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: ph.H, S: blueS, V: blueV})), bgColor, normalTextTarget, opts))

		palette.Color5 = NewColorInfo(baseColor)

		palette.Color6 = NewColorInfo(primaryColor)

		gray7S := baseSat * 0.12
		gray7V := math.Min(baseVal*1.05, 1.0)
		palette.Color7 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: hsv.H, S: gray7S, V: gray7V})), bgColor, normalTextTarget, opts))

		palette.Color8 = NewColorInfo(DeriveDim(bgColor, hsv.H, baseSat*0.15, false))

		brightRedS := math.Min(baseSat*0.75, 1.0)
		brightRedV := math.Min(baseVal*1.35, 1.0)
		palette.Color9 = NewColorInfo(ensureContrastBidirectional(RGBToHex(HSVToRGB(HSV{H: redH, S: brightRedS, V: brightRedV})), bgColor, accentTarget, opts))

		brightGreenS := math.Min(baseSat*0.7, 1.0)
		brightGreenV := math.Min(baseVal*1.2, 1.0)
		palette.Color10 = NewColorInfo(ensureContrastBidirectional(RGBToHex(HSVToRGB(HSV{H: greenH, S: brightGreenS, V: brightGreenV})), bgColor, accentTarget, opts))

		brightYellowS := math.Min(baseSat*0.7, 1.0)
		brightYellowV := math.Min(baseVal*1.5, 1.0)
		palette.Color11 = NewColorInfo(ensureContrastBidirectional(RGBToHex(HSVToRGB(HSV{H: yellowH, S: brightYellowS, V: brightYellowV})), bgColor, accentTarget, opts))

		// Create a gradient of primary variants: Color12 -> Color13 -> Color14 -> Color15 (near white)
		// Color12: Start of the lighter gradient - slightly desaturated
		brightBlueS := ph.S * 0.85
		brightBlueV := math.Min(ph.V*1.1, 1.0)
		palette.Color12 = NewColorInfo(ensureContrastBidirectional(RGBToHex(HSVToRGB(HSV{H: ph.H, S: brightBlueS, V: brightBlueV})), bgColor, accentTarget, opts))

		// Medium-high saturation pastel primary
		color13S := ph.S * 0.7
		color13V := math.Min(ph.V*1.3, 1.0)
		palette.Color13 = NewColorInfo(RGBToHex(HSVToRGB(HSV{H: ph.H, S: color13S, V: color13V})))

		// Lower saturation, lighter variant
		color14S := ph.S * 0.45
		color14V := math.Min(ph.V*1.4, 1.0)
		palette.Color14 = NewColorInfo(RGBToHex(HSVToRGB(HSV{H: ph.H, S: color14S, V: color14V})))

		white15S := baseSat * 0.05
		white15V := math.Min(baseVal*1.45, 1.0)
		palette.Color15 = NewColorInfo(ensureContrastAuto(RGBToHex(HSVToRGB(HSV{H: hsv.H, S: white15S, V: white15V})), bgColor, normalTextTarget, opts))
	}

	applyProfile(&palette, primaryColor, bgColor, normalTextTarget, accentTarget, opts)

	return palette
}

type VariantOptions struct {
	PrimaryDark     string
	PrimaryLight    string
	BackgroundDark  string
	BackgroundLight string
	ContainerDark   string
	ContainerLight  string
	UseDPS          bool
	IsLightMode     bool
	Profile         string
}

func mergeColorInfo(dark, light ColorInfo, isLightMode bool) VariantColorInfo {
	defaultVal := dark
	if isLightMode {
		defaultVal = light
	}

	return VariantColorInfo{
		Dark:    dark,
		Light:   light,
		Default: defaultVal,
	}
}

func GenerateVariantPalette(opts VariantOptions) VariantPalette {
	darkOpts := PaletteOptions{IsLight: false, Background: opts.BackgroundDark, Container: opts.ContainerDark, UseDPS: opts.UseDPS, Profile: opts.Profile}
	lightOpts := PaletteOptions{IsLight: true, Background: opts.BackgroundLight, Container: opts.ContainerLight, UseDPS: opts.UseDPS, Profile: opts.Profile}

	dark := GeneratePalette(opts.PrimaryDark, darkOpts)
	light := GeneratePalette(opts.PrimaryLight, lightOpts)

	return VariantPalette{
		Color0:  mergeColorInfo(dark.Color0, light.Color0, opts.IsLightMode),
		Color1:  mergeColorInfo(dark.Color1, light.Color1, opts.IsLightMode),
		Color2:  mergeColorInfo(dark.Color2, light.Color2, opts.IsLightMode),
		Color3:  mergeColorInfo(dark.Color3, light.Color3, opts.IsLightMode),
		Color4:  mergeColorInfo(dark.Color4, light.Color4, opts.IsLightMode),
		Color5:  mergeColorInfo(dark.Color5, light.Color5, opts.IsLightMode),
		Color6:  mergeColorInfo(dark.Color6, light.Color6, opts.IsLightMode),
		Color7:  mergeColorInfo(dark.Color7, light.Color7, opts.IsLightMode),
		Color8:  mergeColorInfo(dark.Color8, light.Color8, opts.IsLightMode),
		Color9:  mergeColorInfo(dark.Color9, light.Color9, opts.IsLightMode),
		Color10: mergeColorInfo(dark.Color10, light.Color10, opts.IsLightMode),
		Color11: mergeColorInfo(dark.Color11, light.Color11, opts.IsLightMode),
		Color12: mergeColorInfo(dark.Color12, light.Color12, opts.IsLightMode),
		Color13: mergeColorInfo(dark.Color13, light.Color13, opts.IsLightMode),
		Color14: mergeColorInfo(dark.Color14, light.Color14, opts.IsLightMode),
		Color15: mergeColorInfo(dark.Color15, light.Color15, opts.IsLightMode),
	}
}
