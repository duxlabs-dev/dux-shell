package main

import (
	"fmt"
	"os"

	"github.com/duxlabs-dev/dux-shell/core/internal/configprofile"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/spf13/cobra"
)

var profileCmd = &cobra.Command{
	Use:   "profile",
	Short: "Manage config profiles",
	Long:  "List config profiles and export or import them as .tar.gz archives that bundle their wallpapers.",
}

var profileListCmd = &cobra.Command{
	Use:   "list",
	Short: "List config profiles",
	Long:  "List config profiles, one per line as the id and the name separated by a tab.",
	Args:  cobra.NoArgs,
	Run: func(cmd *cobra.Command, args []string) {
		profiles, err := configprofile.List(configprofile.Dir())
		if err != nil {
			log.Fatalf("Error listing profiles: %v", err)
		}
		for _, p := range profiles {
			fmt.Printf("%s\t%s\n", p.ID, p.Name)
		}
	},
}

var profileExportCmd = &cobra.Command{
	Use:   "export <id> <file>",
	Short: "Export a profile to a .tar.gz archive",
	Long:  "Export a profile and the wallpapers it uses to a .tar.gz archive. Paths that aren't bundled (wallpapers that can't be, cycling folders, custom theme files) stay as they are and are printed on stdout, one per line.",
	Args:  cobra.ExactArgs(2),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) == 1 {
			return nil, cobra.ShellCompDirectiveDefault
		}
		if len(args) > 1 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		profiles, _ := configprofile.List(configprofile.Dir())
		ids := make([]string, len(profiles))
		for i, p := range profiles {
			ids[i] = p.ID
		}
		return ids, cobra.ShellCompDirectiveNoFileComp
	},
	Run: func(cmd *cobra.Command, args []string) {
		warnings, err := configprofile.Export(configprofile.Dir(), args[0], args[1])
		if err != nil {
			exitWithStdoutError(err)
		}
		for _, w := range warnings {
			fmt.Println(w)
		}
	},
}

var profileImportCmd = &cobra.Command{
	Use:   "import <file>",
	Short: "Import a profile from a .tar.gz archive",
	Long:  "Import a profile from an archive made by export as a new profile and print its id. Plugin settings, plugin widgets and custom dock trash commands are not imported. The profile is not activated.",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		id, err := configprofile.Import(configprofile.Dir(), configprofile.WallpaperDir(), args[0])
		if err != nil {
			exitWithStdoutError(err)
		}
		fmt.Println(id)
	},
}

// The shell reads only stdout.
func exitWithStdoutError(err error) {
	fmt.Println(err)
	os.Exit(1)
}

func init() {
	profileCmd.AddCommand(profileListCmd, profileExportCmd, profileImportCmd)
}
