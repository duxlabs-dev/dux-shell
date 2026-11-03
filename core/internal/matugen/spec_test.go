package matugen

import (
	"encoding/json"
	"strconv"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNormalizeHexColor(t *testing.T) {
	for _, in := range []string{"#FF3D00", "ff3d00", " #ff3d00 "} {
		got, err := NormalizeHexColor(in)
		require.NoError(t, err, in)
		require.Equal(t, "#ff3d00", got, in)
	}
	for _, in := range []string{"", "#fff", "#ff3d00aa", "red", "#gg3d00", "#ff3d00; rm -rf"} {
		_, err := NormalizeHexColor(in)
		require.Error(t, err, in)
	}
}

func TestGenerateSpecColorsRejectsSmart(t *testing.T) {
	_, err := GenerateSpecColors("#1e88e5", "scheme-smart", 0, ColorModeDark, Spec2025)
	require.Error(t, err)
	require.False(t, SpecSupportsScheme("scheme-smart"))
	require.True(t, SpecSupportsScheme("scheme-vibrant"))
}

func TestGenerateSpecColors2025IsBolderThan2021(t *testing.T) {
	colors2021 := decodeSpecColors(t, "#ff3d00", "scheme-vibrant", Spec2021)
	colors2025 := decodeSpecColors(t, "#ff3d00", "scheme-vibrant", Spec2025)
	require.Equal(t, "#ffb4a2", colors2021["primary"].Dark.Color)
	require.Equal(t, "#ff8f73", colors2025["primary"].Dark.Color)
	require.Equal(t, colors2025["primary"].Dark.Color, colors2025["primary"].Default.Color)
	require.Equal(t, "#ff3d00", colors2025["source_color"].Dark.Color)
}

func TestGenerateSpecColorsDefaultFollowsMode(t *testing.T) {
	colors := decodeSpecColorsMode(t, "#1e88e5", "scheme-tonal-spot", Spec2021, ColorModeLight)
	require.Equal(t, colors["primary"].Light.Color, colors["primary"].Default.Color)
	require.NotEqual(t, colors["primary"].Dark.Color, colors["primary"].Default.Color)
}

func maxChannelDelta(t *testing.T, a, b string) int {
	t.Helper()
	require.Len(t, a, 7)
	require.Len(t, b, 7)
	delta := 0
	for i := 1; i < 7; i += 2 {
		x, err := strconv.ParseInt(a[i:i+2], 16, 0)
		require.NoError(t, err)
		y, err := strconv.ParseInt(b[i:i+2], 16, 0)
		require.NoError(t, err)
		if d := int(x - y); d > delta {
			delta = d
		} else if -d > delta {
			delta = -d
		}
	}
	return delta
}

type specShade struct {
	Color string `json:"color"`
}

type specRole struct {
	Dark    specShade `json:"dark"`
	Light   specShade `json:"light"`
	Default specShade `json:"default"`
}

func decodeSpecColors(t *testing.T, seed, scheme, version string) map[string]specRole {
	return decodeSpecColorsMode(t, seed, scheme, version, ColorModeDark)
}

func decodeSpecColorsMode(t *testing.T, seed, scheme, version string, mode ColorMode) map[string]specRole {
	t.Helper()
	raw, err := GenerateSpecColors(seed, scheme, 0, mode, version)
	require.NoError(t, err)
	var roles map[string]specRole
	require.NoError(t, json.Unmarshal([]byte(raw), &roles))
	return roles
}

func TestGenerateSpecColorsDMSKeepsVibrantAccentsOnTonalSpotSurfaces(t *testing.T) {
	dms := decodeSpecColors(t, "#1c7ecc", "scheme-vibrant", SpecDMS)
	vibrant := decodeSpecColors(t, "#1c7ecc", "scheme-vibrant", Spec2025)
	tonalSpot := decodeSpecColors(t, "#1c7ecc", "scheme-tonal-spot", Spec2025)
	require.Equal(t, vibrant["primary"].Dark.Color, dms["primary"].Dark.Color)
	require.Equal(t, vibrant["secondary_container"].Dark.Color, dms["secondary_container"].Dark.Color)
	require.Equal(t, vibrant["primary"].Light.Color, dms["primary"].Light.Color)
	require.NotEqual(t, vibrant["surface"].Dark.Color, dms["surface"].Dark.Color)
	require.LessOrEqual(t, maxChannelDelta(t, tonalSpot["surface"].Dark.Color, dms["surface"].Dark.Color), 4)
	tonalSpotDMS := decodeSpecColors(t, "#1c7ecc", "scheme-tonal-spot", SpecDMS)
	require.NotEqual(t, tonalSpot["primary"].Dark.Color, tonalSpotDMS["primary"].Dark.Color)
	require.NotEqual(t, dms["primary"].Dark.Color, tonalSpotDMS["primary"].Dark.Color)
	require.True(t, UsesSpecGenerator(SpecDMS, "scheme-vibrant"))
	require.False(t, UsesSpecGenerator(SpecDMS, "scheme-content"))
}
