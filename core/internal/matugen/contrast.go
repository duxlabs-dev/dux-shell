package matugen

import (
	"encoding/json"
	"fmt"
	"maps"
	"math"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/dank16"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

// ContrastOverrides sets colors to an exact WCAG ratio, keyed by palette path, e.g.
// "dank16term.color5" or "colors.outline".
type ContrastOverrides map[string]float64

// Text is WCAG AA for normal text. WCAG has nothing for text meant to recede, so Dim is a
// convention that still flags near-invisible bright black (nord's is 1.69:1).
const (
	RecommendedTextRatio = 4.5
	RecommendedDimRatio  = 2.0
)

// NewContrastOverrides drops malformed input rather than fail theme generation over an optional setting.
func NewContrastOverrides(overridesJSON string) ContrastOverrides {
	if overridesJSON == "" {
		return nil
	}
	var raw map[string]float64
	if err := json.Unmarshal([]byte(overridesJSON), &raw); err != nil {
		log.Warnf("contrast: ignoring overrides %q: %v", overridesJSON, err)
		return nil
	}
	var o ContrastOverrides
	for key, v := range raw {
		if !(v > 0) {
			continue
		}
		if o == nil {
			o = ContrastOverrides{}
		}
		o[key] = math.Min(math.Max(v, 1), 21)
	}
	return o
}

func (o ContrastOverrides) JSON() string {
	if len(o) == 0 {
		return ""
	}
	data, _ := json.Marshal(map[string]float64(o))
	return string(data)
}

// contrastPair is a text color and every background it is drawn on. Dim marks colors
// that are meant to recede (ANSI bright black, outline) and get the lower floor.
type contrastPair struct {
	Fg  string
	Bg  []string
	Dim bool
}

func (p contrastPair) recommended() float64 {
	if p.Dim {
		return RecommendedDimRatio
	}
	return RecommendedTextRatio
}

var contrastPairs = buildContrastPairs()

func buildContrastPairs() []contrastPair {
	surfaces := []string{"colors.surface", "colors.background"}
	// Accents come before the on_* roles drawn over them, so those see the adjusted accent.
	pairs := []contrastPair{
		{Fg: "colors.primary", Bg: surfaces},
		{Fg: "colors.secondary", Bg: surfaces},
		{Fg: "colors.tertiary", Bg: surfaces},
		{Fg: "colors.error", Bg: surfaces},
		{Fg: "colors.on_surface", Bg: []string{"colors.surface", "colors.background", "colors.surface_container", "colors.surface_container_high"}},
		{Fg: "colors.on_background", Bg: []string{"colors.background"}},
		{Fg: "colors.on_surface_variant", Bg: []string{"colors.surface", "colors.surface_container", "colors.surface_container_high"}},
		{Fg: "colors.outline", Bg: surfaces, Dim: true},
		{Fg: "colors.on_primary", Bg: []string{"colors.primary"}},
		{Fg: "colors.on_primary_container", Bg: []string{"colors.primary_container"}},
		{Fg: "colors.on_secondary_container", Bg: []string{"colors.secondary_container"}},
		{Fg: "colors.on_tertiary_container", Bg: []string{"colors.tertiary_container"}},
		{Fg: "colors.on_error_container", Bg: []string{"colors.error_container"}},
	}
	for _, ns := range []string{"dank16", "dank16term"} {
		// color0 is the surface dank16 was built against, but terminals paint colors.background.
		bgs := []string{ns + ".color0", "colors.background"}
		for i := 1; i < 16; i++ {
			pairs = append(pairs, contrastPair{Fg: fmt.Sprintf("%s.color%d", ns, i), Bg: bgs, Dim: i == 8})
		}
	}
	return pairs
}

// Adjustment is one color changed from the theme's. Cause is the changed color it is drawn on
// when that, not the user's own setting for this color, is why it moved.
type Adjustment struct {
	Key       string  `json:"key"`
	From      string  `json:"from"`
	To        string  `json:"to"`
	FromRatio float64 `json:"fromRatio"`
	ToRatio   float64 `json:"toRatio"`
	Target    float64 `json:"target"`
	Cause     string  `json:"cause,omitempty"`
}

func (a Adjustment) String() string {
	return fmt.Sprintf("%-30s %s -> %s  (%.2f -> %.2f:1)", a.Key, a.From, a.To, a.FromRatio, a.ToRatio)
}

// AuditResult is one color against its lowest-contrast background. Original is the theme's own
// ratio, Ratio the rendered one; Target is the user's exact ratio, 0 if none.
type AuditResult struct {
	Key         string  `json:"key"`
	Fg          string  `json:"fg"`
	Bg          string  `json:"bg"`
	Ratio       float64 `json:"ratio"`
	Original    float64 `json:"original"`
	Recommended float64 `json:"recommended"`
	Target      float64 `json:"target"`
	Dim         bool    `json:"dim"`
	Pass        bool    `json:"pass"`
	Cause       string  `json:"cause,omitempty"`
}

func (p contrastPair) backgrounds(palette map[string]string) []string {
	var bgs []string
	for _, key := range p.Bg {
		if hex := palette[key]; hex != "" {
			bgs = append(bgs, hex)
		}
	}
	return bgs
}

// changedBackground is the first of p's backgrounds whose color differs between the two palettes.
func (p contrastPair) changedBackground(before, after map[string]string) string {
	for _, key := range p.Bg {
		if before[key] != after[key] {
			return key
		}
	}
	return ""
}

func worstRatio(fg string, bgs []string) (string, float64) {
	worstBg, worst := "", 0.0
	for _, bg := range bgs {
		if r := dank16.ContrastRatio(fg, bg); worstBg == "" || r < worst {
			worstBg, worst = bg, r
		}
	}
	return worstBg, worst
}

// applyOverrides sets each overridden color in palette (one variant, keyed by palette path) to its
// ratio, and keeps text on a changed background readable. Later pairs see the new values.
func applyOverrides(palette map[string]string, overrides ContrastOverrides) []Adjustment {
	theme := maps.Clone(palette)
	adjustments := []Adjustment{}
	for _, p := range contrastPairs {
		fg := palette[p.Fg]
		bgs := p.backgrounds(palette)
		if fg == "" || len(bgs) == 0 {
			continue
		}
		_, before := worstRatio(fg, bgs)
		target, exact := overrides[p.Fg]
		cause := ""
		var to string
		if exact {
			to = dank16.MatchContrastLstar(fg, bgs, target)
		} else {
			if cause = p.changedBackground(theme, palette); cause == "" {
				continue
			}
			// Changing primary must not leave on_primary less readable than the theme had it,
			// nor below the recommendation, whichever is lower.
			_, own := worstRatio(theme[p.Fg], p.backgrounds(theme))
			target = math.Min(own, p.recommended())
			if before >= target {
				continue
			}
			to = dank16.EnsureContrastLstar(fg, bgs, target)
		}
		if to == fg {
			continue
		}
		_, after := worstRatio(to, bgs)
		palette[p.Fg] = to
		adjustments = append(adjustments, Adjustment{Key: p.Fg, From: fg, To: to, FromRatio: before, ToRatio: after, Target: target, Cause: cause})
	}
	return adjustments
}

// auditPalette judges each color of after; before is the theme's own palette, for Original.
func auditPalette(before, after map[string]string, overrides ContrastOverrides) []AuditResult {
	results := []AuditResult{}
	for _, p := range contrastPairs {
		fg := after[p.Fg]
		bgs := p.backgrounds(after)
		if fg == "" || len(bgs) == 0 {
			continue
		}
		bg, ratio := worstRatio(fg, bgs)
		target, own := overrides[p.Fg]
		cause := p.changedBackground(before, after)
		original := ratio
		if orig := before[p.Fg]; orig != fg || cause != "" {
			if origBgs := p.backgrounds(before); orig != "" && len(origBgs) > 0 {
				_, original = worstRatio(orig, origBgs)
			}
		}
		if own {
			cause = ""
		}
		results = append(results, AuditResult{
			Key: p.Fg, Fg: fg, Bg: bg, Ratio: ratio, Original: original,
			Recommended: p.recommended(), Target: target, Dim: p.Dim, Pass: ratio >= p.recommended(),
			Cause: cause,
		})
	}
	return results
}

// roleMap is role -> variant -> hex. Matugen's own output stores a variant as a bare hex
// string, stock and spec palettes as {"color": hex}; both parse, and import always uses the latter.
type roleMap map[string]map[string]string

func parseRoleMap(raw map[string]any) roleMap {
	roles := roleMap{}
	for role, v := range raw {
		variants, ok := v.(map[string]any)
		if !ok {
			continue
		}
		roles[role] = map[string]string{}
		for variant, val := range variants {
			switch c := val.(type) {
			case string:
				roles[role][variant] = c
			case map[string]any:
				if hex, ok := c["color"].(string); ok {
					roles[role][variant] = hex
				}
			}
		}
	}
	return roles
}

func (r roleMap) importJSON() string {
	out := make(map[string]map[string]map[string]string, len(r))
	for role, variants := range r {
		out[role] = make(map[string]map[string]string, len(variants))
		for variant, hex := range variants {
			out[role][variant] = map[string]string{"color": hex}
		}
	}
	data, _ := json.Marshal(out)
	return string(data)
}

func paletteView(variant string, roles roleMap, palettes map[string]*dank16.VariantPalette) map[string]string {
	view := map[string]string{}
	for role, variants := range roles {
		if hex := variants[variant]; hex != "" {
			view["colors."+role] = hex
		}
	}
	for ns, p := range palettes {
		for i, slot := range p.Slots() {
			view[fmt.Sprintf("%s.color%d", ns, i)] = slot.Variant(variant).Hex
		}
	}
	return view
}

func writeBack(a Adjustment, variant string, roles roleMap, palettes map[string]*dank16.VariantPalette) {
	ns, name, _ := strings.Cut(a.Key, ".")
	if ns == "colors" {
		roles[name][variant] = a.To
		return
	}
	p, ok := palettes[ns]
	if !ok {
		return
	}
	i, err := strconv.Atoi(strings.TrimPrefix(name, "color"))
	if err != nil || i < 0 || i > 15 {
		return
	}
	*p.Slots()[i].Variant(variant) = dank16.NewColorInfo(a.To)
}

// Templates never reference contrastResult: Go writes it into dms-colors.json and the terminal
// configs itself, so a shell older or newer than this binary renders the same templates.
type contrastResult struct {
	Record map[string][]Adjustment
	Audit  map[string][]AuditResult
	// shown is the variant the shell renders: "default", or the mode's when "default" only aliases it.
	shown string
}

// applyContrast changes roles and palettes in place and audits the result. The audit is taken
// here because dms-colors.json writes surface as background and cannot reproduce these ratios.
func applyContrast(overrides ContrastOverrides, roles roleMap, palettes map[string]*dank16.VariantPalette, mode ColorMode) contrastResult {
	res := contrastResult{Record: map[string][]Adjustment{}, Audit: map[string][]AuditResult{}, shown: "default"}
	views := map[string]map[string]string{}
	for _, v := range []string{"dark", "light", "default"} {
		views[v] = paletteView(v, roles, palettes)
	}
	for _, v := range []string{"dark", "light"} {
		res.apply(v, views[v], overrides, roles, palettes)
	}
	if !maps.Equal(views["default"], views[string(mode)]) {
		res.apply("default", views["default"], overrides, roles, palettes)
		return res
	}
	res.shown = string(mode)
	if len(overrides) > 0 {
		aliasDefault(string(mode), roles, palettes)
	}
	return res
}

func (r *contrastResult) apply(variant string, view map[string]string, overrides ContrastOverrides, roles roleMap, palettes map[string]*dank16.VariantPalette) {
	after := view
	if len(overrides) > 0 {
		after = maps.Clone(view)
		adjustments := applyOverrides(after, overrides)
		for _, a := range adjustments {
			writeBack(a, variant, roles, palettes)
		}
		if len(adjustments) > 0 {
			r.Record[variant] = adjustments
		}
	}
	r.Audit[variant] = auditPalette(view, after, overrides)
}

func aliasDefault(mode string, roles roleMap, palettes map[string]*dank16.VariantPalette) {
	for _, variants := range roles {
		if _, ok := variants["default"]; ok {
			variants["default"] = variants[mode]
		}
	}
	for _, p := range palettes {
		for _, slot := range p.Slots() {
			slot.Default = *slot.Variant(mode)
		}
	}
}

// adjusted is key's color in variant after the overrides, or fallback when they left it alone.
func (r contrastResult) adjusted(key, variant, fallback string) string {
	for _, a := range r.Record[variant] {
		if a.Key == key {
			return a.To
		}
	}
	return fallback
}

// terminalAdjustments are the changes in the variant terminals render, for their config header.
func (r contrastResult) terminalAdjustments(alwaysDark bool) []Adjustment {
	variant := r.shown
	if alwaysDark {
		variant = "dark"
	}
	var out []Adjustment
	for _, a := range r.Record[variant] {
		if !strings.HasPrefix(a.Key, "dank16.") {
			out = append(out, a)
		}
	}
	return out
}

// rolesChanged reports whether any theme role moved, i.e. the role map must be re-imported.
func (r contrastResult) rolesChanged() bool {
	for _, adjustments := range r.Record {
		for _, a := range adjustments {
			if strings.HasPrefix(a.Key, "colors.") {
				return true
			}
		}
	}
	return false
}

// withPaletteRecord adds the terminal palette, the adjustment record and the contrast audit to
// the rendered dms-colors.json, so `dms matugen audit` and the settings UI see what apps show.
func withPaletteRecord(colorsJSON []byte, term *dank16.VariantPalette, res contrastResult) ([]byte, error) {
	var doc map[string]any
	if err := json.Unmarshal(colorsJSON, &doc); err != nil {
		return nil, err
	}
	// Same shape as the dank16 section dank.json renders.
	slots := map[string]map[string]string{}
	for i, slot := range term.Slots() {
		slots[fmt.Sprintf("color%d", i)] = map[string]string{"dark": slot.Dark.Hex, "light": slot.Light.Hex, "default": slot.Default.Hex}
	}
	doc["dank16term"] = slots
	doc["adjustments"] = res.Record
	doc["contrast"] = res.Audit
	return json.MarshalIndent(doc, "", "    ")
}

// contrastHeader explains in a terminal config, commented with marker, why colors differ from the theme.
func contrastHeader(adjustments []Adjustment, marker string) string {
	if len(adjustments) == 0 {
		return ""
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s DMS text contrast changed these colors from the theme's (see dms matugen audit):\n", marker)
	for _, a := range adjustments {
		fmt.Fprintf(&b, "%s   %s\n", marker, a)
	}
	return b.String()
}
