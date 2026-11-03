package registries

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

// flock is per open file, so concurrent goroutines contend like separate processes.
func LockCache() (unlock func(), err error) {
	dir := filepath.Join(utils.RuntimeDir(), "dms")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("create registry lock dir: %w", err)
	}

	f, err := os.OpenFile(filepath.Join(dir, "registry.lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open registry lock: %w", err)
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, fmt.Errorf("acquire registry lock: %w", err)
	}
	return func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}
