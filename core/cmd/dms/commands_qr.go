package main

import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/qrcode"
	"github.com/mattn/go-isatty"
	"github.com/spf13/cobra"
)

var (
	qrEcc         string
	qrVersion     int
	qrOutput      string
	qrStdout      bool
	qrClipboard   bool
	qrCopyText    bool
	qrRender      bool
	qrNoRender    bool
	qrInvert      bool
	qrQuietZone   int
	qrModuleSize  int
	qrFg          string
	qrBg          string
	qrTransparent bool
	qrBorder      int
	qrShape       string
	qrLogo        string
	qrLogoScale   int

	qrWifiPassword string
	qrWifiSecurity string
	qrWifiHidden   bool
)

var qrCmd = &cobra.Command{
	Use:   "qr [text]",
	Short: "Generate QR codes",
	Long: `Generate a QR code from text, stdin, or a WiFi network.

By default the code is rendered to the terminal when stdout is a TTY, or
written as PNG bytes to stdout when piped. Use flags to also copy to the
clipboard, save a PNG, or tune encoding and colors.

Input:
  dms qr "https://example.com"     # encode an argument
  echo -n "data" | dms qr          # encode stdin
  dms qr -                         # encode stdin explicitly

Output (combine freely):
  dms qr "text" --clipboard        # copy PNG image to clipboard
  dms qr "text" --copy-text        # copy the source text to clipboard
  dms qr "text" -o code.png        # save a PNG file
  dms qr "text" > code.png         # PNG to stdout (piped)
  dms qr "text" --render           # force terminal render

Encoding & style:
  --ecc L|M|Q|H                    # error correction (default M)
  --qr-version 10                  # force symbol version (1-40)
  --module-size 12 --fg '#000' ... # PNG sizing and colors
  --shape circle                   # round modules
  --logo icon.png                  # center logo (bumps --ecc to H)
  --invert                         # flip colors for light terminals

WiFi:
  dms qr wifi MySSID -p secret     # build from an explicit password
  dms qr wifi MySSID               # pull the saved secret from the shell`,
	Args: cobra.ArbitraryArgs,
	Run:  runQR,
}

var qrWifiCmd = &cobra.Command{
	Use:   "wifi <ssid>",
	Short: "Generate a WiFi QR code",
	Long: `Generate a QR code that joins a WiFi network when scanned.

With --password the code is built entirely offline. Without it, the saved
credentials are fetched from the running DMS shell (like the network panel).`,
	Args: cobra.ExactArgs(1),
	Run:  runQRWifi,
}

func init() {
	qrCmd.PersistentFlags().StringVar(&qrEcc, "ecc", "", "Error correction level: L, M, Q, H (default M, or H with --logo)")
	qrCmd.PersistentFlags().IntVar(&qrVersion, "qr-version", 0, "Force QR symbol version 1-40 (0 = auto)")
	qrCmd.PersistentFlags().StringVarP(&qrOutput, "output", "o", "", "Write a PNG to this file")
	qrCmd.PersistentFlags().BoolVar(&qrStdout, "stdout", false, "Write PNG bytes to stdout")
	qrCmd.PersistentFlags().BoolVar(&qrClipboard, "clipboard", false, "Copy the PNG image to the clipboard")
	qrCmd.PersistentFlags().BoolVar(&qrCopyText, "copy-text", false, "Copy the source text to the clipboard")
	qrCmd.PersistentFlags().BoolVar(&qrRender, "render", false, "Force terminal rendering")
	qrCmd.PersistentFlags().BoolVar(&qrNoRender, "no-render", false, "Never render to the terminal")
	qrCmd.PersistentFlags().BoolVar(&qrInvert, "invert", false, "Swap colors (for light terminals)")
	qrCmd.PersistentFlags().IntVar(&qrQuietZone, "quiet-zone", 2, "Terminal margin in modules")
	qrCmd.PersistentFlags().IntVar(&qrModuleSize, "module-size", 0, "PNG pixels per module (0 = auto)")
	qrCmd.PersistentFlags().StringVar(&qrFg, "fg", "", "Dark module color (#RGB or #RRGGBB)")
	qrCmd.PersistentFlags().StringVar(&qrBg, "bg", "", "Light module color (#RGB or #RRGGBB)")
	qrCmd.PersistentFlags().BoolVar(&qrTransparent, "transparent", false, "Transparent PNG background")
	qrCmd.PersistentFlags().IntVar(&qrBorder, "border", -1, "PNG border in pixels (-1 = auto)")
	qrCmd.PersistentFlags().StringVar(&qrShape, "shape", "square", "PNG module shape (square, circle)")
	qrCmd.PersistentFlags().StringVar(&qrLogo, "logo", "", "Center a PNG/JPEG logo on the PNG output")
	qrCmd.PersistentFlags().IntVar(&qrLogoScale, "logo-scale", 0, "Max logo size as 1/N of the code (0 = library default of 5)")

	qrWifiCmd.Flags().StringVarP(&qrWifiPassword, "password", "p", "", "WiFi password (offline build)")
	qrWifiCmd.Flags().StringVar(&qrWifiSecurity, "security", "WPA", "Security type (WPA, WEP, nopass)")
	qrWifiCmd.Flags().BoolVar(&qrWifiHidden, "hidden", false, "Mark the network as hidden")

	qrCmd.AddCommand(qrWifiCmd)
}

func runQR(cmd *cobra.Command, args []string) {
	text := strings.Join(args, " ")
	if text == "" || text == "-" {
		data, err := io.ReadAll(os.Stdin)
		if err != nil {
			fatalf("Error reading stdin: %v", err)
		}
		text = strings.TrimRight(string(data), "\n")
	}
	if text == "" {
		fatalf("Error: no input (provide text, pipe stdin, or use a subcommand)")
	}
	emitQR(text)
}

func runQRWifi(cmd *cobra.Command, args []string) {
	ssid := args[0]
	if qrWifiPassword != "" || strings.EqualFold(qrWifiSecurity, "nopass") {
		emitQR(qrcode.WiFiString(qrWifiSecurity, ssid, qrWifiPassword, qrWifiHidden))
		return
	}

	content, err := fetchWifiQRContent(ssid)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		fmt.Fprintln(os.Stderr, "Hint: pass --password to build the code without the shell.")
		os.Exit(1)
	}
	if qrWifiHidden {
		content = strings.TrimSuffix(content, ";") + "H:true;;"
	}
	emitQR(content)
}

func emitQR(text string) {
	renderTerm := shouldRenderTerminal()
	pngToStdout := qrStdout || (!renderTerm && qrOutput == "" && !qrClipboard && !qrCopyText)

	if pngToStdout || qrOutput != "" || qrClipboard {
		png, err := qrcode.RenderPNG(text, qrcode.ImageOptions{
			ECC:         effectiveEcc(),
			Version:     qrVersion,
			ModuleSize:  qrModuleSize,
			Fg:          qrFg,
			Bg:          qrBg,
			Transparent: qrTransparent,
			Border:      qrBorder,
			Shape:       qrShape,
			Logo:        qrLogo,
			LogoScale:   qrLogoScale,
		})
		if err != nil {
			fatalf("Error encoding QR: %v", err)
		}
		emitPNG(png, pngToStdout)
	}

	if qrCopyText {
		if err := clipboard.CopyText(text); err != nil {
			fatalf("Error copying text: %v", err)
		}
	}

	if !renderTerm {
		return
	}
	out, err := qrcode.RenderTerminal(text, qrcode.TermOptions{
		ECC:       effectiveEcc(),
		Version:   qrVersion,
		QuietZone: qrQuietZone,
		Invert:    qrInvert,
		Fg:        qrFg,
		Bg:        qrBg,
	})
	if err != nil {
		fatalf("Error rendering QR: %v", err)
	}
	dst := os.Stdout
	if pngToStdout {
		dst = os.Stderr
	}
	fmt.Fprint(dst, out)
}

func emitPNG(png []byte, toStdout bool) {
	if qrOutput != "" {
		if err := os.WriteFile(qrOutput, png, 0o644); err != nil {
			fatalf("Error writing file: %v", err)
		}
		fmt.Fprintln(os.Stderr, qrOutput)
	}
	if toStdout {
		os.Stdout.Write(png)
	}
	if qrClipboard {
		if err := clipboard.Copy(png, "image/png"); err != nil {
			fatalf("Error copying image: %v", err)
		}
	}
}

func shouldRenderTerminal() bool {
	switch {
	case qrNoRender:
		return false
	case qrRender:
		return true
	case qrStdout, qrOutput != "", qrClipboard, qrCopyText:
		return false
	default:
		return isatty.IsTerminal(os.Stdout.Fd())
	}
}

func effectiveEcc() string {
	switch {
	case qrEcc != "":
		return qrEcc
	case qrLogo != "":
		return "H"
	default:
		return "M"
	}
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}

func fetchWifiQRContent(ssid string) (string, error) {
	resp, err := sendServerRequest(ipc.Request{
		ID:     1,
		Method: "network.qrcode-content",
		Params: map[string]any{"ssid": ssid},
	})
	if err != nil {
		return "", err
	}
	if resp.Error != "" {
		return "", fmt.Errorf("%s", resp.Error)
	}
	if resp.Result == nil {
		return "", fmt.Errorf("empty response")
	}
	content, ok := (*resp.Result).(string)
	if !ok {
		return "", fmt.Errorf("unexpected response format")
	}
	return content, nil
}
