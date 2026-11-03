package main

import (
	"fmt"
	"os/exec"
	"strings"
)

const dmsSystemdUnit = "dms.service"
const dmsSessionRestartExitCode = 75 // EX_TEMPFAIL

var runSystemctl = func(args ...string) error {
	output, err := exec.Command("systemctl", args...).CombinedOutput()
	if err == nil {
		return nil
	}
	if detail := strings.TrimSpace(string(output)); detail != "" {
		return fmt.Errorf("%s: %w", detail, err)
	}
	return err
}

// Assigned in init: shellApp's config refers back to trySystemdRestart.
var shellRunning func() bool

func init() {
	shellRunning = func() bool { return len(shellApp.PIDs()) > 0 }
}

func trySystemdRestart() (bool, error) {
	if err := runSystemctl("--user", "is-active", "--quiet", dmsSystemdUnit); err != nil {
		return trySystemdStart()
	}

	if err := runSystemctl("--user", "restart", dmsSystemdUnit); err != nil {
		return true, fmt.Errorf("restarting %s: %w", dmsSystemdUnit, err)
	}
	return true, nil
}

// With nothing running, restart would spawn an unmanaged daemon that blocks
// the unit once the session target starts it. A running hand-started
// instance is left to the plain restart path.
func trySystemdStart() (bool, error) {
	if shellRunning() {
		return false, nil
	}
	if err := runSystemctl("--user", "is-enabled", "--quiet", dmsSystemdUnit); err != nil {
		return false, nil
	}
	if err := runSystemctl("--user", "is-active", "--quiet", "graphical-session.target"); err != nil {
		return false, nil
	}

	if err := runSystemctl("--user", "start", dmsSystemdUnit); err != nil {
		return true, fmt.Errorf("starting %s: %w", dmsSystemdUnit, err)
	}
	return true, nil
}
