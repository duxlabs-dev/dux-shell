package colorpicker

import (
	"fmt"
	"math"
	"strings"
	"sync"

	"github.com/duxlabs-dev/dux-shell/core/internal/wayland/shm"
)

type PixelFormat = shm.PixelFormat

const (
	FormatARGB8888 = shm.FormatARGB8888
	FormatXRGB8888 = shm.FormatXRGB8888
	FormatABGR8888 = shm.FormatABGR8888
	FormatXBGR8888 = shm.FormatXBGR8888
	FormatRGB888   = shm.FormatRGB888
	FormatBGR888   = shm.FormatBGR888
)

type SurfaceState struct {
	mu sync.Mutex

	screenBuf    *ShmBuffer
	screenFormat PixelFormat
	pqEncoded    bool
	refLum       float64
	yInverted    bool

	logicalW int
	logicalH int

	renderBufs [2]*ShmBuffer
	front      int
	primed     [2]bool
	drawn      [2][]rect
	shown      []rect
	fullDamage bool

	scale  int32
	scaleX float64
	scaleY float64

	pointerX int
	pointerY int

	displayFormat OutputFormat
	lowercase     bool

	readyForDisplay bool
	colorPicked     bool
	cancelled       bool
}

func NewSurfaceState(format OutputFormat, lowercase bool) *SurfaceState {
	return &SurfaceState{
		scale:         1,
		displayFormat: format,
		lowercase:     lowercase,
	}
}

func (s *SurfaceState) SetPQEncoding(refLum float64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pqEncoded = true
	s.refLum = refLum
}

func (s *SurfaceState) SetScale(scale int32) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if scale <= 0 {
		scale = 1
	}
	s.scale = scale
}

func (s *SurfaceState) Scale() int32 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.scale
}

func (s *SurfaceState) LogicalSize() (int, int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.logicalW, s.logicalH
}

func (s *SurfaceState) OnScreencopyBuffer(format PixelFormat, width, height, stride int) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	bpp := format.BytesPerPixel()
	if stride < width*bpp {
		return fmt.Errorf("invalid stride %d for width %d (bpp=%d)", stride, width, bpp)
	}

	if s.screenBuf != nil {
		s.screenBuf.Close()
		s.screenBuf = nil
	}

	buf, err := CreateShmBuffer(width, height, stride)
	if err != nil {
		return err
	}

	s.screenBuf = buf
	s.screenBuf.Format = format
	s.screenFormat = format
	return nil
}

func (s *SurfaceState) ScreenBuffer() *ShmBuffer {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.screenBuf
}

func (s *SurfaceState) ScreenFormat() PixelFormat {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.screenFormat
}

func (s *SurfaceState) ReplaceScreenBuffer(newBuf *ShmBuffer) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.screenBuf != nil {
		s.screenBuf.Close()
	}
	s.screenBuf = newBuf
	s.screenFormat = newBuf.Format

	s.recomputeScale()
	s.ensureRenderBuffers()
}

func (s *SurfaceState) OnScreencopyFlags(flags uint32) {
	s.mu.Lock()
	s.yInverted = (flags & 1) != 0
	s.mu.Unlock()
}

func (s *SurfaceState) OnScreencopyReady() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.screenBuf == nil || s.logicalW == 0 || s.logicalH == 0 {
		return
	}

	if s.screenFormat.Is24Bit() {
		converted, newFormat, err := s.screenBuf.ConvertTo32Bit(s.screenFormat)
		if err == nil && converted != s.screenBuf {
			s.screenBuf.Close()
			s.screenBuf = converted
			s.screenFormat = newFormat
		}
	}

	// Magnifier rendering and pixel picking work on 8-bit pixels only
	if s.screenFormat.Is10Bit() {
		switch {
		case s.pqEncoded:
			s.screenBuf.ConvertPQ2020ToSRGB(s.refLum)
		default:
			s.screenBuf.Convert10To8()
		}
		s.screenFormat = s.screenBuf.Format
	}

	s.recomputeScale()
	s.ensureRenderBuffers()
	s.readyForDisplay = true
}

func (s *SurfaceState) OnLayerConfigure(width, height int) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if width <= 0 || height <= 0 {
		return nil
	}

	if s.logicalW == width && s.logicalH == height {
		return nil
	}

	s.logicalW = width
	s.logicalH = height

	s.recomputeScale()
	s.ensureRenderBuffers()

	return nil
}

func (s *SurfaceState) recomputeScale() {
	if s.screenBuf == nil || s.logicalW == 0 || s.logicalH == 0 {
		s.scaleX = 1
		s.scaleY = 1
		return
	}
	s.scaleX = float64(s.screenBuf.Width) / float64(s.logicalW)
	s.scaleY = float64(s.screenBuf.Height) / float64(s.logicalH)
}

func (s *SurfaceState) ensureRenderBuffers() {
	if s.screenBuf == nil {
		return
	}
	s.primed = [2]bool{}
	s.drawn = [2][]rect{}
	s.shown = nil
	s.fullDamage = true

	width := s.screenBuf.Width
	height := s.screenBuf.Height
	stride := s.screenBuf.Stride

	for i := range s.renderBufs {
		buf := s.renderBufs[i]
		if buf != nil {
			if buf.Width == width && buf.Height == height && buf.Stride == stride {
				continue
			}
			buf.Close()
			s.renderBufs[i] = nil
		}

		newBuf, err := CreateShmBuffer(width, height, stride)
		if err != nil {
			continue
		}
		s.renderBufs[i] = newBuf
	}
}

func (s *SurfaceState) OnPointerMotion(x, y float64) {
	s.mu.Lock()
	s.pointerX = int(x)
	s.pointerY = int(y)
	s.mu.Unlock()
}

func (s *SurfaceState) OnPointerButton(button, state uint32) {
	if state != 1 {
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	switch button {
	case 0x110: // BTN_LEFT
		if s.readyForDisplay && s.screenBuf != nil {
			s.colorPicked = true
		}
	}
}

func (s *SurfaceState) OnKey(sym string, state uint32) {
	if state != 1 {
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	switch sym {
	case "Escape":
		s.cancelled = true
	case "Return", "KP_Enter":
		if s.readyForDisplay && s.screenBuf != nil {
			s.colorPicked = true
		}
	}
}

func (s *SurfaceState) IsDone() (picked, cancelled bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.colorPicked, s.cancelled
}

func (s *SurfaceState) IsReady() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.readyForDisplay
}

func (s *SurfaceState) FrontRenderBuffer() *ShmBuffer {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.renderBufs[s.front]
}

func (s *SurfaceState) FrontIndex() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.front
}

func (s *SurfaceState) SwapBuffers() {
	s.mu.Lock()
	s.front ^= 1
	s.mu.Unlock()
}

// rect is a buffer-pixel area, clipped on use.
type rect struct{ x, y, w, h int }

func (r rect) clip(w, h int) rect {
	x1, y1 := max(r.x, 0), max(r.y, 0)
	x2, y2 := min(r.x+r.w, w), min(r.y+r.h, h)
	return rect{x1, y1, max(x2-x1, 0), max(y2-y1, 0)}
}

func magnifierRect(cx, cy int) rect {
	const reach = magnifierRadius + 2
	return rect{cx - reach, cy - reach, 2*reach + 1, 2*reach + 1}
}

// restore puts screen pixels back under the front buffer's previous overlay and
// records cur as its new footprint. It returns what differs from the frame on screen.
func (s *SurfaceState) restore(dst *ShmBuffer, cur []rect) []rect {
	i := s.front
	switch {
	case !s.primed[i]:
		dst.CopyFrom(s.screenBuf)
		s.primed[i] = true
	default:
		for _, r := range s.drawn[i] {
			s.copyRect(dst, r)
		}
	}
	s.drawn[i] = cur

	damage := append(append([]rect(nil), s.shown...), cur...)
	if s.fullDamage {
		s.fullDamage = false
		damage = []rect{{0, 0, dst.Width, dst.Height}}
	}
	s.shown = cur
	return damage
}

func (s *SurfaceState) copyRect(dst *ShmBuffer, r rect) {
	r = r.clip(min(dst.Width, s.screenBuf.Width), min(dst.Height, s.screenBuf.Height))
	if r.w <= 0 || r.h <= 0 {
		return
	}
	src := s.screenBuf
	for y := r.y; y < r.y+r.h; y++ {
		copy(dst.Data()[y*dst.Stride+r.x*4:][:r.w*4], src.Data()[y*src.Stride+r.x*4:][:r.w*4])
	}
}

// Redraw draws the magnifier and preview at the pointer into the front buffer,
// touching only the previous and new overlay areas; the rects are the damage.
func (s *SurfaceState) Redraw() (*ShmBuffer, []rect) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if !s.readyForDisplay || s.screenBuf == nil {
		return nil, nil
	}

	dst := s.renderBufs[s.front]
	if dst == nil {
		return nil, nil
	}

	px := int(math.Round(float64(s.pointerX) * s.scaleX))
	py := int(math.Round(float64(s.pointerY) * s.scaleY))

	px = clamp(px, 0, dst.Width-1)
	py = clamp(py, 0, dst.Height-1)

	sampleY := py
	if s.yInverted {
		sampleY = s.screenBuf.Height - 1 - py
	}

	picked := GetPixelColorWithFormat(s.screenBuf, px, sampleY, s.screenFormat)
	text := formatColorForPreview(picked, s.displayFormat, s.lowercase)
	damage := s.restore(dst, []rect{magnifierRect(px, py), previewRect(dst.Width, dst.Height, px, py, text)})

	drawMagnifierWithInversion(
		dst.Data(), dst.Stride, dst.Width, dst.Height,
		s.screenBuf.Data(), s.screenBuf.Stride, s.screenBuf.Width, s.screenBuf.Height,
		px, py, picked, s.yInverted, s.screenFormat,
	)

	drawColorPreview(dst.Data(), dst.Stride, dst.Width, dst.Height, px, py, picked, s.displayFormat, s.lowercase, s.screenFormat)

	return dst, damage
}

// RedrawScreenOnly renders just the screenshot without any overlay (magnifier, preview).
// Used for when pointer leaves the surface.
func (s *SurfaceState) RedrawScreenOnly() (*ShmBuffer, []rect) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if !s.readyForDisplay || s.screenBuf == nil {
		return nil, nil
	}

	dst := s.renderBufs[s.front]
	if dst == nil {
		return nil, nil
	}

	return dst, s.restore(dst, nil)
}

func (s *SurfaceState) PickColor() (Color, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.screenBuf == nil {
		return Color{}, false
	}

	sx := int(math.Round(float64(s.pointerX) * s.scaleX))
	sy := int(math.Round(float64(s.pointerY) * s.scaleY))

	sx = clamp(sx, 0, s.screenBuf.Width-1)
	sy = clamp(sy, 0, s.screenBuf.Height-1)

	if s.yInverted {
		sy = s.screenBuf.Height - 1 - sy
	}

	return GetPixelColorWithFormat(s.screenBuf, sx, sy, s.screenFormat), true
}

func (s *SurfaceState) Destroy() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.screenBuf != nil {
		s.screenBuf.Close()
		s.screenBuf = nil
	}

	for i := range s.renderBufs {
		if s.renderBufs[i] != nil {
			s.renderBufs[i].Close()
			s.renderBufs[i] = nil
		}
	}
}

func clamp(v, lo, hi int) int {
	switch {
	case v < lo:
		return lo
	case v > hi:
		return hi
	default:
		return v
	}
}

func clampF(v, lo, hi float64) float64 {
	switch {
	case v < lo:
		return lo
	case v > hi:
		return hi
	default:
		return v
	}
}

func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

func blendColors(bg, fg Color, alpha float64) Color {
	alpha = clampF(alpha, 0, 1)
	invAlpha := 1.0 - alpha
	return Color{
		R: uint8(clampF(float64(bg.R)*invAlpha+float64(fg.R)*alpha, 0, 255)),
		G: uint8(clampF(float64(bg.G)*invAlpha+float64(fg.G)*alpha, 0, 255)),
		B: uint8(clampF(float64(bg.B)*invAlpha+float64(fg.B)*alpha, 0, 255)),
		A: 255,
	}
}

const magnifierRadius = 80

func drawMagnifierWithInversion(
	dst []byte, dstStride, dstW, dstH int,
	src []byte, srcStride, srcW, srcH int,
	cx, cy int,
	borderColor Color,
	yInverted bool,
	format PixelFormat,
) {
	if dstW <= 0 || dstH <= 0 || srcW <= 0 || srcH <= 0 {
		return
	}

	const (
		outerRadius      = magnifierRadius
		borderThickness  = 4
		aaWidth          = 1.5
		zoom             = 8.0
		crossThickness   = 2
		crossInnerRadius = 8
	)

	innerRadius := float64(outerRadius - borderThickness)
	outerRadiusF := float64(outerRadius)

	var rOff, bOff int
	switch format {
	case FormatABGR8888, FormatXBGR8888:
		rOff, bOff = 0, 2
	default:
		rOff, bOff = 2, 0
	}

	for dy := -outerRadius - 2; dy <= outerRadius+2; dy++ {
		y := cy + dy
		if y < 0 || y >= dstH {
			continue
		}
		dstRowOff := y * dstStride

		for dx := -outerRadius - 2; dx <= outerRadius+2; dx++ {
			x := cx + dx
			if x < 0 || x >= dstW {
				continue
			}

			dist := math.Sqrt(float64(dx*dx + dy*dy))
			if dist > outerRadiusF+aaWidth {
				continue
			}

			dstOff := dstRowOff + x*4
			if dstOff+4 > len(dst) {
				continue
			}

			bgColor := Color{
				R: dst[dstOff+rOff],
				G: dst[dstOff+1],
				B: dst[dstOff+bOff],
				A: dst[dstOff+3],
			}

			var finalColor Color

			switch {
			case dist > outerRadiusF:
				alpha := clampF(1.0-(dist-outerRadiusF)/aaWidth, 0, 1)
				finalColor = blendColors(bgColor, borderColor, alpha)

			case dist > innerRadius:
				switch {
				case dist > outerRadiusF-aaWidth:
					alpha := clampF((outerRadiusF-dist)/aaWidth, 0, 1)
					finalColor = blendColors(borderColor, borderColor, alpha)
				case dist < innerRadius+aaWidth:
					alpha := clampF((dist-innerRadius)/aaWidth, 0, 1)
					fx := float64(dx) / zoom
					fy := float64(dy) / zoom
					sx := cx + int(math.Round(fx))
					sy := cy + int(math.Round(fy))
					sx = clamp(sx, 0, srcW-1)
					sy = clamp(sy, 0, srcH-1)
					if yInverted {
						sy = srcH - 1 - sy
					}
					srcOff := sy*srcStride + sx*4
					if srcOff+4 <= len(src) {
						magColor := Color{R: src[srcOff+rOff], G: src[srcOff+1], B: src[srcOff+bOff], A: 255}
						finalColor = blendColors(magColor, borderColor, alpha)
					} else {
						finalColor = borderColor
					}
				default:
					finalColor = borderColor
				}

			default:
				fx := float64(dx) / zoom
				fy := float64(dy) / zoom
				sx := cx + int(math.Round(fx))
				sy := cy + int(math.Round(fy))
				sx = clamp(sx, 0, srcW-1)
				sy = clamp(sy, 0, srcH-1)
				if yInverted {
					sy = srcH - 1 - sy
				}
				srcOff := sy*srcStride + sx*4
				if srcOff+4 <= len(src) {
					finalColor = Color{R: src[srcOff+rOff], G: src[srcOff+1], B: src[srcOff+bOff]}
				} else {
					continue
				}
			}

			dst[dstOff+rOff] = finalColor.R
			dst[dstOff+1] = finalColor.G
			dst[dstOff+bOff] = finalColor.B
			dst[dstOff+3] = 255
		}
	}

	drawMagnifierCrosshair(dst, dstStride, dstW, dstH, cx, cy, int(innerRadius), crossThickness, crossInnerRadius)
}

func drawMagnifierCrosshair(
	data []byte, stride, width, height, cx, cy, radius, thickness, innerRadius int,
) {
	if width <= 0 || height <= 0 {
		return
	}

	cx = clamp(cx, 0, width-1)
	cy = clamp(cy, 0, height-1)

	innerR2 := innerRadius * innerRadius

	for dy := -radius; dy <= radius; dy++ {
		y := cy + dy
		if y < 0 || y >= height {
			continue
		}
		rowOff := y * stride

		for dx := -radius; dx <= radius; dx++ {
			x := cx + dx
			if x < 0 || x >= width {
				continue
			}

			dist2 := dx*dx + dy*dy
			if dist2 > innerR2 {
				continue
			}

			absX := abs(dx)
			absY := abs(dy)
			if absX > thickness && absY > thickness {
				continue
			}

			off := rowOff + x*4
			if off+4 > len(data) {
				continue
			}

			isOutline := absX == thickness || absY == thickness
			if isOutline {
				data[off+0] = 0
				data[off+1] = 0
				data[off+2] = 0
				data[off+3] = 255
			} else {
				data[off+0] = 255
				data[off+1] = 255
				data[off+2] = 255
				data[off+3] = 255
			}
		}
	}
}

const (
	fontW = 8
	fontH = 12
)

var fontGlyphs = map[rune][fontH]uint8{
	'0': {
		0b00111100,
		0b01100110,
		0b01100110,
		0b01101110,
		0b01110110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00111100,
		0b00000000,
		0b00000000,
	},
	'1': {
		0b00011000,
		0b00111000,
		0b01111000,
		0b00011000,
		0b00011000,
		0b00011000,
		0b00011000,
		0b00011000,
		0b00011000,
		0b01111110,
		0b00000000,
		0b00000000,
	},
	'2': {
		0b00111100,
		0b01100110,
		0b01100110,
		0b00000110,
		0b00001100,
		0b00011000,
		0b00110000,
		0b01100000,
		0b01100110,
		0b01111110,
		0b00000000,
		0b00000000,
	},
	'3': {
		0b00111100,
		0b01100110,
		0b00000110,
		0b00000110,
		0b00011100,
		0b00000110,
		0b00000110,
		0b00000110,
		0b01100110,
		0b00111100,
		0b00000000,
		0b00000000,
	},
	'4': {
		0b00001100,
		0b00011100,
		0b00111100,
		0b01101100,
		0b11001100,
		0b11001100,
		0b11111110,
		0b00001100,
		0b00001100,
		0b00011110,
		0b00000000,
		0b00000000,
	},
	'5': {
		0b01111110,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01111100,
		0b00000110,
		0b00000110,
		0b00000110,
		0b01100110,
		0b00111100,
		0b00000000,
		0b00000000,
	},
	'6': {
		0b00011100,
		0b00110000,
		0b01100000,
		0b01100000,
		0b01111100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00111100,
		0b00000000,
		0b00000000,
	},
	'7': {
		0b01111110,
		0b01100110,
		0b00000110,
		0b00000110,
		0b00001100,
		0b00011000,
		0b00011000,
		0b00011000,
		0b00011000,
		0b00011000,
		0b00000000,
		0b00000000,
	},
	'8': {
		0b00111100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00111100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00111100,
		0b00000000,
		0b00000000,
	},
	'9': {
		0b00111100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00111110,
		0b00000110,
		0b00000110,
		0b00000110,
		0b00001100,
		0b00111000,
		0b00000000,
		0b00000000,
	},
	'A': {
		0b00011000,
		0b00111100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01111110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00000000,
		0b00000000,
	},
	'B': {
		0b01111100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01111100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01111100,
		0b00000000,
		0b00000000,
	},
	'C': {
		0b00111100,
		0b01100110,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100110,
		0b00111100,
		0b00000000,
		0b00000000,
	},
	'D': {
		0b01111000,
		0b01101100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01101100,
		0b01111000,
		0b00000000,
		0b00000000,
	},
	'E': {
		0b01111110,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01111100,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01111110,
		0b00000000,
		0b00000000,
	},
	'F': {
		0b01111110,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01111100,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b00000000,
		0b00000000,
	},
	'#': {
		0b00000000,
		0b00100100,
		0b00100100,
		0b01111110,
		0b00100100,
		0b00100100,
		0b01111110,
		0b00100100,
		0b00100100,
		0b00000000,
		0b00000000,
		0b00000000,
	},
	'G': {
		0b00111100,
		0b01100110,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01101110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00111100,
		0b00000000,
		0b00000000,
	},
	'H': {
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01111110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00000000,
		0b00000000,
	},
	'K': {
		0b01100110,
		0b01100110,
		0b01101100,
		0b01111000,
		0b01110000,
		0b01111000,
		0b01101100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00000000,
		0b00000000,
	},
	'L': {
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01100000,
		0b01111110,
		0b00000000,
		0b00000000,
	},
	'M': {
		0b01100011,
		0b01110111,
		0b01111111,
		0b01101011,
		0b01100011,
		0b01100011,
		0b01100011,
		0b01100011,
		0b01100011,
		0b01100011,
		0b00000000,
		0b00000000,
	},
	'R': {
		0b01111100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01111100,
		0b01111000,
		0b01101100,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00000000,
		0b00000000,
	},
	'S': {
		0b00111100,
		0b01100110,
		0b01100000,
		0b01100000,
		0b00111100,
		0b00000110,
		0b00000110,
		0b00000110,
		0b01100110,
		0b00111100,
		0b00000000,
		0b00000000,
	},
	'V': {
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00111100,
		0b00011000,
		0b00011000,
		0b00000000,
		0b00000000,
	},
	'Y': {
		0b01100110,
		0b01100110,
		0b01100110,
		0b01100110,
		0b00111100,
		0b00011000,
		0b00011000,
		0b00011000,
		0b00011000,
		0b00011000,
		0b00000000,
		0b00000000,
	},
	'(': {
		0b00001100,
		0b00011000,
		0b00110000,
		0b00110000,
		0b00110000,
		0b00110000,
		0b00110000,
		0b00110000,
		0b00011000,
		0b00001100,
		0b00000000,
		0b00000000,
	},
	')': {
		0b00110000,
		0b00011000,
		0b00001100,
		0b00001100,
		0b00001100,
		0b00001100,
		0b00001100,
		0b00001100,
		0b00011000,
		0b00110000,
		0b00000000,
		0b00000000,
	},
	',': {
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00011000,
		0b00011000,
		0b00110000,
		0b00000000,
		0b00000000,
	},
	'%': {
		0b01100010,
		0b01100110,
		0b00001100,
		0b00001100,
		0b00011000,
		0b00011000,
		0b00110000,
		0b00110000,
		0b01100110,
		0b01000110,
		0b00000000,
		0b00000000,
	},
	' ': {
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
	},
}

const (
	previewPaddingX = 8
	previewPaddingY = 4
	previewSpace    = 2
	previewOffset   = 88
)

// previewRect places the color label beside the magnifier, flipping to the left
// and clamping so it stays on the buffer.
func previewRect(width, height, cx, cy int, text string) rect {
	if len(text) == 0 {
		return rect{}
	}
	textW := len(text)*(fontW+previewSpace) - previewSpace
	boxW := textW + previewPaddingX*2
	boxH := fontH + previewPaddingY*2

	x := cx + previewOffset
	y := cy - boxH/2

	if x+boxW >= width {
		x = cx - boxW - previewOffset
	}
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	if y+boxH >= height {
		y = height - boxH
	}
	return rect{x, y, boxW, boxH}
}

func drawColorPreview(data []byte, stride, width, height int, cx, cy int, c Color, format OutputFormat, lowercase bool, pixelFormat PixelFormat) {
	text := formatColorForPreview(c, format, lowercase)
	if len(text) == 0 {
		return
	}

	box := previewRect(width, height, cx, cy, text)
	x, y := box.x, box.y
	drawFilledRect(data, stride, width, height, x, y, box.w, box.h, c, pixelFormat)

	lum := 0.299*float64(c.R) + 0.587*float64(c.G) + 0.114*float64(c.B)
	var fg Color
	if lum > 128 {
		fg = Color{R: 0, G: 0, B: 0, A: 255}
	} else {
		fg = Color{R: 255, G: 255, B: 255, A: 255}
	}
	drawText(data, stride, width, height, x+previewPaddingX, y+previewPaddingY, text, fg, pixelFormat)
}

func formatColorForPreview(c Color, format OutputFormat, lowercase bool) string {
	switch format {
	case FormatRGB:
		return strings.ToUpper(c.ToRGB())
	case FormatHSL:
		return strings.ToUpper(c.ToHSL())
	case FormatHSV:
		return strings.ToUpper(c.ToHSV())
	case FormatCMYK:
		return strings.ToUpper(c.ToCMYK())
	default:
		if lowercase {
			return c.ToHex(true)
		}
		return c.ToHex(false)
	}
}

func drawFilledRect(data []byte, stride, width, height, x, y, w, h int, col Color, format PixelFormat) {
	if w <= 0 || h <= 0 {
		return
	}
	xEnd := clamp(x+w, 0, width)
	yEnd := clamp(y+h, 0, height)
	x = clamp(x, 0, width)
	y = clamp(y, 0, height)

	var rOff, bOff int
	switch format {
	case FormatABGR8888, FormatXBGR8888:
		rOff, bOff = 0, 2
	default:
		rOff, bOff = 2, 0
	}

	for yy := y; yy < yEnd; yy++ {
		rowOff := yy * stride
		for xx := x; xx < xEnd; xx++ {
			off := rowOff + xx*4
			if off+4 > len(data) {
				continue
			}
			data[off+rOff] = col.R
			data[off+1] = col.G
			data[off+bOff] = col.B
			data[off+3] = 255
		}
	}
}

func drawText(data []byte, stride, width, height, x, y int, text string, col Color, format PixelFormat) {
	for i, r := range text {
		drawGlyph(data, stride, width, height, x+i*(fontW+2), y, r, col, format)
	}
}

func drawGlyph(data []byte, stride, width, height, x, y int, r rune, col Color, format PixelFormat) {
	g, ok := fontGlyphs[r]
	if !ok {
		return
	}

	var rOff, bOff int
	switch format {
	case FormatABGR8888, FormatXBGR8888:
		rOff, bOff = 0, 2
	default:
		rOff, bOff = 2, 0
	}

	for row := range fontH {
		yy := y + row
		if yy < 0 || yy >= height {
			continue
		}
		rowPattern := g[row]
		dstRowOff := yy * stride

		for colIdx := range fontW {
			if (rowPattern & (1 << (fontW - 1 - colIdx))) == 0 {
				continue
			}

			xx := x + colIdx
			if xx < 0 || xx >= width {
				continue
			}

			off := dstRowOff + xx*4
			if off+4 > len(data) {
				continue
			}

			data[off+rOff] = col.R
			data[off+1] = col.G
			data[off+bOff] = col.B
			data[off+3] = 255
		}
	}
}
