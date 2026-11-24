package network

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"sort"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

const (
	vpnAuthDialogMaxOutput = 64 << 10
	vpnAuthDialogMaxStderr = 4 << 10
)

var errVPNAuthDialogCancelled = errors.New("VPN auth dialog cancelled")

type vpnAuthDialogRequest struct {
	Dialog      string
	UUID        string
	Name        string
	ServiceType string
	ExternalUI  bool
	Data        map[string]string
	Secrets     map[string]string
}

type vpnUISecret struct {
	Name      string
	Label     string
	Value     string
	IsSecret  bool
	ShouldAsk bool
}

// Legacy mode returns secrets; external UI mode returns the dialog's fields in order.
func runVPNAuthDialog(ctx context.Context, req vpnAuthDialogRequest) (map[string]string, []vpnUISecret, error) {
	args := []string{"-u", req.UUID, "-n", req.Name, "-s", req.ServiceType, "-i"}
	if req.ExternalUI {
		args = append(args, "--external-ui-mode")
	}

	input, err := vpnAuthDialogInput(req.Data, req.Secrets)
	if err != nil {
		return nil, nil, err
	}

	runCtx, kill := context.WithCancel(ctx)
	defer kill()
	cmd := exec.CommandContext(runCtx, req.Dialog, args...)
	// Bounds Wait when children of a killed dialog still hold stderr.
	cmd.WaitDelay = 2 * time.Second
	stderr := &cappedBuffer{max: vpnAuthDialogMaxStderr}
	cmd.Stderr = stderr
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, nil, fmt.Errorf("VPN auth dialog: failed to create stdin pipe: %w", err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, nil, fmt.Errorf("VPN auth dialog: failed to create stdout pipe: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return nil, nil, fmt.Errorf("VPN auth dialog: failed to start %s: %w", req.Dialog, err)
	}
	// Children of a killed dialog can hold stdout open, so the read below would never end.
	defer context.AfterFunc(runCtx, func() { stdout.Close() })()

	outputRead := make(chan struct{})
	go func() {
		defer stdin.Close()
		if _, err := io.WriteString(stdin, input); err != nil {
			return
		}
		<-outputRead
		if !req.ExternalUI {
			_, _ = io.WriteString(stdin, "QUIT\n\n")
		}
	}()

	limited := &io.LimitedReader{R: stdout, N: vpnAuthDialogMaxOutput + 1}
	var secrets map[string]string
	var output []byte
	var readErr error
	if req.ExternalUI {
		output, readErr = io.ReadAll(limited)
	} else {
		secrets, readErr = readLegacyDialogSecrets(bufio.NewReader(limited))
	}
	tooBig := limited.N <= 0
	if tooBig {
		kill()
	}
	close(outputRead)
	waitErr := cmd.Wait()
	if stderr.Len() > 0 {
		log.Debugf("[VPN] auth dialog %s stderr: %s", req.Dialog, stderr.String())
	}

	var exitErr *exec.ExitError
	switch {
	case ctx.Err() != nil:
		return nil, nil, fmt.Errorf("VPN auth dialog timed out or was cancelled: %w", ctx.Err())
	case tooBig:
		return nil, nil, fmt.Errorf("VPN auth dialog output exceeds %d bytes", vpnAuthDialogMaxOutput)
	case errors.As(waitErr, &exitErr) && exitErr.Exited() && !req.ExternalUI:
		return nil, nil, errVPNAuthDialogCancelled
	case waitErr != nil:
		return nil, nil, fmt.Errorf("VPN auth dialog failed: %w: %s", waitErr, stderrTail(stderr.String()))
	case readErr != nil:
		return nil, nil, fmt.Errorf("VPN auth dialog: reading output: %w", readErr)
	case !req.ExternalUI:
		return secrets, nil, nil
	}
	fields, err := parseVPNUIKeyfile(output)
	if err != nil {
		return nil, nil, err
	}
	return nil, fields, nil
}

func vpnAuthDialogInput(data, secrets map[string]string) (string, error) {
	var b strings.Builder
	write := func(kind string, m map[string]string) error {
		keys := make([]string, 0, len(m))
		for k := range m {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			// A line break would let the value start a new protocol line.
			if strings.ContainsAny(k+m[k], "\r\n") {
				return fmt.Errorf("VPN auth dialog: %s %q contains a line break", strings.ToLower(kind), k)
			}
			fmt.Fprintf(&b, "%s_KEY=%s\n%s_VAL=%s\n\n", kind, k, kind, m[k])
		}
		return nil
	}
	if err := write("DATA", data); err != nil {
		return "", err
	}
	if err := write("SECRET", secrets); err != nil {
		return "", err
	}
	b.WriteString("DONE\n\n")
	return b.String(), nil
}

func stderrTail(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 200 {
		s = "..." + s[len(s)-200:]
	}
	if s == "" {
		return "no error output"
	}
	return s
}

// readLegacyDialogSecrets reads alternating key and value lines. An empty key line ends the
// list, so values may be empty.
func readLegacyDialogSecrets(r *bufio.Reader) (map[string]string, error) {
	secrets := map[string]string{}
	for {
		key, err := readDialogLine(r)
		if err != nil {
			return nil, err
		}
		if key == "" {
			return secrets, nil
		}
		value, err := readDialogLine(r)
		if err != nil {
			return nil, err
		}
		secrets[key] = value
	}
}

func readDialogLine(r *bufio.Reader) (string, error) {
	line, err := r.ReadString('\n')
	if errors.Is(err, io.EOF) {
		return "", errors.New("output ended before the end of the secrets list")
	}
	if err != nil {
		return "", err
	}
	return strings.TrimSuffix(line, "\n"), nil
}

// parseVPNUIKeyfile reads the GLib keyfile an auth dialog prints in external UI mode. Each
// group other than [VPN Plugin UI] describes one secret, named by the group.
func parseVPNUIKeyfile(data []byte) ([]vpnUISecret, error) {
	var fields []vpnUISecret
	var cur *vpnUISecret
	for i, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			cur = nil
			if group := line[1 : len(line)-1]; group != "VPN Plugin UI" {
				fields = append(fields, vpnUISecret{Name: group})
				cur = &fields[len(fields)-1]
			}
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			return nil, fmt.Errorf("VPN auth dialog output line %d is not a key=value pair", i+1)
		}
		key = strings.TrimSpace(key)
		if cur == nil {
			continue
		}
		value = unescapeKeyfileValue(strings.TrimSpace(value))
		switch key {
		case "Value":
			cur.Value = value
		case "Label":
			cur.Label = value
		case "IsSecret":
			cur.IsSecret = value == "true" || value == "1"
		case "ShouldAsk":
			cur.ShouldAsk = value == "true" || value == "1"
		}
	}
	return fields, nil
}

func unescapeKeyfileValue(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	return strings.NewReplacer(`\\`, `\`, `\s`, " ", `\n`, "\n", `\t`, "\t", `\r`, "\r").Replace(s)
}

type cappedBuffer struct {
	strings.Builder
	max int
}

func (b *cappedBuffer) Write(p []byte) (int, error) {
	if room := b.max - b.Len(); room > 0 {
		b.Builder.Write(p[:min(room, len(p))])
	}
	return len(p), nil
}
