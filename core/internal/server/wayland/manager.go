package wayland

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"time"

	"github.com/duxlabs-dev/dux-go/boottimer"
	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/godbus/dbus/v5"

	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/geolocation"
	"github.com/duxlabs-dev/dux-shell/core/internal/icc"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_gamma_control"
	"github.com/duxlabs-dev/dux-shell/core/internal/wayland/shm"
)

const animKelvinStep = 25

const neutralTemp = 6500

// noTempTarget marks "the night light has no temperature target". Plain outputs
// then get the neutral ramp, while outputs with an ICC profile stay at the
// white point their profile was produced at.
const noTempTarget = -1

func NewManager(display wlclient.WaylandDisplay, config Config) (*Manager, error) {
	if err := config.Validate(); err != nil {
		return nil, err
	}

	if config.ElevationTwilight == 0 {
		config.ElevationTwilight = -6.0
	}
	if config.ElevationDaylight == 0 {
		config.ElevationDaylight = 3.0
	}

	m := &Manager{
		config:        config,
		display:       display,
		ctx:           display.Context(),
		cmdq:          make(chan cmd, 128),
		stopChan:      make(chan struct{}),
		updateTrigger: make(chan struct{}, 1),
		dirty:         make(chan struct{}, 1),
		dbusSignal:    make(chan *dbus.Signal, 16),
	}

	if err := m.setupRegistry(); err != nil {
		return nil, err
	}

	if err := m.setupDBusMonitor(); err != nil {
		log.Warnf("Failed to setup D-Bus monitoring: %v", err)
	}

	m.alive = true
	// Publish before the first state push so the snapshot is never nil, and
	// before the actor starts so no other goroutine touches the fields yet.
	m.publishICCState()
	m.recalcSchedule(time.Now())
	m.updateStateFromSchedule()

	m.notifierWg.Add(1)
	go m.notifier()

	m.wg.Add(1)
	go m.schedulerLoop()

	if m.dbusConn != nil {
		m.wg.Add(1)
		go m.dbusMonitor()
	}

	m.wg.Add(1)
	go m.waylandActor()

	// needsControls() also accounts for ICC profiles and per-output
	// temperatures, so controls are set up whenever any of them is configured.
	if m.needsControls() {
		m.post(func() {
			// Profiles and temperatures are configured state, not control state:
			// the registry handler may already have established the controls, and
			// the configuration still has to be attached.
			loaded := m.loadConfiguredICC()
			m.publishICCState()

			if !m.controlsInitialized {
				log.Info("Gamma control enabled at startup")
				m.createControls()
			}

			if loaded {
				// The attached configuration is invisible to the per-output
				// dedup, which only compares the schedule-derived
				// temp/gamma/contrast, so clear that state before applying.
				m.outputs.Range(func(_ uint32, out *outputState) bool {
					out.lastTemp = 0
					return true
				})
				m.applyCurrentTemp("startup")
			}
		})
	}

	return m, nil
}

func (m *Manager) post(fn func()) {
	select {
	case m.cmdq <- cmd{fn: fn}:
	default:
		log.Warn("Actor command queue full")
	}
}

// cloneConfig returns a copy of cfg whose maps belong to the copy. The manager
// mutates the config's maps under configMutex, so a value copy that still
// aliased them would turn a marshal or an iteration after the unlock into a
// concurrent map read/write.
func cloneConfig(cfg Config) Config {
	cfg.ICCProfiles = maps.Clone(cfg.ICCProfiles)
	cfg.OutputTemps = maps.Clone(cfg.OutputTemps)
	cfg.OutputBrightness = maps.Clone(cfg.OutputBrightness)
	return cfg
}

// configSnapshot returns a clone of the current config that stays valid after
// configMutex is released.
func (m *Manager) configSnapshot() Config {
	m.configMutex.RLock()
	defer m.configMutex.RUnlock()
	return cloneConfig(m.config)
}

func (m *Manager) waylandActor() {
	defer m.wg.Done()
	for {
		select {
		case <-m.stopChan:
			return
		case c := <-m.cmdq:
			c.fn()
		}
	}
}

func (m *Manager) anyOutputReady() bool {
	anyReady := false
	m.outputs.Range(func(_ uint32, out *outputState) bool {
		if out.rampSize > 0 && !out.failed {
			anyReady = true
			return false // stop iteration
		}
		return true
	})
	return anyReady
}

const prepareForSleepMatchRule = "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep',path='/org/freedesktop/login1'"

func (m *Manager) setupDBusMonitor() error {
	conn, err := dbus.SystemBus()
	if err != nil {
		return fmt.Errorf("system bus: %w", err)
	}

	if err := conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0, prepareForSleepMatchRule).Err; err != nil {
		return fmt.Errorf("add match: %w", err)
	}

	conn.Signal(m.dbusSignal)
	m.dbusConn = conn
	return nil
}

func (m *Manager) setupRegistry() error {
	registry, err := m.display.GetRegistry()
	if err != nil {
		return fmt.Errorf("get registry: %w", err)
	}
	m.registry = registry

	outputs := make([]*wlclient.Output, 0)
	outputNames := make(map[uint32]string)
	var gammaMgr *wlr_gamma_control.ZwlrGammaControlManagerV1

	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		switch e.Interface {
		case wlr_gamma_control.ZwlrGammaControlManagerV1InterfaceName:
			manager := wlr_gamma_control.NewZwlrGammaControlManagerV1(m.ctx)
			version := min(e.Version, 1)
			if err := registry.Bind(e.Name, e.Interface, version, manager); err == nil {
				gammaMgr = manager
			}
		case "wl_output":
			output := wlclient.NewOutput(m.ctx)
			version := min(e.Version, 4)
			if err := registry.Bind(e.Name, e.Interface, version, output); err != nil {
				return
			}
			outputID := output.ID()
			output.SetNameHandler(func(ev wlclient.OutputNameEvent) {
				outputNames[outputID] = ev.Name
				m.outputNames.Store(outputID, ev.Name)
				m.post(func() {
					m.attachConfiguredICC(outputID, ev.Name)
					m.updateStateFromSchedule()
				})
			})
			if gammaMgr != nil {
				outputs = append(outputs, output)
				m.addAvailableOutput(output)
			}
			m.outputRegNames.Store(outputID, e.Name)

			if !m.needsControls() {
				return
			}
			m.post(func() {
				if err := m.addOutputControl(output); err != nil {
					log.Warnf("gamma: failed to add output control: %v", err)
					return
				}
				if m.controlsInitialized {
					return
				}
				// All outputs had been torn down (monitor sleep/disconnect),
				// clearing controlsInitialized. Mark it ready again so the
				// gamma_size event that follows control creation drives the
				// reapply, instead of waiting for a manual toggle. No explicit
				// apply here: applyGamma's dedup would suppress a no-change
				// write anyway, and the new control isn't ready until gamma_size.
				log.Info("gamma: output returned, re-establishing controls")
				m.controlsInitialized = true
			})
		}
	})

	registry.SetGlobalRemoveHandler(func(e wlclient.RegistryGlobalRemoveEvent) {
		m.post(func() {
			m.removeOutputByRegistryName(e.Name)
			m.updateStateFromSchedule()
		})
	})

	if err := m.display.Roundtrip(); err != nil {
		return fmt.Errorf("roundtrip 1: %w", err)
	}
	if err := m.display.Roundtrip(); err != nil {
		return fmt.Errorf("roundtrip 2: %w", err)
	}

	if gammaMgr == nil {
		return errdefs.ErrNoGammaControl
	}
	if len(outputs) == 0 {
		return fmt.Errorf("no outputs")
	}

	physicalOutputs := make([]*wlclient.Output, 0, len(outputs))
	for _, output := range outputs {
		name := outputNames[output.ID()]
		if len(name) >= 9 && name[:9] == "HEADLESS-" {
			continue
		}
		physicalOutputs = append(physicalOutputs, output)
	}

	m.gammaControl = gammaMgr
	m.availableOutputs = physicalOutputs
	return nil
}

func (m *Manager) setupOutputControls(outputs []*wlclient.Output, manager *wlr_gamma_control.ZwlrGammaControlManagerV1) error {
	for _, output := range outputs {
		control, err := manager.GetGammaControl(output)
		if err != nil {
			continue
		}
		outputID := output.ID()
		registryName, _ := m.outputRegNames.Load(outputID)
		outState := m.controlStateFor(outputID, registryName, output, control)
		m.setupControlHandlers(outState, control)
		m.outputs.Store(outputID, outState)
	}
	return nil
}

// controlStateFor returns the state a (re)created gamma control is attached to.
// A re-created control must not drop what belongs to the output rather than to
// the control: the attached ICC profile and the per-output temperature survive,
// while the ramp bookkeeping and the failure budget start over so the new
// control receives a fresh ramp once it reports gamma_size.
func (m *Manager) controlStateFor(outputID, registryName uint32, output *wlclient.Output, control any) *outputState {
	existing, ok := m.outputs.Load(outputID)
	if !ok {
		return &outputState{
			id:           outputID,
			registryName: registryName,
			output:       output,
			gammaControl: control,
		}
	}

	existing.registryName = registryName
	existing.output = output
	existing.gammaControl = control
	existing.rampSize = 0
	existing.failed = false
	existing.retryCount = 0
	existing.lastFailTime = time.Time{}
	existing.lastTemp = 0
	existing.lastGamma = 0
	existing.lastContrast = 0
	return existing
}

func (m *Manager) setupControlHandlers(state *outputState, control *wlr_gamma_control.ZwlrGammaControlV1) {
	outputID := state.id

	control.SetGammaSizeHandler(func(e wlr_gamma_control.ZwlrGammaControlV1GammaSizeEvent) {
		size := e.Size
		m.post(func() {
			if out, ok := m.outputs.Load(outputID); ok {
				out.rampSize = size
				out.failed = false
				out.retryCount = 0
				out.lastTemp = 0
				if out.gammaRefused {
					out.gammaRefused = false
					m.publishICCState()
					m.updateStateFromSchedule()
				}
			}
			m.applyCurrentTemp("gamma_size")
		})
	})

	control.SetFailedHandler(func(_ wlr_gamma_control.ZwlrGammaControlV1FailedEvent) {
		m.post(func() {
			out, ok := m.outputs.Load(outputID)
			if !ok {
				return
			}
			if ctrl, ok := out.gammaControl.(*wlr_gamma_control.ZwlrGammaControlV1); ok && ctrl != nil && !ctrl.IsZombie() {
				ctrl.Destroy()
			}
			out.gammaControl = nil
			out.markFailed(time.Now())
			if out.gammaRefused {
				m.publishICCState()
				m.updateStateFromSchedule()
			}

			if !m.outputStillValid(out) {
				return
			}

			backoff := time.Duration(300<<uint(min(out.retryCount-1, 4))) * time.Millisecond
			time.AfterFunc(backoff, func() {
				m.post(func() {
					if !m.outputStillValid(out) {
						return
					}
					if _, stillTracked := m.outputs.Load(outputID); !stillTracked {
						return
					}
					m.recreateOutputControl(out)
				})
			})
		})
	})
}

func (m *Manager) addAvailableOutput(o *wlclient.Output) {
	if o == nil {
		return
	}
	m.availOutputsMu.Lock()
	defer m.availOutputsMu.Unlock()
	if slices.Contains(m.availableOutputs, o) {
		return
	}
	m.availableOutputs = append(m.availableOutputs, o)
}

func (m *Manager) removeAvailableOutput(o *wlclient.Output) {
	if o == nil {
		return
	}
	m.availOutputsMu.Lock()
	defer m.availOutputsMu.Unlock()
	m.availableOutputs = slices.DeleteFunc(m.availableOutputs, func(existing *wlclient.Output) bool {
		return existing == o
	})
}

// removeOutputByRegistryName tears down the state of an output that left the
// compositor (unplugged or asleep). Only the wayland actor goroutine calls it.
func (m *Manager) removeOutputByRegistryName(registryName uint32) {
	// Resolve the object ID from the registry name map: both name maps are
	// populated for every wl_output, whether or not a gamma control exists for
	// it, while m.outputs only has entries once the controls exist. On a default
	// install (night light off, no profile, no override) no control is ever
	// created, and the name entries still have to go with the output.
	foundID, found := m.outputIDForRegistryName(registryName)

	var foundOut *outputState
	if found {
		if out, ok := m.outputs.Load(foundID); ok {
			foundOut = out
		}
	} else {
		// An output whose name never arrived is only known through its state.
		m.outputs.Range(func(id uint32, out *outputState) bool {
			if out.registryName == registryName {
				foundID, foundOut, found = id, out, true
				return false
			}
			return true
		})
	}
	if !found {
		return
	}

	// The name entries go first: they are what `dms icc status`/`listOutputs`
	// report, and a rebound wl_output reusing a released object ID would
	// otherwise attach the previous monitor's profile from the stale name.
	m.outputNames.Delete(foundID)
	m.outputRegNames.Delete(foundID)

	if foundOut != nil {
		if foundOut.gammaControl != nil {
			foundOut.gammaControl.(*wlr_gamma_control.ZwlrGammaControlV1).Destroy()
			foundOut.gammaControl = nil
		}
		m.removeAvailableOutput(foundOut.output)
		if foundOut.output != nil && !foundOut.output.IsZombie() {
			_ = foundOut.output.Release()
		}
		m.outputs.Delete(foundID)
	}
	m.publishICCState()

	hasOutputs := false
	m.outputs.Range(func(_ uint32, _ *outputState) bool {
		hasOutputs = true
		return false
	})
	if !hasOutputs {
		m.controlsInitialized = false
	}
}

// outputIDForRegistryName maps a wl_output registry name back to the object ID
// it was announced with.
func (m *Manager) outputIDForRegistryName(registryName uint32) (uint32, bool) {
	var foundID uint32
	var found bool
	m.outputRegNames.Range(func(id, name uint32) bool {
		if name == registryName {
			foundID, found = id, true
			return false
		}
		return true
	})
	return foundID, found
}

func (m *Manager) outputStillValid(out *outputState) bool {
	switch {
	case out == nil:
		return false
	case out.output == nil:
		return false
	case out.output.IsZombie():
		return false
	}
	m.availOutputsMu.RLock()
	defer m.availOutputsMu.RUnlock()
	return slices.Contains(m.availableOutputs, out.output)
}

func isConnectionDeadErr(err error) bool {
	switch {
	case err == nil:
		return false
	case errors.Is(err, syscall.EPIPE):
		return true
	case errors.Is(err, syscall.ECONNRESET):
		return true
	case errors.Is(err, syscall.EBADF):
		return true
	case errors.Is(err, io.EOF):
		return true
	}
	return false
}

func (m *Manager) addOutputControl(output *wlclient.Output) error {
	switch {
	case m.connectionDead.Load():
		return nil
	case output == nil || output.IsZombie():
		return nil
	}

	outputID := output.ID()
	gammaMgr := m.gammaControl.(*wlr_gamma_control.ZwlrGammaControlManagerV1)

	control, err := gammaMgr.GetGammaControl(output)
	if err != nil {
		if isConnectionDeadErr(err) {
			m.markConnectionDead(err)
		}
		return err
	}

	registryName, _ := m.outputRegNames.Load(outputID)
	outState := &outputState{
		id:           outputID,
		registryName: registryName,
		output:       output,
		gammaControl: control,
	}
	m.setupControlHandlers(outState, control)
	m.outputs.Store(outputID, outState)

	// The name may already be known (hotplug after the output was announced),
	// in which case the configured profile/temperature attaches right away.
	if name, ok := m.outputNames.Load(outputID); ok {
		m.attachConfiguredICC(outputID, name)
	}
	m.publishICCState()
	return nil
}

func (m *Manager) recreateOutputControl(out *outputState) error {
	switch {
	case m.connectionDead.Load():
		return nil
	case !m.needsControls() || !m.controlsInitialized:
		return nil
	case out.isVirtual:
		return nil
	case out.retryCount >= 10:
		return nil
	case !m.outputStillValid(out):
		return nil
	}
	if _, ok := m.outputs.Load(out.id); !ok {
		return nil
	}

	gammaMgr, ok := m.gammaControl.(*wlr_gamma_control.ZwlrGammaControlManagerV1)
	if !ok {
		return fmt.Errorf("no gamma manager")
	}

	if existing, ok := out.gammaControl.(*wlr_gamma_control.ZwlrGammaControlV1); ok && existing != nil && !existing.IsZombie() {
		existing.Destroy()
		out.gammaControl = nil
	}

	control, err := gammaMgr.GetGammaControl(out.output)
	if err != nil {
		if isConnectionDeadErr(err) {
			m.markConnectionDead(err)
		}
		return err
	}

	m.setupControlHandlers(out, control)
	out.gammaControl = control
	out.failed = false
	return nil
}

func (m *Manager) markConnectionDead(err error) {
	if m.connectionDead.Swap(true) {
		return
	}
	log.Errorf("gamma: wayland connection appears dead (%v); pausing gamma operations", err)
}

func (m *Manager) recalcSchedule(now time.Time) {
	config := m.configSnapshot()

	m.scheduleMutex.Lock()
	defer m.scheduleMutex.Unlock()

	dayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	alreadyValid := !m.schedule.times.Sunrise.IsZero()
	if m.schedule.calcDay.Equal(dayStart) && alreadyValid {
		return
	}

	var times SunTimes
	var cond SunCondition

	if config.ManualSunrise != nil && config.ManualSunset != nil {
		dur := time.Hour
		if config.ManualDuration != nil {
			dur = *config.ManualDuration
		}
		sunrise := time.Date(now.Year(), now.Month(), now.Day(),
			config.ManualSunrise.Hour(), config.ManualSunrise.Minute(), config.ManualSunrise.Second(), 0, now.Location())
		sunset := time.Date(now.Year(), now.Month(), now.Day(),
			config.ManualSunset.Hour(), config.ManualSunset.Minute(), config.ManualSunset.Second(), 0, now.Location())
		if !sunset.After(sunrise) {
			// night start past midnight belongs to the next day
			sunset = sunset.Add(24 * time.Hour)
		}
		times = SunTimes{
			Dawn:    sunrise.Add(-dur),
			Sunrise: sunrise,
			Sunset:  sunset,
			Night:   sunset.Add(dur),
		}
		cond = SunNormal
	} else {
		lat, lon := m.getLocation()
		if lat == nil || lon == nil {
			m.gammaState = StateStatic
			// stale times from a previous config must not drive applies
			m.schedule = sunSchedule{}
			return
		}
		times, cond = CalculateSunTimesWithTwilight(*lat, *lon, now, config.ElevationTwilight, config.ElevationDaylight)
	}

	m.schedule.calcDay = dayStart
	m.schedule.times = times
	m.schedule.condition = cond

	switch cond {
	case SunNormal:
		m.gammaState = StateNormal
		tempDiff := config.HighTemp - config.LowTemp
		if tempDiff > 0 {
			dawnDur := times.Sunrise.Sub(times.Dawn)
			nightDur := times.Night.Sub(times.Sunset)
			m.schedule.dawnStepTime = time.Duration(max(1, int(dawnDur.Seconds())*animKelvinStep/tempDiff)) * time.Second
			m.schedule.nightStepTime = time.Duration(max(1, int(nightDur.Seconds())*animKelvinStep/tempDiff)) * time.Second
		}
	case SunMidnightSun:
		m.gammaState = StateStatic
	case SunPolarNight:
		m.gammaState = StateStatic
	}
}

func (m *Manager) SetGeoClient(client geolocation.Client) {
	m.geoClient = client
}

func (m *Manager) getLocation() (*float64, *float64) {
	config := m.configSnapshot()

	if config.Latitude != nil && config.Longitude != nil {
		return config.Latitude, config.Longitude
	}
	if !config.UseIPLocation {
		return nil, nil
	}
	if m.geoClient == nil {
		return nil, nil
	}

	m.locationMutex.RLock()
	if m.cachedIPLat != nil && m.cachedIPLon != nil {
		lat, lon := m.cachedIPLat, m.cachedIPLon
		m.locationMutex.RUnlock()
		return lat, lon
	}
	m.locationMutex.RUnlock()

	location, err := m.geoClient.GetLocation()
	if err != nil {
		return nil, nil
	}

	m.locationMutex.Lock()
	m.cachedIPLat = &location.Latitude
	m.cachedIPLon = &location.Longitude
	m.locationMutex.Unlock()
	return m.cachedIPLat, m.cachedIPLon
}

func (m *Manager) hasValidSchedule() bool {
	m.scheduleMutex.RLock()
	defer m.scheduleMutex.RUnlock()
	return !m.schedule.times.Sunrise.IsZero()
}

func (m *Manager) getSunPosition(now time.Time) float64 {
	m.scheduleMutex.RLock()
	sched := m.schedule
	state := m.gammaState
	m.scheduleMutex.RUnlock()

	if sched.times.Sunrise.IsZero() {
		return 1.0
	}

	switch state {
	case StateStatic:
		if sched.condition == SunMidnightSun {
			return 1.0
		}
		return 0.0
	case StateNormal:
		return m.getSunPositionNormal(now, sched.times)
	}
	return 1.0
}

func shiftTimes(times SunTimes, d time.Duration) SunTimes {
	return SunTimes{
		Dawn:    times.Dawn.Add(d),
		Sunrise: times.Sunrise.Add(d),
		Sunset:  times.Sunset.Add(d),
		Night:   times.Night.Add(d),
	}
}

// activeCycle maps early-morning hours back to yesterday's cycle when the
// schedule crosses midnight.
func activeCycle(now time.Time, times SunTimes) SunTimes {
	if now.Before(times.Night.Add(-24 * time.Hour)) {
		return shiftTimes(times, -24*time.Hour)
	}
	return times
}

func (m *Manager) getSunPositionNormal(now time.Time, times SunTimes) float64 {
	times = activeCycle(now, times)
	if now.Before(times.Dawn) {
		return 0.0
	}
	if now.Before(times.Sunrise) {
		return interpolate(now, times.Dawn, times.Sunrise)
	}
	if now.Before(times.Sunset) {
		return 1.0
	}
	if now.Before(times.Night) {
		return interpolate(now, times.Night, times.Sunset)
	}
	return 0.0
}

func interpolate(now time.Time, start, stop time.Time) float64 {
	if start.Equal(stop) {
		return 1.0
	}
	pos := float64(now.Sub(start)) / float64(stop.Sub(start))
	switch {
	case pos > 1.0:
		return 1.0
	case pos < 0.0:
		return 0.0
	default:
		return pos
	}
}

func (m *Manager) getTempFromPosition(pos float64) int {
	m.configMutex.RLock()
	low, high := m.config.LowTemp, m.config.HighTemp
	m.configMutex.RUnlock()
	return low + int(float64(high-low)*pos)
}

func (m *Manager) getNextDeadline(now time.Time) time.Time {
	m.scheduleMutex.RLock()
	sched := m.schedule
	state := m.gammaState
	m.scheduleMutex.RUnlock()

	switch state {
	case StateStatic:
		return m.tomorrow(now)
	case StateNormal:
		return m.getDeadlineNormal(now, sched)
	default:
		return m.tomorrow(now)
	}
}

func (m *Manager) getDeadlineNormal(now time.Time, sched sunSchedule) time.Time {
	times := activeCycle(now, sched.times)
	switch {
	case now.Before(times.Dawn):
		return times.Dawn
	case now.Before(times.Sunrise):
		return now.Add(sched.dawnStepTime)
	case now.Before(times.Sunset):
		return times.Sunset
	case now.Before(times.Night):
		return now.Add(sched.nightStepTime)
	default:
		return m.tomorrowDawn(now)
	}
}

func (m *Manager) tomorrowDawn(now time.Time) time.Time {
	tomorrow := time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, now.Location())

	config := m.configSnapshot()

	if config.ManualSunrise != nil {
		dur := time.Hour
		if config.ManualDuration != nil {
			dur = *config.ManualDuration
		}
		return time.Date(tomorrow.Year(), tomorrow.Month(), tomorrow.Day(),
			config.ManualSunrise.Hour(), config.ManualSunrise.Minute(), config.ManualSunrise.Second(), 0, tomorrow.Location()).Add(-dur)
	}

	lat, lon := m.getLocation()
	if lat == nil || lon == nil {
		return tomorrow
	}

	times, cond := CalculateSunTimesWithTwilight(*lat, *lon, tomorrow, config.ElevationTwilight, config.ElevationDaylight)
	if cond != SunNormal {
		return tomorrow
	}
	return times.Dawn
}

func (m *Manager) tomorrow(now time.Time) time.Time {
	return time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, now.Location())
}

func (m *Manager) schedulerLoop() {
	defer m.wg.Done()

	if m.needsControls() {
		m.post(func() { m.applyCurrentTemp("startup") })
	}

	timer := boottimer.New(24 * time.Hour)
	defer timer.Stop()
	for {
		m.configMutex.RLock()
		enabled := m.config.Enabled
		m.configMutex.RUnlock()

		now := time.Now()
		m.recalcSchedule(now)
		// publish independent of output readiness so night status never
		// presents a stale schedule while applies are blocked (#2967)
		m.updateStateFromSchedule()

		waitDur := 24 * time.Hour
		if enabled {
			deadline := m.getNextDeadline(now)
			if waitDur = time.Until(deadline); waitDur < time.Second {
				waitDur = time.Second
			}
		}
		timer.Reset(waitDur)

		select {
		case <-m.stopChan:
			return
		case <-m.updateTrigger:
			m.scheduleMutex.Lock()
			m.schedule.calcDay = time.Time{}
			m.scheduleMutex.Unlock()
			m.recalcSchedule(time.Now())
			m.updateStateFromSchedule()
			if m.needsControls() {
				m.post(func() { m.applyCurrentTemp("updateTrigger") })
			}
		case <-timer.C:
			if m.needsControls() {
				m.post(func() { m.applyCurrentTemp("timer") })
			}
		}
	}
}

func (m *Manager) applyCurrentTemp(_ string) {
	if !m.controlsInitialized || !m.anyOutputReady() {
		return
	}

	// Ensure schedule is up-to-date (handles display wake after overnight sleep)
	m.recalcSchedule(time.Now())

	m.configMutex.RLock()
	enabled := m.config.Enabled
	low, high := m.config.LowTemp, m.config.HighTemp
	m.configMutex.RUnlock()

	// With the night light disabled, outputs with an ICC profile keep the ramp
	// their profile describes and the rest stay at identity (noTempTarget).
	if !enabled {
		m.applyGamma(noTempTarget)
		m.updateStateFromSchedule()
		return
	}

	if low == high {
		m.applyGamma(low)
		m.updateStateFromSchedule()
		return
	}

	if !m.hasValidSchedule() {
		m.updateStateFromSchedule()
		return
	}

	now := time.Now()
	pos := m.getSunPosition(now)
	temp := m.getTempFromPosition(pos)

	m.applyGamma(temp)
	m.updateStateFromSchedule()
}

// effectiveTempTarget returns the temperature to render an output at: a
// per-output override wins over the night light schedule, so each display can
// keep its own temperature (0 = no override). Without either, the output keeps
// whatever its profile describes.
func effectiveTempTarget(out *outputState, scheduleTemp int) int {
	if out.outputTemp != 0 {
		return out.outputTemp
	}
	if scheduleTemp > 0 {
		return scheduleTemp
	}
	return noTempTarget
}

func (m *Manager) applyGamma(temp int) {
	m.configMutex.RLock()
	gamma, contrast := m.config.Gamma, m.config.Contrast
	m.configMutex.RUnlock()

	switch {
	case m.connectionDead.Load():
		return
	case !m.controlsInitialized:
		return
	}

	var outs []*outputState
	m.outputs.Range(func(_ uint32, out *outputState) bool {
		outs = append(outs, out)
		return true
	})
	if len(outs) == 0 {
		return
	}

	type job struct {
		out        *outputState
		targetTemp int
		data       []byte
	}
	var jobs []job

	for _, out := range outs {
		targetTemp := effectiveTempTarget(out, temp)
		switch {
		case out.failed:
			continue
		case out.rampSize == 0:
			continue
		case out.gammaControl == nil:
			continue
		case out.rampCurrent(targetTemp, gamma, contrast):
			continue
		case !m.outputStillValid(out):
			continue
		}

		var ramp GammaRamp
		if out.iccPath != "" && out.iccProfile != nil {
			// The profile describes the display at the white point display
			// profiles are produced at (D65); a target temperature is composed
			// on top of it.
			profileRamp, err := ProfileRampWithTemp(out.rampSize, out.iccProfile, neutralTemp, targetTemp, gamma, contrast)
			if err != nil {
				log.Warnf("icc: failed to generate ramp for output %d: %v, falling back to temperature", out.id, err)
				fallbackTemp := targetTemp
				if fallbackTemp <= 0 {
					fallbackTemp = neutralTemp
				}
				ramp = GenerateGammaRamp(out.rampSize, fallbackTemp, gamma, contrast)
			} else {
				ramp = profileRamp
				log.Debugf("icc: applied ICC ramp to output %d (size=%d, ref=%dK, target=%dK)", out.id, out.rampSize, neutralTemp, targetTemp)
			}
		} else {
			outTemp := targetTemp
			if outTemp <= 0 {
				outTemp = neutralTemp
			}
			ramp = GenerateGammaRamp(out.rampSize, outTemp, gamma, contrast)
		}
		if out.dimScale > 0 {
			scaleRamp(ramp, out.dimScale)
		}
		buf := bytes.NewBuffer(make([]byte, 0, int(out.rampSize)*6))
		for _, v := range ramp.Red {
			binary.Write(buf, binary.LittleEndian, v)
		}
		for _, v := range ramp.Green {
			binary.Write(buf, binary.LittleEndian, v)
		}
		for _, v := range ramp.Blue {
			binary.Write(buf, binary.LittleEndian, v)
		}
		jobs = append(jobs, job{out: out, targetTemp: targetTemp, data: buf.Bytes()})
	}

	for _, j := range jobs {
		err := m.setGammaBytes(j.out, j.data)
		if err == nil {
			j.out.lastTemp = j.targetTemp
			j.out.lastGamma = gamma
			j.out.lastContrast = contrast
			continue
		}
		log.Warnf("gamma: failed to set output %d: %v", j.out.id, err)
		j.out.failed = true
		j.out.rampSize = 0
		j.out.lastTemp = 0
		if isConnectionDeadErr(err) {
			m.markConnectionDead(err)
			return
		}
	}
}

// rampCurrent compares against the output's effective target, not the schedule
// temperature, so an overridden output is not resent on every schedule step.
// lastTemp 0 never matches a target and marks a forced resend.
func (out *outputState) rampCurrent(targetTemp int, gamma, contrast float64) bool {
	return out.lastTemp == targetTemp && out.lastGamma == gamma && out.lastContrast == contrast
}

func (m *Manager) setGammaBytes(out *outputState, data []byte) error {
	if out.gammaControl == nil {
		return fmt.Errorf("no gamma control")
	}
	ctrl, ok := out.gammaControl.(*wlr_gamma_control.ZwlrGammaControlV1)
	if !ok || ctrl == nil || ctrl.IsZombie() {
		return fmt.Errorf("gamma control invalid")
	}

	fd, err := shm.CreateAnonFd("gamma-ramp")
	if err != nil {
		return err
	}
	defer syscall.Close(fd)

	if err := syscall.Ftruncate(fd, int64(len(data))); err != nil {
		return err
	}

	dupFd, err := syscall.Dup(fd)
	if err != nil {
		return err
	}
	f := os.NewFile(uintptr(dupFd), "gamma")
	defer f.Close()

	if _, err := f.Write(data); err != nil {
		return err
	}
	syscall.Seek(fd, 0, 0)

	return ctrl.SetGamma(fd)
}

func (m *Manager) updateStateFromSchedule() {
	now := time.Now()

	config := m.configSnapshot()

	m.scheduleMutex.RLock()
	times := m.schedule.times
	m.scheduleMutex.RUnlock()

	var pos float64
	var temp int
	var isDay bool
	var deadline time.Time

	if times.Sunrise.IsZero() {
		pos = 1.0
		temp = config.HighTemp
		isDay = true
		deadline = m.tomorrow(now)
	} else {
		pos = m.getSunPosition(now)
		temp = m.getTempFromPosition(pos)
		deadline = m.getNextDeadline(now)
		cycle := activeCycle(now, times)
		isDay = now.After(cycle.Sunrise) && now.Before(cycle.Sunset)
	}

	newState := State{
		Config:         config,
		CurrentTemp:    temp,
		NextTransition: deadline,
		SunriseTime:    times.Sunrise,
		SunsetTime:     times.Sunset,
		DawnTime:       times.Dawn,
		NightTime:      times.Night,
		IsDay:          isDay,
		SunPosition:    pos,
		ICCProfiles:    m.GetICCStatus(),
		OutputTemps:    m.GetOutputTemps(),
		GammaRefused:   m.GammaRefusedOutputs(),
		Outputs:        m.ListOutputs(),
	}

	m.stateMutex.Lock()
	m.state = &newState
	m.stateMutex.Unlock()

	m.notifySubscribers()
}

func (m *Manager) notifier() {
	defer m.notifierWg.Done()
	const minGap = 100 * time.Millisecond
	timer := time.NewTimer(minGap)
	timer.Stop()
	var pending bool

	for {
		select {
		case <-m.stopChan:
			timer.Stop()
			return
		case <-m.dirty:
			if pending {
				continue
			}
			pending = true
			timer.Reset(minGap)
		case <-timer.C:
			if !pending {
				continue
			}
			currentState := m.GetState()
			if m.lastNotified != nil && !stateChanged(m.lastNotified, &currentState) {
				pending = false
				continue
			}
			m.subscribers.Range(func(_ string, ch chan State) bool {
				select {
				case ch <- currentState:
				default:
				}
				return true
			})
			stateCopy := currentState
			m.lastNotified = &stateCopy
			pending = false
		}
	}
}

func (m *Manager) dbusMonitor() {
	defer m.wg.Done()
	for {
		select {
		case <-m.stopChan:
			return
		case sig := <-m.dbusSignal:
			if sig == nil {
				continue
			}
			m.handleDBusSignal(sig)
		}
	}
}

func (m *Manager) handleDBusSignal(sig *dbus.Signal) {
	switch {
	case sig.Name != "org.freedesktop.login1.Manager.PrepareForSleep":
		return
	case len(sig.Body) == 0:
		return
	}
	preparing, ok := sig.Body[0].(bool)
	if !ok || preparing {
		return
	}
	if !m.needsControls() {
		return
	}
	time.AfterFunc(500*time.Millisecond, func() {
		m.post(m.handleResume)
	})
}

func (m *Manager) handleResume() {
	switch {
	case !m.needsControls():
		return
	case !m.controlsInitialized:
		return
	case m.connectionDead.Load():
		return
	}

	// Compositor gamma state is unknown after resume; force a resend (#1235)
	m.outputs.Range(func(_ uint32, out *outputState) bool {
		out.lastTemp = 0
		return true
	})
	m.applyCurrentTemp("resume")
}

func (m *Manager) triggerUpdate() {
	select {
	case m.updateTrigger <- struct{}{}:
	default:
	}
}

func (m *Manager) SetConfig(config Config) error {
	if err := config.Validate(); err != nil {
		return err
	}
	m.configMutex.Lock()
	m.config = cloneConfig(config)
	m.configMutex.Unlock()
	m.triggerUpdate()
	return nil
}

func (m *Manager) SetTemperature(low, high int) error {
	m.configMutex.Lock()
	if m.config.LowTemp == low && m.config.HighTemp == high {
		m.configMutex.Unlock()
		return nil
	}
	updated := m.config
	updated.LowTemp = low
	updated.HighTemp = high
	if err := updated.Validate(); err != nil {
		m.configMutex.Unlock()
		return err
	}
	m.config = updated
	m.configMutex.Unlock()
	m.triggerUpdate()
	return nil
}

func (m *Manager) SetLocation(lat, lon float64) error {
	m.configMutex.Lock()
	if m.config.Latitude != nil && m.config.Longitude != nil &&
		*m.config.Latitude == lat && *m.config.Longitude == lon && !m.config.UseIPLocation {
		m.configMutex.Unlock()
		return nil
	}
	updated := m.config
	updated.Latitude = &lat
	updated.Longitude = &lon
	updated.UseIPLocation = false
	if err := updated.Validate(); err != nil {
		m.configMutex.Unlock()
		return err
	}
	m.config = updated
	m.configMutex.Unlock()
	m.triggerUpdate()
	return nil
}

func (m *Manager) SetUseIPLocation(use bool) {
	m.configMutex.Lock()
	if m.config.UseIPLocation == use {
		m.configMutex.Unlock()
		return
	}
	m.config.UseIPLocation = use
	if use {
		m.config.Latitude = nil
		m.config.Longitude = nil
	}
	m.configMutex.Unlock()

	if use {
		m.locationMutex.Lock()
		m.cachedIPLat = nil
		m.cachedIPLon = nil
		m.locationMutex.Unlock()
	}
	m.triggerUpdate()
}

func (m *Manager) SetManualTimes(sunrise, sunset time.Time, duration *time.Duration) error {
	m.configMutex.Lock()
	if m.config.ManualSunrise != nil && m.config.ManualSunset != nil &&
		m.config.ManualSunrise.Hour() == sunrise.Hour() && m.config.ManualSunrise.Minute() == sunrise.Minute() &&
		m.config.ManualSunset.Hour() == sunset.Hour() && m.config.ManualSunset.Minute() == sunset.Minute() &&
		durationEqual(m.config.ManualDuration, duration) {
		m.configMutex.Unlock()
		return nil
	}
	updated := m.config
	updated.ManualSunrise = &sunrise
	updated.ManualSunset = &sunset
	updated.ManualDuration = duration
	if err := updated.Validate(); err != nil {
		m.configMutex.Unlock()
		return err
	}
	m.config = updated
	m.configMutex.Unlock()
	m.triggerUpdate()
	return nil
}

func (m *Manager) ClearManualTimes() {
	m.configMutex.Lock()
	if m.config.ManualSunrise == nil && m.config.ManualSunset == nil && m.config.ManualDuration == nil {
		m.configMutex.Unlock()
		return
	}
	m.config.ManualSunrise = nil
	m.config.ManualSunset = nil
	m.config.ManualDuration = nil
	m.configMutex.Unlock()
	m.triggerUpdate()
}

func durationEqual(a, b *time.Duration) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}

func (m *Manager) Adjustments() (gamma, contrast float64) {
	m.configMutex.RLock()
	defer m.configMutex.RUnlock()
	return m.config.Gamma, m.config.Contrast
}

func (m *Manager) SetAdjustments(gamma, contrast float64) error {
	m.configMutex.Lock()
	if m.config.Gamma == gamma && m.config.Contrast == contrast {
		m.configMutex.Unlock()
		return nil
	}
	updated := m.config
	updated.Gamma = gamma
	updated.Contrast = contrast
	if err := updated.Validate(); err != nil {
		m.configMutex.Unlock()
		return err
	}
	m.config = updated
	m.configMutex.Unlock()
	m.syncControls()
	return nil
}

func (m *Manager) SetEnabled(enabled bool) {
	m.configMutex.Lock()
	if m.config.Enabled == enabled {
		m.configMutex.Unlock()
		return
	}
	m.config.Enabled = enabled
	m.configMutex.Unlock()
	m.syncControls()
}

func (m *Manager) needsControls() bool {
	m.configMutex.RLock()
	defer m.configMutex.RUnlock()
	return m.config.Enabled ||
		m.config.Gamma != 1.0 ||
		m.config.Contrast != 1.0 ||
		len(m.config.ICCProfiles) > 0 ||
		len(m.config.OutputTemps) > 0 ||
		len(m.config.OutputBrightness) > 0
}

func (m *Manager) syncControls() {
	m.post(func() {
		switch {
		case m.needsControls() && !m.controlsInitialized:
			m.createControls()
		case !m.needsControls() && m.controlsInitialized:
			m.destroyControls()
		default:
			m.triggerUpdate()
		}
	})
}

// ensureOutputControls creates the gamma controls when the manager has none.
// Called on the wayland actor goroutine. A default install (night light off,
// gamma and contrast neutral, no profile, no override) has no controls, but
// applying an ICC profile or a per-output temperature still needs them.
func (m *Manager) ensureOutputControls() bool {
	if m.controlsInitialized {
		return true
	}
	gammaMgr, ok := m.gammaControl.(*wlr_gamma_control.ZwlrGammaControlManagerV1)
	if !ok || gammaMgr == nil {
		log.Warn("icc: gamma control manager not available")
		return false
	}
	m.availOutputsMu.RLock()
	outs := slices.Clone(m.availableOutputs)
	m.availOutputsMu.RUnlock()
	if err := m.setupOutputControls(outs, gammaMgr); err != nil {
		log.Errorf("icc: failed to initialize output controls: %v", err)
		return false
	}
	m.controlsInitialized = true
	log.Info("icc: output controls initialized (gamma was disabled)")
	return true
}

func (m *Manager) createControls() {
	gammaMgr := m.gammaControl.(*wlr_gamma_control.ZwlrGammaControlManagerV1)
	m.availOutputsMu.RLock()
	outs := slices.Clone(m.availableOutputs)
	m.availOutputsMu.RUnlock()
	if err := m.setupOutputControls(outs, gammaMgr); err != nil {
		log.Errorf("gamma: failed to create controls: %v", err)
		return
	}
	m.controlsInitialized = true
	// Recreated controls carry fresh output state, so the snapshot has to
	// follow it rather than keep reporting what the old state held.
	m.publishICCState()
	m.triggerUpdate()
}

func (m *Manager) destroyControls() {
	m.outputs.Range(func(_ uint32, out *outputState) bool {
		if out.gammaControl != nil {
			out.gammaControl.(*wlr_gamma_control.ZwlrGammaControlV1).Destroy()
		}
		return true
	})
	m.outputs.Range(func(key uint32, _ *outputState) bool {
		m.outputs.Delete(key)
		return true
	})
	m.controlsInitialized = false
	m.publishICCState()
}

// loadConfiguredICC attaches the configured ICC profiles and per-output
// temperatures to the outputs that are already known, and reports whether
// anything was attached.
func (m *Manager) loadConfiguredICC() bool {
	config := m.configSnapshot()
	iccProfiles := config.ICCProfiles
	outputTemps := config.OutputTemps

	if len(iccProfiles) == 0 && len(outputTemps) == 0 && len(config.OutputBrightness) == 0 {
		return false
	}

	attached := 0
	m.outputs.Range(func(_ uint32, out *outputState) bool {
		name, ok := m.outputNames.Load(out.id)
		if !ok {
			return true
		}
		if m.applyConfiguredICCForOutput(out, name, config) {
			attached++
		}
		return true
	})

	log.Infof("icc: config has %d profile(s) and %d temperature override(s), attached to %d output(s)",
		len(iccProfiles), len(outputTemps), attached)
	m.publishICCState()
	return attached > 0
}

// attachConfiguredICC attaches the configured profile and temperature to an
// output whose name just became known, so a hotplugged output comes up
// corrected without an explicit re-apply.
func (m *Manager) attachConfiguredICC(outputID uint32, outputName string) {
	config := m.configSnapshot()
	iccProfiles := config.ICCProfiles
	outputTemps := config.OutputTemps

	if len(iccProfiles) == 0 && len(outputTemps) == 0 && len(config.OutputBrightness) == 0 {
		m.publishICCState()
		return
	}

	changed := false
	m.outputs.Range(func(_ uint32, out *outputState) bool {
		if out.id != outputID {
			return true
		}
		changed = m.applyConfiguredICCForOutput(out, outputName, config)
		if changed {
			log.Infof("icc: attached configured profile/temperature to output %s", outputName)
			out.lastTemp = 0
		}
		return false
	})

	// Publish either way: a hotplugged output is new to the snapshot even when
	// it has no configured profile or temperature.
	m.publishICCState()

	if changed {
		m.applyCurrentTemp("output-name")
	}
}

// applyConfiguredICCForOutput applies the configured profile and temperature of
// one output and reports whether anything changed.
func (m *Manager) applyConfiguredICCForOutput(out *outputState, outputName string, config Config) bool {
	changed := false

	if temp, ok := config.OutputTemps[outputName]; ok {
		out.outputTemp = temp
		changed = true
	}

	if percent, ok := config.OutputBrightness[outputName]; ok {
		out.dimScale = brightnessScale(percent)
		changed = true
	}

	if profileName, ok := config.ICCProfiles[outputName]; ok {
		iccPath := resolveICCProfile(profileName)
		profile, err := icc.ParseFile(iccPath)
		switch {
		case err != nil:
			log.Warnf("icc: failed to load profile for output %q: %v", outputName, err)
		case !profile.HasVCGT:
			// Only vcgt can be written to the GPU ramp; the TRC curve describes
			// the display itself and would wash the output out if applied.
			log.Warnf("icc: profile %q for output %q has no vcgt table, not attaching it", iccPath, outputName)
		default:
			out.iccPath = iccPath
			out.iccProfile = profile
			changed = true
		}
	}

	return changed
}

// validateOutputName rejects names no wl_output can report, so a typo or an
// empty argument cannot persist an entry in icc.json that nothing will ever
// match.
func validateOutputName(name string) error {
	switch {
	case name == "":
		return errors.New("icc: output name is required")
	case strings.TrimSpace(name) != name:
		return fmt.Errorf("icc: output name %q has surrounding whitespace", name)
	}
	return nil
}

// validateICCProfilePath rejects relative paths, the daemon does not share the caller's working directory.
func validateICCProfilePath(path string) error {
	switch {
	case path == "":
		return errors.New("icc: profile path is required")
	case !filepath.IsAbs(path):
		return fmt.Errorf("icc: profile path %q must be absolute", path)
	}
	return nil
}

// ApplyICC copies an ICC profile into ICCProfilesDir and applies it to an output.
// outputName is the wl_output name (e.g., "DP-1").
func (m *Manager) ApplyICC(outputName, iccPath string) error {
	if err := validateOutputName(outputName); err != nil {
		return err
	}
	if err := validateICCProfilePath(iccPath); err != nil {
		return err
	}

	profile, err := icc.ParseFile(iccPath)
	if err != nil {
		return fmt.Errorf("icc: failed to parse %s: %w", iccPath, err)
	}
	if profile.ColorSpace != "RGB" {
		return fmt.Errorf("icc: unsupported color space %q, only RGB supported", profile.ColorSpace)
	}
	// Only vcgt holds a video card gamma table, which is what the GPU ramp
	// takes. The TRC tags describe the display's own transfer function, so a
	// profile without vcgt has no correction to apply.
	if !profile.HasVCGT {
		return fmt.Errorf("icc: %s has no vcgt table, so it has no gamma ramp to apply", iccPath)
	}

	profilesDir := ICCProfilesDir()
	profileName, err := stageICCProfile(profilesDir, iccPath)
	if err != nil {
		return fmt.Errorf("icc: failed to store %s in %s: %w", iccPath, profilesDir, err)
	}
	stagedPath := filepath.Join(profilesDir, profileName)

	m.post(func() {
		defer m.updateStateFromSchedule()

		// ICC works with the night light off, but the gamma controls that carry
		// the ramp may not exist yet, so create them before attaching.
		if !m.ensureOutputControls() {
			return
		}

		var targetOutput *outputState
		m.outputs.Range(func(_ uint32, out *outputState) bool {
			if name, ok := m.outputNames.Load(out.id); ok && name == outputName {
				targetOutput = out
				return false
			}
			return true
		})
		if targetOutput == nil {
			log.Warnf("icc: output %q not found", outputName)
			return
		}

		targetOutput.iccPath = stagedPath
		targetOutput.iccProfile = profile
		m.publishICCState()

		// The new profile is invisible to the per-output dedup, so clear this
		// output's state to force a fresh ramp.
		targetOutput.lastTemp = 0
		m.applyCurrentTemp("icc-apply")
	})

	m.configMutex.Lock()
	if m.config.ICCProfiles == nil {
		m.config.ICCProfiles = make(map[string]string)
	}
	m.config.ICCProfiles[outputName] = profileName
	savedConfig := cloneConfig(m.config)
	m.configMutex.Unlock()

	if err := SaveICCConfig(savedConfig); err != nil {
		log.Warnf("icc: failed to save config: %v", err)
	}

	return nil
}

// RemoveICC removes the ICC profile from a specific output, reverting to temperature-based gamma.
func (m *Manager) RemoveICC(outputName string) error {
	if err := validateOutputName(outputName); err != nil {
		return err
	}

	m.configMutex.Lock()
	delete(m.config.ICCProfiles, outputName)
	savedConfig := cloneConfig(m.config)
	m.configMutex.Unlock()

	if err := SaveICCConfig(savedConfig); err != nil {
		log.Warnf("icc: failed to save config: %v", err)
	}

	m.post(func() {
		defer m.updateStateFromSchedule()

		m.outputs.Range(func(_ uint32, out *outputState) bool {
			if name, ok := m.outputNames.Load(out.id); ok && name == outputName {
				if out.iccPath == "" {
					return false
				}
				out.iccPath = ""
				out.iccProfile = nil
				out.lastTemp = 0
				return false
			}
			return true
		})
		if m.releaseIdleControls() {
			return
		}
		m.publishICCState()
		m.applyCurrentTemp("icc-remove")
	})

	return nil
}

// releaseIdleControls tears the gamma controls down once nothing needs them,
// so another gamma client can take over. Called on the wayland actor goroutine.
func (m *Manager) releaseIdleControls() bool {
	if m.needsControls() || !m.controlsInitialized {
		return false
	}
	m.destroyControls()
	return true
}

// publishICCState republishes the ICC snapshot the getters serve. The
// per-output ICC fields are written on the wayland actor goroutine only, so
// this must run there; the getters are called from the IPC handlers, the CLI
// and the scheduler goroutine, which is why they never touch those fields.
// Publishing on ICC changes rather than on every state push also keeps the
// per-profile stat below out of the night light animation path. The status map
// reflects what is attached to an output; the temperature map reports the
// configured value, so a value set for an output that is not known yet is still
// reported instead of snapping the settings slider back to "Default".
func (m *Manager) publishICCState() {
	status := make(map[string]*ICCStatus)
	temps := make(map[string]int)
	refused := []string{}

	m.configMutex.RLock()
	for name, temp := range m.config.OutputTemps {
		if temp != 0 {
			temps[name] = temp
		}
	}
	m.configMutex.RUnlock()

	m.outputs.Range(func(_ uint32, out *outputState) bool {
		name, ok := m.outputNames.Load(out.id)
		if !ok {
			return true
		}
		if _, configured := temps[name]; !configured && out.outputTemp != 0 {
			temps[name] = out.outputTemp
		}
		if out.iccPath != "" {
			status[name] = describeICCProfile(out.iccPath, out.iccProfile)
		}
		if out.gammaRefused {
			refused = append(refused, name)
		}
		return true
	})
	slices.Sort(refused)

	m.iccStateMutex.Lock()
	m.iccStatus = status
	m.iccTemps = temps
	m.iccRefused = refused
	m.iccStateMutex.Unlock()
}

// describeICCProfile builds the record served to the CLI and the settings UI.
// It is the only place that stats the profile file.
func describeICCProfile(path string, profile *icc.Profile) *ICCStatus {
	status := &ICCStatus{
		Path:   path,
		Active: profile != nil,
	}
	if profile != nil {
		status.Description = profile.Description
		status.Version = profile.Version
		status.ColorSpace = profile.ColorSpace
		status.Class = profile.Class
		status.HasVCGT = profile.HasVCGT
		status.TRCKind, status.TRCGamma, status.TRCEntries = profile.TRCKind()
		if profile.VCGT != nil {
			status.VCGTChannels = profile.VCGT.Channels
			status.VCGTEntries = profile.VCGT.Entries
		}
		if x, y, ok := profile.WhitePointXY(); ok {
			status.WhitePointX = x
			status.WhitePointY = y
			status.WhitePointCCT = profile.WhitePointCCT()
			status.WhitePointName = profile.WhitePointName()
		}
	}
	if info, err := os.Stat(path); err == nil {
		status.Size = info.Size()
		status.Modified = info.ModTime().Unix()
	}
	return status
}

// GetICCStatus returns the published ICC status for all outputs.
func (m *Manager) GetICCStatus() map[string]*ICCStatus {
	m.iccStateMutex.RLock()
	defer m.iccStateMutex.RUnlock()
	return maps.Clone(m.iccStatus)
}

// ListOutputs returns a list of all output names for ICC assignment.
func (m *Manager) ListOutputs() []string {
	var names []string
	m.outputNames.Range(func(_ uint32, name string) bool {
		names = append(names, name)
		return true
	})
	slices.Sort(names)
	return names
}

// SetOutputTemp sets a per-output color temperature (1000K-10000K).
// A value of 0 resets to the global default.
func (m *Manager) SetOutputTemp(outputName string, temp int) error {
	if err := validateOutputName(outputName); err != nil {
		return err
	}
	if temp != 0 && (temp < 1000 || temp > 10000) {
		return fmt.Errorf("temperature %d out of range (1000-10000)", temp)
	}

	// Persist first: on a default install (night light off, no profile) no
	// gamma control exists yet, and the stored value is what makes
	// needsControls() true for the controls the apply below creates.
	m.configMutex.Lock()
	if m.config.OutputTemps == nil {
		m.config.OutputTemps = make(map[string]int)
	}
	if temp == 0 {
		delete(m.config.OutputTemps, outputName)
	} else {
		m.config.OutputTemps[outputName] = temp
	}
	savedConfig := cloneConfig(m.config)
	m.configMutex.Unlock()

	if err := SaveICCConfig(savedConfig); err != nil {
		log.Warnf("icc: failed to save config: %v", err)
	}

	m.post(func() {
		defer m.updateStateFromSchedule()

		if m.releaseIdleControls() {
			return
		}
		if !m.needsControls() {
			m.publishICCState()
			return
		}

		// Without controls there are no outputs to write a ramp for, which is
		// why the slider and `dms icc set-temp` used to do nothing until a
		// restart on an install that had never enabled the night light.
		m.ensureOutputControls()

		m.outputs.Range(func(_ uint32, out *outputState) bool {
			if name, ok := m.outputNames.Load(out.id); ok && name == outputName {
				if out.outputTemp == temp {
					return false
				}
				out.outputTemp = temp
				out.lastTemp = 0
				m.publishICCState()
				m.applyCurrentTemp("output-temp-change")
				return false
			}
			return true
		})

		// An output whose name is not known yet picks the value up through
		// attachConfiguredICC; the published state carries the configured value
		// either way, so the settings slider does not snap back to Default.
		m.publishICCState()
	})

	return nil
}

// SetOutputBrightness dims an output through its gamma ramp, for outputs
// without a backlight or DDC/CI. 100 removes the override.
func (m *Manager) SetOutputBrightness(outputName string, percent int) error {
	if err := validateOutputName(outputName); err != nil {
		return err
	}
	percent = min(max(percent, 0), 100)

	m.configMutex.Lock()
	current, configured := m.config.OutputBrightness[outputName]
	if (configured && current == percent) || (!configured && percent == 100) {
		m.configMutex.Unlock()
		return nil
	}
	if m.config.OutputBrightness == nil {
		m.config.OutputBrightness = make(map[string]int)
	}
	if percent == 100 {
		delete(m.config.OutputBrightness, outputName)
	} else {
		m.config.OutputBrightness[outputName] = percent
	}
	savedConfig := cloneConfig(m.config)
	m.configMutex.Unlock()

	if err := SaveICCConfig(savedConfig); err != nil {
		log.Warnf("gamma: failed to save config: %v", err)
	}

	scale := brightnessScale(percent)
	if percent == 100 {
		scale = 0
	}

	m.post(func() {
		defer m.updateStateFromSchedule()

		if m.releaseIdleControls() {
			return
		}
		if !m.ensureOutputControls() {
			return
		}

		m.outputs.Range(func(_ uint32, out *outputState) bool {
			if name, ok := m.outputNames.Load(out.id); !ok || name != outputName {
				return true
			}
			out.dimScale = scale
			out.lastTemp = 0
			m.applyCurrentTemp("output-brightness-change")
			return false
		})
	})

	return nil
}

// GetOutputBrightness returns the configured software brightness per output;
// outputs at full brightness are absent.
func (m *Manager) GetOutputBrightness() map[string]int {
	m.configMutex.RLock()
	defer m.configMutex.RUnlock()
	return maps.Clone(m.config.OutputBrightness)
}

// GammaRefusedOutputs returns the outputs whose gamma control the compositor
// refused, so software brightness cannot dim them.
func (m *Manager) GammaRefusedOutputs() []string {
	m.iccStateMutex.RLock()
	defer m.iccStateMutex.RUnlock()
	return slices.Clone(m.iccRefused)
}

// GetOutputTemps returns the published per-output temperatures.
func (m *Manager) GetOutputTemps() map[string]int {
	m.iccStateMutex.RLock()
	defer m.iccStateMutex.RUnlock()
	return maps.Clone(m.iccTemps)
}

func (m *Manager) Close() {
	close(m.stopChan)
	m.wg.Wait()
	m.notifierWg.Wait()

	m.subscribers.Range(func(key string, ch chan State) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})

	m.outputs.Range(func(_ uint32, out *outputState) bool {
		if ctrl, ok := out.gammaControl.(*wlr_gamma_control.ZwlrGammaControlV1); ok {
			ctrl.Destroy()
		}
		return true
	})
	m.outputs.Range(func(key uint32, _ *outputState) bool {
		m.outputs.Delete(key)
		return true
	})

	if manager, ok := m.gammaControl.(*wlr_gamma_control.ZwlrGammaControlManagerV1); ok {
		manager.Destroy()
	}

	if m.dbusConn != nil {
		m.dbusConn.RemoveSignal(m.dbusSignal)
		m.dbusConn.BusObject().Call("org.freedesktop.DBus.RemoveMatch", 0, prepareForSleepMatchRule)
	}
}
