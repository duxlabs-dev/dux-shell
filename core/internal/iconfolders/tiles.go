package iconfolders

import (
	"fmt"
	"math"
	"strings"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/duxlabs-dev/dux-go/material/contrast"
	"github.com/duxlabs-dev/dux-go/material/num"
)

// Tile colors: the theme's for every icon; one per app from its own logo; the plate the logo is
// drawn on (edge-match), or its seed where it has none; or a neutral tile with a ring in the app's color.
const (
	TileTheme = "theme"
	TileApp   = "app"
	TileEdge  = "edge"
	TileRing  = "ring"
)

// Color sources: Score picks the most colorful prominent color, the way wallpapers are seeded;
// Common picks the color that covers the most of the logo.
const (
	SourceScore  = "score"
	SourceCommon = "common"
)

// File styles: files and folders on the theme tile, or colored folders and file types without it.
const (
	FilesStandard = "standard"
	FilesColor    = "color"
)

// App styles: each logo in its own colors; each logo repainted in its tile's tones; every app a glyph
// on one theme-hue tile; or on one neutral tile.
const (
	AppColor      = "color"
	AppTinted     = "tinted"
	AppThemed     = "themed"
	AppMonochrome = "monochrome"
)

// Tile styles cap how much of the logo's chroma reaches its tile.
const (
	StyleTonal   = "tonal"
	StyleContent = "content"
	StyleNeutral = "neutral"
)

// ToneAuto leaves TileTone and OwnTone to the pack and the theme.
const ToneAuto = -1

const (
	// Material Blend.harmonize: at most this far, and half the distance, toward the key hue.
	harmonizeMaxDegrees = 15.0
	tonalMaxChroma      = 36.0
	neutralMaxChroma    = 10.0
	// The glyph sits on the tile in a quiet tint of its hue.
	glyphMaxChroma = 12.0

	appTileToneDark  = 30
	appTileToneLight = 90

	// Themed: every app a glyph on one tile in the theme hue, like Android's themed icons.
	themedTileToneDark    = 36
	themedTileToneLight   = 84
	themedTileMaxChroma   = 40
	themedGlyphToneDark   = 94
	themedGlyphMaxDark    = 16
	themedGlyphToneLight  = 24
	themedGlyphMaxLight   = 42
	monochromeTileDark    = 26
	monochromeTileLight   = 88
	monochromeGlyphDark   = 90
	monochromeGlyphLight  = 20
	monochromeMaxChroma   = 4
	uniformBackDropDark   = 10
	uniformBackDropLight  = 12
	uniformLightTileAbove = 60
	// The glyph of a uniform app's tile-free copy sits on the panel, not the tile, so it keeps a mode tone.
	bareToneDark  = 80
	bareToneLight = 40

	ringTileToneDark  = 17
	ringTileToneLight = 98
	ringTileMaxChroma = 4
	ringChroma        = 60
	ringToneDark      = 70
	ringToneLight     = 50
	// The shell icons' glyph on a ring tile, and a tinted logo's tones on its tile.
	ringGlyphToneDark  = 80
	ringGlyphToneLight = 30
	// Tinted: like Android's first themed icons, a dark or light tile under the logo in duotone.
	tintedTileToneDark  = 20
	tintedTileToneLight = 90

	// WCAG ratio for graphics against their background.
	minTileContrast = 3.0
	guardToneStep   = 2.0
	guardToneLow    = 10.0
	guardToneHigh   = 96.0
)

// clampTone makes a user tone 0–100, or ToneAuto for anything negative.
func clampTone(tone int) int {
	if tone < 0 {
		return ToneAuto
	}
	return min(tone, 100)
}

func (o *Options) tileColor() string {
	switch strings.ToLower(o.TileColor) {
	case TileApp:
		return TileApp
	case TileEdge:
		return TileEdge
	case TileRing:
		return TileRing
	}
	return TileTheme
}

func (o *Options) colorSource() string {
	if strings.EqualFold(o.ColorSource, SourceCommon) {
		return SourceCommon
	}
	return SourceScore
}

func (o *Options) tileStyle() string {
	switch strings.ToLower(o.TileStyle) {
	case StyleContent:
		return StyleContent
	case StyleNeutral:
		return StyleNeutral
	}
	return StyleTonal
}

func (o *Options) fileStyle() string {
	if strings.EqualFold(o.FileStyle, FilesColor) {
		return FilesColor
	}
	return FilesStandard
}

// ParseFileStyle checks a file style named on a command line; empty means FilesStandard.
func ParseFileStyle(style string) (string, error) {
	switch strings.ToLower(style) {
	case "", FilesStandard:
		return FilesStandard, nil
	case FilesColor:
		return FilesColor, nil
	}
	return "", fmt.Errorf("bad file style %q: want %s or %s", style, FilesStandard, FilesColor)
}

func (o *Options) appStyle() string {
	switch strings.ToLower(o.AppStyle) {
	case AppTinted:
		return AppTinted
	case AppThemed:
		return AppThemed
	case AppMonochrome:
		return AppMonochrome
	}
	return AppColor
}

// ParseAppStyle checks an app style named on a command line; empty means AppColor.
func ParseAppStyle(style string) (string, error) {
	switch strings.ToLower(style) {
	case "", AppColor:
		return AppColor, nil
	case AppTinted:
		return AppTinted, nil
	case AppThemed:
		return AppThemed, nil
	case AppMonochrome:
		return AppMonochrome, nil
	}
	return "", fmt.Errorf("bad app style %q: want %s, %s, %s or %s", style, AppColor, AppTinted, AppThemed, AppMonochrome)
}

func (o *Options) dark() bool {
	return o.Mode != "light"
}

// themeRamp is the ramp from primary, or primary's hue and chroma at TileTone.
func (o *Options) themeRamp(primary, onPrimary string) (Ramp, error) {
	tone := clampTone(o.TileTone)
	if tone == ToneAuto {
		return NewRamp(primary, onPrimary)
	}
	hct, err := parseHct(primary)
	if err != nil {
		return Ramp{}, fmt.Errorf("primary: %w", err)
	}
	return tileRamp(color.Hct{Hue: hct.Hue, Chroma: hct.Chroma, Tone: float64(tone)}), nil
}

func parseHct(hex string) (color.Hct, error) {
	var c color.ARGB
	if err := c.UnmarshalText([]byte(strings.TrimSpace(hex))); err != nil {
		return color.Hct{}, err
	}
	return c.ToHct(), nil
}

// tileRamp derives the back plate and glyph from the tile color the way NewRamp does without on_primary.
func tileRamp(tile color.Hct) Ramp {
	return Ramp{Front: hexOf(tile.ToARGB()), Back: hexOf(backOf(tile).ToARGB()), Glyph: hexOf(glyphOf(tile).ToARGB())}
}

func glyphOf(tile color.Hct) color.Hct {
	glyphTone := 90.0
	if tile.Tone >= 60 {
		glyphTone = 20
	}
	return color.Hct{Hue: tile.Hue, Chroma: min(tile.Chroma, glyphMaxChroma), Tone: glyphTone}
}

func backOf(tile color.Hct) color.Hct {
	return color.Hct{Hue: tile.Hue, Chroma: tile.Chroma, Tone: max(tile.Tone-backToneDrop, backToneFloor)}
}

// harmonize turns hue toward keyHue by half the distance, at most 15 degrees, the shorter way round.
func harmonize(hue, keyHue float64) float64 {
	rotation := min(num.DifferenceDegrees(hue, keyHue)*0.5, harmonizeMaxDegrees)
	// Material's sanitizeDegrees: [0, 360), so a full turn lands on 0.
	turned := math.Mod(hue+rotation*num.RotationDirection(hue, keyHue), 360)
	if turned < 0 {
		turned += 360
	}
	return turned
}

func styleChroma(chroma float64, style string) float64 {
	switch style {
	case StyleContent:
		return chroma
	case StyleNeutral:
		return min(chroma, neutralMaxChroma)
	}
	return min(chroma, tonalMaxChroma)
}

// guardTone moves the tile away from the tone that sits on it until they reach a 3:1 contrast,
// stopping at tone 10 or 96. A tie moves toward the mode's own side: darker in dark mode.
func guardTone(tone, against float64, dark bool) float64 {
	dir := 1.0
	if against > tone || (against == tone && dark) {
		dir = -1
	}
	return guardToward(tone, against, dir)
}

// guardEither is guardTone that turns the other way when its own side runs out of tones before 3:1.
func guardEither(tone, against float64, dark bool) float64 {
	guarded := guardTone(tone, against, dark)
	if contrast.RatioOfTones(guarded, against) >= minTileContrast {
		return guarded
	}
	dir := 1.0
	if guarded > against {
		dir = -1
	}
	other := guardToward(tone, against, dir)
	if contrast.RatioOfTones(other, against) > contrast.RatioOfTones(guarded, against) {
		return other
	}
	return guarded
}

func guardToward(tone, against, dir float64) float64 {
	for contrast.RatioOfTones(tone, against) < minTileContrast {
		if dir < 0 {
			if tone <= guardToneLow {
				break
			}
			tone = max(tone-guardToneStep, guardToneLow)
		} else {
			if tone >= guardToneHigh {
				break
			}
			tone = min(tone+guardToneStep, guardToneHigh)
		}
	}
	return tone
}

// tileSpec is what every app tile shares; only the logo differs per app.
type tileSpec struct {
	color   string
	primary color.Hct
	keyHue  float64
	style   string
	tone    int
	dark    bool
	app     string
}

func (o *Options) tileSpec(primary string) (tileSpec, error) {
	hct, err := parseHct(primary)
	if err != nil {
		return tileSpec{}, fmt.Errorf("primary: %w", err)
	}
	return tileSpec{
		color: o.tileColor(), primary: hct, keyHue: hct.Hue, style: o.tileStyle(),
		tone: clampTone(o.TileTone), dark: o.dark(), app: o.appStyle(),
	}, nil
}

// logo is what sampling an app's icon found: a seed color, the plate it is drawn on, or neither.
type logo struct {
	seed   color.Hct
	seeded bool
	plate  color.ARGB
	plated bool
	reach  float64
}

// tileJSON is one app's entry in the generator's --tiles file, or one of its shell and dux palettes.
type tileJSON struct {
	Tile  string  `json:"tile"`
	Glyph string  `json:"glyph"`
	Back  string  `json:"back"`
	Ring  string  `json:"ring,omitempty"`
	Reach float64 `json:"reach,omitempty"`
	// Tint is the color whose hue a dux app's art is retoned to; only the dux palette has one.
	Tint string `json:"tint,omitempty"`
	// Cutout is a white-on-transparent PNG of the logo's mark, its own plate removed, for the themed styles.
	Cutout string `json:"cutout,omitempty"`
	// Bare is the glyph color of the tile-free copy the bar and notifications show; only the themed styles set it.
	Bare string `json:"bare,omitempty"`
}

// tilesFile is the generator's --tiles file: per-app tiles, the DMS shell icons' palette,
// and the palette of the tiled copies of the pack's own dev.duxlabs.* apps.
type tilesFile struct {
	Apps  map[string]tileJSON `json:"apps"`
	Shell *tileJSON           `json:"shell,omitempty"`
	Dux   *tileJSON           `json:"dux,omitempty"`
}

func (f tilesFile) empty() bool {
	return len(f.Apps) == 0 && f.Shell == nil && f.Dux == nil
}

func tileOf(r Ramp) tileJSON {
	return tileJSON{Tile: r.Front, Glyph: r.Glyph, Back: r.Back}
}

// tileFor colors one app. Without a seed of its own an app takes the theme primary, so the set doesn't mix tile tones.
func (s tileSpec) tileFor(l logo) tileJSON {
	seed := s.primary
	if l.seeded {
		seed = l.seed
	}
	switch {
	case s.color == TileRing:
		return ringTile(seed, s, s.app == AppTinted)
	// A tinted logo is repainted, so its own plate or color would not match the tile.
	case s.color == TileEdge && s.app != AppTinted && l.plated:
		return edgeTile(l)
	case s.color == TileEdge && s.app != AppTinted && l.seeded:
		return tileOf(seedTile(l.seed, s))
	}
	return tileOf(appTile(seed, s))
}

// uniform reports whether every app, the shell and dux icons alike, wears one tile whatever its logo.
func (s tileSpec) uniform() bool {
	return s.app == AppThemed || s.app == AppMonochrome
}

// uniformTile is the one tile of the themed styles: the theme hue, or a near-neutral tinted by it, under a light
// or dark glyph. A set tile tone moves the tile, and the glyph turns to whichever side of it reads; the bare
// glyph stays at the mode's tone, since the panel under it does not move.
func (s tileSpec) uniformTile() tileJSON {
	tileTone, tileChroma := float64(themedTileToneDark), min(s.primary.Chroma, themedTileMaxChroma)
	if !s.dark {
		tileTone = themedTileToneLight
	}
	if s.app == AppMonochrome {
		tileChroma, tileTone = min(s.primary.Chroma, monochromeMaxChroma), monochromeTileDark
		if !s.dark {
			tileTone = monochromeTileLight
		}
	}
	if s.tone != ToneAuto {
		tileTone = float64(s.tone)
	}

	glyph := color.Hct{Hue: s.primary.Hue}
	switch {
	case s.app == AppMonochrome && tileTone < uniformLightTileAbove:
		glyph.Chroma, glyph.Tone = tileChroma, monochromeGlyphDark
	case s.app == AppMonochrome:
		glyph.Chroma, glyph.Tone = tileChroma, monochromeGlyphLight
	case tileTone < uniformLightTileAbove:
		glyph.Chroma, glyph.Tone = min(s.primary.Chroma, themedGlyphMaxDark), themedGlyphToneDark
	default:
		glyph.Chroma, glyph.Tone = min(s.primary.Chroma, themedGlyphMaxLight), themedGlyphToneLight
	}

	drop := float64(uniformBackDropDark)
	if !s.dark {
		drop = uniformBackDropLight
	}
	bare := color.Hct{Hue: s.primary.Hue, Chroma: tileChroma, Tone: bareToneDark}
	if !s.dark {
		bare.Tone = bareToneLight
	}
	tile := color.Hct{Hue: s.primary.Hue, Chroma: tileChroma, Tone: tileTone}
	back := color.Hct{Hue: s.primary.Hue, Chroma: tileChroma, Tone: max(tileTone-drop, 0)}
	return tileJSON{Tile: hexOf(tile.ToARGB()), Glyph: hexOf(glyph.ToARGB()), Back: hexOf(back.ToARGB()), Bare: hexOf(bare.ToARGB())}
}

// edgeTile is the plate the logo is drawn on, exactly, so the tile and the logo's own plate read as one.
func edgeTile(l logo) tileJSON {
	plate := l.plate.ToHct()
	return tileJSON{
		Tile:  hexOf(l.plate),
		Glyph: hexOf(glyphOf(plate).ToARGB()),
		Back:  hexOf(backOf(plate).ToARGB()),
		Reach: math.Round(l.reach*1000) / 1000,
	}
}

// seedTile is the seed itself, unharmonized and uncapped, only moved off the logo's tone until it reads.
func seedTile(seed color.Hct, s tileSpec) Ramp {
	return tileRamp(color.Hct{Hue: seed.Hue, Chroma: seed.Chroma, Tone: guardEither(seed.Tone, seed.Tone, s.dark)})
}

// ringTile is a near-neutral tile in the theme's hue, ringed in the logo's own hue. A painted glyph, the shell
// icons', is drawn in the ring glyph tone, so that is what the tile must clear instead of the logo.
func ringTile(seed color.Hct, s tileSpec, painted bool) tileJSON {
	tone, ringTone := float64(ringTileToneDark), float64(ringToneDark)
	glyphTone := float64(ringGlyphToneDark)
	if !s.dark {
		tone, ringTone, glyphTone = ringTileToneLight, ringToneLight, ringGlyphToneLight
	}
	if s.tone != ToneAuto {
		tone = float64(s.tone)
	}
	chroma := min(s.primary.Chroma, ringTileMaxChroma)
	against := seed.Tone
	if painted {
		against = glyphTone
	}
	tile := color.Hct{Hue: s.primary.Hue, Chroma: chroma, Tone: guardTone(tone, against, s.dark)}
	// A gray seed, only ever a gray theme primary, has an arbitrary hue; at full chroma that rings in a stray color.
	ringC := float64(ringChroma)
	if seed.Chroma < minSeedChroma {
		ringC = min(seed.Chroma, ringTileMaxChroma)
	}
	ring := color.Hct{Hue: seed.Hue, Chroma: ringC, Tone: guardEither(ringTone, tile.Tone, s.dark)}
	r := tileRamp(tile)
	if painted {
		r.Glyph = hexOf(color.Hct{Hue: tile.Hue, Chroma: chroma, Tone: glyphTone}.ToARGB())
	}
	p := tileOf(r)
	p.Ring = hexOf(ring.ToARGB())
	return p
}

// appTile colors an app's tile from its logo's seed, harmonized toward the theme so a dock still reads as one set.
func appTile(seed color.Hct, s tileSpec) Ramp {
	hue := harmonize(seed.Hue, s.keyHue)
	chroma := styleChroma(seed.Chroma, s.style)
	if s.app == AppTinted {
		return tintedTile(hue, chroma, s)
	}
	tone := float64(appTileToneDark)
	if !s.dark {
		tone = appTileToneLight
	}
	if s.tone != ToneAuto {
		tone = float64(s.tone)
	}
	// The logo keeps its own colors, and the seed stands for them.
	return tileRamp(color.Hct{Hue: hue, Chroma: chroma, Tone: guardTone(tone, seed.Tone, s.dark)})
}

// tintedTile is a tinted app's tile: the pack repaints the logo in the glyph's tones, so the glyph is what
// must read on it.
func tintedTile(hue, chroma float64, s tileSpec) Ramp {
	tone, glyphTone := float64(tintedTileToneDark), float64(ringGlyphToneDark)
	if !s.dark {
		tone, glyphTone = tintedTileToneLight, ringGlyphToneLight
	}
	if s.tone != ToneAuto {
		tone = float64(s.tone)
	}
	tile := color.Hct{Hue: hue, Chroma: chroma, Tone: guardTone(tone, glyphTone, s.dark)}
	glyph := color.Hct{Hue: hue, Chroma: chroma, Tone: glyphTone}
	return Ramp{Front: hexOf(tile.ToARGB()), Back: hexOf(backOf(tile).ToARGB()), Glyph: hexOf(glyph.ToARGB())}
}

// ownPalettes colors the pack's own icons in the color and tinted styles: the DMS shell icons and the tiled
// dev.duxlabs.* apps. Ring tiles put both on the vendor apps' neutral tile, ringed in the theme hue.
// Otherwise the shell icons wear an unseeded vendor app's tile so a dock reads as one set, and the dux apps
// keep the theme tile unless tinted. When vendorTiled is false, every vendor app and both sets wear the theme tile.
func (s tileSpec) ownPalettes(ramp Ramp, vendorTiled bool) (shell, dux *tileJSON) {
	if !vendorTiled {
		return nil, nil
	}
	tinted := s.app == AppTinted
	if s.color != TileRing {
		p := s.tileFor(logo{})
		if tinted {
			d := p
			return &p, &d
		}
		return &p, nil
	}

	// The dux art keeps its own tones, retoned to the tile hue, on an unseeded vendor app's tile.
	d := ringTile(s.primary, s, tinted)
	if !tinted {
		d.Tint = ramp.Front
	}

	glyphTone := float64(ringGlyphToneDark)
	if !s.dark {
		glyphTone = ringGlyphToneLight
	}
	g := ringTile(s.primary, s, true)
	g.Glyph = hexOf(color.Hct{Hue: s.primary.Hue, Chroma: s.primary.Chroma, Tone: glyphTone}.ToARGB())
	return &g, &d
}

// uniformPalettes puts the shell icons and the dux apps on the themed styles' one tile, the dux art in its glyph color.
func (s tileSpec) uniformPalettes() (shell, dux *tileJSON) {
	t := s.uniformTile()
	d := t
	d.Tint = t.Glyph
	return &t, &d
}
