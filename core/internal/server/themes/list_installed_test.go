package themes

import (
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/themes"
	"github.com/stretchr/testify/require"
)

func TestPaletteInfoResolvesDefaultFlavorAndAccent(t *testing.T) {
	theme := &themes.Theme{
		Variants: &themes.ThemeVariants{
			Type: "multi",
			Defaults: &themes.MultiVariantDefaults{
				Dark:  map[string]string{"flavor": "mocha", "accent": "mauve"},
				Light: map[string]string{"flavor": "latte", "accent": "mauve"},
			},
			Flavors: []themes.ThemeFlavor{
				{ID: "latte", Light: themes.ColorScheme{Surface: "#eff1f5", Info: "#04a5e5"}},
				{ID: "mocha", Dark: themes.ColorScheme{Surface: "#1e1e2e", Info: "#89dceb"}},
			},
			Accents: []themes.ThemeAccent{
				{ID: "rosewater", FlavorColors: map[string]themes.ColorScheme{"mocha": {Primary: "#f5e0dc"}}},
				{ID: "mauve", FlavorColors: map[string]themes.ColorScheme{
					"mocha": {Primary: "#cba6f7", Secondary: "#f5c2e7"},
					"latte": {Primary: "#8839ef", Secondary: "#ea76cb"},
				}},
			},
		},
	}

	palette := paletteInfo(theme)

	require.NotNil(t, palette)
	require.Equal(t, map[string]string{"primary": "#cba6f7", "secondary": "#f5c2e7", "info": "#89dceb"}, palette.Dark)
	require.Equal(t, map[string]string{"primary": "#8839ef", "secondary": "#ea76cb", "info": "#04a5e5"}, palette.Light)
}

func TestPaletteInfoOverlaysDefaultOptionOnBase(t *testing.T) {
	theme := &themes.Theme{
		Dark:  themes.ColorScheme{Primary: "#000000", Secondary: "#111111"},
		Light: themes.ColorScheme{Primary: "#eeeeee"},
		Variants: &themes.ThemeVariants{
			Default: "ocean",
			Options: []themes.ThemeVariant{
				{ID: "forest", Dark: themes.ColorScheme{Primary: "#00ff00"}},
				{ID: "ocean", Dark: themes.ColorScheme{Surface: "#001020", Secondary: "#0000ff"}, Light: themes.ColorScheme{Primary: "#0000aa"}},
			},
		},
	}

	palette := paletteInfo(theme)

	require.Equal(t, map[string]string{"primary": "#000000", "secondary": "#0000ff"}, palette.Dark)
	require.Equal(t, map[string]string{"primary": "#0000aa"}, palette.Light)
}
