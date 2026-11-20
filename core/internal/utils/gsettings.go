package utils

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

func dconfPath(schema, key string) string {
	return "/" + strings.ReplaceAll(schema, ".", "/") + "/" + key
}

// gsettings reaches whichever backend its own GLib links, not necessarily the
// dconf store GTK apps read, and it exits 0 either way.
func dconfSelected() bool {
	backend := os.Getenv("GSETTINGS_BACKEND")
	return backend == "" || backend == "dconf"
}

// GsettingsGet reads a desktop setting from dconf, falling back to gsettings.
func GsettingsGet(schema, key string) (string, error) {
	if dconfSelected() {
		if out, err := exec.Command("dconf", "read", dconfPath(schema, key)).Output(); err == nil {
			if value := strings.TrimSpace(string(out)); value != "" {
				return value, nil
			}
		}
	}
	out, err := exec.Command("gsettings", "get", schema, key).Output()
	if err != nil {
		return "", fmt.Errorf("dconf/gsettings get failed for %s %s: %w", schema, key, err)
	}
	return strings.TrimSpace(string(out)), nil
}

// GsettingsSet writes a desktop setting to dconf, falling back to gsettings.
func GsettingsSet(schema, key, value string) error {
	return gsettingsWrite(schema, key, "'"+value+"'", value)
}

func GsettingsSetBool(schema, key string, value bool) error {
	literal := strconv.FormatBool(value)
	return gsettingsWrite(schema, key, literal, literal)
}

func gsettingsWrite(schema, key, dconfValue, gsettingsValue string) error {
	if dconfSelected() {
		if err := exec.Command("dconf", "write", dconfPath(schema, key), dconfValue).Run(); err == nil {
			return nil
		}
	}
	return exec.Command("gsettings", "set", schema, key, gsettingsValue).Run()
}
