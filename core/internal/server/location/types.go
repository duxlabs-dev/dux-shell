package location

import (
	"sync"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/geolocation"
)

type State struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

type Manager struct {
	state      *State
	stateMutex sync.RWMutex

	client    geolocation.Client
	startOnce sync.Once

	stopChan chan struct{}
	sigWG    sync.WaitGroup

	subscribers  syncmap.Map[string, chan State]
	dirty        chan struct{}
	notifierWg   sync.WaitGroup
	lastNotified *State
}
