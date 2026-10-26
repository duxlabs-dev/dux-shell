package loginctl

import (
	"context"
	"time"

	"github.com/duxlabs-dev/dux-go/dbusutil"
	"github.com/godbus/dbus/v5"
)

func (m *Manager) handleDBusSignal(sig *dbus.Signal) {
	switch sig.Name {
	case dbusSessionInterface + ".Lock":
		m.stateMutex.Lock()
		m.state.Locked = true
		m.state.LockedHint = true
		m.stateMutex.Unlock()
		m.notifySubscribers()

		if m.sleepInhibitorEnabled.Load() && m.inSleepCycle.Load() {
			id := m.sleepCycleID.Load()
			m.lockTimerMu.Lock()
			if m.lockTimer != nil {
				m.lockTimer.Stop()
			}
			m.lockTimer = time.AfterFunc(m.fallbackDelay, func() {
				m.releaseForCycle(id)
			})
			m.lockTimerMu.Unlock()
		}

	case dbusSessionInterface + ".Unlock":
		if m.keepLockOnUnlock {
			// Only the locker clears LockedHint, so take both from logind, and
			// keep the cached state when logind cannot be read.
			if m.sessionObj != nil && m.updateSessionState() == nil && !m.snapshotState().Locked {
				m.prelockedReady.Store(false)
			}
			m.notifySubscribers()
		} else {
			lockedHint := m.sessionLockedHint()
			m.stateMutex.Lock()
			m.state.Locked = false
			m.state.LockedHint = lockedHint
			m.stateMutex.Unlock()
			m.notifySubscribers()
			m.prelockedReady.Store(false)
		}

		// Cancel the lock timer if it's still running
		m.lockTimerMu.Lock()
		if m.lockTimer != nil {
			m.lockTimer.Stop()
			m.lockTimer = nil
		}
		m.lockTimerMu.Unlock()

		// Re-acquire the sleep inhibitor (acquireSleepInhibitor checks the enabled flag)
		m.acquireSleepInhibitor()

	case dbusManagerInterface + ".PrepareForSleep":
		if len(sig.Body) == 0 {
			return
		}
		preparing, _ := sig.Body[0].(bool)

		if preparing {
			cycleID := m.sleepCycleID.Add(1)
			m.inSleepCycle.Store(true)

			m.stateMutex.RLock()
			alreadyLocked := m.state.Locked
			m.stateMutex.RUnlock()

			if m.lockBeforeSuspend.Load() && !alreadyLocked {
				m.Lock()
			}

			// Locked is logind's Lock hint, before the surface is up.
			// Only lockerReady may release early, and it stays set until unlock.
			if m.prelockedReady.Load() {
				m.releaseSleepInhibitor()
			} else {
				readyCh := m.newLockerReadyCh()
				go func(id uint64, ch <-chan struct{}) {
					<-ch
					if m.inSleepCycle.Load() && m.sleepCycleID.Load() == id {
						m.releaseSleepInhibitor()
					}
				}(cycleID, readyCh)
			}
		} else {
			m.inSleepCycle.Store(false)
			m.signalLockerReady()
			m.refreshSessionBinding()
			m.acquireSleepInhibitor()
		}

		m.stateMutex.Lock()
		m.state.PreparingForSleep = preparing
		m.stateMutex.Unlock()
		m.notifySubscribers()

	case dbusPropsInterface + ".PropertiesChanged":
		m.handlePropertiesChanged(sig)

	case "org.freedesktop.DBus.NameOwnerChanged":
		if len(sig.Body) == 3 {
			name, _ := sig.Body[0].(string)
			oldOwner, _ := sig.Body[1].(string)
			newOwner, _ := sig.Body[2].(string)
			if name == dbusDest && oldOwner != "" && newOwner != "" {
				m.updateSessionState()
				if !m.inSleepCycle.Load() {
					m.acquireSleepInhibitor()
				}
				m.notifySubscribers()
			}
		}
	}
}

// logind's Unlock does not clear LockedHint, the locker does. Report logind's
// value so a shell restarted while still locked can take the lock back.
func (m *Manager) sessionLockedHint() bool {
	if m.sessionObj == nil {
		return false
	}
	props, err := m.getSessionProperties(context.Background())
	if err != nil {
		return false
	}
	return dbusutil.GetOr(props, "LockedHint", false)
}

func (m *Manager) handlePropertiesChanged(sig *dbus.Signal) {
	if len(sig.Body) < 2 {
		return
	}

	iface, ok := sig.Body[0].(string)
	if !ok {
		return
	}

	changes, ok := sig.Body[1].(map[string]dbus.Variant)
	if !ok {
		return
	}

	if iface == dbusManagerInterface {
		m.handleManagerPropertiesChanged(changes)
		return
	}
	if iface != dbusSessionInterface {
		return
	}

	var needsUpdate bool

	for key, variant := range changes {
		switch key {
		case "Active":
			if val, ok := dbusutil.As[bool](variant); ok {
				m.stateMutex.Lock()
				m.state.Active = val
				m.stateMutex.Unlock()
				needsUpdate = true
			}
		case "IdleHint":
			if val, ok := dbusutil.As[bool](variant); ok {
				m.stateMutex.Lock()
				m.state.IdleHint = val
				m.stateMutex.Unlock()
				needsUpdate = true
			}
		case "IdleSinceHint":
			if val, ok := dbusutil.As[uint64](variant); ok {
				m.stateMutex.Lock()
				m.state.IdleSinceHint = val
				m.stateMutex.Unlock()
				needsUpdate = true
			}
		case "LockedHint":
			if val, ok := dbusutil.As[bool](variant); ok {
				m.stateMutex.Lock()
				m.state.LockedHint = val
				m.state.Locked = val
				m.stateMutex.Unlock()
				if !val {
					m.prelockedReady.Store(false)
				}
				needsUpdate = true
			}
		}
	}

	if needsUpdate {
		m.notifySubscribers()
	}
}

// Keep Awake blocks the suspend that would have locked the session, so lock
// on lid close instead, unless logind counts the machine as docked.
func (m *Manager) handleManagerPropertiesChanged(changes map[string]dbus.Variant) {
	variant, ok := changes["LidClosed"]
	if !ok {
		return
	}
	closed, ok := dbusutil.As[bool](variant)
	if !ok || !closed || !m.lockBeforeSuspend.Load() || !m.keepingAwake() || m.docked() {
		return
	}

	m.stateMutex.RLock()
	locked := m.state.Locked
	m.stateMutex.RUnlock()
	if !locked {
		m.Lock()
	}
}

func (m *Manager) docked() bool {
	var docked bool
	if err := m.managerObj.Call(dbusPropsInterface+".Get", 0, dbusManagerInterface, "Docked").Store(&docked); err != nil {
		return false
	}
	return docked
}
