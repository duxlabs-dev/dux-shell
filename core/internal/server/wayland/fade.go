package wayland

import (
	"math"
	"time"
)

const (
	fadeDuration   = 2500 * time.Millisecond
	fadeInterval   = 50 * time.Millisecond
	fadePendingTTL = time.Second
)

type fadeState struct {
	requested time.Time
	start     time.Time
	from      map[uint32]int
}

func (f *fadeState) running() bool { return !f.start.IsZero() }

func (m *Manager) requestFade() {
	m.fade = &fadeState{requested: time.Now()}
	m.fading.Store(true)
}

func fadeTemp(from, to int, t float64) int {
	switch {
	case t <= 0:
		return from
	case t >= 1:
		return to
	}
	t = t * t * (3 - 2*t)
	fromMired, toMired := 1e6/float64(from), 1e6/float64(to)
	return int(math.Round(1e6 / (fromMired + (toMired-fromMired)*t)))
}

func (m *Manager) beginFade() {
	from := make(map[uint32]int)
	m.outputs.Range(func(id uint32, out *outputState) bool {
		from[id] = out.lastTemp
		return true
	})
	m.fade.start = time.Now()
	m.fade.from = from
}

// dropStaleFade ends a fade that cannot progress because no output is ready.
func (m *Manager) dropStaleFade() {
	f := m.fade
	if f == nil || (!f.running() && time.Since(f.requested) <= fadePendingTTL) {
		return
	}
	m.endFade()
}

func (m *Manager) fadeProgress() float64 {
	return float64(time.Since(m.fade.start)) / float64(fadeDuration)
}

func (m *Manager) fadeTarget(out *outputState, target int) int {
	if m.fade == nil || !m.fade.running() {
		return target
	}
	t := m.fadeProgress()
	if t >= 1 {
		return target
	}
	from := m.fade.from[out.id]
	if from <= 0 {
		from = neutralTemp
	}
	to := target
	if to <= 0 {
		to = neutralTemp
	}
	return fadeTemp(from, to, t)
}

func (m *Manager) stepFade() {
	if m.fade == nil || !m.fade.running() {
		return
	}
	if m.fadeProgress() >= 1 {
		m.endFade()
		return
	}
	if m.fadeTimer != nil {
		m.fadeTimer.Stop()
	}
	m.fadeTimer = time.AfterFunc(fadeInterval, func() {
		m.post(func() { m.applyCurrentTemp("fade") })
	})
}

func (m *Manager) cancelFade() {
	if m.fadeTimer != nil {
		m.fadeTimer.Stop()
		m.fadeTimer = nil
	}
	m.fade = nil
	m.fading.Store(false)
}

func (m *Manager) endFade() {
	m.cancelFade()
	if m.controlsInitialized && !m.needsControls() {
		m.destroyControls()
	}
}
