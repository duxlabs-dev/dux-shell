package main

import (
	"fmt"
	"os"
	"runtime/debug"

	"github.com/duxlabs-dev/dux-shell/core/internal/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/colorpicker"
	"github.com/duxlabs-dev/dux-shell/core/internal/site"
	"github.com/spf13/cobra"
)

var (
	colorOutputFmt  string
	colorAutocopy   bool
	colorNotify     bool
	colorLowercase  bool
	colorAllowMulti bool
)

var colorCmd = &cobra.Command{
	Use:   "color",
	Short: "Color utilities",
	Long: `Color utilities including picking colors from the screen.

This is the screen eyedropper CLI. To open the in-shell color modal, use:
  dms ipc call color-picker toggle

See: ` + site.Docs + "/dms/keybinds-ipc",
}

var colorPickCmd = &cobra.Command{
	Use:   "pick",
	Short: "Pick a color from the screen",
	Long: `Pick a color from anywhere on your screen using an interactive color picker.

Click on any pixel to capture its color, or press Escape to cancel.

This is the screen eyedropper CLI. To open the in-shell color modal, use:
  dms ipc call color-picker toggle

Output format flags (mutually exclusive, default: --hex):
  --hex  - Hexadecimal (#RRGGBB)
  --rgb  - RGB values (R G B)
  --hsl  - HSL values (H S% L%)
  --hsv  - HSV values (H S% V%)
  --cmyk - CMYK values (C% M% Y% K%)
  --json - JSON with all formats

Optional:
  --raw - Removes ANSI escape codes and background colors. Use this when piping to other commands

Examples:
  dms color pick                # Pick color, output as hex
  dms color pick --rgb          # Output as RGB
  dms color pick --json         # Output all formats as JSON
  dms color pick --hex -l       # Output hex in lowercase
  dms color pick -a             # Auto-copy result to clipboard
  dms color pick --allow-multiple  # Skip the one-picker-at-a-time guard`,
	Run: runColorPick,
}

func init() {
	colorPickCmd.Flags().Bool("hex", false, "Output as hexadecimal (#RRGGBB)")
	colorPickCmd.Flags().Bool("rgb", false, "Output as RGB (R G B)")
	colorPickCmd.Flags().Bool("hsl", false, "Output as HSL (H S% L%)")
	colorPickCmd.Flags().Bool("hsv", false, "Output as HSV (H S% V%)")
	colorPickCmd.Flags().Bool("cmyk", false, "Output as CMYK (C% M% Y% K%)")
	colorPickCmd.Flags().Bool("json", false, "Output all formats as JSON")
	colorPickCmd.Flags().Bool("raw", false, "Removes ANSI escape codes and background colors. Use this when piping to other commands")
	colorPickCmd.Flags().StringVarP(&colorOutputFmt, "output-format", "o", "", "Custom output format template")
	colorPickCmd.Flags().BoolVarP(&colorAutocopy, "autocopy", "a", false, "Copy result to clipboard")
	colorPickCmd.Flags().BoolVarP(&colorLowercase, "lowercase", "l", false, "Output hex in lowercase")
	colorPickCmd.Flags().BoolVar(&colorAllowMulti, "allow-multiple", false, "Open a picker even when another selection overlay is already open")

	colorPickCmd.MarkFlagsMutuallyExclusive("hex", "rgb", "hsl", "hsv", "cmyk", "json")

	colorCmd.AddCommand(colorPickCmd)
}

func runColorPick(cmd *cobra.Command, args []string) {
	format := colorpicker.FormatHex // default
	jsonOutput, _ := cmd.Flags().GetBool("json")

	if rgb, _ := cmd.Flags().GetBool("rgb"); rgb {
		format = colorpicker.FormatRGB
	} else if hsl, _ := cmd.Flags().GetBool("hsl"); hsl {
		format = colorpicker.FormatHSL
	} else if hsv, _ := cmd.Flags().GetBool("hsv"); hsv {
		format = colorpicker.FormatHSV
	} else if cmyk, _ := cmd.Flags().GetBool("cmyk"); cmyk {
		format = colorpicker.FormatCMYK
	}

	config := colorpicker.Config{
		Format:        format,
		CustomFormat:  colorOutputFmt,
		Lowercase:     colorLowercase,
		Autocopy:      colorAutocopy,
		Notify:        colorNotify,
		AllowMultiple: colorAllowMulti,
	}

	// One-shot process holding a few screen-sized buffers: skip GC cycles while it runs.
	debug.SetGCPercent(-1)
	debug.SetMemoryLimit(1 << 30)

	picker := colorpicker.New(config)
	color, err := picker.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if color == nil {
		os.Exit(0)
	}

	var output string
	if jsonOutput {
		jsonStr, err := color.ToJSON()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		output = jsonStr
	} else {
		output = color.Format(config.Format, config.Lowercase, config.CustomFormat)
	}

	if colorAutocopy {
		copyToClipboard(output)
	}

	if jsonOutput {
		fmt.Println(output)
		return
	}

	if raw, _ := cmd.Flags().GetBool("raw"); raw {
		fmt.Printf("%s\n", output)
		return
	}

	if color.IsDark() {
		fmt.Printf("\033[48;2;%d;%d;%dm\033[97m %s \033[0m\n", color.R, color.G, color.B, output)
	} else {
		fmt.Printf("\033[48;2;%d;%d;%dm\033[30m %s \033[0m\n", color.R, color.G, color.B, output)
	}
}

func copyToClipboard(text string) {
	if err := clipboard.CopyText(text); err != nil {
		fmt.Fprintln(os.Stderr, "clipboard copy failed:", err)
	}
}
