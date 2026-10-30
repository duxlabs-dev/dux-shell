package colorpicker

import (
	"fmt"
	"sync"

	"github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/keyboard_shortcuts_inhibit"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_layer_shell"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_screencopy"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wp_color_management"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wp_viewporter"
	"github.com/duxlabs-dev/dux-shell/core/internal/screenshot"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	wlhelpers "github.com/duxlabs-dev/dux-shell/core/internal/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/wayland/keymap"
)

type Config struct {
	Format        OutputFormat
	CustomFormat  string
	Lowercase     bool
	Autocopy      bool
	Notify        bool
	AllowMultiple bool
}

type Output struct {
	wlOutput        *client.Output
	name            string
	globalName      uint32
	x, y            int32
	width           int32
	height          int32
	scale           int32
	fractionalScale float64
	transform       int32
}

type LayerSurface struct {
	output       *Output
	state        *SurfaceState
	wlSurface    *client.Surface
	layerSurf    *wlr_layer_shell.ZwlrLayerSurfaceV1
	viewport     *wp_viewporter.WpViewport
	wlPools      [2]*client.ShmPool
	wlBuffers    [2]*client.Buffer
	slotBusy     [2]bool
	needsRedraw  bool
	framePending bool
	scopyBuffer  *client.Buffer
	configured   bool
	hidden       bool
}

type Picker struct {
	config Config

	display  *client.Display
	registry *client.Registry
	ctx      *client.Context

	compositor *client.Compositor
	shm        *client.Shm
	seat       *client.Seat
	pointer    *client.Pointer
	keyboard   *client.Keyboard
	keymap     *keymap.Keymap
	layerShell *wlr_layer_shell.ZwlrLayerShellV1
	screencopy *wlr_screencopy.ZwlrScreencopyManagerV1
	viewporter *wp_viewporter.WpViewporter
	colorMgr   *wp_color_management.WpColorManagerV1

	compositorVersion uint32

	shortcutsInhibitMgr *keyboard_shortcuts_inhibit.ZwpKeyboardShortcutsInhibitManagerV1
	shortcutsInhibitor  *keyboard_shortcuts_inhibit.ZwpKeyboardShortcutsInhibitorV1

	outputs   map[uint32]*Output
	outputsMu sync.Mutex

	surfaces      []*LayerSurface
	activeSurface *LayerSurface

	running     bool
	pickedColor *Color
	err         error
}

func New(config Config) *Picker {
	return &Picker{
		config:  config,
		outputs: make(map[uint32]*Output),
	}
}

func (p *Picker) Run() (*Color, error) {
	if !p.config.AllowMultiple {
		lock, err := utils.LockSelectionOverlay()
		if err != nil {
			return nil, err
		}
		defer lock.Release()
	}

	if err := p.connect(); err != nil {
		return nil, fmt.Errorf("wayland connect: %w", err)
	}
	defer p.cleanup()

	if err := p.setupRegistry(); err != nil {
		return nil, fmt.Errorf("registry setup: %w", err)
	}

	if err := p.roundtrip(); err != nil {
		return nil, fmt.Errorf("roundtrip: %w", err)
	}

	if p.screencopy == nil {
		return nil, fmt.Errorf("compositor does not support wlr-screencopy-unstable-v1")
	}

	if p.layerShell == nil {
		return nil, fmt.Errorf("compositor does not support wlr-layer-shell-unstable-v1")
	}

	if p.seat == nil {
		return nil, fmt.Errorf("no seat available")
	}

	if err := p.roundtrip(); err != nil {
		return nil, fmt.Errorf("roundtrip: %w", err)
	}

	// Extra roundtrip to ensure pointer/keyboard from seat capabilities are registered
	if err := p.roundtrip(); err != nil {
		return nil, fmt.Errorf("roundtrip after seat: %w", err)
	}

	if err := p.createSurfaces(); err != nil {
		return nil, fmt.Errorf("create surfaces: %w", err)
	}

	if err := p.roundtrip(); err != nil {
		return nil, fmt.Errorf("roundtrip: %w", err)
	}

	p.running = true
	for p.running {
		if err := p.ctx.Dispatch(); err != nil {
			p.err = err
			break
		}

		p.flushRedraws()
		p.checkDone()
	}

	if p.err != nil {
		return nil, p.err
	}

	return p.pickedColor, nil
}

func (p *Picker) checkDone() {
	for _, ls := range p.surfaces {
		picked, cancelled := ls.state.IsDone()
		switch {
		case cancelled:
			p.running = false
			return
		case picked:
			color, ok := ls.state.PickColor()
			if ok {
				p.pickedColor = &color
			}
			p.running = false
			return
		}
	}
}

// flushRedraws paints queued surfaces, at most once per compositor frame each.
func (p *Picker) flushRedraws() {
	for _, ls := range p.surfaces {
		if !ls.needsRedraw || ls.framePending {
			continue
		}
		p.redrawSurface(ls)
	}
}

func (p *Picker) connect() error {
	display, err := client.Connect("")
	if err != nil {
		return err
	}
	p.display = display
	p.ctx = display.Context()
	return nil
}

func (p *Picker) roundtrip() error {
	return wlhelpers.Roundtrip(p.display, p.ctx)
}

func (p *Picker) setupRegistry() error {
	registry, err := p.display.GetRegistry()
	if err != nil {
		return err
	}
	p.registry = registry

	registry.SetGlobalHandler(func(e client.RegistryGlobalEvent) {
		p.handleGlobal(e)
	})

	registry.SetGlobalRemoveHandler(func(e client.RegistryGlobalRemoveEvent) {
		p.outputsMu.Lock()
		delete(p.outputs, e.Name)
		p.outputsMu.Unlock()
	})

	return nil
}

func (p *Picker) handleGlobal(e client.RegistryGlobalEvent) {
	switch e.Interface {
	case client.CompositorInterfaceName:
		compositor := client.NewCompositor(p.ctx)
		if err := p.registry.Bind(e.Name, e.Interface, e.Version, compositor); err == nil {
			p.compositor = compositor
			p.compositorVersion = e.Version
		}

	case client.ShmInterfaceName:
		shm := client.NewShm(p.ctx)
		if err := p.registry.Bind(e.Name, e.Interface, e.Version, shm); err == nil {
			p.shm = shm
		}

	case client.SeatInterfaceName:
		seat := client.NewSeat(p.ctx)
		if err := p.registry.Bind(e.Name, e.Interface, e.Version, seat); err == nil {
			p.seat = seat
			p.setupInput()
		}

	case client.OutputInterfaceName:
		output := client.NewOutput(p.ctx)
		version := min(e.Version, 4)
		if err := p.registry.Bind(e.Name, e.Interface, version, output); err == nil {
			p.outputsMu.Lock()
			p.outputs[e.Name] = &Output{
				wlOutput:        output,
				globalName:      e.Name,
				scale:           1,
				fractionalScale: 1.0,
			}
			p.outputsMu.Unlock()
			p.setupOutputHandlers(e.Name, output)
		}

	case wlr_layer_shell.ZwlrLayerShellV1InterfaceName:
		layerShell := wlr_layer_shell.NewZwlrLayerShellV1(p.ctx)
		version := min(e.Version, 4)
		if err := p.registry.Bind(e.Name, e.Interface, version, layerShell); err == nil {
			p.layerShell = layerShell
		}

	case wlr_screencopy.ZwlrScreencopyManagerV1InterfaceName:
		screencopy := wlr_screencopy.NewZwlrScreencopyManagerV1(p.ctx)
		version := min(e.Version, 3)
		if err := p.registry.Bind(e.Name, e.Interface, version, screencopy); err == nil {
			p.screencopy = screencopy
		}

	case wp_viewporter.WpViewporterInterfaceName:
		viewporter := wp_viewporter.NewWpViewporter(p.ctx)
		if err := p.registry.Bind(e.Name, e.Interface, e.Version, viewporter); err == nil {
			p.viewporter = viewporter
		}

	case wp_color_management.WpColorManagerV1InterfaceName:
		mgr := wp_color_management.NewWpColorManagerV1(p.ctx)
		if err := p.registry.Bind(e.Name, e.Interface, 1, mgr); err == nil {
			p.colorMgr = mgr
		}

	case keyboard_shortcuts_inhibit.ZwpKeyboardShortcutsInhibitManagerV1InterfaceName:
		mgr := keyboard_shortcuts_inhibit.NewZwpKeyboardShortcutsInhibitManagerV1(p.ctx)
		if err := p.registry.Bind(e.Name, e.Interface, e.Version, mgr); err == nil {
			p.shortcutsInhibitMgr = mgr
		}
	}
}

func (p *Picker) setupOutputHandlers(name uint32, output *client.Output) {
	output.SetGeometryHandler(func(e client.OutputGeometryEvent) {
		p.outputsMu.Lock()
		if o, ok := p.outputs[name]; ok {
			o.x = e.X
			o.y = e.Y
			o.transform = int32(e.Transform)
		}
		p.outputsMu.Unlock()
	})

	output.SetModeHandler(func(e client.OutputModeEvent) {
		if e.Flags&uint32(client.OutputModeCurrent) == 0 {
			return
		}
		p.outputsMu.Lock()
		if o, ok := p.outputs[name]; ok {
			o.width = e.Width
			o.height = e.Height
		}
		p.outputsMu.Unlock()
	})

	output.SetScaleHandler(func(e client.OutputScaleEvent) {
		p.outputsMu.Lock()
		if o, ok := p.outputs[name]; ok {
			o.scale = e.Factor
			o.fractionalScale = float64(e.Factor)
		}
		p.outputsMu.Unlock()
	})

	output.SetNameHandler(func(e client.OutputNameEvent) {
		p.outputsMu.Lock()
		if o, ok := p.outputs[name]; ok {
			o.name = e.Name
		}
		p.outputsMu.Unlock()
	})
}

func (p *Picker) createSurfaces() error {
	p.outputsMu.Lock()
	outputs := make([]*Output, 0, len(p.outputs))
	for _, o := range p.outputs {
		outputs = append(outputs, o)
	}
	p.outputsMu.Unlock()

	for _, output := range outputs {
		refLum, pq := p.outputPQEncoding(output)
		ls, err := p.createLayerSurface(output)
		if err != nil {
			return fmt.Errorf("output %s: %w", output.name, err)
		}
		if pq {
			ls.state.SetPQEncoding(refLum)
		}
		p.surfaces = append(p.surfaces, ls)
	}

	return nil
}

func (p *Picker) outputPQEncoding(output *Output) (float64, bool) {
	if p.colorMgr == nil {
		return 0, false
	}

	desc, ok := wp_color_management.QueryOutputDescription(p.colorMgr, output.wlOutput, p.roundtrip)
	if !ok {
		return 0, false
	}

	pq := desc.TF == uint32(wp_color_management.WpColorManagerV1TransferFunctionSt2084Pq) &&
		desc.Primaries == uint32(wp_color_management.WpColorManagerV1PrimariesBt2020)
	if !pq {
		return 0, false
	}
	return float64(desc.ReferenceLum), true
}

func (p *Picker) createLayerSurface(output *Output) (*LayerSurface, error) {
	surface, err := p.compositor.CreateSurface()
	if err != nil {
		return nil, fmt.Errorf("create surface: %w", err)
	}

	layerSurf, err := p.layerShell.GetLayerSurface(
		surface,
		output.wlOutput,
		uint32(wlr_layer_shell.ZwlrLayerShellV1LayerOverlay),
		"dms-colorpicker",
	)
	if err != nil {
		return nil, fmt.Errorf("get layer surface: %w", err)
	}

	ls := &LayerSurface{
		output:    output,
		state:     NewSurfaceState(p.config.Format, p.config.Lowercase),
		wlSurface: surface,
		layerSurf: layerSurf,
		hidden:    true, // Start hidden, will show overlay when pointer enters
	}

	if p.viewporter != nil {
		vp, err := p.viewporter.GetViewport(surface)
		if err == nil {
			ls.viewport = vp
		}
	}

	if err := layerSurf.SetAnchor(
		uint32(wlr_layer_shell.ZwlrLayerSurfaceV1AnchorTop) |
			uint32(wlr_layer_shell.ZwlrLayerSurfaceV1AnchorBottom) |
			uint32(wlr_layer_shell.ZwlrLayerSurfaceV1AnchorLeft) |
			uint32(wlr_layer_shell.ZwlrLayerSurfaceV1AnchorRight),
	); err != nil {
		log.Warn("failed to set layer anchor", "err", err)
	}
	if err := layerSurf.SetExclusiveZone(-1); err != nil {
		log.Warn("failed to set exclusive zone", "err", err)
	}
	if err := layerSurf.SetKeyboardInteractivity(uint32(wlr_layer_shell.ZwlrLayerSurfaceV1KeyboardInteractivityExclusive)); err != nil {
		log.Warn("failed to set keyboard interactivity", "err", err)
	}

	layerSurf.SetConfigureHandler(func(e wlr_layer_shell.ZwlrLayerSurfaceV1ConfigureEvent) {
		if err := layerSurf.AckConfigure(e.Serial); err != nil {
			log.Warn("failed to ack configure", "err", err)
		}
		if err := ls.state.OnLayerConfigure(int(e.Width), int(e.Height)); err != nil {
			log.Warn("failed to handle layer configure", "err", err)
		}
		ls.configured = true

		scale := p.computeSurfaceScale(ls)
		ls.state.SetScale(scale)

		if !ls.state.IsReady() {
			p.captureForSurface(ls)
		} else {
			p.redrawSurface(ls)
		}

		// Request shortcut inhibition once surface is configured
		p.ensureShortcutsInhibitor(ls)
	})

	layerSurf.SetClosedHandler(func(e wlr_layer_shell.ZwlrLayerSurfaceV1ClosedEvent) {
		p.running = false
	})

	if err := surface.Commit(); err != nil {
		log.Warn("failed to commit surface", "err", err)
	}
	return ls, nil
}

func (p *Picker) computeSurfaceScale(ls *LayerSurface) int32 {
	out := ls.output
	if out == nil || out.scale <= 0 {
		return 1
	}
	return out.scale
}

func (p *Picker) ensureShortcutsInhibitor(ls *LayerSurface) {
	if p.shortcutsInhibitMgr == nil || p.seat == nil || p.shortcutsInhibitor != nil {
		return
	}

	inhibitor, err := p.shortcutsInhibitMgr.InhibitShortcuts(ls.wlSurface, p.seat)
	if err != nil {
		log.Debug("failed to create shortcuts inhibitor", "err", err)
		return
	}

	p.shortcutsInhibitor = inhibitor

	inhibitor.SetActiveHandler(func(e keyboard_shortcuts_inhibit.ZwpKeyboardShortcutsInhibitorV1ActiveEvent) {
		log.Debug("shortcuts inhibitor active")
	})

	inhibitor.SetInactiveHandler(func(e keyboard_shortcuts_inhibit.ZwpKeyboardShortcutsInhibitorV1InactiveEvent) {
		log.Debug("shortcuts inhibitor deactivated by compositor")
	})
}

func (p *Picker) captureForSurface(ls *LayerSurface) {
	frame, err := p.screencopy.CaptureOutput(0, ls.output.wlOutput)
	if err != nil {
		return
	}

	frame.SetBufferHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1BufferEvent) {
		if err := ls.state.OnScreencopyBuffer(PixelFormat(e.Format), int(e.Width), int(e.Height), int(e.Stride)); err != nil {
			log.Error("failed to create screencopy buffer", "err", err)
		}
	})

	frame.SetBufferDoneHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1BufferDoneEvent) {
		screenBuf := ls.state.ScreenBuffer()
		if screenBuf == nil {
			return
		}

		pool, err := p.shm.CreatePool(screenBuf.Fd(), int32(screenBuf.Size()))
		if err != nil {
			return
		}

		wlBuffer, err := pool.CreateBuffer(0, int32(screenBuf.Width), int32(screenBuf.Height), int32(screenBuf.Stride), uint32(ls.state.screenFormat))
		if err != nil {
			pool.Destroy()
			return
		}

		if ls.scopyBuffer != nil {
			ls.scopyBuffer.Destroy()
		}
		ls.scopyBuffer = wlBuffer
		wlBuffer.SetReleaseHandler(func(e client.BufferReleaseEvent) {})

		if err := frame.Copy(wlBuffer); err != nil {
			log.Error("failed to copy frame", "err", err)
		}
		pool.Destroy()
	})

	frame.SetFlagsHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1FlagsEvent) {
		ls.state.OnScreencopyFlags(e.Flags)
	})

	frame.SetReadyHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1ReadyEvent) {
		ls.state.OnScreencopyReady()

		screenBuf := ls.state.ScreenBuffer()
		if screenBuf != nil {
			transformed, err := ls.output.untransformFrame(screenBuf)
			if err != nil {
				log.Error("apply transform failed", "err", err)
			} else if transformed != screenBuf {
				ls.state.ReplaceScreenBuffer(transformed)
			}
		}

		logicalW, _ := ls.state.LogicalSize()
		screenBuf = ls.state.ScreenBuffer()
		if logicalW > 0 && screenBuf != nil {
			ls.output.fractionalScale = float64(screenBuf.Width) / float64(logicalW)
		}

		scale := p.computeSurfaceScale(ls)
		ls.state.SetScale(scale)
		frame.Destroy()
		p.redrawSurface(ls)
	})

	frame.SetFailedHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1FailedEvent) {
		frame.Destroy()
	})
}

func (o *Output) untransformFrame(buf *ShmBuffer) (*ShmBuffer, error) {
	if screenshot.FrameInLogicalOrientation(o.transform, o.width, o.height, buf.Width, buf.Height) {
		return buf, nil
	}
	return buf.ApplyTransform(InverseTransform(o.transform))
}

func (p *Picker) redrawSurface(ls *LayerSurface) {
	slot := ls.state.FrontIndex()
	if ls.slotBusy[slot] || ls.framePending {
		ls.needsRedraw = true
		return
	}

	var renderBuf *ShmBuffer
	var damage []rect
	switch {
	case ls.hidden:
		renderBuf, damage = ls.state.RedrawScreenOnly()
	default:
		renderBuf, damage = ls.state.Redraw()
	}
	if renderBuf == nil {
		return
	}

	ls.needsRedraw = false

	if ls.wlPools[slot] == nil {
		pool, err := p.shm.CreatePool(renderBuf.Fd(), int32(renderBuf.Size()))
		if err != nil {
			return
		}
		ls.wlPools[slot] = pool

		wlBuffer, err := pool.CreateBuffer(0, int32(renderBuf.Width), int32(renderBuf.Height), int32(renderBuf.Stride), uint32(ls.state.ScreenFormat()))
		if err != nil {
			return
		}
		ls.wlBuffers[slot] = wlBuffer

		s := slot
		wlBuffer.SetReleaseHandler(func(e client.BufferReleaseEvent) {
			ls.slotBusy[s] = false
		})
	}

	ls.slotBusy[slot] = true

	logicalW, logicalH := ls.state.LogicalSize()
	if logicalW == 0 || logicalH == 0 {
		logicalW = int(ls.output.width)
		logicalH = int(ls.output.height)
	}

	if ls.viewport != nil {
		_ = ls.wlSurface.SetBufferScale(1)
		_ = ls.viewport.SetSource(0, 0, float64(renderBuf.Width), float64(renderBuf.Height))
		_ = ls.viewport.SetDestination(int32(logicalW), int32(logicalH))
	} else {
		bufferScale := ls.output.scale
		if bufferScale <= 0 {
			bufferScale = 1
		}
		_ = ls.wlSurface.SetBufferScale(bufferScale)
	}
	_ = ls.wlSurface.Attach(ls.wlBuffers[slot], 0, 0)
	switch {
	case p.compositorVersion < 4:
		_ = ls.wlSurface.Damage(0, 0, int32(logicalW), int32(logicalH))
	default:
		for _, r := range damage {
			r = r.clip(renderBuf.Width, renderBuf.Height)
			if r.w <= 0 || r.h <= 0 {
				continue
			}
			_ = ls.wlSurface.DamageBuffer(int32(r.x), int32(r.y), int32(r.w), int32(r.h))
		}
	}
	if cb, err := ls.wlSurface.Frame(); err == nil {
		ls.framePending = true
		cb.SetDoneHandler(func(client.CallbackDoneEvent) {
			_ = cb.Destroy()
			ls.framePending = false
		})
	}
	_ = ls.wlSurface.Commit()

	ls.state.SwapBuffers()
}

func (p *Picker) hideSurface(ls *LayerSurface) {
	if ls == nil || ls.wlSurface == nil || ls.hidden {
		return
	}
	ls.hidden = true
	// Redraw without the crosshair overlay
	p.redrawSurface(ls)
}

func (p *Picker) setupInput() {
	if p.seat == nil {
		return
	}

	p.seat.SetCapabilitiesHandler(func(e client.SeatCapabilitiesEvent) {
		if e.Capabilities&uint32(client.SeatCapabilityPointer) != 0 && p.pointer == nil {
			pointer, err := p.seat.GetPointer()
			if err != nil {
				return
			}
			p.pointer = pointer
			p.setupPointerHandlers()
		}
		if e.Capabilities&uint32(client.SeatCapabilityKeyboard) != 0 && p.keyboard == nil {
			keyboard, err := p.seat.GetKeyboard()
			if err != nil {
				return
			}
			p.keyboard = keyboard
			p.setupKeyboardHandlers()
		}
	})
}

func (p *Picker) setupPointerHandlers() {
	p.pointer.SetEnterHandler(func(e client.PointerEnterEvent) {
		if err := p.pointer.SetCursor(e.Serial, nil, 0, 0); err != nil {
			log.Debug("failed to hide cursor", "err", err)
		}

		if e.Surface == nil {
			return
		}

		p.activeSurface = nil
		surfaceID := e.Surface.ID()
		for _, ls := range p.surfaces {
			if ls.wlSurface.ID() == surfaceID {
				p.activeSurface = ls
				break
			}
		}
		if p.activeSurface == nil {
			return
		}

		if p.activeSurface.hidden {
			p.activeSurface.hidden = false
		}

		p.activeSurface.state.OnPointerMotion(e.SurfaceX, e.SurfaceY)
		p.activeSurface.needsRedraw = true
	})

	p.pointer.SetLeaveHandler(func(e client.PointerLeaveEvent) {
		if e.Surface == nil {
			return
		}
		surfaceID := e.Surface.ID()
		for _, ls := range p.surfaces {
			if ls.wlSurface.ID() == surfaceID {
				p.hideSurface(ls)
				break
			}
		}
	})

	p.pointer.SetMotionHandler(func(e client.PointerMotionEvent) {
		if p.activeSurface == nil {
			return
		}
		p.activeSurface.state.OnPointerMotion(e.SurfaceX, e.SurfaceY)
		p.activeSurface.needsRedraw = true
	})

	p.pointer.SetButtonHandler(func(e client.PointerButtonEvent) {
		if p.activeSurface == nil {
			return
		}
		p.activeSurface.state.OnPointerButton(e.Button, e.State)
	})
}

func (p *Picker) setupKeyboardHandlers() {
	p.keyboard.SetKeymapHandler(func(e client.KeyboardKeymapEvent) {
		p.keymap = keymap.FromEvent(e)
	})

	p.keyboard.SetKeyHandler(func(e client.KeyboardKeyEvent) {
		sym := p.keymap.Keysym(e.Key)
		for _, ls := range p.surfaces {
			ls.state.OnKey(sym, e.State)
		}
	})
}

func (p *Picker) cleanup() {
	for _, ls := range p.surfaces {
		if ls.scopyBuffer != nil {
			ls.scopyBuffer.Destroy()
		}
		for i := range ls.wlBuffers {
			if ls.wlBuffers[i] != nil {
				ls.wlBuffers[i].Destroy()
			}
			if ls.wlPools[i] != nil {
				ls.wlPools[i].Destroy()
			}
		}
		if ls.viewport != nil {
			ls.viewport.Destroy()
		}
		if ls.layerSurf != nil {
			ls.layerSurf.Destroy()
		}
		if ls.wlSurface != nil {
			ls.wlSurface.Destroy()
		}
		if ls.state != nil {
			ls.state.Destroy()
		}
	}

	if p.shortcutsInhibitor != nil {
		if err := p.shortcutsInhibitor.Destroy(); err != nil {
			log.Debug("failed to destroy shortcuts inhibitor", "err", err)
		}
		p.shortcutsInhibitor = nil
	}

	if p.shortcutsInhibitMgr != nil {
		if err := p.shortcutsInhibitMgr.Destroy(); err != nil {
			log.Debug("failed to destroy shortcuts inhibit manager", "err", err)
		}
		p.shortcutsInhibitMgr = nil
	}

	if p.viewporter != nil {
		p.viewporter.Destroy()
	}

	if p.colorMgr != nil {
		p.colorMgr.Destroy()
	}

	if p.screencopy != nil {
		p.screencopy.Destroy()
	}

	if p.pointer != nil {
		p.pointer.Release()
	}

	if p.keyboard != nil {
		p.keyboard.Release()
	}

	if p.display != nil {
		p.ctx.Close()
	}
}
