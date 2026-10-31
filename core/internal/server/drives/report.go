package drives

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"regexp"
	"sync"
	"time"
)

const (
	reportTimeout  = 30 * time.Second
	reportMaxBytes = 4 << 20
)

var reportMu sync.Mutex

var wholeDiskPath = regexp.MustCompile(`^/dev/[A-Za-z0-9]+$`)

// Report is smartctl's JSON output for one drive. smartctl sets exit bits for drive warnings too, so the output is
// worth reading whatever ExitCode says.
type Report struct {
	Output   string `json:"output"`
	ExitCode int    `json:"exitCode"`
}

// FullReport runs `smartctl -x --json` on a block device. The system monitor's root helper calls it, so the device
// must be a plain /dev path of a block device.
func FullReport(device string) (*Report, error) {
	if !wholeDiskPath.MatchString(device) {
		return nil, errors.New("invalid device")
	}
	fi, err := os.Stat(device)
	if err != nil || fi.Mode()&os.ModeDevice == 0 || fi.Mode()&os.ModeCharDevice != 0 {
		return nil, errors.New("not a block device")
	}
	path := smartctlPath()
	if path == "" {
		return nil, errors.New("smartctl not found")
	}
	reportMu.Lock()
	defer reportMu.Unlock()

	ctx, cancel := context.WithTimeout(context.Background(), reportTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, "-x", "--json", device)
	cmd.WaitDelay = 2 * time.Second
	pipe, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	out, readErr := io.ReadAll(io.LimitReader(pipe, reportMaxBytes+1))
	tooBig := len(out) > reportMaxBytes
	if tooBig {
		cancel()
	}
	err = cmd.Wait()
	switch {
	case tooBig:
		return nil, errors.New("report too large")
	case ctx.Err() != nil:
		return nil, errors.New("smartctl timed out")
	case readErr != nil:
		return nil, readErr
	}
	var exitErr *exec.ExitError
	switch {
	case errors.As(err, &exitErr):
		return &Report{Output: string(out), ExitCode: exitErr.ExitCode()}, nil
	case err != nil:
		return nil, err
	}
	return &Report{Output: string(out)}, nil
}
