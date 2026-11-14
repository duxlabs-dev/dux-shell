package tailscale

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"
	"unicode"
)

const (
	operatorGrantTimeout = 3 * time.Minute
	defaultLoginServer   = "https://controlplane.tailscale.com"
)

var (
	ErrOperatorGrantCancelled = errors.New("permission not granted")
	operatorUsernameRe        = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_.-]*\$?$`)
)

type commandRunner func(ctx context.Context, argv []string) (output []byte, exitCode int, err error)

type (
	statFunc     func(string) (os.FileInfo, error)
	lookPathFunc func(string) (string, error)
	userFunc     func() (*user.User, error)
)

// The elevated argv never goes through a shell. Only the login server comes from IPC callers,
// validated and passed as a single element after "=", so it can't become a flag.
func operatorGrantArgv(stat statFunc, lookPath lookPathFunc, current userFunc) ([]string, error) {
	pkexec, tailscale, username, err := resolveOperatorCommand(stat, lookPath, current)
	if err != nil {
		return nil, err
	}
	return []string{pkexec, tailscale, "set", "--operator=" + username}, nil
}

// addProfileArgv creates a new profile owned by the operator; --timeout=1s makes the
// CLI exit on its own right after it has started the login.
func addProfileArgv(stat statFunc, lookPath lookPathFunc, current userFunc, server string) ([]string, error) {
	server, err := validLoginServer(server)
	if err != nil {
		return nil, err
	}
	pkexec, tailscale, username, err := resolveOperatorCommand(stat, lookPath, current)
	if err != nil {
		return nil, err
	}
	return []string{pkexec, tailscale, "login", "--operator=" + username, "--login-server=" + server, "--timeout=1s"}, nil
}

func validLoginServer(raw string) (string, error) {
	if raw == "" {
		return defaultLoginServer, nil
	}
	errInvalid := errors.New("login server must be an http or https URL without credentials, query or fragment")
	if strings.IndexFunc(raw, func(r rune) bool { return unicode.IsSpace(r) || unicode.IsControl(r) }) >= 0 ||
		strings.ContainsAny(raw, "?#") {
		return "", errInvalid
	}
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" || u.User != nil {
		return "", errInvalid
	}
	return raw, nil
}

func resolveOperatorCommand(stat statFunc, lookPath lookPathFunc, current userFunc) (pkexec, tailscale, username string, err error) {
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
	if pkexec, err = resolve("pkexec"); err != nil {
		return
	}
	if tailscale, err = resolve("tailscale"); err != nil {
		return
	}
	u, err := current()
	if err != nil {
		return "", "", "", fmt.Errorf("current user: %w", err)
	}
	if !operatorUsernameRe.MatchString(u.Username) {
		return "", "", "", fmt.Errorf("unsupported user name %q", u.Username)
	}
	return pkexec, tailscale, u.Username, nil
}

func grantOperator(ctx context.Context, argv []string, run commandRunner) error {
	out, code, err := runElevated(ctx, argv, run, "tailscale set --operator")
	if err == nil && code != 0 {
		return fmt.Errorf("tailscale set --operator failed: %s", out)
	}
	return err
}

// runElevated returns the trimmed output and exit code. A dismissed or refused
// pkexec prompt returns ErrOperatorGrantCancelled.
func runElevated(ctx context.Context, argv []string, run commandRunner, label string) (string, int, error) {
	if len(argv) == 0 {
		return "", 0, errors.New("empty command")
	}
	ctx, cancel := context.WithTimeout(ctx, operatorGrantTimeout)
	defer cancel()

	raw, code, err := run(ctx, argv)
	out := strings.TrimSpace(string(raw))
	switch {
	case err != nil:
		return out, code, fmt.Errorf("%s failed: %w", label, err)
	case code == 126 || code == 127:
		// 126: dialog dismissed; 127: not authorized or pkexec failed
		if out != "" {
			return out, code, fmt.Errorf("%w: %s", ErrOperatorGrantCancelled, out)
		}
		return out, code, ErrOperatorGrantCancelled
	}
	return out, code, nil
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
