//go:build linux

package config

import (
	"fmt"
	"net"
	"os"
	"time"

	"golang.org/x/sys/unix"
)

const niriSocketDialTimeout = time.Second

// A package upgrade swaps niri on PATH while the session keeps running the old one; /proc still execs it.
func runningNiriExe() string {
	socket := os.Getenv("NIRI_SOCKET")
	if socket == "" {
		return ""
	}
	conn, err := net.DialTimeout("unix", socket, niriSocketDialTimeout)
	if err != nil {
		return ""
	}
	defer conn.Close()

	unixConn, ok := conn.(*net.UnixConn)
	if !ok {
		return ""
	}
	raw, err := unixConn.SyscallConn()
	if err != nil {
		return ""
	}
	var cred *unix.Ucred
	var credErr error
	if err := raw.Control(func(fd uintptr) {
		cred, credErr = unix.GetsockoptUcred(int(fd), unix.SOL_SOCKET, unix.SO_PEERCRED)
	}); err != nil || credErr != nil {
		return ""
	}
	// A peer in another pid namespace reports pid 0.
	if cred.Pid <= 0 {
		return ""
	}
	exe := fmt.Sprintf("/proc/%d/exe", cred.Pid)
	if _, err := os.Stat(exe); err != nil {
		return ""
	}
	return exe
}
