package distros

import (
	"context"
	"encoding/base64"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/netfetch"
)

const (
	crc24Init = 0xB704CE
	crc24Poly = 0x1864CFB
)

func crc24(data []byte) uint32 {
	crc := uint32(crc24Init)
	for _, b := range data {
		crc ^= uint32(b) << 16
		for range 8 {
			crc <<= 1
			if crc&0x1000000 != 0 {
				crc ^= crc24Poly
			}
		}
	}
	return crc & 0xFFFFFF
}

func dearmorPGP(armored []byte) ([]byte, error) {
	lines := strings.Split(strings.ReplaceAll(string(armored), "\r\n", "\n"), "\n")

	start := -1
	for i, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), "-----BEGIN PGP ") {
			start = i + 1
			break
		}
	}
	if start < 0 {
		return nil, fmt.Errorf("no PGP armor header found")
	}

	// Armor headers run until the first blank line; a headerless block has none.
	for start < len(lines) && strings.Contains(lines[start], ": ") {
		start++
	}
	for start < len(lines) && strings.TrimSpace(lines[start]) == "" {
		start++
	}

	var payload strings.Builder
	checksum := ""
	ended := false
	for _, line := range lines[start:] {
		trimmed := strings.TrimSpace(line)
		switch {
		case trimmed == "":
			continue
		case strings.HasPrefix(trimmed, "-----END PGP "):
			ended = true
		case strings.HasPrefix(trimmed, "="):
			checksum = trimmed[1:]
		default:
			payload.WriteString(trimmed)
		}
		if ended {
			break
		}
	}
	if !ended {
		return nil, fmt.Errorf("unterminated PGP armor block")
	}

	decoded, err := base64.StdEncoding.DecodeString(payload.String())
	if err != nil {
		return nil, fmt.Errorf("invalid base64 in PGP armor: %w", err)
	}
	if len(decoded) == 0 {
		return nil, fmt.Errorf("PGP armor block is empty")
	}

	if checksum == "" {
		return decoded, nil
	}

	want, err := base64.StdEncoding.DecodeString(checksum)
	if err != nil || len(want) != 3 {
		return nil, fmt.Errorf("invalid PGP armor checksum %q", checksum)
	}
	got := crc24(decoded)
	if uint32(want[0])<<16|uint32(want[1])<<8|uint32(want[2]) != got {
		return nil, fmt.Errorf("PGP armor checksum mismatch")
	}
	return decoded, nil
}

func fetchDearmoredKey(ctx context.Context, url string) ([]byte, error) {
	armored, err := netfetch.Bytes(ctx, url, netfetch.Options{Timeout: 30 * time.Second})
	if err != nil {
		return nil, fmt.Errorf("failed to fetch %s: %w", url, err)
	}

	keyring, err := dearmorPGP(armored)
	if err != nil {
		return nil, fmt.Errorf("failed to dearmor key from %s: %w", url, err)
	}
	return keyring, nil
}

// privesc.ExecCommand owns stdin for the sudo password, so the key cannot be piped in.
func writeTempKeyring(keyring []byte) (string, error) {
	f, err := os.CreateTemp("", "dms-repo-key-*.gpg")
	if err != nil {
		return "", fmt.Errorf("failed to create temp keyring: %w", err)
	}
	defer f.Close()

	if _, err := f.Write(keyring); err != nil {
		os.Remove(f.Name())
		return "", fmt.Errorf("failed to write temp keyring: %w", err)
	}
	if err := f.Chmod(0o644); err != nil {
		os.Remove(f.Name())
		return "", fmt.Errorf("failed to chmod temp keyring: %w", err)
	}
	return f.Name(), nil
}
