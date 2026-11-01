package themes

import (
	"github.com/duxlabs-dev/dux-shell/core/internal/themes"
)

type VariantInfo struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type FlavorInfo struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Mode string `json:"mode,omitempty"`
}

type AccentInfo struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Color string `json:"color,omitempty"`
}

type MultiDefaults struct {
	Dark  map[string]string `json:"dark,omitempty"`
	Light map[string]string `json:"light,omitempty"`
}

type VariantsInfo struct {
	Type     string         `json:"type,omitempty"`
	Default  string         `json:"default,omitempty"`
	Defaults *MultiDefaults `json:"defaults,omitempty"`
	Options  []VariantInfo  `json:"options,omitempty"`
	Flavors  []FlavorInfo   `json:"flavors,omitempty"`
	Accents  []AccentInfo   `json:"accents,omitempty"`
}

type PaletteInfo struct {
	Dark  map[string]string `json:"dark,omitempty"`
	Light map[string]string `json:"light,omitempty"`
}

type ThemeInfo struct {
	ID          string            `json:"id"`
	Name        string            `json:"name"`
	Version     string            `json:"version"`
	Author      string            `json:"author,omitempty"`
	Description string            `json:"description,omitempty"`
	PreviewPath string            `json:"previewPath,omitempty"`
	SourceDir   string            `json:"sourceDir,omitempty"`
	Installed   bool              `json:"installed,omitempty"`
	FirstParty  bool              `json:"firstParty,omitempty"`
	HasUpdate   bool              `json:"hasUpdate,omitempty"`
	HasVariants bool              `json:"hasVariants,omitempty"`
	Variants    *VariantsInfo     `json:"variants,omitempty"`
	Palette     *PaletteInfo      `json:"palette,omitempty"`
	WCAG        *themes.ThemeWCAG `json:"wcag,omitempty"`
}
