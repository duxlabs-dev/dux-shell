package wayland

import (
	"maps"
	"math"
	"slices"
	"sync"
	"sync/atomic"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/geolocation"
	"github.com/duxlabs-dev/dux-shell/core/internal/icc"
	"github.com/godbus/dbus/v5"
)

// outputBrightnessFloor is the ramp scale at 0%, so a software-dimmed output
// stays readable instead of going black.
const outputBrightnessFloor = 0.1

type GammaState int

const (
	StateNormal GammaState = iota
	StateTransition
	StateStatic
)

type Config struct {
	Outputs           []string
	LowTemp           int
	HighTemp          int
	Latitude          *float64
	Longitude         *float64
	UseIPLocation     bool
	ManualSunrise     *time.Time
	ManualSunset      *time.Time
	ManualDuration    *time.Duration
	Gamma             float64
	Contrast          float64
	Enabled           bool
	ElevationTwilight float64
	ElevationDaylight float64
	ICCProfiles       map[string]string `json:"iccProfiles,omitempty"`      // outputName -> file in ICCProfilesDir, or an absolute path
	OutputTemps       map[string]int    `json:"outputTemps,omitempty"`      // outputName -> per-output color temperature (K)
	OutputBrightness  map[string]int    `json:"outputBrightness,omitempty"` // outputName -> software brightness percent, below 100 only
}

type State struct {
	Config         Config                `json:"config"`
	CurrentTemp    int                   `json:"currentTemp"`
	NextTransition time.Time             `json:"nextTransition"`
	SunriseTime    time.Time             `json:"sunriseTime"`
	SunsetTime     time.Time             `json:"sunsetTime"`
	DawnTime       time.Time             `json:"dawnTime"`
	NightTime      time.Time             `json:"nightTime"`
	IsDay          bool                  `json:"isDay"`
	SunPosition    float64               `json:"sunPosition"`
	ICCProfiles    map[string]*ICCStatus `json:"iccProfiles"` // outputName -> status
	OutputTemps    map[string]int        `json:"outputTemps"` // outputName -> current temp
	Outputs        []string              `json:"outputs"`     // connected output names, sorted
	GammaRefused   []string              `json:"gammaRefused,omitempty"`
}

// ICCStatus represents the ICC profile status for a single output.
type ICCStatus struct {
	Path        string `json:"path"`        // ICC file path
	Description string `json:"description"` // ICC profile description
	Version     string `json:"version"`     // ICC version
	ColorSpace  string `json:"colorSpace"`  // e.g., "RGB"
	HasVCGT     bool   `json:"hasVCGT"`     // has video card gamma table
	Active      bool   `json:"active"`      // currently applied

	// Descriptive profile metadata, surfaced in the UI so a profile can be
	// identified without leaving the settings page.
	Class          string  `json:"class,omitempty"`          // "mntr", "scnr", "prtr"
	TRCKind        string  `json:"trcKind,omitempty"`        // "identity", "gamma", "table", "mixed"
	TRCGamma       float64 `json:"trcGamma,omitempty"`       // when TRCKind is "gamma"
	TRCEntries     int     `json:"trcEntries,omitempty"`     // when TRCKind is "table"
	VCGTChannels   int     `json:"vcgtChannels,omitempty"`   // channels in the video card gamma table
	VCGTEntries    int     `json:"vcgtEntries,omitempty"`    // entries per channel
	WhitePointX    float64 `json:"whitePointX,omitempty"`    // chromaticity x
	WhitePointY    float64 `json:"whitePointY,omitempty"`    // chromaticity y
	WhitePointCCT  int     `json:"whitePointCCT,omitempty"`  // correlated color temperature (K)
	WhitePointName string  `json:"whitePointName,omitempty"` // "D50", "D65", ...
	Size           int64   `json:"size,omitempty"`           // profile file size in bytes
	Modified       int64   `json:"modified,omitempty"`       // profile file mtime, unix seconds
}

type cmd struct {
	fn func()
}

type sunSchedule struct {
	times         SunTimes
	condition     SunCondition
	dawnStepTime  time.Duration
	nightStepTime time.Duration
	calcDay       time.Time
}

type Manager struct {
	config      Config
	configMutex sync.RWMutex
	state       *State
	stateMutex  sync.RWMutex

	display             wlclient.WaylandDisplay
	ctx                 *wlclient.Context
	registry            *wlclient.Registry
	gammaControl        any
	availableOutputs    []*wlclient.Output
	availOutputsMu      sync.RWMutex
	outputRegNames      syncmap.Map[uint32, uint32]
	outputNames         syncmap.Map[uint32, string] // outputID -> wl_output name string (e.g., "DP-1")
	outputs             syncmap.Map[uint32, *outputState]
	controlsInitialized bool
	connectionDead      atomic.Bool

	// The per-output ICC fields (iccPath, iccProfile, outputTemp) are only
	// touched by the wayland actor goroutine. The published snapshot below is
	// what the IPC handlers, the CLI and the scheduler read, so they never
	// reach into outputState from another goroutine.
	iccStateMutex sync.RWMutex
	iccStatus     map[string]*ICCStatus // outputName -> status
	iccTemps      map[string]int        // outputName -> per-output temperature (K)
	iccRefused    []string              // outputs whose gamma control the compositor refused, sorted

	cmdq  chan cmd
	alive bool

	stopChan      chan struct{}
	updateTrigger chan struct{}
	wg            sync.WaitGroup

	schedule      sunSchedule
	scheduleMutex sync.RWMutex
	gammaState    GammaState

	cachedIPLat   *float64
	cachedIPLon   *float64
	locationMutex sync.RWMutex

	subscribers  syncmap.Map[string, chan State]
	dirty        chan struct{}
	notifierWg   sync.WaitGroup
	lastNotified *State

	dbusConn   *dbus.Conn
	dbusSignal chan *dbus.Signal

	geoClient geolocation.Client
}

type outputState struct {
	id           uint32
	registryName uint32
	output       *wlclient.Output
	gammaControl any
	rampSize     uint32
	failed       bool
	isVirtual    bool
	retryCount   int
	lastFailTime time.Time
	lastTemp     int
	lastGamma    float64
	lastContrast float64
	iccPath      string       // path to ICC profile file, empty if not set
	iccProfile   *icc.Profile // cached parsed ICC profile (nil if not loaded)
	outputTemp   int          // per-output color temperature (K), 0 = use global temp
	dimScale     float64      // software brightness ramp scale, 0 = full
	gammaRefused bool         // the latest control failed before reporting gamma_size
}

// markFailed records a failed control. A failure before gamma_size is the
// compositor refusing the output (another client holds it, or it is not
// allowed there), as opposed to a control lost after it worked.
func (out *outputState) markFailed(now time.Time) {
	out.gammaRefused = out.rampSize == 0
	out.failed = true
	out.rampSize = 0
	out.retryCount++
	out.lastFailTime = now
}

func DefaultConfig() Config {
	return Config{
		Outputs:           []string{},
		LowTemp:           4000,
		HighTemp:          6500,
		Gamma:             1.0,
		Contrast:          1.0,
		Enabled:           false,
		ElevationTwilight: -6.0,
		ElevationDaylight: 3.0,
	}
}

func (c *Config) Validate() error {
	if c.LowTemp < 1000 || c.LowTemp > 10000 {
		return errdefs.ErrInvalidTemperature
	}
	if c.HighTemp < 1000 || c.HighTemp > 10000 {
		return errdefs.ErrInvalidTemperature
	}
	if c.LowTemp > c.HighTemp {
		return errdefs.ErrInvalidTemperature
	}
	if c.Gamma <= 0 || c.Gamma > 10 {
		return errdefs.ErrInvalidGamma
	}
	if c.Contrast < 0.5 || c.Contrast > 2 {
		return errdefs.ErrInvalidContrast
	}
	if c.Latitude != nil && (math.Abs(*c.Latitude) > 90) {
		return errdefs.ErrInvalidLocation
	}
	if c.Longitude != nil && (math.Abs(*c.Longitude) > 180) {
		return errdefs.ErrInvalidLocation
	}
	if (c.Latitude != nil) != (c.Longitude != nil) {
		return errdefs.ErrInvalidLocation
	}
	if (c.ManualSunrise != nil) != (c.ManualSunset != nil) {
		return errdefs.ErrInvalidManualTimes
	}
	if c.ManualDuration != nil && (*c.ManualDuration < 0 || *c.ManualDuration > 6*time.Hour) {
		return errdefs.ErrInvalidDuration
	}
	return nil
}

func (m *Manager) GetState() State {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	if m.state == nil {
		return State{}
	}
	return *m.state
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

func stateChanged(old, new *State) bool {
	if old == nil || new == nil {
		return true
	}
	if old.CurrentTemp != new.CurrentTemp {
		return true
	}
	if old.IsDay != new.IsDay {
		return true
	}
	if !old.NextTransition.Equal(new.NextTransition) {
		return true
	}
	if !old.SunriseTime.Equal(new.SunriseTime) {
		return true
	}
	if !old.SunsetTime.Equal(new.SunsetTime) {
		return true
	}
	if old.Config.Enabled != new.Config.Enabled {
		return true
	}
	if old.Config.Gamma != new.Config.Gamma || old.Config.Contrast != new.Config.Contrast {
		return true
	}
	if old.SunPosition != new.SunPosition {
		return true
	}
	return iccStateChanged(old, new)
}

// iccStateChanged reports whether the ICC part of the state (what the Display
// Config card renders) differs. Without it, applying or removing a profile and
// setting a per-output temperature are the only things that changed, and the
// notifier would treat the state as unchanged and never push it.
func iccStateChanged(old, new *State) bool {
	if len(old.ICCProfiles) != len(new.ICCProfiles) || len(old.OutputTemps) != len(new.OutputTemps) {
		return true
	}
	if !maps.Equal(old.Config.OutputBrightness, new.Config.OutputBrightness) {
		return true
	}
	if !slices.Equal(old.Outputs, new.Outputs) || !slices.Equal(old.GammaRefused, new.GammaRefused) {
		return true
	}
	for name, temp := range new.OutputTemps {
		if oldTemp, ok := old.OutputTemps[name]; !ok || oldTemp != temp {
			return true
		}
	}
	for name, status := range new.ICCProfiles {
		prev, ok := old.ICCProfiles[name]
		if !ok || prev == nil || status == nil {
			if prev != status {
				return true
			}
			continue
		}
		if *prev != *status {
			return true
		}
	}
	return false
}
