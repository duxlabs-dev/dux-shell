package main

import (
	"fmt"

	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/spf13/cobra"
)

var setupHeadlessCmd = &cobra.Command{
	Use:               "headless",
	Short:             "Deploy DMS configurations without prompts",
	Long:              "Deploy compositor and terminal configurations non-interactively, for installers and scripts",
	PersistentPreRunE: requireMutableSystemCommand,
	RunE: func(cmd *cobra.Command, args []string) error {
		compositor, _ := cmd.Flags().GetString("compositor")
		terminal, _ := cmd.Flags().GetString("terminal")
		noSystemd, _ := cmd.Flags().GetBool("no-systemd")
		force, _ := cmd.Flags().GetBool("force")
		skipExisting, _ := cmd.Flags().GetBool("skip-existing")
		stockBinds, _ := cmd.Flags().GetBool("stock-binds")
		cmd.SilenceUsage = true
		return runSetupHeadless(compositor, terminal, noSystemd, force, skipExisting, stockBinds)
	},
}

func init() {
	setupHeadlessCmd.Flags().String("compositor", "", "Compositor to configure: niri, hyprland, or mango")
	setupHeadlessCmd.Flags().String("terminal", "", "Also deploy a terminal config: ghostty, kitty, or alacritty (binds otherwise use $TERMINAL or the first installed terminal)")
	setupHeadlessCmd.Flags().Bool("no-systemd", false, "Deploy session config without systemd integration")
	setupHeadlessCmd.Flags().Bool("force", false, "Overwrite existing configs (timestamped backups are created)")
	setupHeadlessCmd.Flags().Bool("skip-existing", false, "Warn and skip instead of failing when a config already exists")
	setupHeadlessCmd.Flags().Bool("stock-binds", false, "Replace existing keybinds with the DMS stock set (a backup is kept)")
	_ = setupHeadlessCmd.MarkFlagRequired("compositor")
	setupHeadlessCmd.MarkFlagsMutuallyExclusive("force", "skip-existing")
}

func runSetupHeadless(compositor, terminal string, noSystemd, force, skipExisting, stockBinds bool) error {
	wm, err := parseHeadlessCompositor(compositor)
	if err != nil {
		return err
	}
	term, termSelected, err := parseHeadlessTerminal(terminal)
	if err != nil {
		return err
	}

	deployCompositor := true
	deployTerminal := termSelected

	if !force {
		if existing := firstExistingPath(compositorPrimaryPaths(wm)); existing != "" {
			if !skipExisting {
				return fmt.Errorf("%s config already exists: %s (use --force to overwrite with backup, or --skip-existing)", compositor, existing)
			}
			fmt.Printf("⚠ Skipping %s config, already exists: %s\n", compositor, existing)
			deployCompositor = false
		}
		if deployTerminal {
			if existing := firstExistingPath([]string{terminalPrimaryPath(term)}); existing != "" {
				if !skipExisting {
					return fmt.Errorf("%s config already exists: %s (use --force to overwrite with backup, or --skip-existing)", terminal, existing)
				}
				fmt.Printf("⚠ Skipping %s config, already exists: %s\n", terminal, existing)
				deployTerminal = false
			}
		}
	}

	if !deployCompositor && !deployTerminal {
		return nil
	}

	logChan := make(chan string, 100)
	logDone := make(chan struct{})
	go func() {
		for msg := range logChan {
			fmt.Println("  " + msg)
		}
		close(logDone)
	}()
	deployer := config.NewConfigDeployer(logChan)
	deployer.SetReplaceBinds(stockBinds)

	var results []config.DeploymentResult
	var deployErr error
	if deployCompositor {
		terminalCommand := defaultTerminalCommand()
		if termSelected {
			terminalCommand = term.Command()
		}
		if wm == deps.WindowManagerHyprland {
			deployer.SetHyprlandVersion(installedHyprlandVersion())
		}
		result, err := deployer.DeployCompositor(wm, terminalCommand, headlessUseSystemd(wm, noSystemd))
		results = append(results, result)
		deployErr = err
	}
	if deployErr == nil && deployTerminal {
		terminalResults, err := deployer.DeployTerminal(term)
		results = append(results, terminalResults...)
		deployErr = err
	}

	close(logChan)
	<-logDone

	for _, result := range results {
		if !result.Deployed {
			continue
		}
		fmt.Printf("✓ %s: %s\n", result.ConfigType, result.Path)
		if result.BackupPath != "" {
			fmt.Printf("  Backup: %s\n", result.BackupPath)
		}
	}

	if deployErr != nil {
		return fmt.Errorf("deployment failed: %w", deployErr)
	}
	return nil
}

func parseHeadlessCompositor(name string) (deps.WindowManager, error) {
	switch name {
	case "niri":
		return deps.WindowManagerNiri, nil
	case "hyprland":
		return deps.WindowManagerHyprland, nil
	case "mango":
		return deps.WindowManagerMango, nil
	default:
		return 0, fmt.Errorf("unknown compositor %q (expected niri, hyprland, or mango)", name)
	}
}

func parseHeadlessTerminal(name string) (deps.Terminal, bool, error) {
	switch name {
	case "":
		return deps.TerminalGhostty, false, nil
	case "ghostty":
		return deps.TerminalGhostty, true, nil
	case "kitty":
		return deps.TerminalKitty, true, nil
	case "alacritty":
		return deps.TerminalAlacritty, true, nil
	default:
		return 0, false, fmt.Errorf("unknown terminal %q (expected ghostty, kitty, or alacritty)", name)
	}
}

func headlessUseSystemd(wm deps.WindowManager, noSystemd bool) bool {
	if noSystemd {
		return false
	}
	return !isVoidSetup()
}
