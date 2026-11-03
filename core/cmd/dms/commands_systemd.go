package main

import (
	"fmt"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/spf13/cobra"
)

var systemdCompositorFlag string

var systemdCmd = &cobra.Command{
	Use:   "systemd",
	Short: "Start DMS as a systemd user service with the compositor session",
	Long: `Manage dms.service for the compositor session.

enable makes the compositor's own session unit want dms.service, so DMS starts
with that compositor only: hyprland-session.target, niri.service or
mango-session.target. The compositor is the running one, or --compositor.`,
}

var systemdEnableCmd = &cobra.Command{
	Use:   "enable",
	Short: "Start dms.service with the compositor session",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		wm, err := systemdCompositor()
		if err != nil {
			return err
		}
		unit, err := config.EnableSession(wm)
		if err != nil {
			return err
		}
		fmt.Printf("dms.service starts with %s\n", unit)
		now, _ := cmd.Flags().GetBool("now")
		if !now {
			return nil
		}
		if err := runSystemctl("--user", "start", dmsSystemdUnit); err != nil {
			return err
		}
		fmt.Println("dms.service started")
		return nil
	},
}

var systemdDisableCmd = &cobra.Command{
	Use:   "disable",
	Short: "Stop starting dms.service with any compositor session",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		removed, err := config.DisableSession()
		if err != nil {
			return err
		}
		if len(removed) == 0 {
			fmt.Println("dms.service was not wanted by any compositor session")
		} else {
			fmt.Printf("dms.service no longer starts with %s\n", strings.Join(removed, ", "))
		}
		now, _ := cmd.Flags().GetBool("now")
		if !now {
			return nil
		}
		return runSystemctl("--user", "stop", dmsSystemdUnit)
	},
}

var systemdStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show which compositor sessions start dms.service",
	Args:  cobra.NoArgs,
	Run: func(cmd *cobra.Command, args []string) {
		state := getServiceState("dms", true)
		if !state.exists {
			fmt.Println("dms.service: not installed")
			return
		}
		fmt.Printf("dms.service: %s", state.enabled)
		if state.active != "" {
			fmt.Printf(", %s", state.active)
		}
		fmt.Println()
		wanted := config.SessionWanted()
		if len(wanted) == 0 {
			fmt.Println("Starts with: nothing (run 'dms systemd enable')")
			return
		}
		fmt.Printf("Starts with: %s\n", strings.Join(wanted, ", "))
	},
}

func systemdLifecycleCmd(verb string) *cobra.Command {
	return &cobra.Command{
		Use:   verb,
		Short: strings.ToUpper(verb[:1]) + verb[1:] + " dms.service",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runSystemctl("--user", verb, dmsSystemdUnit)
		},
	}
}

func systemdCompositor() (deps.WindowManager, error) {
	if systemdCompositorFlag == "" {
		if wm, ok := config.RunningCompositor(); ok {
			return wm, nil
		}
		name, err := detectCompositorForSetup()
		if err != nil {
			return 0, err
		}
		systemdCompositorFlag = name
	}
	switch strings.ToLower(systemdCompositorFlag) {
	case "hyprland":
		return deps.WindowManagerHyprland, nil
	case "niri":
		return deps.WindowManagerNiri, nil
	case "mango", "mangowc":
		return deps.WindowManagerMango, nil
	}
	return 0, fmt.Errorf("unknown compositor %q (hyprland, niri or mango)", systemdCompositorFlag)
}

func init() {
	systemdEnableCmd.Flags().StringVar(&systemdCompositorFlag, "compositor", "", "hyprland, niri or mango (default: the running one)")
	systemdEnableCmd.Flags().Bool("now", false, "Also start dms.service")
	systemdDisableCmd.Flags().Bool("now", false, "Also stop dms.service")
	systemdCmd.AddCommand(systemdEnableCmd, systemdDisableCmd, systemdStatusCmd, systemdLifecycleCmd("start"), systemdLifecycleCmd("stop"), systemdLifecycleCmd("restart"))
}
