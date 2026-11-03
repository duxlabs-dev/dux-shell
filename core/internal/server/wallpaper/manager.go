package wallpaper

import (
	"reflect"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/loginctl"
)

type activeSchedule struct {
	cfg      ScheduleConfig
	nextFire time.Time
}

// Grace period before a missed-while-off schedule fires, so a freshly
// connected frontend has its cycle-seq baseline before the bump arrives.
var catchUpDelay = 3 * time.Second

type Manager struct {
	config      Config
	configMutex sync.RWMutex

	state      *State
	stateMutex sync.RWMutex

	subscribers syncmap.Map[string, chan State]

	stopChan      chan struct{}
	updateTrigger chan struct{}
	resetReq      chan string
	wg            sync.WaitGroup

	// Owned by schedulerLoop after start; keyed like schedules ("" = global).
	lastFires    map[string]time.Time
	persistFires func(map[string]time.Time)
}

func NewManager() *Manager {
	return newManager(loadLastFires(), saveLastFires)
}

func newManager(lastFires map[string]time.Time, persistFires func(map[string]time.Time)) *Manager {
	if lastFires == nil {
		lastFires = map[string]time.Time{}
	}
	m := &Manager{
		config: Config{
			Global:   ScheduleConfig{Mode: "interval", IntervalSec: 300, Time: "06:00"},
			Monitors: map[string]ScheduleConfig{},
		},
		stopChan:      make(chan struct{}),
		updateTrigger: make(chan struct{}, 1),
		resetReq:      make(chan string, 8),
		lastFires:     lastFires,
		persistFires:  persistFires,
	}
	m.state = &State{Config: m.getConfig()}

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

func (m *Manager) SetConfig(config Config) {
	if config.Monitors == nil {
		config.Monitors = map[string]ScheduleConfig{}
	}
	m.configMutex.Lock()
	if reflect.DeepEqual(m.config, config) {
		m.configMutex.Unlock()
		return
	}
	m.config = config
	m.configMutex.Unlock()
	m.TriggerUpdate()
}

func (m *Manager) ResetSchedule(target string) {
	select {
	case m.resetReq <- target:
	default:
	}
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
	ch := lm.Subscribe("wallpaper")
	m.wg.Go(func() {
		defer lm.Unsubscribe("wallpaper")
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

	schedules := map[string]*activeSchedule{}
	resets := map[string]bool{}
	var seq uint64
	var timer *time.Timer

	for {
		now := time.Now()
		config := m.getConfig()
		active := activeSchedules(config)

		for key := range schedules {
			if _, ok := active[key]; !ok {
				delete(schedules, key)
			}
		}
		firesDirty := false
		for key, cfg := range active {
			s, ok := schedules[key]
			switch {
			case !ok:
				s = &activeSchedule{cfg: cfg, nextFire: computeNext(now, cfg)}
				schedules[key] = s
				if cfg.Mode == "time" {
					last := m.lastFires[key]
					prev, valid := prevDailyTime(now, cfg.Time)
					switch {
					case last.IsZero():
						// First enable (or no history): seed instead of firing.
						m.lastFires[key] = now
						firesDirty = true
					case valid && last.Before(prev):
						// Scheduled time passed while dms wasn't running.
						s.nextFire = now.Add(catchUpDelay)
					}
				}
			case s.cfg != cfg || resets[key]:
				s.cfg = cfg
				s.nextFire = computeNext(now, cfg)
			}
			delete(resets, key)
		}

		var dueKeys []string
		for key, s := range schedules {
			if !s.nextFire.After(now) {
				dueKeys = append(dueKeys, key)
				s.nextFire = computeNext(now, s.cfg)
				if s.cfg.Mode == "time" {
					m.lastFires[key] = now
					firesDirty = true
				}
			}
		}

		if firesDirty {
			for key := range m.lastFires {
				if _, ok := schedules[key]; !ok {
					delete(m.lastFires, key)
				}
			}
			m.persistFires(m.lastFires)
		}

		next, hasNext := soonest(schedules)
		if len(dueKeys) == 0 {
			m.setState(config, next, seq, "")
		}
		for _, key := range dueKeys {
			seq++
			m.setState(config, next, seq, key)
		}

		waitDur := 24 * time.Hour
		if hasNext {
			waitDur = max(time.Until(next), time.Second)
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
		case key := <-m.resetReq:
			timer.Stop()
			resets[key] = true
		case <-timer.C:
		}
	}
}

func (m *Manager) setState(config Config, next time.Time, seq uint64, target string) {
	newState := State{Config: config, NextRotation: next, CycleSeq: seq, Target: target}

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

func activeSchedules(config Config) map[string]ScheduleConfig {
	out := map[string]ScheduleConfig{}
	if config.PerMonitor {
		for name, cfg := range config.Monitors {
			if cfg.Enabled {
				out[name] = cfg
			}
		}
		return out
	}
	if config.Global.Enabled {
		out[""] = config.Global
	}
	return out
}

func computeNext(now time.Time, cfg ScheduleConfig) time.Time {
	switch cfg.Mode {
	case "time":
		return nextDailyTime(now, cfg.Time)
	default:
		sec := max(cfg.IntervalSec, 1)
		return now.Add(time.Duration(sec) * time.Second)
	}
}

func nextDailyTime(now time.Time, hhmm string) time.Time {
	hour, minute, ok := parseHHMM(hhmm)
	if !ok {
		return now.Add(24 * time.Hour)
	}
	next := time.Date(now.Year(), now.Month(), now.Day(), hour, minute, 0, 0, now.Location())
	if !next.After(now) {
		next = next.Add(24 * time.Hour)
	}
	return next
}

func prevDailyTime(now time.Time, hhmm string) (time.Time, bool) {
	hour, minute, ok := parseHHMM(hhmm)
	if !ok {
		return time.Time{}, false
	}
	prev := time.Date(now.Year(), now.Month(), now.Day(), hour, minute, 0, 0, now.Location())
	if prev.After(now) {
		prev = prev.Add(-24 * time.Hour)
	}
	return prev, true
}

func parseHHMM(hhmm string) (int, int, bool) {
	parts := strings.Split(hhmm, ":")
	if len(parts) != 2 {
		return 0, 0, false
	}
	hour, err := strconv.Atoi(parts[0])
	if err != nil || hour < 0 || hour > 23 {
		return 0, 0, false
	}
	minute, err := strconv.Atoi(parts[1])
	if err != nil || minute < 0 || minute > 59 {
		return 0, 0, false
	}
	return hour, minute, true
}

func soonest(schedules map[string]*activeSchedule) (time.Time, bool) {
	var best time.Time
	found := false
	for _, s := range schedules {
		if !found || s.nextFire.Before(best) {
			best = s.nextFire
			found = true
		}
	}
	return best, found
}

func statesEqual(a, b *State) bool {
	switch {
	case a == nil || b == nil:
		return a == b
	case a.CycleSeq != b.CycleSeq:
		return false
	case a.Target != b.Target:
		return false
	case !a.NextRotation.Equal(b.NextRotation):
		return false
	}
	return reflect.DeepEqual(a.Config, b.Config)
}
