package main

import (
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/plugins"
	"github.com/duxlabs-dev/dux-shell/core/internal/server"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/sysupdate"
	"github.com/duxlabs-dev/dux-shell/core/internal/shellembed"
	"github.com/duxlabs-dev/dux-shell/core/internal/site"
	"github.com/spf13/cobra"
)

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Show version information",
	Run:   runVersion,
}

var ipcCmd = &cobra.Command{
	Use:   "ipc",
	Short: "Send IPC commands to running DMS shell",
	Long: `Send IPC commands to the running DMS shell.

  dms ipc call <target> <function> [args...]   invoke a command
  dms ipc list                                 list all targets and functions

Full reference: ` + site.Docs + "/dms/keybinds-ipc",
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		return getShellIPCCompletions(args, toComplete), cobra.ShellCompDirectiveNoFileComp
	},
	Run: func(cmd *cobra.Command, args []string) {
		runShellIPCCommand(args)
	},
}

var ipcListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all IPC targets and functions",
	Run: func(cmd *cobra.Command, args []string) {
		printIPCHelp()
	},
}

func init() {
	ipcCmd.AddCommand(ipcListCmd)
	ipcCmd.SetHelpFunc(func(cmd *cobra.Command, args []string) {
		printIPCHelp()
	})
	pluginsUpdateCmd.Flags().BoolP("all", "a", false, "Update all installed plugins")
	pluginsUpdateCmd.Flags().Bool("check", false, "Check for available updates without applying them")
	pluginsLockCmd.Flags().StringP("output", "o", "", "Also write the lockfile to this path")
	pluginsRestoreCmd.Flags().Bool("prune", false, "Remove managed plugins that are not in the lockfile")
}

var debugSrvCmd = &cobra.Command{
	Use:   "debug-srv",
	Short: "Start the debug server",
	Long:  "Start the Unix socket debug server for DMS",
	Run: func(cmd *cobra.Command, args []string) {
		if err := startDebugServer(); err != nil {
			log.Fatalf("Error starting debug server: %v", err)
		}
	},
}

var pluginsCmd = &cobra.Command{
	Use:   "plugins",
	Short: "Manage DMS plugins",
	Long:  "Browse and manage DMS plugins from the registry",
}

var pluginsBrowseCmd = &cobra.Command{
	Use:   "browse",
	Short: "Browse available plugins",
	Long:  "Browse available plugins from the DMS plugin registry",
	Run: func(cmd *cobra.Command, args []string) {
		if err := browsePlugins(); err != nil {
			log.Fatalf("Error browsing plugins: %v", err)
		}
	},
}

var pluginsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List installed plugins",
	Long:  "List all installed DMS plugins",
	Run: func(cmd *cobra.Command, args []string) {
		if err := listInstalledPlugins(); err != nil {
			log.Fatalf("Error listing plugins: %v", err)
		}
	},
}

var pluginsInstallCmd = &cobra.Command{
	Use:   "install <plugin-id>",
	Short: "Install a plugin by ID",
	Long:  "Install a DMS plugin from the registry using its ID (e.g., 'myPlugin'). Plugin names with spaces are also supported for backward compatibility.",
	Args:  cobra.ExactArgs(1),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) != 0 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		return getAvailablePluginIDs(), cobra.ShellCompDirectiveNoFileComp
	},
	Run: func(cmd *cobra.Command, args []string) {
		if err := installPluginCLI(args[0]); err != nil {
			log.Fatalf("Error installing plugin: %v", err)
		}
	},
}

var pluginsUninstallCmd = &cobra.Command{
	Use:   "uninstall <plugin-id>",
	Short: "Uninstall a plugin by ID",
	Long:  "Uninstall a DMS plugin using its ID (e.g., 'myPlugin'). Plugin names with spaces are also supported for backward compatibility.",
	Args:  cobra.ExactArgs(1),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) != 0 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		return getInstalledPluginIDs(), cobra.ShellCompDirectiveNoFileComp
	},
	Run: func(cmd *cobra.Command, args []string) {
		if err := uninstallPluginCLI(args[0]); err != nil {
			log.Fatalf("Error uninstalling plugin: %v", err)
		}
	},
}

var pluginsUpdateCmd = &cobra.Command{
	Use:   "update [plugin-id]",
	Short: "Update a plugin by ID, or all plugins",
	Long:  "Update an installed DMS plugin using its ID (e.g., 'myPlugin'). If --all or -a is specified, all installed plugins will be updated.",
	Args: func(cmd *cobra.Command, args []string) error {
		updateAll, _ := cmd.Flags().GetBool("all")
		if updateAll {
			if len(args) > 0 {
				return fmt.Errorf("cannot specify plugin ID when using --all/-a")
			}
			return nil
		}
		if len(args) != 1 {
			return fmt.Errorf("requires exactly 1 arg (plugin ID) or use --all/-a")
		}
		return nil
	},
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) != 0 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		return getInstalledPluginIDs(), cobra.ShellCompDirectiveNoFileComp
	},
	Run: func(cmd *cobra.Command, args []string) {
		checkOnly, _ := cmd.Flags().GetBool("check")
		updateAll, _ := cmd.Flags().GetBool("all")
		if checkOnly {
			if updateAll {
				if err := checkAllPluginsCLI(); err != nil {
					log.Fatalf("Error checking updates: %v", err)
				}
				return
			}
			if err := checkPluginCLI(args[0]); err != nil {
				log.Fatalf("Error checking update: %v", err)
			}
			return
		}
		if updateAll {
			if err := updateAllPluginsCLI(); err != nil {
				log.Fatalf("Error updating plugins: %v", err)
			}
			return
		}
		if err := updatePluginCLI(args[0]); err != nil {
			log.Fatalf("Error updating plugin: %v", err)
		}
	},
}

var pluginsLockCmd = &cobra.Command{
	Use:   "lock",
	Short: "Record installed plugins and their exact revisions",
	Long:  "Write a portable plugins.lock.json containing every managed user plugin and its current Git commit.",
	Args:  cobra.NoArgs,
	Run: func(cmd *cobra.Command, args []string) {
		output, _ := cmd.Flags().GetString("output")
		if err := lockPluginsCLI(output); err != nil {
			log.Fatalf("Error writing plugin lockfile: %v", err)
		}
	},
}

var pluginsRestoreCmd = &cobra.Command{
	Use:   "restore [lockfile]",
	Short: "Restore plugins from exact revisions in a lockfile",
	Long:  "Install or reset all plugins in a portable plugins.lock.json. Existing managed plugins are retained unless --prune is specified.",
	Args:  cobra.MaximumNArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		path := ""
		if len(args) == 1 {
			path = args[0]
		}
		prune, _ := cmd.Flags().GetBool("prune")
		if err := restorePluginsCLI(path, prune); err != nil {
			log.Fatalf("Error restoring plugins: %v", err)
		}
	},
}

func runVersion(cmd *cobra.Command, args []string) {
	fmt.Printf("%s\n", formatVersion(Version))
}

// Git builds: dms (git) v0.6.2-XXXX
// Stable releases: dms v0.6.2
func formatVersion(version string) string {
	if n := sysupdate.GitBuildCount(version); n > 0 {
		// Fedora COPR (0.0.git.2267.d430cae9) carries no real base version.
		base, _, ok := strings.Cut(version, "+git")
		if !ok {
			base = getBaseVersion()
		}
		return fmt.Sprintf("dms (git) v%s-%d", strings.TrimPrefix(base, "v"), n)
	}

	// Stable release format: 0.6.2
	re := regexp.MustCompile(`^([\d.]+)$`)
	if matches := re.FindStringSubmatch(version); matches != nil {
		return fmt.Sprintf("dms v%s", matches[1])
	}

	return fmt.Sprintf("dms %s", version)
}

var baseVersionRe = regexp.MustCompile(`^([\d.]+)`)

// Installed UI trees, for builds without an embedded UI.
var shellVersionPaths = []string{
	"/usr/share/quickshell/dms/VERSION",
	"/usr/local/share/quickshell/dms/VERSION",
	"/etc/xdg/quickshell/dms/VERSION",
}

func getBaseVersion() string {
	if ver := parseBaseVersion(shellembed.Version()); ver != "" {
		return ver
	}

	for _, path := range shellVersionPaths {
		content, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		if ver := parseBaseVersion(string(content)); ver != "" {
			return ver
		}
	}

	return "1.0.2"
}

func parseBaseVersion(raw string) string {
	matches := baseVersionRe.FindStringSubmatch(strings.TrimPrefix(strings.TrimSpace(raw), "v"))
	if matches == nil {
		return ""
	}
	return matches[1]
}

func startDebugServer() error {
	server.CLIVersion = Version
	return server.Start(true)
}

func browsePlugins() error {
	registry, err := plugins.NewRegistry()
	if err != nil {
		return fmt.Errorf("failed to create registry: %w", err)
	}

	manager, err := plugins.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create manager: %w", err)
	}

	fmt.Println("Fetching plugin registry...")
	pluginList, err := registry.List()
	if err != nil {
		return fmt.Errorf("failed to list plugins: %w", err)
	}

	if len(pluginList) == 0 {
		fmt.Println("No plugins found in registry.")
		return nil
	}

	feedback := plugins.FetchFeedback()

	nameByID := make(map[string]string, len(pluginList))
	for _, plugin := range pluginList {
		nameByID[plugin.ID] = plugin.Name
	}

	fmt.Printf("\nAvailable Plugins (%d):\n\n", len(pluginList))
	for _, plugin := range pluginList {
		installed, _ := manager.IsInstalled(plugin)
		installedMarker := ""
		if installed {
			installedMarker = " [Installed]"
		}

		fmt.Printf("  %s%s\n", plugin.Name, installedMarker)
		fmt.Printf("    ID: %s\n", plugin.ID)
		fmt.Printf("    Category: %s\n", plugin.Category)
		fmt.Printf("    Author: %s\n", plugin.Author)
		fmt.Printf("    Description: %s\n", plugin.Description)
		fmt.Printf("    Repository: %s\n", plugin.Repo)
		if len(plugin.Capabilities) > 0 {
			fmt.Printf("    Capabilities: %s\n", strings.Join(plugin.Capabilities, ", "))
		}
		if len(plugin.Compositors) > 0 {
			fmt.Printf("    Compositors: %s\n", strings.Join(plugin.Compositors, ", "))
		}
		if len(plugin.Dependencies) > 0 {
			fmt.Printf("    Dependencies: %s\n", strings.Join(plugin.Dependencies, ", "))
		}
		if fb, ok := feedback[plugin.ID]; ok {
			fmt.Printf("    Upvotes: %d\n", fb.Upvotes)
			if len(fb.Status) > 0 {
				fmt.Printf("    Status: %s\n", strings.Join(fb.Status, ", "))
			}
			if fb.IssueURL != "" {
				fmt.Printf("    Discuss: %s\n", fb.IssueURL)
			}
			if len(fb.Similar) > 0 {
				names := make([]string, len(fb.Similar))
				for i, id := range fb.Similar {
					if name, ok := nameByID[id]; ok {
						names[i] = name
					} else {
						names[i] = id
					}
				}
				fmt.Printf("    Related: %s\n", strings.Join(names, ", "))
			}
		}
		fmt.Println()
	}

	return nil
}

func listInstalledPlugins() error {
	manager, err := plugins.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create manager: %w", err)
	}

	registry, err := plugins.NewRegistry()
	if err != nil {
		return fmt.Errorf("failed to create registry: %w", err)
	}

	installedNames, err := manager.ListInstalled()
	if err != nil {
		return fmt.Errorf("failed to list installed plugins: %w", err)
	}

	if len(installedNames) == 0 {
		fmt.Println("No plugins installed.")
		return nil
	}

	allPlugins, err := registry.List()
	if err != nil {
		return fmt.Errorf("failed to list plugins: %w", err)
	}

	pluginMap := make(map[string]plugins.Plugin)
	for _, p := range allPlugins {
		pluginMap[p.ID] = p
	}

	fmt.Printf("\nInstalled Plugins (%d):\n\n", len(installedNames))
	for _, id := range installedNames {
		if plugin, ok := pluginMap[id]; ok {
			hasUpdateStr := ""
			if hasUpdates, _, err := manager.HasUpdates(id, plugin); err == nil && hasUpdates {
				hasUpdateStr = " (update available)"
			}
			fmt.Printf("  %s%s\n", plugin.Name, hasUpdateStr)
			fmt.Printf("    ID: %s\n", plugin.ID)
			fmt.Printf("    Category: %s\n", plugin.Category)
			fmt.Printf("    Author: %s\n", plugin.Author)
			fmt.Println()
		} else {
			fmt.Printf("  %s (not in registry)\n\n", id)
		}
	}

	return nil
}

func installPluginCLI(idOrName string) error {
	registry, err := plugins.NewRegistry()
	if err != nil {
		return fmt.Errorf("failed to create registry: %w", err)
	}

	manager, err := plugins.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create manager: %w", err)
	}

	pluginList, err := registry.List()
	if err != nil {
		return fmt.Errorf("failed to list plugins: %w", err)
	}

	// First, try to find by ID (preferred method)
	var plugin *plugins.Plugin
	for _, p := range pluginList {
		if p.ID == idOrName {
			plugin = &p
			break
		}
	}

	// Fallback to name for backward compatibility
	if plugin == nil {
		for _, p := range pluginList {
			if p.Name == idOrName {
				plugin = &p
				break
			}
		}
	}

	if plugin == nil {
		return fmt.Errorf("plugin not found: %s", idOrName)
	}

	installed, err := manager.IsInstalled(*plugin)
	if err != nil {
		return fmt.Errorf("failed to check install status: %w", err)
	}

	if installed {
		return fmt.Errorf("plugin already installed: %s", plugin.Name)
	}

	fmt.Printf("Installing plugin: %s (ID: %s)\n", plugin.Name, plugin.ID)
	if err := manager.Install(*plugin); err != nil {
		return fmt.Errorf("failed to install plugin: %w", err)
	}

	fmt.Printf("Plugin installed successfully: %s\n", plugin.Name)
	return nil
}

func lockPluginsCLI(outputPath string) error {
	manager, err := plugins.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create manager: %w", err)
	}
	warnings, err := manager.WriteCurrentLockfile(outputPath)
	if err != nil {
		return err
	}
	for _, warning := range warnings {
		fmt.Fprintf(os.Stderr, "Warning: %s\n", warning)
	}
	fmt.Printf("Plugin lockfile written: %s\n", manager.GetLockfilePath())
	if outputPath != "" && outputPath != manager.GetLockfilePath() {
		fmt.Printf("Plugin lockfile exported: %s\n", outputPath)
	}
	return nil
}

func restorePluginsCLI(path string, prune bool) error {
	manager, err := plugins.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create manager: %w", err)
	}
	if err := manager.RestoreFromLockfile(path, prune); err != nil {
		return err
	}
	if path == "" {
		path = manager.GetLockfilePath()
	}
	fmt.Printf("Plugins restored from lockfile: %s\n", path)
	return nil
}

func getAvailablePluginIDs() []string {
	registry, err := plugins.NewRegistry()
	if err != nil {
		return nil
	}

	pluginList, err := registry.List()
	if err != nil {
		return nil
	}

	var ids []string
	for _, p := range pluginList {
		ids = append(ids, p.ID)
	}
	return ids
}

func getInstalledPluginIDs() []string {
	manager, err := plugins.NewManager()
	if err != nil {
		return nil
	}

	installed, err := manager.ListInstalled()
	if err != nil {
		return nil
	}

	return installed
}

func uninstallPluginCLI(idOrName string) error {
	manager, err := plugins.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create manager: %w", err)
	}

	registry, err := plugins.NewRegistry()
	if err != nil {
		return fmt.Errorf("failed to create registry: %w", err)
	}

	pluginList, _ := registry.List()
	plugin := plugins.FindByIDOrName(idOrName, pluginList)

	if plugin != nil {
		installed, err := manager.IsInstalled(*plugin)
		if err != nil {
			return fmt.Errorf("failed to check install status: %w", err)
		}
		if !installed {
			return fmt.Errorf("plugin not installed: %s", plugin.Name)
		}

		fmt.Printf("Uninstalling plugin: %s (ID: %s)\n", plugin.Name, plugin.ID)
		if err := manager.Uninstall(*plugin); err != nil {
			return fmt.Errorf("failed to uninstall plugin: %w", err)
		}
		fmt.Printf("Plugin uninstalled successfully: %s\n", plugin.Name)
		return nil
	}

	fmt.Printf("Uninstalling plugin: %s\n", idOrName)
	if err := manager.UninstallByIDOrName(idOrName); err != nil {
		return err
	}
	fmt.Printf("Plugin uninstalled successfully: %s\n", idOrName)
	return nil
}

func updatePluginCLI(idOrName string) error {
	manager, err := plugins.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create manager: %w", err)
	}

	registry, err := plugins.NewRegistry()
	if err != nil {
		return fmt.Errorf("failed to create registry: %w", err)
	}

	pluginList, _ := registry.List()
	plugin := plugins.FindByIDOrName(idOrName, pluginList)

	if plugin != nil {
		installed, err := manager.IsInstalled(*plugin)
		if err != nil {
			return fmt.Errorf("failed to check install status: %w", err)
		}
		if !installed {
			return fmt.Errorf("plugin not installed: %s", plugin.Name)
		}

		fmt.Printf("Updating plugin: %s (ID: %s)\n", plugin.Name, plugin.ID)
		if err := manager.Update(*plugin); err != nil {
			return fmt.Errorf("failed to update plugin: %w", err)
		}
		fmt.Printf("Plugin updated successfully: %s\n", plugin.Name)
		return nil
	}

	fmt.Printf("Updating plugin: %s\n", idOrName)
	if err := manager.UpdateByIDOrName(idOrName); err != nil {
		return err
	}
	fmt.Printf("Plugin updated successfully: %s\n", idOrName)
	return nil
}

func updateAllPluginsCLI() error {
	manager, err := plugins.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create manager: %w", err)
	}

	registry, err := plugins.NewRegistry()
	if err != nil {
		return fmt.Errorf("failed to create registry: %w", err)
	}

	installed, err := manager.ListInstalled()
	if err != nil {
		return fmt.Errorf("failed to list installed plugins: %w", err)
	}

	pluginList, _ := registry.List()

	var errs []error
	for _, pluginID := range installed {
		plugin := plugins.FindByIDOrName(pluginID, pluginList)
		if plugin != nil {
			fmt.Printf("Updating plugin: %s (ID: %s)\n", plugin.Name, plugin.ID)
			if err := manager.Update(*plugin); err != nil {
				if strings.Contains(err.Error(), "cannot update system plugin") {
					fmt.Printf("Skipping system plugin: %s\n", plugin.Name)
				} else {
					errs = append(errs, fmt.Errorf("failed to update %s: %w", plugin.Name, err))
				}
			} else {
				fmt.Printf("Plugin updated successfully: %s\n", plugin.Name)
			}
		} else {
			fmt.Printf("Updating plugin: %s\n", pluginID)
			if err := manager.UpdateByIDOrName(pluginID); err != nil {
				if strings.Contains(err.Error(), "cannot update system plugin") {
					fmt.Printf("Skipping system plugin: %s\n", pluginID)
				} else {
					errs = append(errs, fmt.Errorf("failed to update %s: %w", pluginID, err))
				}
			} else {
				fmt.Printf("Plugin updated successfully: %s\n", pluginID)
			}
		}
	}

	if len(errs) > 0 {
		for _, err := range errs {
			fmt.Fprintf(os.Stderr, "%v\n", err)
		}
		return fmt.Errorf("failed to update some plugins")
	}

	return nil
}

func checkPluginCLI(idOrName string) error {
	manager, err := plugins.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create manager: %w", err)
	}

	registry, err := plugins.NewRegistry()
	if err != nil {
		return fmt.Errorf("failed to create registry: %w", err)
	}

	pluginList, _ := registry.List()
	plugin := plugins.FindByIDOrName(idOrName, pluginList)

	if plugin != nil {
		installed, err := manager.IsInstalled(*plugin)
		if err != nil {
			return fmt.Errorf("failed to check install status: %w", err)
		}
		if !installed {
			return fmt.Errorf("plugin not installed: %s", plugin.Name)
		}

		hasUpdates, _, err := manager.HasUpdates(plugin.ID, *plugin)
		if err != nil {
			return fmt.Errorf("failed to check updates: %w", err)
		}

		if hasUpdates {
			fmt.Printf("Update available for plugin: %s (ID: %s)\n", plugin.Name, plugin.ID)
		} else {
			fmt.Printf("Plugin is up to date: %s\n", plugin.Name)
		}
		return nil
	}

	dummyPlugin := plugins.Plugin{ID: idOrName}
	hasUpdates, _, err := manager.HasUpdates(idOrName, dummyPlugin)
	if err != nil {
		return fmt.Errorf("failed to check updates: %w", err)
	}

	if hasUpdates {
		fmt.Printf("Update available for plugin: %s\n", idOrName)
	} else {
		fmt.Printf("Plugin is up to date: %s\n", idOrName)
	}
	return nil
}

func checkAllPluginsCLI() error {
	manager, err := plugins.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create manager: %w", err)
	}

	registry, err := plugins.NewRegistry()
	if err != nil {
		return fmt.Errorf("failed to create registry: %w", err)
	}

	installed, err := manager.ListInstalled()
	if err != nil {
		return fmt.Errorf("failed to list installed plugins: %w", err)
	}

	pluginList, _ := registry.List()

	var count int
	for _, pluginID := range installed {
		plugin := plugins.FindByIDOrName(pluginID, pluginList)
		var hasUpdates bool
		var name string

		if plugin != nil {
			name = plugin.Name
			hasUpdates, _, _ = manager.HasUpdates(pluginID, *plugin)
		} else {
			name = pluginID
			dummyPlugin := plugins.Plugin{ID: pluginID}
			hasUpdates, _, _ = manager.HasUpdates(pluginID, dummyPlugin)
		}

		if hasUpdates {
			fmt.Printf("Update available for plugin: %s (ID: %s)\n", name, pluginID)
			count++
		}
	}

	if count > 0 {
		fmt.Printf("\nFound %d plugin(s) with available updates.\n", count)
	} else {
		fmt.Println("All plugins are up to date.")
	}

	return nil
}

func getCommonCommands() []*cobra.Command {
	commands := shellApp.Commands()
	return append(commands, []*cobra.Command{
		versionCmd,
		ipcCmd,
		debugSrvCmd,
		sysmonHelperCmd,
		pluginsCmd,
		registryCmd,
		dank16Cmd,
		brightnessCmd,
		iccCmd,
		dpmsCmd,
		keybindsCmd,
		greeterCmd,
		setupCmd,
		colorCmd,
		qrCmd,
		screenshotCmd,
		notifyActionCmd,
		notifyCmd,
		genericNotifyActionCmd,
		matugenCmd,
		clipboardCmd,
		chromaCmd,
		doctorCmd,
		configCmd,
		dlCmd,
		randrCmd,
		blurCmd,
		trashCmd,
		systemCmd,
		systemdCmd,
		switchUserCmd,
		switchCmd,
		migrateCmd,
		dmenuCmd,
	}...)
}
