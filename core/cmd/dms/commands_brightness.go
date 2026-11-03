package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/brightness"
	"github.com/spf13/cobra"
)

var brightnessCmd = &cobra.Command{
	Use:   "brightness",
	Short: "Control device brightness",
	Long:  "Control brightness for backlight and LED devices (use --ddc to include DDC/I2C monitors)",
}

var brightnessListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all brightness devices",
	Long:  "List all available brightness devices with their current values",
	Run:   runBrightnessList,
}

var brightnessSetCmd = &cobra.Command{
	Use:   "set <device_id> <percent>",
	Short: "Set brightness for a device",
	Long:  "Set brightness percentage (0-100) for a specific device",
	Args:  cobra.ExactArgs(2),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) != 0 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		includeDDC, _ := cmd.Flags().GetBool("ddc")
		return getBrightnessDevices(includeDDC), cobra.ShellCompDirectiveNoFileComp
	},
	Run: runBrightnessSet,
}

var brightnessGetCmd = &cobra.Command{
	Use:   "get <device_id>",
	Short: "Get brightness for a device",
	Long:  "Get current brightness percentage for a specific device",
	Args:  cobra.ExactArgs(1),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) != 0 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		includeDDC, _ := cmd.Flags().GetBool("ddc")
		return getBrightnessDevices(includeDDC), cobra.ShellCompDirectiveNoFileComp
	},
	Run: runBrightnessGet,
}

func init() {
	brightnessListCmd.Flags().Bool("ddc", false, "Include DDC/I2C monitors (slower)")
	brightnessSetCmd.Flags().Bool("ddc", false, "Include DDC/I2C monitors (slower)")
	brightnessSetCmd.Flags().Bool("exponential", false, "Use exponential brightness scaling")
	brightnessSetCmd.Flags().Float64("exponent", 1.2, "Exponent for exponential scaling (default 1.2)")
	brightnessGetCmd.Flags().Bool("ddc", false, "Include DDC/I2C monitors (slower)")

	brightnessCmd.SetHelpTemplate(`{{.Long}}

Usage:
  {{.UseLine}}{{if .HasAvailableSubCommands}}

Available Commands:{{range .Commands}}{{if (or .IsAvailableCommand (eq .Name "help"))}}
  {{rpad .Name .NamePadding }} {{.Short}}{{end}}{{end}}{{end}}{{if .HasAvailableLocalFlags}}

Flags:
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasAvailableInheritedFlags}}

Global Flags:
{{.InheritedFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasHelpSubCommands}}

Additional help topics:{{range .Commands}}{{if .IsAdditionalHelpTopicCommand}}
  {{rpad .Name .NamePadding}} {{.Short}}{{end}}{{end}}{{end}}{{if .HasAvailableSubCommands}}

Use "{{.CommandPath}} [command] --help" for more information about a command.{{end}}
`)

	brightnessListCmd.SetHelpTemplate(`{{.Long}}

Usage:
  {{.UseLine}}{{if .HasAvailableLocalFlags}}

Flags:
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasAvailableInheritedFlags}}

Global Flags:
{{.InheritedFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}
`)

	brightnessSetCmd.SetHelpTemplate(`{{.Long}}

Usage:
  {{.UseLine}}{{if .HasAvailableLocalFlags}}

Flags:
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasAvailableInheritedFlags}}

Global Flags:
{{.InheritedFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}
`)

	brightnessGetCmd.SetHelpTemplate(`{{.Long}}

Usage:
  {{.UseLine}}{{if .HasAvailableLocalFlags}}

Flags:
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasAvailableInheritedFlags}}

Global Flags:
{{.InheritedFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}
`)

	brightnessCmd.AddCommand(brightnessListCmd, brightnessSetCmd, brightnessGetCmd)
}

func getAllBrightnessDevices(includeDDC bool) []brightness.Device {
	allDevices := []brightness.Device{}

	sysfs, err := brightness.NewSysfsBackend()
	if err != nil {
		log.Debugf("Failed to initialize sysfs backend: %v", err)
	} else {
		devices, err := sysfs.GetDevices()
		if err != nil {
			log.Debugf("Failed to get sysfs devices: %v", err)
		} else {
			allDevices = append(allDevices, devices...)
		}
	}

	if includeDDC {
		ddc, err := brightness.NewDDCBackend()
		if err != nil {
			fmt.Printf("Warning: Failed to initialize DDC backend: %v\n", err)
		} else {
			time.Sleep(100 * time.Millisecond)
			devices, err := ddc.GetDevices()
			if err != nil {
				fmt.Printf("Warning: Failed to get DDC devices: %v\n", err)
			} else {
				allDevices = append(allDevices, devices...)
			}
			ddc.Close()
		}
	}

	return allDevices
}

func runBrightnessList(cmd *cobra.Command, args []string) {
	includeDDC, _ := cmd.Flags().GetBool("ddc")
	allDevices := getAllBrightnessDevices(includeDDC)

	if len(allDevices) == 0 {
		fmt.Println("No brightness devices found")
		return
	}

	maxIDLen := len("Device")
	maxNameLen := len("Name")
	for _, dev := range allDevices {
		if len(dev.ID) > maxIDLen {
			maxIDLen = len(dev.ID)
		}
		if len(dev.Name) > maxNameLen {
			maxNameLen = len(dev.Name)
		}
	}

	idPad := maxIDLen + 2
	namePad := maxNameLen + 2

	fmt.Printf("%-*s  %-12s  %-*s  %s\n", idPad, "Device", "Class", namePad, "Name", "Brightness")

	sepLen := idPad + 2 + 12 + 2 + namePad + 2 + 15
	for range sepLen {
		fmt.Print("─")
	}
	fmt.Println()

	for _, device := range allDevices {
		fmt.Printf("%-*s  %-12s  %-*s  %3d%%\n",
			idPad,
			device.ID,
			device.Class,
			namePad,
			device.Name,
			device.CurrentPercent,
		)
	}
}

func runBrightnessSet(cmd *cobra.Command, args []string) {
	deviceID := args[0]
	var percent int
	if _, err := fmt.Sscanf(args[1], "%d", &percent); err != nil {
		log.Fatalf("Invalid percent value: %s", args[1])
	}

	if percent < 0 || percent > 100 {
		log.Fatalf("Percent must be between 0 and 100")
	}

	includeDDC, _ := cmd.Flags().GetBool("ddc")
	exponential, _ := cmd.Flags().GetBool("exponential")
	exponent, _ := cmd.Flags().GetFloat64("exponent")

	parts := strings.SplitN(deviceID, ":", 2)
	if len(parts) == 2 && (parts[0] == "backlight" || parts[0] == "leds") {
		if ok := tryLogindBrightness(parts[0], parts[1], deviceID, percent, exponential, exponent); ok {
			return
		}
	}

	sysfs, err := brightness.NewSysfsBackend()
	if err == nil {
		if err := sysfs.SetBrightnessWithExponent(deviceID, percent, exponential, exponent); err == nil {
			fmt.Printf("Set %s to %d%%\n", deviceID, percent)
			return
		}
		log.Debugf("sysfs.SetBrightness failed: %v", err)
	} else {
		log.Debugf("NewSysfsBackend failed: %v", err)
	}

	// Try DDC if requested
	if includeDDC {
		ddc, err := brightness.NewDDCBackend()
		if err == nil {
			defer ddc.Close()
			time.Sleep(100 * time.Millisecond)
			if err := ddc.SetBrightnessWithExponent(deviceID, percent, exponential, exponent, nil); err == nil {
				ddc.WaitPending()
				fmt.Printf("Set %s to %d%%\n", deviceID, percent)
				return
			}
			log.Debugf("ddc.SetBrightness failed: %v", err)
		} else {
			log.Debugf("NewDDCBackend failed: %v", err)
		}
	}

	log.Fatalf("Failed to set brightness for device: %s", deviceID)
}

func tryLogindBrightness(subsystem, name, deviceID string, percent int, exponential bool, exponent float64) bool {
	sysfs, err := brightness.NewSysfsBackend()
	if err != nil {
		log.Debugf("NewSysfsBackend failed: %v", err)
		return false
	}

	logind, err := brightness.NewLogindBackend()
	if err != nil {
		log.Debugf("NewLogindBackend failed: %v", err)
		return false
	}
	defer logind.Close()

	dev, err := sysfs.GetDevice(deviceID)
	if err != nil {
		log.Debugf("sysfs.GetDeviceByID failed: %v", err)
		return false
	}

	value := sysfs.PercentToValueWithExponent(percent, dev, exponential, exponent)
	if err := logind.SetBrightness(subsystem, name, uint32(value)); err != nil {
		log.Debugf("logind.SetBrightness failed: %v", err)
		return false
	}

	log.Debugf("set %s to %d%% (%d) via logind", deviceID, percent, value)
	fmt.Printf("Set %s to %d%%\n", deviceID, percent)
	return true
}

func getBrightnessDevices(includeDDC bool) []string {
	allDevices := getAllBrightnessDevices(includeDDC)

	var deviceIDs []string
	for _, device := range allDevices {
		deviceIDs = append(deviceIDs, device.ID)
	}
	return deviceIDs
}

func runBrightnessGet(cmd *cobra.Command, args []string) {
	deviceID := args[0]
	includeDDC, _ := cmd.Flags().GetBool("ddc")
	allDevices := getAllBrightnessDevices(includeDDC)

	for _, device := range allDevices {
		if device.ID == deviceID {
			fmt.Printf("%s: %d%% (%d/%d)\n",
				device.ID,
				device.CurrentPercent,
				device.Current,
				device.Max,
			)
			return
		}
	}

	log.Fatalf("Device not found: %s", deviceID)
}
