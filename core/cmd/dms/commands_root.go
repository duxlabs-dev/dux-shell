package main

import (
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "dms",
	Short: "dms CLI",
	Long:  "dms is the Dux Shell management CLI and backend server.",
}

func init() {
	rootCmd.PersistentFlags().StringVarP(shellApp.CustomConfigVar(), "config", "c", "", "Path to a UI config dir (containing shell.qml) to use instead of the embedded UI (env: DMS_SHELL_DIR)")
}
