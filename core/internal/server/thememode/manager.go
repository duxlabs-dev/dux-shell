package thememode

import (
	"errors"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/geolocation"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/loginctl"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wayland"
)

const (
	defaultStartHour         = 18
	defaultStartMinute       = 0
	defaultEndHour           = 6
	defaultEndMinute         = 0
	defaultElevationTwilight = -6.0
	defaultElevationDaylight = 3.0
)

type Manager struct {
	config      Config
	configMutex sync.RWMutex

	state      *State
	stateMutex sync.RWMutex

	subscribers syncmap.Map[string, chan State]

	locationMutex sync.RWMutex
	cachedIPLat   *float64
	cachedIPLon   *float64

	geoClient geolocation.Client

	stopChan      chan struct{}
	updateTrigger chan struct{}
	wg            sync.WaitGroup
}

func NewManager() *Manager {
	m := &Manager{
		config: Config{
			Enabled:           false,
			Mode:              "time",
			StartHour:         defaultStartHour,
			StartMinute:       defaultStartMinute,
			EndHour:           defaultEndHour,
			EndMinute:         defaultEndMinute,
			ElevationTwilight: defaultElevationTwilight,
			ElevationDaylight: defaultElevationDaylight,
		},
		stopChan:      make(chan struct{}),
		updateTrigger: make(chan struct{}, 1),
	}

	m.updateState(time.Now())

	m.wg.Add(1)
	go m.schedulerLoop()

	return m
}

func (m *Manager) GetState() State {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	if m.state == nil {
		return State{Config: m.getConfig()}
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

func (m *Manager) SetEnabled(enabled bool) {
	m.configMutex.Lock()
	if m.config.Enabled == enabled {
		m.configMutex.Unlock()
		return
	}
	m.config.Enabled = enabled
	m.configMutex.Unlock()
	m.TriggerUpdate()
}

func (m *Manager) SetMode(mode string) {
	m.configMutex.Lock()
	if m.config.Mode == mode {
		m.configMutex.Unlock()
		return
	}
	m.config.Mode = mode
	m.configMutex.Unlock()
	m.TriggerUpdate()
}

func (m *Manager) SetSchedule(startHour, startMinute, endHour, endMinute int) {
	m.configMutex.Lock()
	changed := m.config.StartHour != startHour ||
		m.config.StartMinute != startMinute ||
		m.config.EndHour != endHour ||
		m.config.EndMinute != endMinute
	if !changed {
		m.configMutex.Unlock()
		return
	}
	m.config.StartHour = startHour
	m.config.StartMinute = startMinute
	m.config.EndHour = endHour
	m.config.EndMinute = endMinute
	m.configMutex.Unlock()
	m.TriggerUpdate()
}

func (m *Manager) SetLocation(lat, lon float64) {
	m.configMutex.Lock()
	if m.config.Latitude != nil && m.config.Longitude != nil &&
		*m.config.Latitude == lat && *m.config.Longitude == lon && !m.config.UseIPLocation {
		m.configMutex.Unlock()
		return
	}
	m.config.Latitude = &lat
	m.config.Longitude = &lon
	m.config.UseIPLocation = false
	m.configMutex.Unlock()

	m.locationMutex.Lock()
	m.cachedIPLat = nil
	m.cachedIPLon = nil
	m.locationMutex.Unlock()

	m.TriggerUpdate()
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

	m.TriggerUpdate()
}

func (m *Manager) TriggerUpdate() {
	select {
	case m.updateTrigger <- struct{}{}:
	default:
	}
}

func (m *Manager) Close() {
	select {
	case <-m.stopChan:
		return
	default:
		close(m.stopChan)
	}
	m.wg.Wait()
	m.subscribers.Range(func(key string, ch chan State) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})
}

func (m *Manager) WatchLoginctl(lm *loginctl.Manager) {
	ch := lm.Subscribe("thememode")
	m.wg.Go(func() {
		defer lm.Unsubscribe("thememode")
		for {
			select {
			case <-m.stopChan:
				return
			case state, ok := <-ch:
				if !ok {
					return
				}
				if state.PreparingForSleep {
					continue
				}
				m.TriggerUpdate()
			}
		}
	})
}

func (m *Manager) schedulerLoop() {
	defer m.wg.Done()

	var timer *time.Timer
	for {
		config := m.getConfig()
		now := time.Now()
		var isLight bool
		var next time.Time
		if config.Enabled {
			isLight, next = m.computeSchedule(now, config)
		} else {
			m.stateMutex.RLock()
			if m.state != nil {
				isLight = m.state.IsLight
			}
			m.stateMutex.RUnlock()
			next = now.Add(24 * time.Hour)
		}

		m.updateStateWithValues(config, isLight, next)

		waitDur := time.Until(next)
		if !config.Enabled {
			waitDur = 24 * time.Hour
		}
		if waitDur < time.Second {
			waitDur = time.Second
		}

		if timer != nil {
			timer.Stop()
		}
		timer = time.NewTimer(waitDur)

		select {
		case <-m.stopChan:
			timer.Stop()
			return
		case <-m.updateTrigger:
			timer.Stop()
			continue
		case <-timer.C:
			continue
		}
	}
}

func (m *Manager) updateState(now time.Time) {
	config := m.getConfig()
	var isLight bool
	var next time.Time
	if config.Enabled {
		isLight, next = m.computeSchedule(now, config)
	} else {
		m.stateMutex.RLock()
		if m.state != nil {
			isLight = m.state.IsLight
		}
		m.stateMutex.RUnlock()
		next = now.Add(24 * time.Hour)
	}
	m.updateStateWithValues(config, isLight, next)
}

func (m *Manager) updateStateWithValues(config Config, isLight bool, next time.Time) {
	newState := State{
		Config:         config,
		IsLight:        isLight,
		NextTransition: next,
	}

	m.stateMutex.Lock()
	if m.state != nil && statesEqual(m.state, &newState) {
		m.stateMutex.Unlock()
		return
	}
	m.state = &newState
	m.stateMutex.Unlock()

	m.notifySubscribers()
}

func (m *Manager) notifySubscribers() {
	state := m.GetState()
	m.subscribers.Range(func(key string, ch chan State) bool {
		select {
		case ch <- state:
		default:
		}
		return true
	})
}

func (m *Manager) getConfig() Config {
	m.configMutex.RLock()
	defer m.configMutex.RUnlock()
	return m.config
}

func (m *Manager) SetGeoClient(client geolocation.Client) {
	m.geoClient = client
}

func (m *Manager) getLocation(config Config) (*float64, *float64) {
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

func statesEqual(a, b *State) bool {
	if a == nil || b == nil {
		return a == b
	}
	if a.IsLight != b.IsLight || !a.NextTransition.Equal(b.NextTransition) {
		return false
	}
	return a.Config == b.Config
}

func (m *Manager) computeSchedule(now time.Time, config Config) (bool, time.Time) {
	switch config.Mode {
	case "location":
		return m.computeLocationSchedule(now, config)
	default:
		return computeTimeSchedule(now, config)
	}
}

func computeTimeSchedule(now time.Time, config Config) (bool, time.Time) {
	startMinutes := config.StartHour*60 + config.StartMinute
	endMinutes := config.EndHour*60 + config.EndMinute
	currentMinutes := now.Hour()*60 + now.Minute()

	startTime := time.Date(now.Year(), now.Month(), now.Day(), config.StartHour, config.StartMinute, 0, 0, now.Location())
	endTime := time.Date(now.Year(), now.Month(), now.Day(), config.EndHour, config.EndMinute, 0, 0, now.Location())

	if startMinutes == endMinutes {
		next := startTime
		if !next.After(now) {
			next = next.Add(24 * time.Hour)
		}
		return true, next
	}

	if startMinutes < endMinutes {
		if currentMinutes < startMinutes {
			return true, startTime
		}
		if currentMinutes >= endMinutes {
			return true, startTime.Add(24 * time.Hour)
		}
		return false, endTime
	}

	if currentMinutes >= startMinutes {
		return false, endTime.Add(24 * time.Hour)
	}
	if currentMinutes < endMinutes {
		return false, endTime
	}
	return true, startTime
}

func (m *Manager) computeLocationSchedule(now time.Time, config Config) (bool, time.Time) {
	lat, lon := m.getLocation(config)
	if lat == nil || lon == nil {
		currentIsLight := false
		m.stateMutex.RLock()
		if m.state != nil {
			currentIsLight = m.state.IsLight
		}
		m.stateMutex.RUnlock()
		return currentIsLight, now.Add(10 * time.Minute)
	}

	times, cond := wayland.CalculateSunTimesWithTwilight(*lat, *lon, now, config.ElevationTwilight, config.ElevationDaylight)
	switch cond {
	case wayland.SunMidnightSun:
		return true, startOfNextDay(now)
	case wayland.SunPolarNight:
		return false, startOfNextDay(now)
	}

	if now.Before(times.Sunrise) {
		return false, times.Sunrise
	}
	if now.Before(times.Sunset) {
		return true, times.Sunset
	}

	nextDay := startOfNextDay(now)
	nextTimes, nextCond := wayland.CalculateSunTimesWithTwilight(*lat, *lon, nextDay, config.ElevationTwilight, config.ElevationDaylight)
	switch nextCond {
	case wayland.SunMidnightSun:
		return true, startOfNextDay(nextDay)
	case wayland.SunPolarNight:
		return false, startOfNextDay(nextDay)
	}

	return false, nextTimes.Sunrise
}

func startOfNextDay(t time.Time) time.Time {
	next := t.Add(24 * time.Hour)
	return time.Date(next.Year(), next.Month(), next.Day(), 0, 0, 0, 0, next.Location())
}

func validateHourMinute(hour, minute int) bool {
	return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
}

func (m *Manager) ValidateSchedule(startHour, startMinute, endHour, endMinute int) error {
	if !validateHourMinute(startHour, startMinute) || !validateHourMinute(endHour, endMinute) {
		return errInvalidTime
	}
	return nil
}

var errInvalidTime = errors.New("invalid schedule time")
