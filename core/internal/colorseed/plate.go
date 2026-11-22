package colorseed

import (
	"image"
	imgcolor "image/color"
	"math"

	"github.com/duxlabs-dev/dux-go/material/color"
)

// Plate detection, ported from the Dux Icons design mockup: a plated icon shows one color all
// round the band just inside its outline.
const (
	plateMinAlpha    = 250
	plateSquareInner = 0.8
	plateSquareOuter = 0.95
	plateRoundInner  = 0.8
	plateRoundOuter  = 0.93
	plateNearDist    = 48.0
	plateMinBand     = 0.6
	plateMinCover    = 0.3
	// A plate carries a mark of another color; one color all over is the logo itself.
	plateMaxCover = 0.97
	// A plate fills the square or round band all the way round. Open silhouettes like VS Code's leave most
	// of it transparent, and what they do draw there can be one color.
	plateMinFill = 0.72
	// Reach counts what the generator sees as the icon: at least half opaque.
	reachMinAlpha = 128
)

type rgbSum struct {
	r, g, b float64
	n       int
}

// Plate returns the color of the plate the icon is drawn on, if it has one.
func Plate(img image.Image) (color.ARGB, bool) {
	m := measurePlate(nrgbaOf(img))
	return m.plate, m.plated
}

// plateMeasure is what Plate found: the band's most common color, how full the square and round
// bands are, how much of the band is near that color and how much of the icon it covers.
type plateMeasure struct {
	plate         color.ARGB
	plated        bool
	square, round float64
	band, cover   float64
}

func (m plateMeasure) fill() float64 {
	return max(m.square, m.round)
}

func nrgbaOf(img image.Image) *image.NRGBA {
	if n, ok := img.(*image.NRGBA); ok {
		return n
	}
	b := img.Bounds()
	n := image.NewNRGBA(b)
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			n.SetNRGBA(x, y, imgcolor.NRGBAModel.Convert(img.At(x, y)).(imgcolor.NRGBA))
		}
	}
	return n
}

// opaqueBounds is the box of every pixel drawn at all, empty when nothing is.
func opaqueBounds(img *image.NRGBA) image.Rectangle {
	b := img.Bounds()
	minX, minY, maxX, maxY := b.Max.X, b.Max.Y, b.Min.X-1, b.Min.Y-1
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			if img.NRGBAAt(x, y).A > 0 {
				minX, minY, maxX, maxY = min(minX, x), min(minY, y), max(maxX, x), max(maxY, y)
			}
		}
	}
	if maxX < minX {
		return image.Rectangle{}
	}
	return image.Rect(minX, minY, maxX+1, maxY+1)
}

func measurePlate(img *image.NRGBA) plateMeasure {
	box := opaqueBounds(img)
	cx, cy := float64(box.Min.X+box.Max.X-1)/2, float64(box.Min.Y+box.Max.Y-1)/2
	rx, ry := float64(box.Dx()-1)/2, float64(box.Dy()-1)/2
	if rx <= 0 || ry <= 0 {
		return plateMeasure{}
	}

	b := img.Bounds()
	var band []imgcolor.NRGBA
	var square, round bandFill
	buckets := map[int]*rgbSum{}
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			p := img.NRGBAAt(x, y)
			ex, ey := (float64(x)-cx)/rx, (float64(y)-cy)/ry
			r, rc := max(math.Abs(ex), math.Abs(ey)), math.Hypot(ex, ey)
			inSquare := r > plateSquareInner && r < plateSquareOuter
			inRound := rc > plateRoundInner && rc < plateRoundOuter
			opaque := p.A >= plateMinAlpha
			square.add(inSquare, opaque)
			round.add(inRound, opaque)
			if !opaque || (!inSquare && !inRound) {
				continue
			}
			band = append(band, p)
			key := int(p.R>>4)<<8 | int(p.G>>4)<<4 | int(p.B>>4)
			sum := buckets[key]
			if sum == nil {
				sum = &rgbSum{}
				buckets[key] = sum
			}
			sum.r, sum.g, sum.b, sum.n = sum.r+float64(p.R), sum.g+float64(p.G), sum.b+float64(p.B), sum.n+1
		}
	}
	m := plateMeasure{square: square.ratio(), round: round.ratio()}
	if len(band) == 0 {
		return m
	}

	// Ties go to the lowest key so a run never depends on map order.
	winnerKey, winner := -1, (*rgbSum)(nil)
	for key, sum := range buckets {
		if winner == nil || sum.n > winner.n || (sum.n == winner.n && key < winnerKey) {
			winnerKey, winner = key, sum
		}
	}
	n := float64(winner.n)
	pr, pg, pb := winner.r/n, winner.g/n, winner.b/n
	near := func(p imgcolor.NRGBA) bool {
		return math.Sqrt(sq(float64(p.R)-pr)+sq(float64(p.G)-pg)+sq(float64(p.B)-pb)) < plateNearDist
	}

	bandNear := 0
	for _, p := range band {
		if near(p) {
			bandNear++
		}
	}
	opaque, opaqueNear := 0, 0
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			p := img.NRGBAAt(x, y)
			if p.A <= 127 {
				continue
			}
			opaque++
			if near(p) {
				opaqueNear++
			}
		}
	}
	m.plate = color.NewARGB(255, uint8(math.Round(pr)), uint8(math.Round(pg)), uint8(math.Round(pb)))
	m.band = float64(bandNear) / float64(len(band))
	m.cover = float64(opaqueNear) / float64(max(opaque, 1))
	m.plated = m.fill() >= plateMinFill && m.band > plateMinBand && m.cover > plateMinCover && m.cover < plateMaxCover
	return m
}

// bandFill counts a band's pixels, transparent ones included, and how many of them are opaque.
type bandFill struct {
	total, opaque int
}

func (f *bandFill) add(in, opaque bool) {
	if !in {
		return
	}
	f.total++
	if opaque {
		f.opaque++
	}
}

func (f bandFill) ratio() float64 {
	if f.total == 0 {
		return 0
	}
	return float64(f.opaque) / float64(f.total)
}

// Reach is how far the icon's at least half opaque pixels reach from the canvas center, as a fraction
// of half its size: about 1 for a full-bleed circle, √2 for a full square, 0 when nothing is drawn.
// Each pixel counts by its far corner, so content scaled by 1/Reach never crosses the radius.
func Reach(img image.Image) float64 {
	b := img.Bounds()
	half := float64(max(b.Dx(), b.Dy())) / 2
	if half == 0 {
		return 0
	}
	cx, cy := float64(b.Min.X+b.Max.X)/2, float64(b.Min.Y+b.Max.Y)/2
	farthest := 0.0
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			if _, _, _, a := img.At(x, y).RGBA(); a>>8 < reachMinAlpha {
				continue
			}
			dx := max(math.Abs(float64(x)-cx), math.Abs(float64(x+1)-cx))
			dy := max(math.Abs(float64(y)-cy), math.Abs(float64(y+1)-cy))
			farthest = max(farthest, dx*dx+dy*dy)
		}
	}
	return math.Sqrt(farthest) / half
}

func sq(v float64) float64 {
	return v * v
}
