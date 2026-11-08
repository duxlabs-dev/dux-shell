package tailscale

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"
)

const operatorGrantTimeout = 3 * time.Minute

var (
	ErrOperatorGrantCancelled = errors.New("permission not granted")
	operatorUsernameRe        = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_.-]*\$?$`)
)

type commandRunner func(ctx context.Context, argv []string) (output []byte, exitCode int, err error)

// The argv is fixed: nothing in it comes from IPC callers, and it never goes through a shell.
func operatorGrantArgv(stat func(string) (os.FileInfo, error), lookPath func(string) (string, error), current func() (*user.User, error)) ([]string, error) {
	resolve := func(name string) (string, error) {
		p, err := lookPath(name)
		if err != nil && !errors.Is(err, exec.ErrNotFound) {
			return "", fmt.Errorf("%s not usable: %w", name, err)
		}
		if err != nil || !filepath.IsAbs(p) {
			return "", fmt.Errorf("%s not found", name)
		}
		fi, err := stat(p)
		if err != nil {
			return "", fmt.Errorf("%s not usable: %w", name, err)
		}
		st, ok := fi.Sys().(*syscall.Stat_t)
		switch {
		case !ok, st.Uid != 0, !fi.Mode().IsRegular(), fi.Mode().Perm()&0o022 != 0:
			return "", fmt.Errorf("%s must be a root-owned file not writable by others", p)
		case name == "pkexec" && fi.Mode()&os.ModeSetuid == 0:
			return "", fmt.Errorf("%s is not setuid", p)
		}
		return p, nil
	}
	pkexec, err := resolve("pkexec")
	if err != nil {
		return nil, err
	}
	tailscale, err := resolve("tailscale")
	if err != nil {
		return nil, err
	}
	u, err := current()
	if err != nil {
		return nil, fmt.Errorf("current user: %w", err)
	}
	if !operatorUsernameRe.MatchString(u.Username) {
		return nil, fmt.Errorf("unsupported user name %q", u.Username)
	}
	return []string{pkexec, tailscale, "set", "--operator=" + u.Username}, nil
}

func grantOperator(ctx context.Context, argv []string, run commandRunner) error {
	if len(argv) == 0 {
		return errors.New("empty command")
	}
	ctx, cancel := context.WithTimeout(ctx, operatorGrantTimeout)
	defer cancel()

	out, code, err := run(ctx, argv)
	switch {
	case err != nil:
		return fmt.Errorf("tailscale set --operator failed: %w", err)
	case code == 0:
		return nil
	case code == 126 || code == 127:
		// 126: dialog dismissed; 127: not authorized or pkexec failed
		if msg := strings.TrimSpace(string(out)); msg != "" {
			return fmt.Errorf("%w: %s", ErrOperatorGrantCancelled, msg)
		}
		return ErrOperatorGrantCancelled
	default:
		return fmt.Errorf("tailscale set --operator failed: %s", strings.TrimSpace(string(out)))
	}
}

func execCommandRunner(ctx context.Context, argv []string) ([]byte, int, error) {
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.WaitDelay = 5 * time.Second
	out, err := cmd.CombinedOutput()
	if errors.Is(err, exec.ErrWaitDelay) && cmd.ProcessState != nil && cmd.ProcessState.Success() {
		return out, 0, nil
	}
	if ctxErr := ctx.Err(); ctxErr != nil {
		return out, -1, ctxErr
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return out, exitErr.ExitCode(), nil
	}
	if err != nil {
		return out, -1, err
	}
	return out, 0, nil
}
