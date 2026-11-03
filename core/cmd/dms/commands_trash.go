package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/duxlabs-dev/dux-go/trash"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/spf13/cobra"
)

var trashCmd = &cobra.Command{
	Use:   "trash",
	Short: "Manage the user's trash (XDG Trash spec 1.0)",
}

var trashPutCmd = &cobra.Command{
	Use:   "put <path...>",
	Short: "Move files or directories into the trash",
	Args:  cobra.MinimumNArgs(1),
	Run:   runTrashPut,
}

var trashListCmd = &cobra.Command{
	Use:   "list",
	Short: "List trashed items across all known trash directories",
	Run:   runTrashList,
}

var trashCountCmd = &cobra.Command{
	Use:   "count",
	Short: "Print the total number of trashed items",
	Run:   runTrashCount,
}

var trashEmptyCmd = &cobra.Command{
	Use:   "empty",
	Short: "Permanently delete every trashed item",
	Run:   runTrashEmpty,
}

var trashRestoreCmd = &cobra.Command{
	Use:   "restore <name>",
	Short: "Restore a trashed item to its original location",
	Args:  cobra.ExactArgs(1),
	Run:   runTrashRestore,
}

var (
	trashJSONOutput bool
	trashRestoreDir string
)

func init() {
	trashListCmd.Flags().BoolVar(&trashJSONOutput, "json", false, "Output as JSON")
	trashRestoreCmd.Flags().StringVar(&trashRestoreDir, "trash-dir", "", "Trash directory containing the item (default: home trash)")
	trashCmd.AddCommand(trashPutCmd, trashListCmd, trashCountCmd, trashEmptyCmd, trashRestoreCmd)
}

func runTrashPut(cmd *cobra.Command, args []string) {
	var failed int
	for _, p := range args {
		if _, err := trash.Put(p); err != nil {
			log.Errorf("trash %s: %v", p, err)
			failed++
			continue
		}
		fmt.Println(p)
	}
	if failed > 0 {
		os.Exit(1)
	}
}

func runTrashList(cmd *cobra.Command, args []string) {
	entries, err := trash.List()
	if err != nil {
		log.Fatalf("list trash: %v", err)
	}

	if trashJSONOutput {
		if entries == nil {
			entries = []trash.Entry{}
		}
		out, _ := json.MarshalIndent(entries, "", "  ")
		fmt.Println(string(out))
		return
	}

	if len(entries) == 0 {
		fmt.Println("Trash is empty")
		return
	}
	for _, e := range entries {
		marker := "F"
		if e.IsDir {
			marker = "D"
		}
		fmt.Printf("%s  %s  %s  %s\n", marker, e.DeletionDate, e.Name, e.OriginalPath)
	}
}

func runTrashCount(cmd *cobra.Command, args []string) {
	n, err := trash.Count()
	if err != nil {
		log.Fatalf("count trash: %v", err)
	}
	fmt.Println(n)
}

func runTrashEmpty(cmd *cobra.Command, args []string) {
	if err := trash.Empty(); err != nil {
		log.Fatalf("empty trash: %v", err)
	}
}

func runTrashRestore(cmd *cobra.Command, args []string) {
	if err := trash.Restore(args[0], trashRestoreDir); err != nil {
		log.Fatalf("restore: %v", err)
	}
}
