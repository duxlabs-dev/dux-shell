package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	bolt "go.etcd.io/bbolt"
	_ "golang.org/x/image/bmp"
	_ "golang.org/x/image/tiff"
	_ "golang.org/x/image/webp"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/wlclipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/spf13/cobra"
)

var clipboardCmd = &cobra.Command{
	Use:     "clipboard",
	Aliases: []string{"cl"},
	Short:   "Manage clipboard",
	Long:    "Interact with the clipboard manager",
}

var clipCopyCmd = &cobra.Command{
	Use:   "copy [text]",
	Short: "Copy text to clipboard",
	Long:  "Copy text to clipboard. If no text provided, reads from stdin. Works without server.",
	Run:   runClipCopy,
}

var (
	clipCopyForeground bool
	clipCopyPasteOnce  bool
	clipCopyType       string
	clipCopyDownload   bool
	clipJSONOutput     bool
)

var clipPasteCmd = &cobra.Command{
	Use:   "paste",
	Short: "Paste text from clipboard",
	Long:  "Paste text from clipboard to stdout. Works without server.",
	Run:   runClipPaste,
}

var clipSendPasteCmd = &cobra.Command{
	Use:   "send-paste",
	Short: "Send a paste keystroke to the focused window",
	Long:  "Emulate ctrl+v (or ctrl+shift+v with --shift) via a virtual keyboard. Works without server.",
	Run:   runClipSendPaste,
}

var clipSendPasteShift bool

var clipWatchCmd = &cobra.Command{
	Use:   "watch [command]",
	Short: "Watch clipboard for changes",
	Long: `Watch clipboard for changes and optionally execute a command.
Works like wl-paste --watch. Does not require server.

If a command is provided, it will be executed each time the clipboard changes,
with the clipboard content piped to its stdin.

Examples:
  dms cl watch              # Print clipboard changes to stdout
  dms cl watch cat          # Same as above
  dms cl watch notify-send  # Send notification on clipboard change`,
	Run: runClipWatch,
}

var clipHistoryCmd = &cobra.Command{
	Use:   "history",
	Short: "Show clipboard history",
	Long:  "Show clipboard history with previews (requires server)",
	Run:   runClipHistory,
}

var clipGetCmd = &cobra.Command{
	Use:   "get <id>",
	Short: "Get clipboard entry by ID",
	Long:  "Get full clipboard entry data by ID (requires server). Use --copy to copy it to clipboard.",
	Args:  cobra.ExactArgs(1),
	Run:   runClipGet,
}

var clipGetCopy bool

var clipDeleteCmd = &cobra.Command{
	Use:   "delete <id>",
	Short: "Delete clipboard entry",
	Long:  "Delete a clipboard history entry by ID (requires server)",
	Args:  cobra.ExactArgs(1),
	Run:   runClipDelete,
}

var clipClearCmd = &cobra.Command{
	Use:   "clear",
	Short: "Clear clipboard history",
	Long:  "Clear all clipboard history (requires server)",
	Run:   runClipClear,
}

var clipWatchStore bool
var clipWatchMimes bool

var clipSearchCmd = &cobra.Command{
	Use:   "search [query]",
	Short: "Search clipboard history",
	Long:  "Search clipboard history with filters (requires server)",
	Run:   runClipSearch,
}

var (
	clipSearchLimit    int
	clipSearchOffset   int
	clipSearchMimeType string
	clipSearchImages   bool
	clipSearchText     bool
)

var clipConfigCmd = &cobra.Command{
	Use:   "config",
	Short: "Manage clipboard config",
	Long:  "Get or set clipboard configuration (requires server)",
}

var clipConfigGetCmd = &cobra.Command{
	Use:   "get",
	Short: "Get clipboard config",
	Run:   runClipConfigGet,
}

var clipConfigSetCmd = &cobra.Command{
	Use:   "set",
	Short: "Set clipboard config",
	Long: `Set clipboard configuration options.

Examples:
  dms cl config set --max-history 200
  dms cl config set --auto-clear-days 7
  dms cl config set --clear-at-startup`,
	Run: runClipConfigSet,
}

var (
	clipConfigMaxHistory     int
	clipConfigAutoClearDays  int
	clipConfigClearAtStartup bool
	clipConfigNoClearStartup bool
	clipConfigDisabled       bool
	clipConfigEnabled        bool
)

var clipExportCmd = &cobra.Command{
	Use:   "export [file]",
	Short: "Export clipboard history to JSON",
	Long:  "Export clipboard history to JSON file. If no file specified, writes to stdout.",
	Run:   runClipExport,
}

var clipImportCmd = &cobra.Command{
	Use:   "import <file>",
	Short: "Import clipboard history from JSON",
	Long:  "Import clipboard history from JSON file exported by 'dms cl export'.",
	Args:  cobra.ExactArgs(1),
	Run:   runClipImport,
}

var clipMigrateCmd = &cobra.Command{
	Use:   "cliphist-migrate [db-path]",
	Short: "Migrate from cliphist",
	Long:  "Migrate clipboard history from cliphist. Uses default cliphist path if not specified.",
	Run:   runClipMigrate,
}

var clipMigrateDelete bool

func init() {
	clipCopyCmd.Flags().BoolVarP(&clipCopyForeground, "foreground", "f", false, "Stay in foreground instead of forking")
	clipCopyCmd.Flags().BoolVarP(&clipCopyPasteOnce, "paste-once", "o", false, "Exit after first paste")
	clipCopyCmd.Flags().StringVarP(&clipCopyType, "type", "t", "text/plain;charset=utf-8", "MIME type")
	clipCopyCmd.Flags().BoolVarP(&clipCopyDownload, "download", "d", false, "Download URL as image and copy as file")

	clipWatchCmd.Flags().BoolVar(&clipJSONOutput, "json", false, "Output as JSON")
	clipHistoryCmd.Flags().BoolVar(&clipJSONOutput, "json", false, "Output as JSON")
	clipGetCmd.Flags().BoolVar(&clipJSONOutput, "json", false, "Output as JSON")
	clipGetCmd.Flags().BoolVarP(&clipGetCopy, "copy", "C", false, "Copy entry to clipboard")

	clipSearchCmd.Flags().IntVarP(&clipSearchLimit, "limit", "l", 50, "Max results")
	clipSearchCmd.Flags().IntVarP(&clipSearchOffset, "offset", "o", 0, "Result offset")
	clipSearchCmd.Flags().StringVarP(&clipSearchMimeType, "mime", "m", "", "Filter by MIME type")
	clipSearchCmd.Flags().BoolVar(&clipSearchImages, "images", false, "Only images")
	clipSearchCmd.Flags().BoolVar(&clipSearchText, "text", false, "Only text")
	clipSearchCmd.Flags().BoolVar(&clipJSONOutput, "json", false, "Output as JSON")

	clipConfigSetCmd.Flags().IntVar(&clipConfigMaxHistory, "max-history", 0, "Max history entries")
	clipConfigSetCmd.Flags().IntVar(&clipConfigAutoClearDays, "auto-clear-days", -1, "Auto-clear entries older than N days (0 to disable)")
	clipConfigSetCmd.Flags().BoolVar(&clipConfigClearAtStartup, "clear-at-startup", false, "Clear history on startup")
	clipConfigSetCmd.Flags().BoolVar(&clipConfigNoClearStartup, "no-clear-at-startup", false, "Don't clear history on startup")
	clipConfigSetCmd.Flags().BoolVar(&clipConfigDisabled, "disable", false, "Disable clipboard tracking")
	clipConfigSetCmd.Flags().BoolVar(&clipConfigEnabled, "enable", false, "Enable clipboard tracking")

	clipWatchCmd.Flags().BoolVarP(&clipWatchStore, "store", "s", false, "Store clipboard changes to history (no server required)")
	clipWatchCmd.Flags().BoolVarP(&clipWatchMimes, "mimes", "m", false, "Show all offered MIME types")

	clipMigrateCmd.Flags().BoolVar(&clipMigrateDelete, "delete", false, "Delete cliphist db after successful migration")

	clipSendPasteCmd.Flags().BoolVarP(&clipSendPasteShift, "shift", "s", false, "Send ctrl+shift+v (terminal paste)")

	clipConfigCmd.AddCommand(clipConfigGetCmd, clipConfigSetCmd)
	clipboardCmd.AddCommand(clipCopyCmd, clipPasteCmd, clipSendPasteCmd, clipWatchCmd, clipHistoryCmd, clipGetCmd, clipDeleteCmd, clipClearCmd, clipSearchCmd, clipConfigCmd, clipExportCmd, clipImportCmd, clipMigrateCmd)
}

func runClipCopy(cmd *cobra.Command, args []string) {
	var data []byte
	copyFromStdin := false

	switch {
	case len(args) > 0:
		data = []byte(args[0])
	case clipCopyDownload || clipCopyType == "__multi__":
		var err error
		data, err = io.ReadAll(os.Stdin)
		if err != nil {
			log.Fatalf("read stdin: %v", err)
		}
	default:
		copyFromStdin = true
	}

	if clipCopyDownload {
		filePath, err := downloadToTempFile(strings.TrimSpace(string(data)))
		if err != nil {
			log.Fatalf("download: %v", err)
		}
		if err := copyFileToClipboard(filePath); err != nil {
			log.Fatalf("copy file: %v", err)
		}
		fmt.Printf("Downloaded and copied: %s\n", filePath)
		return
	}

	if clipCopyType == "__multi__" {
		offers, err := parseMultiOffers(data)
		if err != nil {
			log.Fatalf("parse multi offers: %v", err)
		}
		if err := clipboard.CopyMulti(offers, true, clipCopyPasteOnce); err != nil {
			log.Fatalf("copy multi: %v", err)
		}
		return
	}

	if copyFromStdin {
		if err := clipboard.CopyReader(os.Stdin, clipCopyType, clipCopyForeground, clipCopyPasteOnce); err != nil {
			log.Fatalf("copy: %v", err)
		}
		return
	}

	if err := clipboard.CopyOpts(data, clipCopyType, clipCopyForeground, clipCopyPasteOnce); err != nil {
		log.Fatalf("copy: %v", err)
	}
}

func parseMultiOffers(data []byte) ([]wlclipboard.Offer, error) {
	var offers []wlclipboard.Offer
	pos := 0

	for pos < len(data) {
		mimeEnd := bytes.IndexByte(data[pos:], 0)
		if mimeEnd == -1 {
			break
		}
		mimeType := string(data[pos : pos+mimeEnd])
		pos += mimeEnd + 1

		lenEnd := bytes.IndexByte(data[pos:], 0)
		if lenEnd == -1 {
			break
		}
		dataLen, err := strconv.Atoi(string(data[pos : pos+lenEnd]))
		if err != nil {
			return nil, fmt.Errorf("parse length: %w", err)
		}
		pos += lenEnd + 1

		if pos+dataLen > len(data) {
			return nil, fmt.Errorf("data truncated")
		}
		offerData := data[pos : pos+dataLen]
		pos += dataLen

		offers = append(offers, wlclipboard.Offer{MimeType: mimeType, Data: offerData})
	}

	return offers, nil
}

func runClipPaste(cmd *cobra.Command, args []string) {
	data, _, err := wlclipboard.Paste()
	if err != nil {
		log.Fatalf("paste: %v", err)
	}
	os.Stdout.Write(data)
}

func runClipSendPaste(cmd *cobra.Command, args []string) {
	if err := clipboard.SendPasteKeystroke(clipSendPasteShift); err != nil {
		log.Fatalf("send-paste: %v", err)
	}
}

func runClipWatch(cmd *cobra.Command, args []string) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		cancel()
	}()

	switch {
	case len(args) > 0:
		if err := wlclipboard.Watch(ctx, func(data []byte, mimeType string) {
			runCommand(args, data)
		}); err != nil && err != context.Canceled {
			log.Fatalf("Watch error: %v", err)
		}
	case clipWatchStore:
		if err := wlclipboard.Watch(ctx, func(data []byte, mimeType string) {
			if err := clipboard.Store(data, mimeType); err != nil {
				log.Errorf("store: %v", err)
			}
		}); err != nil && err != context.Canceled {
			log.Fatalf("Watch error: %v", err)
		}
	case clipWatchMimes:
		if err := clipboard.WatchAll(ctx, func(data []byte, mimeType string, allMimes []string) {
			if clipJSONOutput {
				out := map[string]any{
					"data":      string(data),
					"mimeType":  mimeType,
					"mimeTypes": allMimes,
					"timestamp": time.Now().Format(time.RFC3339),
					"size":      len(data),
				}
				j, _ := json.Marshal(out)
				fmt.Println(string(j))
				return
			}
			fmt.Printf("=== Clipboard Change ===\n")
			fmt.Printf("Selected: %s\n", mimeType)
			fmt.Printf("All MIME types:\n")
			for _, m := range allMimes {
				fmt.Printf("  - %s\n", m)
			}
			fmt.Printf("Size: %d bytes\n\n", len(data))
		}); err != nil && err != context.Canceled {
			log.Fatalf("Watch error: %v", err)
		}
	case clipJSONOutput:
		if err := wlclipboard.Watch(ctx, func(data []byte, mimeType string) {
			out := map[string]any{
				"data":      string(data),
				"mimeType":  mimeType,
				"timestamp": time.Now().Format(time.RFC3339),
				"size":      len(data),
			}
			j, _ := json.Marshal(out)
			fmt.Println(string(j))
		}); err != nil && err != context.Canceled {
			log.Fatalf("Watch error: %v", err)
		}
	default:
		if err := wlclipboard.Watch(ctx, func(data []byte, mimeType string) {
			os.Stdout.Write(data)
			os.Stdout.WriteString("\n")
		}); err != nil && err != context.Canceled {
			log.Fatalf("Watch error: %v", err)
		}
	}
}

func runCommand(args []string, stdin []byte) {
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if len(stdin) == 0 {
		cmd.Run()
		return
	}

	r, w, err := os.Pipe()
	if err != nil {
		cmd.Run()
		return
	}

	cmd.Stdin = r
	go func() {
		w.Write(stdin)
		w.Close()
	}()
	cmd.Run()
}

func runClipHistory(cmd *cobra.Command, args []string) {
	req := ipc.Request{
		ID:     1,
		Method: "clipboard.getHistory",
	}

	resp, err := sendServerRequest(req)
	if err != nil {
		log.Fatalf("Failed to get clipboard history: %v", err)
	}

	if resp.Error != "" {
		log.Fatalf("Error: %s", resp.Error)
	}

	if resp.Result == nil {
		if clipJSONOutput {
			fmt.Println("[]")
		} else {
			fmt.Println("No clipboard history")
		}
		return
	}

	historyList, ok := (*resp.Result).([]any)
	if !ok {
		log.Fatal("Invalid response format")
	}

	if clipJSONOutput {
		out, _ := json.MarshalIndent(historyList, "", "  ")
		fmt.Println(string(out))
		return
	}

	if len(historyList) == 0 {
		fmt.Println("No clipboard history")
		return
	}

	fmt.Println("Clipboard History:")
	fmt.Println()

	for _, item := range historyList {
		entry, ok := item.(map[string]any)
		if !ok {
			continue
		}

		id := uint64(entry["id"].(float64))
		preview := entry["preview"].(string)
		timestamp := entry["timestamp"].(string)
		isImage := entry["isImage"].(bool)

		typeStr := "text"
		if isImage {
			typeStr = "image"
		}

		fmt.Printf("ID: %d | %s | %s\n", id, typeStr, timestamp)
		fmt.Printf("  %s\n", preview)
		fmt.Println()
	}
}

func runClipGet(cmd *cobra.Command, args []string) {
	id, err := strconv.ParseUint(args[0], 10, 64)
	if err != nil {
		log.Fatalf("Invalid ID: %v", err)
	}

	if clipGetCopy {
		req := ipc.Request{
			ID:     1,
			Method: "clipboard.copyEntry",
			Params: map[string]any{"id": id},
		}

		resp, err := sendServerRequest(req)
		if err != nil {
			log.Fatalf("Failed to copy clipboard entry: %v", err)
		}
		if resp.Error != "" {
			log.Fatalf("Error: %s", resp.Error)
		}

		fmt.Printf("Copied entry %d to clipboard\n", id)
		return
	}

	req := ipc.Request{
		ID:     1,
		Method: "clipboard.getEntry",
		Params: map[string]any{
			"id": id,
		},
	}

	resp, err := sendServerRequest(req)
	if err != nil {
		log.Fatalf("Failed to get clipboard entry: %v", err)
	}

	if resp.Error != "" {
		log.Fatalf("Error: %s", resp.Error)
	}

	if resp.Result == nil {
		log.Fatal("Entry not found")
	}

	entry, ok := (*resp.Result).(map[string]any)
	if !ok {
		log.Fatal("Invalid response format")
	}

	switch {
	case clipJSONOutput:
		output, _ := json.MarshalIndent(entry, "", "  ")
		fmt.Println(string(output))
	default:
		if data, ok := entry["data"].(string); ok {
			fmt.Print(data)
		} else {
			output, _ := json.MarshalIndent(entry, "", "  ")
			fmt.Println(string(output))
		}
	}
}

func runClipDelete(cmd *cobra.Command, args []string) {
	id, err := strconv.ParseUint(args[0], 10, 64)
	if err != nil {
		log.Fatalf("Invalid ID: %v", err)
	}

	req := ipc.Request{
		ID:     1,
		Method: "clipboard.deleteEntry",
		Params: map[string]any{
			"id": id,
		},
	}

	resp, err := sendServerRequest(req)
	if err != nil {
		log.Fatalf("Failed to delete clipboard entry: %v", err)
	}

	if resp.Error != "" {
		log.Fatalf("Error: %s", resp.Error)
	}

	fmt.Printf("Deleted entry %d\n", id)
}

func runClipClear(cmd *cobra.Command, args []string) {
	req := ipc.Request{
		ID:     1,
		Method: "clipboard.clearHistory",
	}

	resp, err := sendServerRequest(req)
	if err != nil {
		log.Fatalf("Failed to clear clipboard history: %v", err)
	}

	if resp.Error != "" {
		log.Fatalf("Error: %s", resp.Error)
	}

	fmt.Println("Clipboard history cleared")
}

func runClipSearch(cmd *cobra.Command, args []string) {
	params := map[string]any{
		"limit":  clipSearchLimit,
		"offset": clipSearchOffset,
	}

	if len(args) > 0 {
		params["query"] = args[0]
	}
	if clipSearchMimeType != "" {
		params["mimeType"] = clipSearchMimeType
	}
	if clipSearchImages {
		params["isImage"] = true
	} else if clipSearchText {
		params["isImage"] = false
	}

	req := ipc.Request{
		ID:     1,
		Method: "clipboard.search",
		Params: params,
	}

	resp, err := sendServerRequest(req)
	if err != nil {
		log.Fatalf("Failed to search clipboard: %v", err)
	}

	if resp.Error != "" {
		log.Fatalf("Error: %s", resp.Error)
	}

	if resp.Result == nil {
		log.Fatal("No results")
	}

	result, ok := (*resp.Result).(map[string]any)
	if !ok {
		log.Fatal("Invalid response format")
	}

	if clipJSONOutput {
		out, _ := json.MarshalIndent(result, "", "  ")
		fmt.Println(string(out))
		return
	}

	entries, _ := result["entries"].([]any)
	total := int(result["total"].(float64))
	hasMore := result["hasMore"].(bool)

	if len(entries) == 0 {
		fmt.Println("No results found")
		return
	}

	fmt.Printf("Results: %d of %d\n\n", len(entries), total)

	for _, item := range entries {
		entry, ok := item.(map[string]any)
		if !ok {
			continue
		}

		id := uint64(entry["id"].(float64))
		preview := entry["preview"].(string)
		timestamp := entry["timestamp"].(string)
		isImage := entry["isImage"].(bool)

		typeStr := "text"
		if isImage {
			typeStr = "image"
		}

		fmt.Printf("ID: %d | %s | %s\n", id, typeStr, timestamp)
		fmt.Printf("  %s\n\n", preview)
	}

	if hasMore {
		fmt.Printf("Use --offset %d to see more results\n", clipSearchOffset+clipSearchLimit)
	}
}

func runClipConfigGet(cmd *cobra.Command, args []string) {
	req := ipc.Request{
		ID:     1,
		Method: "clipboard.getConfig",
	}

	resp, err := sendServerRequest(req)
	if err != nil {
		log.Fatalf("Failed to get config: %v", err)
	}

	if resp.Error != "" {
		log.Fatalf("Error: %s", resp.Error)
	}

	if resp.Result == nil {
		log.Fatal("No config returned")
	}

	cfg, ok := (*resp.Result).(map[string]any)
	if !ok {
		log.Fatal("Invalid response format")
	}

	output, _ := json.MarshalIndent(cfg, "", "  ")
	fmt.Println(string(output))
}

func runClipConfigSet(cmd *cobra.Command, args []string) {
	params := map[string]any{}

	if cmd.Flags().Changed("max-history") {
		params["maxHistory"] = clipConfigMaxHistory
	}
	if cmd.Flags().Changed("auto-clear-days") {
		params["autoClearDays"] = clipConfigAutoClearDays
	}
	if clipConfigClearAtStartup {
		params["clearAtStartup"] = true
	}
	if clipConfigNoClearStartup {
		params["clearAtStartup"] = false
	}
	if clipConfigDisabled {
		params["disabled"] = true
	}
	if clipConfigEnabled {
		params["disabled"] = false
	}

	if len(params) == 0 {
		fmt.Println("No config options specified")
		return
	}

	req := ipc.Request{
		ID:     1,
		Method: "clipboard.setConfig",
		Params: params,
	}

	resp, err := sendServerRequest(req)
	if err != nil {
		log.Fatalf("Failed to set config: %v", err)
	}

	if resp.Error != "" {
		log.Fatalf("Error: %s", resp.Error)
	}

	fmt.Println("Config updated")
}

func runClipExport(cmd *cobra.Command, args []string) {
	req := ipc.Request{
		ID:     1,
		Method: "clipboard.getHistory",
	}

	resp, err := sendServerRequest(req)
	if err != nil {
		log.Fatalf("Failed to get clipboard history: %v", err)
	}
	if resp.Error != "" {
		log.Fatalf("Error: %s", resp.Error)
	}
	if resp.Result == nil {
		log.Fatal("No clipboard history")
	}

	out, err := json.MarshalIndent(resp.Result, "", "  ")
	if err != nil {
		log.Fatalf("Failed to marshal: %v", err)
	}

	if len(args) == 0 {
		fmt.Println(string(out))
		return
	}

	if err := os.WriteFile(args[0], out, 0o644); err != nil {
		log.Fatalf("Failed to write file: %v", err)
	}
	fmt.Printf("Exported to %s\n", args[0])
}

func runClipImport(cmd *cobra.Command, args []string) {
	data, err := os.ReadFile(args[0])
	if err != nil {
		log.Fatalf("Failed to read file: %v", err)
	}

	var entries []map[string]any
	if err := json.Unmarshal(data, &entries); err != nil {
		log.Fatalf("Failed to parse JSON: %v", err)
	}

	var imported int
	for _, entry := range entries {
		dataStr, ok := entry["data"].(string)
		if !ok {
			continue
		}
		mimeType, _ := entry["mimeType"].(string)
		if mimeType == "" {
			mimeType = "text/plain"
		}

		var entryData []byte
		if decoded, err := base64.StdEncoding.DecodeString(dataStr); err == nil {
			entryData = decoded
		} else {
			entryData = []byte(dataStr)
		}

		if err := clipboard.Store(entryData, mimeType); err != nil {
			log.Errorf("Failed to store entry: %v", err)
			continue
		}
		imported++
	}

	fmt.Printf("Imported %d entries\n", imported)
}

func runClipMigrate(cmd *cobra.Command, args []string) {
	dbPath := getCliphistPath()
	if len(args) > 0 {
		dbPath = args[0]
	}

	if _, err := os.Stat(dbPath); err != nil {
		log.Fatalf("Cliphist db not found: %s", dbPath)
	}

	db, err := bolt.Open(dbPath, 0o644, &bolt.Options{
		ReadOnly: true,
		Timeout:  1 * time.Second,
	})
	if err != nil {
		log.Fatalf("Failed to open cliphist db: %v", err)
	}
	defer db.Close()

	var migrated int
	err = db.View(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("b"))
		if b == nil {
			return fmt.Errorf("cliphist bucket not found")
		}

		c := b.Cursor()
		for k, v := c.First(); k != nil; k, v = c.Next() {
			if len(v) == 0 {
				continue
			}

			mimeType := detectMimeType(v)
			if err := clipboard.Store(v, mimeType); err != nil {
				log.Errorf("Failed to store entry %d: %v", btoi(k), err)
				continue
			}
			migrated++
		}
		return nil
	})
	if err != nil {
		log.Fatalf("Migration failed: %v", err)
	}

	fmt.Printf("Migrated %d entries from cliphist\n", migrated)

	if !clipMigrateDelete {
		return
	}

	db.Close()
	if err := os.Remove(dbPath); err != nil {
		log.Errorf("Failed to delete cliphist db: %v", err)
		return
	}
	os.Remove(filepath.Dir(dbPath))
	fmt.Println("Deleted cliphist db")
}

func getCliphistPath() string {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		return filepath.Join(os.Getenv("HOME"), ".cache", "cliphist", "db")
	}
	return filepath.Join(cacheDir, "cliphist", "db")
}

func detectMimeType(data []byte) string {
	if _, _, err := image.DecodeConfig(bytes.NewReader(data)); err == nil {
		return "image/png"
	}
	return "text/plain"
}

func btoi(v []byte) uint64 {
	return binary.BigEndian.Uint64(v)
}

func downloadToTempFile(rawURL string) (string, error) {
	if !strings.HasPrefix(rawURL, "http://") && !strings.HasPrefix(rawURL, "https://") {
		return "", fmt.Errorf("invalid URL: %s", rawURL)
	}

	parsedURL, err := url.Parse(rawURL)
	if err != nil {
		return "", fmt.Errorf("parse URL: %w", err)
	}

	ext := filepath.Ext(parsedURL.Path)
	if ext == "" {
		ext = ".png"
	}

	client := &http.Client{Timeout: 30 * time.Second}

	var data []byte
	var contentType string
	var lastErr error

	for attempt := range 3 {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt) * 500 * time.Millisecond)
		}

		req, err := http.NewRequest("GET", rawURL, nil)
		if err != nil {
			lastErr = fmt.Errorf("create request: %w", err)
			continue
		}
		req.Header.Set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
		req.Header.Set("Accept", "image/*,video/*,*/*")

		resp, err := client.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("download (attempt %d): %w", attempt+1, err)
			continue
		}

		if resp.StatusCode != http.StatusOK {
			resp.Body.Close()
			lastErr = fmt.Errorf("download failed (attempt %d): status %d", attempt+1, resp.StatusCode)
			continue
		}

		data, err = io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			lastErr = fmt.Errorf("read response (attempt %d): %w", attempt+1, err)
			continue
		}

		contentType = resp.Header.Get("Content-Type")
		if idx := strings.Index(contentType, ";"); idx != -1 {
			contentType = strings.TrimSpace(contentType[:idx])
		}

		lastErr = nil
		break
	}

	if lastErr != nil {
		return "", lastErr
	}

	if len(data) == 0 {
		return "", fmt.Errorf("downloaded empty file")
	}

	if !strings.HasPrefix(contentType, "image/") && !strings.HasPrefix(contentType, "video/") {
		if _, _, err := image.DecodeConfig(bytes.NewReader(data)); err != nil {
			return "", fmt.Errorf("not a valid media file (content-type: %s)", contentType)
		}
	}

	cacheDir, err := os.UserCacheDir()
	if err != nil {
		cacheDir = "/tmp"
	}
	clipDir := filepath.Join(cacheDir, "dms", "clipboard")
	if err := os.MkdirAll(clipDir, 0o755); err != nil {
		return "", fmt.Errorf("create cache dir: %w", err)
	}

	filePath := filepath.Join(clipDir, fmt.Sprintf("%d%s", time.Now().UnixNano(), ext))
	if err := os.WriteFile(filePath, data, 0o644); err != nil {
		return "", fmt.Errorf("write file: %w", err)
	}

	return filePath, nil
}

// copyFileToClipboard copies through the server so the entry lands in
// history, and serves the same offers itself when the server is down or
// refuses (e.g. file over the history size limit).
func copyFileToClipboard(filePath string) error {
	if abs, err := filepath.Abs(filePath); err == nil {
		filePath = abs
	}
	resp, ok := tryServerRequest(ipc.Request{
		ID:     1,
		Method: "clipboard.copyFile",
		Params: map[string]any{"filePath": filePath},
	})
	if ok && resp.Error == "" {
		return nil
	}

	data, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("read file: %w", err)
	}
	return clipboard.CopyMulti(clipboard.FileOffers(filePath, filePath, data), false, false)
}
