package firewall

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"slices"
	"strings"
)

var errHelperGone = errors.New("firewall helper exited")

type Helper struct {
	run      func(args ...string) (string, error)
	defaults func() (string, error)
}

func NewHelper() *Helper {
	return &Helper{
		run: runUFW,
		defaults: func() (string, error) {
			data, err := os.ReadFile(ufwDefaultFile)
			return string(data), err
		},
	}
}

func runUFW(args ...string) (string, error) {
	cmd := exec.Command("ufw", args...)
	cmd.Env = []string{"LC_ALL=C", "PATH=/usr/sbin:/usr/bin:/sbin:/bin"}
	output, err := cmd.CombinedOutput()
	if err != nil {
		if errors.Is(err, exec.ErrNotFound) {
			return "", errors.New("ufw is not installed")
		}
		if message := strings.TrimSpace(string(output)); message != "" {
			return "", errors.New(message)
		}
		return "", err
	}
	return string(output), nil
}

func stringParam(params map[string]any, key string) string {
	value, _ := params[key].(string)
	return value
}

func (h *Helper) Call(method string, params map[string]any) (any, error) {
	switch method {
	case "ping":
		return true, nil
	case "state":
		return h.state()
	case "status":
		return h.run("status")
	case "rule.add":
		return h.addRule(params)
	case "rule.delete":
		return h.deleteRule(stringParam(params, "spec"))
	case "default.set":
		return h.setDefault(stringParam(params, "direction"), stringParam(params, "policy"))
	}
	return nil, fmt.Errorf("unknown method: %s", method)
}

func (h *Helper) state() (any, error) {
	added, err := h.run("show", "added")
	if err != nil {
		return nil, err
	}
	apps, err := h.run("app", "list")
	if err != nil {
		return nil, err
	}
	defaults, err := h.defaults()
	if err != nil {
		return nil, err
	}
	return ufwRawState{Added: added, Apps: apps, Defaults: defaults}, nil
}

func (h *Helper) addRule(params map[string]any) (any, error) {
	spec := RuleSpec{
		Kind:   stringParam(params, "kind"),
		Action: stringParam(params, "action"),
		Target: stringParam(params, "target"),
		Proto:  stringParam(params, "proto"),
		Source: stringParam(params, "source"),
	}
	if err := spec.Validate(); err != nil {
		return nil, err
	}
	if spec.Kind == KindService {
		apps, err := h.run("app", "list")
		if err != nil {
			return nil, err
		}
		if !slices.Contains(parseUFWApps(apps), spec.Target) {
			return nil, fmt.Errorf("unknown application: %q", spec.Target)
		}
	}
	if _, err := h.run(spec.ufwArgs()...); err != nil {
		return nil, err
	}
	return true, nil
}

func (h *Helper) deleteRule(spec string) (any, error) {
	added, err := h.run("show", "added")
	if err != nil {
		return nil, err
	}
	listed := slices.ContainsFunc(parseUFWAdded(added), func(rule Rule) bool { return rule.ID == spec })
	if !listed {
		return nil, errors.New("no such rule")
	}
	args, err := ufwDeleteArgs(spec)
	if err != nil {
		return nil, err
	}
	if _, err := h.run(args...); err != nil {
		return nil, err
	}
	return true, nil
}

func ufwDeleteArgs(spec string) ([]string, error) {
	tokens, err := splitQuoted(spec)
	if err != nil {
		return nil, err
	}
	if len(tokens) == 0 {
		return nil, errors.New("empty rule")
	}
	if tokens[0] == "route" {
		return append([]string{"--force", "route", "delete"}, tokens[1:]...), nil
	}
	return append([]string{"--force", "delete"}, tokens...), nil
}

func (h *Helper) setDefault(direction, policy string) (any, error) {
	if direction != "incoming" && direction != "outgoing" {
		return nil, fmt.Errorf("invalid direction: %q", direction)
	}
	if policy != ActionAllow && policy != ActionDeny && policy != ActionReject {
		return nil, fmt.Errorf("invalid policy: %q", policy)
	}
	if _, err := h.run("default", policy, direction); err != nil {
		return nil, err
	}
	return true, nil
}

// splitQuoted undoes the single quotes ufw puts around app names and comments.
func splitQuoted(value string) ([]string, error) {
	tokens := []string{}
	var current strings.Builder
	inQuote, hasToken := false, false
	for _, r := range value {
		switch {
		case r == '\'':
			inQuote = !inQuote
			hasToken = true
		case r == ' ' && !inQuote:
			if hasToken {
				tokens = append(tokens, current.String())
				current.Reset()
				hasToken = false
			}
		default:
			current.WriteRune(r)
			hasToken = true
		}
	}
	if inQuote {
		return nil, errors.New("unbalanced quote in rule")
	}
	if hasToken {
		tokens = append(tokens, current.String())
	}
	return tokens, nil
}

type processHelper struct {
	cmd    *exec.Cmd
	stdin  io.WriteCloser
	stdout io.ReadCloser
	lines  *bufio.Scanner
	nextID int
}

func startProcessHelper(ctx context.Context) (ufwHelper, error) {
	dms, err := os.Executable()
	if err != nil {
		return nil, err
	}
	cmd := exec.Command("pkexec", dms, "firewall-helper")
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}

	lines := bufio.NewScanner(stdout)
	lines.Buffer(make([]byte, 64*1024), 4*1024*1024)
	helper := &processHelper{cmd: cmd, stdin: stdin, stdout: stdout, lines: lines}

	// Killing pkexec ends its prompt. Once it has become the root helper the kill is
	// refused, and Unlock closes that helper instead.
	stopCancel := context.AfterFunc(ctx, func() { _ = cmd.Process.Kill() })
	defer stopCancel()

	err = helper.Call("ping", nil, nil)
	if err == nil {
		return helper, nil
	}
	_ = stdin.Close()
	waitErr := cmd.Wait()
	if ctx.Err() != nil {
		return nil, ErrAuthDismissed
	}
	var exitErr *exec.ExitError
	if errors.As(waitErr, &exitErr) {
		switch exitErr.ExitCode() {
		case 126:
			return nil, ErrAuthDismissed
		case 127:
			return nil, errors.New("authorization failed, is a polkit agent running?")
		}
	}
	return nil, err
}

func (h *processHelper) Call(method string, params map[string]any, out any) error {
	h.nextID++
	id := h.nextID
	request, err := json.Marshal(map[string]any{"id": id, "method": method, "params": params})
	if err != nil {
		return err
	}
	if _, err := h.stdin.Write(append(request, '\n')); err != nil {
		return errHelperGone
	}
	if !h.lines.Scan() {
		return errHelperGone
	}

	var response struct {
		ID     int             `json:"id"`
		Result json.RawMessage `json:"result"`
		Error  string          `json:"error"`
	}
	if err := json.Unmarshal(h.lines.Bytes(), &response); err != nil {
		return err
	}
	if response.ID != id {
		return errHelperGone
	}
	if response.Error != "" {
		return errors.New(response.Error)
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(response.Result, out)
}

func (h *processHelper) Close() {
	_ = h.stdin.Close()
	go func() {
		_, _ = io.Copy(io.Discard, h.stdout)
		_ = h.cmd.Wait()
	}()
}
