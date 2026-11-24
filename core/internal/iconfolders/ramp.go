package iconfolders

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/duxlabs-dev/dux-go/material/color"
)

const (
	backToneDrop  = 12
	backToneFloor = 10
)

// Ramp is the three folder roles every recipe maps a pack's own colors onto.
type Ramp struct {
	Front string
	Back  string
	Glyph string
}

func NewRamp(primary, onPrimary string) (Ramp, error) {
	var front color.ARGB
	if err := front.UnmarshalText([]byte(strings.TrimSpace(primary))); err != nil {
		return Ramp{}, fmt.Errorf("primary: %w", err)
	}
	hct := front.ToHct()
	back := color.Hct{Hue: hct.Hue, Chroma: hct.Chroma, Tone: max(hct.Tone-backToneDrop, backToneFloor)}.ToARGB()

	// Stock and custom themes may not define on_primary.
	glyph := color.ARGBFromLstar(90)
	if hct.Tone >= 60 {
		glyph = color.ARGBFromLstar(20)
	}
	if strings.TrimSpace(onPrimary) != "" {
		if err := glyph.UnmarshalText([]byte(strings.TrimSpace(onPrimary))); err != nil {
			return Ramp{}, fmt.Errorf("on_primary: %w", err)
		}
	}

	return Ramp{Front: hexOf(front), Back: hexOf(back), Glyph: hexOf(glyph)}, nil
}

func hexOf(c color.ARGB) string {
	return fmt.Sprintf("#%02x%02x%02x", c.Red(), c.Green(), c.Blue())
}

func loadRamp(colorsPath, mode string) (Ramp, error) {
	primary, onPrimary, err := loadPrimary(colorsPath, mode)
	if err != nil {
		return Ramp{}, err
	}
	return NewRamp(primary, onPrimary)
}

// loadPrimary reads the mode's primary and on_primary roles from dms-colors.json.
func loadPrimary(colorsPath, mode string) (string, string, error) {
	data, err := os.ReadFile(colorsPath)
	if err != nil {
		return "", "", fmt.Errorf("failed to read colors: %w", err)
	}
	var parsed struct {
		Colors map[string]map[string]string `json:"colors"`
	}
	if err := json.Unmarshal(data, &parsed); err != nil {
		return "", "", fmt.Errorf("failed to parse %s: %w", colorsPath, err)
	}
	if mode != "light" {
		mode = "dark"
	}
	roles := parsed.Colors[mode]
	if roles["primary"] == "" {
		return "", "", fmt.Errorf("%s has no %s primary", colorsPath, mode)
	}
	return roles["primary"], roles["on_primary"], nil
}
