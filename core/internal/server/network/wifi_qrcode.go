package network

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/qrcode"
)

const qrCodeTmpPrefix = "/tmp/dank-wifi-qrcode-"

func FormatWiFiQRString(securityType, ssid, password string) string {
	return qrcode.WiFiString(securityType, ssid, password, false)
}

func qrCodePaths(ssid string) (themed, normal string) {
	safe := sanitizeSSIDForPath(ssid)
	themed = fmt.Sprintf("%s%s-themed.png", qrCodeTmpPrefix, safe)
	normal = fmt.Sprintf("%s%s-normal.png", qrCodeTmpPrefix, safe)
	return
}

func isValidQRCodePath(path string) bool {
	clean := filepath.Clean(path)
	return (strings.HasPrefix(clean, qrCodeTmpPrefix) || strings.HasPrefix(clean, textQRCodeTmpPrefix)) && strings.HasSuffix(clean, ".png")
}

var safePathChar = regexp.MustCompile(`[^a-zA-Z0-9_-]`)

func sanitizeSSIDForPath(ssid string) string {
	return safePathChar.ReplaceAllString(ssid, "_")
}

var iwdVerbatimSSID = regexp.MustCompile(`^[a-zA-Z0-9 _-]+$`)

func iwdConfigPath(ssid string) string {
	switch {
	case iwdVerbatimSSID.MatchString(ssid):
		return fmt.Sprintf("/var/lib/iwd/%s.psk", ssid)
	default:
		return fmt.Sprintf("/var/lib/iwd/=%x.psk", []byte(ssid))
	}
}

func parseIWDPassphrase(data string) (string, error) {
	inSecurity := false
	for line := range strings.SplitSeq(data, "\n") {
		line = strings.TrimSpace(line)
		switch {
		case line == "[Security]":
			inSecurity = true
		case strings.HasPrefix(line, "["):
			inSecurity = false
		case inSecurity && strings.HasPrefix(line, "Passphrase="):
			return strings.TrimPrefix(line, "Passphrase="), nil
		}
	}
	return "", fmt.Errorf("no passphrase found in iwd config")
}
