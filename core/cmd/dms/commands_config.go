package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/luaconfig"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"github.com/spf13/cobra"
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Configuration utilities",
}

var resolveIncludeCmd = &cobra.Command{
	Use:   "resolve-include <compositor> <filename>",
	Short: "Check if a file is included in compositor config",
	Long:  "Recursively check if a file is included/sourced in compositor configuration. Returns JSON with exists and included status.",
	Args:  cobra.ExactArgs(2),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		switch len(args) {
		case 0:
			return []string{"hyprland", "niri", "mangowc"}, cobra.ShellCompDirectiveNoFileComp
		case 1:
			return []string{
				"binds.lua",
				"binds-user.lua",
				"colors.lua",
				"layout.lua",
				"outputs.lua",
				"cursor.lua",
				"input.lua",
				"windowrules.lua",
				"cursor.kdl",
				"layout.kdl",
				"outputs.kdl",
				"binds.kdl",
				"input.kdl",
				"cursor.conf",
				"input.conf",
				"layout.conf",
				"outputs.conf",
				"binds.conf",
			}, cobra.ShellCompDirectiveNoFileComp
		}
		return nil, cobra.ShellCompDirectiveNoFileComp
	},
	Run: runResolveInclude,
}

var mangoMonitorRulesCmd = &cobra.Command{
	Use:    "mango-monitor-rules",
	Short:  "Print the monitor rules of the Mango main config as monitor_rule= lines",
	Hidden: true,
	Args:   cobra.NoArgs,
	Run: func(cmd *cobra.Command, args []string) {
		for _, line := range mangoMonitorRules(mangoconf.Dir()) {
			fmt.Println(line)
		}
	},
}

func init() {
	configCmd.AddCommand(resolveIncludeCmd, mangoMonitorRulesCmd)
}

// mangoMonitorRules lets the shell carry fields it does not model when it rewrites dms/outputs.conf.
func mangoMonitorRules(dir string) []string {
	var out []string
	_ = mangoconf.Walk(dir, mangoconf.MainConfig(dir), mangoconf.Vars{}, func(_ string, e mangoconf.Entry) {
		if e.Key == "monitor_rule" && !strings.Contains(e.Value, "\n") {
			out = append(out, "monitor_rule="+e.Value)
		}
	})
	return out
}

type IncludeResult struct {
	Exists   bool `json:"exists"`
	Included bool `json:"included"`
}

func runResolveInclude(cmd *cobra.Command, args []string) {
	compositor := strings.ToLower(args[0])
	filename := args[1]

	var result IncludeResult
	var err error

	switch compositor {
	case "hyprland":
		result, err = checkHyprlandInclude(filename)
	case "niri":
		result, err = checkNiriInclude(filename)
	case "mangowc", "mango":
		result, err = checkMangoWCInclude(filename)
	default:
		log.Fatalf("Unknown compositor: %s", compositor)
	}

	if err != nil {
		log.Fatalf("Error checking include: %v", err)
	}

	output, _ := json.Marshal(result)
	fmt.Fprintln(os.Stdout, string(output))
}

func checkHyprlandInclude(filename string) (IncludeResult, error) {
	configDir := filepath.Join(utils.XDGConfigHome(), "hypr")

	targetPath := filepath.Join(configDir, "dms", filename)
	result := IncludeResult{}

	if _, err := os.Stat(targetPath); err == nil {
		result.Exists = true
	}

	targetAbs, err := filepath.Abs(targetPath)
	if err != nil {
		return result, err
	}

	mainLua := filepath.Join(configDir, "hyprland.lua")
	if _, err := os.Stat(mainLua); err != nil {
		return result, nil
	}
	result.Included = luaconfig.RequiresTarget(mainLua, targetAbs, make(map[string]bool))
	return result, nil
}

func checkNiriInclude(filename string) (IncludeResult, error) {
	configDir := filepath.Join(utils.XDGConfigHome(), "niri")

	targetPath := filepath.Join(configDir, "dms", filename)
	result := IncludeResult{}

	if _, err := os.Stat(targetPath); err == nil {
		result.Exists = true
	}

	mainConfig := filepath.Join(configDir, "config.kdl")
	if _, err := os.Stat(mainConfig); os.IsNotExist(err) {
		return result, nil
	}

	targetAbs, err := filepath.Abs(targetPath)
	if err != nil {
		return result, err
	}

	processed := make(map[string]bool)
	result.Included = niriFindInclude(mainConfig, targetAbs, processed)
	return result, nil
}

func niriFindInclude(filePath, target string, processed map[string]bool) bool {
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return false
	}

	if processed[absPath] {
		return false
	}
	processed[absPath] = true

	data, err := os.ReadFile(absPath)
	if err != nil {
		return false
	}

	baseDir := filepath.Dir(absPath)
	content := string(data)

	for line := range strings.SplitSeq(content, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "//") || trimmed == "" {
			continue
		}

		if !strings.HasPrefix(trimmed, "include") {
			continue
		}

		startQuote := strings.Index(trimmed, "\"")
		if startQuote == -1 {
			continue
		}
		endQuote := strings.LastIndex(trimmed, "\"")
		if endQuote <= startQuote {
			continue
		}

		fullPath, err := resolveSourcePath(baseDir, trimmed[startQuote+1:endQuote])
		if err != nil {
			continue
		}

		if fullPath == target || niriFindInclude(fullPath, target, processed) {
			return true
		}
	}

	return false
}

func checkMangoWCInclude(filename string) (IncludeResult, error) {
	configDir := mangoconf.Dir()
	targetPath := filepath.Join(configDir, "dms", filename)
	var result IncludeResult
	if _, err := os.Stat(targetPath); err == nil {
		result.Exists = true
	}
	_ = mangoconf.Walk(configDir, mangoconf.MainConfig(configDir), mangoconf.Vars{}, func(_ string, e mangoconf.Entry) {
		result.Included = result.Included || (e.IsSource() && e.Value == targetPath)
	})
	return result, nil
}

func resolveSourcePath(baseDir, raw string) (string, error) {
	expanded, err := utils.ExpandPath(raw)
	if err != nil {
		return "", err
	}
	if !filepath.IsAbs(expanded) {
		expanded = filepath.Join(baseDir, expanded)
	}
	return filepath.Abs(expanded)
}
