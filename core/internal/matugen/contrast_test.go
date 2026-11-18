package matugen

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/dank16"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// bruView is the bru espresso/yellow dark palette as DMS generated it, the case that started this.
func bruView() map[string]string {
	return map[string]string{
		"colors.background": "#1c1814",
		"colors.surface":    "#26211c",
		"colors.primary":    "#dbb32d",
		"colors.on_primary": "#1c1814",
		"dank16term.color0": "#26211c",
		"dank16term.color5": "#55461b",
		"dank16term.color6": "#dbb32d",
		"dank16term.color8": "#565348",
		"colors.on_surface": "#f5e8c7",
		"colors.outline":    "#b2ab9f",
	}
}

func minAgainst(view map[string]string, fg string, bgs ...string) float64 {
	_, r := worstRatio(view[fg], func() []string {
		var hexes []string
		for _, b := range bgs {
			hexes = append(hexes, view[b])
		}
		return hexes
	}())
	return r
}

func TestApplyOverrides(t *testing.T) {
	tests := []struct {
		name      string
		key       string
		ratio     float64
		unchanged []string
	}{
		{"raises magenta against surface and background", "dank16term.color5", 6, []string{"dank16term.color8", "dank16term.color6"}},
		{"can lower contrast", "dank16term.color6", 5, []string{"dank16term.color5"}},
		{"dim bright black", "dank16term.color8", 3.5, []string{"dank16term.color5"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			orig, view := bruView(), bruView()
			adjustments := applyOverrides(view, ContrastOverrides{tt.key: tt.ratio})

			got := minAgainst(view, tt.key, "dank16term.color0", "colors.background")
			assert.GreaterOrEqual(t, got, tt.ratio)
			assert.Less(t, got, tt.ratio+0.15, "exact ratio overshot")
			for _, k := range tt.unchanged {
				assert.Equal(t, orig[k], view[k], k)
			}
			require.Len(t, adjustments, 1)
			a := adjustments[0]
			assert.Equal(t, tt.key, a.Key)
			assert.Equal(t, orig[tt.key], a.From)
			assert.Equal(t, view[tt.key], a.To)
			assert.Equal(t, tt.ratio, a.Target)
			assert.InDelta(t, got, a.ToRatio, 1e-9)
		})
	}
}

func TestApplyOverridesOffChangesNothing(t *testing.T) {
	view := bruView()
	assert.Empty(t, applyOverrides(view, nil))
	assert.Equal(t, bruView(), view)
}

func TestApplyOverridesDarkensTextOnBrightAccent(t *testing.T) {
	view := map[string]string{"colors.primary": "#dbb32d", "colors.on_primary": "#6a5a30"}
	applyOverrides(view, ContrastOverrides{"colors.on_primary": 4.5})
	assert.GreaterOrEqual(t, dank16.ContrastRatio(view["colors.on_primary"], "#dbb32d"), 4.5)
	assert.Less(t, dank16.Luminance(view["colors.on_primary"]), dank16.Luminance("#6a5a30"))
}

func TestAuditPalette(t *testing.T) {
	tests := []struct {
		name      string
		overrides ContrastOverrides
		fail      []string
		pass      []string
	}{
		{"recommendations flag magenta, accept dim bright black at 2.29", nil, []string{"dank16term.color5"}, []string{"dank16term.color8", "dank16term.color6", "colors.on_primary"}},
		{"an override does not move the bar", ContrastOverrides{"dank16term.color5": 1.5}, []string{"dank16term.color5"}, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := map[string]AuditResult{}
			for _, r := range auditPalette(bruView(), bruView(), tt.overrides) {
				got[r.Key] = r
			}
			for _, k := range tt.fail {
				assert.False(t, got[k].Pass, "%s should be below its recommended ratio", k)
			}
			for _, k := range tt.pass {
				assert.True(t, got[k].Pass, "%s should pass", k)
			}
		})
	}
}

func TestAuditPaletteReportsOriginalAndTarget(t *testing.T) {
	before, after := bruView(), bruView()
	overrides := ContrastOverrides{"dank16term.color5": 4.5}
	applyOverrides(after, overrides)

	var color5, color8 AuditResult
	for _, r := range auditPalette(before, after, overrides) {
		switch r.Key {
		case "dank16term.color5":
			color5 = r
		case "dank16term.color8":
			color8 = r
		}
	}
	assert.InDelta(t, 1.73, color5.Original, 0.01, "theme's own ratio against its surface")
	assert.GreaterOrEqual(t, color5.Ratio, 4.5)
	assert.Equal(t, 4.5, color5.Target)
	assert.Equal(t, RecommendedTextRatio, color5.Recommended)
	assert.True(t, color5.Pass)
	assert.Equal(t, color8.Original, color8.Ratio, "untouched color")
	assert.Equal(t, RecommendedDimRatio, color8.Recommended)
	assert.Zero(t, color8.Target)
}

func TestParseRoleMapAcceptsBothShapes(t *testing.T) {
	var raw map[string]any
	require.NoError(t, json.Unmarshal([]byte(`{
		"primary": {"dark": "#dbb32d", "light": "#896c00"},
		"outline": {"dark": {"color": "#b2ab9f"}, "default": {"color": "#b2ab9f"}}
	}`), &raw))
	roles := parseRoleMap(raw)
	assert.Equal(t, "#dbb32d", roles["primary"]["dark"])
	assert.Equal(t, "#b2ab9f", roles["outline"]["default"])
	assert.JSONEq(t, `{"primary": {"dark": {"color": "#dbb32d"}, "light": {"color": "#896c00"}},
		"outline": {"dark": {"color": "#b2ab9f"}, "default": {"color": "#b2ab9f"}}}`, roles.importJSON())
}

const bruStock = `{
	"primary": {"dark": {"color": "#dbb32d"}, "light": {"color": "#896c00"}, "default": {"color": "#dbb32d"}},
	"primary_container": {"dark": {"color": "#55461b"}, "light": {"color": "#eee3be"}, "default": {"color": "#55461b"}},
	"surface": {"dark": {"color": "#26211c"}, "light": {"color": "#f3ead0"}, "default": {"color": "#26211c"}},
	"background": {"dark": {"color": "#1c1814"}, "light": {"color": "#faf3e0"}, "default": {"color": "#1c1814"}},
	"on_surface_variant": {"dark": {"color": "#6b6355"}, "light": {"color": "#2d241a"}, "default": {"color": "#6b6355"}}
}`

func bruSeeds() dank16Seeds {
	return dank16Seeds{"#dbb32d", "#896c00", "#26211c", "#f3ead0", "#55461b", "#eee3be"}
}

func TestBuildPalettesOffIsUntouched(t *testing.T) {
	opts := &Options{Mode: ColorModeDark}
	b := buildPalettes(opts, bruSeeds(), bruStock, false)

	assert.Empty(t, b.AdjustedRoles, "no overrides must keep the theme's own roles")
	assert.Equal(t, dank16.GenerateVariantJSON(generateDank16Variants(bruSeeds(), ColorModeDark, "")), b.Dank16JSON)
	assert.Equal(t, generateDank16Variants(bruSeeds(), ColorModeDark, ""), b.Term)
	assert.Empty(t, b.Contrast.Record)
	assert.Empty(t, b.Contrast.terminalAdjustments(false))
	assert.Equal(t, "dark", b.Contrast.shown)
	assert.NotContains(t, b.Contrast.Audit, "default", "default is the dark variant here, so it is not audited twice")
	for _, v := range []string{"dark", "light"} {
		keys := map[string]bool{}
		for _, r := range b.Contrast.Audit[v] {
			keys[r.Key] = true
			assert.Equal(t, r.Original, r.Ratio, "%s %s", v, r.Key)
		}
		assert.True(t, keys["colors.on_surface_variant"], "%s: theme roles are audited with nothing to change", v)
		assert.True(t, keys["dank16term.color5"], "%s: terminal colors are audited", v)
	}
}

func TestBuildPalettesMeasuresTerminalAgainstBackground(t *testing.T) {
	// Terminals paint colors.background, not color0 (the surface dank16 was built on); here the
	// background is closer to magenta's lightness, so it is where magenta is weakest.
	const background = "#3a3020"
	stock := `{"primary": {"dark": {"color": "#dbb32d"}, "default": {"color": "#dbb32d"}},
		"background": {"dark": {"color": "` + background + `"}, "default": {"color": "` + background + `"}}}`
	b := buildPalettes(&Options{Mode: ColorModeDark}, bruSeeds(), stock, false)
	for _, r := range b.Contrast.Audit[b.Contrast.shown] {
		if r.Key == "dank16term.color5" {
			assert.Equal(t, background, r.Bg)
			assert.InDelta(t, dank16.ContrastRatio(b.Term.Color5.Default.Hex, background), r.Ratio, 1e-9)
			return
		}
	}
	t.Fatal("no dank16term.color5 row")
}

func TestBuildPalettesDefaultFollowsTheMode(t *testing.T) {
	overrides := ContrastOverrides{"dank16term.color5": 5, "colors.on_surface_variant": 4.5}
	b := buildPalettes(&Options{Mode: ColorModeDark, ContrastOverrides: overrides}, bruSeeds(), bruStock, false)

	assert.Equal(t, b.Term.Color5.Dark, b.Term.Color5.Default, "templates render .default.")
	assert.GreaterOrEqual(t, dank16.ContrastRatio(b.Term.Color5.Default.Hex, "#1c1814"), 5.0)
	var roles map[string]map[string]map[string]string
	require.NoError(t, json.Unmarshal([]byte(b.AdjustedRoles), &roles))
	osv := roles["on_surface_variant"]
	assert.Equal(t, osv["dark"], osv["default"])
	assert.NotEqual(t, "#6b6355", osv["default"]["color"])
}

func TestBuildPalettesAuditsADistinctDefault(t *testing.T) {
	// A stock theme whose default is not its dark variant gets its own pass.
	stock := `{"background": {"dark": {"color": "#1c1814"}, "default": {"color": "#faf3e0"}},
		"on_surface": {"dark": {"color": "#f5e8c7"}, "default": {"color": "#2d241a"}}}`
	b := buildPalettes(&Options{Mode: ColorModeDark}, bruSeeds(), stock, false)
	assert.Equal(t, "default", b.Contrast.shown)
	assert.Contains(t, b.Contrast.Audit, "default")
}

func TestTerminalAdjustments(t *testing.T) {
	term := Adjustment{Key: "dank16term.color5"}
	dark := Adjustment{Key: "dank16term.color8"}
	editor := Adjustment{Key: "dank16.color5"}
	res := contrastResult{shown: "light", Record: map[string][]Adjustment{"light": {term, editor}, "dark": {dark}}}
	assert.Equal(t, []Adjustment{term}, res.terminalAdjustments(false), "the shown variant, without editor colors")
	assert.Equal(t, []Adjustment{dark}, res.terminalAdjustments(true), "forced dark")
}

func TestWithPaletteRecord(t *testing.T) {
	term := generateDank16Variants(bruSeeds(), ColorModeDark, "")
	res := contrastResult{
		Record: map[string][]Adjustment{"default": {{Key: "dank16term.color5", From: "#55461b", To: "#9a8758"}}},
		Audit:  map[string][]AuditResult{"default": {{Key: "dank16term.color5", Ratio: 4.5, Original: 1.73, Recommended: 4.5, Pass: true}}},
	}
	out, err := withPaletteRecord([]byte(`{"mode": "dark", "dank16": {"color0": {"dark": "#26211c"}}}`), &term, res)
	require.NoError(t, err)

	var doc colorsFile
	require.NoError(t, json.Unmarshal(out, &doc))
	assert.Equal(t, "dark", doc.Mode)
	assert.Equal(t, "#26211c", doc.Dank16["color0"]["dark"], "rendered sections are kept")
	assert.Equal(t, term.Color5.Light.Hex, doc.Dank16Term["color5"]["light"])
	assert.Len(t, doc.Dank16Term, 16)
	assert.Equal(t, res.Record, doc.Adjustments)
	assert.Equal(t, res.Audit, doc.Contrast)

	_, err = withPaletteRecord([]byte("not json"), &term, res)
	assert.Error(t, err)
}

func TestNewContrastOverrides(t *testing.T) {
	tests := []struct {
		name, in string
		want     ContrastOverrides
	}{
		{"off", "", nil},
		{"plain", `{"dank16term.color5": 5}`, ContrastOverrides{"dank16term.color5": 5}},
		{"clamped to the WCAG range", `{"a": 0.5, "b": 30}`, ContrastOverrides{"a": 1, "b": 21}},
		{"zero and negative dropped", `{"colors.outline": 0, "a": -2}`, nil},
		{"malformed dropped", `{"dank16term.color5":`, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := NewContrastOverrides(tt.in)
			assert.Equal(t, tt.want, got)
			assert.Equal(t, got, NewContrastOverrides(got.JSON()), "survives the socket round trip")
		})
	}
}

func TestAuditColorsFile(t *testing.T) {
	write := func(t *testing.T, body string) string {
		path := filepath.Join(t.TempDir(), "dms-colors.json")
		require.NoError(t, os.WriteFile(path, []byte(body), 0o644))
		return path
	}
	stored := write(t, `{
		"mode": "dark",
		"colors": {"dark": {"background": "#1c1814"}},
		"dank16term": {"color0": {"dark": "#26211c"}, "color5": {"dark": "#55461b"}},
		"adjustments": {"default": [{"key": "dank16term.color5", "from": "#55461b", "to": "#9a8758", "fromRatio": 1.73, "toRatio": 4.54, "target": 4.5}]},
		"contrast": {"default": [{"key": "dank16term.color5", "fg": "#9a8758", "bg": "#26211c", "ratio": 4.54, "original": 1.73, "recommended": 4.5, "target": 4.5, "pass": true}]}
	}`)
	aliased := write(t, `{
		"mode": "dark",
		"adjustments": {"dark": [{"key": "dank16term.color5", "from": "#55461b", "to": "#9a8758"}]},
		"contrast": {"dark": [{"key": "dank16term.color5", "ratio": 4.54, "original": 1.73, "recommended": 4.5, "pass": true}],
		             "light": [{"key": "dank16term.color5", "ratio": 1.2, "recommended": 4.5, "pass": false}]}
	}`)
	legacy := write(t, `{
		"mode": "light",
		"colors": {"light": {"background": "#faf3e0"}},
		"dank16term": {"color0": {"light": "#f3ead0"}, "color5": {"light": "#eee3be"}}
	}`)

	tests := []struct {
		name, path, variant string
		wantVariant         string
		wantRatio           float64
		wantPass            bool
		wantAdjusted        int
	}{
		{"stored audit for what the shell shows", stored, "", "default", 4.54, true, 1},
		{"default is the mode's variant when not stored apart", aliased, "default", "dark", 4.54, true, 1},
		{"another variant on request", aliased, "light", "light", 1.2, false, 0},
		{"older file is measured directly", legacy, "", "light", 1.07, false, 0},
		{"older file's default is its mode, not dark", legacy, "default", "light", 1.07, false, 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			report, err := AuditColorsFile(tt.path, tt.variant, false)
			require.NoError(t, err)
			assert.Equal(t, tt.wantVariant, report.Variant)
			require.Len(t, report.Results, 1)
			assert.Equal(t, "dank16term.color5", report.Results[0].Key)
			assert.InDelta(t, tt.wantRatio, report.Results[0].Ratio, 0.01)
			assert.Equal(t, tt.wantPass, report.Results[0].Pass)
			assert.Len(t, report.Adjustments, tt.wantAdjusted)
		})
	}
}

func TestOverrideOnAccentKeepsTextOnItReadable(t *testing.T) {
	findAdj := func(adjs []Adjustment, key string) *Adjustment {
		for i := range adjs {
			if adjs[i].Key == key {
				return &adjs[i]
			}
		}
		return nil
	}
	t.Run("on_primary follows a primary change", func(t *testing.T) {
		before, view := bruView(), bruView()
		overrides := ContrastOverrides{"colors.primary": 3}
		adjs := applyOverrides(view, overrides)

		a := findAdj(adjs, "colors.on_primary")
		require.NotNil(t, a, "on_primary must be re-checked when primary moves")
		assert.Equal(t, "colors.primary", a.Cause)
		assert.Equal(t, RecommendedTextRatio, a.Target, "the theme had 8.8:1, so the recommendation is the lower bar")
		assert.GreaterOrEqual(t, dank16.ContrastRatio(view["colors.on_primary"], view["colors.primary"]), RecommendedTextRatio)

		for _, r := range auditPalette(before, view, overrides) {
			if r.Key == "colors.on_primary" {
				assert.Equal(t, "colors.primary", r.Cause)
				assert.Equal(t, view["colors.primary"], r.Bg, "measured against the new primary")
			}
			if r.Key == "colors.primary" {
				assert.Empty(t, r.Cause, "primary was changed by its own setting")
			}
		}
	})
	t.Run("the user's own ratio for on_primary wins", func(t *testing.T) {
		before, view := bruView(), bruView()
		overrides := ContrastOverrides{"colors.primary": 3, "colors.on_primary": 2.5}
		adjs := applyOverrides(view, overrides)
		a := findAdj(adjs, "colors.on_primary")
		require.NotNil(t, a)
		assert.Empty(t, a.Cause)
		assert.InDelta(t, 2.5, dank16.ContrastRatio(view["colors.on_primary"], view["colors.primary"]), 0.15)
		for _, r := range auditPalette(before, view, overrides) {
			if r.Key == "colors.on_primary" {
				assert.Empty(t, r.Cause, "the audit agrees: the user's own setting moved it")
			}
		}
	})
	t.Run("text that stays readable is left alone", func(t *testing.T) {
		view := bruView()
		adjs := applyOverrides(view, ContrastOverrides{"colors.primary": 8})
		assert.Nil(t, findAdj(adjs, "colors.on_primary"))
		assert.Equal(t, bruView()["colors.on_primary"], view["colors.on_primary"])
	})
}

func TestAuditColorsFileTerminalsForcedDark(t *testing.T) {
	path := filepath.Join(t.TempDir(), "dms-colors.json")
	require.NoError(t, os.WriteFile(path, []byte(`{"mode": "light", "contrast": {
		"default": [{"key": "colors.on_surface", "ratio": 12, "recommended": 4.5, "pass": true},
		            {"key": "dank16term.color5", "ratio": 6.1, "recommended": 4.5, "pass": true}],
		"dark":    [{"key": "colors.on_surface", "ratio": 13, "recommended": 4.5, "pass": true},
		            {"key": "dank16term.color5", "ratio": 1.7, "recommended": 4.5, "pass": false}]}}`), 0o644))

	ratios := func(terminalsDark bool) map[string]float64 {
		report, err := AuditColorsFile(path, "", terminalsDark)
		require.NoError(t, err)
		out := map[string]float64{}
		for _, r := range report.Results {
			out[r.Key] = r.Ratio
		}
		return out
	}
	assert.Equal(t, map[string]float64{"colors.on_surface": 12, "dank16term.color5": 6.1}, ratios(false))
	assert.Equal(t, map[string]float64{"colors.on_surface": 12, "dank16term.color5": 1.7}, ratios(true), "terminal rows from dark, app rows as shown")
}

func TestAuditColorsFileRejectsUnknownVariant(t *testing.T) {
	_, err := AuditColorsFile(filepath.Join(t.TempDir(), "missing.json"), "Dark", false)
	assert.ErrorContains(t, err, "unknown variant")
}
