package main

import (
	"os"
	"os/exec"
	"runtime"
	"strings"
)

func disableMemProfilingUnlessRequested() {
	if os.Getenv("DMS_PPROF") != "" {
		return
	}
	runtime.MemProfileRate = 0
}

func firstArg(args []string) string {
	for _, arg := range args[1:] {
		if !strings.HasPrefix(arg, "-") {
			return arg
		}
	}
	return ""
}

// isReadOnlyCommand returns true if the CLI args indicate a command that is
// safe to run as root (e.g. shell completion, help).
func isReadOnlyCommand(args []string) bool {
	switch firstArg(args) {
	case "completion", "help", "__complete", "system":
		return true
	}
	return false
}

// sysmon-helper is started through pkexec and has to run as root.
func isRootHelper(args []string) bool {
	return firstArg(args) == "sysmon-helper"
}

func isArchPackageInstalled(packageName string) bool {
	cmd := exec.Command("pacman", "-Q", packageName)
	err := cmd.Run()
	return err == nil
}
