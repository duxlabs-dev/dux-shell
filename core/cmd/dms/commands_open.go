package main

import (
	"fmt"
	"mime"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/spf13/cobra"
)

var (
	openMimeType    string
	openCategories  []string
	openRequestType string
)

var openCmd = &cobra.Command{
	Use:   "open [target]",
	Short: "Open a file, URL, or resource with an application picker",
	Long: `Open a target (URL, file, or other resource) using the DMS application picker.
By default, this opens URLs with the browser picker. You can customize the behavior
with flags to handle different MIME types or application categories.

Examples:
  dms open https://example.com                    # Open URL with browser picker
  dms open file.pdf                               # Open file (MIME auto-detected)
  dms open file.pdf --mime application/pdf        # Override MIME detection
  dms open document.odt --category Office         # Open with office applications`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		runOpen(args[0])
	},
}

func init() {
	rootCmd.AddCommand(openCmd)
	openCmd.Flags().StringVar(&openMimeType, "mime", "", "MIME type for filtering applications")
	openCmd.Flags().StringSliceVar(&openCategories, "category", []string{}, "Application categories to filter (e.g., WebBrowser, Office, Graphics)")
	openCmd.Flags().StringVar(&openRequestType, "type", "url", "Request type (url, file, or custom)")
	_ = openCmd.RegisterFlagCompletionFunc("type", func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		return []string{"url", "file", "custom"}, cobra.ShellCompDirectiveNoFileComp
	})
}

func detectMimeFromPath(path string) string {
	ext := filepath.Ext(path)
	if ext == "" {
		return ""
	}
	return mime.TypeByExtension(ext)
}

func runOpen(target string) {
	actualTarget := target
	detectedMimeType := openMimeType
	detectedRequestType := openRequestType

	log.Infof("Processing target: %s", target)

	switch {
	case isScheme(target, "file://"):
		parsedURL, err := url.Parse(target)
		if err == nil {
			actualTarget = parsedURL.Path
		}
		if abs, err := filepath.Abs(actualTarget); err == nil {
			actualTarget = abs
		}
		if detectedRequestType == "url" || detectedRequestType == "" {
			detectedRequestType = "file"
		}
		if detectedMimeType == "" {
			detectedMimeType = detectMimeFromPath(actualTarget)
		}
		log.Infof("Detected file:// URI, absolute path: %s", actualTarget)

	case isScheme(target, "http://"), isScheme(target, "https://"), isScheme(target, "dms://"):
		if detectedRequestType == "" {
			detectedRequestType = "url"
		}
		log.Infof("Detected URL: %s", target)

	default:
		if _, err := os.Stat(target); err != nil {
			break
		}
		if abs, err := filepath.Abs(target); err == nil {
			actualTarget = abs
		}
		if detectedRequestType == "url" || detectedRequestType == "" {
			detectedRequestType = "file"
		}
		if detectedMimeType == "" {
			detectedMimeType = detectMimeFromPath(actualTarget)
		}
		log.Infof("Detected local file path: %s", actualTarget)
	}

	params := map[string]any{
		"target": actualTarget,
	}

	if detectedMimeType != "" {
		params["mimeType"] = detectedMimeType
	}

	if len(openCategories) > 0 {
		params["categories"] = openCategories
	}

	if detectedRequestType != "" {
		params["requestType"] = detectedRequestType
	}

	method := "apppicker.open"
	if detectedMimeType == "" && len(openCategories) == 0 && (isScheme(target, "http://") || isScheme(target, "https://") || isScheme(target, "dms://")) {
		method = "browser.open"
		params["url"] = target
	}

	req := ipc.Request{
		ID:     1,
		Method: method,
		Params: params,
	}

	log.Infof("Sending request - Method: %s, Params: %+v", method, params)

	if err := sendServerRequestFireAndForget(req); err != nil {
		fmt.Println("DMS is not running. Please start DMS first.")
		os.Exit(1)
	}

	log.Infof("Request sent successfully")
}

func isScheme(target, prefix string) bool {
	return strings.HasPrefix(target, prefix)
}
