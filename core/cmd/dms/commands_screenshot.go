package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime/debug"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/notify"
	"github.com/duxlabs-dev/dux-shell/core/internal/qsipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/screenshot"
	"github.com/spf13/cobra"
)

var (
	ssOutputName  string
	ssSeat        string
	ssCursor      string
	ssFormat      string
	ssQuality     int
	ssOutputDir   string
	ssFilename    string
	ssNoClipboard bool
	ssNoFile      bool
	ssNoNotify    bool
	ssNoConfirm   bool
	ssReset       bool
	ssStdout      bool
	ssJSON        bool
	ssGeometry    bool
	ssAllowMulti  bool
	ssHUD         string
)

type screenshotMetadata struct {
	Status string  `json:"status"`
	Path   string  `json:"path,omitempty"`
	X      *int    `json:"x,omitempty"`
	Y      *int    `json:"y,omitempty"`
	Width  int     `json:"width,omitempty"`
	Height int     `json:"height,omitempty"`
	Scale  float64 `json:"scale,omitempty"`
	Mime   string  `json:"mime,omitempty"`
	Error  string  `json:"error,omitempty"`
}

var screenshotCmd = &cobra.Command{
	Use:   "screenshot",
	Short: "Capture screenshots",
	Long: `Capture screenshots from Wayland displays.

Modes:
  region      - Select a region interactively (default)
  full        - Capture the focused output
  all         - Capture all outputs combined
  output      - Capture a specific output by name
  window      - Capture the focused window (Hyprland/Mango/niri/Aqueous)
  last        - Capture the last selected region
  scroll      - Select a region, then scroll to capture a stitched tall image

Output format (--format):
  png         - PNG format (default)
  jpg/jpeg    - JPEG format
  ppm         - PPM format

Examples:
  dms screenshot                     # Region select, save file + clipboard
  dms screenshot full                # Full screen of focused output
  dms screenshot all                 # All screens combined
  dms screenshot output -o DP-1      # Specific output
  dms screenshot window              # Focused window
  dms screenshot last                # Last region (pre-selected)
  dms screenshot --reset             # Reset last region pre-selection
  dms screenshot --no-clipboard      # Save file only
  dms screenshot --no-file           # Clipboard only
  dms screenshot --no-confirm        # Region capture on mouse release
  dms screenshot --cursor=on         # Include cursor
  dms screenshot -f jpg -q 85        # JPEG with quality 85
  dms screenshot --json              # Print capture metadata as JSON
  dms screenshot --allow-multiple    # Skip the one-selector-at-a-time guard
  dms screenshot -g                  # Print selected region geometry (X,Y WxH) to stdout
  dms screenshot scroll              # Scroll capture, Enter finishes / Esc cancels
  dms screenshot scroll --interval 250`,
}

var ssRegionCmd = &cobra.Command{
	Use:   "region",
	Short: "Select a region interactively",
	Run:   runScreenshotRegion,
}

var ssFullCmd = &cobra.Command{
	Use:   "full",
	Short: "Capture the focused output",
	Run:   runScreenshotFull,
}

var ssAllCmd = &cobra.Command{
	Use:   "all",
	Short: "Capture all outputs combined",
	Run:   runScreenshotAll,
}

var ssOutputCmd = &cobra.Command{
	Use:   "output",
	Short: "Capture a specific output",
	Run:   runScreenshotOutput,
}

var ssLastCmd = &cobra.Command{
	Use:   "last",
	Short: "Capture the last selected region",
	Long: `Capture the previously selected region without interactive selection.
If no previous region exists, falls back to interactive selection.`,
	Run: runScreenshotLast,
}

var ssWindowCmd = &cobra.Command{
	Use:   "window",
	Short: "Capture the focused window",
	Long:  `Capture the currently focused window. Supported on Hyprland, Mango, niri, and Aqueous. Aqueous requires a running DMS shell and crops the output including borders and overlapping windows.`,
	Run:   runScreenshotWindow,
}

var ssScrollInterval int

var ssScrollCmd = &cobra.Command{
	Use:   "scroll",
	Short: "Capture a scrolling region stitched into one tall image",
	Long: `Select a region, then scroll the content beneath with the mouse wheel or
touchpad while frames are captured and stitched vertically. Finish with the
on-screen done button; cancel with the cancel button. Enter and Esc work
everywhere: most compositors hold the keyboard on the overlay (keyboard
scrolling does not reach the app there), while Hyprland leaves the keyboard
with the application — keyboard scrolling works, and Enter/Esc act through
temporary global binds for the session. The cursor is never included in
frames.

Frames are stitched continuously while scrolling, and revisited content is
never duplicated — scrolling up past the starting point extends the image
upward. Content jumped past faster than capture can follow is skipped rather
than stitched incorrectly.

Rotated outputs are not supported.`,
	Run: runScreenshotScroll,
}

var ssListCmd = &cobra.Command{
	Use:   "list",
	Short: "List available outputs",
	Run:   runScreenshotList,
}

var notifyActionCmd = &cobra.Command{
	Use:    "notify-action",
	Hidden: true,
	Run: func(cmd *cobra.Command, args []string) {
		notify.RunActionListener(args)
	},
}

func init() {
	screenshotCmd.PersistentFlags().StringVarP(&ssOutputName, "output", "o", "", "Output name for 'output' mode")
	screenshotCmd.PersistentFlags().StringVar(&ssSeat, "seat", "", "Seat for Aqueous capture (required with multiple seats)")
	screenshotCmd.PersistentFlags().StringVar(&ssCursor, "cursor", "off", "Include cursor in screenshot (on/off)")
	screenshotCmd.PersistentFlags().StringVarP(&ssFormat, "format", "f", "png", "Output format (png, jpg, ppm)")
	screenshotCmd.PersistentFlags().IntVarP(&ssQuality, "quality", "q", 90, "JPEG quality (1-100)")
	screenshotCmd.PersistentFlags().StringVarP(&ssOutputDir, "dir", "d", "", "Output directory")
	screenshotCmd.PersistentFlags().StringVar(&ssFilename, "filename", "", "Output filename (auto-generated if empty)")
	screenshotCmd.PersistentFlags().BoolVar(&ssNoClipboard, "no-clipboard", false, "Don't copy to clipboard")
	screenshotCmd.PersistentFlags().BoolVar(&ssNoFile, "no-file", false, "Don't save to file")
	screenshotCmd.PersistentFlags().BoolVar(&ssNoNotify, "no-notify", false, "Don't show notification")
	screenshotCmd.PersistentFlags().BoolVar(&ssNoConfirm, "no-confirm", false, "Region mode: capture on mouse release without Enter/Space confirmation")
	screenshotCmd.PersistentFlags().BoolVar(&ssReset, "reset", false, "Reset saved last-region preselection before capturing")
	screenshotCmd.PersistentFlags().BoolVar(&ssStdout, "stdout", false, "Output image to stdout (for piping to swappy, etc.)")
	screenshotCmd.PersistentFlags().BoolVar(&ssJSON, "json", false, "Print capture metadata as JSON")
	screenshotCmd.PersistentFlags().BoolVarP(&ssGeometry, "geometry", "g", false, "Print selected region geometry (X,Y WxH) to stdout without capturing an image")
	screenshotCmd.PersistentFlags().BoolVar(&ssAllowMulti, "allow-multiple", false, "Open a selector even when another one is already open")
	screenshotCmd.PersistentFlags().StringVar(&ssHUD, "hud", "auto", "HUD overlay scale in region selector (auto, off/0, or integer scale 1-4)")

	ssScrollCmd.Flags().IntVar(&ssScrollInterval, "interval", 45, "Capture interval in milliseconds (30-1000)")

	screenshotCmd.AddCommand(ssRegionCmd)
	screenshotCmd.AddCommand(ssScrollCmd)
	screenshotCmd.AddCommand(ssFullCmd)
	screenshotCmd.AddCommand(ssAllCmd)
	screenshotCmd.AddCommand(ssOutputCmd)
	screenshotCmd.AddCommand(ssLastCmd)
	screenshotCmd.AddCommand(ssWindowCmd)
	screenshotCmd.AddCommand(ssListCmd)

	screenshotCmd.Run = runScreenshotRegion
}

func getScreenshotConfig(mode screenshot.Mode) screenshot.Config {
	config := screenshot.DefaultConfig()
	config.Mode = mode
	config.OutputName = ssOutputName
	config.Seat = ssSeat
	if strings.EqualFold(ssCursor, "on") {
		config.Cursor = screenshot.CursorOn
	}
	config.Clipboard = !ssNoClipboard
	config.SaveFile = !ssNoFile
	config.Notify = !ssNoNotify
	config.NoConfirm = ssNoConfirm
	config.Reset = ssReset
	config.Stdout = ssStdout
	config.Geometry = ssGeometry
	config.AllowMultiple = ssAllowMulti
	config.HUD = ssHUD

	if ssGeometry {
		config.Clipboard = false
		config.SaveFile = false
		config.Notify = false
	}

	if ssOutputDir != "" {
		config.OutputDir = ssOutputDir
	}
	if ssFilename != "" {
		config.Filename = ssFilename
	}

	switch strings.ToLower(ssFormat) {
	case "jpg", "jpeg":
		config.Format = screenshot.FormatJPEG
	case "ppm":
		config.Format = screenshot.FormatPPM
	default:
		config.Format = screenshot.FormatPNG
	}

	if ssQuality < 1 {
		ssQuality = 1
	}
	if ssQuality > 100 {
		ssQuality = 100
	}
	config.Quality = ssQuality

	if mode == screenshot.ModeRegion || mode == screenshot.ModeScroll {
		config.SnapTargets = fetchShellSnapTargets()
	}

	return config
}

func fetchShellSnapTargets() []screenshot.SnapTarget {
	pid, ok := shellApp.SessionPID()
	if !ok {
		return nil
	}
	res, isVoid, err := qsipc.Call(qsipc.SocketPathForPID(pid), "screenshot", "getSurfaces", nil)
	if err != nil || isVoid || res == "" {
		return nil
	}
	var targets []screenshot.SnapTarget
	if err := json.Unmarshal([]byte(res), &targets); err != nil {
		return nil
	}
	return targets
}

// setPopoutScreenshotMode toggles the shell handshake so popouts drop their keyboard grab during region select.
// Best-effort and not awaited: qs takes ~20ms to come up, longer than the selector needs to show.
func setPopoutScreenshotMode(begin bool) {
	fn := "end"
	if begin {
		fn = "begin"
	}
	if pid, ok := shellApp.SessionPID(); ok {
		_, _, _ = qsipc.Call(qsipc.SocketPathForPID(pid), "screenshot", fn, nil)
		return
	}
	cmdArgs := []string{"ipc"}
	if err := shellApp.ResolveConfig(nil, nil); err != nil {
		return
	}
	if qsHasAnyDisplay() {
		cmdArgs = append(cmdArgs, "--any-display")
	}
	cmdArgs = append(cmdArgs, "-p", shellApp.ConfigPath())
	cmdArgs = append(cmdArgs, "call", "screenshot", fn)
	_ = exec.Command("qs", cmdArgs...).Start()
}

func writeScreenshotJSON(meta screenshotMetadata) {
	_ = json.NewEncoder(os.Stdout).Encode(meta)
}

func exitScreenshotError(context string, err error) {
	if ssJSON {
		writeScreenshotJSON(screenshotMetadata{Status: "error", Error: err.Error()})
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "Error%s: %v\n", context, err)
	os.Exit(1)
}

func formatMime(format screenshot.Format) string {
	switch format {
	case screenshot.FormatJPEG:
		return "image/jpeg"
	case screenshot.FormatPPM:
		return "image/x-portable-pixmap"
	default:
		return "image/png"
	}
}

func runScreenshot(config screenshot.Config) {
	if ssJSON && config.Stdout {
		fmt.Fprintln(os.Stderr, "Error: --json cannot be combined with --stdout")
		os.Exit(1)
	}
	if config.Geometry {
		if config.Stdout {
			fmt.Fprintln(os.Stderr, "Error: --geometry cannot be combined with --stdout")
			os.Exit(1)
		}
		if config.Mode == screenshot.ModeScroll {
			fmt.Fprintln(os.Stderr, "Error: --geometry cannot be combined with scroll mode")
			os.Exit(1)
		}
	}

	// Short-lived process over a few tens of MB: let the heap grow instead of paying GC cycles mid-capture.
	debug.SetGCPercent(-1)
	debug.SetMemoryLimit(1 << 30)

	// Region select needs the keyboard; drop popout grabs for its duration.
	config.SelectorHook = setPopoutScreenshotMode
	result, err := screenshot.New(config).Run()
	if err != nil {
		exitScreenshotError("", err)
	}

	if result == nil {
		if ssJSON {
			writeScreenshotJSON(screenshotMetadata{Status: "aborted", Error: "User cancelled selection"})
		}
		if config.Geometry {
			os.Exit(1)
		}
		os.Exit(0)
	}

	if config.Geometry {
		if ssJSON {
			x := int(result.Region.X)
			y := int(result.Region.Y)
			writeScreenshotJSON(screenshotMetadata{
				Status: "success",
				X:      &x,
				Y:      &y,
				Width:  int(result.Region.Width),
				Height: int(result.Region.Height),
			})
		} else {
			fmt.Println(result.Region.GeometryString())
		}
		os.Exit(0)
	}

	if result.Buffer != nil {
		defer result.Buffer.Close()

		if result.YInverted {
			result.Buffer.FlipVertical()
		}
	}

	if result.CopyOnly {
		config.SaveFile = false
		config.Clipboard = true
		config.Stdout = false
	}

	if config.Stdout {
		if err := writeImageToStdout(result.Buffer, config.Format, config.Quality, result.Format, result.CICP); err != nil {
			exitScreenshotError(" writing to stdout", err)
		}
		return
	}

	var filePath string

	if config.SaveFile {
		outputDir := config.OutputDir
		if outputDir == "" {
			outputDir = screenshot.GetOutputDir()
		}

		filename := config.Filename
		if filename == "" {
			filename = screenshot.GenerateFilename(config.Format)
		}

		filePath = filepath.Join(outputDir, filename)
		if err := screenshot.WriteToFileWithFormat(result.Buffer, filePath, config.Format, config.Quality, result.Format, result.CICP); err != nil {
			exitScreenshotError(" writing file", err)
		}
		if !ssJSON {
			fmt.Println(filePath)
		}
	}

	if config.Clipboard {
		var err error
		if filePath != "" && config.Format != screenshot.FormatPPM {
			err = copyFileToClipboard(filePath)
		} else {
			err = copyImageToClipboard(result.Buffer, config.Format, config.Quality, result.Format, result.CICP)
		}
		if err != nil {
			exitScreenshotError(" copying to clipboard", err)
		}
		if !ssJSON && !config.SaveFile {
			if ssStdout {
				fmt.Fprintln(os.Stderr, "Copied to clipboard")
			} else {
				fmt.Println("Copied to clipboard")
			}
		}
	}

	if ssJSON {
		if result.CopyOnly {
			writeScreenshotJSON(screenshotMetadata{
				Status: "aborted",
				Error:  "User copied to clipboard",
			})
		} else {
			scale := result.Scale
			if scale <= 0 {
				scale = 1.0
			}
			writeScreenshotJSON(screenshotMetadata{
				Status: "success",
				Path:   filePath,
				Width:  result.Buffer.Width,
				Height: result.Buffer.Height,
				Scale:  scale,
				Mime:   formatMime(config.Format),
			})
		}
	}

	if config.Notify {
		thumbData, thumbW, thumbH := bufferToRGBAThumbnail(result.Buffer, 640, result.Format)
		id := screenshot.SendNotification(screenshot.NotifyResult{
			FilePath:  filePath,
			Clipboard: config.Clipboard,
			ImageData: thumbData,
			Width:     thumbW,
			Height:    thumbH,
		})
		watchNotificationAction(id, filePath)
	}
}

func copyImageToClipboard(buf *screenshot.ShmBuffer, format screenshot.Format, quality int, pixelFormat uint32, cicp *screenshot.CICP) error {
	var mimeType string
	var data bytes.Buffer

	switch format {
	case screenshot.FormatJPEG:
		mimeType = "image/jpeg"
		if err := screenshot.EncodeBufferJPEG(&data, buf, pixelFormat, quality); err != nil {
			return err
		}
	default:
		mimeType = "image/png"
		if err := screenshot.EncodeBufferPNG(&data, buf, pixelFormat, cicp); err != nil {
			return err
		}
	}

	return clipboard.Copy(data.Bytes(), mimeType)
}

func writeImageToStdout(buf *screenshot.ShmBuffer, format screenshot.Format, quality int, pixelFormat uint32, cicp *screenshot.CICP) error {
	switch format {
	case screenshot.FormatJPEG:
		return screenshot.EncodeBufferJPEG(os.Stdout, buf, pixelFormat, quality)
	default:
		return screenshot.EncodeBufferPNG(os.Stdout, buf, pixelFormat, cicp)
	}
}

func bufferToRGBAThumbnail(buf *screenshot.ShmBuffer, maxSize int, pixelFormat uint32) ([]byte, int, int) {
	if buf == nil || buf.Width <= 0 || buf.Height <= 0 || maxSize <= 0 {
		return nil, 0, 0
	}

	srcW, srcH := buf.Width, buf.Height
	longest := max(srcW, srcH)
	dstW, dstH := srcW, srcH
	if longest > maxSize {
		dstW = max(1, srcW*maxSize/longest)
		dstH = max(1, srcH*maxSize/longest)
	}

	data := buf.Data()
	rgba := make([]byte, dstW*dstH*4)

	is10Bit := screenshot.PixelFormat(pixelFormat).Is10Bit()

	var swapRB bool
	switch pixelFormat {
	case uint32(screenshot.FormatABGR8888), uint32(screenshot.FormatXBGR8888),
		uint32(screenshot.FormatABGR2101010), uint32(screenshot.FormatXBGR2101010):
		swapRB = false
	default:
		swapRB = true
	}

	for y := range dstH {
		y0, y1 := y*srcH/dstH, (y+1)*srcH/dstH
		for x := range dstW {
			x0, x1 := x*srcW/dstW, (x+1)*srcW/dstW
			var r, g, b, samples uint64
			for srcY := y0; srcY < y1; srcY++ {
				for srcX := x0; srcX < x1; srcX++ {
					si := srcY*buf.Stride + srcX*4
					if si+3 >= len(data) {
						continue
					}
					c0, c1, c2 := data[si], data[si+1], data[si+2]
					if is10Bit {
						v := binary.LittleEndian.Uint32(data[si:])
						c0, c1, c2 = uint8(v>>2), uint8(v>>12), uint8(v>>22)
					}
					if swapRB {
						c0, c2 = c2, c0
					}
					r += uint64(c0)
					g += uint64(c1)
					b += uint64(c2)
					samples++
				}
			}
			if samples == 0 {
				continue
			}
			di := (y*dstW + x) * 4
			rgba[di+0] = byte((r + samples/2) / samples)
			rgba[di+1] = byte((g + samples/2) / samples)
			rgba[di+2] = byte((b + samples/2) / samples)
			rgba[di+3] = 255
		}
	}
	return rgba, dstW, dstH
}

func runScreenshotRegion(cmd *cobra.Command, args []string) {
	config := getScreenshotConfig(screenshot.ModeRegion)
	runScreenshot(config)
}

func runScreenshotScroll(cmd *cobra.Command, args []string) {
	config := getScreenshotConfig(screenshot.ModeScroll)
	config.IntervalMs = min(max(ssScrollInterval, 30), 1000)
	runScreenshot(config)
}

func runScreenshotFull(cmd *cobra.Command, args []string) {
	config := getScreenshotConfig(screenshot.ModeFullScreen)
	runScreenshot(config)
}

func runScreenshotAll(cmd *cobra.Command, args []string) {
	config := getScreenshotConfig(screenshot.ModeAllScreens)
	runScreenshot(config)
}

func runScreenshotOutput(cmd *cobra.Command, args []string) {
	if ssOutputName == "" && len(args) > 0 {
		ssOutputName = args[0]
	}
	if ssOutputName == "" {
		fmt.Fprintln(os.Stderr, "Error: output name required (use -o or provide as argument)")
		os.Exit(1)
	}
	config := getScreenshotConfig(screenshot.ModeOutput)
	runScreenshot(config)
}

func runScreenshotLast(cmd *cobra.Command, args []string) {
	config := getScreenshotConfig(screenshot.ModeLastRegion)
	runScreenshot(config)
}

func runScreenshotWindow(cmd *cobra.Command, args []string) {
	config := getScreenshotConfig(screenshot.ModeWindow)
	runScreenshot(config)
}

func runScreenshotList(cmd *cobra.Command, args []string) {
	outputs, err := screenshot.ListOutputs()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	for _, o := range outputs {
		scaleStr := fmt.Sprintf("%.2f", o.FractionalScale)
		if o.FractionalScale == float64(int(o.FractionalScale)) {
			scaleStr = fmt.Sprintf("%d", int(o.FractionalScale))
		}

		transformStr := transformName(o.Transform)

		fmt.Printf("%s: %dx%d+%d+%d scale=%s transform=%s\n",
			o.Name, o.Width, o.Height, o.X, o.Y, scaleStr, transformStr)
	}
}

func transformName(t int32) string {
	switch t {
	case 0:
		return "normal"
	case 1:
		return "90"
	case 2:
		return "180"
	case 3:
		return "270"
	case 4:
		return "flipped"
	case 5:
		return "flipped-90"
	case 6:
		return "flipped-180"
	case 7:
		return "flipped-270"
	default:
		return fmt.Sprintf("%d", t)
	}
}
