package main

import (
	"fmt"
	"os"

	"github.com/duxlabs-dev/dux-shell/core/internal/backup"
	"github.com/spf13/cobra"
)

var backupOutputPath string

var backupCmd = &cobra.Command{
	Use:   "backup",
	Short: "Backup and restore DMS configuration",
}

var backupCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Create a tar.gz backup of ~/.config/dms (settings, plugins, themes)",
	Args:  cobra.NoArgs,
	Run:   runBackupCreate,
}

var backupRestoreCmd = &cobra.Command{
	Use:   "restore <archive>",
	Short: "Restore a DMS configuration backup; the current configuration is moved aside first",
	Args:  cobra.ExactArgs(1),
	Run:   runBackupRestore,
}

func init() {
	backupCreateCmd.Flags().StringVarP(&backupOutputPath, "output", "o", "", "Output archive path (default dms-backup-<timestamp>.tar.gz)")
	backupCmd.AddCommand(backupCreateCmd, backupRestoreCmd)
	rootCmd.AddCommand(backupCmd)
}

func runBackupCreate(cmd *cobra.Command, args []string) {
	output := backupOutputPath
	if output == "" {
		output = backup.DefaultArchiveName()
	}

	if err := backup.Create(output); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println(output)
}

func runBackupRestore(cmd *cobra.Command, args []string) {
	previous, err := backup.Restore(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if previous != "" {
		fmt.Printf("Previous configuration moved to %s\n", previous)
	}
	fmt.Println("Restore complete. Restart the shell to apply.")
}
