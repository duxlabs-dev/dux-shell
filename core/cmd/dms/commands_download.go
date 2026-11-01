package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/netfetch"
	"github.com/spf13/cobra"
)

var dlOutput string
var dlUserAgent string
var dlHeaders []string
var dlTimeout int
var dlConnectTimeout int
var dlIPv4Only bool

var dlCmd = &cobra.Command{
	Use:   "dl <url>",
	Short: "Download a URL to stdout or file",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		if err := runDownload(args[0]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	},
}

func init() {
	dlCmd.Flags().StringVarP(&dlOutput, "output", "o", "", "Output file path (default: stdout)")
	dlCmd.Flags().StringVar(&dlUserAgent, "user-agent", "", "Custom User-Agent header")
	dlCmd.Flags().StringArrayVarP(&dlHeaders, "header", "H", nil, "Extra request header as 'Name: value' (repeatable)")
	dlCmd.Flags().IntVar(&dlTimeout, "timeout", 10, "Total request timeout in seconds")
	dlCmd.Flags().IntVar(&dlConnectTimeout, "connect-timeout", 5, "Connection timeout in seconds")
	dlCmd.Flags().BoolVarP(&dlIPv4Only, "ipv4", "4", false, "Force IPv4 only")
}

func parseHeaders(raw []string) (map[string]string, error) {
	if len(raw) == 0 {
		return nil, nil
	}

	headers := make(map[string]string, len(raw))
	for _, entry := range raw {
		name, value, found := strings.Cut(entry, ":")
		if !found {
			return nil, fmt.Errorf("invalid header %q: expected 'Name: value'", entry)
		}
		name = strings.TrimSpace(name)
		if name == "" {
			return nil, fmt.Errorf("invalid header %q: empty name", entry)
		}
		headers[name] = strings.TrimSpace(value)
	}
	return headers, nil
}

func runDownload(url string) error {
	headers, err := parseHeaders(dlHeaders)
	if err != nil {
		return err
	}

	opts := netfetch.Options{
		Headers:        headers,
		UserAgent:      dlUserAgent,
		Timeout:        time.Duration(dlTimeout) * time.Second,
		ConnectTimeout: time.Duration(dlConnectTimeout) * time.Second,
		IPv4Only:       dlIPv4Only,
	}

	if dlOutput == "" {
		return netfetch.ToWriter(context.Background(), url, opts, os.Stdout)
	}

	if err := netfetch.ToFile(context.Background(), url, opts, dlOutput); err != nil {
		return err
	}

	fmt.Println(dlOutput)
	return nil
}
