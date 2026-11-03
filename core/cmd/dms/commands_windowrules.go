package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"github.com/duxlabs-dev/dux-shell/core/internal/windowrules"
	"github.com/duxlabs-dev/dux-shell/core/internal/windowrules/providers"
	"github.com/spf13/cobra"
)

var windowrulesCmd = &cobra.Command{
	Use:   "windowrules",
	Short: "Manage window rules",
}

var windowrulesListCmd = &cobra.Command{
	Use:   "list [compositor]",
	Short: "List all window rules",
	Long:  "List all window rules from compositor config file. Returns JSON with rules and DMS status.",
	Args:  cobra.MaximumNArgs(1),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) == 0 {
			return []string{"hyprland", "niri", "mango"}, cobra.ShellCompDirectiveNoFileComp
		}
		return nil, cobra.ShellCompDirectiveNoFileComp
	},
	Run: runWindowrulesList,
}

var windowrulesAddCmd = &cobra.Command{
	Use:   "add <compositor> '<json>'",
	Short: "Add a window rule to DMS file",
	Long:  "Add a new window rule to the DMS-managed rules file.",
	Args:  cobra.ExactArgs(2),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) == 0 {
			return []string{"hyprland", "niri", "mango"}, cobra.ShellCompDirectiveNoFileComp
		}
		return nil, cobra.ShellCompDirectiveNoFileComp
	},
	Run: runWindowrulesAdd,
}

var windowrulesUpdateCmd = &cobra.Command{
	Use:   "update <compositor> <id> '<json>'",
	Short: "Update a window rule in DMS file",
	Long:  "Update an existing window rule in the DMS-managed rules file.",
	Args:  cobra.ExactArgs(3),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) == 0 {
			return []string{"hyprland", "niri", "mango"}, cobra.ShellCompDirectiveNoFileComp
		}
		return nil, cobra.ShellCompDirectiveNoFileComp
	},
	Run: runWindowrulesUpdate,
}

var windowrulesRemoveCmd = &cobra.Command{
	Use:   "remove <compositor> <id>",
	Short: "Remove a window rule from DMS file",
	Long:  "Remove a window rule from the DMS-managed rules file.",
	Args:  cobra.ExactArgs(2),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) == 0 {
			return []string{"hyprland", "niri", "mango"}, cobra.ShellCompDirectiveNoFileComp
		}
		return nil, cobra.ShellCompDirectiveNoFileComp
	},
	Run: runWindowrulesRemove,
}

var windowrulesReorderCmd = &cobra.Command{
	Use:   "reorder <compositor> '<json-array-of-ids>'",
	Short: "Reorder window rules in DMS file",
	Long:  "Reorder window rules by providing a JSON array of rule IDs in the desired order.",
	Args:  cobra.ExactArgs(2),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) == 0 {
			return []string{"hyprland", "niri", "mango"}, cobra.ShellCompDirectiveNoFileComp
		}
		return nil, cobra.ShellCompDirectiveNoFileComp
	},
	Run: runWindowrulesReorder,
}

func init() {
	configCmd.AddCommand(windowrulesCmd)
	windowrulesCmd.AddCommand(windowrulesListCmd)
	windowrulesCmd.AddCommand(windowrulesAddCmd)
	windowrulesCmd.AddCommand(windowrulesUpdateCmd)
	windowrulesCmd.AddCommand(windowrulesRemoveCmd)
	windowrulesCmd.AddCommand(windowrulesReorderCmd)
}

type WindowRulesListResult struct {
	Rules     []windowrules.WindowRule    `json:"rules"`
	DMSStatus *windowrules.DMSRulesStatus `json:"dmsStatus,omitempty"`
}

type WindowRuleWriteResult struct {
	Success bool   `json:"success"`
	ID      string `json:"id,omitempty"`
	Path    string `json:"path,omitempty"`
	Error   string `json:"error,omitempty"`
}

func getCompositor(args []string) string {
	if len(args) > 0 {
		return strings.ToLower(args[0])
	}
	if os.Getenv("NIRI_SOCKET") != "" {
		return "niri"
	}
	if os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "" {
		return "hyprland"
	}
	if os.Getenv("MANGO_INSTANCE_SIGNATURE") != "" {
		return "mango"
	}
	return ""
}

func writeRuleError(errMsg string) {
	result := WindowRuleWriteResult{Success: false, Error: errMsg}
	output, _ := json.Marshal(result)
	fmt.Fprintln(os.Stdout, string(output))
	os.Exit(1)
}

func writeRuleSuccess(id, path string) {
	result := WindowRuleWriteResult{Success: true, ID: id, Path: path}
	output, _ := json.Marshal(result)
	fmt.Fprintln(os.Stdout, string(output))
}

func runWindowrulesList(cmd *cobra.Command, args []string) {
	compositor := getCompositor(args)
	if compositor == "" {
		log.Fatalf("Could not detect compositor. Please specify: hyprland, niri, or mango")
	}

	var result WindowRulesListResult

	switch compositor {
	case "niri":
		configDir := filepath.Join(utils.XDGConfigHome(), "niri")

		parseResult, err := providers.ParseNiriWindowRules(configDir)
		if err != nil {
			log.Fatalf("Failed to parse niri window rules: %v", err)
		}

		allRules := providers.ConvertNiriRulesToWindowRules(parseResult.Rules)

		provider := providers.NewNiriWritableProvider(configDir)
		dmsRulesPath := provider.GetOverridePath()
		dmsRules, _ := provider.LoadDMSRules()

		dmsRuleMap := make(map[int]windowrules.WindowRule)
		for i, dr := range dmsRules {
			dmsRuleMap[i] = dr
		}

		dmsIdx := 0
		for i, r := range allRules {
			if r.Source == dmsRulesPath {
				if dmr, ok := dmsRuleMap[dmsIdx]; ok {
					allRules[i].ID = dmr.ID
					allRules[i].Name = dmr.Name
				}
				dmsIdx++
			}
		}

		result.Rules = allRules
		result.DMSStatus = parseResult.DMSStatus

	case "hyprland":
		configDir := filepath.Join(utils.XDGConfigHome(), "hypr")

		parseResult, err := providers.ParseHyprlandWindowRules(configDir)
		if err != nil {
			log.Fatalf("Failed to parse hyprland window rules: %v", err)
		}

		allRules := providers.ConvertHyprlandRulesToWindowRules(parseResult.Rules)

		provider := providers.NewHyprlandWritableProvider(configDir)
		dmsRulesPath := provider.GetOverridePath()
		dmsRules, _ := provider.LoadDMSRules()

		dmsRuleMap := make(map[int]windowrules.WindowRule)
		for i, dr := range dmsRules {
			dmsRuleMap[i] = dr
		}

		dmsIdx := 0
		for i, r := range allRules {
			if r.Source == dmsRulesPath {
				if dmr, ok := dmsRuleMap[dmsIdx]; ok {
					allRules[i].ID = dmr.ID
					allRules[i].Name = dmr.Name
				}
				dmsIdx++
			}
		}

		result.Rules = allRules
		result.DMSStatus = parseResult.DMSStatus

	case "mango", "mangowc":
		configDir := mangoconf.Dir()

		parseResult, err := providers.ParseMangoWindowRules(configDir)
		if err != nil {
			log.Fatalf("Failed to parse mango window rules: %v", err)
		}

		allRules := providers.ConvertMangoRulesToWindowRules(parseResult.Rules)

		provider := providers.NewMangoWritableProvider(configDir)
		dmsRules, _ := provider.LoadDMSRules()

		dmsRuleMap := make(map[int]windowrules.WindowRule)
		for i, dr := range dmsRules {
			dmsRuleMap[i] = dr
		}

		dmsIdx := 0
		for i, r := range allRules {
			if r.Source == "dms/windowrules.conf" {
				if dmr, ok := dmsRuleMap[dmsIdx]; ok {
					allRules[i].ID = dmr.ID
					allRules[i].Name = dmr.Name
				}
				dmsIdx++
			}
		}

		result.Rules = allRules
		result.DMSStatus = parseResult.DMSStatus

	default:
		log.Fatalf("Unknown compositor: %s", compositor)
	}

	output, _ := json.Marshal(result)
	fmt.Fprintln(os.Stdout, string(output))
}

func runWindowrulesAdd(cmd *cobra.Command, args []string) {
	compositor := strings.ToLower(args[0])
	ruleJSON := args[1]

	var rule windowrules.WindowRule
	if err := json.Unmarshal([]byte(ruleJSON), &rule); err != nil {
		writeRuleError(fmt.Sprintf("Invalid JSON: %v", err))
	}

	if rule.ID == "" {
		rule.ID = generateRuleID()
	}
	rule.Enabled = true

	provider := getWindowRulesProvider(compositor)
	if provider == nil {
		writeRuleError(fmt.Sprintf("Unknown compositor: %s", compositor))
	}

	if err := provider.SetRule(rule); err != nil {
		writeRuleError(err.Error())
	}

	writeRuleSuccess(rule.ID, provider.GetOverridePath())
}

func runWindowrulesUpdate(cmd *cobra.Command, args []string) {
	compositor := strings.ToLower(args[0])
	ruleID := args[1]
	ruleJSON := args[2]

	var rule windowrules.WindowRule
	if err := json.Unmarshal([]byte(ruleJSON), &rule); err != nil {
		writeRuleError(fmt.Sprintf("Invalid JSON: %v", err))
	}

	rule.ID = ruleID

	provider := getWindowRulesProvider(compositor)
	if provider == nil {
		writeRuleError(fmt.Sprintf("Unknown compositor: %s", compositor))
	}

	if err := provider.SetRule(rule); err != nil {
		writeRuleError(err.Error())
	}

	writeRuleSuccess(rule.ID, provider.GetOverridePath())
}

func runWindowrulesRemove(cmd *cobra.Command, args []string) {
	compositor := strings.ToLower(args[0])
	ruleID := args[1]

	provider := getWindowRulesProvider(compositor)
	if provider == nil {
		writeRuleError(fmt.Sprintf("Unknown compositor: %s", compositor))
	}

	if err := provider.RemoveRule(ruleID); err != nil {
		writeRuleError(err.Error())
	}

	writeRuleSuccess(ruleID, provider.GetOverridePath())
}

func runWindowrulesReorder(cmd *cobra.Command, args []string) {
	compositor := strings.ToLower(args[0])
	idsJSON := args[1]

	var ids []string
	if err := json.Unmarshal([]byte(idsJSON), &ids); err != nil {
		writeRuleError(fmt.Sprintf("Invalid JSON array: %v", err))
	}

	provider := getWindowRulesProvider(compositor)
	if provider == nil {
		writeRuleError(fmt.Sprintf("Unknown compositor: %s", compositor))
	}

	if err := provider.ReorderRules(ids); err != nil {
		writeRuleError(err.Error())
	}

	writeRuleSuccess("", provider.GetOverridePath())
}

func getWindowRulesProvider(compositor string) windowrules.WritableProvider {
	switch compositor {
	case "niri":
		configDir := filepath.Join(utils.XDGConfigHome(), "niri")
		return providers.NewNiriWritableProvider(configDir)
	case "hyprland":
		configDir := filepath.Join(utils.XDGConfigHome(), "hypr")
		return providers.NewHyprlandWritableProvider(configDir)
	case "mango", "mangowc":
		configDir := mangoconf.Dir()
		return providers.NewMangoWritableProvider(configDir)
	default:
		return nil
	}
}

func generateRuleID() string {
	return fmt.Sprintf("wr_%d", time.Now().UnixNano())
}
