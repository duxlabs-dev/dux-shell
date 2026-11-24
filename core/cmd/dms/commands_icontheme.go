package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/duxlabs-dev/dux-shell/core/internal/iconfolders"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"github.com/spf13/cobra"
)

var iconThemeCmd = &cobra.Command{
	Use:   "icon-theme",
	Short: "List, install and remove icon themes",
}

var iconThemeListCmd = &cobra.Command{
	Use:   "list",
	Short: "List the installed icon themes with a few of each one's icons, and the cursor themes with their pointer",
	Args:  cobra.NoArgs,
	Run: func(cmd *cobra.Command, args []string) {
		o := iconThemeOptions(cmd)
		line, _ := json.Marshal(map[string]any{"themes": iconfolders.ListThemes(o), "cursors": iconfolders.ListCursors(o)})
		fmt.Println(string(line))
	},
}

var iconThemeInstallCmd = &cobra.Command{
	Use:   "install <archive|folder>",
	Short: "Install the icon themes of an archive or folder into your icon directory",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		replace, _ := cmd.Flags().GetBool("replace")
		printIconThemes(iconfolders.InstallTheme(iconThemeOptions(cmd), args[0], replace))
	},
}

var iconThemeRemoveCmd = &cobra.Command{
	Use:   "remove <theme>",
	Short: "Remove an icon theme from your icon directory",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		inUse, _ := cmd.Flags().GetStringArray("in-use")
		printIconThemes([]string{args[0]}, iconfolders.RemoveTheme(iconThemeOptions(cmd), args[0], inUse))
	},
}

var cursorThemeCmd = &cobra.Command{
	Use:   "cursor-theme",
	Short: "Install and remove cursor themes",
}

var cursorThemeInstallCmd = &cobra.Command{
	Use:   "install <archive|folder>",
	Short: "Install the cursor themes of an archive or folder into your icon directory",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		replace, _ := cmd.Flags().GetBool("replace")
		printIconThemes(iconfolders.InstallCursor(iconThemeOptions(cmd), args[0], replace))
	},
}

var cursorThemeRemoveCmd = &cobra.Command{
	Use:   "remove <theme>",
	Short: "Remove a cursor theme from your icon directory",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		inUse, _ := cmd.Flags().GetStringArray("in-use")
		printIconThemes([]string{args[0]}, iconfolders.RemoveCursor(iconThemeOptions(cmd), args[0], inUse))
	},
}

func init() {
	iconThemeCmd.PersistentFlags().String("state-dir", "", "State directory holding the folder recolor state (default: $XDG_CACHE_HOME/dms)")
	iconThemeInstallCmd.Flags().Bool("replace", false, "Replace a theme of the same name")
	iconThemeRemoveCmd.Flags().StringArray("in-use", nil, "A theme that must keep working; repeat for each")
	iconThemeCmd.AddCommand(iconThemeListCmd, iconThemeInstallCmd, iconThemeRemoveCmd)
	rootCmd.AddCommand(iconThemeCmd)

	cursorThemeCmd.PersistentFlags().String("state-dir", "", "State directory holding the folder recolor state (default: $XDG_CACHE_HOME/dms)")
	cursorThemeInstallCmd.Flags().Bool("replace", false, "Replace a theme of the same name")
	cursorThemeRemoveCmd.Flags().StringArray("in-use", nil, "A theme that must keep working; repeat for each")
	cursorThemeCmd.AddCommand(cursorThemeInstallCmd, cursorThemeRemoveCmd)
	rootCmd.AddCommand(cursorThemeCmd)
}

func iconThemeOptions(cmd *cobra.Command) iconfolders.Options {
	stateDir, _ := cmd.Flags().GetString("state-dir")
	if stateDir == "" {
		stateDir = filepath.Join(utils.XDGCacheHome(), "dms")
	}
	opts := iconfolders.NewOptions()
	opts.StateDir = stateDir
	return opts
}

// printIconThemes writes the one stdout line the shell reads: the themes, or the refusal and its code.
func printIconThemes(themes any, err error) {
	var out any = map[string]any{"themes": themes}
	var refusal *iconfolders.LibraryError
	switch {
	case errors.As(err, &refusal):
		out = refusal
	case err != nil:
		out = map[string]string{"error": err.Error()}
	}
	line, _ := json.Marshal(out)
	fmt.Println(string(line))
	if err != nil {
		os.Exit(1)
	}
}
