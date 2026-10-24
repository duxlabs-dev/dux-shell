package screenshot

import (
	"fmt"
	"math"
	"sync"

	"github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_screencopy"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wp_color_management"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	wlhelpers "github.com/duxlabs-dev/dux-shell/core/internal/wayland/client"
)

type WaylandOutput struct {
	wlOutput        *client.Output
	globalName      uint32
	name            string
	x, y            int32
	width           int32
	height          int32
	scale           int32
	fractionalScale float64
	transform       int32
}

type CaptureResult struct {
	Buffer    *ShmBuffer
	Region    Region
	YInverted bool
	Format    uint32
	Scale     float64
	CICP      *CICP
	CopyOnly  bool
	OCROnly   bool
}

func (o *WaylandOutput) effectiveScale() float64 {
	scale := o.fractionalScale
	if scale <= 0 && DetectCompositor() == CompositorHyprland {
		scale = GetHyprlandMonitorScale(o.name)
	}
	if scale <= 0 {
		scale = float64(o.scale)
	}
	if scale <= 0 {
		return 1.0
	}
	return scale
}

func (o *WaylandOutput) bounds() Region {
	x, y, w, h := o.x, o.y, o.width, o.height
	if DetectCompositor() == CompositorHyprland {
		if hx, hy, hw, hh, ok := GetHyprlandMonitorGeometry(o.name); ok {
			return Region{X: hx, Y: hy, Width: hw, Height: hh, Output: o.name}
		}
	}
	if o.transform == 1 || o.transform == 3 || o.transform == 5 || o.transform == 7 {
		w, h = h, w
	}
	if scale := o.effectiveScale(); scale > 0 {
		w = int32(math.Round(float64(w) / scale))
		h = int32(math.Round(float64(h) / scale))
	}
	return Region{
		X:      x,
		Y:      y,
		Width:  w,
		Height: h,
		Output: o.name,
	}
}

func geometryResult(region Region) *CaptureResult {
	return &CaptureResult{Region: region}
}

type Screenshoter struct {
	config Config

	display  *client.Display
	registry *client.Registry
	ctx      *client.Context

	compositor *client.Compositor
	shm        *client.Shm
	screencopy *wlr_screencopy.ZwlrScreencopyManagerV1
	colorMgr   *wp_color_management.WpColorManagerV1

	outputs   map[uint32]*WaylandOutput
	outputsMu sync.Mutex
}

func New(config Config) *Screenshoter {
	return &Screenshoter{
		config:  config,
		outputs: make(map[uint32]*WaylandOutput),
	}
}

func (s *Screenshoter) Run() (*CaptureResult, error) {
	if err := s.connect(); err != nil {
		return nil, fmt.Errorf("wayland connect: %w", err)
	}
	defer s.cleanup()

	if err := s.setupRegistry(); err != nil {
		return nil, fmt.Errorf("registry setup: %w", err)
	}

	if err := s.roundtrip(); err != nil {
		return nil, fmt.Errorf("roundtrip: %w", err)
	}

	if s.screencopy == nil {
		return nil, fmt.Errorf("compositor does not support wlr-screencopy-unstable-v1")
	}

	if err := s.roundtrip(); err != nil {
		return nil, fmt.Errorf("roundtrip: %w", err)
	}

	switch s.config.Mode {
	case ModeLastRegion:
		return s.captureLastRegion()
	case ModeRegion, ModeScroll:
		return s.captureRegion()
	case ModeWindow:
		return s.captureWindow()
	case ModeOutput:
		return s.captureOutput(s.config.OutputName)
	case ModeFullScreen:
		return s.captureFullScreen()
	case ModeAllScreens:
		return s.captureAllScreens()
	default:
		return s.captureRegion()
	}
}

func (s *Screenshoter) captureLastRegion() (*CaptureResult, error) {
	lastRegion := GetLastRegion()
	if lastRegion.IsEmpty() {
		return s.captureRegion()
	}

	var output *WaylandOutput
	if lastRegion.Output != "" {
		output = s.findOutputByName(lastRegion.Output)
	}
	if output == nil {
		output = s.findOutputForRegion(lastRegion)
	}
	if output == nil {
		return s.captureRegion()
	}

	if s.config.Geometry {
		scale := output.effectiveScale()
		if scale <= 0 {
			scale = 1.0
		}
		localX := float64(lastRegion.X-output.x) / scale
		localY := float64(lastRegion.Y-output.y) / scale
		logicalW := float64(lastRegion.Width) / scale
		logicalH := float64(lastRegion.Height) / scale
		return geometryResult(Region{
			X:      int32(math.Round(float64(output.x) + localX)),
			Y:      int32(math.Round(float64(output.y) + localY)),
			Width:  int32(math.Round(logicalW)),
			Height: int32(math.Round(logicalH)),
			Output: output.name,
		}), nil
	}

	return s.captureRegionOnOutput(output, lastRegion)
}

func (s *Screenshoter) captureRegion() (*CaptureResult, error) {
	if !s.config.AllowMultiple {
		lock, err := utils.LockSelectionOverlay()
		if err != nil {
			return nil, err
		}
		defer lock.Release()
	}

	if s.config.Reset {
		if err := SaveLastRegion(Region{}); err != nil {
			log.Debug("failed to reset last region", "err", err)
		}
	}

	if hook := s.config.SelectorHook; hook != nil {
		started := make(chan struct{})
		go func() {
			hook(true)
			close(started)
		}()
		defer func() {
			<-started
			hook(false)
		}()
	}

	PrefetchOverlayStyle()
	selector := NewRegionSelector(s)
	result, cancelled, err := selector.Run()
	if err != nil {
		return nil, fmt.Errorf("region selection: %w", err)
	}
	if cancelled || result == nil {
		return nil, nil
	}

	if !s.config.Geometry && result.Region.Output != "" {
		if err := SaveLastRegion(result.Region); err != nil {
			log.Debug("failed to save last region", "err", err)
		}
	}

	if out := s.findOutputByName(result.Region.Output); out != nil {
		result.CICP = s.outputCICP(out)
	}

	return result, nil
}

func (s *Screenshoter) captureWindow() (*CaptureResult, error) {
	if DetectCompositor() == CompositorAqueous {
		return s.captureAqueousWindow()
	}
	if DetectCompositor() == CompositorNiri {
		if s.config.Geometry {
			return nil, fmt.Errorf("window geometry mode is not supported on niri")
		}
		return s.captureNiriWindow()
	}

	geom, err := GetActiveWindow()
	if err != nil {
		return nil, err
	}

	region := Region{
		X:      geom.X,
		Y:      geom.Y,
		Width:  geom.Width,
		Height: geom.Height,
	}

	if s.config.Geometry {
		return geometryResult(region), nil
	}

	var output *WaylandOutput
	if geom.Output != "" {
		output = s.findOutputByName(geom.Output)
	}
	if output == nil {
		output = s.findOutputForRegion(region)
	}
	if output == nil {
		return nil, fmt.Errorf("could not find output for window")
	}

	switch DetectCompositor() {
	case CompositorHyprland:
		return s.captureAndCrop(output, region)
	case CompositorMango:
		return s.captureMangoWindow(output, region, geom)
	default:
		return s.captureRegionOnOutput(output, region)
	}
}

func (s *Screenshoter) captureMangoWindow(output *WaylandOutput, region Region, geom *WindowGeometry) (*CaptureResult, error) {
	result, err := s.captureWholeOutput(output)
	if err != nil {
		return nil, err
	}

	scale := geom.Scale
	if scale <= 0 || scale == 1.0 {
		if output.fractionalScale > 1.0 {
			scale = output.fractionalScale
		}
	}
	if scale <= 0 {
		scale = 1.0
	}

	localX := int(float64(region.X-geom.OutputX) * scale)
	localY := int(float64(region.Y-geom.OutputY) * scale)
	w := int(float64(region.Width) * scale)
	h := int(float64(region.Height) * scale)

	if localX < 0 {
		w += localX
		localX = 0
	}
	if localY < 0 {
		h += localY
		localY = 0
	}
	if localX+w > result.Buffer.Width {
		w = result.Buffer.Width - localX
	}
	if localY+h > result.Buffer.Height {
		h = result.Buffer.Height - localY
	}

	if w <= 0 || h <= 0 {
		result.Buffer.Close()
		return nil, fmt.Errorf("window not visible on output")
	}

	cropped, err := CreateShmBuffer(w, h, w*4)
	if err != nil {
		result.Buffer.Close()
		return nil, fmt.Errorf("create crop buffer: %w", err)
	}

	srcData := result.Buffer.Data()
	dstData := cropped.Data()

	for y := 0; y < h; y++ {
		srcY := localY + y
		if result.YInverted {
			srcY = result.Buffer.Height - 1 - (localY + y)
		}
		if srcY < 0 || srcY >= result.Buffer.Height {
			continue
		}

		dstY := y
		if result.YInverted {
			dstY = h - 1 - y
		}

		for x := 0; x < w; x++ {
			srcX := localX + x
			if srcX < 0 || srcX >= result.Buffer.Width {
				continue
			}

			si := srcY*result.Buffer.Stride + srcX*4
			di := dstY*cropped.Stride + x*4

			if si+3 >= len(srcData) || di+3 >= len(dstData) {
				continue
			}

			dstData[di+0] = srcData[si+0]
			dstData[di+1] = srcData[si+1]
			dstData[di+2] = srcData[si+2]
			dstData[di+3] = srcData[si+3]
		}
	}

	result.Buffer.Close()
	cropped.Format = PixelFormat(result.Format)

	return &CaptureResult{
		Buffer:    cropped,
		Region:    region,
		YInverted: false,
		Format:    result.Format,
		Scale:     scale,
		CICP:      result.CICP,
	}, nil
}

func (s *Screenshoter) captureFullScreen() (*CaptureResult, error) {
	if DetectCompositor() == CompositorAqueous {
		name, err := aqueousFocusedOutput(s.config.Seat)
		if err != nil {
			return nil, err
		}
		return s.captureOutput(name)
	}
	output := s.findFocusedOutput()
	if output == nil {
		s.outputsMu.Lock()
		for _, o := range s.outputs {
			output = o
			break
		}
		s.outputsMu.Unlock()
	}

	if output == nil {
		return nil, fmt.Errorf("no output available")
	}

	if s.config.Geometry {
		return geometryResult(output.bounds()), nil
	}

	return s.captureWholeOutput(output)
}

func (s *Screenshoter) captureOutput(name string) (*CaptureResult, error) {
	s.outputsMu.Lock()
	var output *WaylandOutput
	for _, o := range s.outputs {
		if o.name == name {
			output = o
			break
		}
	}
	s.outputsMu.Unlock()

	if output == nil {
		return nil, fmt.Errorf("output %q not found", name)
	}

	if s.config.Geometry {
		return geometryResult(output.bounds()), nil
	}

	return s.captureWholeOutput(output)
}

func (s *Screenshoter) captureAllScreens() (*CaptureResult, error) {
	s.outputsMu.Lock()
	outputs := make([]*WaylandOutput, 0, len(s.outputs))
	for _, o := range s.outputs {
		outputs = append(outputs, o)
	}
	s.outputsMu.Unlock()

	if len(outputs) == 0 {
		return nil, fmt.Errorf("no outputs available")
	}

	if s.config.Geometry {
		minX, minY := math.MaxInt32, math.MaxInt32
		maxX, maxY := math.MinInt32, math.MinInt32
		for _, o := range outputs {
			b := o.bounds()
			if int(b.X) < minX {
				minX = int(b.X)
			}
			if int(b.Y) < minY {
				minY = int(b.Y)
			}
			if int(b.X+b.Width) > maxX {
				maxX = int(b.X + b.Width)
			}
			if int(b.Y+b.Height) > maxY {
				maxY = int(b.Y + b.Height)
			}
		}
		return geometryResult(Region{
			X:      int32(minX),
			Y:      int32(minY),
			Width:  int32(maxX - minX),
			Height: int32(maxY - minY),
		}), nil
	}

	if len(outputs) == 1 {
		return s.captureWholeOutput(outputs[0])
	}

	wlrInfos := getAllOutputInfos()

	type pendingOutput struct {
		result *CaptureResult
		logX   float64
		logY   float64
		scale  float64
	}
	var pending []pendingOutput
	maxScale := 1.0

	for _, output := range outputs {
		result, err := s.captureWholeOutput(output)
		if err != nil {
			log.Warn("failed to capture output", "name", output.name, "err", err)
			continue
		}

		logX, logY := float64(output.x), float64(output.y)
		scale := float64(output.scale)

		switch DetectCompositor() {
		case CompositorHyprland:
			if hx, hy, _, _, ok := GetHyprlandMonitorGeometry(output.name); ok {
				logX, logY = float64(hx), float64(hy)
			}
			if hs := GetHyprlandMonitorScale(output.name); hs > 0 {
				scale = hs
			}
		default:
			if wlrInfos != nil {
				if info, ok := wlrInfos[output.name]; ok {
					logX, logY = float64(info.x), float64(info.y)
					if info.scale > 0 {
						scale = info.scale
					}
				}
			}
		}

		if scale <= 0 {
			scale = 1.0
		}

		pending = append(pending, pendingOutput{result: result, logX: logX, logY: logY, scale: scale})
		if scale > maxScale {
			maxScale = scale
		}
	}

	if len(pending) == 0 {
		return nil, fmt.Errorf("failed to capture any outputs")
	}
	if len(pending) == 1 {
		return pending[0].result, nil
	}

	type layoutEntry struct {
		result  *CaptureResult
		canvasX int
		canvasY int
		canvasW int
		canvasH int
	}
	entries := make([]layoutEntry, len(pending))
	var minX, minY, maxX, maxY int

	for i, p := range pending {
		cx := int(math.Round(p.logX * maxScale))
		cy := int(math.Round(p.logY * maxScale))
		cw := int(math.Round(float64(p.result.Buffer.Width) * maxScale / p.scale))
		ch := int(math.Round(float64(p.result.Buffer.Height) * maxScale / p.scale))

		entries[i] = layoutEntry{result: p.result, canvasX: cx, canvasY: cy, canvasW: cw, canvasH: ch}

		right := cx + cw
		bottom := cy + ch
		if i == 0 {
			minX, minY, maxX, maxY = cx, cy, right, bottom
			continue
		}
		if cx < minX {
			minX = cx
		}
		if cy < minY {
			minY = cy
		}
		if right > maxX {
			maxX = right
		}
		if bottom > maxY {
			maxY = bottom
		}
	}

	totalW := maxX - minX
	totalH := maxY - minY
	composite, err := CreateShmBuffer(totalW, totalH, totalW*4)
	if err != nil {
		for _, e := range entries {
			e.result.Buffer.Close()
		}
		return nil, fmt.Errorf("create composite buffer: %w", err)
	}
	composite.Clear()

	var format uint32
	cicp := entries[0].result.CICP
	for _, e := range entries {
		// Outputs may mix 8-bit and 10-bit; composite in 8-bit
		if PixelFormat(e.result.Format).Is10Bit() {
			e.result.Buffer.Convert10To8()
			e.result.Format = uint32(e.result.Buffer.Format)
		}
		if format == 0 {
			format = e.result.Format
		}
		if cicp != nil && (e.result.CICP == nil || *e.result.CICP != *cicp) {
			cicp = nil
		}
		s.blitBufferScaled(composite, e.result.Buffer,
			e.canvasX-minX, e.canvasY-minY, e.canvasW, e.canvasH,
			e.result.YInverted)
		e.result.Buffer.Close()
	}

	return &CaptureResult{
		Buffer: composite,
		Region: Region{X: int32(minX), Y: int32(minY), Width: int32(totalW), Height: int32(totalH)},
		Format: format,
		Scale:  maxScale,
		CICP:   cicp,
	}, nil
}

func (s *Screenshoter) blitBufferScaled(dst, src *ShmBuffer, dstX, dstY, dstW, dstH int, yInverted bool) {
	if dstW <= 0 || dstH <= 0 {
		return
	}

	srcData := src.Data()
	dstData := dst.Data()

	for dy := range dstH {
		canvasY := dstY + dy
		if canvasY < 0 || canvasY >= dst.Height {
			continue
		}

		srcY := dy * src.Height / dstH
		if yInverted {
			srcY = src.Height - 1 - srcY
		}
		if srcY < 0 || srcY >= src.Height {
			continue
		}

		srcRowOff := srcY * src.Stride
		dstRowOff := canvasY * dst.Stride

		for dx := range dstW {
			canvasX := dstX + dx
			if canvasX < 0 || canvasX >= dst.Width {
				continue
			}

			srcX := dx * src.Width / dstW
			if srcX >= src.Width {
				continue
			}

			si := srcRowOff + srcX*4
			di := dstRowOff + canvasX*4

			if si+3 >= len(srcData) || di+3 >= len(dstData) {
				continue
			}

			dstData[di+0] = srcData[si+0]
			dstData[di+1] = srcData[si+1]
			dstData[di+2] = srcData[si+2]
			dstData[di+3] = srcData[si+3]
		}
	}
}

func (s *Screenshoter) captureWholeOutput(output *WaylandOutput) (*CaptureResult, error) {
	cursor := int32(s.config.Cursor)

	frame, err := s.screencopy.CaptureOutput(cursor, output.wlOutput)
	if err != nil {
		return nil, fmt.Errorf("capture output: %w", err)
	}

	result, err := s.processFrame(frame, Region{
		X:      output.x,
		Y:      output.y,
		Width:  output.width,
		Height: output.height,
		Output: output.name,
	})
	if err != nil {
		return nil, err
	}
	result.Scale = output.effectiveScale()
	result.CICP = s.outputCICP(output)

	if result.YInverted {
		result.Buffer.FlipVertical()
		result.YInverted = false
	}

	if output.transform == TransformNormal {
		return result, nil
	}

	invTransform := InverseTransform(output.transform)
	transformed, err := result.Buffer.ApplyTransform(invTransform)
	if err != nil {
		result.Buffer.Close()
		return nil, fmt.Errorf("apply transform: %w", err)
	}

	if transformed != result.Buffer {
		result.Buffer.Close()
		result.Buffer = transformed
	}

	result.Region.Width = int32(transformed.Width)
	result.Region.Height = int32(transformed.Height)

	return result, nil
}

func (s *Screenshoter) captureAndCrop(output *WaylandOutput, region Region) (*CaptureResult, error) {
	result, err := s.captureWholeOutput(output)
	if err != nil {
		return nil, err
	}

	outX, outY := output.x, output.y
	scale := float64(output.scale)
	if DetectCompositor() == CompositorHyprland {
		if hx, hy, _, _, ok := GetHyprlandMonitorGeometry(output.name); ok {
			outX, outY = hx, hy
		}
		if s := GetHyprlandMonitorScale(output.name); s > 0 {
			scale = s
		}
	}
	if scale <= 0 {
		scale = 1.0
	}

	localX := int(float64(region.X-outX) * scale)
	localY := int(float64(region.Y-outY) * scale)
	w := int(float64(region.Width) * scale)
	h := int(float64(region.Height) * scale)

	cropped, err := CreateShmBuffer(w, h, w*4)
	if err != nil {
		result.Buffer.Close()
		return nil, fmt.Errorf("create crop buffer: %w", err)
	}

	srcData := result.Buffer.Data()
	dstData := cropped.Data()

	for y := range h {
		srcY := localY + y
		if result.YInverted {
			srcY = result.Buffer.Height - 1 - (localY + y)
		}
		if srcY < 0 || srcY >= result.Buffer.Height {
			continue
		}

		dstY := y
		if result.YInverted {
			dstY = h - 1 - y
		}

		for x := range w {
			srcX := localX + x
			if srcX < 0 || srcX >= result.Buffer.Width {
				continue
			}

			si := srcY*result.Buffer.Stride + srcX*4
			di := dstY*cropped.Stride + x*4

			if si+3 >= len(srcData) || di+3 >= len(dstData) {
				continue
			}

			dstData[di+0] = srcData[si+0]
			dstData[di+1] = srcData[si+1]
			dstData[di+2] = srcData[si+2]
			dstData[di+3] = srcData[si+3]
		}
	}

	result.Buffer.Close()
	cropped.Format = PixelFormat(result.Format)

	return &CaptureResult{
		Buffer:    cropped,
		Region:    region,
		YInverted: false,
		Format:    result.Format,
		Scale:     scale,
		CICP:      result.CICP,
	}, nil
}

func (s *Screenshoter) captureRegionOnOutput(output *WaylandOutput, region Region) (*CaptureResult, error) {
	if output.transform != TransformNormal {
		return s.captureRegionOnTransformedOutput(output, region)
	}

	scale := output.effectiveScale()

	localX := int32(float64(region.X-output.x) * scale)
	localY := int32(float64(region.Y-output.y) * scale)
	w := int32(float64(region.Width) * scale)
	h := int32(float64(region.Height) * scale)

	if DetectCompositor() == CompositorMango {
		scaledOutW := int32(float64(output.width) * scale)
		scaledOutH := int32(float64(output.height) * scale)
		if localX >= scaledOutW {
			localX = localX % scaledOutW
		}
		if localY >= scaledOutH {
			localY = localY % scaledOutH
		}
		if localX+w > scaledOutW {
			w = scaledOutW - localX
		}
		if localY+h > scaledOutH {
			h = scaledOutH - localY
		}
		if localX < 0 {
			w += localX
			localX = 0
		}
		if localY < 0 {
			h += localY
			localY = 0
		}
	}

	cursor := int32(s.config.Cursor)

	frame, err := s.screencopy.CaptureOutputRegion(cursor, output.wlOutput, localX, localY, w, h)
	if err != nil {
		return nil, fmt.Errorf("capture region: %w", err)
	}

	result, err := s.processFrame(frame, region)
	if err != nil {
		return nil, err
	}
	result.Scale = scale
	result.CICP = s.outputCICP(output)
	return result, nil
}

func (s *Screenshoter) captureRegionOnTransformedOutput(output *WaylandOutput, region Region) (*CaptureResult, error) {
	result, err := s.captureWholeOutput(output)
	if err != nil {
		return nil, err
	}

	scale := output.effectiveScale()

	localX := int(float64(region.X-output.x) * scale)
	localY := int(float64(region.Y-output.y) * scale)
	w := int(float64(region.Width) * scale)
	h := int(float64(region.Height) * scale)

	if localX < 0 {
		w += localX
		localX = 0
	}
	if localY < 0 {
		h += localY
		localY = 0
	}
	if localX+w > result.Buffer.Width {
		w = result.Buffer.Width - localX
	}
	if localY+h > result.Buffer.Height {
		h = result.Buffer.Height - localY
	}

	if w <= 0 || h <= 0 {
		result.Buffer.Close()
		return nil, fmt.Errorf("region not visible on output")
	}

	cropped, err := CreateShmBuffer(w, h, w*4)
	if err != nil {
		result.Buffer.Close()
		return nil, fmt.Errorf("create crop buffer: %w", err)
	}

	srcData := result.Buffer.Data()
	dstData := cropped.Data()

	for y := 0; y < h; y++ {
		srcOff := (localY+y)*result.Buffer.Stride + localX*4
		dstOff := y * cropped.Stride
		if srcOff+w*4 <= len(srcData) && dstOff+w*4 <= len(dstData) {
			copy(dstData[dstOff:dstOff+w*4], srcData[srcOff:srcOff+w*4])
		}
	}

	result.Buffer.Close()
	cropped.Format = PixelFormat(result.Format)

	return &CaptureResult{
		Buffer:    cropped,
		Region:    region,
		YInverted: false,
		Format:    result.Format,
		Scale:     scale,
		CICP:      result.CICP,
	}, nil
}

func (s *Screenshoter) processFrame(frame *wlr_screencopy.ZwlrScreencopyFrameV1, region Region) (*CaptureResult, error) {
	var buf *ShmBuffer
	var pool *client.ShmPool
	var wlBuf *client.Buffer
	var format PixelFormat
	var yInverted bool
	ready := false
	failed := false

	frame.SetBufferHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1BufferEvent) {
		format = PixelFormat(e.Format)
		bpp := format.BytesPerPixel()
		if int(e.Stride) < int(e.Width)*bpp {
			log.Error("invalid stride from compositor", "stride", e.Stride, "width", e.Width, "bpp", bpp)
			// bail out here or the dispatch loop waits forever on a ready/failed
			// event that never comes (frame.Copy is never called)
			failed = true
			return
		}
		var err error
		buf, err = CreateShmBuffer(int(e.Width), int(e.Height), int(e.Stride))
		if err != nil {
			log.Error("failed to create buffer", "err", err)
			failed = true
			return
		}
		buf.Format = format
	})

	frame.SetFlagsHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1FlagsEvent) {
		yInverted = (e.Flags & 1) != 0
	})

	frame.SetBufferDoneHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1BufferDoneEvent) {
		if buf == nil {
			return
		}

		var err error
		pool, err = s.shm.CreatePool(buf.Fd(), int32(buf.Size()))
		if err != nil {
			log.Error("failed to create pool", "err", err)
			failed = true
			return
		}

		wlBuf, err = pool.CreateBuffer(0, int32(buf.Width), int32(buf.Height), int32(buf.Stride), uint32(format))
		if err != nil {
			pool.Destroy()
			pool = nil
			log.Error("failed to create wl_buffer", "err", err)
			failed = true
			return
		}

		if err := frame.Copy(wlBuf); err != nil {
			log.Error("failed to copy frame", "err", err)
		}
	})

	frame.SetReadyHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1ReadyEvent) {
		ready = true
	})

	frame.SetFailedHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1FailedEvent) {
		failed = true
	})

	for !ready && !failed {
		if err := s.ctx.Dispatch(); err != nil {
			frame.Destroy()
			return nil, fmt.Errorf("dispatch: %w", err)
		}
	}

	frame.Destroy()
	if wlBuf != nil {
		wlBuf.Destroy()
	}
	if pool != nil {
		pool.Destroy()
	}

	if failed {
		if buf != nil {
			buf.Close()
		}
		return nil, fmt.Errorf("frame capture failed")
	}

	if format.Is24Bit() {
		converted, newFormat, err := buf.ConvertTo32Bit(format)
		if err != nil {
			buf.Close()
			return nil, fmt.Errorf("convert 24-bit to 32-bit: %w", err)
		}
		if converted != buf {
			buf.Close()
			buf = converted
		}
		format = newFormat
	}

	return &CaptureResult{
		Buffer:    buf,
		Region:    region,
		YInverted: yInverted,
		Format:    uint32(format),
	}, nil
}

func (s *Screenshoter) findOutputByName(name string) *WaylandOutput {
	s.outputsMu.Lock()
	defer s.outputsMu.Unlock()
	for _, o := range s.outputs {
		if o.name == name {
			return o
		}
	}
	return nil
}

func (s *Screenshoter) findOutputForRegion(region Region) *WaylandOutput {
	s.outputsMu.Lock()
	defer s.outputsMu.Unlock()

	cx := region.X + region.Width/2
	cy := region.Y + region.Height/2

	for _, o := range s.outputs {
		b := o.bounds()
		if cx >= b.X && cx < b.X+b.Width && cy >= b.Y && cy < b.Y+b.Height {
			return o
		}
	}

	for _, o := range s.outputs {
		b := o.bounds()
		if region.X >= b.X && region.X < b.X+b.Width &&
			region.Y >= b.Y && region.Y < b.Y+b.Height {
			return o
		}
	}

	return nil
}

func (s *Screenshoter) findFocusedOutput() *WaylandOutput {
	if mon := GetFocusedMonitor(); mon != "" {
		s.outputsMu.Lock()
		defer s.outputsMu.Unlock()
		for _, o := range s.outputs {
			if o.name == mon {
				return o
			}
		}
	}
	s.outputsMu.Lock()
	defer s.outputsMu.Unlock()
	for _, o := range s.outputs {
		return o
	}
	return nil
}

func (s *Screenshoter) connect() error {
	display, err := client.Connect("")
	if err != nil {
		return err
	}
	s.display = display
	s.ctx = display.Context()
	return nil
}

func (s *Screenshoter) roundtrip() error {
	return wlhelpers.Roundtrip(s.display, s.ctx)
}

func (s *Screenshoter) setupRegistry() error {
	registry, err := s.display.GetRegistry()
	if err != nil {
		return err
	}
	s.registry = registry

	registry.SetGlobalHandler(func(e client.RegistryGlobalEvent) {
		s.handleGlobal(e)
	})

	registry.SetGlobalRemoveHandler(func(e client.RegistryGlobalRemoveEvent) {
		s.outputsMu.Lock()
		delete(s.outputs, e.Name)
		s.outputsMu.Unlock()
	})

	return nil
}

func (s *Screenshoter) handleGlobal(e client.RegistryGlobalEvent) {
	switch e.Interface {
	case client.CompositorInterfaceName:
		comp := client.NewCompositor(s.ctx)
		if err := s.registry.Bind(e.Name, e.Interface, e.Version, comp); err == nil {
			s.compositor = comp
		}

	case client.ShmInterfaceName:
		shm := client.NewShm(s.ctx)
		if err := s.registry.Bind(e.Name, e.Interface, e.Version, shm); err == nil {
			s.shm = shm
		}

	case client.OutputInterfaceName:
		output := client.NewOutput(s.ctx)
		version := min(e.Version, 4)
		if err := s.registry.Bind(e.Name, e.Interface, version, output); err == nil {
			s.outputsMu.Lock()
			s.outputs[e.Name] = &WaylandOutput{
				wlOutput:        output,
				globalName:      e.Name,
				scale:           1,
				fractionalScale: 1.0,
			}
			s.outputsMu.Unlock()
			s.setupOutputHandlers(e.Name, output)
		}

	case wlr_screencopy.ZwlrScreencopyManagerV1InterfaceName:
		sc := wlr_screencopy.NewZwlrScreencopyManagerV1(s.ctx)
		version := min(e.Version, 3)
		if err := s.registry.Bind(e.Name, e.Interface, version, sc); err == nil {
			s.screencopy = sc
		}

	case wp_color_management.WpColorManagerV1InterfaceName:
		mgr := wp_color_management.NewWpColorManagerV1(s.ctx)
		if err := s.registry.Bind(e.Name, e.Interface, 1, mgr); err == nil {
			s.colorMgr = mgr
		}
	}
}

func (s *Screenshoter) setupOutputHandlers(name uint32, output *client.Output) {
	output.SetGeometryHandler(func(e client.OutputGeometryEvent) {
		s.outputsMu.Lock()
		if o, ok := s.outputs[name]; ok {
			o.x, o.y = e.X, e.Y
			o.transform = int32(e.Transform)
		}
		s.outputsMu.Unlock()
	})

	output.SetModeHandler(func(e client.OutputModeEvent) {
		if e.Flags&uint32(client.OutputModeCurrent) == 0 {
			return
		}
		s.outputsMu.Lock()
		if o, ok := s.outputs[name]; ok {
			o.width, o.height = e.Width, e.Height
		}
		s.outputsMu.Unlock()
	})

	output.SetScaleHandler(func(e client.OutputScaleEvent) {
		s.outputsMu.Lock()
		if o, ok := s.outputs[name]; ok {
			o.scale = e.Factor
			o.fractionalScale = float64(e.Factor)
		}
		s.outputsMu.Unlock()
	})

	output.SetNameHandler(func(e client.OutputNameEvent) {
		s.outputsMu.Lock()
		if o, ok := s.outputs[name]; ok {
			o.name = e.Name
		}
		s.outputsMu.Unlock()
	})
}

func (s *Screenshoter) cleanup() {
	if s.colorMgr != nil {
		s.colorMgr.Destroy()
	}
	if s.screencopy != nil {
		s.screencopy.Destroy()
	}
	if s.display != nil {
		s.ctx.Close()
	}
}

func (s *Screenshoter) GetOutputs() []*WaylandOutput {
	s.outputsMu.Lock()
	defer s.outputsMu.Unlock()
	out := make([]*WaylandOutput, 0, len(s.outputs))
	for _, o := range s.outputs {
		out = append(out, o)
	}
	return out
}

func ListOutputs() ([]Output, error) {
	sc := New(DefaultConfig())
	if err := sc.connect(); err != nil {
		return nil, err
	}
	defer sc.cleanup()

	if err := sc.setupRegistry(); err != nil {
		return nil, err
	}
	if err := sc.roundtrip(); err != nil {
		return nil, err
	}
	if err := sc.roundtrip(); err != nil {
		return nil, err
	}

	sc.outputsMu.Lock()
	defer sc.outputsMu.Unlock()

	compositor := DetectCompositor()
	result := make([]Output, 0, len(sc.outputs))
	for _, o := range sc.outputs {
		out := Output{
			Name:            o.name,
			X:               o.x,
			Y:               o.y,
			Width:           o.width,
			Height:          o.height,
			Scale:           o.scale,
			FractionalScale: o.fractionalScale,
			Transform:       o.transform,
		}

		switch compositor {
		case CompositorHyprland:
			if hx, hy, hw, hh, ok := GetHyprlandMonitorGeometry(o.name); ok {
				out.X, out.Y = hx, hy
				out.Width, out.Height = hw, hh
			}
			if s := GetHyprlandMonitorScale(o.name); s > 0 {
				out.FractionalScale = s
			}
		}

		result = append(result, out)
	}
	return result, nil
}
