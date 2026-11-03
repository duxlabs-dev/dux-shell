package main

import (
	"errors"
	"slices"
	"strings"
	"testing"
)

func TestTrySystemdRestart(t *testing.T) {
	tests := []struct {
		name        string
		running     bool
		ok          []string
		wantHandled bool
		wantCall    string
	}{
		{"active unit restarts", false, []string{"is-active dms.service", "restart"}, true, "restart dms.service"},
		{"enabled inactive unit starts", false, []string{"is-enabled", "is-active graphical-session.target", "start"}, true, "start dms.service"},
		{"hand-started instance keeps plain restart", true, []string{"is-enabled", "is-active graphical-session.target", "start"}, false, ""},
		{"session target not up", false, []string{"is-enabled"}, false, ""},
		{"unit disabled", false, []string{"is-active graphical-session.target"}, false, ""},
		{"no systemd", false, nil, false, ""},
	}

	origSystemctl, origRunning := runSystemctl, shellRunning
	t.Cleanup(func() { runSystemctl, shellRunning = origSystemctl, origRunning })

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			shellRunning = func() bool { return tt.running }
			var calls []string
			runSystemctl = func(args ...string) error {
				call := strings.Join(slices.DeleteFunc(slices.Clone(args), func(a string) bool {
					return strings.HasPrefix(a, "--")
				}), " ")
				calls = append(calls, call)
				for _, prefix := range tt.ok {
					if strings.HasPrefix(call, prefix) {
						return nil
					}
				}
				return errors.New("exit status 3")
			}

			handled, err := trySystemdRestart()
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if handled != tt.wantHandled {
				t.Fatalf("handled = %v, want %v (calls %q)", handled, tt.wantHandled, calls)
			}
			if tt.wantCall != "" && !slices.Contains(calls, tt.wantCall) {
				t.Fatalf("missing %q in calls %q", tt.wantCall, calls)
			}
			if !tt.wantHandled && slices.ContainsFunc(calls, func(c string) bool { return strings.HasPrefix(c, "start") }) {
				t.Fatalf("unexpected start in calls %q", calls)
			}
		})
	}
}
