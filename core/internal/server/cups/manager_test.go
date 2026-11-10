package cups

import (
	"errors"
	"fmt"
	"sync"
	"testing"

	mocks_cups "github.com/duxlabs-dev/dux-shell/core/internal/mocks/cups"
	"github.com/stretchr/testify/assert"
)

// mirrors the real managers: eventChan guarded by mu, conn/running deliberately
// unsynchronized so overlapping Start/Stop trips the race detector
type stubSubscription struct {
	mu      sync.Mutex
	events  chan SubscriptionEvent
	conn    *int
	running bool
}

func (s *stubSubscription) Start() error {
	if s.running {
		return errors.New("already running")
	}
	s.running = true

	s.mu.Lock()
	s.events = make(chan SubscriptionEvent)
	s.mu.Unlock()

	v := 0
	s.conn = &v
	*s.conn++

	return nil
}

func (s *stubSubscription) Stop() {
	if !s.running {
		return
	}
	s.running = false
	s.conn = nil

	s.mu.Lock()
	close(s.events)
	s.mu.Unlock()
}

func (s *stubSubscription) Events() <-chan SubscriptionEvent {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.events
}

func TestManager_SubscribeUnsubscribeRace(t *testing.T) {
	m := NewTestManager(mocks_cups.NewMockCUPSClientInterface(t), nil)
	m.subscription = &stubSubscription{}

	var wg sync.WaitGroup
	for i := range 8 {
		wg.Go(func() {
			id := fmt.Sprintf("client-%d", i)
			for range 50 {
				m.Subscribe(id)
				m.Unsubscribe(id)
			}
		})
	}
	wg.Wait()
}

func TestStateChanged(t *testing.T) {
	tests := []struct {
		name     string
		oldState *CUPSState
		newState *CUPSState
		want     bool
	}{
		{
			name: "no change",
			oldState: &CUPSState{
				Printers: map[string]*Printer{
					"p1": {Name: "p1", State: "idle"},
				},
			},
			newState: &CUPSState{
				Printers: map[string]*Printer{
					"p1": {Name: "p1", State: "idle"},
				},
			},
			want: false,
		},
		{
			name: "state changed",
			oldState: &CUPSState{
				Printers: map[string]*Printer{
					"p1": {Name: "p1", State: "idle"},
				},
			},
			newState: &CUPSState{
				Printers: map[string]*Printer{
					"p1": {Name: "p1", State: "processing"},
				},
			},
			want: true,
		},
		{
			name: "printer added",
			oldState: &CUPSState{
				Printers: map[string]*Printer{},
			},
			newState: &CUPSState{
				Printers: map[string]*Printer{
					"p1": {Name: "p1", State: "idle"},
				},
			},
			want: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := stateChanged(tt.oldState, tt.newState)
			assert.Equal(t, tt.want, got)
		})
	}
}
