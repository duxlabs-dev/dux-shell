package screenshot

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"time"

	"github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_layer_shell"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_screencopy"
	"golang.org/x/sys/unix"
)

type selectorPhase int

const (
	phaseSelect selectorPhase = iota
	phaseScroll
)

const (
	scrollMaxFailures = 5
	scrollSeamTicks   = 4

	scrollPreviewMarginLogical    = 16
	scrollPreviewPaddingLogical   = 6
	scrollPreviewMinImageWLogical = 80
	scrollPreviewMaxImageWLogical = 240
	scrollPreviewMaxImageHLogical = 360
)

type scrollSession struct {
	output *WaylandOutput
	// wire coords for CaptureOutputRegion (logical or device px per compositor)
	capX, capY, capW, capH int32
	// device-pixel rect in the overlay buffer, for hole/border drawing
	holeX, holeY, holeW, holeH int

	interval time.Duration
	nextTick time.Time
	inFlight bool
	failures int
	kept     int
	abortErr error

	buf            *ShmBuffer
	pool           *client.ShmPool
	wlBuf          *client.Buffer
	frame          *wlr_screencopy.ZwlrScreencopyFrameV1
	format         PixelFormat
	frameW, frameH int
	yInverted      bool

	prevSig        []float32
	prevPlaced     bool
	unmatched      bool
	unmatchedTicks int

	// control bar geometry in overlay buffer pixels
	barX, barY, barW, barH int
	doneX, doneY, doneW    int
	cancelX, cancelY       int
	cancelW                int
	btnH                   int

	// preview panel geometry and window in overlay buffer pixels
	previewX, previewY, previewW, previewH int
	previewStartRow, previewRows           int
	hasPreview                             bool

	sigCh     chan os.Signal
	keysBound bool

	st *stitcher
}

func (r *RegionSelector) dispatchOrTick() error {
	timeout := -1
	if s := r.scroll; r.phase == phaseScroll && s != nil && s.sigCh != nil {
		select {
		case sig := <-s.sigCh:
			switch sig {
			case unix.SIGUSR2:
				r.cancelled = true
				r.running = false
			default:
				r.finishScroll()
			}
			return nil
		default:
		}
	}
	if s := r.scroll; r.phase == phaseScroll && s.abortErr == nil && (s.st == nil || !s.st.full) {
		timeout = max(int(time.Until(s.nextTick).Milliseconds()), 0)
	}

	fds := []unix.PollFd{{Fd: int32(r.ctx.Fd()), Events: unix.POLLIN}}
	n, err := unix.Poll(fds, timeout)
	switch {
	case err == unix.EINTR:
		return nil
	case err != nil:
		return err
	case n > 0:
		return r.ctx.Dispatch()
	}

	r.scrollTick()
	return nil
}

func (r *RegionSelector) scrollTick() {
	s := r.scroll
	if s == nil {
		return
	}
	if s.inFlight || (s.st != nil && s.st.full) {
		s.nextTick = time.Now().Add(s.interval)
		return
	}
	r.startScrollCapture()
}

func (r *RegionSelector) enterScrollPhase(os *OutputSurface, x, y, w, h int) {
	switch {
	case os.output.transform != TransformNormal:
		r.abortScroll(fmt.Errorf("scroll capture does not support rotated outputs"))
		return
	case w < 1 || h < 1:
		r.abortScroll(fmt.Errorf("empty scroll capture region"))
		return
	}

	interval := 45
	if r.screenshoter != nil && r.screenshoter.config.IntervalMs > 0 {
		interval = r.screenshoter.config.IntervalMs
	}

	capX, capY, capW, capH := scrollCaptureRect(DetectCompositor(), os.output.fractionalScale, x, y, w, h)

	r.scroll = &scrollSession{
		output:   os.output,
		capX:     int32(capX),
		capY:     int32(capY),
		capW:     int32(capW),
		capH:     int32(capH),
		holeX:    x,
		holeY:    y,
		holeW:    w,
		holeH:    h,
		interval: time.Duration(interval) * time.Millisecond,
		nextTick: time.Now(),
	}

	r.layoutScrollBar(os)

	for _, surf := range r.surfaces {
		r.setInputPassthrough(surf, surf == os)
	}

	// Hyprland routes all pointer input to exclusive-keyboard layers
	// (https://github.com/hyprwm/Hyprland/discussions/14136), so the keyboard
	// is released there and Enter/Esc come back via temporary global binds
	if DetectCompositor() == CompositorHyprland {
		r.enterHyprlandScrollInput(os)
	}

	r.phase = phaseScroll
	for _, surf := range r.surfaces {
		r.redrawSurface(surf)
	}
}

func scrollCaptureRect(comp Compositor, scale float64, x, y, w, h int) (int, int, int, int) {
	// mango takes device pixels, deviating from spec (observed); Hyprland scales the box itself, so it stays on the spec path
	if comp == CompositorMango || scale <= 1 {
		return x, y, w, h
	}
	// spec: logical coordinates, scaled by the compositor
	// https://wayland.app/protocols/wlr-screencopy-unstable-v1#zwlr_screencopy_manager_v1:request:capture_output_region
	return int(float64(x)/scale + 0.5), int(float64(y)/scale + 0.5),
		int(float64(w)/scale + 0.5), int(float64(h)/scale + 0.5)
}

// sized for the worst-case counter so the input region is set once
func (r *RegionSelector) layoutScrollBar(os *OutputSurface) {
	s := r.scroll
	const charAdv, pad, gap = 9, 12, 16

	s.btnH = 24
	s.doneW = len("done")*charAdv + 24
	s.cancelW = len("cancel")*charAdv + 24
	counterW := len("99999 shots 999999px") * charAdv
	s.barW = pad + s.doneW + gap + s.cancelW + gap + counterW + pad
	s.barH = s.btnH + 24

	bufW, bufH := os.screenBuf.Width, os.screenBuf.Height
	s.barX = (bufW - s.barW) / 2
	s.barY = bufH - s.barH - 24

	borderX1, borderY1 := s.holeX-3, s.holeY-3
	borderX2, borderY2 := s.holeX+s.holeW+3, s.holeY+s.holeH+3
	overlapsHole := s.barX < borderX2 && s.barX+s.barW > borderX1 &&
		s.barY < borderY2 && s.barY+s.barH > borderY1
	overlapsPreview := s.hasPreview &&
		s.barX < s.previewX+s.previewW && s.barX+s.barW > s.previewX &&
		s.barY < s.previewY+s.previewH && s.barY+s.barH > s.previewY
	if overlapsHole || overlapsPreview {
		s.barY = 24
	}

	s.doneX = s.barX + pad
	s.doneY = s.barY + (s.barH-s.btnH)/2
	s.cancelX = s.doneX + s.doneW + gap
	s.cancelY = s.doneY
}

func (r *RegionSelector) scrollPreviewPanel(os *OutputSurface) (x, y, w, h int, startRow, previewRows int, ok bool) {
	s := r.scroll
	if s == nil || s.st == nil || s.frameW <= 0 || s.st.rows() <= 0 || os == nil || os.screenBuf == nil {
		return 0, 0, 0, 0, 0, 0, false
	}

	bufW, bufH := os.screenBuf.Width, os.screenBuf.Height
	scale := 1.0
	if os.logicalW > 0 {
		scale = float64(bufW) / float64(os.logicalW)
	}
	if scale <= 0 {
		scale = 1.0
	}

	margin := int(float64(scrollPreviewMarginLogical) * scale)
	padding := int(float64(scrollPreviewPaddingLogical) * scale)
	minImageW := int(float64(scrollPreviewMinImageWLogical) * scale)
	maxImageW := int(float64(scrollPreviewMaxImageWLogical) * scale)
	maxImageH := int(float64(scrollPreviewMaxImageHLogical) * scale)

	selX := s.holeX
	selY := s.holeY
	selW := s.holeW
	selH := s.holeH

	leftGap := selX
	rightGap := bufW - (selX + selW)
	if leftGap < 0 {
		leftGap = 0
	}
	if rightGap < 0 {
		rightGap = 0
	}

	onLeft := leftGap >= rightGap
	sideGap := rightGap
	if onLeft {
		sideGap = leftGap
	}

	maxHeight := min(maxImageH, bufH-margin*2)
	availableWidth := sideGap - (margin*2 + padding*2)
	if maxHeight <= 0 || availableWidth < minImageW {
		return 0, 0, 0, 0, 0, 0, false
	}

	totalRows := s.st.rows()
	maxPreviewRows := int(float64(s.frameW) * float64(maxHeight) / float64(minImageW))
	startRow = 0
	previewRows = totalRows
	if maxPreviewRows > 0 && totalRows > maxPreviewRows {
		startRow = totalRows - maxPreviewRows
		previewRows = maxPreviewRows
	}

	aspect := float64(s.frameW) / float64(previewRows)
	imageWidth := int(float64(maxHeight)*aspect + 0.5)
	imageWidth = min(imageWidth, maxImageW)
	imageWidth = min(imageWidth, availableWidth)
	if imageWidth < minImageW {
		return 0, 0, 0, 0, 0, 0, false
	}

	imageHeight := max(int(float64(imageWidth)/aspect+0.5), 1)
	panelWidth := imageWidth + padding*2
	panelHeight := imageHeight + padding*2

	var panelX int
	if onLeft {
		panelX = selX - margin - panelWidth
	} else {
		panelX = selX + selW + margin
	}

	panelY := selY + (selH-panelHeight)/2
	panelY = clamp(panelY, margin, bufH-margin-panelHeight)

	return panelX, panelY, panelWidth, panelHeight, startRow, previewRows, true
}

func (r *RegionSelector) updateScrollPreviewLayout(os *OutputSurface) {
	s := r.scroll
	if s == nil || os == nil {
		return
	}
	px, py, pw, ph, startRow, previewRows, ok := r.scrollPreviewPanel(os)
	changed := s.hasPreview != ok || s.previewX != px || s.previewY != py || s.previewW != pw || s.previewH != ph
	s.previewX, s.previewY, s.previewW, s.previewH = px, py, pw, ph
	s.previewStartRow, s.previewRows = startRow, previewRows
	s.hasPreview = ok

	if changed {
		r.layoutScrollBar(os)
		r.setInputPassthrough(os, true)
	}
}

func (r *RegionSelector) setInputPassthrough(os *OutputSurface, withBar bool) {
	if r.compositor == nil || os == nil || os.wlSurface == nil {
		return
	}
	reg, err := r.compositor.CreateRegion()
	if err != nil {
		return
	}
	if withBar && os.screenBuf != nil && os.logicalW > 0 {
		s := r.scroll
		scaleX := float64(os.logicalW) / float64(os.screenBuf.Width)
		scaleY := float64(os.logicalH) / float64(os.screenBuf.Height)
		_ = reg.Add(int32(float64(s.barX)*scaleX), int32(float64(s.barY)*scaleY),
			int32(float64(s.barW)*scaleX)+1, int32(float64(s.barH)*scaleY)+1)
		if s.hasPreview {
			_ = reg.Add(int32(float64(s.previewX)*scaleX), int32(float64(s.previewY)*scaleY),
				int32(float64(s.previewW)*scaleX)+1, int32(float64(s.previewH)*scaleY)+1)
		}
	}
	_ = os.wlSurface.SetInputRegion(reg)
	_ = reg.Destroy()
}

func (r *RegionSelector) enterHyprlandScrollInput(osurf *OutputSurface) {
	for _, surf := range r.surfaces {
		_ = surf.layerSurf.SetKeyboardInteractivity(uint32(wlr_layer_shell.ZwlrLayerSurfaceV1KeyboardInteractivityNone))
	}
	if r.shortcutsInhibitor != nil {
		_ = r.shortcutsInhibitor.Destroy()
		r.shortcutsInhibitor = nil
	}

	s := r.scroll
	scale := osurf.output.fractionalScale
	if scale <= 0 {
		scale = 1
	}
	cx := int(float64(osurf.output.x) + float64(s.holeX+s.holeW/2)/scale)
	cy := int(float64(osurf.output.y) + float64(s.holeY+s.holeH/2)/scale)
	hyprlandFocusWindowAt(cx, cy)

	s.sigCh = make(chan os.Signal, 2)
	signal.Notify(s.sigCh, unix.SIGUSR1, unix.SIGUSR2)
	s.keysBound = exec.Command("hyprctl", hyprlandBindScrollKeysArgs(os.Getpid())...).Run() == nil
}

func hyprlandFocusWindowAt(x, y int) {
	out, err := exec.Command("hyprctl", "-j", "clients").Output()
	if err != nil {
		return
	}
	var clients []struct {
		Address        string `json:"address"`
		At             [2]int `json:"at"`
		Size           [2]int `json:"size"`
		Mapped         bool   `json:"mapped"`
		Hidden         bool   `json:"hidden"`
		FocusHistoryID int    `json:"focusHistoryID"`
	}
	if json.Unmarshal(out, &clients) != nil {
		return
	}

	best := -1
	for i, c := range clients {
		if !c.Mapped || c.Hidden {
			continue
		}
		if x < c.At[0] || x >= c.At[0]+c.Size[0] || y < c.At[1] || y >= c.At[1]+c.Size[1] {
			continue
		}
		if best < 0 || c.FocusHistoryID < clients[best].FocusHistoryID {
			best = i
		}
	}
	if best < 0 {
		return
	}
	_ = exec.Command("hyprctl", hyprlandFocusArgs(clients[best].Address)...).Run()
}

func hyprlandFocusArgs(address string) []string {
	return []string{"dispatch", fmt.Sprintf("hl.dsp.focus({ window = %q })", "address:"+address)}
}

func hyprlandBindScrollKeysArgs(pid int) []string {
	return []string{"eval", fmt.Sprintf(`hl.bind("Return", hl.dsp.exec_cmd("kill -USR1 %d")); hl.bind("Escape", hl.dsp.exec_cmd("kill -USR2 %d"))`, pid, pid)}
}

func hyprlandUnbindScrollKeysArgs() []string {
	return []string{"eval", `hl.unbind("Return"); hl.unbind("Escape")`}
}

func (r *RegionSelector) scrollBarHit(x, y float64) string {
	s := r.scroll
	os := r.selection.surface
	if s == nil || os == nil || os.screenBuf == nil || os.logicalW == 0 {
		return ""
	}
	bx := int(x * float64(os.screenBuf.Width) / float64(os.logicalW))
	by := int(y * float64(os.screenBuf.Height) / float64(os.logicalH))

	switch {
	case bx >= s.doneX && bx < s.doneX+s.doneW && by >= s.doneY && by < s.doneY+s.btnH:
		return "done"
	case bx >= s.cancelX && bx < s.cancelX+s.cancelW && by >= s.cancelY && by < s.cancelY+s.btnH:
		return "cancel"
	case s.hasPreview && bx >= s.previewX && bx < s.previewX+s.previewW && by >= s.previewY && by < s.previewY+s.previewH:
		return "preview"
	default:
		return ""
	}
}

func alphaFormat(format uint32) uint32 {
	switch format {
	case uint32(FormatXRGB8888):
		return uint32(FormatARGB8888)
	case uint32(FormatXBGR8888):
		return uint32(FormatABGR8888)
	default:
		return format
	}
}

func (r *RegionSelector) startScrollCapture() {
	s := r.scroll
	frame, err := r.screencopy.CaptureOutputRegion(0, s.output.wlOutput, s.capX, s.capY, s.capW, s.capH)
	if err != nil {
		r.abortScroll(fmt.Errorf("scroll capture: %w", err))
		return
	}
	s.inFlight = true
	s.frame = frame
	s.nextTick = time.Now().Add(s.interval)

	frame.SetBufferHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1BufferEvent) {
		if err := s.ensureCaptureBuffer(r, e); err != nil {
			r.abortScroll(err)
			return
		}
		if err := frame.Copy(s.wlBuf); err != nil {
			log.Error("scroll frame copy failed", "err", err)
		}
	})

	frame.SetFlagsHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1FlagsEvent) {
		s.yInverted = (e.Flags & 1) != 0
	})

	frame.SetReadyHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1ReadyEvent) {
		frame.Destroy()
		s.frame = nil
		s.inFlight = false
		s.failures = 0
		s.nextTick = time.Now().Add(s.interval)
		r.handleScrollFrame()
	})

	frame.SetFailedHandler(func(e wlr_screencopy.ZwlrScreencopyFrameV1FailedEvent) {
		frame.Destroy()
		s.frame = nil
		s.inFlight = false
		s.failures++
		s.nextTick = time.Now().Add(s.interval)
		if s.failures >= scrollMaxFailures {
			r.abortScroll(fmt.Errorf("screencopy failed %d consecutive times", s.failures))
		}
	})
}

func (s *scrollSession) ensureCaptureBuffer(r *RegionSelector, e wlr_screencopy.ZwlrScreencopyFrameV1BufferEvent) error {
	if s.buf != nil {
		if int(e.Width) != s.frameW || int(e.Height) != s.frameH || PixelFormat(e.Format) != s.format {
			return fmt.Errorf("output changed during scroll capture")
		}
		return nil
	}

	format := PixelFormat(e.Format)
	if int(e.Stride) < int(e.Width)*format.BytesPerPixel() {
		return fmt.Errorf("invalid stride from compositor: %d for width %d", e.Stride, e.Width)
	}

	buf, err := CreateShmBuffer(int(e.Width), int(e.Height), int(e.Stride))
	if err != nil {
		return fmt.Errorf("create scroll buffer: %w", err)
	}
	buf.Format = format

	pool, err := r.shm.CreatePool(buf.Fd(), int32(buf.Size()))
	if err != nil {
		buf.Close()
		return fmt.Errorf("create scroll pool: %w", err)
	}

	wlBuf, err := pool.CreateBuffer(0, int32(buf.Width), int32(buf.Height), int32(buf.Stride), e.Format)
	if err != nil {
		pool.Destroy()
		buf.Close()
		return fmt.Errorf("create scroll wl_buffer: %w", err)
	}

	s.buf = buf
	s.pool = pool
	s.wlBuf = wlBuf
	s.format = format
	s.frameW = int(e.Width)
	s.frameH = int(e.Height)
	return nil
}

func (r *RegionSelector) handleScrollFrame() {
	s := r.scroll
	if s == nil || s.buf == nil {
		return
	}

	rows, err := s.extractRows()
	if err != nil {
		r.abortScroll(err)
		return
	}

	if s.st == nil {
		s.st = newStitcher(s.frameW * 4)
	}

	cols := s.st.rowSamples(rows)
	sig := s.st.frameSig(rows)
	dup := duplicateFrame(sig, s.prevSig)
	s.prevSig = sig

	// moving content: recapture at compositor speed, the timer paces idle only
	if !dup {
		s.nextTick = time.Now()
	}

	var added int
	switch {
	case dup && s.unmatched:
		// settled somewhere unreachable: seam a new segment after a few ticks
		s.unmatchedTicks++
		if s.unmatchedTicks < scrollSeamTicks {
			return
		}
		var placed bool
		added, placed = s.st.pushFrame(rows, cols)
		if !placed {
			added = s.st.seamAppend(rows, cols)
		}
		s.prevPlaced = true
		s.unmatched = false
		s.unmatchedTicks = 0
	case dup && s.prevPlaced:
		return
	default:
		var placed bool
		added, placed = s.st.pushFrame(rows, cols)
		s.prevPlaced = placed
		s.unmatched = !placed
		s.unmatchedTicks = 0
	}

	if scrollDebug {
		log.Error("scroll frame", "dup", dup, "unmatched", s.unmatched,
			"placed", s.prevPlaced, "added", added, "canvas", s.st.rows(), "kept", s.kept)
	}
	if added == 0 {
		return
	}
	s.kept++
	if r.selection.surface != nil {
		r.updateScrollPreviewLayout(r.selection.surface)
		r.redrawSurface(r.selection.surface)
	}
}

var scrollDebug = os.Getenv("DMS_SCROLL_DEBUG") != ""

func (s *scrollSession) extractRows() ([]byte, error) {
	src := s.buf
	format := s.format

	if format.Is24Bit() {
		converted, newFormat, err := src.ConvertTo32Bit(format)
		if err != nil {
			return nil, fmt.Errorf("convert scroll frame: %w", err)
		}
		defer converted.Close()
		src = converted
		s.format = newFormat
	}

	rows := make([]byte, s.frameW*4*s.frameH)
	data := src.Data()
	for y := 0; y < s.frameH; y++ {
		srcY := y
		if s.yInverted {
			srcY = s.frameH - 1 - y
		}
		srcOff := srcY * src.Stride
		dstOff := y * s.frameW * 4
		if srcOff+s.frameW*4 > len(data) {
			continue
		}
		copy(rows[dstOff:dstOff+s.frameW*4], data[srcOff:srcOff+s.frameW*4])
	}
	return rows, nil
}

func (r *RegionSelector) finishScroll() {
	s := r.scroll
	if s == nil || s.st == nil || s.st.rows() == 0 {
		r.cancelled = true
		r.running = false
		return
	}

	buf, err := CreateShmBuffer(s.frameW, s.st.rows(), s.frameW*4)
	if err != nil {
		r.abortScroll(fmt.Errorf("create stitched buffer: %w", err))
		return
	}
	copy(buf.Data(), s.st.canvas)
	buf.Format = s.format

	r.capturedBuffer = buf
	r.capturedRegion = Region{
		X:      int32(s.holeX),
		Y:      int32(s.holeY),
		Width:  int32(s.holeW),
		Height: int32(s.holeH),
		Output: s.output.name,
	}
	// same convention as finishSelection or preselect breaks on scaled outputs
	r.result = Region{
		X:      int32(s.holeX) + s.output.x,
		Y:      int32(s.holeY) + s.output.y,
		Width:  int32(s.holeW),
		Height: int32(s.holeH),
		Output: s.output.name,
	}
	r.running = false
}

func (r *RegionSelector) abortScroll(err error) {
	if r.scroll == nil {
		r.scroll = &scrollSession{}
	}
	r.scroll.abortErr = err
	r.running = false
}

func (r *RegionSelector) cleanupScroll() {
	s := r.scroll
	if s == nil {
		return
	}
	if s.keysBound {
		_ = exec.Command("hyprctl", hyprlandUnbindScrollKeysArgs()...).Run()
	}
	if s.sigCh != nil {
		signal.Stop(s.sigCh)
	}
	if s.frame != nil {
		s.frame.Destroy()
	}
	if s.wlBuf != nil {
		s.wlBuf.Destroy()
	}
	if s.pool != nil {
		s.pool.Destroy()
	}
	if s.buf != nil {
		s.buf.Close()
	}
}
