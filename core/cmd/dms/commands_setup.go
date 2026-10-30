package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"github.com/spf13/cobra"
)

var setupCmd = &cobra.Command{
	Use:               "setup",
	Short:             "Deploy DMS configurations",
	Long:              "Deploy compositor and terminal configurations with interactive prompts",
	PersistentPreRunE: preRunPrivileged,
	Run: func(cmd *cobra.Command, args []string) {
		if err := runSetup(); err != nil {
			log.Fatalf("Error during setup: %v", err)
		}
	},
}

var setupBindsCmd = &cobra.Command{
	Use:   "binds",
	Short: "Deploy default keybinds config",
	Run: func(cmd *cobra.Command, args []string) {
		if err := runSetupDmsConfig("binds"); err != nil {
			log.Fatalf("Error: %v", err)
		}
	},
}

var setupLayoutCmd = &cobra.Command{
	Use:   "layout",
	Short: "Deploy default layout config",
	Run: func(cmd *cobra.Command, args []string) {
		if err := runSetupDmsConfig("layout"); err != nil {
			log.Fatalf("Error: %v", err)
		}
	},
}

var setupColorsCmd = &cobra.Command{
	Use:   "colors",
	Short: "Deploy default colors config",
	Run: func(cmd *cobra.Command, args []string) {
		if err := runSetupDmsConfig("colors"); err != nil {
			log.Fatalf("Error: %v", err)
		}
	},
}

var setupAlttabCmd = &cobra.Command{
	Use:   "alttab",
	Short: "Deploy default alt-tab config (niri only)",
	Run: func(cmd *cobra.Command, args []string) {
		if err := runSetupDmsConfig("alttab"); err != nil {
			log.Fatalf("Error: %v", err)
		}
	},
}

var setupOutputsCmd = &cobra.Command{
	Use:   "outputs",
	Short: "Deploy default outputs config",
	Run: func(cmd *cobra.Command, args []string) {
		if err := runSetupDmsConfig("outputs"); err != nil {
			log.Fatalf("Error: %v", err)
		}
	},
}

var setupCursorCmd = &cobra.Command{
	Use:   "cursor",
	Short: "Deploy default cursor config",
	Run: func(cmd *cobra.Command, args []string) {
		if err := runSetupDmsConfig("cursor"); err != nil {
			log.Fatalf("Error: %v", err)
		}
	},
}

var setupWindowrulesCmd = &cobra.Command{
	Use:   "windowrules",
	Short: "Deploy default window rules config",
	Run: func(cmd *cobra.Command, args []string) {
		if err := runSetupDmsConfig("windowrules"); err != nil {
			log.Fatalf("Error: %v", err)
		}
	},
}

type dmsConfigSpec struct {
	niriFile     string
	hyprFile     string
	mangoFile    string
	niriContent  func(terminal string) string
	hyprContent  func(terminal string) string
	mangoContent func(terminal string) string
}

var dmsConfigSpecs = map[string]dmsConfigSpec{
	"binds": {
		niriFile:  "binds.kdl",
		hyprFile:  "binds.lua",
		mangoFile: "binds.conf",
		niriContent: func(t string) string {
			return strings.ReplaceAll(config.NiriBindsConfig, "{{TERMINAL_COMMAND}}", t)
		},
		hyprContent: func(t string) string {
			return strings.ReplaceAll(config.DMSBindsLuaConfig, "{{TERMINAL_COMMAND}}", t)
		},
		mangoContent: func(t string) string {
			return strings.ReplaceAll(config.MangoBindsConfig, "{{TERMINAL_COMMAND}}", t)
		},
	},
	"layout": {
		niriFile:     "layout.kdl",
		hyprFile:     "layout.lua",
		mangoFile:    "layout.conf",
		niriContent:  func(_ string) string { return config.NiriLayoutConfig },
		hyprContent:  func(_ string) string { return config.DMSLayoutLuaConfig },
		mangoContent: func(_ string) string { return config.MangoLayoutConfig },
	},
	"colors": {
		niriFile:     "colors.kdl",
		hyprFile:     "colors.lua",
		mangoFile:    "colors.conf",
		niriContent:  func(_ string) string { return config.NiriColorsConfig },
		hyprContent:  func(_ string) string { return config.DMSColorsLuaConfig },
		mangoContent: func(_ string) string { return config.MangoColorsConfig },
	},
	"alttab": {
		niriFile:    "alttab.kdl",
		niriContent: func(_ string) string { return config.NiriAlttabConfig },
	},
	"input": {
		niriFile:     "input.kdl",
		hyprFile:     "input.lua",
		mangoFile:    "input.conf",
		niriContent:  func(_ string) string { return config.NiriInputConfig },
		hyprContent:  func(_ string) string { return config.DMSInputLuaConfig },
		mangoContent: func(_ string) string { return "" },
	},
	"outputs": {
		niriFile:     "outputs.kdl",
		hyprFile:     "outputs.lua",
		mangoFile:    "outputs.conf",
		niriContent:  func(_ string) string { return "" },
		hyprContent:  func(_ string) string { return config.DMSOutputsLuaConfig },
		mangoContent: func(_ string) string { return "" },
	},
	"cursor": {
		niriFile:     "cursor.kdl",
		hyprFile:     "cursor.lua",
		mangoFile:    "cursor.conf",
		niriContent:  func(_ string) string { return "" },
		hyprContent:  func(_ string) string { return config.DMSCursorLuaConfig },
		mangoContent: func(_ string) string { return "" },
	},
	"windowrules": {
		niriFile:     "windowrules.kdl",
		hyprFile:     "windowrules.lua",
		mangoFile:    "windowrules.conf",
		niriContent:  func(_ string) string { return "" },
		hyprContent:  func(_ string) string { return config.DMSWindowRulesLuaConfig },
		mangoContent: func(_ string) string { return "" },
	},
}

var knownTerminals = []string{"ghostty", "foot", "kitty", "alacritty"}

func terminalFromEnv() string {
	return strings.TrimSpace(os.Getenv("TERMINAL"))
}

func installedTerminals() []string {
	var found []string
	for _, t := range knownTerminals {
		if utils.CommandExists(t) {
			found = append(found, t)
		}
	}
	return found
}

func installedHyprlandVersion() string {
	_, ver := getVersionFromCommand("Hyprland", "--version", distros.ParseHyprlandVersion)
	return ver
}

func defaultTerminalCommand() string {
	if env := terminalFromEnv(); env != "" {
		return env
	}
	if found := installedTerminals(); len(found) > 0 {
		return found[0]
	}
	return "ghostty"
}

func detectTerminal() (string, error) {
	if env := terminalFromEnv(); env != "" {
		return env, nil
	}

	found := installedTerminals()
	switch len(found) {
	case 0:
		return "ghostty", nil
	case 1:
		return found[0], nil
	}

	fmt.Println("Multiple terminals detected:")
	for i, t := range found {
		fmt.Printf("%d) %s\n", i+1, t)
	}
	fmt.Printf("\nChoice (1-%d): ", len(found))

	var response string
	fmt.Scanln(&response)
	response = strings.TrimSpace(response)

	choice := 0
	fmt.Sscanf(response, "%d", &choice)
	if choice < 1 || choice > len(found) {
		return "", fmt.Errorf("invalid choice")
	}
	return found[choice-1], nil
}

func detectCompositorForSetup() (string, error) {
	var compositors []string
	for _, candidate := range []string{"niri", "Hyprland", "mango"} {
		if utils.CommandExists(candidate) {
			compositors = append(compositors, candidate)
		}
	}

	switch len(compositors) {
	case 0:
		return "", fmt.Errorf("no supported compositors found (niri, Hyprland, or mango required)")
	case 1:
		return strings.ToLower(compositors[0]), nil
	}

	fmt.Println("Multiple compositors detected:")
	for i, compositor := range compositors {
		fmt.Printf("%d) %s\n", i+1, compositor)
	}
	fmt.Printf("\nChoice (1-%d): ", len(compositors))

	var response string
	fmt.Scanln(&response)
	choice := 0
	fmt.Sscanf(strings.TrimSpace(response), "%d", &choice)
	if choice < 1 || choice > len(compositors) {
		return "", fmt.Errorf("invalid choice")
	}
	return strings.ToLower(compositors[choice-1]), nil
}

func runSetupDmsConfig(name string) error {
	spec, ok := dmsConfigSpecs[name]
	if !ok {
		return fmt.Errorf("unknown config: %s", name)
	}

	compositor, err := detectCompositorForSetup()
	if err != nil {
		return err
	}

	var filename string
	var contentFn func(string) string
	switch compositor {
	case "niri":
		filename = spec.niriFile
		contentFn = spec.niriContent
	case "hyprland":
		filename = spec.hyprFile
		contentFn = spec.hyprContent
	case "mango", "mangowc":
		filename = spec.mangoFile
		contentFn = spec.mangoContent
	default:
		return fmt.Errorf("unsupported compositor: %s", compositor)
	}

	if filename == "" {
		return fmt.Errorf("%s is not supported for %s", name, compositor)
	}

	var dmsDir string
	switch compositor {
	case "niri":
		dmsDir = filepath.Join(utils.XDGConfigHome(), "niri", "dms")
	case "hyprland":
		dmsDir = filepath.Join(utils.XDGConfigHome(), "hypr", "dms")
	case "mango", "mangowc":
		dmsDir = filepath.Join(mangoconf.Dir(), "dms")
	}

	if err := os.MkdirAll(dmsDir, 0o755); err != nil {
		return fmt.Errorf("failed to create dms directory: %w", err)
	}

	path := filepath.Join(dmsDir, filename)
	if info, err := os.Stat(path); err == nil && info.Size() > 0 {
		return fmt.Errorf("%s already exists and is not empty: %s", name, path)
	}

	terminal := "ghostty"
	if contentFn != nil && name == "binds" {
		terminal, err = detectTerminal()
		if err != nil {
			return err
		}
	}

	content := contentFn(terminal)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		return fmt.Errorf("failed to write %s: %w", filename, err)
	}

	fmt.Printf("Deployed %s to %s\n", name, path)
	return nil
}

func runSetup() error {
	fmt.Println("=== DMS Configuration Setup ===")

	ensureInputGroup()

	wm, wmSelected := promptCompositor()
	terminal, terminalSelected := promptTerminal()
	useSystemd := true
	if wmSelected {
		if wm == deps.WindowManagerMango && !mangoconf.SessionTargetInstalled() {
			useSystemd = false
			fmt.Println("\nThis Mango has no mango-session.target (added in 0.17.1); DMS will start from the Mango config.")
		} else if isVoidSetup() {
			useSystemd = false
			fmt.Println("\nVoid Linux detected; deploying non-systemd session config.")
		} else {
			useSystemd = promptSystemd()
		}
	}

	if !wmSelected && !terminalSelected {
		fmt.Println("No configurations selected. Exiting.")
		return nil
	}

	replaceBinds := false
	if wmSelected {
		if path, ok := config.ExistingBinds(wm); ok {
			replaceBinds = promptBinds(path)
		}
	}

	if wmSelected || terminalSelected {
		willBackup := checkExistingConfigs(wm, wmSelected, terminal, terminalSelected)
		if willBackup {
			fmt.Println("\n⚠ Existing configurations will be backed up with timestamps.")
		}

		fmt.Print("\nProceed with deployment? (y/N): ")
		var response string
		fmt.Scanln(&response)
		response = strings.ToLower(strings.TrimSpace(response))

		if response != "y" && response != "yes" {
			fmt.Println("Setup cancelled.")
			return nil
		}
	}

	fmt.Println("\nDeploying configurations...")
	logChan := make(chan string, 100)
	deployer := config.NewConfigDeployer(logChan)
	deployer.SetReplaceBinds(replaceBinds)

	go func() {
		for msg := range logChan {
			fmt.Println("  " + msg)
		}
	}()

	var results []config.DeploymentResult
	var err error

	if wmSelected {
		terminalCommand := defaultTerminalCommand()
		if terminalSelected {
			terminalCommand = terminal.Command()
		}
		if wm == deps.WindowManagerHyprland {
			deployer.SetHyprlandVersion(installedHyprlandVersion())
		}
		var result config.DeploymentResult
		result, err = deployer.DeployCompositor(wm, terminalCommand, useSystemd)
		results = append(results, result)
	}
	if err == nil && terminalSelected {
		var terminalResults []config.DeploymentResult
		terminalResults, err = deployer.DeployTerminal(terminal)
		results = append(results, terminalResults...)
	}

	close(logChan)

	if err != nil {
		return fmt.Errorf("deployment failed: %w", err)
	}

	fmt.Println("\n=== Deployment Complete ===")
	for _, result := range results {
		if result.Deployed {
			fmt.Printf("✓ %s: %s\n", result.ConfigType, result.Path)
			if result.BackupPath != "" {
				fmt.Printf("  Backup: %s\n", result.BackupPath)
			}
		}
	}

	return nil
}

func isVoidSetup() bool {
	osInfo, err := distros.GetOSInfo()
	if err != nil {
		return false
	}
	config, exists := distros.Registry[osInfo.Distribution.ID]
	return exists && config.Family == distros.FamilyVoid
}

// Add user to the input group for the evdev manager for inut state tracking.
// Caps Lock OSD and the Caps Lock bar indicator.
func ensureInputGroup() {
	if !utils.HasGroup("input") {
		return
	}
	currentUser := os.Getenv("USER")
	if currentUser == "" {
		currentUser = os.Getenv("LOGNAME")
	}
	if currentUser == "" {
		return
	}
	out, err := execGroups(currentUser)
	if err == nil && strings.Contains(out, "input") {
		fmt.Printf("✓ %s is already in the input group (Caps Lock OSD enabled)\n", currentUser)
		return
	}
	fmt.Println("Adding user to input group for Caps Lock OSD support...")
	if err := privesc.Run(context.Background(), "", "usermod", "-aG", "input", currentUser); err != nil {
		fmt.Printf("⚠ Could not add %s to input group (Caps Lock OSD will be unavailable): %v\n", currentUser, err)
	} else {
		fmt.Printf("✓ Added %s to input group (logout/login required to take effect)\n", currentUser)
	}
}

func execGroups(user string) (string, error) {
	out, err := exec.Command("groups", user).Output()
	return string(out), err
}

func promptCompositor() (deps.WindowManager, bool) {
	fmt.Println("Select compositor:")
	fmt.Println("1) Niri")
	fmt.Println("2) Hyprland")
	fmt.Println("3) Mango")
	fmt.Println("4) None")

	var response string
	fmt.Print("\nChoice (1-4): ")
	fmt.Scanln(&response)
	response = strings.TrimSpace(response)

	switch response {
	case "1":
		return deps.WindowManagerNiri, true
	case "2":
		return deps.WindowManagerHyprland, true
	case "3":
		return deps.WindowManagerMango, true
	default:
		return deps.WindowManagerNiri, false
	}
}

func promptTerminal() (deps.Terminal, bool) {
	fmt.Println("\nSelect terminal:")
	fmt.Println("1) Ghostty")
	fmt.Println("2) Kitty")
	fmt.Println("3) Alacritty")
	fmt.Println("4) None")

	var response string
	fmt.Print("\nChoice (1-4): ")
	fmt.Scanln(&response)
	response = strings.TrimSpace(response)

	switch response {
	case "1":
		return deps.TerminalGhostty, true
	case "2":
		return deps.TerminalKitty, true
	case "3":
		return deps.TerminalAlacritty, true
	default:
		return deps.TerminalGhostty, false
	}
}

func promptBinds(path string) bool {
	fmt.Printf("\nFound your keybinds in %s.\n", path)
	fmt.Println("  1) Keep my binds as they are")
	fmt.Println("  2) Start from the DMS stock binds")
	fmt.Println("Either way a timestamped backup is kept.")
	fmt.Print("Choice (1-2) [1]: ")
	var response string
	fmt.Scanln(&response)
	return strings.TrimSpace(response) == "2"
}

func promptSystemd() bool {
	fmt.Println("\nUse systemd for session management?")
	fmt.Println("1) Yes (recommended for most distros)")
	fmt.Println("2) No (standalone, no systemd integration)")

	var response string
	fmt.Print("\nChoice (1-2): ")
	fmt.Scanln(&response)
	response = strings.TrimSpace(response)

	return response != "2"
}

func checkExistingConfigs(wm deps.WindowManager, wmSelected bool, terminal deps.Terminal, terminalSelected bool) bool {
	if wmSelected && firstExistingPath(compositorPrimaryPaths(wm)) != "" {
		return true
	}
	return terminalSelected && firstExistingPath([]string{terminalPrimaryPath(terminal)}) != ""
}

func compositorPrimaryPaths(wm deps.WindowManager) []string {
	homeDir := os.Getenv("HOME")
	switch wm {
	case deps.WindowManagerNiri:
		return []string{filepath.Join(homeDir, ".config", "niri", "config.kdl")}
	case deps.WindowManagerHyprland:
		return []string{filepath.Join(config.HyprlandConfigDir(), "hyprland.lua")}
	case deps.WindowManagerMango:
		return []string{
			filepath.Join(homeDir, ".config", "mango", "config.conf"),
			filepath.Join(homeDir, ".config", "mango", "mango.conf"),
		}
	default:
		return nil
	}
}

func terminalPrimaryPath(terminal deps.Terminal) string {
	homeDir := os.Getenv("HOME")
	switch terminal {
	case deps.TerminalGhostty:
		return filepath.Join(homeDir, ".config", "ghostty", "config")
	case deps.TerminalKitty:
		return filepath.Join(homeDir, ".config", "kitty", "kitty.conf")
	case deps.TerminalAlacritty:
		return filepath.Join(homeDir, ".config", "alacritty", "alacritty.toml")
	default:
		return ""
	}
}

func firstExistingPath(paths []string) string {
	for _, path := range paths {
		if path == "" {
			continue
		}
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}
	return ""
}
