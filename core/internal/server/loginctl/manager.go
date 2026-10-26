package loginctl

import (
	"context"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/dbusutil"
	"github.com/godbus/dbus/v5"
)

func NewManager(keepLockOnUnlock bool) (*Manager, error) {
	conn, err := dbus.SystemBus()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to system bus: %w", err)
	}

	m := &Manager{
		state:      &SessionState{},
		stateMutex: sync.RWMutex{},

		stopChan: make(chan struct{}),
		conn:     conn,
		dirty:    make(chan struct{}, 1),
		signals:  make(chan *dbus.Signal, 256),

		keepLockOnUnlock: keepLockOnUnlock,
	}
	m.sleepInhibitorEnabled.Store(true)

	if err := m.initialize(); err != nil {
		return nil, err
	}

	if err := m.acquireSleepInhibitor(); err != nil {
		fmt.Fprintf(os.Stderr, "sleep inhibitor unavailable: %v\n", err)
	}

	m.notifierWg.Add(1)
	go m.notifier()

	if err := m.startSignalPump(); err != nil {
		m.Close()
		return nil, err
	}

	return m, nil
}

func (m *Manager) initialize() error {
	m.managerObj = m.conn.Object(dbusDest, dbus.ObjectPath(dbusPath))

	m.initializeFallbackDelay()

	sessionID, sessionPath, err := m.discoverSession()
	if err != nil {
		return fmt.Errorf("failed to get session path: %w", err)
	}

	m.stateMutex.Lock()
	m.state.SessionID = sessionID
	m.state.SessionPath = string(sessionPath)
	m.sessionPath = sessionPath
	m.stateMutex.Unlock()

	m.sessionObj = m.conn.Object(dbusDest, sessionPath)

	if err := m.updateSessionState(); err != nil {
		return err
	}

	return nil
}

func (m *Manager) discoverSession() (string, dbus.ObjectPath, error) {
	// 1. Explicit XDG_SESSION_ID
	if id := os.Getenv("XDG_SESSION_ID"); id != "" {
		if path, err := m.getSession(id); err == nil {
			fmt.Fprintf(os.Stderr, "loginctl: using XDG_SESSION_ID=%s\n", id)
			return id, path, nil
		}
	}

	// 2. PID-based lookup (works when caller is inside a session cgroup)
	if id, path, err := m.getSessionByPID(uint32(os.Getpid())); err == nil {
		fmt.Fprintf(os.Stderr, "loginctl: found session %s via PID\n", id)
		return id, path, nil
	}

	// 3. User's primary display session (handles UWSM and similar)
	if id, path, err := m.getUserDisplaySession(); err == nil {
		fmt.Fprintf(os.Stderr, "loginctl: found session %s via User.Display\n", id)
		return id, path, nil
	}

	// 4. Score all sessions for current UID
	if id, path, err := m.findBestSession(); err == nil {
		fmt.Fprintf(os.Stderr, "loginctl: found session %s via ListSessions scoring\n", id)
		return id, path, nil
	}

	// 5. Last resort: "self"
	path, err := m.getSession("self")
	if err != nil {
		return "", "", fmt.Errorf("%w", err)
	}
	return "self", path, nil
}

func (m *Manager) getSession(id string) (dbus.ObjectPath, error) {
	var out dbus.ObjectPath
	err := m.managerObj.Call(dbusManagerInterface+".GetSession", 0, id).Store(&out)
	if err != nil {
		return "", err
	}
	return out, nil
}

func (m *Manager) getSessionByPID(pid uint32) (string, dbus.ObjectPath, error) {
	var path dbus.ObjectPath
	if err := m.managerObj.Call(dbusManagerInterface+".GetSessionByPID", 0, pid).Store(&path); err != nil {
		return "", "", err
	}

	sessionObj := m.conn.Object(dbusDest, path)
	var id dbus.Variant
	if err := sessionObj.Call(dbusPropsInterface+".Get", 0, dbusSessionInterface, "Id").Store(&id); err != nil {
		return "", "", err
	}
	return id.Value().(string), path, nil
}

func (m *Manager) getUserDisplaySession() (string, dbus.ObjectPath, error) {
	uid := uint32(os.Getuid())

	var userPath dbus.ObjectPath
	if err := m.managerObj.Call(dbusManagerInterface+".GetUser", 0, uid).Store(&userPath); err != nil {
		return "", "", err
	}

	userObj := m.conn.Object(dbusDest, userPath)
	var display dbus.Variant
	if err := userObj.Call(dbusPropsInterface+".Get", 0, dbusUserInterface, "Display").Store(&display); err != nil {
		return "", "", err
	}

	pair, ok := display.Value().([]any)
	if !ok || len(pair) < 2 {
		return "", "", fmt.Errorf("unexpected Display format")
	}

	sessionID, _ := pair[0].(string)
	sessionPath, _ := pair[1].(dbus.ObjectPath)
	if sessionID == "" || sessionPath == "" {
		return "", "", fmt.Errorf("empty Display session")
	}

	return sessionID, sessionPath, nil
}

type sessionCandidate struct {
	id   string
	path dbus.ObjectPath
}

func (m *Manager) findBestSession() (string, dbus.ObjectPath, error) {
	// ListSessions returns a(susso): [][]any where each entry is [id, uid, name, seat, path]
	var raw [][]any
	if err := m.managerObj.Call(dbusManagerInterface+".ListSessions", 0).Store(&raw); err != nil {
		return "", "", err
	}

	uid := uint32(os.Getuid())
	var candidates []sessionCandidate
	for _, entry := range raw {
		if len(entry) < 5 {
			continue
		}
		entryUID, _ := entry[1].(uint32)
		if entryUID != uid {
			continue
		}
		id, _ := entry[0].(string)
		path, _ := entry[4].(dbus.ObjectPath)
		if id != "" && path != "" {
			candidates = append(candidates, sessionCandidate{id: id, path: path})
		}
	}
	if len(candidates) == 0 {
		return "", "", fmt.Errorf("no sessions for uid %d", uid)
	}

	bestScore := -1
	var best sessionCandidate
	for _, c := range candidates {
		score := m.scoreSession(c.path)
		if score > bestScore {
			bestScore = score
			best = c
		}
	}
	if bestScore < 0 {
		return "", "", fmt.Errorf("no viable session found")
	}
	return best.id, best.path, nil
}

func (m *Manager) scoreSession(path dbus.ObjectPath) int {
	obj := m.conn.Object(dbusDest, path)
	var props map[string]dbus.Variant
	if err := obj.Call(dbusPropsInterface+".GetAll", 0, dbusSessionInterface).Store(&props); err != nil {
		return -1
	}

	getStr := func(key string) string {
		if v, ok := props[key]; ok {
			if s, ok := v.Value().(string); ok {
				return s
			}
		}
		return ""
	}
	getBool := func(key string) bool {
		if v, ok := props[key]; ok {
			if b, ok := v.Value().(bool); ok {
				return b
			}
		}
		return false
	}
	getUint32 := func(key string) uint32 {
		if v, ok := props[key]; ok {
			if u, ok := v.Value().(uint32); ok {
				return u
			}
		}
		return 0
	}

	class := getStr("Class")
	if class != "user" {
		return -1
	}
	if getBool("Remote") {
		return -1
	}

	score := 0

	if getBool("Active") {
		score += 100
	}

	switch getStr("Type") {
	case "wayland", "x11":
		score += 80
	case "tty":
		score += 10
	}

	if v, ok := props["Seat"]; ok {
		if seatArr, ok := v.Value().([]any); ok && len(seatArr) >= 1 {
			if seat, ok := seatArr[0].(string); ok && seat != "" {
				score += 40
				if seat == "seat0" {
					score += 10
				}
			}
		}
	}

	if getUint32("VTNr") > 0 {
		score += 20
	}

	return score
}

func (m *Manager) refreshSessionBinding() error {
	if m.managerObj == nil || m.conn == nil {
		return fmt.Errorf("manager not fully initialized")
	}

	sessionPath, err := m.getSession(m.state.SessionID)
	if err != nil {
		return fmt.Errorf("failed to get session path: %w", err)
	}

	m.stateMutex.RLock()
	currentPath := m.sessionPath
	m.stateMutex.RUnlock()

	if sessionPath == currentPath {
		return nil
	}

	m.stopSignalPump()

	m.stateMutex.Lock()
	m.state.SessionPath = string(sessionPath)
	m.sessionPath = sessionPath
	m.stateMutex.Unlock()

	m.sessionObj = m.conn.Object(dbusDest, sessionPath)

	if err := m.updateSessionState(); err != nil {
		return err
	}

	m.signals = make(chan *dbus.Signal, 256)
	return m.startSignalPump()
}

func (m *Manager) updateSessionState() error {
	ctx := context.Background()
	props, err := m.getSessionProperties(ctx)
	if err != nil {
		return err
	}

	m.stateMutex.Lock()
	defer m.stateMutex.Unlock()

	m.state.Active = dbusutil.GetOr(props, "Active", m.state.Active)
	m.state.IdleHint = dbusutil.GetOr(props, "IdleHint", m.state.IdleHint)
	m.state.IdleSinceHint = dbusutil.GetOr(props, "IdleSinceHint", m.state.IdleSinceHint)
	if lockedHint, ok := dbusutil.Get[bool](props, "LockedHint"); ok {
		m.state.LockedHint = lockedHint
		m.state.Locked = lockedHint
	}
	m.state.SessionType = dbusutil.GetOr(props, "Type", m.state.SessionType)
	m.state.SessionClass = dbusutil.GetOr(props, "Class", m.state.SessionClass)
	if v, ok := props["User"]; ok {
		if userArr, ok := v.Value().([]any); ok && len(userArr) >= 1 {
			if uid, ok := userArr[0].(uint32); ok {
				m.state.User = uid
			}
		}
	}
	m.state.UserName = dbusutil.GetOr(props, "Name", m.state.UserName)
	m.state.RemoteHost = dbusutil.GetOr(props, "RemoteHost", m.state.RemoteHost)
	m.state.Service = dbusutil.GetOr(props, "Service", m.state.Service)
	m.state.TTY = dbusutil.GetOr(props, "TTY", m.state.TTY)
	m.state.Display = dbusutil.GetOr(props, "Display", m.state.Display)
	m.state.Remote = dbusutil.GetOr(props, "Remote", m.state.Remote)
	if v, ok := props["Seat"]; ok {
		if seatArr, ok := v.Value().([]any); ok && len(seatArr) >= 1 {
			if seatID, ok := seatArr[0].(string); ok {
				m.state.Seat = seatID
			}
		}
	}
	m.state.VTNr = dbusutil.GetOr(props, "VTNr", m.state.VTNr)

	return nil
}

func (m *Manager) getSessionProperties(ctx context.Context) (map[string]dbus.Variant, error) {
	var props map[string]dbus.Variant
	err := m.sessionObj.CallWithContext(ctx, dbusPropsInterface+".GetAll", 0, dbusSessionInterface).Store(&props)
	if err != nil {
		return nil, err
	}
	return props, nil
}

func (m *Manager) acquireSleepInhibitor() error {
	if !m.sleepInhibitorEnabled.Load() {
		return nil
	}

	m.inhibitMu.Lock()
	defer m.inhibitMu.Unlock()

	if m.inhibitFile != nil {
		return nil
	}

	if m.managerObj == nil {
		return fmt.Errorf("manager object not available")
	}

	file, err := m.inhibit("sleep", "Dux Shell", "Lock before suspend", "delay")
	if err != nil {
		return err
	}

	m.inhibitFile = file
	return nil
}

func (m *Manager) inhibit(what, who, why, mode string) (*os.File, error) {
	var fd dbus.UnixFD
	err := m.managerObj.Call(dbusManagerInterface+".Inhibit", 0, what, who, why, mode).Store(&fd)
	if err != nil {
		return nil, err
	}
	return os.NewFile(uintptr(fd), "inhibit"), nil
}

func (m *Manager) releaseSleepInhibitor() {
	m.inhibitMu.Lock()
	f := m.inhibitFile
	m.inhibitFile = nil
	m.inhibitMu.Unlock()
	if f != nil {
		f.Close()
	}
}

func (m *Manager) releaseForCycle(id uint64) {
	if !m.inSleepCycle.Load() || m.sleepCycleID.Load() != id {
		return
	}
	m.releaseSleepInhibitor()
}

func (m *Manager) initializeFallbackDelay() {
	var maxDelayUSec uint64
	err := m.managerObj.Call(
		dbusPropsInterface+".Get",
		0,
		dbusManagerInterface,
		"InhibitDelayMaxUSec",
	).Store(&maxDelayUSec)

	if err != nil {
		m.fallbackDelay = 2 * time.Second
		return
	}

	maxDelay := time.Duration(maxDelayUSec) * time.Microsecond
	computed := (maxDelay * 8) / 10

	if computed < 2*time.Second {
		m.fallbackDelay = 2 * time.Second
	} else if computed > 4*time.Second {
		m.fallbackDelay = 4 * time.Second
	} else {
		m.fallbackDelay = computed
	}
}

func (m *Manager) newLockerReadyCh() chan struct{} {
	m.lockerReadyChMu.Lock()
	defer m.lockerReadyChMu.Unlock()
	m.lockerReadyCh = make(chan struct{})
	return m.lockerReadyCh
}

func (m *Manager) signalLockerReady() {
	m.lockerReadyChMu.Lock()
	ch := m.lockerReadyCh
	if ch != nil {
		close(ch)
		m.lockerReadyCh = nil
	}
	m.lockerReadyChMu.Unlock()
}

func (m *Manager) snapshotState() SessionState {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	return *m.state
}

func stateChangedMeaningfully(old, new *SessionState) bool {
	if old.Locked != new.Locked {
		return true
	}
	if old.LockedHint != new.LockedHint {
		return true
	}
	if old.Active != new.Active {
		return true
	}
	if old.IdleHint != new.IdleHint {
		return true
	}
	if old.PreparingForSleep != new.PreparingForSleep {
		return true
	}
	return false
}

func (m *Manager) GetState() SessionState {
	return m.snapshotState()
}

func (m *Manager) Subscribe(id string) chan SessionState {
	ch := make(chan SessionState, 64)
	m.subscribers.Store(id, ch)
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)
	}
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

			currentState := m.snapshotState()

			if m.lastNotifiedState != nil && !stateChangedMeaningfully(m.lastNotifiedState, &currentState) {
				pending = false
				continue
			}

			m.subscribers.Range(func(key string, ch chan SessionState) bool {
				select {
				case ch <- currentState:
				default:
				}
				return true
			})

			stateCopy := currentState
			m.lastNotifiedState = &stateCopy
			pending = false
		}
	}
}

func (m *Manager) notifySubscribers() {
	select {
	case m.dirty <- struct{}{}:
	default:
	}
}

func (m *Manager) startSignalPump() error {
	m.conn.Signal(m.signals)

	if err := m.conn.AddMatchSignal(
		dbus.WithMatchObjectPath(m.sessionPath),
		dbus.WithMatchInterface(dbusPropsInterface),
		dbus.WithMatchMember("PropertiesChanged"),
	); err != nil {
		m.conn.RemoveSignal(m.signals)
		return err
	}
	if err := m.conn.AddMatchSignal(
		dbus.WithMatchObjectPath(m.sessionPath),
		dbus.WithMatchInterface(dbusSessionInterface),
		dbus.WithMatchMember("Lock"),
	); err != nil {
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
		m.conn.RemoveSignal(m.signals)
		return err
	}
	if err := m.conn.AddMatchSignal(
		dbus.WithMatchObjectPath(m.sessionPath),
		dbus.WithMatchInterface(dbusSessionInterface),
		dbus.WithMatchMember("Unlock"),
	); err != nil {
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusSessionInterface),
			dbus.WithMatchMember("Lock"),
		)
		m.conn.RemoveSignal(m.signals)
		return err
	}
	if err := m.conn.AddMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusPath)),
		dbus.WithMatchInterface(dbusManagerInterface),
		dbus.WithMatchMember("PrepareForSleep"),
	); err != nil {
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusSessionInterface),
			dbus.WithMatchMember("Lock"),
		)
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusSessionInterface),
			dbus.WithMatchMember("Unlock"),
		)
		m.conn.RemoveSignal(m.signals)
		return err
	}

	if err := m.conn.AddMatchSignal(
		dbus.WithMatchObjectPath("/org/freedesktop/DBus"),
		dbus.WithMatchInterface("org.freedesktop.DBus"),
		dbus.WithMatchMember("NameOwnerChanged"),
	); err != nil {
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusSessionInterface),
			dbus.WithMatchMember("Lock"),
		)
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusSessionInterface),
			dbus.WithMatchMember("Unlock"),
		)
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(dbusPath)),
			dbus.WithMatchInterface(dbusManagerInterface),
			dbus.WithMatchMember("PrepareForSleep"),
		)
		m.conn.RemoveSignal(m.signals)
		return err
	}

	if err := m.conn.AddMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusPath)),
		dbus.WithMatchInterface(dbusPropsInterface),
		dbus.WithMatchMember("PropertiesChanged"),
	); err != nil {
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusPropsInterface),
			dbus.WithMatchMember("PropertiesChanged"),
		)
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusSessionInterface),
			dbus.WithMatchMember("Lock"),
		)
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(m.sessionPath),
			dbus.WithMatchInterface(dbusSessionInterface),
			dbus.WithMatchMember("Unlock"),
		)
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath(dbus.ObjectPath(dbusPath)),
			dbus.WithMatchInterface(dbusManagerInterface),
			dbus.WithMatchMember("PrepareForSleep"),
		)
		m.conn.RemoveMatchSignal(
			dbus.WithMatchObjectPath("/org/freedesktop/DBus"),
			dbus.WithMatchInterface("org.freedesktop.DBus"),
			dbus.WithMatchMember("NameOwnerChanged"),
		)
		m.conn.RemoveSignal(m.signals)
		return err
	}

	m.sigWG.Go(func() {
		for {
			select {
			case <-m.stopChan:
				return
			case sig, ok := <-m.signals:
				if !ok {
					return
				}
				if sig == nil {
					continue
				}
				m.handleDBusSignal(sig)
			}
		}
	})
	return nil
}

func (m *Manager) stopSignalPump() {
	if m.conn == nil {
		return
	}
	m.conn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(m.sessionPath),
		dbus.WithMatchInterface(dbusPropsInterface),
		dbus.WithMatchMember("PropertiesChanged"),
	)
	m.conn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(m.sessionPath),
		dbus.WithMatchInterface(dbusSessionInterface),
		dbus.WithMatchMember("Lock"),
	)
	m.conn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(m.sessionPath),
		dbus.WithMatchInterface(dbusSessionInterface),
		dbus.WithMatchMember("Unlock"),
	)
	m.conn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusPath)),
		dbus.WithMatchInterface(dbusManagerInterface),
		dbus.WithMatchMember("PrepareForSleep"),
	)
	m.conn.RemoveMatchSignal(
		dbus.WithMatchObjectPath("/org/freedesktop/DBus"),
		dbus.WithMatchInterface("org.freedesktop.DBus"),
		dbus.WithMatchMember("NameOwnerChanged"),
	)
	m.conn.RemoveMatchSignal(
		dbus.WithMatchObjectPath(dbus.ObjectPath(dbusPath)),
		dbus.WithMatchInterface(dbusPropsInterface),
		dbus.WithMatchMember("PropertiesChanged"),
	)

	m.conn.RemoveSignal(m.signals)
	close(m.signals)

	m.sigWG.Wait()
}

func (m *Manager) Close() {
	close(m.stopChan)
	m.notifierWg.Wait()

	m.stopSignalPump()

	m.releaseSleepInhibitor()
	m.releaseKeepAwake()

	m.subscribers.Range(func(key string, ch chan SessionState) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})
}
