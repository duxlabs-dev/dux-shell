package main

import (
	"fmt"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/registries"
	"github.com/spf13/afero"
	"github.com/spf13/cobra"
)

var registryCmd = &cobra.Command{
	Use:   "registry",
	Short: "Manage plugin and theme registries",
	Long:  "Manage the registries DMS fetches plugins and themes from. The official registry is always active and additional registries can be added by name and git URL, unless the CLI policy sets disable_registries.",
}

var registryListCmd = &cobra.Command{
	Use:   "list",
	Short: "List configured registries",
	Run: func(cmd *cobra.Command, args []string) {
		for _, s := range registries.Load(afero.NewOsFs()) {
			suffix := ""
			if s.Official() {
				suffix = " (official)"
			}
			fmt.Printf("%s%s\n    %s\n", s.Name, suffix, s.URL)
		}
	},
}

var registryAddCmd = &cobra.Command{
	Use:   "add <name> <url>",
	Short: "Add a registry",
	Long:  "Add a registry by name and git URL. The repository must contain a plugins/ or themes/ directory in the registry format.",
	Args:  cobra.ExactArgs(2),
	Run: func(cmd *cobra.Command, args []string) {
		if err := registries.Add(afero.NewOsFs(), args[0], args[1]); err != nil {
			log.Fatalf("Error adding registry: %v", err)
		}
		fmt.Printf("Registry added: %s\n", args[0])
	},
}

var registryRemoveCmd = &cobra.Command{
	Use:   "remove <name>",
	Short: "Remove a registry",
	Args:  cobra.ExactArgs(1),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) != 0 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		var names []string
		for _, s := range registries.Load(afero.NewOsFs()) {
			if !s.Official() {
				names = append(names, s.Name)
			}
		}
		return names, cobra.ShellCompDirectiveNoFileComp
	},
	Run: func(cmd *cobra.Command, args []string) {
		if err := registries.Remove(afero.NewOsFs(), args[0]); err != nil {
			log.Fatalf("Error removing registry: %v", err)
		}
		fmt.Printf("Registry removed: %s\n", args[0])
	},
}
