package main

import (
	"encoding/json"
	"fmt"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/spf13/cobra"
)

var randrCmd = &cobra.Command{
	Use:   "randr",
	Short: "Query output display information",
	Long:  "Query Wayland compositor for output names, scales, resolutions and refresh rates via zwlr-output-management",
	Run:   runRandr,
}

func init() {
	randrCmd.Flags().Bool("json", false, "Output in JSON format")
}

type randrJSON struct {
	Outputs []randrOutput `json:"outputs"`
}

func runRandr(cmd *cobra.Command, args []string) {
	outputs, err := queryRandr()
	if err != nil {
		log.Fatalf("%v", err)
	}

	jsonFlag, _ := cmd.Flags().GetBool("json")

	if jsonFlag {
		data, err := json.Marshal(randrJSON{Outputs: outputs})
		if err != nil {
			log.Fatalf("failed to marshal JSON: %v", err)
		}
		fmt.Println(string(data))
		return
	}

	for i, out := range outputs {
		if i > 0 {
			fmt.Println()
		}
		status := "enabled"
		if !out.Enabled {
			status = "disabled"
		}
		fmt.Printf("%s (%s)\n", out.Name, status)
		fmt.Printf("  Scale:      %.4g\n", out.Scale)
		fmt.Printf("  Resolution: %dx%d\n", out.Width, out.Height)
		if out.Refresh > 0 {
			fmt.Printf("  Refresh:    %.2f Hz\n", float64(out.Refresh)/1000.0)
		}
	}
}
