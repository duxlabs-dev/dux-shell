package sysupdate

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"sync"
	"syscall"

	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
)

type RunOptions struct {
	Env         []string
	OnLine      func(string)
	AttachStdio bool
}

func Run(ctx context.Context, argv []string, opts RunOptions) error {
	if len(argv) == 0 {
		return fmt.Errorf("sysupdate.Run: empty argv")
	}

	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	if len(opts.Env) > 0 {
		cmd.Env = append(cmd.Environ(), opts.Env...)
	}
	if opts.AttachStdio {
		cmd.Cancel = func() error {
			if cmd.Process == nil {
				return nil
			}
			return cmd.Process.Kill()
		}
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	}

	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		// Once pkexec authenticates, the group is root-owned and cannot be signalled.
		if errors.Is(err, syscall.EPERM) && opts.OnLine != nil {
			opts.OnLine("Cannot stop a privileged upgrade; waiting for it to finish.")
		}
		return err
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return err
	}

	if err := cmd.Start(); err != nil {
		return err
	}

	var wg sync.WaitGroup
	wg.Add(2)
	go pump(stdout, opts.OnLine, &wg)
	go pump(stderr, opts.OnLine, &wg)
	wg.Wait()

	err = cmd.Wait()
	// The kill was refused and the process then exited cleanly, so the run succeeded.
	if errors.Is(err, syscall.EPERM) {
		return nil
	}
	return err
}

// pkexec exits 126 when the authentication dialog is dismissed.
func isAuthDismissed(err error) bool {
	var exitErr *exec.ExitError
	return errors.As(err, &exitErr) && exitErr.ExitCode() == 126
}

func pump(r io.Reader, onLine func(string), wg *sync.WaitGroup) {
	defer wg.Done()
	if onLine == nil {
		_, _ = io.Copy(io.Discard, r)
		return
	}
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)
	for scanner.Scan() {
		onLine(scanner.Text())
	}
}

func Capture(ctx context.Context, argv []string) (string, error) {
	if len(argv) == 0 {
		return "", fmt.Errorf("sysupdate.Capture: empty argv")
	}
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	out, err := cmd.Output()
	return string(out), err
}

// privescBin returns the binary to use for privilege escalation.
// When useSudo is true it auto-detects the best available tool (sudo/doas/run0).
// When false it falls back to pkexec for GUI callers.
func privescBin(useSudo bool) string {
	if useSudo {
		if t, err := privesc.Detect(); err == nil {
			return t.Name()
		}
	}
	return "pkexec"
}

func findTerminal(override string) string {
	if override != "" && commandExists(override) {
		return override
	}
	if t := os.Getenv("TERMINAL"); t != "" && commandExists(t) {
		return t
	}
	for _, t := range []string{"ghostty", "kitty", "foot", "alacritty", "wezterm", "konsole", "gnome-terminal", "xterm"} {
		if commandExists(t) {
			return t
		}
	}
	return ""
}

func wrapInTerminal(term, title, shellCmd string, extraArgs []string) []string {
	const appID = "dev.duxlabs.shell"
	banner := fmt.Sprintf(
		`printf '\033[1;36m=== %s ===\033[0m\n'; printf '\033[2m$ %s\033[0m\n'; printf '\033[33mYou may be prompted for your sudo password to apply system updates.\033[0m\n\n'`,
		title, shellCmd,
	)
	closer := `dms_update_status=$?
if [ "$dms_update_status" -eq 0 ]; then
    printf '\n\033[1;32m=== Done. Press Enter to close. ===\033[0m\n'
else
    printf '\n\033[1;31m=== Update failed (exit %s). Press Enter to close. ===\033[0m\n' "$dms_update_status"
fi
read -r dms_update_reply
exit "$dms_update_status"`
	export := `export SUDO_PROMPT="[DMS] sudo password for %u: "; `
	full := export + banner + "; " + shellCmd + "; " + closer

	var argv []string
	execFlag := "-e"
	switch term {
	case "kitty", "alacritty":
		argv = []string{term, "--class", appID, "-T", title}
	case "wezterm":
		argv = []string{term, "start", "--always-new-process", "--class", appID}
		execFlag = "--"
	case "foot":
		argv = []string{term, "--app-id=" + appID, "--title=" + title}
	case "ghostty":
		argv = []string{term, "--class=" + appID, "--title=" + title}
	case "xterm":
		argv = []string{term, "-class", appID, "-T", title}
	case "konsole":
		argv = []string{term, "-p", "tabtitle=" + title}
	case "gnome-terminal":
		// --wait: the factory process otherwise returns immediately
		argv = []string{term, "--wait", "--title=" + title}
		execFlag = "--"
	default:
		argv = []string{term}
	}
	argv = append(argv, extraArgs...)
	return append(argv, execFlag, "sh", "-c", full)
}
