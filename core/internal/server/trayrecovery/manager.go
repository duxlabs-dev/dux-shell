package trayrecovery

import (
	"fmt"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/loginctl"
	"github.com/godbus/dbus/v5"
)

const (
	resumeDelay    = 3 * time.Second
	firstBootDelay = 15 * time.Second
)

type Manager struct {
	conn     *dbus.Conn
	stopChan chan struct{}
	wg       sync.WaitGroup
}

func NewManager() (*Manager, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to session bus: %w", err)
	}

	m := &Manager{
		conn:     conn,
		stopChan: make(chan struct{}),
	}

	// Only run a startup scan when the system has been suspended at least once.
	// On a fresh boot CLOCK_BOOTTIME ≈ CLOCK_MONOTONIC (difference ~0).
	// After any suspend/resume cycle the difference grows by the time spent
	// sleeping.  This avoids duplicate registrations on normal boot where apps
	// are still starting up and will register their own tray icons shortly.
	if timeSuspended() > 5*time.Second {
		go m.scheduleRecovery(resumeDelay)
	}

	return m, nil
}

// WatchLoginctl subscribes to loginctl session state changes and triggers
// tray recovery after resume from suspend (PrepareForSleep false transition).
// This handles the case where the process survives suspend.
func (m *Manager) WatchLoginctl(lm *loginctl.Manager) {
	ch := lm.Subscribe("tray-recovery")
	m.wg.Go(func() {
		defer lm.Unsubscribe("tray-recovery")

		wasSleeping := false
		for {
			select {
			case <-m.stopChan:
				return
			case state, ok := <-ch:
				if !ok {
					return
				}
				if state.PreparingForSleep {
					wasSleeping = true
					continue
				}
				if wasSleeping {
					wasSleeping = false
					go m.scheduleRecovery(resumeDelay)
				}
			}
		}
	})
}

// A restarted shell brings up an empty watcher, and clients that ignore
// NameOwnerChanged never re-register (#1142).
func (m *Manager) WatchWatcherOwner() {
	if err := m.conn.AddMatchSignal(
		dbus.WithMatchInterface(dbusIface),
		dbus.WithMatchMember("NameOwnerChanged"),
		dbus.WithMatchArg(0, sniWatcherDest),
	); err != nil {
		log.Warnf("TrayRecoveryService: NameOwnerChanged match failed: %v", err)
		return
	}

	ch := make(chan *dbus.Signal, 16)
	m.conn.Signal(ch)

	m.wg.Go(func() {
		defer m.conn.RemoveSignal(ch)
		hadOwner := m.getNameOwner(sniWatcherDest) != ""
		for {
			select {
			case <-m.stopChan:
				return
			case sig, ok := <-ch:
				if !ok {
					return
				}
				if sig.Name != dbusIface+".NameOwnerChanged" || len(sig.Body) < 3 {
					continue
				}
				name, _ := sig.Body[0].(string)
				newOwner, _ := sig.Body[2].(string)
				if name != sniWatcherDest || newOwner == "" {
					continue
				}
				if !hadOwner {
					hadOwner = true
					// First boot: autostart apps (e.g. KeePassXC) may have tried
					// to register their SNI item before the watcher existed and
					// never retry. A one-time delayed scan picks those up.
					log.Info("TrayRecoveryService: StatusNotifierWatcher appeared for the first time, scheduling boot scan")
					go m.scheduleRecovery(firstBootDelay)
					continue
				}
				log.Info("TrayRecoveryService: StatusNotifierWatcher changed hands, scheduling rescan")
				go m.scheduleRecovery(resumeDelay)
			}
		}
	})
}

func (m *Manager) scheduleRecovery(delay time.Duration) {
	select {
	case <-time.After(delay):
		m.recoverTrayItems()
	case <-m.stopChan:
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
	log.Info("TrayRecovery manager closed")
}
