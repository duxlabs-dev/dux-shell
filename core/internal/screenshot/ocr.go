package screenshot

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"
	"sync"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/notify"
	"github.com/godbus/dbus/v5"
)

var HasOCR = sync.OnceValue(func() bool {
	_, err := exec.LookPath("tesseract")
	return err == nil
})

func DefaultOCRLang() string {
	out, err := exec.Command("tesseract", "--list-langs").Output()
	if err != nil {
		return "eng"
	}
	return parseTesseractLangs(string(out))
}

func parseTesseractLangs(output string) string {
	lines := strings.Split(output, "\n")
	var langs []string
	for i, line := range lines {
		line = strings.TrimSpace(line)
		if i == 0 && strings.HasPrefix(strings.ToLower(line), "list of available languages") {
			continue
		}
		if line == "" || line == "osd" || line == "equ" {
			continue
		}
		langs = append(langs, line)
	}
	if len(langs) == 0 {
		return "eng"
	}
	return strings.Join(langs, "+")
}

func ResolveOCRLang(lang string) string {
	lang = strings.TrimSpace(lang)
	if lang != "" {
		return lang
	}
	return DefaultOCRLang()
}

func ExtractTextFromBuffer(buf *ShmBuffer, pixelFormat uint32, cicp *CICP, lang string) (string, error) {
	if buf == nil {
		return "", fmt.Errorf("empty capture buffer")
	}
	if !HasOCR() {
		return "", fmt.Errorf("tesseract is not installed")
	}

	var pngBuf bytes.Buffer
	if err := EncodeBufferPNG(&pngBuf, buf, pixelFormat, cicp); err != nil {
		return "", fmt.Errorf("encode png for ocr: %w", err)
	}

	resolvedLang := ResolveOCRLang(lang)
	cmd := exec.Command("tesseract", "-", "-", "-l", resolvedLang)
	cmd.Stdin = &pngBuf
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		if errMsg := strings.TrimSpace(stderr.String()); errMsg != "" {
			return "", fmt.Errorf("tesseract failed: %s", errMsg)
		}
		return "", fmt.Errorf("tesseract failed: %w", err)
	}

	return strings.TrimSpace(stdout.String()), nil
}

func ExtractTextFromFile(filePath, lang string) (string, error) {
	if !HasOCR() {
		return "", fmt.Errorf("tesseract is not installed")
	}
	resolvedLang := ResolveOCRLang(lang)
	cmd := exec.Command("tesseract", filePath, "-", "-l", resolvedLang)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		if errMsg := strings.TrimSpace(stderr.String()); errMsg != "" {
			return "", fmt.Errorf("tesseract failed: %s", errMsg)
		}
		return "", fmt.Errorf("tesseract failed: %w", err)
	}
	return strings.TrimSpace(stdout.String()), nil
}

func SendOCRNotification(text string, copied bool) {
	conn, err := dbus.SessionBus()
	if err != nil {
		log.Debug("dbus session failed", "err", err)
		return
	}

	summary := "Text extracted"
	body := text
	if text == "" {
		summary = "OCR"
		body = "No text detected"
	} else {
		const maxPreview = 160
		runes := []rune(body)
		if len(runes) > maxPreview {
			body = string(runes[:maxPreview]) + "…"
		}
		if copied {
			body = fmt.Sprintf("%s\nCopied to clipboard", body)
		}
	}

	hints := map[string]dbus.Variant{
		"desktop-entry": dbus.MakeVariant(notify.AppID),
	}

	obj := conn.Object(notifyDest, notifyPath)
	call := obj.Call(
		notifyInterface+".Notify",
		0,
		"DMS",
		uint32(0),
		notify.AppID,
		summary,
		body,
		[]string{},
		hints,
		int32(5000),
	)
	if call.Err != nil {
		log.Debug("ocr notify call failed", "err", call.Err)
	}
}
