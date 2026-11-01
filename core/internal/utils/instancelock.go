package utils

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

const (
	// Shared by the screenshot region selector and the color picker: one grabbing overlay at a time.
	SelectionOverlayLock = "dms-selection-overlay"
	// Matches what the wayland client dials when WAYLAND_DISPLAY is unset.
	defaultWaylandDisplay = "wayland-0"
)

var (
	ErrLockHeld      = errors.New("lock is held by another process")
	ErrOverlayActive = errors.New("another dms selection overlay is already open")
)

type FileLock struct {
	file *os.File
}

func displayScope() string {
	name := filepath.Base(os.Getenv("WAYLAND_DISPLAY"))
	switch name {
	case ".", "..", string(filepath.Separator):
		return defaultWaylandDisplay
	}
	return name
}

// One user's concurrent sessions share XDG_RUNTIME_DIR, so the lock is per wayland display.
func lockPath(name string) string {
	return filepath.Join(RuntimeDir(), fmt.Sprintf("%s-%d-%s.lock", name, os.Getuid(), displayScope()))
}

func lockHolderPID(name string) int {
	data, err := os.ReadFile(lockPath(name))
	if err != nil {
		return 0
	}

	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return 0
	}
	return pid
}

func TryLock(name string) (*FileLock, error) {
	f, err := os.OpenFile(lockPath(name), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}

	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, ErrLockHeld
		}
		return nil, err
	}

	if err := f.Truncate(0); err == nil {
		_, _ = f.WriteString(strconv.Itoa(os.Getpid()))
	}

	return &FileLock{file: f}, nil
}

// LockSelectionOverlay only refuses on contention: a lock file that cannot be created or
// flocked yields a nil lock and no error, so the overlay still runs unguarded.
func LockSelectionOverlay() (*FileLock, error) {
	lock, err := TryLock(SelectionOverlayLock)
	if err == nil {
		return lock, nil
	}

	if !errors.Is(err, ErrLockHeld) {
		log.Debug("selection overlay lock unavailable", "err", err)
		return nil, nil
	}

	if pid := lockHolderPID(SelectionOverlayLock); pid > 0 {
		return nil, fmt.Errorf("%w (pid %d)", ErrOverlayActive, pid)
	}
	return nil, ErrOverlayActive
}

func (l *FileLock) Release() {
	if l == nil || l.file == nil {
		return
	}
	_ = syscall.Flock(int(l.file.Fd()), syscall.LOCK_UN)
	l.file.Close()
	l.file = nil
}
