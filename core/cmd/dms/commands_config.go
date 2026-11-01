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

func init() {
	configCmd.AddCommand(resolveIncludeCmd)
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
	result := IncludeResult{}

	if _, err := os.Stat(targetPath); err == nil {
		result.Exists = true
	}

	mainConfig := filepath.Join(configDir, "config.conf")
	if _, err := os.Stat(mainConfig); os.IsNotExist(err) {
		mainConfig = filepath.Join(configDir, "mango.conf")
	}
	if _, err := os.Stat(mainConfig); os.IsNotExist(err) {
		return result, nil
	}

	targetAbs, err := filepath.Abs(targetPath)
	if err != nil {
		return result, err
	}

	processed := make(map[string]bool)
	result.Included = mangowcFindInclude(mainConfig, targetAbs, processed)
	return result, nil
}

func mangowcFindInclude(filePath, target string, processed map[string]bool) bool {
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
	lines := strings.SplitSeq(string(data), "\n")

	for line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") || trimmed == "" {
			continue
		}

		if !strings.HasPrefix(trimmed, "source") {
			continue
		}

		parts := strings.SplitN(trimmed, "=", 2)
		if len(parts) < 2 {
			continue
		}

		fullPath, err := resolveSourcePath(baseDir, strings.TrimSpace(parts[1]))
		if err != nil {
			continue
		}

		if fullPath == target || mangowcFindInclude(fullPath, target, processed) {
			return true
		}
	}

	return false
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
