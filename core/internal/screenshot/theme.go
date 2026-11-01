package screenshot

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type ThemeColors struct {
	Background string `json:"surface"`
	OnSurface  string `json:"on_surface"`
	Primary    string `json:"primary"`
}

type ColorScheme struct {
	Dark  ThemeColors `json:"dark"`
	Light ThemeColors `json:"light"`
}

type ColorsFile struct {
	Colors ColorScheme `json:"colors"`
}

var (
	styleOnce   sync.Once
	cachedStyle OverlayStyle
)

// keeps the dconf spawn off the first paint
func PrefetchOverlayStyle() {
	go LoadOverlayStyle()
}

func LoadOverlayStyle() OverlayStyle {
	styleOnce.Do(func() { cachedStyle = loadOverlayStyle() })
	return cachedStyle
}

func loadOverlayStyle() OverlayStyle {
	style := DefaultOverlayStyle
	colors := loadColorsFile()
	if colors == nil {
		return style
	}

	theme := &colors.Dark
	if isLightMode() {
		theme = &colors.Light
	}

	if bg, ok := parseHexColor(theme.Background); ok {
		style.BackgroundR, style.BackgroundG, style.BackgroundB = bg[0], bg[1], bg[2]
	}
	if text, ok := parseHexColor(theme.OnSurface); ok {
		style.TextR, style.TextG, style.TextB = text[0], text[1], text[2]
	}
	if accent, ok := parseHexColor(theme.Primary); ok {
		style.AccentR, style.AccentG, style.AccentB = accent[0], accent[1], accent[2]
	}

	return style
}

func loadColorsFile() *ColorScheme {
	path := getColorsFilePath()
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}

	var file ColorsFile
	if err := json.Unmarshal(data, &file); err != nil {
		return nil
	}

	return &file.Colors
}

func getColorsFilePath() string {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		log.Error("Failed to get user cache dir", "err", err)
		return ""
	}
	return filepath.Join(cacheDir, "dms", "dms-colors.json")
}

func isLightMode() bool {
	scheme, err := utils.GsettingsGet("org.gnome.desktop.interface", "color-scheme")
	if err != nil {
		return false
	}

	switch scheme {
	case "'prefer-light'", "'default'":
		return true
	}
	return false
}

func parseHexColor(hex string) ([3]uint8, bool) {
	hex = strings.TrimPrefix(hex, "#")
	if len(hex) != 6 {
		return [3]uint8{}, false
	}

	var r, g, b uint8
	for i, ptr := range []*uint8{&r, &g, &b} {
		val := 0
		for j := range 2 {
			c := hex[i*2+j]
			val *= 16
			switch {
			case c >= '0' && c <= '9':
				val += int(c - '0')
			case c >= 'a' && c <= 'f':
				val += int(c - 'a' + 10)
			case c >= 'A' && c <= 'F':
				val += int(c - 'A' + 10)
			default:
				return [3]uint8{}, false
			}
		}
		*ptr = uint8(val)
	}

	return [3]uint8{r, g, b}, true
}
