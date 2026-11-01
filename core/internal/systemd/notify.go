package systemd

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

var ErrReadinessTimeout = errors.New("shell readiness timed out")

type BusNameConflictError struct {
	Name     string
	OwnerPID uint32
}

func (e *BusNameConflictError) Error() string {
	return fmt.Sprintf("%s is already owned by another process (PID %d)", e.Name, e.OwnerPID)
}

type Readiness struct {
	uiReady chan uint32
	once    sync.Once
}

func NewReadiness() *Readiness {
	return &Readiness{uiReady: make(chan uint32, 1)}
}

func (r *Readiness) ShellReady(pid uint32) {
	r.once.Do(func() { r.uiReady <- pid })
}

func (r *Readiness) Wait(ctx context.Context) {
	path := os.Getenv("NOTIFY_SOCKET")
	if path == "" {
		return
	}
	if path[0] != '/' && path[0] != '@' {
		log.Warn("Could not report shell readiness: invalid NOTIFY_SOCKET address")
		return
	}

	started := time.Now()
	timeout, err := startupTimeout(ctx)
	if err != nil {
		if ctx.Err() != nil {
			return
		}
		log.Warnf("Could not read systemd startup timeout; using one minute: %v", err)
		timeout = max(0, time.Minute-time.Since(started))
	}

	var conn *dbus.Conn
	defer func() {
		if conn != nil {
			conn.Close()
		}
	}()
	err = r.wait(ctx, timeout, func(ctx context.Context, pid uint32) (bool, error) {
		if conn != nil && !conn.Connected() {
			conn.Close()
			conn = nil
		}
		if conn == nil {
			var err error
			conn, err = dbus.ConnectSessionBus(dbus.WithContext(ctx))
			if err != nil {
				return false, fmt.Errorf("connect to session bus: %w", err)
			}
		}
		checkCtx, cancel := context.WithTimeout(ctx, time.Second)
		defer cancel()
		ready, status, err := shellServicesReady(checkCtx, conn, pid)
		if err != nil {
			return false, err
		}
		if !ready {
			return false, errors.New(status)
		}
		if err := ctx.Err(); err != nil {
			return false, err
		}
		message := "READY=1"
		if status != "" {
			message += "\nSTATUS=" + status
		}
		if err := sendNotification(path, message); err != nil {
			return false, err
		}
		if status != "" {
			log.Warn(status)
		}
		return true, nil
	})
	if err == nil || ctx.Err() != nil {
		return
	}
	status := "Shell started with a readiness warning: " + err.Error()
	if notifyErr := sendNotification(path, "READY=1\nSTATUS="+status); notifyErr != nil {
		log.Warnf("Could not report shell readiness: %v; %v", err, notifyErr)
		return
	}
	log.Warn(status)
}

func (r *Readiness) wait(parent context.Context, timeout time.Duration, check func(context.Context, uint32) (bool, error)) error {
	var ctx context.Context
	var cancel context.CancelFunc
	if timeout < 0 {
		ctx, cancel = context.WithCancel(parent)
	} else {
		ctx, cancel = context.WithTimeout(parent, timeout)
	}
	defer cancel()

	var pid uint32
	select {
	case pid = <-r.uiReady:
	case <-ctx.Done():
		if parent.Err() != nil {
			return nil
		}
		return fmt.Errorf("%w: UI did not report readiness", ErrReadinessTimeout)
	}

	delay := 20 * time.Millisecond
	timer := time.NewTimer(delay)
	defer timer.Stop()
	var lastError error
	for {
		select {
		case <-ctx.Done():
			if parent.Err() != nil {
				return nil
			}
			if lastError != nil {
				return fmt.Errorf("%w: %v", ErrReadinessTimeout, lastError)
			}
			return ErrReadinessTimeout
		case <-timer.C:
			if ctx.Err() != nil {
				continue
			}
			ready, err := check(ctx, pid)
			if ctx.Err() != nil {
				continue
			}
			if err == nil && ready {
				return nil
			}
			lastError = err
			timer.Reset(delay)
			delay = min(delay*2, 5*time.Second)
		}
	}
}

func sendNotification(path, message string) error {
	conn, err := net.DialTimeout("unixgram", path, time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()

	if err := conn.SetWriteDeadline(time.Now().Add(time.Second)); err != nil {
		return err
	}
	_, err = conn.Write([]byte(message))
	return err
}

func shellServicesReady(ctx context.Context, conn *dbus.Conn, shellPID uint32) (bool, string, error) {
	status := ""
	ready, err := busNameReady(ctx, conn, "org.freedesktop.Notifications", shellPID)
	var conflict *BusNameConflictError
	switch {
	case errors.As(err, &conflict):
		status = fmt.Sprintf("Ready; notifications handled by external process (PID %d)", conflict.OwnerPID)
	case err != nil:
		return false, "", err
	case !ready:
		return false, "notification service has no D-Bus owner", nil
	}
	ready, err = busNameReady(ctx, conn, "org.kde.StatusNotifierWatcher", 0)
	if err != nil {
		return false, "", err
	}
	if !ready {
		return false, "tray watcher has no D-Bus owner", nil
	}

	var names []string
	if err := conn.BusObject().CallWithContext(ctx, "org.freedesktop.DBus.ListNames", 0).Store(&names); err != nil {
		return false, "", fmt.Errorf("list tray hosts: %w", err)
	}
	hostPrefix := fmt.Sprintf("org.kde.StatusNotifierHost-%d-", shellPID)
	for _, name := range names {
		if !strings.HasPrefix(name, hostPrefix) {
			continue
		}
		ready, err := busNameReady(ctx, conn, name, shellPID)
		if err != nil {
			return false, "", err
		}
		if !ready {
			continue
		}

		var registered dbus.Variant
		err = conn.Object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher").CallWithContext(ctx,
			"org.freedesktop.DBus.Properties.Get", dbus.FlagNoAutoStart,
			"org.kde.StatusNotifierWatcher", "IsStatusNotifierHostRegistered").Store(&registered)
		if busNameMissing(err) {
			return false, "tray watcher disappeared during startup", nil
		}
		if err != nil {
			return false, "", fmt.Errorf("get tray watcher readiness: %w", err)
		}
		ready, _ = registered.Value().(bool)
		if !ready {
			return false, "tray watcher did not report a registered host", nil
		}
		return true, status, nil
	}
	return false, "shell tray host is not registered on D-Bus", nil
}

func busNameReady(ctx context.Context, conn *dbus.Conn, name string, expectedPID uint32) (bool, error) {
	var ownerPID uint32
	err := conn.BusObject().CallWithContext(ctx, "org.freedesktop.DBus.GetConnectionUnixProcessID", 0, name).Store(&ownerPID)
	if busNameMissing(err) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("get owner of %s: %w", name, err)
	}
	if expectedPID != 0 && ownerPID != expectedPID {
		return false, &BusNameConflictError{Name: name, OwnerPID: ownerPID}
	}
	return true, nil
}

func busNameMissing(err error) bool {
	var busErr dbus.Error
	return errors.As(err, &busErr) && (busErr.Name == "org.freedesktop.DBus.Error.NameHasNoOwner" ||
		busErr.Name == "org.freedesktop.DBus.Error.ServiceUnknown")
}
