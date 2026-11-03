package screenshot

import (
	"fmt"
	"math"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"sync"
)

const (
	fontCharW = 8
	fontCharH = 12
	fontStep  = fontCharW + 1
)

func scaleFactor(scale float64) int {
	s := int(math.Round(scale))
	if s < 1 {
		return 1
	}
	return s
}

var fontGlyphs = map[rune][fontCharH]uint8{
	'0': {0x3C, 0x66, 0x66, 0x6E, 0x76, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00, 0x00},
	'1': {0x18, 0x38, 0x78, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00, 0x00},
	'2': {0x3C, 0x66, 0x66, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x66, 0x7E, 0x00, 0x00},
	'3': {0x3C, 0x66, 0x06, 0x06, 0x1C, 0x06, 0x06, 0x06, 0x66, 0x3C, 0x00, 0x00},
	'4': {0x0C, 0x1C, 0x3C, 0x6C, 0xCC, 0xCC, 0xFE, 0x0C, 0x0C, 0x1E, 0x00, 0x00},
	'5': {0x7E, 0x60, 0x60, 0x60, 0x7C, 0x06, 0x06, 0x06, 0x66, 0x3C, 0x00, 0x00},
	'6': {0x1C, 0x30, 0x60, 0x60, 0x7C, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00, 0x00},
	'7': {0x7E, 0x66, 0x06, 0x06, 0x0C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00},
	'8': {0x3C, 0x66, 0x66, 0x66, 0x3C, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00, 0x00},
	'9': {0x3C, 0x66, 0x66, 0x66, 0x3E, 0x06, 0x06, 0x06, 0x0C, 0x38, 0x00, 0x00},
	'x': {0x00, 0x00, 0x00, 0x66, 0x66, 0x3C, 0x18, 0x3C, 0x66, 0x66, 0x00, 0x00},
	'C': {0x3C, 0x66, 0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00, 0x00},
	'D': {0x7C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x7C, 0x00, 0x00},
	'E': {0x7E, 0x60, 0x60, 0x60, 0x7C, 0x60, 0x60, 0x60, 0x60, 0x7E, 0x00, 0x00},
	'P': {0x7C, 0x66, 0x66, 0x66, 0x7C, 0x60, 0x60, 0x60, 0x60, 0x60, 0x00, 0x00},
	'R': {0x7C, 0x66, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00},
	'S': {0x3C, 0x66, 0x60, 0x60, 0x3C, 0x06, 0x06, 0x06, 0x66, 0x3C, 0x00, 0x00},
	'a': {0x00, 0x00, 0x00, 0x3C, 0x06, 0x3E, 0x66, 0x66, 0x66, 0x3E, 0x00, 0x00},
	'c': {0x00, 0x00, 0x00, 0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00, 0x00},
	'd': {0x00, 0x00, 0x06, 0x06, 0x06, 0x3E, 0x66, 0x66, 0x66, 0x3E, 0x00, 0x00},
	'e': {0x00, 0x00, 0x00, 0x3C, 0x66, 0x66, 0x7E, 0x60, 0x60, 0x3C, 0x00, 0x00},
	'g': {0x00, 0x00, 0x00, 0x3E, 0x66, 0x66, 0x66, 0x3E, 0x06, 0x7C, 0x00, 0x00},
	'h': {0x00, 0x60, 0x60, 0x60, 0x7C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00},
	'i': {0x00, 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00},
	'm': {0x00, 0x00, 0x00, 0x76, 0x6B, 0x6B, 0x6B, 0x6B, 0x6B, 0x6B, 0x00, 0x00},
	'n': {0x00, 0x00, 0x00, 0x7C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00},
	'o': {0x00, 0x00, 0x00, 0x3C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00, 0x00},
	'p': {0x00, 0x00, 0x00, 0x7C, 0x66, 0x66, 0x66, 0x7C, 0x60, 0x60, 0x00, 0x00},
	'r': {0x00, 0x00, 0x00, 0x6E, 0x76, 0x60, 0x60, 0x60, 0x60, 0x60, 0x00, 0x00},
	's': {0x00, 0x00, 0x00, 0x3E, 0x60, 0x60, 0x3C, 0x06, 0x06, 0x7C, 0x00, 0x00},
	't': {0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x0E, 0x00, 0x00},
	'u': {0x00, 0x00, 0x00, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3E, 0x00, 0x00},
	'v': {0x00, 0x00, 0x00, 0x66, 0x66, 0x66, 0x3C, 0x3C, 0x18, 0x18, 0x00, 0x00},
	'w': {0x00, 0x00, 0x00, 0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00, 0x00},
	'z': {0x00, 0x00, 0x00, 0x7E, 0x0C, 0x18, 0x30, 0x60, 0x60, 0x7E, 0x00, 0x00},
	'l': {0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00},
	'+': {0x00, 0x00, 0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00},
	' ': {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
	':': {0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00},
	'/': {0x00, 0x02, 0x06, 0x0C, 0x18, 0x18, 0x30, 0x60, 0x40, 0x00, 0x00, 0x00},
	'[': {0x3C, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3C, 0x00, 0x00},
	']': {0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00, 0x00},
	'b': {0x00, 0x60, 0x60, 0x60, 0x7C, 0x66, 0x66, 0x66, 0x66, 0x7C, 0x00, 0x00},
	'f': {0x00, 0x0E, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00},
	'j': {0x00, 0x0C, 0x00, 0x1C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x4C, 0x38, 0x00},
	'k': {0x00, 0x60, 0x60, 0x60, 0x66, 0x6C, 0x78, 0x6C, 0x66, 0x66, 0x00, 0x00},
	'q': {0x00, 0x00, 0x00, 0x3E, 0x66, 0x66, 0x66, 0x3E, 0x06, 0x06, 0x00, 0x00},
	'y': {0x00, 0x00, 0x00, 0x66, 0x66, 0x66, 0x66, 0x3E, 0x06, 0x7C, 0x00, 0x00},
	'-': {0x00, 0x00, 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
}

type OverlayStyle struct {
	BackgroundR, BackgroundG, BackgroundB, BackgroundA uint8
	TextR, TextG, TextB                                uint8
	AccentR, AccentG, AccentB                          uint8
}

var DefaultOverlayStyle = OverlayStyle{
	BackgroundR: 30, BackgroundG: 30, BackgroundB: 30, BackgroundA: 220,
	TextR: 255, TextG: 255, TextB: 255,
	AccentR: 100, AccentG: 180, AccentB: 255,
}

type selectionRenderBounds struct {
	x, y, w, h  int
	labelText   string
	top, bottom bool
	left, right bool
	scaleX      float64
}

// dirtyRect is half-open in buffer pixels.
type dirtyRect struct {
	x1 int
	y1 int
	x2 int
	y2 int
}

func (d dirtyRect) empty() bool {
	return d.x2 <= d.x1 || d.y2 <= d.y1
}

func (d dirtyRect) intersect(o dirtyRect) dirtyRect {
	return dirtyRect{
		x1: max(d.x1, o.x1),
		y1: max(d.y1, o.y1),
		x2: min(d.x2, o.x2),
		y2: min(d.y2, o.y2),
	}
}

func (d dirtyRect) grow(n int) dirtyRect {
	return dirtyRect{x1: d.x1 - n, y1: d.y1 - n, x2: d.x2 + n, y2: d.y2 + n}
}

func (d dirtyRect) clampTo(w, h int) dirtyRect {
	return d.intersect(dirtyRect{0, 0, w, h})
}

// minus returns d with o cut out, as up to four strips.
func (d dirtyRect) minus(o dirtyRect) []dirtyRect {
	if d.empty() {
		return nil
	}
	i := d.intersect(o)
	if i.empty() {
		return []dirtyRect{d}
	}
	var out []dirtyRect
	for _, s := range []dirtyRect{
		{d.x1, d.y1, d.x2, i.y1},
		{d.x1, i.y2, d.x2, d.y2},
		{d.x1, i.y1, i.x1, i.y2},
		{i.x2, i.y1, d.x2, i.y2},
	} {
		if !s.empty() {
			out = append(out, s)
		}
	}
	return out
}

// overlay is what a frame draws on top of the dimmed background: the bright
// selection interior with its border ring, and the dimensions label.
type overlay struct {
	interior    dirtyRect
	label       dirtyRect
	text        string
	top         bool
	bottom      bool
	left        bool
	right       bool
	showHandles bool
	scaleX      float64
}

func (o *overlay) full() dirtyRect {
	return o.interior.grow(borderThickness - 1)
}

func (o *overlay) inner() dirtyRect {
	return o.interior.grow(-1)
}

func (o *overlay) ring() []dirtyRect {
	return o.full().minus(o.inner())
}

func handleRadius(scale float64) int {
	radius := int(math.Round(float64(resizeHandleRadius) * scale))
	if radius < 6 {
		return 6
	}
	return radius
}

func (o *overlay) handleRects() []dirtyRect {
	if !o.showHandles {
		return nil
	}
	radius := handleRadius(o.scaleX)
	var rects []dirtyRect
	in := o.interior
	if o.top && o.left {
		rects = append(rects, dirtyRect{in.x1 - radius, in.y1 - radius, in.x1 + radius + 1, in.y1 + radius + 1})
	}
	if o.top && o.right {
		rects = append(rects, dirtyRect{in.x2 - 1 - radius, in.y1 - radius, in.x2 + radius, in.y1 + radius + 1})
	}
	if o.bottom && o.left {
		rects = append(rects, dirtyRect{in.x1 - radius, in.y2 - 1 - radius, in.x1 + radius + 1, in.y2 + radius})
	}
	if o.bottom && o.right {
		rects = append(rects, dirtyRect{in.x2 - 1 - radius, in.y2 - 1 - radius, in.x2 + radius, in.y2 + radius})
	}
	return rects
}

// overlayDelta returns the areas to re-dim and to re-brighten when prev is replaced by cur; nil means no overlay.
func overlayDelta(prev, cur *overlay) (dim, bright []dirtyRect) {
	var curInterior, prevInner dirtyRect
	var curHandles []dirtyRect
	if cur != nil {
		curInterior = cur.interior
		curHandles = cur.handleRects()
	}
	if prev != nil {
		dim = append(prev.full().minus(curInterior), prev.label.minus(curInterior)...)
		if prev.showHandles && !slices.Equal(prev.handleRects(), curHandles) {
			for _, h := range prev.handleRects() {
				dim = append(dim, h.minus(curInterior)...)
			}
		}
		prevInner = prev.inner()
	}
	if cur != nil {
		bright = cur.interior.minus(prevInner)
	}
	return dim, bright
}

var dimLUT = func() (t [256]uint8) {
	for i := range t {
		t[i] = uint8(i * 3 / 5)
	}
	return t
}()

func dimRow(p []byte) {
	for i := 0; i+3 < len(p); i += 4 {
		p[i], p[i+1], p[i+2], p[i+3] = dimLUT[p[i]], dimLUT[p[i+1]], dimLUT[p[i+2]], 255
	}
}

func opaqueRow(p []byte) {
	for i := 3; i < len(p); i += 4 {
		p[i] = 255
	}
}

func parallelRows(rows int, fn func(y1, y2 int)) {
	workers := min(runtime.GOMAXPROCS(0), 8, rows)
	if workers <= 1 {
		fn(0, rows)
		return
	}
	chunk := (rows + workers - 1) / workers
	var wg sync.WaitGroup
	for y := 0; y < rows; y += chunk {
		wg.Add(1)
		go func(y1, y2 int) {
			defer wg.Done()
			fn(y1, y2)
		}(y, min(y+chunk, rows))
	}
	wg.Wait()
}

func paintDimmedFrame(dst, src *ShmBuffer) {
	dstData, srcData := dst.Data(), src.Data()
	rowLen := min(dst.Width, src.Width) * 4
	parallelRows(min(dst.Height, src.Height), func(y1, y2 int) {
		for y := y1; y < y2; y++ {
			d := dstData[y*dst.Stride:][:rowLen]
			s := srcData[y*src.Stride:][:rowLen]
			for i := 0; i+3 < rowLen; i += 4 {
				d[i], d[i+1], d[i+2], d[i+3] = dimLUT[s[i]], dimLUT[s[i+1]], dimLUT[s[i+2]], 255
			}
		}
	})
}

// paintRect copies area from the capture into dst, dimmed or bright.
func (r *RegionSelector) paintRect(os *OutputSurface, dst *ShmBuffer, area dirtyRect, dim bool) {
	src := r.getSourceBuffer(os)
	if src == nil {
		return
	}
	area = area.clampTo(min(src.Width, dst.Width), min(src.Height, dst.Height))
	if area.empty() {
		return
	}
	rowLen := (area.x2 - area.x1) * 4
	for y := area.y1; y < area.y2; y++ {
		s := src.Data()[y*src.Stride+area.x1*4:][:rowLen]
		d := dst.Data()[y*dst.Stride+area.x1*4:][:rowLen]
		copy(d, s)
		if dim {
			dimRow(d)
		} else {
			opaqueRow(d)
		}
	}
}

func (r *RegionSelector) selectionRenderBounds(os *OutputSurface) (selectionRenderBounds, bool) {
	if os == nil || os.output == nil {
		return selectionRenderBounds{}, false
	}

	if (!r.selection.hasSelection || r.selection.fromPreSelect) && r.hoveredTarget != nil {
		t := r.hoveredTarget
		srcBuf := r.getSourceBuffer(os)
		if srcBuf == nil {
			return selectionRenderBounds{}, false
		}
		outputMinX := float64(os.output.x)
		outputMinY := float64(os.output.y)
		outputMaxX := outputMinX + float64(os.logicalW)
		outputMaxY := outputMinY + float64(os.logicalH)

		minX := t.X
		minY := t.Y
		maxX := t.X + t.Width
		maxY := t.Y + t.Height

		if math.Max(minX, outputMinX) >= math.Min(maxX, outputMaxX) ||
			math.Max(minY, outputMinY) >= math.Min(maxY, outputMaxY) {
			return selectionRenderBounds{}, false
		}

		scaleX, scaleY := 1.0, 1.0
		if os.logicalW > 0 && os.logicalH > 0 {
			scaleX = float64(srcBuf.Width) / float64(os.logicalW)
			scaleY = float64(srcBuf.Height) / float64(os.logicalH)
		}
		x1 := clamp(int(math.Floor((minX-outputMinX)*scaleX)), 0, srcBuf.Width-1)
		y1 := clamp(int(math.Floor((minY-outputMinY)*scaleY)), 0, srcBuf.Height-1)
		w := int(math.Round(t.Width * scaleX))
		h := int(math.Round(t.Height * scaleY))
		x2 := clamp(x1+w-1, 0, srcBuf.Width-1)
		y2 := clamp(y1+h-1, 0, srcBuf.Height-1)
		w = x2 - x1 + 1
		h = y2 - y1 + 1

		labelText := fmt.Sprintf("[%s] %dx%d", t.DisplayName(), w, h)

		return selectionRenderBounds{
			x: x1, y: y1, w: w, h: h, labelText: labelText,
			top:    minY >= outputMinY && minY < outputMaxY,
			bottom: maxY > outputMinY && maxY <= outputMaxY,
			left:   minX >= outputMinX && minX < outputMaxX,
			right:  maxX > outputMinX && maxX <= outputMaxX,
			scaleX: scaleX,
		}, true
	}

	ext, ok := r.selectionExtent()
	if !ok || !ext.intersects(os) {
		return selectionRenderBounds{}, false
	}

	srcBuf := r.getSourceBuffer(os)
	if srcBuf == nil {
		return selectionRenderBounds{}, false
	}

	selectionMinX := math.Min(r.selection.anchorX, r.selection.currentX)
	selectionMinY := math.Min(r.selection.anchorY, r.selection.currentY)
	selectionMaxX := math.Max(r.selection.anchorX, r.selection.currentX)
	selectionMaxY := math.Max(r.selection.anchorY, r.selection.currentY)
	outputMinX := float64(os.output.x)
	outputMinY := float64(os.output.y)
	outputMaxX := outputMinX + float64(os.logicalW)
	outputMaxY := outputMinY + float64(os.logicalH)

	scaleX, scaleY := 1.0, 1.0
	if os.logicalW > 0 && os.logicalH > 0 {
		scaleX = float64(srcBuf.Width) / float64(os.logicalW)
		scaleY = float64(srcBuf.Height) / float64(os.logicalH)
	}
	x1 := clamp(int(math.Floor((selectionMinX-outputMinX)*scaleX)), 0, srcBuf.Width-1)
	y1 := clamp(int(math.Floor((selectionMinY-outputMinY)*scaleY)), 0, srcBuf.Height-1)
	x2 := clamp(int(math.Floor((selectionMaxX-outputMinX)*scaleX)), 0, srcBuf.Width-1)
	y2 := clamp(int(math.Floor((selectionMaxY-outputMinY)*scaleY)), 0, srcBuf.Height-1)
	w, h := x2-x1+1, y2-y1+1
	labelW, labelH := ext.width(), ext.height()
	if r.shiftHeld && ext.within(os) {
		w = min(w, h)
		h = w
		labelW, labelH = w, h
	}
	labelText := ""
	if os == ext.surface {
		labelText = fmt.Sprintf("%dx%d", labelW, labelH)
	}
	return selectionRenderBounds{
		x: x1, y: y1, w: w, h: h, labelText: labelText,
		top:    selectionMinY >= outputMinY && selectionMinY < outputMaxY,
		bottom: selectionMaxY > outputMinY && selectionMaxY <= outputMaxY,
		left:   selectionMinX >= outputMinX && selectionMinX < outputMaxX,
		right:  selectionMaxX > outputMinX && selectionMaxX <= outputMaxX,
		scaleX: scaleX,
	}, true
}

func (r *RegionSelector) overlayFor(os *OutputSurface, buf *ShmBuffer) *overlay {
	bounds, ok := r.selectionRenderBounds(os)
	if !ok {
		return nil
	}
	var label dirtyRect
	if bounds.labelText != "" {
		label, _ = labelRect(bounds, buf.Width, buf.Height)
	}
	return &overlay{
		interior:    dirtyRect{bounds.x, bounds.y, bounds.x + bounds.w, bounds.y + bounds.h},
		label:       label,
		text:        bounds.labelText,
		top:         bounds.top,
		bottom:      bounds.bottom,
		left:        bounds.left,
		right:       bounds.right,
		showHandles: (r.resizingHandle != handleNone || (r.ctrlHeld && !r.selection.dragging)) && r.selection.hasSelection && r.phase != phaseScroll,
		scaleX:      bounds.scaleX,
	}
}

// drawOverlay brings a buffer holding prev up to cur, touching only what changed.
func (r *RegionSelector) drawOverlay(os *OutputSurface, renderBuf *ShmBuffer, prev, cur *overlay) {
	dim, bright := overlayDelta(prev, cur)
	for _, d := range dim {
		r.paintRect(os, renderBuf, d, true)
	}
	for _, b := range bright {
		r.paintRect(os, renderBuf, b, false)
	}
	if cur == nil {
		return
	}

	data, stride, w, h := renderBuf.Data(), renderBuf.Stride, renderBuf.Width, renderBuf.Height
	in := cur.interior
	r.drawSelectionBorder(data, stride, w, h, in, cur, os.screenFormat)
	if cur.showHandles {
		r.drawCornerHandles(data, stride, w, h, in, cur, os.screenFormat)
	}
	if cur.text != "" {
		r.drawLabel(data, stride, w, h, cur, os.screenFormat)
	}
}

func (r *RegionSelector) drawSelectionBorder(data []byte, stride, bufW, bufH int, in dirtyRect, o *overlay, format uint32) {
	for i := range borderThickness {
		if o.top {
			r.drawHLine(data, stride, bufW, bufH, in.x1, in.y1-i, in.x2-in.x1, format)
		}
		if o.bottom {
			r.drawHLine(data, stride, bufW, bufH, in.x1, in.y2+i-1, in.x2-in.x1, format)
		}
		if o.left {
			r.drawVLine(data, stride, bufW, bufH, in.x1-i, in.y1, in.y2-in.y1, format)
		}
		if o.right {
			r.drawVLine(data, stride, bufW, bufH, in.x2+i-1, in.y1, in.y2-in.y1, format)
		}
	}
}

func (r *RegionSelector) drawCornerHandles(data []byte, stride, bufW, bufH int, in dirtyRect, o *overlay, format uint32) {
	radius := handleRadius(o.scaleX)
	if o.top && o.left {
		r.drawCornerHandle(data, stride, bufW, bufH, in.x1, in.y1, radius, handleTopLeft)
	}
	if o.top && o.right {
		r.drawCornerHandle(data, stride, bufW, bufH, in.x2-1, in.y1, radius, handleTopRight)
	}
	if o.bottom && o.left {
		r.drawCornerHandle(data, stride, bufW, bufH, in.x1, in.y2-1, radius, handleBottomLeft)
	}
	if o.bottom && o.right {
		r.drawCornerHandle(data, stride, bufW, bufH, in.x2-1, in.y2-1, radius, handleBottomRight)
	}
}

func (r *RegionSelector) drawCornerHandle(data []byte, stride, bufW, bufH, cx, cy, radius int, handle resizeHandle) {
	radSq := radius * radius
	for dy := -radius; dy <= radius; dy++ {
		py := cy + dy
		if py < 0 || py >= bufH {
			continue
		}
		rowOff := py * stride
		for dx := -radius; dx <= radius; dx++ {
			px := cx + dx
			if px < 0 || px >= bufW {
				continue
			}
			if dx*dx+dy*dy > radSq {
				continue
			}
			switch handle {
			case handleTopLeft:
				if dx >= 0 && dy >= 0 {
					continue
				}
			case handleTopRight:
				if dx <= 0 && dy >= 0 {
					continue
				}
			case handleBottomLeft:
				if dx >= 0 && dy <= 0 {
					continue
				}
			case handleBottomRight:
				if dx <= 0 && dy <= 0 {
					continue
				}
			}
			off := rowOff + px*4
			if off+3 < len(data) {
				data[off] = 255
				data[off+1] = 255
				data[off+2] = 255
				data[off+3] = 255
			}
		}
	}
}

// overlayDamage lists the buffer areas that differ between a frame showing prev and one showing cur.
func overlayDamage(prev, cur *overlay) []dirtyRect {
	dim, bright := overlayDelta(prev, cur)
	damage := append(dim, bright...)
	var prevHandles, curHandles []dirtyRect
	if prev != nil {
		prevHandles = prev.handleRects()
	}
	if cur != nil {
		curHandles = cur.handleRects()
	}
	if !slices.Equal(prevHandles, curHandles) {
		damage = append(damage, prevHandles...)
		damage = append(damage, curHandles...)
	}
	if cur == nil {
		return damage
	}
	return append(append(damage, cur.ring()...), cur.label)
}

func (r *RegionSelector) drawScrollOverlay(os *OutputSurface, renderBuf *ShmBuffer) {
	data := renderBuf.Data()
	stride := renderBuf.Stride
	w, h := renderBuf.Width, renderBuf.Height

	// 40% premultiplied scrim
	for y := range h {
		off := y * stride
		for x := range w {
			i := off + x*4
			if i+3 >= len(data) {
				continue
			}
			data[i+0], data[i+1], data[i+2], data[i+3] = 0, 0, 0, 102
		}
	}

	s := r.scroll
	if s == nil || r.selection.surface != os {
		return
	}

	// hole oversized 2px so overlay pixels never land in captured frames
	holeX := s.holeX - 2
	holeY := s.holeY - 2
	holeW := s.holeW + 4
	holeH := s.holeH + 4

	x1 := clamp(holeX, 0, w)
	y1 := clamp(holeY, 0, h)
	x2 := clamp(holeX+holeW, 0, w)
	y2 := clamp(holeY+holeH, 0, h)

	for y := y1; y < y2; y++ {
		off := y * stride
		for x := x1; x < x2; x++ {
			i := off + x*4
			if i+3 >= len(data) {
				continue
			}
			data[i+0], data[i+1], data[i+2], data[i+3] = 0, 0, 0, 0
		}
	}

	r.drawBorder(data, stride, w, h, holeX-1, holeY-1, holeW+2, holeH+2, os.screenFormat)
	r.drawScrollBar(data, stride, w, h, os.screenFormat)
	r.drawScrollPreview(data, stride, w, h, os)
}

func (r *RegionSelector) drawScrollPreview(data []byte, stride, bufW, bufH int, os *OutputSurface) {
	s := r.scroll
	if s == nil || s.st == nil || s.st.rows() == 0 || !s.hasPreview {
		return
	}

	canvas := s.st.canvas
	sourceW := s.frameW
	sourceRows := s.st.rows()
	if sourceW <= 0 || sourceRows <= 0 || len(canvas) < sourceW*sourceRows*4 {
		return
	}

	scale := 1.0
	if os.logicalW > 0 {
		scale = float64(bufW) / float64(os.logicalW)
	}
	if scale <= 0 {
		scale = 1.0
	}
	padding := int(float64(scrollPreviewPaddingLogical) * scale)

	format := os.screenFormat
	// 1. Draw translucent dark panel background
	r.fillRect(data, stride, bufW, bufH, s.previewX, s.previewY, s.previewW, s.previewH, 16, 16, 16, 230, format)

	// 2. Draw downscaled stitched canvas
	imageX := s.previewX + padding
	imageY := s.previewY + padding
	imageW := s.previewW - padding*2
	imageH := s.previewH - padding*2
	if imageW <= 0 || imageH <= 0 {
		return
	}

	needSwap := formatIsBGR(uint32(s.format)) != formatIsBGR(format)

	startRow := s.previewStartRow
	previewRows := s.previewRows
	if previewRows <= 0 || startRow < 0 || startRow+previewRows > sourceRows {
		startRow = 0
		previewRows = sourceRows
	}

	for y := range imageH {
		srcY := startRow + y*previewRows/imageH
		if srcY >= sourceRows {
			srcY = sourceRows - 1
		}
		dstY := imageY + y
		if dstY < 0 || dstY >= bufH {
			continue
		}
		dstRowOff := dstY * stride
		srcRowOff := srcY * sourceW * 4

		for x := range imageW {
			srcX := x * sourceW / imageW
			dstX := imageX + x
			if dstX < 0 || dstX >= bufW {
				continue
			}
			srcIdx := srcRowOff + srcX*4
			dstIdx := dstRowOff + dstX*4
			if srcIdx+3 >= len(canvas) || dstIdx+3 >= len(data) {
				continue
			}

			if needSwap {
				data[dstIdx+0] = canvas[srcIdx+2]
				data[dstIdx+1] = canvas[srcIdx+1]
				data[dstIdx+2] = canvas[srcIdx+0]
			} else {
				data[dstIdx+0] = canvas[srcIdx+0]
				data[dstIdx+1] = canvas[srcIdx+1]
				data[dstIdx+2] = canvas[srcIdx+2]
			}
			data[dstIdx+3] = 255
		}
	}

	// 3. Draw border around preview panel
	borderW := max(int(scale+0.5), 1)
	for i := range borderW {
		r.drawHLine(data, stride, bufW, bufH, s.previewX-i, s.previewY-i, s.previewW+2*i, format)
		r.drawHLine(data, stride, bufW, bufH, s.previewX-i, s.previewY+s.previewH+i-1, s.previewW+2*i, format)
		r.drawVLine(data, stride, bufW, bufH, s.previewX-i, s.previewY-i, s.previewH+2*i, format)
		r.drawVLine(data, stride, bufW, bufH, s.previewX+s.previewW+i-1, s.previewY-i, s.previewH+2*i, format)
	}
}

func (r *RegionSelector) drawScrollBar(data []byte, stride, bufW, bufH int, format uint32) {
	s := r.scroll
	style := LoadOverlayStyle()

	r.fillRect(data, stride, bufW, bufH, s.barX, s.barY, s.barW, s.barH,
		style.BackgroundR, style.BackgroundG, style.BackgroundB, 245, format)

	labelY := s.doneY + (s.btnH-fontCharH)/2
	r.fillRect(data, stride, bufW, bufH, s.doneX, s.doneY, s.doneW, s.btnH,
		style.AccentR, style.AccentG, style.AccentB, 255, format)
	r.drawText(data, stride, bufW, bufH, s.doneX+12, labelY, "done", 10, 10, 10, format)

	r.fillRect(data, stride, bufW, bufH, s.cancelX, s.cancelY, s.cancelW, s.btnH,
		70, 70, 70, 255, format)
	r.drawText(data, stride, bufW, bufH, s.cancelX+12, labelY, "cancel",
		style.TextR, style.TextG, style.TextB, format)

	rows := 0
	if s.st != nil {
		rows = s.st.rows()
	}
	counter := fmt.Sprintf("%d shots %dpx", s.kept, rows)
	r.drawText(data, stride, bufW, bufH, s.cancelX+s.cancelW+16, labelY, counter,
		style.TextR, style.TextG, style.TextB, format)
}

const (
	minHUDScale = 1
	maxHUDScale = 4
)

func (r *RegionSelector) hudScale(effectiveScale float64) int {
	hudOpt := "auto"
	if r.screenshoter != nil && r.screenshoter.config.HUD != "" {
		hudOpt = strings.ToLower(strings.TrimSpace(r.screenshoter.config.HUD))
	}
	switch hudOpt {
	case "off", "none", "false", "0":
		return 0
	case "", "auto":
		return min(scaleFactor(effectiveScale), maxHUDScale)
	default:
		if val, err := strconv.ParseFloat(hudOpt, 64); err == nil {
			if val <= 0 {
				return 0
			}
			return min(max(scaleFactor(val), minHUDScale), maxHUDScale)
		}
		return min(scaleFactor(effectiveScale), maxHUDScale)
	}
}

type hudItem struct {
	key, desc string
}

func (h hudItem) width(step int) int {
	return (len(h.key) + 1 + len(h.desc)) * step
}

func (r *RegionSelector) hudItems() []hudItem {
	cursorLabel := "hide"
	if !r.showCapturedCursor {
		cursorLabel = "show"
	}
	captureKey := "Space/Enter"
	if r.screenshoter != nil && r.screenshoter.config.NoConfirm {
		captureKey = "Drag+Release"
	}

	return []hudItem{
		{captureKey, "capture"},
		{"Ctrl+C", "copy"},
		{"Ctrl", "resize/move"},
		{"P", cursorLabel + " cursor"},
		{"Esc", "cancel"},
	}
}

func (r *RegionSelector) hudDimensions(bufW, bufH, scale int) (hudX, hudY, hudW, hudH int) {
	if scale <= 0 {
		return 0, 0, 0, 0
	}
	scale = scaleFactor(float64(scale))
	charH := fontCharH * scale
	padding, itemSpacing := 12*scale, 24*scale
	margin := 20 * scale

	items := r.hudItems()
	totalW := 0
	step := fontStep * scale
	for i, item := range items {
		totalW += item.width(step)
		if i < len(items)-1 {
			totalW += itemSpacing
		}
	}

	hudW = totalW + padding*2
	hudH = charH + padding*2
	hudX = (bufW - hudW) / 2
	hudY = bufH - hudH - margin
	return hudX, hudY, hudW, hudH
}

func (r *RegionSelector) drawHUD(data []byte, stride, bufW, bufH int, format uint32, scale int) {
	if r.selection.dragging || scale <= 0 {
		return
	}

	scale = scaleFactor(float64(scale))
	hudX, hudY, hudW, hudH := r.hudDimensions(bufW, bufH, scale)
	style := LoadOverlayStyle()
	r.fillRect(data, stride, bufW, bufH, hudX, hudY, hudW, hudH,
		style.BackgroundR, style.BackgroundG, style.BackgroundB, style.BackgroundA, format)

	padding, itemSpacing := 12*scale, 24*scale
	step := fontStep * scale
	items := r.hudItems()

	tx, ty := hudX+padding, hudY+padding
	for i, item := range items {
		r.drawTextScaled(data, stride, bufW, bufH, tx, ty, item.key,
			style.AccentR, style.AccentG, style.AccentB, format, scale)
		r.drawTextScaled(data, stride, bufW, bufH, tx+len(item.key)*step, ty, " "+item.desc,
			style.TextR, style.TextG, style.TextB, format, scale)
		tx += item.width(step)

		if i < len(items)-1 {
			tx += itemSpacing
		}
	}
}

const borderThickness = 2

func (r *RegionSelector) drawBorder(data []byte, stride, bufW, bufH, x, y, w, h int, format uint32) {
	for i := range borderThickness {
		r.drawHLine(data, stride, bufW, bufH, x-i, y-i, w+2*i, format)
		r.drawHLine(data, stride, bufW, bufH, x-i, y+h+i-1, w+2*i, format)
		r.drawVLine(data, stride, bufW, bufH, x-i, y-i, h+2*i, format)
		r.drawVLine(data, stride, bufW, bufH, x+w+i-1, y-i, h+2*i, format)
	}
}

func (r *RegionSelector) drawHLine(data []byte, stride, bufW, bufH, x, y, length int, _ uint32) {
	if y < 0 || y >= bufH {
		return
	}
	rowOff := y * stride
	for i := range length {
		px := x + i
		if px < 0 || px >= bufW {
			continue
		}
		off := rowOff + px*4
		if off+3 >= len(data) {
			continue
		}
		data[off], data[off+1], data[off+2], data[off+3] = 255, 255, 255, 255
	}
}

func (r *RegionSelector) drawVLine(data []byte, stride, bufW, bufH, x, y, length int, _ uint32) {
	if x < 0 || x >= bufW {
		return
	}
	for i := range length {
		py := y + i
		if py < 0 || py >= bufH {
			continue
		}
		off := py*stride + x*4
		if off+3 >= len(data) {
			continue
		}
		data[off], data[off+1], data[off+2], data[off+3] = 255, 255, 255, 255
	}
}

func labelRect(b selectionRenderBounds, bufW, bufH int) (dirtyRect, string) {
	scale := scaleFactor(b.scaleX)
	text := b.labelText
	charH := fontCharH * scale
	step := fontStep * scale
	textW := len(text) * step
	padX := 4 * scale
	padY := 2 * scale
	offsetY := 8 * scale

	tx := b.x + (b.w-textW)/2
	ty := b.y + b.h + offsetY
	if ty+charH > bufH {
		ty = b.y - charH - offsetY
	}
	tx = clamp(tx, 0, bufW-textW)
	return dirtyRect{x1: tx - padX, y1: ty - padY, x2: tx + textW + padX, y2: ty + charH + padY}, text
}

func (r *RegionSelector) drawLabel(data []byte, stride, bufW, bufH int, o *overlay, format uint32) {
	scale := scaleFactor(o.scaleX)
	l := o.label
	r.fillRect(data, stride, bufW, bufH, l.x1, l.y1, l.x2-l.x1, l.y2-l.y1, 0, 0, 0, 200, format)
	r.drawTextScaled(data, stride, bufW, bufH, l.x1+4*scale, l.y1+2*scale, o.text, 255, 255, 255, format, scale)
}

func formatIsBGR(format uint32) bool {
	return format == uint32(FormatABGR8888) || format == uint32(FormatXBGR8888)
}

func (r *RegionSelector) fillRect(data []byte, stride, bufW, bufH, x, y, w, h int, cr, cg, cb, ca uint8, format uint32) {
	alpha := float64(ca) / 255.0
	invAlpha := 1.0 - alpha

	c0, c2 := cb, cr
	if formatIsBGR(format) {
		c0, c2 = cr, cb
	}

	for py := y; py < y+h && py < bufH; py++ {
		if py < 0 {
			continue
		}
		for px := x; px < x+w && px < bufW; px++ {
			if px < 0 {
				continue
			}
			off := py*stride + px*4
			if off+3 >= len(data) {
				continue
			}
			data[off+0] = uint8(float64(data[off+0])*invAlpha + float64(c0)*alpha)
			data[off+1] = uint8(float64(data[off+1])*invAlpha + float64(cg)*alpha)
			data[off+2] = uint8(float64(data[off+2])*invAlpha + float64(c2)*alpha)
			data[off+3] = 255
		}
	}
}

func (r *RegionSelector) drawText(data []byte, stride, bufW, bufH, x, y int, text string, cr, cg, cb uint8, format uint32) {
	r.drawTextScaled(data, stride, bufW, bufH, x, y, text, cr, cg, cb, format, 1)
}

func (r *RegionSelector) drawTextScaled(data []byte, stride, bufW, bufH, x, y int, text string, cr, cg, cb uint8, format uint32, scale int) {
	scale = scaleFactor(float64(scale))
	step := fontStep * scale
	for i, ch := range text {
		r.drawChar(data, stride, bufW, bufH, x+i*step, y, ch, cr, cg, cb, format, scale)
	}
}

func (r *RegionSelector) drawChar(data []byte, stride, bufW, bufH, x, y int, ch rune, cr, cg, cb uint8, format uint32, scale int) {
	glyph, ok := fontGlyphs[ch]
	if !ok {
		return
	}

	scale = scaleFactor(float64(scale))

	c0, c2 := cb, cr
	if formatIsBGR(format) {
		c0, c2 = cr, cb
	}

	for row := range fontCharH {
		bits := glyph[row]
		for dy := range scale {
			py := y + row*scale + dy
			if py < 0 || py >= bufH {
				continue
			}
			rowOff := py * stride
			for col := range fontCharW {
				if (bits & (1 << (7 - col))) == 0 {
					continue
				}
				baseX := x + col*scale
				for dx := range scale {
					px := baseX + dx
					if px < 0 || px >= bufW {
						continue
					}
					off := rowOff + px*4
					if off+3 >= len(data) {
						continue
					}
					data[off], data[off+1], data[off+2], data[off+3] = c0, cg, c2, 255
				}
			}
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
