package freedesktop

import (
	"context"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/dbusutil"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

func NewManager() (*Manager, error) {
	systemConn, err := dbus.SystemBus()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to system bus: %w", err)
	}

	sessionConn, err := dbus.SessionBus()
	if err != nil {
		sessionConn = nil
	}

	m := &Manager{
		state: &FreedeskState{
			Accounts:    AccountsState{},
			Settings:    SettingsState{},
			Screensaver: ScreensaverState{},
		},
		stateMutex:  sync.RWMutex{},
		systemConn:  systemConn,
		sessionConn: sessionConn,
		currentUID:  uint64(os.Getuid()),
	}

	m.initializeAccounts()
	m.initializeSettings()
	m.initializeScreensaver()

	return m, nil
}

func (m *Manager) initializeAccounts() error {
	accountsManager := m.systemConn.Object(dbusAccountsDest, dbus.ObjectPath(dbusAccountsPath))

	var userPath dbus.ObjectPath
	err := accountsManager.Call(dbusAccountsInterface+".FindUserById", 0, int64(m.currentUID)).Store(&userPath)
	if err != nil {
		m.stateMutex.Lock()
		m.state.Accounts.Available = false
		m.stateMutex.Unlock()
		return err
	}

	m.accountsObj = m.systemConn.Object(dbusAccountsDest, userPath)

	m.stateMutex.Lock()
	m.state.Accounts.Available = true
	m.state.Accounts.UserPath = string(userPath)
	m.state.Accounts.UID = m.currentUID
	m.stateMutex.Unlock()

	if err := m.updateAccountsState(); err != nil {
		return fmt.Errorf("failed to update accounts state: %w", err)
	}

	return nil
}

func (m *Manager) initializeSettings() error {
	if m.sessionConn == nil {
		m.stateMutex.Lock()
		m.state.Settings.Available = false
		m.stateMutex.Unlock()
		return fmt.Errorf("no session bus connection")
	}

	m.settingsObj = m.sessionConn.Object(dbusPortalDest, dbus.ObjectPath(dbusPortalPath))

	var variant dbus.Variant
	err := m.settingsObj.Call(dbusPortalSettingsInterface+".ReadOne", 0, "org.freedesktop.appearance", "color-scheme").Store(&variant)
	if err != nil {
		m.stateMutex.Lock()
		m.state.Settings.Available = false
		m.stateMutex.Unlock()
		return err
	}

	m.stateMutex.Lock()
	m.state.Settings.Available = true
	m.stateMutex.Unlock()

	if err := m.updateSettingsState(); err != nil {
		return fmt.Errorf("failed to update settings state: %w", err)
	}

	go m.watchSettingsChanges()

	return nil
}

// ExpectColorSchemeEcho registers a self-write so the watcher swallows its SettingChanged echo instead of forwarding it as an external change.
func (m *Manager) ExpectColorSchemeEcho(scheme string) {
	var value uint32
	switch scheme {
	case "prefer-dark":
		value = 1
	case "prefer-light":
		value = 2
	}
	m.selfEchoMu.Lock()
	m.selfEchoes = append(m.selfEchoes, colorSchemeEcho{value: value, expires: time.Now().Add(10 * time.Second)})
	m.selfEchoMu.Unlock()
}

func (m *Manager) consumeSelfEcho(value uint32) bool {
	m.selfEchoMu.Lock()
	defer m.selfEchoMu.Unlock()

	now := time.Now()
	kept := m.selfEchoes[:0]
	consumed := false
	for _, echo := range m.selfEchoes {
		if now.After(echo.expires) {
			continue
		}
		if !consumed && echo.value == value {
			consumed = true
			continue
		}
		kept = append(kept, echo)
	}
	m.selfEchoes = kept
	return consumed
}

func (m *Manager) watchSettingsChanges() {
	// reuse the shared session connection; a dedicated one was unreachable
	// from Close() and leaked with this goroutine
	if m.sessionConn == nil {
		return
	}
	conn := m.sessionConn

	if err := conn.AddMatchSignal(
		dbus.WithMatchInterface(dbusPortalSettingsInterface),
		dbus.WithMatchMember("SettingChanged"),
	); err != nil {
		log.Warnf("Failed to watch portal settings changes: %v", err)
		return
	}

	signals := make(chan *dbus.Signal, 64)
	m.stateMutex.Lock()
	m.settingsSignals = signals
	m.stateMutex.Unlock()
	conn.Signal(signals)

	for sig := range signals {
		if sig.Name != dbusPortalSettingsInterface+".SettingChanged" {
			continue
		}
		if len(sig.Body) < 3 {
			continue
		}

		namespace, _ := sig.Body[0].(string)
		key, _ := sig.Body[1].(string)
		if namespace != "org.freedesktop.appearance" || key != "color-scheme" {
			continue
		}

		variant, ok := sig.Body[2].(dbus.Variant)
		if !ok {
			continue
		}
		colorScheme, ok := dbusutil.As[uint32](variant)
		if !ok {
			continue
		}

		selfInflicted := m.consumeSelfEcho(colorScheme)

		m.stateMutex.Lock()
		changed := m.state.Settings.ColorScheme != colorScheme || !m.state.Settings.Available
		m.state.Settings.ColorScheme = colorScheme
		m.state.Settings.Available = true
		m.stateMutex.Unlock()

		if changed && !selfInflicted {
			m.NotifySubscribers()
		}
	}
}

func (m *Manager) updateAccountsState() error {
	if !m.state.Accounts.Available || m.accountsObj == nil {
		return fmt.Errorf("accounts service not available")
	}

	ctx := context.Background()
	props, err := m.getAccountProperties(ctx)
	if err != nil {
		return err
	}

	m.stateMutex.Lock()
	defer m.stateMutex.Unlock()

	m.state.Accounts.IconFile = dbusutil.GetOr(props, "IconFile", "")
	m.state.Accounts.RealName = dbusutil.GetOr(props, "RealName", "")
	m.state.Accounts.UserName = dbusutil.GetOr(props, "UserName", "")
	m.state.Accounts.AccountType = dbusutil.GetOr(props, "AccountType", int32(0))
	m.state.Accounts.HomeDirectory = dbusutil.GetOr(props, "HomeDirectory", "")
	m.state.Accounts.Shell = dbusutil.GetOr(props, "Shell", "")
	m.state.Accounts.Email = dbusutil.GetOr(props, "Email", "")
	m.state.Accounts.Language = dbusutil.GetOr(props, "Language", "")
	m.state.Accounts.Location = dbusutil.GetOr(props, "Location", "")
	m.state.Accounts.Locked = dbusutil.GetOr(props, "Locked", false)
	m.state.Accounts.PasswordMode = dbusutil.GetOr(props, "PasswordMode", int32(0))

	return nil
}

func (m *Manager) updateSettingsState() error {
	if !m.state.Settings.Available || m.settingsObj == nil {
		return fmt.Errorf("settings portal not available")
	}

	var variant dbus.Variant
	err := m.settingsObj.Call(dbusPortalSettingsInterface+".ReadOne", 0, "org.freedesktop.appearance", "color-scheme").Store(&variant)
	if err != nil {
		// Older xdg-desktop-portal versions only expose the deprecated Read.
		var nested dbus.Variant
		if rerr := m.settingsObj.Call(dbusPortalSettingsInterface+".Read", 0, "org.freedesktop.appearance", "color-scheme").Store(&nested); rerr != nil {
			log.Warnf("color-scheme: ReadOne (%v) and Read (%v) both failed", err, rerr)
			return err
		}
		variant = nested
	}

	colorScheme, ok := dbusutil.As[uint32](variant)
	if !ok {
		// Read double-wraps the value in a variant.
		if inner, innerOk := variant.Value().(dbus.Variant); innerOk {
			colorScheme, ok = dbusutil.As[uint32](inner)
		}
	}
	if ok {
		m.stateMutex.Lock()
		m.state.Settings.ColorScheme = colorScheme
		m.stateMutex.Unlock()
	}

	return nil
}

func (m *Manager) getAccountProperties(ctx context.Context) (map[string]dbus.Variant, error) {
	var props map[string]dbus.Variant
	err := m.accountsObj.CallWithContext(ctx, dbusPropsInterface+".GetAll", 0, dbusAccountsUserInterface).Store(&props)
	if err != nil {
		return nil, err
	}
	return props, nil
}

func (m *Manager) GetState() FreedeskState {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	return *m.state
}

func (m *Manager) Subscribe(id string) chan FreedeskState {
	ch := make(chan FreedeskState, 64)
	m.subscribers.Store(id, ch)
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)
	}
}

func (m *Manager) NotifySubscribers() {
	state := m.GetState()
	m.subscribers.Range(func(key string, ch chan FreedeskState) bool {
		select {
		case ch <- state:
		default:
		}
		return true
	})
}

func (m *Manager) Close() {
	m.subscribers.Range(func(key string, ch chan FreedeskState) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})

	m.screensaverSubscribers.Range(func(key string, ch chan ScreensaverState) bool {
		close(ch)
		m.screensaverSubscribers.Delete(key)
		return true
	})

	if m.sessionConn != nil {
		m.sessionConn.RemoveMatchSignal(
			dbus.WithMatchInterface(dbusPortalSettingsInterface),
			dbus.WithMatchMember("SettingChanged"),
		)
		m.stateMutex.Lock()
		signals := m.settingsSignals
		m.settingsSignals = nil
		m.stateMutex.Unlock()
		if signals != nil {
			m.sessionConn.RemoveSignal(signals)
			close(signals)
		}
	}
}
