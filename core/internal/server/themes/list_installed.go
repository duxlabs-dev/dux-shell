package themes

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/themes"
)

func addVariantsInfo(info *ThemeInfo, variants *themes.ThemeVariants) {
	if variants == nil {
		return
	}

	if variants.Type == "multi" {
		if len(variants.Flavors) == 0 && len(variants.Accents) == 0 {
			return
		}
		info.HasVariants = true
		info.Variants = &VariantsInfo{
			Type:    "multi",
			Flavors: make([]FlavorInfo, len(variants.Flavors)),
			Accents: make([]AccentInfo, len(variants.Accents)),
		}
		if variants.Defaults != nil {
			info.Variants.Defaults = &MultiDefaults{
				Dark:  variants.Defaults.Dark,
				Light: variants.Defaults.Light,
			}
		}
		for i, f := range variants.Flavors {
			mode := ""
			switch {
			case f.Dark.Primary != "" && f.Light.Primary != "":
				mode = "both"
			case f.Dark.Primary != "":
				mode = "dark"
			case f.Light.Primary != "":
				mode = "light"
			default:
				if f.Dark.Surface != "" {
					mode = "dark"
				} else if f.Light.Surface != "" {
					mode = "light"
				}
			}
			info.Variants.Flavors[i] = FlavorInfo{ID: f.ID, Name: f.Name, Mode: mode}
		}
		for i, a := range variants.Accents {
			color := ""
			if colors, ok := a.FlavorColors["mocha"]; ok && colors.Primary != "" {
				color = colors.Primary
			} else if colors, ok := a.FlavorColors["latte"]; ok && colors.Primary != "" {
				color = colors.Primary
			} else {
				for _, c := range a.FlavorColors {
					if c.Primary != "" {
						color = c.Primary
						break
					}
				}
			}
			info.Variants.Accents[i] = AccentInfo{ID: a.ID, Name: a.Name, Color: color}
		}
		return
	}

	if len(variants.Options) == 0 {
		return
	}
	info.HasVariants = true
	info.Variants = &VariantsInfo{
		Default: variants.Default,
		Options: make([]VariantInfo, len(variants.Options)),
	}
	for i, v := range variants.Options {
		info.Variants.Options[i] = VariantInfo{ID: v.ID, Name: v.Name}
	}
}

func paletteInfo(theme *themes.Theme) *PaletteInfo {
	dark, light := defaultSchemes(theme)
	info := &PaletteInfo{Dark: swatchColors(dark), Light: swatchColors(light)}
	if info.Dark == nil && info.Light == nil {
		return nil
	}
	return info
}

func defaultSchemes(theme *themes.Theme) (themes.ColorScheme, themes.ColorScheme) {
	v := theme.Variants
	if v == nil {
		return theme.Dark, theme.Light
	}
	if v.Type == "multi" {
		return multiScheme(v, theme.Dark, false), multiScheme(v, theme.Light, true)
	}
	for _, opt := range v.Options {
		if opt.ID == v.Default {
			return overlay(theme.Dark, opt.Dark), overlay(theme.Light, opt.Light)
		}
	}
	if len(v.Options) > 0 {
		return overlay(theme.Dark, v.Options[0].Dark), overlay(theme.Light, v.Options[0].Light)
	}
	return theme.Dark, theme.Light
}

// variants and flavors often carry surfaces only; the accent colors stay on the base scheme
func overlay(base, top themes.ColorScheme) themes.ColorScheme {
	pick := func(fallback, value string) string {
		if value != "" {
			return value
		}
		return fallback
	}
	base.Primary = pick(base.Primary, top.Primary)
	base.Secondary = pick(base.Secondary, top.Secondary)
	base.PrimaryContainer = pick(base.PrimaryContainer, top.PrimaryContainer)
	base.Info = pick(base.Info, top.Info)
	base.Error = pick(base.Error, top.Error)
	base.Warning = pick(base.Warning, top.Warning)
	return base
}

func multiScheme(v *themes.ThemeVariants, base themes.ColorScheme, light bool) themes.ColorScheme {
	defaults := map[string]string{}
	if v.Defaults != nil {
		if light {
			defaults = v.Defaults.Light
		} else {
			defaults = v.Defaults.Dark
		}
	}
	scheme := base
	flavorID := defaults["flavor"]
	for _, f := range v.Flavors {
		if f.ID != flavorID {
			continue
		}
		if light {
			scheme = overlay(base, f.Light)
		} else {
			scheme = overlay(base, f.Dark)
		}
		break
	}
	for _, a := range v.Accents {
		if a.ID != defaults["accent"] {
			continue
		}
		if accent, ok := a.FlavorColors[flavorID]; ok {
			scheme = overlay(scheme, accent)
		}
		break
	}
	return scheme
}

func swatchColors(scheme themes.ColorScheme) map[string]string {
	if scheme.Primary == "" {
		return nil
	}
	colors := map[string]string{"primary": scheme.Primary}
	for key, value := range map[string]string{
		"secondary":        scheme.Secondary,
		"primaryContainer": scheme.PrimaryContainer,
		"info":             scheme.Info,
		"error":            scheme.Error,
		"warning":          scheme.Warning,
	} {
		if value != "" {
			colors[key] = value
		}
	}
	return colors
}

func HandleListInstalled(conn *ipc.ConnWriter, req ipc.Request) {
	manager, err := themes.NewManager()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create manager: %v", err))
		return
	}

	installedIDs, err := manager.ListInstalled()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to list installed themes: %v", err))
		return
	}

	themeMap := make(map[string]themes.Theme)
	if registry, err := themes.NewRegistry(); err == nil {
		if allThemes, err := registry.List(); err == nil {
			for _, t := range allThemes {
				themeMap[t.ID] = t
			}
		}
	}

	result := make([]ThemeInfo, 0, len(installedIDs))
	for _, id := range installedIDs {
		if theme, ok := themeMap[id]; ok {
			hasUpdate := false
			if hasUpdates, err := manager.HasUpdates(id, theme); err == nil {
				hasUpdate = hasUpdates
			}

			info := ThemeInfo{
				ID:          theme.ID,
				Name:        theme.Name,
				Version:     theme.Version,
				Author:      theme.Author,
				Description: theme.Description,
				SourceDir:   id,
				FirstParty:  isFirstParty(theme.Author),
				HasUpdate:   hasUpdate,
			}
			addVariantsInfo(&info, theme.Variants)
			info.Palette = paletteInfo(&theme)
			result = append(result, info)
		} else {
			installed, err := manager.GetInstalledTheme(id)
			if err != nil {
				result = append(result, ThemeInfo{
					ID:        id,
					Name:      id,
					SourceDir: id,
				})
				continue
			}
			info := ThemeInfo{
				ID:          installed.ID,
				Name:        installed.Name,
				Version:     installed.Version,
				Author:      installed.Author,
				Description: installed.Description,
				SourceDir:   id,
				FirstParty:  isFirstParty(installed.Author),
			}
			addVariantsInfo(&info, installed.Variants)
			info.Palette = paletteInfo(installed)
			result = append(result, info)
		}
	}

	conn.Respond(req.ID, result)
}
