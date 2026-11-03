package wlroutput

import (
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestStateChanged_OneNil(t *testing.T) {
	s := &State{Serial: 1}
	assert.True(t, stateChanged(s, nil))
	assert.True(t, stateChanged(nil, s))
}

func TestStateChanged_SerialDiffers(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{}}
	b := &State{Serial: 2, Outputs: []Output{}}
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_OutputCountDiffers(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1"}}}
	b := &State{Serial: 1, Outputs: []Output{}}
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_OutputNameDiffers(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", Enabled: true}}}
	b := &State{Serial: 1, Outputs: []Output{{Name: "HDMI-A-1", Enabled: true}}}
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_OutputEnabledDiffers(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", Enabled: true}}}
	b := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", Enabled: false}}}
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_OutputPositionDiffers(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", X: 0, Y: 0}}}
	b := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", X: 1920, Y: 0}}}
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_OutputTransformDiffers(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", Transform: 0}}}
	b := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", Transform: 1}}}
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_OutputScaleDiffers(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", Scale: 1.0}}}
	b := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", Scale: 2.0}}}
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_OutputAdaptiveSyncDiffers(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", AdaptiveSync: 0}}}
	b := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", AdaptiveSync: 1}}}
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_CurrentModeNilVsNonNil(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", CurrentMode: nil}}}
	b := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", CurrentMode: &OutputMode{Width: 1920}}}}
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_CurrentModeDiffers(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{
		Name:        "eDP-1",
		CurrentMode: &OutputMode{Width: 1920, Height: 1080, Refresh: 60000},
	}}}
	b := &State{Serial: 1, Outputs: []Output{{
		Name:        "eDP-1",
		CurrentMode: &OutputMode{Width: 2560, Height: 1440, Refresh: 60000},
	}}}
	assert.True(t, stateChanged(a, b))

	b.Outputs[0].CurrentMode.Width = 1920
	b.Outputs[0].CurrentMode.Height = 1080
	b.Outputs[0].CurrentMode.Refresh = 144000
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_ModesLengthDiffers(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", Modes: []OutputMode{{Width: 1920}}}}}
	b := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", Modes: []OutputMode{{Width: 1920}, {Width: 1280}}}}}
	assert.True(t, stateChanged(a, b))
}

func TestStateChanged_Equal(t *testing.T) {
	mode := OutputMode{Width: 1920, Height: 1080, Refresh: 60000, Preferred: true}
	a := &State{
		Serial: 5,
		Outputs: []Output{{
			Name:           "eDP-1",
			Description:    "Built-in display",
			Make:           "BOE",
			Model:          "0x0ABC",
			SerialNumber:   "12345",
			PhysicalWidth:  309,
			PhysicalHeight: 174,
			Enabled:        true,
			X:              0,
			Y:              0,
			Transform:      0,
			Scale:          1.0,
			CurrentMode:    &mode,
			Modes:          []OutputMode{mode},
			AdaptiveSync:   0,
		}},
	}
	b := &State{
		Serial: 5,
		Outputs: []Output{{
			Name:           "eDP-1",
			Description:    "Built-in display",
			Make:           "BOE",
			Model:          "0x0ABC",
			SerialNumber:   "12345",
			PhysicalWidth:  309,
			PhysicalHeight: 174,
			Enabled:        true,
			X:              0,
			Y:              0,
			Transform:      0,
			Scale:          1.0,
			CurrentMode:    &mode,
			Modes:          []OutputMode{mode},
			AdaptiveSync:   0,
		}},
	}
	assert.False(t, stateChanged(a, b))
}

func TestManager_ConcurrentGetState(t *testing.T) {
	m := &Manager{
		state: &State{
			Serial:  1,
			Outputs: []Output{{Name: "eDP-1", Enabled: true}},
		},
	}

	var wg sync.WaitGroup
	const goroutines = 50
	const iterations = 100

	for range goroutines / 2 {
		wg.Go(func() {
			for range iterations {
				s := m.GetState()
				_ = s.Serial
				_ = s.Outputs
			}
		})
	}

	for i := range goroutines / 2 {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for j := range iterations {
				m.stateMutex.Lock()
				m.state = &State{
					Serial:  uint32(j),
					Outputs: []Output{{Name: "eDP-1", Scale: float64(j % 3)}},
				}
				m.stateMutex.Unlock()
			}
		}(i)
	}

	wg.Wait()
}

func TestManager_ConcurrentSubscriberAccess(t *testing.T) {
	m := &Manager{
		stopChan: make(chan struct{}),
		dirty:    make(chan struct{}, 1),
	}

	var wg sync.WaitGroup
	const goroutines = 20

	for i := range goroutines {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			subID := string(rune('a' + id))
			ch := m.Subscribe(subID)
			assert.NotNil(t, ch)
			m.Unsubscribe(subID)
		}(i)
	}

	wg.Wait()
}

func TestManager_NotifySubscribersNonBlocking(t *testing.T) {
	m := &Manager{
		dirty: make(chan struct{}, 1),
	}

	for range 10 {
		m.notifySubscribers()
	}

	assert.Len(t, m.dirty, 1)
}

func TestManager_PostQueueFull(t *testing.T) {
	m := &Manager{
		cmdq:     make(chan cmd, 2),
		stopChan: make(chan struct{}),
	}

	m.post(func() {})
	m.post(func() {})
	m.post(func() {})
	m.post(func() {})

	assert.Len(t, m.cmdq, 2)
}

func TestManager_GetStateNilState(t *testing.T) {
	m := &Manager{}

	s := m.GetState()
	assert.NotNil(t, s.Outputs)
	assert.Equal(t, uint32(0), s.Serial)
}

func TestStateChanged_BothCurrentModeNil(t *testing.T) {
	a := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", CurrentMode: nil}}}
	b := &State{Serial: 1, Outputs: []Output{{Name: "eDP-1", CurrentMode: nil}}}
	assert.False(t, stateChanged(a, b))
}
