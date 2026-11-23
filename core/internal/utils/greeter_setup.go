package utils

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"

	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

var validateSudoPassword = privesc.ValidatePassword

// RunDmsGreeterInstall delegates greeter setup to the standalone dms-greeter
// binary, which owns greetd configuration since the greeter moved out of DMS.
// dms-greeter refuses sudo and escalates itself, so cache the credential first.
func RunDmsGreeterInstall(sudoPassword string, logFunc func(string)) error {
	binary, err := exec.LookPath("dms-greeter")
	if err != nil {
		return fmt.Errorf("dms-greeter binary not found; install the dms-greeter package and run 'dms-greeter install'")
	}

	if sudoPassword != "" {
		if err := validateSudoPassword(context.Background(), sudoPassword); err != nil {
			return fmt.Errorf("could not refresh sudo credentials for greeter setup: %w", err)
		}
	}

	cmd := exec.Command(binary, "install", "--yes")
	if sudoPassword != "" {
		// Use the tool whose credential was just cached.
		cmd.Env = append(os.Environ(), privesc.EnvVar+"=sudo")
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
