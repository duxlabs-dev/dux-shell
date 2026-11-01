package wlroutput

import (
	"sync"

	"github.com/duxlabs-dev/dux-go/syncmap"
	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_output_management"
)

type OutputMode struct {
	Width     int32  `json:"width"`
	Height    int32  `json:"height"`
	Refresh   int32  `json:"refresh"`
	Preferred bool   `json:"preferred"`
	ID        uint32 `json:"id"`
}

type Output struct {
	Name                  string       `json:"name"`
	Description           string       `json:"description"`
	Make                  string       `json:"make"`
	Model                 string       `json:"model"`
	SerialNumber          string       `json:"serialNumber"`
	PhysicalWidth         int32        `json:"physicalWidth"`
	PhysicalHeight        int32        `json:"physicalHeight"`
	Enabled               bool         `json:"enabled"`
	X                     int32        `json:"x"`
	Y                     int32        `json:"y"`
	Transform             int32        `json:"transform"`
	Scale                 float64      `json:"scale"`
	CurrentMode           *OutputMode  `json:"currentMode"`
	Modes                 []OutputMode `json:"modes"`
	AdaptiveSync          uint32       `json:"adaptiveSync"`
	AdaptiveSyncSupported bool         `json:"adaptiveSyncSupported"`
	ID                    uint32       `json:"id"`
}

type State struct {
	Outputs []Output `json:"outputs"`
	Serial  uint32   `json:"serial"`
}

type cmd struct {
	fn func()
}

type Manager struct {
	display  wlclient.WaylandDisplay
	ctx      *wlclient.Context
	registry *wlclient.Registry
	manager  *wlr_output_management.ZwlrOutputManagerV1

	heads syncmap.Map[uint32, *headState]
	modes syncmap.Map[uint32, *modeState]

	serial uint32

	wlMutex  sync.Mutex
	cmdq     chan cmd
	stopChan chan struct{}
	wg       sync.WaitGroup

	subscribers  syncmap.Map[string, chan State]
	dirty        chan struct{}
	notifierWg   sync.WaitGroup
	lastNotified *State

	stateMutex sync.RWMutex
	state      *State

	fatalError chan error
}

type headState struct {
	id                    uint32
	handle                *wlr_output_management.ZwlrOutputHeadV1
	name                  string
	description           string
	make                  string
	model                 string
	serialNumber          string
	physicalWidth         int32
	physicalHeight        int32
	enabled               bool
	x                     int32
	y                     int32
	transform             int32
	scale                 float64
	currentModeID         uint32
	modeIDs               []uint32
	adaptiveSync          uint32
	adaptiveSyncSupported bool
	finished              bool
	ready                 bool
}

type modeState struct {
	id        uint32
	handle    *wlr_output_management.ZwlrOutputModeV1
	width     int32
	height    int32
	refresh   int32
	preferred bool
	finished  bool
}

func (m *Manager) GetState() State {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	if m.state == nil {
		return State{
			Outputs: []Output{},
			Serial:  0,
		}
	}
	stateCopy := *m.state
	return stateCopy
}

func (m *Manager) Subscribe(id string) chan State {
	ch := make(chan State, 64)

	m.subscribers.Store(id, ch)

	return ch
}

func (m *Manager) Unsubscribe(id string) {

	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)

	}

}

func (m *Manager) notifySubscribers() {
	select {
	case m.dirty <- struct{}{}:
	default:
	}
}

func (m *Manager) FatalError() <-chan error {
	return m.fatalError
}

func stateChanged(old, new *State) bool {
	if old == nil || new == nil {
		return true
	}
	if old.Serial != new.Serial {
		return true
	}
	if len(old.Outputs) != len(new.Outputs) {
		return true
	}
	for i := range new.Outputs {
		if i >= len(old.Outputs) {
			return true
		}
		oldOut := &old.Outputs[i]
		newOut := &new.Outputs[i]
		if oldOut.Name != newOut.Name || oldOut.Enabled != newOut.Enabled {
			return true
		}
		if oldOut.X != newOut.X || oldOut.Y != newOut.Y {
			return true
		}
		if oldOut.Transform != newOut.Transform || oldOut.Scale != newOut.Scale {
			return true
		}
		if oldOut.AdaptiveSync != newOut.AdaptiveSync || oldOut.AdaptiveSyncSupported != newOut.AdaptiveSyncSupported {
			return true
		}
		if (oldOut.CurrentMode == nil) != (newOut.CurrentMode == nil) {
			return true
		}
		if oldOut.CurrentMode != nil && newOut.CurrentMode != nil {
			if oldOut.CurrentMode.Width != newOut.CurrentMode.Width ||
				oldOut.CurrentMode.Height != newOut.CurrentMode.Height ||
				oldOut.CurrentMode.Refresh != newOut.CurrentMode.Refresh {
				return true
			}
		}
		if len(oldOut.Modes) != len(newOut.Modes) {
			return true
		}
	}
	return false
}
