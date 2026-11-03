package loginctl

import (
	"errors"
	"fmt"
)

var (
	errLockBeforeSuspendManaged = errors.New("lock before suspend is managed by administrator policy")
	errSleepInhibitorManaged    = errors.New("the sleep inhibitor is managed by administrator policy")
)

func (m *Manager) Lock() error {
	if m.sessionObj == nil {
		return fmt.Errorf("session object not available")
	}
	err := m.sessionObj.Call(dbusSessionInterface+".Lock", 0).Err
	if err != nil {
		if refreshErr := m.refreshSessionBinding(); refreshErr == nil {
			err = m.sessionObj.Call(dbusSessionInterface+".Lock", 0).Err
		}
		if err != nil {
			return fmt.Errorf("failed to lock session: %w", err)
		}
	}
	return nil
}

func (m *Manager) Unlock() error {
	err := m.sessionObj.Call(dbusSessionInterface+".Unlock", 0).Err
	if err != nil {
		if refreshErr := m.refreshSessionBinding(); refreshErr == nil {
			err = m.sessionObj.Call(dbusSessionInterface+".Unlock", 0).Err
		}
		if err != nil {
			return fmt.Errorf("failed to unlock session: %w", err)
		}
	}
	return nil
}

func (m *Manager) Activate() error {
	err := m.sessionObj.Call(dbusSessionInterface+".Activate", 0).Err
	if err != nil {
		if refreshErr := m.refreshSessionBinding(); refreshErr == nil {
			err = m.sessionObj.Call(dbusSessionInterface+".Activate", 0).Err
		}
		if err != nil {
			return fmt.Errorf("failed to activate session: %w", err)
		}
	}
	return nil
}

func (m *Manager) SetLockedHint(locked bool) error {
	err := m.sessionObj.Call(dbusSessionInterface+".SetLockedHint", 0, locked).Err
	if err != nil {
		if refreshErr := m.refreshSessionBinding(); refreshErr == nil {
			err = m.sessionObj.Call(dbusSessionInterface+".SetLockedHint", 0, locked).Err
		}
		if err != nil {
			return fmt.Errorf("failed to set locked hint: %w", err)
		}
	}
	return nil
}

func (m *Manager) SetIdleHint(idle bool) error {
	err := m.sessionObj.Call(dbusSessionInterface+".SetIdleHint", 0, idle).Err
	if err != nil {
		if refreshErr := m.refreshSessionBinding(); refreshErr == nil {
			err = m.sessionObj.Call(dbusSessionInterface+".SetIdleHint", 0, idle).Err
		}
		if err != nil {
			return fmt.Errorf("failed to set idle hint: %w", err)
		}
	}
	return nil
}

func (m *Manager) Terminate() error {
	err := m.sessionObj.Call(dbusSessionInterface+".Terminate", 0).Err
	if err != nil {
		if refreshErr := m.refreshSessionBinding(); refreshErr == nil {
			err = m.sessionObj.Call(dbusSessionInterface+".Terminate", 0).Err
		}
		if err != nil {
			return fmt.Errorf("failed to terminate session: %w", err)
		}
	}
	return nil
}

// applyLockPolicy starts from the managed settings, before the shell connects.
func (m *Manager) applyLockPolicy() {
	if managed := m.lockPolicy.LockBeforeSuspend; managed != nil {
		m.lockBeforeSuspend.Store(*managed)
	}
	enabled, managed := m.lockPolicy.sleepInhibitor()
	m.sleepInhibitorEnabled.Store(enabled || !managed)
}

func (m *Manager) SetLockBeforeSuspend(enabled bool) error {
	if managed := m.lockPolicy.LockBeforeSuspend; managed != nil && *managed != enabled {
		return errLockBeforeSuspendManaged
	}
	m.lockBeforeSuspend.Store(enabled)
	return nil
}

func (m *Manager) markLockerReady() {
	m.lockTimerMu.Lock()
	if m.lockTimer != nil {
		m.lockTimer.Stop()
		m.lockTimer = nil
	}
	m.lockTimerMu.Unlock()

	id := m.sleepCycleID.Load()
	m.releaseForCycle(id)

	if m.inSleepCycle.Load() {
		m.signalLockerReady()
		return
	}
	m.prelockedReady.Store(true)
}

func (m *Manager) SetSleepInhibitorEnabled(enabled bool) error {
	if managedValue, managed := m.lockPolicy.sleepInhibitor(); managed && managedValue != enabled {
		return errSleepInhibitorManaged
	}
	m.sleepInhibitorEnabled.Store(enabled)
	if enabled {
		// Re-acquire inhibitor if enabled
		m.acquireSleepInhibitor()
	} else {
		// Release inhibitor if disabled
		m.releaseSleepInhibitor()
	}
	return nil
}
