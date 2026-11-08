package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"sync"

	"github.com/duxlabs-dev/dux-shell/core/internal/clipolicy"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
	"github.com/spf13/afero"
	"github.com/spf13/cobra"
)

var (
	immutablePolicyOnce sync.Once
	immutablePolicy     immutableCommandPolicy
	immutablePolicyErr  error
)

//go:embed assets/cli-policy.default.json
var defaultCLIPolicyJSON []byte

type immutableCommandPolicy struct {
	ImmutableSystem bool
	ImmutableReason string
	BlockedCommands []string
	Message         string
}

func normalizeCommandSpec(raw string) string {
	normalized := strings.ToLower(strings.TrimSpace(raw))
	normalized = strings.TrimPrefix(normalized, "dms ")
	return strings.Join(strings.Fields(normalized), " ")
}

func normalizeBlockedCommands(raw []string) []string {
	normalized := make([]string, 0, len(raw))
	seen := make(map[string]bool)

	for _, cmd := range raw {
		spec := normalizeCommandSpec(cmd)
		if spec == "" || seen[spec] {
			continue
		}
		seen[spec] = true
		normalized = append(normalized, spec)
	}

	return normalized
}

func commandBlockedByPolicy(commandPath string, blocked []string) bool {
	normalizedPath := normalizeCommandSpec(commandPath)
	if normalizedPath == "" {
		return false
	}

	for _, entry := range blocked {
		spec := normalizeCommandSpec(entry)
		if spec == "" {
			continue
		}
		if normalizedPath == spec || strings.HasPrefix(normalizedPath, spec+" ") {
			return true
		}
	}

	return false
}

func mergePolicyFile(base *immutableCommandPolicy, path string) error {
	policyFile, err := clipolicy.LoadFile(afero.NewOsFs(), path)
	if err != nil {
		return err
	}
	if policyFile == nil {
		return nil
	}

	if policyFile.ImmutableSystem != nil {
		base.ImmutableSystem = *policyFile.ImmutableSystem
	}
	if policyFile.BlockedCommands != nil {
		base.BlockedCommands = normalizeBlockedCommands(*policyFile.BlockedCommands)
	}
	if policyFile.Message != nil {
		msg := strings.TrimSpace(*policyFile.Message)
		if msg != "" {
			base.Message = msg
		}
	}

	return nil
}

func getImmutablePolicy() (*immutableCommandPolicy, error) {
	immutablePolicyOnce.Do(func() {
		detectedImmutable, reason := distros.DetectImmutable()
		immutablePolicy = immutableCommandPolicy{
			ImmutableSystem: detectedImmutable,
			ImmutableReason: reason,
			BlockedCommands: nil,
			Message:         "This command is disabled on immutable/image-based systems. Use your distro-native workflow for system-level changes.",
		}

		var defaultPolicy clipolicy.File
		if err := json.Unmarshal(defaultCLIPolicyJSON, &defaultPolicy); err != nil {
			immutablePolicyErr = fmt.Errorf("failed to parse embedded default CLI policy: %w", err)
			return
		}
		if defaultPolicy.BlockedCommands != nil {
			immutablePolicy.BlockedCommands = normalizeBlockedCommands(*defaultPolicy.BlockedCommands)
		}
		if defaultPolicy.Message != nil {
			msg := strings.TrimSpace(*defaultPolicy.Message)
			if msg != "" {
				immutablePolicy.Message = msg
			}
		}

		if err := mergePolicyFile(&immutablePolicy, clipolicy.PackagedPath); err != nil {
			immutablePolicyErr = err
			return
		}
		if err := mergePolicyFile(&immutablePolicy, clipolicy.AdminPath); err != nil {
			immutablePolicyErr = err
			return
		}
	})

	if immutablePolicyErr != nil {
		return nil, immutablePolicyErr
	}
	return &immutablePolicy, nil
}

func requireMutableSystemCommand(cmd *cobra.Command, _ []string) error {
	policy, err := getImmutablePolicy()
	if err != nil {
		return err
	}
	if !policy.ImmutableSystem {
		return nil
	}

	commandPath := normalizeCommandSpec(cmd.CommandPath())
	if !commandBlockedByPolicy(commandPath, policy.BlockedCommands) {
		return nil
	}

	reason := ""
	if policy.ImmutableReason != "" {
		reason = "Detected immutable system: " + policy.ImmutableReason + "\n"
	}

	return fmt.Errorf("%s%s\nCommand: dms %s\nPolicy files:\n  %s\n  %s", reason, policy.Message, commandPath, clipolicy.PackagedPath, clipolicy.AdminPath)
}

// preRunPrivileged combines the immutable-system check with a privesc tool
// selection prompt (shown only when multiple tools are available and the
// $DMS_PRIVESC env var isn't set).
func preRunPrivileged(cmd *cobra.Command, args []string) error {
	if err := requireMutableSystemCommand(cmd, args); err != nil {
		return err
	}
	if _, err := privesc.PromptCLI(os.Stdout, os.Stdin); err != nil {
		return err
	}
	return nil
}
