package utils

import (
	"bufio"
	"context"
	"fmt"
	"os/exec"

	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

// RunDmsGreeterInstall delegates greeter setup to the standalone dms-greeter
// binary, which owns greetd configuration since the greeter moved out of DMS.
func RunDmsGreeterInstall(sudoPassword string, logFunc func(string)) error {
	binary, err := exec.LookPath("dms-greeter")
	if err != nil {
		return fmt.Errorf("dms-greeter binary not found; install the dms-greeter package and run 'dms-greeter install'")
	}

	// Without a password dms-greeter escalates on its own.
	argv := []string{binary, "install", "--yes"}
	cmd := exec.Command(argv[0], argv[1:]...)
	if sudoPassword != "" {
		cmd = privesc.ExecCommand(context.Background(), sudoPassword, privesc.QuoteArgsForShell(argv))
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = cmd.Stdout

	if err := cmd.Start(); err != nil {
		return err
	}
	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		logFunc(scanner.Text())
	}
	return cmd.Wait()
}
