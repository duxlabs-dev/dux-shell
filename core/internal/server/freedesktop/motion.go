package freedesktop

import (
	"errors"
	"time"

	"github.com/duxlabs-dev/dux-go/dbusutil"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"github.com/godbus/dbus/v5"
)

// Two portal backends serving one namespace each emit SettingChanged, so a
// write echoes more than once.
const motionSettleWindow = 2 * time.Second

// Observed under their gsettings schema names, which the gtk and gnome backends both
// serve; org.freedesktop.appearance reduced-motion exists only with the gnome one.
type motionSource struct {
	namespace string
	key       string
	reduces   func(dbus.Variant) (reduce bool, ok bool)
	write     func(reduce bool) error
}

var motionSources = []motionSource{
	{
		namespace: gnomeA11yInterfaceSchema,
		key:       gnomeReducedMotionKey,
		reduces: func(variant dbus.Variant) (bool, bool) {
			preference, ok := dbusutil.As[string](variant)
			return preference == "reduce", ok
		},
		write: func(reduce bool) error {
			preference := "no-preference"
			if reduce {
				preference = "reduce"
			}
			return utils.GsettingsSet(gnomeA11yInterfaceSchema, gnomeReducedMotionKey, preference)
		},
	},
	{
		namespace: gnomeInterfaceSchema,
		key:       gnomeAnimationsKey,
		reduces: func(variant dbus.Variant) (bool, bool) {
			animate, ok := dbusutil.As[bool](variant)
			return !animate, ok
		},
		write: func(reduce bool) error {
			return utils.GsettingsSetBool(gnomeInterfaceSchema, gnomeAnimationsKey, !reduce)
		},
	},
}

func (s motionSource) id() string {
	return s.namespace + "/" + s.key
}

func findMotionSource(namespace, key string) (motionSource, bool) {
	for _, source := range motionSources {
		if source.namespace == namespace && source.key == key {
			return source, true
		}
	}
	return motionSource{}, false
}

func (m *Manager) readSystemMotion() {
	seen := make(map[string]motionSourceState, len(motionSources))
	reduce := false
	for _, source := range motionSources {
		var variant dbus.Variant
		if err := m.settingsObj.Call(dbusPortalSettingsInterface+".ReadOne", 0, source.namespace, source.key).Store(&variant); err != nil {
			continue
		}
		reduces, ok := source.reduces(variant)
		if !ok {
			continue
		}
		seen[source.id()] = motionSourceState{reduce: reduces}
		reduce = reduce || reduces
	}

	m.motionMu.Lock()
	m.motionSeen = seen
	m.motionMu.Unlock()

	m.stateMutex.Lock()
	m.state.Settings.ReducedMotion = reduce
	m.stateMutex.Unlock()
}

// SetReducedMotion writes sources the portal does not serve blind, so it works without a portal.
func (m *Manager) SetReducedMotion(reduce bool) (ReducedMotionResult, error) {
	m.motionMu.Lock()
	defer m.motionMu.Unlock()

	var failures []error
	wrote := false
	for _, source := range motionSources {
		known, seen := m.motionSeen[source.id()]
		if seen && known.reduce == reduce {
			continue
		}
		if err := source.write(reduce); err != nil {
			failures = append(failures, err)
			continue
		}
		m.motionSeen[source.id()] = motionSourceState{reduce: reduce, settlesAt: time.Now().Add(motionSettleWindow)}
		wrote = true
	}
	if wrote {
		time.AfterFunc(motionSettleWindow, m.settleMotion)
	}

	m.stateMutex.Lock()
	m.state.Settings.ReducedMotion = reduce
	m.state.Settings.ReducedMotionRevision++
	result := ReducedMotionResult{Revision: m.state.Settings.ReducedMotionRevision}
	m.stateMutex.Unlock()

	if len(failures) == len(motionSources) {
		return result, errors.Join(failures...)
	}
	return result, nil
}

func (m *Manager) handleMotionChange(source motionSource, variant dbus.Variant) {
	reduce, ok := source.reduces(variant)
	if !ok {
		return
	}

	m.motionMu.Lock()
	known := m.motionSeen[source.id()]
	settling := time.Now().Before(known.settlesAt)
	if settling {
		known.settlingSignal = &reduce
		m.motionSeen[source.id()] = known
	} else {
		m.motionSeen[source.id()] = motionSourceState{reduce: reduce}
	}
	m.motionMu.Unlock()

	if settling {
		return
	}
	m.followSystemMotion(reduce)
}

func (m *Manager) settleMotion() {
	now := time.Now()
	var external []bool

	m.motionMu.Lock()
	for _, source := range motionSources {
		known, seen := m.motionSeen[source.id()]
		if !seen || known.settlingSignal == nil || now.Before(known.settlesAt) {
			continue
		}
		last := *known.settlingSignal
		if last != known.reduce {
			external = append(external, last)
		}
		m.motionSeen[source.id()] = motionSourceState{reduce: last}
	}
	m.motionMu.Unlock()

	for _, reduce := range external {
		m.followSystemMotion(reduce)
	}
}

func (m *Manager) followSystemMotion(reduce bool) {
	m.stateMutex.Lock()
	changed := m.state.Settings.ReducedMotion != reduce
	if changed {
		m.state.Settings.ReducedMotion = reduce
		m.state.Settings.ReducedMotionRevision++
	}
	m.stateMutex.Unlock()

	if changed {
		m.NotifySubscribers()
	}
}
