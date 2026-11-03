package main

import (
	"encoding/json"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/clipolicy"
)

// The greeter commands forward to dms-greeter, which applies its own policy;
// a packaged /usr/share/dms/cli-policy.json can still block them here.
func TestDefaultImmutablePolicyBlocksNothing(t *testing.T) {
	var policyFile clipolicy.File
	if err := json.Unmarshal(defaultCLIPolicyJSON, &policyFile); err != nil {
		t.Fatalf("failed to parse embedded CLI policy: %v", err)
	}
	if policyFile.BlockedCommands == nil {
		t.Fatal("embedded CLI policy has no blocked_commands")
	}

	blocked := normalizeBlockedCommands(*policyFile.BlockedCommands)
	for _, command := range []string{"greeter install", "greeter enable", "greeter uninstall", "greeter sync"} {
		if commandBlockedByPolicy(command, blocked) {
			t.Fatalf("%s must be available by default on image-based systems", command)
		}
	}
	if commandBlockedByPolicy("setup", blocked) {
		t.Fatal("setup only writes to the home directory and must stay available on image-based systems")
	}
}
