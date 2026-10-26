package loginctl

import (
	"fmt"
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

func (m *Manager) SetLockBeforeSuspend(enabled bool) {
	m.lockBeforeSuspend.Store(enabled)
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

func (m *Manager) SetKeepAwake(enabled bool) error {
	if !enabled {
		m.releaseKeepAwake()
		return nil
	}

	m.keepAwakeMu.Lock()
	defer m.keepAwakeMu.Unlock()

	if m.keepAwakeFile != nil {
		return nil
	}
	if m.managerObj == nil {
		return fmt.Errorf("manager object not available")
	}

	file, err := m.inhibit("sleep:handle-lid-switch", "Dux Shell", "Keep Awake", "block")
	if err != nil {
		return fmt.Errorf("failed to inhibit sleep: %w", err)
	}
	m.keepAwakeFile = file
	return nil
}

func (m *Manager) releaseKeepAwake() {
	m.keepAwakeMu.Lock()
	f := m.keepAwakeFile
	m.keepAwakeFile = nil
	m.keepAwakeMu.Unlock()
	if f != nil {
		f.Close()
	}
}

func (m *Manager) keepingAwake() bool {
	m.keepAwakeMu.Lock()
	defer m.keepAwakeMu.Unlock()
	return m.keepAwakeFile != nil
}

func (m *Manager) SetSleepInhibitorEnabled(enabled bool) {
	m.sleepInhibitorEnabled.Store(enabled)
	if enabled {
		// Re-acquire inhibitor if enabled
		m.acquireSleepInhibitor()
	} else {
		// Release inhibitor if disabled
		m.releaseSleepInhibitor()
	}
}
