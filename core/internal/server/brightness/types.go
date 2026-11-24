package brightness

import (
	"sync"
	"sync/atomic"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/pubsub"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wayland"
)

type DeviceClass string

const (
	ClassBacklight DeviceClass = "backlight"
	ClassLED       DeviceClass = "leds"
	ClassDDC       DeviceClass = "ddc"
	ClassSoftware  DeviceClass = "software"
)

type Device struct {
	Class          DeviceClass `json:"class"`
	ID             string      `json:"id"`
	Name           string      `json:"name"`
	Current        int         `json:"current"`
	Max            int         `json:"max"`
	CurrentPercent int         `json:"currentPercent"`
	Backend        string      `json:"backend"`
}

type State struct {
	Devices []Device `json:"devices"`
}

type DeviceUpdate struct {
	Device Device `json:"device"`
}

type Backend interface {
	Rescan() error
	GetDevices() ([]Device, error)
	SetBrightnessWithExponent(id string, percent int, exponential bool, exponent float64) error
}

type deviceMonitor interface {
	Close()
}

type Manager struct {
	logindBackend *LogindBackend
	sysfsBackend  *SysfsBackend
	nativeBackend Backend
	ddcBackend    *DDCBackend
	monitor       deviceMonitor
	gamma         atomic.Pointer[wayland.Manager]

	logindReady bool
	nativeReady bool
	ddcReady    bool
	// Until DDC has probed, every external monitor looks uncovered.
	ddcSettled atomic.Bool

	exponential bool

	stateMutex sync.RWMutex
	state      State

	subscribers       pubsub.Broker[State]
	updateSubscribers pubsub.Broker[DeviceUpdate]

	broadcastMutex   sync.Mutex
	broadcastTimer   *time.Timer
	broadcastPending bool
	pendingDeviceID  string

	stopChan chan struct{}
}

type SysfsBackend struct {
	basePath string
	classes  []string

	deviceCache syncmap.Map[string, *sysfsDevice]
}

type sysfsDevice struct {
	class         DeviceClass
	id            string
	name          string
	maxBrightness int
	minValue      int
}

type DDCBackend struct {
	devices syncmap.Map[string, *ddcDevice]

	scanMutex    sync.Mutex
	lastScan     time.Time
	scanInterval time.Duration

	debounceMutex   sync.Mutex
	debounceTimers  map[string]*time.Timer
	debouncePending map[string]ddcPendingSet
	debounceWg      sync.WaitGroup

	ioMutex   sync.Mutex
	onReread  func()
	stop      chan struct{}
	closeOnce sync.Once
}

type ddcPendingSet struct {
	percent  int
	callback func()
}

type ddcDevice struct {
	bus            int
	addr           int
	id             string
	name           string
	adapter        string
	connector      string
	max            int
	lastBrightness int
}

type ddcCapability struct {
	vcp     byte
	max     int
	current int
}

func (m *Manager) Subscribe(id string) chan State {
	return m.subscribers.Subscribe(id)
}

func (m *Manager) Unsubscribe(id string, ch chan State) {
	m.subscribers.Unsubscribe(id, ch)
}

func (m *Manager) SubscribeUpdates(id string) chan DeviceUpdate {
	return m.updateSubscribers.Subscribe(id)
}

func (m *Manager) UnsubscribeUpdates(id string, ch chan DeviceUpdate) {
	m.updateSubscribers.Unsubscribe(id, ch)
}

func (m *Manager) NotifySubscribers() {
	m.stateMutex.RLock()
	state := m.state
	m.stateMutex.RUnlock()

	m.subscribers.Publish(state)
}

func (m *Manager) GetState() State {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	return m.state
}

func (m *Manager) Close() {
	close(m.stopChan)

	m.subscribers.Close()
	m.updateSubscribers.Close()

	if m.monitor != nil {
		m.monitor.Close()
	}

	if m.logindBackend != nil {
		m.logindBackend.Close()
	}

	if m.ddcBackend != nil {
		m.ddcBackend.Close()
	}
}
