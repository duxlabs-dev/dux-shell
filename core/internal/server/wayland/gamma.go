package wayland

import (
	"math"

	"github.com/duxlabs-dev/dux-shell/core/internal/icc"
)

type GammaRamp struct {
	Red   []uint16
	Green []uint16
	Blue  []uint16
}

type rgb struct {
	r, g, b float64
}

type xyz struct {
	x, y, z float64
}

func illuminantD(temp int) (float64, float64, bool) {
	var x float64
	switch {
	case temp >= 2500 && temp <= 7000:
		t := float64(temp)
		x = 0.244063 + 0.09911e3/t + 2.9678e6/(t*t) - 4.6070e9/(t*t*t)
	case temp > 7000 && temp <= 25000:
		t := float64(temp)
		x = 0.237040 + 0.24748e3/t + 1.9018e6/(t*t) - 2.0064e9/(t*t*t)
	default:
		return 0, 0, false
	}
	y := -3*(x*x) + 2.870*x - 0.275
	return x, y, true
}

func planckianLocus(temp int) (float64, float64, bool) {
	var x, y float64
	switch {
	case temp >= 1667 && temp <= 4000:
		t := float64(temp)
		x = -0.2661239e9/(t*t*t) - 0.2343589e6/(t*t) + 0.8776956e3/t + 0.179910
		if temp <= 2222 {
			y = -1.1064814*(x*x*x) - 1.34811020*(x*x) + 2.18555832*x - 0.20219683
		} else {
			y = -0.9549476*(x*x*x) - 1.37418593*(x*x) + 2.09137015*x - 0.16748867
		}
	case temp > 4000 && temp < 25000:
		t := float64(temp)
		x = -3.0258469e9/(t*t*t) + 2.1070379e6/(t*t) + 0.2226347e3/t + 0.240390
		y = 3.0817580*(x*x*x) - 5.87338670*(x*x) + 3.75112997*x - 0.37001483
	default:
		return 0, 0, false
	}
	return x, y, true
}

func srgbGamma(value, gamma float64) float64 {
	if value <= 0.0031308 {
		return 12.92 * value
	}
	return math.Pow(1.055*value, 1.0/gamma) - 0.055
}

func clamp01(v float64) float64 {
	switch {
	case v > 1.0:
		return 1.0
	case v < 0.0:
		return 0.0
	default:
		return v
	}
}

func xyzToSRGB(c xyz) rgb {
	return rgb{
		r: srgbGamma(clamp01(3.2404542*c.x-1.5371385*c.y-0.4985314*c.z), 2.2),
		g: srgbGamma(clamp01(-0.9692660*c.x+1.8760108*c.y+0.0415560*c.z), 2.2),
		b: srgbGamma(clamp01(0.0556434*c.x-0.2040259*c.y+1.0572252*c.z), 2.2),
	}
}

func normalizeRGB(c *rgb) {
	maxw := math.Max(c.r, math.Max(c.g, c.b))
	if maxw > 0 {
		c.r /= maxw
		c.g /= maxw
		c.b /= maxw
	}
}

func calcWhitepoint(temp int) rgb {
	if temp == 6500 {
		return rgb{r: 1.0, g: 1.0, b: 1.0}
	}

	var wp xyz

	switch {
	case temp >= 25000:
		x, y, _ := illuminantD(25000)
		wp.x = x
		wp.y = y
	case temp >= 4000:
		x, y, _ := illuminantD(temp)
		wp.x = x
		wp.y = y
	case temp >= 2500:
		x1, y1, _ := illuminantD(temp)
		x2, y2, _ := planckianLocus(temp)
		factor := float64(4000-temp) / 1500.0
		sineFactor := (math.Cos(math.Pi*factor) + 1.0) / 2.0
		wp.x = x1*sineFactor + x2*(1.0-sineFactor)
		wp.y = y1*sineFactor + y2*(1.0-sineFactor)
	default:
		t := max(temp, 1667)
		x, y, _ := planckianLocus(t)
		wp.x = x
		wp.y = y
	}

	wp.z = 1.0 - wp.x - wp.y

	wpRGB := xyzToSRGB(wp)
	normalizeRGB(&wpRGB)
	return wpRGB
}

func applyContrast(val, contrast float64) float64 {
	return clamp01((val-0.5)*contrast + 0.5)
}

func GenerateGammaRamp(size uint32, temp int, gamma, contrast float64) GammaRamp {
	ramp := GammaRamp{
		Red:   make([]uint16, size),
		Green: make([]uint16, size),
		Blue:  make([]uint16, size),
	}

	wp := calcWhitepoint(temp)

	for i := range size {
		val := applyContrast(float64(i)/float64(size-1), contrast)
		ramp.Red[i] = uint16(clamp01(math.Pow(val*wp.r, 1.0/gamma)) * 65535.0)
		ramp.Green[i] = uint16(clamp01(math.Pow(val*wp.g, 1.0/gamma)) * 65535.0)
		ramp.Blue[i] = uint16(clamp01(math.Pow(val*wp.b, 1.0/gamma)) * 65535.0)
	}

	return ramp
}

func brightnessScale(percent int) float64 {
	return outputBrightnessFloor + (1-outputBrightnessFloor)*float64(percent)/100
}

// scaleRamp dims the ramp in perceived brightness, not light output.
func scaleRamp(ramp GammaRamp, factor float64) {
	for _, channel := range [][]uint16{ramp.Red, ramp.Green, ramp.Blue} {
		for i, v := range channel {
			channel[i] = uint16(float64(v) * factor)
		}
	}
}

func GenerateIdentityRamp(size uint32) GammaRamp {
	ramp := GammaRamp{
		Red:   make([]uint16, size),
		Green: make([]uint16, size),
		Blue:  make([]uint16, size),
	}

	for i := range size {
		val := uint16((float64(i) / float64(size-1)) * 65535.0)
		ramp.Red[i] = val
		ramp.Green[i] = val
		ramp.Blue[i] = val
	}

	return ramp
}

// ProfileRampWithTemp builds the ramp for an output with an ICC profile: the
// vcgt table is sampled at the contrast-adjusted input, the user gamma is
// applied to the result, and a temperature target (targetTemp > 0) is composed
// as the white point ratio against baseTemp, the profile's reference white.
func ProfileRampWithTemp(size uint32, profile *icc.Profile, baseTemp, targetTemp int, gamma, contrast float64) (GammaRamp, error) {
	iccRamp, err := icc.GenerateGammaRampAt(size, profile, func(t float64) float64 { return applyContrast(t, contrast) })
	if err != nil {
		return GammaRamp{}, err
	}

	tint := whitepointRatio(baseTemp, targetTemp)
	ramp := GammaRamp{
		Red:   make([]uint16, size),
		Green: make([]uint16, size),
		Blue:  make([]uint16, size),
	}
	for i := range size {
		ramp.Red[i] = adjustRampValue(iccRamp.Red[i], tint.r, gamma)
		ramp.Green[i] = adjustRampValue(iccRamp.Green[i], tint.g, gamma)
		ramp.Blue[i] = adjustRampValue(iccRamp.Blue[i], tint.b, gamma)
	}
	return ramp, nil
}

func whitepointRatio(baseTemp, targetTemp int) rgb {
	if targetTemp <= 0 || targetTemp == baseTemp {
		return rgb{r: 1, g: 1, b: 1}
	}
	base := calcWhitepoint(baseTemp)
	target := calcWhitepoint(targetTemp)
	return rgb{
		r: channelRatio(target.r, base.r),
		g: channelRatio(target.g, base.g),
		b: channelRatio(target.b, base.b),
	}
}

func channelRatio(target, base float64) float64 {
	if base <= 0 {
		return 1
	}
	return target / base
}

func adjustRampValue(value uint16, tint, gamma float64) uint16 {
	linear := clamp01(float64(value) / 65535.0 * tint)
	return uint16(math.Round(clamp01(math.Pow(linear, 1.0/gamma)) * 65535.0))
}
