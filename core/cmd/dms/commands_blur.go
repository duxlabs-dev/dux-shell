package main

import (
	"fmt"
	"os"

	"github.com/duxlabs-dev/dux-shell/core/internal/blur"
	"github.com/spf13/cobra"
)

var blurCmd = &cobra.Command{
	Use:   "blur",
	Short: "Background blur utilities",
}

var blurCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Check if the compositor supports background blur (ext-background-effect-v1)",
	Args:  cobra.NoArgs,
	Run:   runBlurCheck,
}

func init() {
	blurCmd.AddCommand(blurCheckCmd)
}

func runBlurCheck(cmd *cobra.Command, args []string) {
	supported, err := blur.ProbeSupport()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	switch supported {
	case true:
		fmt.Println("supported")
	default:
		fmt.Println("unsupported")
	}
}
