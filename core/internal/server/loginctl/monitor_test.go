package loginctl

import (
	"os"
	"sync"
	"testing"
	"time"

	mockdbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestManager_HandleDBusSignal_Lock(t *testing.T) {
	manager := &Manager{
		state: &SessionState{
			Locked:     false,
			LockedHint: false,
		},
		stateMutex: sync.RWMutex{},
		dirty:      make(chan struct{}, 1),
	}

	sig := &dbus.Signal{
		Name: "org.freedesktop.login1.Session.Lock",
	}

	manager.handleDBusSignal(sig)

	manager.stateMutex.RLock()
	defer manager.stateMutex.RUnlock()
	assert.True(t, manager.state.Locked)
	assert.True(t, manager.state.LockedHint)
}

func TestManager_HandleDBusSignal_Unlock(t *testing.T) {
	tests := []struct {
		name           string
		keepLock       bool
		call           *dbus.Call // logind's GetAll answer; nil means no session object
		wantLocked     bool
		wantLockedHint bool
	}{
		{name: "logind cleared LockedHint", call: lockedHintCall(false)},
		{name: "logind still reports LockedHint", call: lockedHintCall(true), wantLockedHint: true},
		{name: "logind unreachable", call: &dbus.Call{Err: assert.AnError}},
		{name: "policy, LockedHint still set", keepLock: true, call: lockedHintCall(true), wantLocked: true, wantLockedHint: true},
		{name: "policy, LockedHint cleared", keepLock: true, call: lockedHintCall(false)},
		{name: "policy, logind unreachable", keepLock: true, call: &dbus.Call{Err: assert.AnError}, wantLocked: true, wantLockedHint: true},
		{name: "policy, no session object", keepLock: true, wantLocked: true, wantLockedHint: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager := &Manager{
				state: &SessionState{
					Locked:     true,
					LockedHint: true,
				},
				stateMutex:       sync.RWMutex{},
				dirty:            make(chan struct{}, 1),
				keepLockOnUnlock: tt.keepLock,
			}
			if tt.call != nil {
				sessionObj := mockdbus.NewMockBusObject(t)
				sessionObj.EXPECT().CallWithContext(mock.Anything, "org.freedesktop.DBus.Properties.GetAll", dbus.Flags(0), "org.freedesktop.login1.Session").Return(tt.call)
				manager.sessionObj = sessionObj
			}
			manager.markLockerReady()

			manager.handleDBusSignal(&dbus.Signal{
				Name: "org.freedesktop.login1.Session.Unlock",
			})

			assert.Equal(t, tt.wantLocked, manager.prelockedReady.Load())
			manager.stateMutex.RLock()
			defer manager.stateMutex.RUnlock()
			assert.Equal(t, tt.wantLocked, manager.state.Locked)
			assert.Equal(t, tt.wantLockedHint, manager.state.LockedHint)
		})
	}
}

func lockedHintCall(lockedHint bool) *dbus.Call {
	return &dbus.Call{Body: []any{map[string]dbus.Variant{
		"LockedHint": dbus.MakeVariant(lockedHint),
	}}}
}

func TestManager_HandleDBusSignal_PrepareForSleep(t *testing.T) {
	t.Run("preparing for sleep - true", func(t *testing.T) {
		manager := &Manager{
			state: &SessionState{
				PreparingForSleep: false,
			},
			stateMutex: sync.RWMutex{},
			dirty:      make(chan struct{}, 1),
		}

		sig := &dbus.Signal{
			Name: "org.freedesktop.login1.Manager.PrepareForSleep",
			Body: []any{true},
		}

		manager.handleDBusSignal(sig)

		manager.stateMutex.RLock()
		defer manager.stateMutex.RUnlock()
		assert.True(t, manager.state.PreparingForSleep)
	})

	t.Run("preparing for sleep - false", func(t *testing.T) {
		manager := &Manager{
			state: &SessionState{
				PreparingForSleep: true,
			},
			stateMutex: sync.RWMutex{},
			dirty:      make(chan struct{}, 1),
		}

		sig := &dbus.Signal{
			Name: "org.freedesktop.login1.Manager.PrepareForSleep",
			Body: []any{false},
		}

		manager.handleDBusSignal(sig)

		manager.stateMutex.RLock()
		defer manager.stateMutex.RUnlock()
		assert.False(t, manager.state.PreparingForSleep)
	})

	t.Run("empty body", func(t *testing.T) {
		manager := &Manager{
			state: &SessionState{
				PreparingForSleep: false,
			},
			stateMutex: sync.RWMutex{},
			dirty:      make(chan struct{}, 1),
		}

		sig := &dbus.Signal{
			Name: "org.freedesktop.login1.Manager.PrepareForSleep",
			Body: []any{},
		}

		manager.handleDBusSignal(sig)

		manager.stateMutex.RLock()
		defer manager.stateMutex.RUnlock()
		assert.False(t, manager.state.PreparingForSleep)
	})
}

func TestManager_PrepareForSleep_LockedHintKeepsInhibitor(t *testing.T) {
	f, err := os.CreateTemp(t.TempDir(), "inhibit")
	require.NoError(t, err)

	manager := &Manager{
		state: &SessionState{
			Locked: true,
		},
		stateMutex:    sync.RWMutex{},
		dirty:         make(chan struct{}, 1),
		inhibitFile:   f,
		fallbackDelay: time.Hour,
	}
	manager.lockBeforeSuspend.Store(true)

	manager.handleDBusSignal(&dbus.Signal{
		Name: "org.freedesktop.login1.Manager.PrepareForSleep",
		Body: []any{true},
	})

	assert.Same(t, f, manager.inhibitFile)
	assert.True(t, manager.inSleepCycle.Load())

	manager.markLockerReady()
	manager.inhibitMu.Lock()
	released := manager.inhibitFile
	manager.inhibitMu.Unlock()
	assert.Nil(t, released)
}

func TestManager_PrepareForSleep_PrelockedReadySurvivesAnotherSleep(t *testing.T) {
	f, err := os.CreateTemp(t.TempDir(), "inhibit")
	require.NoError(t, err)

	manager := &Manager{
		state:       &SessionState{},
		stateMutex:  sync.RWMutex{},
		dirty:       make(chan struct{}, 1),
		inhibitFile: f,
	}
	manager.lockBeforeSuspend.Store(true)
	manager.prelockedReady.Store(true)

	manager.handleDBusSignal(&dbus.Signal{
		Name: "org.freedesktop.login1.Manager.PrepareForSleep",
		Body: []any{true},
	})
	assert.Nil(t, manager.inhibitFile)
	assert.True(t, manager.prelockedReady.Load())

	manager.handleDBusSignal(&dbus.Signal{
		Name: "org.freedesktop.login1.Manager.PrepareForSleep",
		Body: []any{false},
	})
	assert.True(t, manager.prelockedReady.Load())

	f2, err := os.CreateTemp(t.TempDir(), "inhibit")
	require.NoError(t, err)
	manager.inhibitFile = f2
	manager.handleDBusSignal(&dbus.Signal{
		Name: "org.freedesktop.login1.Manager.PrepareForSleep",
		Body: []any{true},
	})
	assert.Nil(t, manager.inhibitFile)
	assert.True(t, manager.prelockedReady.Load())
}

func TestManager_PrepareForSleep_KeepsInhibitorUntilLockerReady(t *testing.T) {
	f, err := os.CreateTemp(t.TempDir(), "inhibit")
	require.NoError(t, err)

	manager := &Manager{
		state:         &SessionState{},
		stateMutex:    sync.RWMutex{},
		dirty:         make(chan struct{}, 1),
		inhibitFile:   f,
		fallbackDelay: time.Hour,
	}
	manager.lockBeforeSuspend.Store(true)

	manager.handleDBusSignal(&dbus.Signal{
		Name: "org.freedesktop.login1.Manager.PrepareForSleep",
		Body: []any{true},
	})

	assert.Same(t, f, manager.inhibitFile)
	assert.True(t, manager.inSleepCycle.Load())

	manager.signalLockerReady()

	require.Eventually(t, func() bool {
		manager.inhibitMu.Lock()
		defer manager.inhibitMu.Unlock()
		return manager.inhibitFile == nil
	}, time.Second, 5*time.Millisecond)
}

func TestManager_MarkLockerReady_ClearedOnUnlock(t *testing.T) {
	manager := &Manager{
		state: &SessionState{
			Locked:     true,
			LockedHint: true,
		},
		stateMutex: sync.RWMutex{},
		dirty:      make(chan struct{}, 1),
	}
	manager.markLockerReady()
	assert.True(t, manager.prelockedReady.Load())

	manager.handleDBusSignal(&dbus.Signal{
		Name: "org.freedesktop.login1.Session.Unlock",
	})

	assert.False(t, manager.prelockedReady.Load())
	assert.False(t, manager.state.Locked)
}

func TestManager_HandlePropertiesChanged(t *testing.T) {
	t.Run("active property changed", func(t *testing.T) {
		manager := &Manager{
			state: &SessionState{
				Active: false,
			},
			stateMutex: sync.RWMutex{},
			dirty:      make(chan struct{}, 1),
		}

		sig := &dbus.Signal{
			Name: "org.freedesktop.DBus.Properties.PropertiesChanged",
			Body: []any{
				"org.freedesktop.login1.Session",
				map[string]dbus.Variant{
					"Active": dbus.MakeVariant(true),
				},
			},
		}

		manager.handlePropertiesChanged(sig)

		manager.stateMutex.RLock()
		defer manager.stateMutex.RUnlock()
		assert.True(t, manager.state.Active)
	})

	t.Run("idle hint property changed", func(t *testing.T) {
		manager := &Manager{
			state: &SessionState{
				IdleHint: false,
			},
			stateMutex: sync.RWMutex{},
			dirty:      make(chan struct{}, 1),
		}

		sig := &dbus.Signal{
			Name: "org.freedesktop.DBus.Properties.PropertiesChanged",
			Body: []any{
				"org.freedesktop.login1.Session",
				map[string]dbus.Variant{
					"IdleHint": dbus.MakeVariant(true),
				},
			},
		}

		manager.handlePropertiesChanged(sig)

		manager.stateMutex.RLock()
		defer manager.stateMutex.RUnlock()
		assert.True(t, manager.state.IdleHint)
	})

	t.Run("idle since hint property changed", func(t *testing.T) {
		manager := &Manager{
			state: &SessionState{
				IdleSinceHint: 0,
			},
			stateMutex: sync.RWMutex{},
			dirty:      make(chan struct{}, 1),
		}

		sig := &dbus.Signal{
			Name: "org.freedesktop.DBus.Properties.PropertiesChanged",
			Body: []any{
				"org.freedesktop.login1.Session",
				map[string]dbus.Variant{
					"IdleSinceHint": dbus.MakeVariant(uint64(123456789)),
				},
			},
		}

		manager.handlePropertiesChanged(sig)

		manager.stateMutex.RLock()
		defer manager.stateMutex.RUnlock()
		assert.Equal(t, uint64(123456789), manager.state.IdleSinceHint)
	})

	t.Run("locked hint property changed", func(t *testing.T) {
		manager := &Manager{
			state: &SessionState{
				LockedHint: false,
				Locked:     false,
			},
			stateMutex: sync.RWMutex{},
			dirty:      make(chan struct{}, 1),
		}

		sig := &dbus.Signal{
			Name: "org.freedesktop.DBus.Properties.PropertiesChanged",
			Body: []any{
				"org.freedesktop.login1.Session",
				map[string]dbus.Variant{
					"LockedHint": dbus.MakeVariant(true),
				},
			},
		}

		manager.handlePropertiesChanged(sig)

		manager.stateMutex.RLock()
		defer manager.stateMutex.RUnlock()
		assert.True(t, manager.state.LockedHint)
		assert.True(t, manager.state.Locked)
	})

	t.Run("wrong interface", func(t *testing.T) {
		manager := &Manager{
			state: &SessionState{
				Active: false,
			},
			stateMutex: sync.RWMutex{},
			dirty:      make(chan struct{}, 1),
		}

		sig := &dbus.Signal{
			Name: "org.freedesktop.DBus.Properties.PropertiesChanged",
			Body: []any{
				"org.freedesktop.SomeOtherInterface",
				map[string]dbus.Variant{
					"Active": dbus.MakeVariant(true),
				},
			},
		}

		manager.handlePropertiesChanged(sig)

		manager.stateMutex.RLock()
		defer manager.stateMutex.RUnlock()
		assert.False(t, manager.state.Active)
	})

	t.Run("empty body", func(t *testing.T) {
		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			dirty:      make(chan struct{}, 1),
		}

		sig := &dbus.Signal{
			Name: "org.freedesktop.DBus.Properties.PropertiesChanged",
			Body: []any{},
		}

		assert.NotPanics(t, func() {
			manager.handlePropertiesChanged(sig)
		})
	})
}

func TestManager_LidClosedWhileKeepingAwake(t *testing.T) {
	lidClosed := &dbus.Signal{
		Name: "org.freedesktop.DBus.Properties.PropertiesChanged",
		Body: []any{
			"org.freedesktop.login1.Manager",
			map[string]dbus.Variant{"LidClosed": dbus.MakeVariant(true)},
			[]string{},
		},
	}

	newManager := func(t *testing.T, keepAwake, lockBeforeSuspend bool) *Manager {
		m := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			dirty:      make(chan struct{}, 1),
		}
		if keepAwake {
			f, err := os.CreateTemp(t.TempDir(), "inhibit")
			require.NoError(t, err)
			m.keepAwakeFile = f
		}
		m.lockBeforeSuspend.Store(lockBeforeSuspend)
		return m
	}

	expectDocked := func(managerObj *mockdbus.MockBusObject, docked bool) {
		managerObj.EXPECT().
			Call("org.freedesktop.DBus.Properties.Get", dbus.Flags(0), "org.freedesktop.login1.Manager", "Docked").
			Return(&dbus.Call{Body: []any{dbus.MakeVariant(docked)}})
	}

	t.Run("locks when undocked", func(t *testing.T) {
		managerObj := mockdbus.NewMockBusObject(t)
		sessionObj := mockdbus.NewMockBusObject(t)
		expectDocked(managerObj, false)
		sessionObj.EXPECT().Call("org.freedesktop.login1.Session.Lock", dbus.Flags(0)).Return(&dbus.Call{})

		m := newManager(t, true, true)
		m.managerObj = managerObj
		m.sessionObj = sessionObj
		m.handleDBusSignal(lidClosed)
	})

	t.Run("does not lock when docked", func(t *testing.T) {
		managerObj := mockdbus.NewMockBusObject(t)
		expectDocked(managerObj, true)

		m := newManager(t, true, true)
		m.managerObj = managerObj
		m.sessionObj = mockdbus.NewMockBusObject(t)
		m.handleDBusSignal(lidClosed)
	})

	t.Run("does not lock without keep awake", func(t *testing.T) {
		m := newManager(t, false, true)
		m.managerObj = mockdbus.NewMockBusObject(t)
		m.sessionObj = mockdbus.NewMockBusObject(t)
		m.handleDBusSignal(lidClosed)
	})

	t.Run("does not lock with lock before suspend off", func(t *testing.T) {
		m := newManager(t, true, false)
		m.managerObj = mockdbus.NewMockBusObject(t)
		m.sessionObj = mockdbus.NewMockBusObject(t)
		m.handleDBusSignal(lidClosed)
	})
}

func TestManager_SetKeepAwakeFalseReleasesInhibitor(t *testing.T) {
	f, err := os.CreateTemp(t.TempDir(), "inhibit")
	require.NoError(t, err)
	m := &Manager{keepAwakeFile: f}

	require.NoError(t, m.SetKeepAwake(false))

	assert.Nil(t, m.keepAwakeFile)
	assert.Error(t, f.Close())
}
