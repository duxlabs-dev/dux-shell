//go:build linux

package lowprio

import (
	"runtime"

	"golang.org/x/sys/unix"
)

func LowerThreadPriority() {
	_ = unix.Setpriority(unix.PRIO_PROCESS, unix.Gettid(), 19)
}

// The thread is never unlocked, so it dies with the goroutine instead of rejoining the pool niced.
// Processes started by job inherit the priority.
func Go(job func()) {
	go func() {
		runtime.LockOSThread()
		LowerThreadPriority()
		job()
	}()
}
