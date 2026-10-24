package screenshot

import (
	"fmt"
	"math"
	"sync"

	"github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/keyboard_shortcuts_inhibit"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_layer_shell"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_screencopy"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wp_cursor_shape"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wp_viewporter"
	wlhelpers "github.com/duxlabs-dev/dux-shell/core/internal/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/wayland/keymap"
)

type resizeHandle int

const (
	handleNone resizeHandle = iota
	handleTopLeft
	handleTopRight
	handleBottomLeft
	handleBottomRight
)

const (
	resizeHandleRadius = 12
	resizeHitRadius    = resizeHandleRadius + 4
)

type SelectionState struct {
	hasSelection  bool           // There's a selection to display (pre-loaded or user-drawn)
	fromPreSelect bool           // hasSelection was set by applyPreSelection, not by user interaction
	dragging      bool           // User is actively drawing a new selection
	surface       *OutputSurface // Surface where selection was made
	// Global logical coordinates. Keeping these independent of the active
	// surface lets a drag continue across output boundaries.
	anchorX  float64
	anchorY  float64
	currentX float64
	currentY float64
}

type RenderSlot struct {
	shm                   *ShmBuffer
	pool                  *client.ShmPool
	wlBuf                 *client.Buffer
	busy                  bool
	backgroundInitialized bool
	backgroundSource      *ShmBuffer
	backgroundDragging    bool
	backgroundCursor      bool
	backgroundPhase       selectorPhase
	backgroundHandles     bool
	backgroundShift       bool
	overlay               *overlay
}

func (s *RenderSlot) cacheValid(src *ShmBuffer, dragging, cursor bool, phase selectorPhase, handles, shift bool) bool {
	return s.backgroundInitialized &&
		s.backgroundSource == src &&
		s.backgroundDragging == dragging &&
		s.backgroundCursor == cursor &&
		s.backgroundPhase == phase &&
		s.backgroundHandles == handles &&
		s.backgroundShift == shift
}

type OutputSurface struct {
	output            *WaylandOutput
	wlSurface         *client.Surface
	layerSurf         *wlr_layer_shell.ZwlrLayerSurfaceV1
	viewport          *wp_viewporter.WpViewport
	screenBuf         *ShmBuffer
	screenBufNoCursor *ShmBuffer
	screenFormat      uint32
	logicalW          int
	logicalH          int
	configured        bool
	yInverted         bool

	// Triple-buffered render slots
	slots        [3]*RenderSlot
	slotsReady   bool
	slotFormat   uint32
	slotPrefault sync.WaitGroup
	captured     bool

	shown           *overlay
	framePending    bool
	redrawQueued    bool
	committedCursor bool
}

type PreCapture struct {
	screenBuf         *ShmBuffer
	screenBufNoCursor *ShmBuffer
	format            uint32
	yInverted         bool
	width             int
	height            int
	stride            int
}

type RegionSelector struct {
	screenshoter *Screenshoter

	display  *client.Display
	registry *client.Registry
	ctx      *client.Context

	compositor *client.Compositor
	shm        *client.Shm
	seat       *client.Seat
	pointer    *client.Pointer
	touch      *client.Touch
	keyboard   *client.Keyboard
	keymap     *keymap.Keymap
	layerShell *wlr_layer_shell.ZwlrLayerShellV1
	screencopy *wlr_screencopy.ZwlrScreencopyManagerV1
	viewporter *wp_viewporter.WpViewporter

	compositorVersion uint32

	shortcutsInhibitMgr *keyboard_shortcuts_inhibit.ZwpKeyboardShortcutsInhibitManagerV1
	shortcutsInhibitor  *keyboard_shortcuts_inhibit.ZwpKeyboardShortcutsInhibitorV1

	outputs    map[uint32]*WaylandOutput
	outputsMu  sync.Mutex
	preCapture map[*WaylandOutput]*PreCapture

	surfaces      []*OutputSurface
	activeSurface *OutputSurface

	// Cursor surface fallback when the compositor lacks cursor shapes.
	cursorSurface *client.Surface
	cursorBuffer  *ShmBuffer
	cursorSerial  uint32
	cursorShape   *wp_cursor_shape.WpCursorShapeManagerV1
	cursorDevice  *wp_cursor_shape.WpCursorShapeDeviceV1
	cursorWlBuf   *client.Buffer
	cursorPool    *client.ShmPool

	selection          SelectionState
	pointerX           float64
	pointerY           float64
	hasTouchPoint      bool
	touchPointId       int32
	preSelect          Region
	showCapturedCursor bool
	shiftHeld          bool
	ctrlHeld           bool
	altHeld            bool
	movingSelection    bool
	moveOffsetX        float64
	moveOffsetY        float64
	resizingHandle     resizeHandle

	phase  selectorPhase
	scroll *scrollSession

	snapTargets   []SnapTarget
	hoveredTarget *SnapTarget
	clickedTarget *SnapTarget
	dragStartX    float64
	dragStartY    float64

	running   bool
	cancelled bool
	copyOnly  bool
	ocrOnly   bool
	result    Region

	capturedBuffer *ShmBuffer
	capturedRegion Region
}

func NewRegionSelector(s *Screenshoter) *RegionSelector {
	return &RegionSelector{
		screenshoter:       s,
		outputs:            make(map[uint32]*WaylandOutput),
		preCapture:         make(map[*WaylandOutput]*PreCapture),
		showCapturedCursor: s.config.Cursor == CursorOn,
		snapTargets:        s.config.SnapTargets,
	}
}

func (r *RegionSelector) Run() (*CaptureResult, bool, error) {
	if r.screenshoter != nil && r.screenshoter.config.Reset {
		r.preSelect = Region{}
	} else {
		r.preSelect = GetLastRegion()
	}

	if err := r.connect(); err != nil {
		return nil, false, fmt.Errorf("wayland connect: %w", err)
	}
	defer r.cleanup()

	if err := r.setupRegistry(); err != nil {
		return nil, false, fmt.Errorf("registry setup: %w", err)
	}

	if err := r.roundtrip(); err != nil {
		return nil, false, fmt.Errorf("roundtrip after registry: %w", err)
	}

	switch {
	case r.screencopy == nil:
		return nil, false, fmt.Errorf("compositor does not support wlr-screencopy-unstable-v1")
	case r.layerShell == nil:
		return nil, false, fmt.Errorf("compositor does not support wlr-layer-shell-unstable-v1")
	case r.seat == nil:
		return nil, false, fmt.Errorf("no seat available")
	case r.compositor == nil:
		return nil, false, fmt.Errorf("compositor not available")
	case r.shm == nil:
		return nil, false, fmt.Errorf("wl_shm not available")
	case len(r.outputs) == 0:
		return nil, false, fmt.Errorf("no outputs available")
	}

	if err := r.roundtrip(); err != nil {
		return nil, false, fmt.Errorf("roundtrip after protocol check: %w", err)
	}

	// unmapped until their first buffer, so the configure round trip overlaps the captures
	if err := r.createSurfaces(); err != nil {
		return nil, false, fmt.Errorf("create surfaces: %w", err)
	}

	_ = r.createCursor()

	if err := r.roundtrip(); err != nil {
		return nil, false, fmt.Errorf("roundtrip after surfaces: %w", err)
	}

	if err := r.preCaptureAllOutputs(); err != nil {
		return nil, false, fmt.Errorf("pre-capture: %w", err)
	}

	for _, os := range r.surfaces {
		if os.configured && !os.captured {
			r.captureForSurface(os)
		}
	}

	r.running = true
	for r.running {
		if err := r.dispatchOrTick(); err != nil {
			return nil, false, fmt.Errorf("dispatch: %w", err)
		}
	}

	if r.scroll != nil && r.scroll.abortErr != nil {
		return nil, false, r.scroll.abortErr
	}

	if r.cancelled {
		return nil, true, nil
	}

	if r.screenshoter != nil && r.screenshoter.config.Geometry {
		reg, ok := r.selectedLogicalGeometry()
		if !ok {
			return nil, true, nil
		}
		return geometryResult(reg), false, nil
	}

	if r.capturedBuffer == nil {
		return nil, r.cancelled, nil
	}

	yInverted := false
	var format uint32
	scale := 1.0
	if r.selection.surface != nil {
		yInverted = r.selection.surface.yInverted
		format = r.selection.surface.screenFormat
		if s := r.selection.surface.output.fractionalScale; s > 0 {
			scale = s
		}
	}
	if r.scroll != nil {
		yInverted = false
		format = uint32(r.scroll.format)
	}

	return &CaptureResult{
		Buffer:    r.capturedBuffer,
		Region:    r.result,
		YInverted: yInverted,
		Format:    format,
		Scale:     scale,
		CopyOnly:  r.copyOnly,
		OCROnly:   r.ocrOnly,
	}, false, nil
}

func (r *RegionSelector) selectedLogicalGeometry() (Region, bool) {
	ext, ok := r.selectionExtent()
	if !ok || ext.width() <= 0 || ext.height() <= 0 {
		return Region{}, false
	}

	x1, y1, x2, y2 := ext.logical()
	lx := int(math.Round(x1))
	ly := int(math.Round(y1))
	lw := int(math.Round(x2 - x1))
	lh := int(math.Round(y2 - y1))

	if r.shiftHeld && ext.within(ext.surface) {
		size := min(lw, lh)
		lw = size
		lh = size
	}

	if lw <= 0 || lh <= 0 {
		return Region{}, false
	}

	outputName := ""
	if ext.within(ext.surface) && ext.surface.output != nil {
		outputName = ext.surface.output.name
	}

	return Region{
		X:      int32(lx),
		Y:      int32(ly),
		Width:  int32(lw),
		Height: int32(lh),
		Output: outputName,
	}, true
}

func (r *RegionSelector) connect() error {
	display, err := client.Connect("")
	if err != nil {
		return err
	}
	r.display = display
	r.ctx = display.Context()
	return nil
}

func (r *RegionSelector) roundtrip() error {
	return wlhelpers.Roundtrip(r.display, r.ctx)
}

func (r *RegionSelector) setupRegistry() error {
	registry, err := r.display.GetRegistry()
	if err != nil {
		return err
	}
	r.registry = registry

	registry.SetGlobalHandler(func(e client.RegistryGlobalEvent) {
		r.handleGlobal(e)
	})

	registry.SetGlobalRemoveHandler(func(e client.RegistryGlobalRemoveEvent) {
		r.outputsMu.Lock()
		delete(r.outputs, e.Name)
		r.outputsMu.Unlock()
	})

	return nil
}

func (r *RegionSelector) handleGlobal(e client.RegistryGlobalEvent) {
	switch e.Interface {
	case client.CompositorInterfaceName:
		comp := client.NewCompositor(r.ctx)
		if err := r.registry.Bind(e.Name, e.Interface, e.Version, comp); err == nil {
			r.compositor = comp
			r.compositorVersion = e.Version
		}

	case client.ShmInterfaceName:
		shm := client.NewShm(r.ctx)
		if err := r.registry.Bind(e.Name, e.Interface, e.Version, shm); err == nil {
			r.shm = shm
		}

	case client.SeatInterfaceName:
		seat := client.NewSeat(r.ctx)
		if err := r.registry.Bind(e.Name, e.Interface, e.Version, seat); err == nil {
			r.seat = seat
			r.setupInput()
		}

	case client.OutputInterfaceName:
		output := client.NewOutput(r.ctx)
		version := min(e.Version, 4)
		if err := r.registry.Bind(e.Name, e.Interface, version, output); err == nil {
			r.outputsMu.Lock()
			r.outputs[e.Name] = &WaylandOutput{
				wlOutput:        output,
				globalName:      e.Name,
				scale:           1,
				fractionalScale: 1.0,
			}
			r.outputsMu.Unlock()
			r.setupOutputHandlers(e.Name, output)
		}

	case wlr_layer_shell.ZwlrLayerShellV1InterfaceName:
		ls := wlr_layer_shell.NewZwlrLayerShellV1(r.ctx)
		version := min(e.Version, 4)
		if err := r.registry.Bind(e.Name, e.Interface, version, ls); err == nil {
			r.layerShell = ls
		}

	case wlr_screencopy.ZwlrScreencopyManagerV1InterfaceName:
		sc := wlr_screencopy.NewZwlrScreencopyManagerV1(r.ctx)
		version := min(e.Version, 3)
		if err := r.registry.Bind(e.Name, e.Interface, version, sc); err == nil {
			r.screencopy = sc
		}

	case wp_viewporter.WpViewporterInterfaceName:
		vp := wp_viewporter.NewWpViewporter(r.ctx)
		if err := r.registry.Bind(e.Name, e.Interface, e.Version, vp); err == nil {
			r.viewporter = vp
		}

	case keyboard_shortcuts_inhibit.ZwpKeyboardShortcutsInhibitManagerV1InterfaceName:
		mgr := keyboard_shortcuts_inhibit.NewZwpKeyboardShortcutsInhibitManagerV1(r.ctx)
		if err := r.registry.Bind(e.Name, e.Interface, e.Version, mgr); err == nil {
			r.shortcutsInhibitMgr = mgr
		}

	case wp_cursor_shape.WpCursorShapeManagerV1InterfaceName:
		mgr := wp_cursor_shape.NewWpCursorShapeManagerV1(r.ctx)
		if err := r.registry.Bind(e.Name, e.Interface, 1, mgr); err == nil {
			r.cursorShape = mgr
		}
	}
}

func (r *RegionSelector) setupOutputHandlers(name uint32, output *client.Output) {
	output.SetGeometryHandler(func(e client.OutputGeometryEvent) {
		r.outputsMu.Lock()
		if o, ok := r.outputs[name]; ok {
			o.x = e.X
			o.y = e.Y
			o.transform = int32(e.Transform)
		}
		r.outputsMu.Unlock()
	})

	output.SetModeHandler(func(e client.OutputModeEvent) {
		if e.Flags&uint32(client.OutputModeCurrent) == 0 {
			return
		}
		r.outputsMu.Lock()
		if o, ok := r.outputs[name]; ok {
			o.width = e.Width
			o.height = e.Height
		}
		r.outputsMu.Unlock()
	})

	output.SetScaleHandler(func(e client.OutputScaleEvent) {
		r.outputsMu.Lock()
		if o, ok := r.outputs[name]; ok {
			o.scale = e.Factor
			o.fractionalScale = float64(e.Factor)
		}
		r.outputsMu.Unlock()
	})

	output.SetNameHandler(func(e client.OutputNameEvent) {
		r.outputsMu.Lock()
		if o, ok := r.outputs[name]; ok {
			o.name = e.Name
		}
		r.outputsMu.Unlock()
	})
}

func (r *RegionSelector) preCaptureAllOutputs() error {
	r.outputsMu.Lock()
	outputs := make([]*WaylandOutput, 0, len(r.outputs))
	for _, o := range r.outputs {
		outputs = append(outputs, o)
	}
	r.outputsMu.Unlock()

	pending := len(outputs) * 2
	done := make(chan struct{}, pending)

	for _, output := range outputs {
		pc := &PreCapture{}
		r.preCapture[output] = pc

		r.preCaptureOutput(output, pc, true, func() { done <- struct{}{} })
		r.preCaptureOutput(output, pc, false, func() { done <- struct{}{} })
	}

	for i := 0; i < pending; i++ {
		if err := r.ctx.Dispatch(); err != nil {
			return err
		}
		select {
		case <-done:
		default:
			i--
		}
	}
	return nil
}

func (r *RegionSelector) preCaptureOutput(output *WaylandOutput, pc *PreCapture, withCursor bool, onReady func()) {
	cursor := int32(0)
	if withCursor {
		cursor = 1
	}

	frame, err := r.screencopy.CaptureOutput(cursor, output.wlOutput)
	if err != nil {
		log.Error("screencopy capture failed", "err", err)
		onReady()
		return
	}

	var capturedBuf *ShmBuffer

	var capturedFormat PixelFormat
	frame.SetBufferHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1BufferEvent) {
		capturedFormat = PixelFormat(e.Format)
		bpp := capturedFormat.BytesPerPixel()
		if int(e.Stride) < int(e.Width)*bpp {
			log.Error("invalid stride from compositor", "stride", e.Stride, "width", e.Width, "bpp", bpp)
			return
		}
		if pc.width == 0 {
			pc.width, pc.height, pc.stride = int(e.Width), int(e.Height), int(e.Stride)
			pc.format = uint32(capturedFormat.To8Bit())
			if bpp == 4 && output.transform == TransformNormal {
				r.prepareSlots(output, pc)
			}
		}
		buf, err := CreateShmBuffer(int(e.Width), int(e.Height), int(e.Stride))
		if err != nil {
			log.Error("create screen buffer failed", "err", err)
			return
		}

		capturedBuf = buf
		buf.Format = capturedFormat

		pool, err := r.shm.CreatePool(buf.Fd(), int32(buf.Size()))
		if err != nil {
			log.Error("create shm pool failed", "err", err)
			return
		}

		wlBuf, err := pool.CreateBuffer(0, int32(buf.Width), int32(buf.Height), int32(buf.Stride), e.Format)
		if err != nil {
			log.Error("create wl_buffer failed", "err", err)
			pool.Destroy()
			return
		}

		if err := frame.Copy(wlBuf); err != nil {
			log.Error("frame copy failed", "err", err)
		}
		pool.Destroy()
	})

	frame.SetFlagsHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1FlagsEvent) {
		if withCursor {
			pc.yInverted = (e.Flags & 1) != 0
		}
	})

	frame.SetReadyHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1ReadyEvent) {
		frame.Destroy()

		if capturedBuf == nil {
			onReady()
			return
		}

		if capturedFormat.Is24Bit() {
			converted, newFormat, err := capturedBuf.ConvertTo32Bit(capturedFormat)
			if err != nil {
				log.Error("convert 24-bit to 32-bit failed", "err", err)
			} else if converted != capturedBuf {
				capturedBuf.Close()
				capturedBuf = converted
				capturedFormat = newFormat
			}
		}

		// Overlay rendering and crop work on 8-bit pixels only
		if capturedFormat.Is10Bit() {
			capturedBuf.Convert10To8()
			capturedFormat = capturedBuf.Format
		}

		pc.format = uint32(capturedFormat)

		if pc.yInverted {
			capturedBuf.FlipVertical()
			pc.yInverted = false
		}

		if output.transform != TransformNormal {
			invTransform := InverseTransform(output.transform)
			transformed, err := capturedBuf.ApplyTransform(invTransform)
			if err != nil {
				log.Error("apply transform failed", "err", err)
			} else if transformed != capturedBuf {
				capturedBuf.Close()
				capturedBuf = transformed
			}
		}

		if withCursor {
			pc.screenBuf = capturedBuf
		} else {
			pc.screenBufNoCursor = capturedBuf
		}

		onReady()
	})

	frame.SetFailedHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1FailedEvent) {
		log.Error("screencopy failed")
		frame.Destroy()
		onReady()
	})
}

func (r *RegionSelector) createSurfaces() error {
	r.outputsMu.Lock()
	outputs := make([]*WaylandOutput, 0, len(r.outputs))
	for _, o := range r.outputs {
		outputs = append(outputs, o)
	}
	r.outputsMu.Unlock()

	for _, output := range outputs {
		os, err := r.createOutputSurface(output)
		if err != nil {
			return fmt.Errorf("output %s: %w", output.name, err)
		}
		r.surfaces = append(r.surfaces, os)
	}

	return nil
}

func (r *RegionSelector) createCursor() error {
	const size = 24
	const hotspot = size / 2

	surface, err := r.compositor.CreateSurface()
	if err != nil {
		return fmt.Errorf("create cursor surface: %w", err)
	}
	r.cursorSurface = surface

	buf, err := CreateShmBuffer(size, size, size*4)
	if err != nil {
		return fmt.Errorf("create cursor buffer: %w", err)
	}
	r.cursorBuffer = buf

	// Draw crosshair
	data := buf.Data()
	for y := range size {
		for x := range size {
			off := (y*size + x) * 4
			// Vertical line
			if x >= hotspot-1 && x <= hotspot && y >= 2 && y < size-2 {
				data[off+0] = 255 // B
				data[off+1] = 255 // G
				data[off+2] = 255 // R
				data[off+3] = 255 // A
				continue
			}
			// Horizontal line
			if y >= hotspot-1 && y <= hotspot && x >= 2 && x < size-2 {
				data[off+0] = 255
				data[off+1] = 255
				data[off+2] = 255
				data[off+3] = 255
				continue
			}
			// Transparent
			data[off+0] = 0
			data[off+1] = 0
			data[off+2] = 0
			data[off+3] = 0
		}
	}

	pool, err := r.shm.CreatePool(buf.Fd(), int32(buf.Size()))
	if err != nil {
		return fmt.Errorf("create cursor pool: %w", err)
	}
	r.cursorPool = pool

	wlBuf, err := pool.CreateBuffer(0, size, size, size*4, uint32(FormatARGB8888))
	if err != nil {
		return fmt.Errorf("create cursor wl_buffer: %w", err)
	}
	r.cursorWlBuf = wlBuf

	if err := surface.Attach(wlBuf, 0, 0); err != nil {
		return fmt.Errorf("attach cursor: %w", err)
	}
	if err := surface.Damage(0, 0, size, size); err != nil {
		return fmt.Errorf("damage cursor: %w", err)
	}
	if err := surface.Commit(); err != nil {
		return fmt.Errorf("commit cursor: %w", err)
	}

	return nil
}

func (r *RegionSelector) refreshCursor() {
	r.setNativeCursor(r.cursorSerial)
}

func cursorShapeForHandle(handle resizeHandle) uint32 {
	switch handle {
	case handleTopLeft, handleBottomRight:
		return uint32(wp_cursor_shape.WpCursorShapeDeviceV1ShapeNwseResize)
	case handleTopRight, handleBottomLeft:
		return uint32(wp_cursor_shape.WpCursorShapeDeviceV1ShapeNeswResize)
	default:
		return uint32(wp_cursor_shape.WpCursorShapeDeviceV1ShapeGrab)
	}
}

func (r *RegionSelector) setNativeCursor(serial uint32) {
	if r.cursorShape == nil || r.pointer == nil || serial == 0 {
		return
	}
	shape := uint32(wp_cursor_shape.WpCursorShapeDeviceV1ShapeCrosshair)
	if r.phase == phaseScroll {
		switch r.scrollBarHit(r.pointerX, r.pointerY) {
		case "done", "cancel", "preview":
			shape = uint32(wp_cursor_shape.WpCursorShapeDeviceV1ShapePointer)
		default:
			shape = uint32(wp_cursor_shape.WpCursorShapeDeviceV1ShapeDefault)
		}
	} else if r.resizingHandle != handleNone {
		shape = cursorShapeForHandle(r.resizingHandle)
	} else if r.movingSelection && r.selection.dragging {
		shape = uint32(wp_cursor_shape.WpCursorShapeDeviceV1ShapeGrabbing)
	} else if r.ctrlHeld && r.selection.hasSelection && !r.selection.dragging {
		if r.activeSurface != nil && r.activeSurface.output != nil {
			pointerGlobalX := r.pointerX + float64(r.activeSurface.output.x)
			pointerGlobalY := r.pointerY + float64(r.activeSurface.output.y)
			shape = cursorShapeForHandle(r.resizeHandleAt(pointerGlobalX, pointerGlobalY))
		} else {
			shape = uint32(wp_cursor_shape.WpCursorShapeDeviceV1ShapeGrab)
		}
	} else if r.ctrlHeld && !r.selection.dragging {
		shape = uint32(wp_cursor_shape.WpCursorShapeDeviceV1ShapeGrab)
	}
	if r.cursorDevice == nil {
		device, err := r.cursorShape.GetPointer(r.pointer)
		if err != nil {
			return
		}
		r.cursorDevice = device
	}
	_ = r.cursorDevice.SetShape(serial, shape)
}

func (r *RegionSelector) createOutputSurface(output *WaylandOutput) (*OutputSurface, error) {
	surface, err := r.compositor.CreateSurface()
	if err != nil {
		return nil, fmt.Errorf("create surface: %w", err)
	}

	layerSurf, err := r.layerShell.GetLayerSurface(
		surface,
		output.wlOutput,
		uint32(wlr_layer_shell.ZwlrLayerShellV1LayerOverlay),
		"dms-screenshot",
	)
	if err != nil {
		return nil, fmt.Errorf("get layer surface: %w", err)
	}

	os := &OutputSurface{
		output:    output,
		wlSurface: surface,
		layerSurf: layerSurf,
	}

	if r.viewporter != nil {
		vp, err := r.viewporter.GetViewport(surface)
		if err == nil {
			os.viewport = vp
		}
	}

	if err := layerSurf.SetAnchor(
		uint32(wlr_layer_shell.ZwlrLayerSurfaceV1AnchorTop) |
			uint32(wlr_layer_shell.ZwlrLayerSurfaceV1AnchorBottom) |
			uint32(wlr_layer_shell.ZwlrLayerSurfaceV1AnchorLeft) |
			uint32(wlr_layer_shell.ZwlrLayerSurfaceV1AnchorRight),
	); err != nil {
		return nil, fmt.Errorf("set anchor: %w", err)
	}
	if err := layerSurf.SetExclusiveZone(-1); err != nil {
		return nil, fmt.Errorf("set exclusive zone: %w", err)
	}
	if err := layerSurf.SetKeyboardInteractivity(uint32(wlr_layer_shell.ZwlrLayerSurfaceV1KeyboardInteractivityExclusive)); err != nil {
		return nil, fmt.Errorf("set keyboard interactivity: %w", err)
	}

	layerSurf.SetConfigureHandler(func(e wlr_layer_shell.ZwlrLayerSurfaceV1ConfigureEvent) {
		if err := layerSurf.AckConfigure(e.Serial); err != nil {
			log.Error("ack configure failed", "err", err)
			return
		}
		os.logicalW = int(e.Width)
		os.logicalH = int(e.Height)
		os.configured = true
		r.captureForSurface(os)
		r.ensureShortcutsInhibitor(os)
	})

	layerSurf.SetClosedHandler(func(e wlr_layer_shell.ZwlrLayerSurfaceV1ClosedEvent) {
		r.running = false
		r.cancelled = true
	})

	if err := surface.Commit(); err != nil {
		return nil, fmt.Errorf("surface commit: %w", err)
	}

	return os, nil
}

func (r *RegionSelector) ensureShortcutsInhibitor(os *OutputSurface) {
	if r.shortcutsInhibitMgr == nil || r.seat == nil || r.shortcutsInhibitor != nil {
		return
	}
	inhibitor, err := r.shortcutsInhibitMgr.InhibitShortcuts(os.wlSurface, r.seat)
	if err == nil {
		r.shortcutsInhibitor = inhibitor
	}
}

func (r *RegionSelector) captureForSurface(os *OutputSurface) {
	pc := r.preCapture[os.output]
	if pc == nil {
		return
	}

	os.screenBuf = pc.screenBuf
	os.screenBufNoCursor = pc.screenBufNoCursor
	os.screenFormat = pc.format
	os.yInverted = pc.yInverted
	if os.screenBuf == nil {
		return
	}
	os.captured = true

	if os.logicalW > 0 {
		os.output.fractionalScale = float64(os.screenBuf.Width) / float64(os.logicalW)
	}

	r.ensureSlots(os, os.screenBuf.Width, os.screenBuf.Height, os.screenBuf.Stride, os.screenFormat)
	r.applyPreSelection(os)
	r.redrawSurface(os)
}

// prefaulted while the copy is in flight so the first paint does not stall on page faults
func (r *RegionSelector) prepareSlots(output *WaylandOutput, pc *PreCapture) {
	for _, os := range r.surfaces {
		if os.output == output && os.configured {
			r.ensureSlots(os, pc.width, pc.height, pc.stride, pc.format)
		}
	}
}

func (r *RegionSelector) releaseSlots(os *OutputSurface) {
	os.slotPrefault.Wait()
	os.slotsReady = false
	for i, slot := range os.slots {
		if slot == nil {
			continue
		}
		slot.wlBuf.Destroy()
		slot.pool.Destroy()
		slot.shm.Close()
		os.slots[i] = nil
	}
}

func prefault(buf *ShmBuffer) {
	data := buf.Data()
	for i := 0; i < len(data); i += 4096 {
		data[i] = 0
	}
}

func (r *RegionSelector) ensureSlots(os *OutputSurface, width, height, stride int, format uint32) {
	if first := os.slots[0]; os.slotsReady && first != nil && first.shm.Width == width && first.shm.Height == height && first.shm.Stride == stride && os.slotFormat == format {
		return
	}
	r.releaseSlots(os)
	os.slotFormat = format

	for i := range 3 {
		slot := &RenderSlot{}

		buf, err := CreateShmBuffer(width, height, stride)
		if err != nil {
			log.Error("create render slot buffer failed", "err", err)
			return
		}
		slot.shm = buf

		pool, err := r.shm.CreatePool(buf.Fd(), int32(buf.Size()))
		if err != nil {
			log.Error("create render slot pool failed", "err", err)
			buf.Close()
			return
		}
		slot.pool = pool

		// niri latches surface opacity from the first buffer's format
		// (observed), so slots are ARGB from the start with A=255 when opaque
		wlBuf, err := pool.CreateBuffer(0, int32(buf.Width), int32(buf.Height), int32(buf.Stride), alphaFormat(format))
		if err != nil {
			log.Error("create render slot wl_buffer failed", "err", err)
			pool.Destroy()
			buf.Close()
			return
		}
		slot.wlBuf = wlBuf

		slotRef := slot
		wlBuf.SetReleaseHandler(func(e client.BufferReleaseEvent) {
			slotRef.busy = false
			if os.redrawQueued && !os.framePending {
				r.renderSurface(os)
			}
		})

		os.slots[i] = slot
	}
	os.slotsReady = true
	os.slotPrefault.Add(1)
	go func() {
		defer os.slotPrefault.Done()
		for _, slot := range os.slots {
			prefault(slot.shm)
		}
	}()
}

func (os *OutputSurface) acquireFreeSlot() *RenderSlot {
	for _, slot := range os.slots {
		if slot != nil && !slot.busy {
			return slot
		}
	}
	return nil
}

func (r *RegionSelector) applyPreSelection(os *OutputSurface) {
	if r.preSelect.IsEmpty() || os.screenBuf == nil || r.selection.hasSelection {
		return
	}

	if r.preSelect.Output != "" && r.preSelect.Output != os.output.name {
		return
	}

	scaleX := float64(os.logicalW) / float64(os.screenBuf.Width)
	scaleY := float64(os.logicalH) / float64(os.screenBuf.Height)

	x1 := float64(r.preSelect.X-os.output.x) * scaleX
	y1 := float64(r.preSelect.Y-os.output.y) * scaleY
	// selection edges are inclusive; the exclusive width edge is one device px past it
	x2 := float64(r.preSelect.X-os.output.x+r.preSelect.Width)*scaleX - scaleX
	y2 := float64(r.preSelect.Y-os.output.y+r.preSelect.Height)*scaleY - scaleY

	r.selection.hasSelection = true
	r.selection.fromPreSelect = true
	r.selection.dragging = false
	r.selection.surface = os
	r.selection.anchorX = float64(os.output.x) + x1
	r.selection.anchorY = float64(os.output.y) + y1
	r.selection.currentX = float64(os.output.x) + x2
	r.selection.currentY = float64(os.output.y) + y2
	r.activeSurface = os
}

func (r *RegionSelector) getSourceBuffer(os *OutputSurface) *ShmBuffer {
	if !r.showCapturedCursor && os.screenBufNoCursor != nil {
		return os.screenBufNoCursor
	}
	return os.screenBuf
}

// redrawSurface coalesces redraws to one per compositor frame.
func (r *RegionSelector) redrawSurface(os *OutputSurface) {
	os.redrawQueued = true
	if os.framePending {
		return
	}
	r.renderSurface(os)
}

func (r *RegionSelector) renderSurface(os *OutputSurface) {
	srcBuf := r.getSourceBuffer(os)
	if srcBuf == nil || !os.slotsReady {
		return
	}

	slot := os.acquireFreeSlot()
	if slot == nil {
		return
	}
	os.redrawQueued = false
	os.slotPrefault.Wait()

	fullDamage := true
	var damage []dirtyRect
	switch r.phase {
	case phaseScroll:
		r.drawScrollOverlay(os, slot.shm)
		slot.backgroundInitialized = false
		slot.backgroundSource = nil
		slot.overlay, os.shown = nil, nil
	default:
		cur := r.overlayFor(os, slot.shm)
		handles := (r.resizingHandle != handleNone || (r.ctrlHeld && !r.selection.dragging)) && r.selection.hasSelection && r.phase != phaseScroll
		shift := r.shiftHeld && r.selection.hasSelection
		switch {
		case !slot.cacheValid(srcBuf, r.selection.dragging, r.showCapturedCursor, r.phase, handles, shift):
			paintDimmedFrame(slot.shm, srcBuf)
			effectiveScale := 1.0
			if os.output != nil {
				effectiveScale = os.output.effectiveScale()
			}
			hudScale := r.hudScale(effectiveScale)
			r.drawHUD(slot.shm.Data(), slot.shm.Stride, slot.shm.Width, slot.shm.Height, os.screenFormat, hudScale)
			slot.backgroundInitialized = true
			slot.backgroundSource = srcBuf
			slot.backgroundDragging = r.selection.dragging
			slot.backgroundCursor = r.showCapturedCursor
			slot.backgroundPhase = r.phase
			slot.backgroundHandles = handles
			slot.backgroundShift = shift
			slot.overlay = nil
		case r.compositorVersion >= 4:
			fullDamage = false
			damage = overlayDamage(os.shown, cur)
			if os.committedCursor != r.showCapturedCursor {
				fullDamage = true
				damage = nil
			} else if len(damage) == 0 {
				return
			}
		}
		r.drawOverlay(os, slot.shm, slot.overlay, cur)
		slot.overlay, os.shown = cur, cur
	}

	if os.viewport != nil {
		_ = os.wlSurface.SetBufferScale(1)
		_ = os.viewport.SetSource(0, 0, float64(slot.shm.Width), float64(slot.shm.Height))
		_ = os.viewport.SetDestination(int32(os.logicalW), int32(os.logicalH))
	} else {
		bufferScale := os.output.scale
		if bufferScale <= 0 {
			bufferScale = 1
		}
		_ = os.wlSurface.SetBufferScale(bufferScale)
	}

	_ = os.wlSurface.Attach(slot.wlBuf, 0, 0)
	switch {
	case fullDamage:
		_ = os.wlSurface.Damage(0, 0, int32(os.logicalW), int32(os.logicalH))
	default:
		for _, d := range damage {
			d = d.clampTo(slot.shm.Width, slot.shm.Height)
			if d.empty() {
				continue
			}
			_ = os.wlSurface.DamageBuffer(int32(d.x1), int32(d.y1), int32(d.x2-d.x1), int32(d.y2-d.y1))
		}
	}
	if cb, err := os.wlSurface.Frame(); err == nil {
		os.framePending = true
		cb.SetDoneHandler(func(client.CallbackDoneEvent) {
			_ = cb.Destroy()
			os.framePending = false
			if os.redrawQueued {
				r.renderSurface(os)
			}
		})
	}
	_ = os.wlSurface.Commit()
	os.committedCursor = r.showCapturedCursor

	// Mark this slot as busy until compositor releases it
	slot.busy = true
}

func (r *RegionSelector) cleanup() {
	if r.cursorWlBuf != nil {
		r.cursorWlBuf.Destroy()
	}
	if r.cursorPool != nil {
		r.cursorPool.Destroy()
	}
	if r.cursorSurface != nil {
		r.cursorSurface.Destroy()
	}
	if r.cursorBuffer != nil {
		r.cursorBuffer.Close()
	}
	if r.cursorDevice != nil {
		_ = r.cursorDevice.Destroy()
	}
	if r.cursorShape != nil {
		_ = r.cursorShape.Destroy()
	}

	r.cleanupScroll()

	for _, os := range r.surfaces {
		for _, slot := range os.slots {
			if slot == nil {
				continue
			}
			if slot.wlBuf != nil {
				slot.wlBuf.Destroy()
			}
			if slot.pool != nil {
				slot.pool.Destroy()
			}
			if slot.shm != nil {
				slot.shm.Close()
			}
		}
		if os.viewport != nil {
			os.viewport.Destroy()
		}
		if os.layerSurf != nil {
			os.layerSurf.Destroy()
		}
		if os.wlSurface != nil {
			os.wlSurface.Destroy()
		}
		if os.screenBuf != nil {
			os.screenBuf.Close()
		}
		if os.screenBufNoCursor != nil {
			os.screenBufNoCursor.Close()
		}
	}

	if r.shortcutsInhibitor != nil {
		_ = r.shortcutsInhibitor.Destroy()
	}
	if r.shortcutsInhibitMgr != nil {
		_ = r.shortcutsInhibitMgr.Destroy()
	}
	if r.viewporter != nil {
		r.viewporter.Destroy()
	}
	if r.screencopy != nil {
		r.screencopy.Destroy()
	}
	if r.pointer != nil {
		r.pointer.Release()
	}
	if r.touch != nil {
		_ = r.touch.Release()
	}
	if r.keyboard != nil {
		r.keyboard.Release()
	}
	if r.display != nil {
		r.ctx.Close()
	}
}
