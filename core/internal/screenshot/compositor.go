package screenshot

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sync"

	"github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_output_management"
	wlhelpers "github.com/duxlabs-dev/dux-shell/core/internal/wayland/client"
)

type Compositor int

const (
	CompositorUnknown Compositor = iota
	CompositorHyprland
	CompositorSway
	CompositorNiri
	CompositorScroll
	CompositorMiracle
	CompositorMango
	CompositorAqueous
	CompositorUmbriel
)

var detectedCompositor Compositor = -1

func DetectCompositor() Compositor {
	if detectedCompositor >= 0 {
		return detectedCompositor
	}

	candidates := []struct {
		socket     string
		needsStat  bool
		compositor Compositor
	}{
		{os.Getenv("AQUEOUS_SOCKET"), true, CompositorAqueous},
		{os.Getenv("MANGO_INSTANCE_SIGNATURE"), true, CompositorMango},
		{os.Getenv("UMBRIEL_SOCKET"), true, CompositorUmbriel},
		{os.Getenv("NIRI_SOCKET"), true, CompositorNiri},
		{os.Getenv("SCROLLSOCK"), true, CompositorScroll},
		{os.Getenv("MIRACLESOCK"), true, CompositorMiracle},
		{os.Getenv("SWAYSOCK"), true, CompositorSway},
		{os.Getenv("HYPRLAND_INSTANCE_SIGNATURE"), false, CompositorHyprland},
	}

	// A stale env var from a previous session must not mask the live compositor
	for _, c := range candidates {
		if c.socket == "" {
			continue
		}
		if c.needsStat {
			if _, err := os.Stat(c.socket); err != nil {
				continue
			}
		}
		detectedCompositor = c.compositor
		return detectedCompositor
	}

	detectedCompositor = CompositorUnknown
	return detectedCompositor
}

type WindowGeometry struct {
	X       int32
	Y       int32
	Width   int32
	Height  int32
	Output  string
	Scale   float64
	OutputX int32
	OutputY int32
}

func GetActiveWindow() (*WindowGeometry, error) {
	switch DetectCompositor() {
	case CompositorHyprland:
		return getHyprlandActiveWindow()
	case CompositorMango:
		return getMangoActiveWindow()
	case CompositorAqueous:
		model, err := aqueousSnapshot(context.Background())
		if err != nil {
			return nil, err
		}
		return aqueousWindowGeometry(model, "")
	default:
		return nil, fmt.Errorf("window capture requires Hyprland, Mango, niri, or Aqueous")
	}
}

type hyprlandWindow struct {
	At   [2]int32 `json:"at"`
	Size [2]int32 `json:"size"`
}

func getHyprlandActiveWindow() (*WindowGeometry, error) {
	output, err := exec.Command("hyprctl", "-j", "activewindow").Output()
	if err != nil {
		return nil, fmt.Errorf("hyprctl activewindow: %w", err)
	}

	var win hyprlandWindow
	if err := json.Unmarshal(output, &win); err != nil {
		return nil, fmt.Errorf("parse activewindow: %w", err)
	}

	if win.Size[0] <= 0 || win.Size[1] <= 0 {
		return nil, fmt.Errorf("no active window")
	}

	return &WindowGeometry{
		X:      win.At[0],
		Y:      win.At[1],
		Width:  win.Size[0],
		Height: win.Size[1],
	}, nil
}

type hyprlandMonitor struct {
	Name      string  `json:"name"`
	X         int32   `json:"x"`
	Y         int32   `json:"y"`
	Width     int32   `json:"width"`
	Height    int32   `json:"height"`
	Scale     float64 `json:"scale"`
	Transform int32   `json:"transform"`
	Focused   bool    `json:"focused"`
}

func GetHyprlandMonitorScale(name string) float64 {
	output, err := exec.Command("hyprctl", "-j", "monitors").Output()
	if err != nil {
		return 0
	}

	var monitors []hyprlandMonitor
	if err := json.Unmarshal(output, &monitors); err != nil {
		return 0
	}

	for _, m := range monitors {
		if m.Name == name {
			return m.Scale
		}
	}
	return 0
}

// !TODO: remove with the frameInLogicalOrientation version fallback
var hyprlandVersion = sync.OnceValues(func() (int, int) {
	output, err := exec.Command("hyprctl", "-j", "version").Output()
	if err != nil {
		return 0, 0
	}
	var info struct {
		Version string `json:"version"`
	}
	if err := json.Unmarshal(output, &info); err != nil {
		return 0, 0
	}
	var major, minor int
	fmt.Sscanf(info.Version, "%d.%d", &major, &minor)
	return major, minor
})

func hyprlandVersionAtLeast(major, minor int) bool {
	haveMajor, haveMinor := hyprlandVersion()
	if haveMajor != major {
		return haveMajor > major
	}
	return haveMinor >= minor
}

func getHyprlandFocusedMonitor() string {
	output, err := exec.Command("hyprctl", "-j", "monitors").Output()
	if err != nil {
		return ""
	}

	var monitors []hyprlandMonitor
	if err := json.Unmarshal(output, &monitors); err != nil {
		return ""
	}

	for _, m := range monitors {
		if m.Focused {
			return m.Name
		}
	}
	return ""
}

func GetHyprlandMonitorGeometry(name string) (x, y, w, h int32, ok bool) {
	output, err := exec.Command("hyprctl", "-j", "monitors").Output()
	if err != nil {
		return 0, 0, 0, 0, false
	}
	return hyprlandMonitorGeometry(output, name)
}

func hyprlandMonitorGeometry(monitorsJSON []byte, name string) (x, y, w, h int32, ok bool) {
	var monitors []hyprlandMonitor
	if err := json.Unmarshal(monitorsJSON, &monitors); err != nil {
		return 0, 0, 0, 0, false
	}

	for _, m := range monitors {
		if m.Name != name {
			continue
		}
		// hyprctl reports width/height before the transform is applied
		modeW, modeH := m.Width, m.Height
		if m.Transform%2 == 1 {
			modeW, modeH = modeH, modeW
		}
		logicalW := int32(float64(modeW) / m.Scale)
		logicalH := int32(float64(modeH) / m.Scale)
		return m.X, m.Y, logicalW, logicalH, true
	}
	return 0, 0, 0, 0, false
}

type swayWorkspace struct {
	Output  string `json:"output"`
	Focused bool   `json:"focused"`
}

func getSwayFocusedMonitor() string {
	output, err := exec.Command("swaymsg", "-t", "get_workspaces").Output()
	if err != nil {
		return ""
	}

	var workspaces []swayWorkspace
	if err := json.Unmarshal(output, &workspaces); err != nil {
		return ""
	}

	for _, ws := range workspaces {
		if ws.Focused {
			return ws.Output
		}
	}
	return ""
}

func getScrollFocusedMonitor() string {
	output, err := exec.Command("scrollmsg", "-t", "get_workspaces").Output()
	if err != nil {
		return ""
	}

	var workspaces []swayWorkspace
	if err := json.Unmarshal(output, &workspaces); err != nil {
		return ""
	}

	for _, ws := range workspaces {
		if ws.Focused {
			return ws.Output
		}
	}
	return ""
}

func getMiracleFocusedMonitor() string {
	output, err := exec.Command("miraclemsg", "-t", "get_workspaces").Output()
	if err != nil {
		return ""
	}

	var workspaces []swayWorkspace
	if err := json.Unmarshal(output, &workspaces); err != nil {
		return ""
	}

	for _, ws := range workspaces {
		if ws.Focused {
			return ws.Output
		}
	}
	return ""
}

type mangoMonitor struct {
	Name   string  `json:"name"`
	Active bool    `json:"active"`
	X      int32   `json:"x"`
	Y      int32   `json:"y"`
	Scale  float64 `json:"scale"`
}

func getMangoMonitors() []mangoMonitor {
	output, err := exec.Command("mmsg", "get", "all-monitors").Output()
	if err != nil {
		return nil
	}

	var data struct {
		Monitors []mangoMonitor `json:"monitors"`
	}
	if err := json.Unmarshal(output, &data); err != nil {
		return nil
	}
	return data.Monitors
}

func getMangoFocusedMonitor() string {
	for _, m := range getMangoMonitors() {
		if m.Active {
			return m.Name
		}
	}
	return ""
}

type mangoClient struct {
	Monitor   string `json:"monitor"`
	IsFocused bool   `json:"is_focused"`
	X         int32  `json:"x"`
	Y         int32  `json:"y"`
	Width     int32  `json:"width"`
	Height    int32  `json:"height"`
}

func getMangoActiveWindow() (*WindowGeometry, error) {
	output, err := exec.Command("mmsg", "get", "all-clients").Output()
	if err != nil {
		return nil, fmt.Errorf("mmsg get all-clients: %w", err)
	}

	var data struct {
		Clients []mangoClient `json:"clients"`
	}
	if err := json.Unmarshal(output, &data); err != nil {
		return nil, fmt.Errorf("parse all-clients: %w", err)
	}

	for _, c := range data.Clients {
		if !c.IsFocused {
			continue
		}
		if c.Width <= 0 || c.Height <= 0 {
			return nil, fmt.Errorf("no active window")
		}

		geom := &WindowGeometry{
			X:      c.X,
			Y:      c.Y,
			Width:  c.Width,
			Height: c.Height,
			Output: c.Monitor,
			Scale:  1.0,
		}
		for _, m := range getMangoMonitors() {
			if m.Name != c.Monitor {
				continue
			}
			geom.OutputX = m.X
			geom.OutputY = m.Y
			if m.Scale > 0 {
				geom.Scale = m.Scale
			}
			break
		}
		return geom, nil
	}

	return nil, fmt.Errorf("no focused window")
}

type niriWorkspace struct {
	Output    string `json:"output"`
	IsFocused bool   `json:"is_focused"`
}

func getNiriFocusedMonitor() string {
	output, err := exec.Command("niri", "msg", "-j", "workspaces").Output()
	if err != nil {
		return ""
	}

	var workspaces []niriWorkspace
	if err := json.Unmarshal(output, &workspaces); err != nil {
		return ""
	}

	for _, ws := range workspaces {
		if ws.IsFocused {
			return ws.Output
		}
	}
	return ""
}

type umbrielWorkspace struct {
	Output  string `json:"output"`
	Focused bool   `json:"focused"`
}

func getUmbrielFocusedMonitor() string {
	output, err := exec.Command("umbriel", "workspaces", "--json").Output()
	if err != nil {
		return ""
	}

	var workspaces []umbrielWorkspace
	if err := json.Unmarshal(output, &workspaces); err != nil {
		return ""
	}

	for _, ws := range workspaces {
		if ws.Focused {
			return ws.Output
		}
	}
	return ""
}

func GetFocusedMonitor() string {
	switch DetectCompositor() {
	case CompositorAqueous:
		name, _ := aqueousFocusedOutput("")
		return name
	case CompositorHyprland:
		return getHyprlandFocusedMonitor()
	case CompositorSway:
		return getSwayFocusedMonitor()
	case CompositorScroll:
		return getScrollFocusedMonitor()
	case CompositorMiracle:
		return getMiracleFocusedMonitor()
	case CompositorNiri:
		return getNiriFocusedMonitor()
	case CompositorMango:
		return getMangoFocusedMonitor()
	case CompositorUmbriel:
		return getUmbrielFocusedMonitor()
	}
	return ""
}

type outputInfo struct {
	x, y      int32
	scale     float64
	transform int32
}

func getAllOutputInfos() map[string]*outputInfo {
	display, err := client.Connect("")
	if err != nil {
		return nil
	}
	ctx := display.Context()
	defer ctx.Close()

	registry, err := display.GetRegistry()
	if err != nil {
		return nil
	}

	var outputManager *wlr_output_management.ZwlrOutputManagerV1

	registry.SetGlobalHandler(func(e client.RegistryGlobalEvent) {
		if e.Interface == wlr_output_management.ZwlrOutputManagerV1InterfaceName {
			mgr := wlr_output_management.NewZwlrOutputManagerV1(ctx)
			version := min(e.Version, 4)
			if err := registry.Bind(e.Name, e.Interface, version, mgr); err == nil {
				outputManager = mgr
			}
		}
	})

	if err := wlhelpers.Roundtrip(display, ctx); err != nil {
		return nil
	}

	if outputManager == nil {
		return nil
	}

	type headState struct {
		name      string
		x, y      int32
		scale     float64
		transform int32
	}
	heads := make(map[*wlr_output_management.ZwlrOutputHeadV1]*headState)
	done := false

	outputManager.SetHeadHandler(func(e wlr_output_management.ZwlrOutputManagerV1HeadEvent) {
		state := &headState{}
		heads[e.Head] = state
		e.Head.SetNameHandler(func(ne wlr_output_management.ZwlrOutputHeadV1NameEvent) {
			state.name = ne.Name
		})
		e.Head.SetPositionHandler(func(pe wlr_output_management.ZwlrOutputHeadV1PositionEvent) {
			state.x = pe.X
			state.y = pe.Y
		})
		e.Head.SetScaleHandler(func(se wlr_output_management.ZwlrOutputHeadV1ScaleEvent) {
			state.scale = se.Scale
		})
		e.Head.SetTransformHandler(func(te wlr_output_management.ZwlrOutputHeadV1TransformEvent) {
			state.transform = te.Transform
		})
	})
	outputManager.SetDoneHandler(func(e wlr_output_management.ZwlrOutputManagerV1DoneEvent) {
		done = true
	})

	for !done {
		if err := ctx.Dispatch(); err != nil {
			return nil
		}
	}

	result := make(map[string]*outputInfo, len(heads))
	for _, state := range heads {
		if state.name == "" {
			continue
		}
		result[state.name] = &outputInfo{
			x:         state.x,
			y:         state.y,
			scale:     state.scale,
			transform: state.transform,
		}
	}
	return result
}
