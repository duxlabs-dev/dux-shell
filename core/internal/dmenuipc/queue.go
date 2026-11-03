package dmenuipc

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

func AcquireQueueSlot(onWait func()) (release func(), err error) {
	dir := filepath.Join(utils.RuntimeDir(), "dms")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("create dmenu queue dir: %w", err)
	}
	path := filepath.Join(dir, "dmenu.lock")

	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open dmenu queue lock: %w", err)
	}

	release = func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}

	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil {
		return release, nil
	}

	if onWait != nil {
		onWait()
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, fmt.Errorf("acquire dmenu queue lock: %w", err)
	}
	return release, nil
}
