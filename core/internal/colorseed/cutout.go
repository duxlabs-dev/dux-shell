package colorseed

import (
	"image"
	imgcolor "image/color"
	"image/draw"
	"math"
	"slices"

	"github.com/duxlabs-dev/dux-go/material/color"
	xdraw "golang.org/x/image/draw"
)

// Cut-out stages, named after the design study: the logo's own plate stripped, a dark framed tile's
// bright marks, a full-bleed logo with its light parts punched out, or an open logo shaded by its value.
const (
	StagePlateStrip = "plate-strip"
	StageTileLuma   = "tile-luma-sil"
	StageCutoutSil  = "cutout-sil"
	StageDepthSil   = "depth-sil"
)

const (
	// CutoutDim is the side of the square Cutout returns.
	CutoutDim     = 192
	cutoutWorkDim = 256
	cutoutMargin  = 0.06
	// Below this alpha a pixel is not part of the mark when cropping.
	cutoutMinAlpha = 0.25

	// plate-strip: RGB distance from the plate where the mark starts, and the range its full alpha is reached over.
	stripNear   = 28.0
	stripFarMin = 68.0
	stripFarMax = 140.0
	stripFarP95 = 0.75
	// The plate's rim, where bevels and drop shadows sit, as a share of the canvas.
	stripRim = 0.03

	// A full-bleed square tile with a dark, uneven face under bright marks, like Ghostty's screen in its bezel.
	tileMinSquare   = 0.85
	tileMaxBand     = 0.6
	tileMaxMedian   = 70.0
	tileMinBright   = 160.0
	tileLumaOffset  = 22.0
	tileLumaRange   = 48.0
	tileInnerSquare = 0.8

	// cutout-sil: how light and gray a pixel must be to be a hole in a full-bleed logo.
	holeMinLight = 0.72
	holeLightAA  = 0.2
	holeMaxSat   = 0.28
	holeSatAA    = 0.12
	// cutout-sil: a seam runs where two saturated hues this far apart meet.
	seamMinSat     = 0.35
	seamMinValue   = 0.3
	seamMinHueStep = 35.0
	seamHalfWidth  = 2

	// depth-sil: the darkest of the logo keeps this much alpha, its lightest all of it.
	depthFloor = 0.58
)

// Cutout cuts a logo down to its mark: white, with the mark in alpha, centered in a CutoutDim
// square. It reports which stage cut it, and false when no mark is left.
func Cutout(img image.Image) (*image.NRGBA, string, bool) {
	work := squareOf(img, cutoutWorkDim)
	alpha, stage := cutAlpha(work)
	out, ok := frame(alpha, work.Bounds())
	return out, stage, ok
}

// squareOf draws img centered in an n×n square, aspect kept, the way IconImage does.
func squareOf(img image.Image, n int) *image.NRGBA {
	b := img.Bounds()
	dst := image.NewRGBA(image.Rect(0, 0, n, n))
	if b.Empty() {
		return nrgbaOf(dst)
	}
	scale := float64(n) / float64(max(b.Dx(), b.Dy()))
	w, h := max(int(math.Round(float64(b.Dx())*scale)), 1), max(int(math.Round(float64(b.Dy())*scale)), 1)
	x, y := (n-w)/2, (n-h)/2
	xdraw.CatmullRom.Scale(dst, image.Rect(x, y, x+w, y+h), img, b, xdraw.Src, nil)
	return nrgbaOf(dst)
}

// cutAlpha is the mark's coverage per pixel, 0–1, row by row over img's bounds.
func cutAlpha(img *image.NRGBA) ([]float64, string) {
	m := measurePlate(img)
	switch {
	case m.plated:
		return stripPlate(img, m.plate), StagePlateStrip
	case m.square >= tileMinSquare && m.band < tileMaxBand:
		if alpha, ok := tileLuma(img); ok {
			return alpha, StageTileLuma
		}
	}
	if m.fill() >= plateMinFill {
		return punchHoles(img), StageCutoutSil
	}
	return depth(img), StageDepthSil
}

func pixelAlpha(img *image.NRGBA, fn func(r, g, b, a float64) float64) []float64 {
	b := img.Bounds()
	alpha := make([]float64, 0, b.Dx()*b.Dy())
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			p := img.NRGBAAt(x, y)
			alpha = append(alpha, fn(float64(p.R), float64(p.G), float64(p.B), float64(p.A)/255))
		}
	}
	return alpha
}

// stripPlate keeps what differs from the plate in RGB, so a mark close to it in lightness but
// not in color survives. The plate is fitted as a plane, so a shaded plate strips as cleanly
// as a flat one, and its rim, where bevels and shadows sit, goes.
func stripPlate(img *image.NRGBA, plate color.ARGB) []float64 {
	fit := fitPlate(img, plate)
	inner := innerMask(img, int(math.Round(stripRim*float64(img.Bounds().Dx()))))
	b := img.Bounds()
	dist := make([]float64, 0, b.Dx()*b.Dy())
	var drawn []float64
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			p := img.NRGBAAt(x, y)
			d := fit.distance(x, y, p)
			dist = append(dist, d)
			if p.A >= 128 {
				drawn = append(drawn, d)
			}
		}
	}
	far := min(max(stripFarP95*percentile(drawn, 0.95), stripFarMin), stripFarMax)
	alpha := pixelAlpha(img, func(_, _, _, a float64) float64 { return a })
	for i := range alpha {
		if !inner[i] {
			alpha[i] = 0
			continue
		}
		alpha[i] *= ramp(dist[i], stripNear, far)
	}
	return alpha
}

// planeFit is a color per channel as c0 + c1·x + c2·y.
type planeFit [3][3]float64

func (f planeFit) distance(x, y int, p imgcolor.NRGBA) float64 {
	sum := 0.0
	for ch, v := range [3]uint8{p.R, p.G, p.B} {
		want := f[ch][0] + f[ch][1]*float64(x) + f[ch][2]*float64(y)
		sum += sq(float64(v) - min(max(want, 0), 255))
	}
	return math.Sqrt(sum)
}

// fitPlate fits the plate's color over the band pixels near it, twice so the second fit covers
// shaded ends. Too few pixels, or a degenerate spread, keep it flat.
func fitPlate(img *image.NRGBA, plate color.ARGB) planeFit {
	flat := planeFit{{float64(plate.Red())}, {float64(plate.Green())}, {float64(plate.Blue())}}
	box := opaqueBounds(img)
	cx, cy := float64(box.Min.X+box.Max.X-1)/2, float64(box.Min.Y+box.Max.Y-1)/2
	rx, ry := float64(box.Dx()-1)/2, float64(box.Dy()-1)/2
	if rx <= 0 || ry <= 0 {
		return flat
	}
	fit := flat
	for range 2 {
		var m [3][3]float64
		var rhs [3][3]float64
		n := 0
		for y := box.Min.Y; y < box.Max.Y; y++ {
			for x := box.Min.X; x < box.Max.X; x++ {
				p := img.NRGBAAt(x, y)
				ex, ey := (float64(x)-cx)/rx, (float64(y)-cy)/ry
				r, rc := max(math.Abs(ex), math.Abs(ey)), math.Hypot(ex, ey)
				inBand := (r > plateSquareInner && r < plateSquareOuter) || (rc > plateRoundInner && rc < plateRoundOuter)
				if p.A < plateMinAlpha || !inBand || fit.distance(x, y, p) >= plateNearDist {
					continue
				}
				v := [3]float64{1, float64(x), float64(y)}
				for i := range 3 {
					for j := range 3 {
						m[i][j] += v[i] * v[j]
					}
					for ch, c := range [3]uint8{p.R, p.G, p.B} {
						rhs[ch][i] += v[i] * float64(c)
					}
				}
				n++
			}
		}
		next, ok := solvePlane(m, rhs)
		if n < 16 || !ok {
			return fit
		}
		fit = next
	}
	return fit
}

// solvePlane solves m·c = rhs for each channel by Cramer's rule.
func solvePlane(m, rhs [3][3]float64) (planeFit, bool) {
	det := func(a [3][3]float64) float64 {
		return a[0][0]*(a[1][1]*a[2][2]-a[1][2]*a[2][1]) - a[0][1]*(a[1][0]*a[2][2]-a[1][2]*a[2][0]) + a[0][2]*(a[1][0]*a[2][1]-a[1][1]*a[2][0])
	}
	d := det(m)
	if math.Abs(d) < 1e-6 {
		return planeFit{}, false
	}
	var fit planeFit
	for ch := range 3 {
		for col := range 3 {
			a := m
			for row := range 3 {
				a[row][col] = rhs[ch][row]
			}
			fit[ch][col] = det(a) / d
		}
	}
	return fit, true
}

// innerMask marks the pixels at least k pixels inside the icon's at least half opaque shape.
func innerMask(img *image.NRGBA, k int) []bool {
	b := img.Bounds()
	opaque := func(x, y int) bool {
		return image.Pt(x, y).In(b) && img.NRGBAAt(x, y).A >= 128
	}
	diag := int(math.Round(float64(k) / math.Sqrt2))
	mask := make([]bool, 0, b.Dx()*b.Dy())
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			mask = append(mask, opaque(x, y) && opaque(x-k, y) && opaque(x+k, y) && opaque(x, y-k) && opaque(x, y+k) &&
				opaque(x-diag, y-diag) && opaque(x+diag, y-diag) && opaque(x-diag, y+diag) && opaque(x+diag, y+diag))
		}
	}
	return mask
}

// tileLuma keeps what is well above the tile face's median luma, or reports false for a face that
// is not dark under bright marks.
func tileLuma(img *image.NRGBA) ([]float64, bool) {
	b := img.Bounds()
	box := opaqueBounds(img)
	cx, cy := float64(box.Min.X+box.Max.X-1)/2, float64(box.Min.Y+box.Max.Y-1)/2
	rx, ry := float64(box.Dx()-1)/2, float64(box.Dy()-1)/2
	if rx <= 0 || ry <= 0 {
		return nil, false
	}
	var face []float64
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			p := img.NRGBAAt(x, y)
			if p.A < plateMinAlpha || max(math.Abs(float64(x)-cx)/rx, math.Abs(float64(y)-cy)/ry) >= tileInnerSquare {
				continue
			}
			face = append(face, luma(float64(p.R), float64(p.G), float64(p.B)))
		}
	}
	median := percentile(face, 0.5)
	if len(face) == 0 || median >= tileMaxMedian || percentile(face, 0.95) <= tileMinBright {
		return nil, false
	}
	from := median + tileLumaOffset
	return pixelAlpha(img, func(r, g, b, a float64) float64 {
		return ramp(luma(r, g, b), from, from+tileLumaRange) * a
	}), true
}

// punchHoles keeps a full-bleed logo's shape and punches out its light grays and the seams
// between saturated hues, so the parts it is made of stay apart.
func punchHoles(img *image.NRGBA) []float64 {
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	hues := make([]float64, 0, w*h)
	alpha := pixelAlpha(img, func(r, g, b, a float64) float64 {
		v, s := hsv(r, g, b)
		hue := -1.0
		if s >= seamMinSat && v >= seamMinValue && a >= 0.5 {
			hue = hueOf(r, g, b)
		}
		hues = append(hues, hue)
		hole := ramp(v, holeMinLight, holeMinLight+holeLightAA) * (1 - ramp(s, holeMaxSat, holeMaxSat+holeSatAA))
		return (1 - hole) * a
	})
	for y := range h {
		for x := range w {
			hue := hues[y*w+x]
			if hue < 0 {
				continue
			}
		seam:
			for _, d := range [][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {1, -1}, {-1, 1}} {
				for step := 1; step <= seamHalfWidth; step++ {
					nx, ny := x+d[0]*step, y+d[1]*step
					if nx < 0 || nx >= w || ny < 0 || ny >= h {
						break
					}
					if other := hues[ny*w+nx]; other >= 0 && hueDistance(hue, other) > seamMinHueStep {
						alpha[y*w+x] = 0
						break seam
					}
				}
			}
		}
	}
	return alpha
}

// depth keeps an open logo's whole shape, its darker parts fainter, so folds and overlaps still show.
func depth(img *image.NRGBA) []float64 {
	var values []float64
	bounds := img.Bounds()
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			if p := img.NRGBAAt(x, y); p.A >= 128 {
				v, _ := hsv(float64(p.R), float64(p.G), float64(p.B))
				values = append(values, v)
			}
		}
	}
	lo, hi := percentile(values, 0.05), percentile(values, 0.95)
	return pixelAlpha(img, func(r, g, b, a float64) float64 {
		norm := 1.0
		if hi-lo > 0.05 {
			v, _ := hsv(r, g, b)
			norm = ramp(v, lo, hi)
		}
		return (depthFloor + (1-depthFloor)*norm) * a
	})
}

// frame crops alpha to the mark plus a margin, squares it about the mark's center and scales it to CutoutDim.
func frame(alpha []float64, b image.Rectangle) (*image.NRGBA, bool) {
	w := b.Dx()
	mark := image.Rectangle{}
	for i, a := range alpha {
		if a >= cutoutMinAlpha {
			x, y := i%w, i/w
			mark = mark.Union(image.Rect(x, y, x+1, y+1))
		}
	}
	if mark.Dx() < 4 || mark.Dy() < 4 {
		return nil, false
	}
	side := int(math.Ceil(float64(max(mark.Dx(), mark.Dy())) * (1 + 2*cutoutMargin)))
	canvas := image.NewAlpha(image.Rect(0, 0, side, side))
	off := image.Pt((side-mark.Dx())/2-mark.Min.X, (side-mark.Dy())/2-mark.Min.Y)
	for i, a := range alpha {
		if p := image.Pt(i%w+off.X, i/w+off.Y); p.In(canvas.Rect) {
			canvas.Pix[canvas.PixOffset(p.X, p.Y)] = uint8(math.Round(min(max(a, 0), 1) * 255))
		}
	}
	scaled := image.NewAlpha(image.Rect(0, 0, CutoutDim, CutoutDim))
	xdraw.CatmullRom.Scale(scaled, scaled.Rect, canvas, canvas.Rect, draw.Src, nil)
	out := image.NewNRGBA(scaled.Rect)
	for i, a := range scaled.Pix {
		out.Pix[4*i], out.Pix[4*i+1], out.Pix[4*i+2], out.Pix[4*i+3] = 255, 255, 255, a
	}
	return out, true
}

func ramp(v, lo, hi float64) float64 {
	if hi <= lo {
		if v >= hi {
			return 1
		}
		return 0
	}
	return min(max((v-lo)/(hi-lo), 0), 1)
}

func luma(r, g, b float64) float64 {
	return 0.299*r + 0.587*g + 0.114*b
}

// hsv returns HSV value and saturation, 0–1, from 0–255 channels.
func hsv(r, g, b float64) (v, s float64) {
	hi, lo := max(r, g, b), min(r, g, b)
	if hi == 0 {
		return 0, 0
	}
	return hi / 255, (hi - lo) / hi
}

// hueOf is the HSV hue in degrees of 0–255 channels.
func hueOf(r, g, b float64) float64 {
	hi, lo := max(r, g, b), min(r, g, b)
	if hi == lo {
		return 0
	}
	var hue float64
	switch hi {
	case r:
		hue = math.Mod((g-b)/(hi-lo), 6)
	case g:
		hue = (b-r)/(hi-lo) + 2
	default:
		hue = (r-g)/(hi-lo) + 4
	}
	if hue *= 60; hue < 0 {
		hue += 360
	}
	return hue
}

func hueDistance(a, b float64) float64 {
	d := math.Abs(a - b)
	return min(d, 360-d)
}

func percentile(values []float64, p float64) float64 {
	if len(values) == 0 {
		return 0
	}
	sorted := slices.Clone(values)
	slices.Sort(sorted)
	return sorted[min(int(p*float64(len(sorted)-1)+0.5), len(sorted)-1)]
}
