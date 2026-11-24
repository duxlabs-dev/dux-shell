package location

import (
	"sync"

	"github.com/duxlabs-dev/dux-shell/core/internal/geolocation"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/pubsub"
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

	subscribers pubsub.Broker[State]
	dirty       chan struct{}
	notifierWg  sync.WaitGroup
}
