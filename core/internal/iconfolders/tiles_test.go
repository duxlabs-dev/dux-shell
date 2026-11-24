package iconfolders

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"image"
	imgcolor "image/color"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/duxlabs-dev/dux-go/material/contrast"
	"github.com/duxlabs-dev/dux-shell/core/internal/colorseed"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func toneOf(t *testing.T, hex string) float64 {
	t.Helper()
	hct, err := parseHct(hex)
	require.NoError(t, err)
	return hct.Tone
}

func hctOf(t *testing.T, hex string) color.Hct {
	t.Helper()
	hct, err := parseHct(hex)
	require.NoError(t, err)
	return hct
}

func TestHarmonize(t *testing.T) {
	tests := []struct {
		name     string
		hue, key float64
		want     float64
	}{
		{name: "far hues turn the full 15 degrees", hue: 30, key: 90, want: 45},
		{name: "near hues turn half the distance", hue: 80, key: 90, want: 85},
		{name: "downward", hue: 90, key: 80, want: 85},
		{name: "the short way across zero, upward", hue: 350, key: 10, want: 0},
		{name: "the short way across zero, downward", hue: 10, key: 350, want: 0},
		{name: "the long way is never taken", hue: 20, key: 300, want: 5},
		{name: "the same hue stays", hue: 100, key: 100, want: 100},
		{name: "half a turn rotates by the cap", hue: 0, key: 180, want: 15},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			assert.InDelta(t, tc.want, harmonize(tc.hue, tc.key), 1e-9)
		})
	}
}

func TestStyleChroma(t *testing.T) {
	tests := []struct {
		style  string
		chroma float64
		want   float64
	}{
		{StyleTonal, 80, 36},
		{StyleTonal, 20, 20},
		{StyleContent, 80, 80},
		{StyleContent, 5, 5},
		{StyleNeutral, 80, 10},
		{StyleNeutral, 4, 4},
	}
	for _, tc := range tests {
		assert.Equal(t, tc.want, styleChroma(tc.chroma, tc.style), "%s %v", tc.style, tc.chroma)
	}
}

func TestGuardTone(t *testing.T) {
	tests := []struct {
		name          string
		tone, against float64
		dark          bool
		want          float64
	}{
		{name: "enough contrast stays", tone: 30, against: 80, dark: true, want: 30},
		{name: "a lighter logo darkens the tile", tone: 30, against: 40, dark: true, want: 10},
		{name: "a set tone the logo matches is guarded too", tone: 80, against: 52, dark: true, want: 88},
		{name: "a darker logo lightens the tile", tone: 30, against: 20, dark: true, want: 52},
		{name: "light tile under a mid logo stays", tone: 90, against: 40, want: 90},
		{name: "light tile under a pale logo stops at 96", tone: 90, against: 85, want: 96},
		{name: "light tile under a paler logo darkens", tone: 90, against: 95, want: 56},
		{name: "a tie moves darker in dark mode", tone: 50, against: 50, dark: true, want: 18},
		{name: "a tie moves lighter in light mode", tone: 50, against: 50, want: 86},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := guardTone(tc.tone, tc.against, tc.dark)
			assert.Equal(t, tc.want, got)
			if got > guardToneLow && got < guardToneHigh {
				assert.GreaterOrEqual(t, contrast.RatioOfTones(got, tc.against), minTileContrast)
			}
		})
	}
}

func TestAppTile(t *testing.T) {
	primary := hctOf(t, "#69b2ff")
	red := hctOf(t, "#e53935")
	navy := color.Hct{Hue: 260, Chroma: 40, Tone: 25}
	tests := []struct {
		name                  string
		seed                  color.Hct
		spec                  tileSpec
		tile, glyph, back     float64
		maxChroma, wantChroma float64
	}{
		{name: "dark tonal darkens below the logo", seed: red, spec: tileSpec{style: StyleTonal, tone: ToneAuto, dark: true}, tile: 20, glyph: 90, back: 10, maxChroma: 36},
		{name: "light content keeps 90", seed: red, spec: tileSpec{style: StyleContent, tone: ToneAuto}, tile: 90, glyph: 20, back: 78},
		{name: "a dark logo lifts a dark-mode tile", seed: navy, spec: tileSpec{style: StyleTonal, tone: ToneAuto, dark: true}, tile: 56, glyph: 90, back: 44},
		{name: "a set tone replaces the mode's", seed: navy, spec: tileSpec{style: StyleTonal, tone: 80, dark: true}, tile: 80, glyph: 20, back: 68},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			tc.spec.keyHue = primary.Hue
			ramp := appTile(tc.seed, tc.spec)
			assert.InDelta(t, tc.tile, toneOf(t, ramp.Front), 0.6)
			assert.InDelta(t, tc.glyph, toneOf(t, ramp.Glyph), 0.6)
			assert.InDelta(t, tc.back, toneOf(t, ramp.Back), 0.6)
			front := hctOf(t, ramp.Front)
			if tc.maxChroma > 0 {
				assert.LessOrEqual(t, front.Chroma, tc.maxChroma+1)
			}
			if front.Chroma > 5 {
				assert.InDelta(t, harmonize(tc.seed.Hue, primary.Hue), front.Hue, 3, "the tile takes the harmonized hue")
			}
		})
	}
}

func TestThemeRamp(t *testing.T) {
	o := Options{TileTone: ToneAuto}
	auto, err := o.themeRamp("#69b2ff", "#003055")
	require.NoError(t, err)
	today, err := NewRamp("#69b2ff", "#003055")
	require.NoError(t, err)
	assert.Equal(t, today, auto, "auto is today's ramp")
	fresh := NewOptions()
	auto, err = fresh.themeRamp("#69b2ff", "#003055")
	require.NoError(t, err)
	assert.Equal(t, today, auto, "NewOptions keeps today's ramp, not a tone-0 one")

	for _, tc := range []struct{ tone, glyph int }{{40, 90}, {75, 20}, {100, 20}} {
		o.TileTone = tc.tone
		ramp, err := o.themeRamp("#69b2ff", "#003055")
		require.NoError(t, err)
		front, primary := hctOf(t, ramp.Front), hctOf(t, "#69b2ff")
		assert.InDelta(t, float64(tc.tone), front.Tone, 0.6)
		if front.Chroma > 5 {
			assert.InDelta(t, primary.Hue, front.Hue, 2)
		}
		assert.InDelta(t, float64(tc.glyph), toneOf(t, ramp.Glyph), 0.6)
		assert.InDelta(t, max(float64(tc.tone)-backToneDrop, backToneFloor), toneOf(t, ramp.Back), 0.6)
		assert.LessOrEqual(t, hctOf(t, ramp.Glyph).Chroma, glyphMaxChroma+1)
	}

	o.TileTone = 250
	high, err := o.themeRamp("#69b2ff", "")
	require.NoError(t, err)
	assert.InDelta(t, 100, toneOf(t, high.Front), 0.6, "tones clamp to 100")

	o.TileTone = 50
	_, err = o.themeRamp("not a color", "")
	require.Error(t, err)
}

func TestTileOptionsDefault(t *testing.T) {
	var o Options
	assert.Equal(t, TileTheme, o.tileColor())
	assert.Equal(t, SourceScore, o.colorSource())
	assert.Equal(t, StyleTonal, o.tileStyle())
	o = Options{TileColor: "App", ColorSource: "common", TileStyle: "NEUTRAL"}
	assert.Equal(t, TileApp, o.tileColor())
	assert.Equal(t, SourceCommon, o.colorSource())
	assert.Equal(t, StyleNeutral, o.tileStyle())
	o = Options{TileColor: "Edge"}
	assert.Equal(t, TileEdge, o.tileColor())
	o = Options{TileColor: "ring"}
	assert.Equal(t, TileRing, o.tileColor())
	o = Options{TileColor: "bogus", ColorSource: "bogus", TileStyle: "content"}
	assert.Equal(t, TileTheme, o.tileColor())
	assert.Equal(t, SourceScore, o.colorSource())
	assert.Equal(t, StyleContent, o.tileStyle())
	assert.Equal(t, FilesStandard, o.fileStyle())
	for style, want := range map[string]string{"": FilesStandard, "standard": FilesStandard, "Color": FilesColor, "color": FilesColor, "bogus": FilesStandard} {
		o = Options{FileStyle: style}
		assert.Equal(t, want, o.fileStyle(), style)
	}
	assert.Equal(t, ToneAuto, clampTone(-7))
	assert.Equal(t, 0, clampTone(0))
	assert.Equal(t, 100, clampTone(101))
}

// A pack that lists --tiles, as every case here but the last test's.
func TestGeneratorArgs(t *testing.T) {
	ramp := Ramp{Front: "#111111", Glyph: "#222222", Back: "#333333"}
	today := []string{"--out", "/o", "--name", "Dux Icons", "--tile", "#111111", "--glyph", "#222222", "--back", "#333333", "--app-style", "color", "--no-gradient"}
	tests := []struct {
		name  string
		opts  Options
		tiles string
		want  []string
		err   string
	}{
		{name: "defaults are today's args", opts: Options{TileTone: ToneAuto, OwnTone: ToneAuto}, want: today},
		{name: "NewOptions leaves both tones automatic", opts: NewOptions(), want: today},
		{name: "theme tiles and style options add nothing", opts: Options{TileTone: ToneAuto, OwnTone: ToneAuto, TileColor: TileTheme, ColorSource: SourceCommon, TileStyle: StyleNeutral}, want: today},
		{name: "themed, gradient, shape", opts: Options{TileTone: ToneAuto, OwnTone: ToneAuto, AppStyle: AppThemed, Gradient: true, Shape: "squircle"},
			want: []string{"--out", "/o", "--name", "Dux Icons", "--tile", "#111111", "--glyph", "#222222", "--back", "#333333", "--app-style", "themed", "--gradient", "--shape", "squircle"}},
		{name: "monochrome drops the own tone", opts: Options{TileTone: ToneAuto, OwnTone: 40, AppStyle: "Monochrome"},
			want: []string{"--out", "/o", "--name", "Dux Icons", "--tile", "#111111", "--glyph", "#222222", "--back", "#333333", "--app-style", "monochrome", "--no-gradient"}},
		{name: "own tone", opts: Options{TileTone: ToneAuto, OwnTone: 40}, want: append(append([]string{}, today...), "--own-tone", "40")},
		{name: "own tone 0 is a tone", opts: Options{TileTone: ToneAuto, OwnTone: 0}, want: append(append([]string{}, today...), "--own-tone", "0")},
		{name: "own tone clamps", opts: Options{TileTone: ToneAuto, OwnTone: 140}, want: append(append([]string{}, today...), "--own-tone", "100")},
		{name: "tile tone only moves the ramp", opts: Options{TileTone: 60, OwnTone: ToneAuto}, want: today},
		{name: "tiles file", opts: Options{TileTone: ToneAuto, OwnTone: ToneAuto}, tiles: "/tmp/p.json", want: append(append([]string{}, today...), "--tiles", "/tmp/p.json")},
		{name: "everything", opts: Options{TileTone: ToneAuto, OwnTone: 85, Shape: "square"}, tiles: "/p",
			want: []string{"--out", "/o", "--name", "Dux Icons", "--tile", "#111111", "--glyph", "#222222", "--back", "#333333", "--app-style", "color", "--no-gradient", "--shape", "square", "--own-tone", "85", "--tiles", "/p"}},
		{name: "standard files add nothing", opts: Options{TileTone: ToneAuto, OwnTone: ToneAuto, FileStyle: FilesStandard}, want: today},
		{name: "an unknown file style is standard", opts: Options{TileTone: ToneAuto, OwnTone: ToneAuto, FileStyle: "papirus"}, want: today},
		{name: "color files", opts: Options{TileTone: ToneAuto, OwnTone: ToneAuto, FileStyle: FilesColor}, want: append(append([]string{}, today...), "--files-style", "color")},
		{name: "color files before the tiles", opts: Options{TileTone: ToneAuto, OwnTone: 85, FileStyle: "Color"}, tiles: "/p",
			want: append(append([]string{}, today...), "--own-tone", "85", "--files-style", "color", "--tiles", "/p")},
		{name: "bad shape", opts: Options{Shape: "../x"}, err: "bad icon shape"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			args, err := tc.opts.generatorArgs("/o", ramp, generatorFlags{tiles: true, appStyle: true, ownTone: true, filesStyle: true}, tc.tiles)
			if tc.err != "" {
				require.ErrorContains(t, err, tc.err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tc.want, args)
		})
	}
}

// The released pack has neither --tile nor --tiles: it takes the tile color as --badge, never a tiles file,
// and none of the newer flags.
func TestGeneratorArgsForAPackBeforeTiles(t *testing.T) {
	ramp := Ramp{Front: "#111111", Glyph: "#222222", Back: "#333333"}
	o := Options{TileTone: ToneAuto, OwnTone: 85, Shape: "square", FileStyle: FilesColor}
	args, err := o.generatorArgs("/o", ramp, generatorFlags{}, "/p")
	require.NoError(t, err)
	assert.Equal(t, []string{"--out", "/o", "--name", "Dux Icons", "--badge", "#111111", "--glyph", "#222222", "--back", "#333333", "--no-mono", "--no-gradient", "--shape", "square"}, args)
	// A tiled pack with no --own-tone or --files-style.
	args, err = o.generatorArgs("/o", ramp, generatorFlags{tiles: true, appStyle: true}, "/p")
	require.NoError(t, err)
	assert.NotContains(t, args, "--own-tone")
	assert.NotContains(t, args, "--files-style")
	assert.Equal(t, "--tile", o.styleArgs(ramp, generatorFlags{tiles: true})[0])
	assert.Equal(t, "--badge", o.styleArgs(ramp, generatorFlags{})[0])

	// A pack with no --app-style knows the tinted style only as --mono, and has no glyph styles.
	for style, want := range map[string]string{AppColor: "--no-mono", AppTinted: "--mono", AppThemed: "--mono", AppMonochrome: "--mono"} {
		o.AppStyle = style
		args := o.styleArgs(ramp, generatorFlags{tiles: true})
		assert.Contains(t, args, want, style)
		assert.NotContains(t, args, "--app-style", style)
	}
}

func TestParseGeneratorFlags(t *testing.T) {
	tests := []struct {
		help string
		want generatorFlags
	}{
		{"usage: dux-icons [-h] [--badge HEX] [--mono]", generatorFlags{}},
		{"usage: dux-icons [-h] [--tile HEX] [--tiles FILE] [--mono]", generatorFlags{tiles: true}},
		{"usage: dux-icons [--tile HEX] [--app-style {color,themed,monochrome}] [--tiles FILE]", generatorFlags{tiles: true, appStyle: true}},
		{"usage: dux-icons [--tile HEX] [--app-style STYLE] [--tiles FILE] [--own-tone L] [--files-style {standard,color}]",
			generatorFlags{tiles: true, appStyle: true, ownTone: true, filesStyle: true}},
	}
	for _, tc := range tests {
		assert.Equal(t, tc.want, parseGeneratorFlags([]byte(tc.help)), tc.help)
	}
}

func TestParseFileStyle(t *testing.T) {
	for in, want := range map[string]string{"": FilesStandard, "standard": FilesStandard, "STANDARD": FilesStandard, "color": FilesColor, "Color": FilesColor} {
		got, err := ParseFileStyle(in)
		require.NoError(t, err, in)
		assert.Equal(t, want, got, in)
	}
	for _, bad := range []string{"base", "colour", "papirus", " color"} {
		_, err := ParseFileStyle(bad)
		assert.ErrorContains(t, err, "bad file style", bad)
	}
}

func TestAppStyle(t *testing.T) {
	for in, want := range map[string]string{"": AppColor, "color": AppColor, "Tinted": AppTinted, "Themed": AppThemed, "monochrome": AppMonochrome} {
		got, err := ParseAppStyle(in)
		require.NoError(t, err, in)
		assert.Equal(t, want, got, in)
		o := Options{AppStyle: in}
		assert.Equal(t, want, o.appStyle(), in)
	}
	for _, bad := range []string{"mono", "true", " themed"} {
		_, err := ParseAppStyle(bad)
		assert.ErrorContains(t, err, "bad app style", bad)
		o := Options{AppStyle: bad}
		assert.Equal(t, AppColor, o.appStyle(), bad)
	}
}

func TestTintedTiles(t *testing.T) {
	primary := hctOf(t, "#69b2ff")
	ramp, err := NewRamp("#69b2ff", "#003055")
	require.NoError(t, err)
	red := hctOf(t, "#e02020")
	plated := logo{seed: red, seeded: true, plate: color.ARGB(0xffe02020), plated: true, reach: 0.8}
	spec := tileSpec{primary: primary, keyHue: primary.Hue, style: StyleTonal, tone: ToneAuto, app: AppTinted}

	for _, dark := range []bool{true, false} {
		s := spec
		s.dark = dark
		tileTone, glyphTone := float64(tintedTileToneLight), float64(ringGlyphToneLight)
		if dark {
			tileTone, glyphTone = tintedTileToneDark, ringGlyphToneDark
		}
		for _, tile := range []string{TileApp, TileEdge} {
			s.color = tile
			name := fmt.Sprintf("%s dark=%v", tile, dark)
			got := s.tileFor(plated)
			assert.InDelta(t, tileTone, toneOf(t, got.Tile), 0.6, "%s: the duotone tile", name)
			assert.InDelta(t, glyphTone, toneOf(t, got.Glyph), 0.6, "%s: the logo's tones", name)
			assert.Zero(t, got.Reach, "%s: a repainted logo never takes its own plate", name)
			assert.InDelta(t, harmonize(red.Hue, primary.Hue), hctOf(t, got.Tile).Hue, 3, "%s: the logo's hue", name)
		}

		// The dux apps are repainted like an unseeded vendor app.
		s.color = TileApp
		shell, dux := s.ownPalettes(ramp, true)
		require.NotNil(t, dux)
		assert.Equal(t, *shell, *dux)
		assert.Empty(t, dux.Tint)

		s.color = TileRing
		ringed := s.tileFor(logo{seed: red, seeded: true})
		assert.InDelta(t, glyphTone, toneOf(t, ringed.Glyph), 0.6, "dark=%v: the ring tile clears the repainted logo", dark)
		_, dux = s.ownPalettes(ramp, true)
		assert.Empty(t, dux.Tint, "dark=%v", dark)
	}
}

// writePNG draws a square plate of fill under a small black mark, on a transparent background.
func writePNG(t *testing.T, path string, fill imgcolor.NRGBA) {
	t.Helper()
	img := image.NewNRGBA(image.Rect(0, 0, 32, 32))
	for y := 4; y < 28; y++ {
		for x := 4; x < 28; x++ {
			img.SetNRGBA(x, y, fill)
			if x >= 13 && x < 19 && y >= 13 && y < 19 {
				img.SetNRGBA(x, y, imgcolor.NRGBA{A: 255})
			}
		}
	}
	f, err := os.Create(path)
	require.NoError(t, err)
	defer f.Close()
	require.NoError(t, png.Encode(f, img))
}

func TestPlateSeedCache(t *testing.T) {
	dir := t.TempDir()
	state := filepath.Join(dir, "state")
	red, gray := filepath.Join(dir, "red.png"), filepath.Join(dir, "gray.png")
	writePNG(t, red, imgcolor.NRGBA{R: 0xe5, G: 0x39, B: 0x35, A: 0xff})
	writePNG(t, gray, imgcolor.NRGBA{R: 0x80, G: 0x80, B: 0x80, A: 0xff})
	broken := filepath.Join(dir, "broken.svg")
	require.NoError(t, os.WriteFile(broken, []byte("<svg"), 0o644))
	sources := map[string]string{"red": red, "also-red": red, "gray": gray, "broken": broken, "gone": filepath.Join(dir, "gone.png")}

	seeds := loadPlateSeeds(state)
	found := seeds.resolve(sources, SourceScore)
	seeds.save(sources)
	assert.ElementsMatch(t, []string{"red", "also-red", "gray"}, keys(found), "broken files are skipped")
	assert.InDelta(t, hctOf(t, "#e53935").Hue, found["red"].seed.Hue, 2)
	gl := found["gray"]
	assert.False(t, gl.seeded, "gray has no color")
	assert.True(t, gl.plated, "but it is a plate")
	assert.Equal(t, color.NewARGB(255, 0x80, 0x80, 0x80), gl.plate)
	assert.InDelta(t, 0.75*math.Sqrt2, gl.reach, 0.02)
	require.FileExists(t, filepath.Join(state, PlateSeedsFile))

	cached := loadPlateSeeds(state)
	assert.Len(t, cached.Entries, 3, "one entry per sampled file, the colorless ones too")
	assert.Equal(t, "", cached.Entries[plateSeedKey(gray, SourceScore)].Seed)

	// A forged entry for the file as it is proves the cache is read, not the file.
	entry := cached.Entries[plateSeedKey(red, SourceScore)]
	entry.Seed = "#00FF00"
	cached.Entries[plateSeedKey(red, SourceScore)] = entry
	found = cached.resolve(sources, SourceScore)
	assert.InDelta(t, hctOf(t, "#00ff00").Hue, found["red"].seed.Hue, 0.01)
	assert.False(t, cached.dirty, "a cache hit writes nothing")

	found = cached.resolve(sources, SourceCommon)
	assert.InDelta(t, hctOf(t, "#e53935").Hue, found["red"].seed.Hue, 2)
	assert.True(t, cached.dirty)

	writePNG(t, red, imgcolor.NRGBA{R: 0x1e, G: 0x88, B: 0xe5, A: 0xff})
	future := entry.ModTime + 5e9
	require.NoError(t, os.Chtimes(red, time.Unix(0, future), time.Unix(0, future)))
	found = cached.resolve(sources, SourceScore)
	assert.InDelta(t, hctOf(t, "#1e88e5").Hue, found["red"].seed.Hue, 3)

	cached.save(map[string]string{"red": red})
	reread := loadPlateSeeds(state)
	for key := range reread.Entries {
		assert.True(t, strings.HasPrefix(key, red+"|"), key)
	}
	assert.Len(t, reread.Entries, 2)

	require.NoError(t, os.WriteFile(filepath.Join(state, PlateSeedsFile), []byte("junk"), 0o644))
	assert.Empty(t, loadPlateSeeds(state).Entries, "a broken cache starts over")

	info, err := os.Stat(red)
	require.NoError(t, err)
	old := fmt.Sprintf(`{"entries":{%q:{"size":%d,"modTime":%d,"seed":"#00ff00"}}}`, plateSeedKey(red, SourceScore), info.Size(), info.ModTime().UnixNano())
	require.NoError(t, os.WriteFile(filepath.Join(state, PlateSeedsFile), []byte(old), 0o644))
	stale := loadPlateSeeds(state)
	assert.Empty(t, stale.Entries, "a cache from before plates were detected starts over")
	found = stale.resolve(map[string]string{"red": red}, SourceScore)
	assert.True(t, found["red"].plated)
}

func TestPlateSeedCacheKeepsPathsWithBars(t *testing.T) {
	dir := t.TempDir()
	state := filepath.Join(dir, "state")
	// A bar is a valid file name character; the key's own separator is the last one.
	barred := filepath.Join(dir, "a|b", "red|1.png")
	require.NoError(t, os.MkdirAll(filepath.Dir(barred), 0o755))
	writePNG(t, barred, imgcolor.NRGBA{R: 0xe5, G: 0x39, B: 0x35, A: 0xff})
	sources := map[string]string{"red": barred}

	seeds := loadPlateSeeds(state)
	seeds.resolve(sources, SourceScore)
	seeds.save(sources)
	cached := loadPlateSeeds(state)
	assert.Contains(t, cached.Entries, plateSeedKey(barred, SourceScore), "the entry survives the save that uses it")
	cached.resolve(sources, SourceScore)
	assert.False(t, cached.dirty, "and is a cache hit, not sampled again")
}

func TestCommonSourceSkipsGrayLogos(t *testing.T) {
	dir := t.TempDir()
	gray := filepath.Join(dir, "gray.png")
	writePNG(t, gray, imgcolor.NRGBA{R: 0x70, G: 0x70, B: 0x72, A: 0xff})
	assert.Empty(t, sampleLogo(gray, SourceCommon).Seed)
	assert.Empty(t, sampleLogo(gray, SourceScore).Seed)
}

func keys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

func TestSelfBuiltPackGivesAppsTheirOwnTiles(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	icons := t.TempDir()
	red := filepath.Join(icons, "red.png")
	writePNG(t, red, imgcolor.NRGBA{R: 0xe5, G: 0x39, B: 0x35, A: 0xff})
	green := filepath.Join(icons, "green.svg")
	require.NoError(t, os.WriteFile(green, []byte(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><rect width="16" height="16" fill="#2e7d32"/></svg>`), 0o644))
	zipped := filepath.Join(icons, "green.svgz")
	var gz bytes.Buffer
	zw := gzip.NewWriter(&gz)
	_, err := zw.Write([]byte(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><rect width="16" height="16" fill="#2e7d32"/></svg>`))
	require.NoError(t, err)
	require.NoError(t, zw.Close())
	require.NoError(t, os.WriteFile(zipped, gz.Bytes(), 0o644))
	xpm := filepath.Join(icons, "old.xpm")
	require.NoError(t, os.WriteFile(xpm, []byte("/* XPM */"), 0o644))
	sources, err := json.Marshal(map[string]any{"apps": map[string]string{
		"org.red.App": red, "org.green.App": green, "org.zipped.App": zipped, "org.old.App": xpm, "dev.duxlabs.Files": red, "relative": "red.png",
	}})
	require.NoError(t, err)

	theme := e.apply(AppColor)
	assert.NoFileExists(t, filepath.Join(theme.Dir, "tiles.json"), "theme tiles color no app, and the shell icons wear the theme tile with them")

	// A listing that fails keeps the theme tiles, and is logged once until a listing works again.
	o := e.opts()
	o.TileColor = TileApp
	e.flag("dump-fail")
	failed, err := Apply(o)
	require.NoError(t, err)
	assert.Equal(t, theme.Applied, failed.Applied)
	_, warned := dumpWarned.Load(o.Generator)
	assert.True(t, warned)

	require.NoError(t, os.Remove(filepath.Join(e.bin, "dump-fail")))
	require.NoError(t, os.WriteFile(filepath.Join(e.bin, "sources"), sources, 0o644))
	app, err := Apply(o)
	require.NoError(t, err)
	assert.NotEqual(t, theme.Applied, app.Applied, "new tiles are a new build")
	_, warned = dumpWarned.Load(o.Generator)
	assert.False(t, warned, "a listing that works again lets the next failure be logged")
	var tiles struct {
		Apps map[string]tileJSON `json:"apps"`
	}
	require.NoError(t, json.Unmarshal([]byte(e.overlay(app.Applied, "tiles.json")), &tiles))
	assert.ElementsMatch(t, []string{"org.red.App", "org.green.App", "org.zipped.App", "org.old.App", "relative"}, keys(tiles.Apps))
	assert.InDelta(t, 20, toneOf(t, tiles.Apps["org.red.App"].Tile), 0.6, "dark mode under a bright red logo")
	assert.Equal(t, tiles.Apps["org.green.App"], tiles.Apps["org.zipped.App"], "a gzipped SVG is sampled like the SVG")
	assert.NotEqual(t, tiles.Apps["org.old.App"], tiles.Apps["org.zipped.App"])
	// Logos that can't be sampled take the theme hue at the app tile tone, not the theme tile.
	assert.Equal(t, tiles.Apps["org.old.App"], tiles.Apps["relative"])
	assert.InDelta(t, 30, toneOf(t, tiles.Apps["org.old.App"].Tile), 0.6)
	assert.InDelta(t, hctOf(t, "#69b2ff").Hue, hctOf(t, tiles.Apps["org.old.App"].Tile).Hue, 2)
	dumped, err := os.ReadFile(filepath.Join(e.bin, "dumped"))
	require.NoError(t, err)
	ramp, err := NewRamp("#69b2ff", "#003055")
	require.NoError(t, err)
	assert.Equal(t, ramp.Front+" "+ramp.Glyph+" "+ramp.Back+" color\n", string(dumped), "the listing gets the same colors")
	assert.FileExists(t, filepath.Join(e.state, PlateSeedsFile))
	passed, err := os.ReadFile(filepath.Join(e.bin, "tiles-path"))
	require.NoError(t, err)
	assert.NoFileExists(t, string(passed), "the tiles file is removed after the build")

	same, err := Apply(o)
	require.NoError(t, err)
	assert.Equal(t, app, same, "the cached seeds build the same theme")

	o.TileStyle = StyleNeutral
	neutral, err := Apply(o)
	require.NoError(t, err)
	assert.NotEqual(t, app.Applied, neutral.Applied, "a tile style is a new build")

	o.OwnTone = 35
	own, err := Apply(o)
	require.NoError(t, err)
	assert.Equal(t, "35", e.overlay(own.Applied, "scalable/places/own-tone"))
	assert.NotEqual(t, neutral.Applied, own.Applied)

	o.OwnTone, o.TileTone = ToneAuto, 75
	toned, err := Apply(o)
	require.NoError(t, err)
	folder := strings.Fields(e.overlay(toned.Applied, "scalable/places/folder.svg"))
	assert.InDelta(t, 75, toneOf(t, folder[0]), 0.6, "tile tone moves the theme tile too")
	require.NoError(t, json.Unmarshal([]byte(e.overlay(toned.Applied, "tiles.json")), &tiles))
	assert.InDelta(t, 75, toneOf(t, tiles.Apps["org.green.App"].Tile), 6)
}

func TestOldSelfBuiltPackGetsNoTiles(t *testing.T) {
	e := newSelfEnv(t)
	e.flag("old")
	icons := t.TempDir()
	red := filepath.Join(icons, "red.png")
	writePNG(t, red, imgcolor.NRGBA{R: 0xe5, G: 0x39, B: 0x35, A: 0xff})
	sources, err := json.Marshal(map[string]any{"apps": map[string]string{"org.red.App": red}})
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(e.bin, "sources"), sources, 0o644))
	probes := func() int {
		t.Helper()
		data, err := os.ReadFile(filepath.Join(e.bin, "helped"))
		require.NoError(t, err)
		return strings.Count(string(data), "x")
	}

	// The fake rejects every flag the released pack lacks, so any of these failing means one was passed. Color
	// files are the DMS default.
	for _, mode := range []string{"dark", "light"} {
		for _, tile := range []string{TileTheme, TileApp, TileEdge, TileRing} {
			o := e.opts()
			o.Mode, o.TileColor, o.FileStyle, o.OwnTone = mode, tile, FilesColor, 70
			state, err := Apply(o)
			require.NoError(t, err, "%s %s", mode, tile)
			assert.NoFileExists(t, filepath.Join(state.Dir, "tiles.json"), "%s %s", mode, tile)
			assert.Equal(t, "badge", e.overlay(state.Applied, "scalable/places/tile-flag"), "%s %s: the released pack's color flag", mode, tile)
		}
	}
	assert.NoFileExists(t, filepath.Join(e.bin, "dumped"), "an old pack is never asked to list its sources")
	assert.Equal(t, 1, probes(), "the generator is probed once, not on every build")

	// Upgrading the pack in place changes the file, so it is probed again.
	require.NoError(t, os.Remove(filepath.Join(e.bin, "old")))
	later := time.Now().Add(time.Hour)
	require.NoError(t, os.Chtimes(filepath.Join(e.bin, SelfBuilt), later, later))
	o := e.opts()
	o.TileColor = TileApp
	state, err := Apply(o)
	require.NoError(t, err)
	var tiles tilesFile
	require.NoError(t, json.Unmarshal([]byte(e.overlay(state.Applied, "tiles.json")), &tiles))
	assert.Equal(t, []string{"org.red.App"}, keys(tiles.Apps))
	assert.Equal(t, 2, probes())
	assert.Equal(t, "tile", e.overlay(state.Applied, "scalable/places/tile-flag"), "a pack that lists --tiles gets --tile")
	var raw struct {
		Apps map[string]map[string]any `json:"apps"`
	}
	require.NoError(t, json.Unmarshal([]byte(e.overlay(state.Applied, "tiles.json")), &raw))
	assert.Contains(t, raw.Apps["org.red.App"], "tile", "the generator reads each tile's color from \"tile\"")
	assert.NotContains(t, raw.Apps["org.red.App"], "badge")
}

func ratio(t *testing.T, a, b string) float64 {
	t.Helper()
	return contrast.RatioOfTones(toneOf(t, a), toneOf(t, b))
}

func TestEdgeTiles(t *testing.T) {
	primary := hctOf(t, "#69b2ff")
	red := hctOf(t, "#e53935")
	navy := color.Hct{Hue: 260, Chroma: 40, Tone: 25}
	spec := tileSpec{color: TileEdge, primary: primary, keyHue: primary.Hue, style: StyleTonal, tone: ToneAuto, dark: true}
	plated := logo{seed: red, seeded: true, plate: color.NewARGB(255, 0x1e, 0x88, 0xe5), plated: true, reach: 1.01234}

	got := spec.tileFor(plated)
	assert.Equal(t, "#1e88e5", got.Tile, "the logo's own plate, exactly")
	assert.InDelta(t, 1.012, got.Reach, 1e-9)
	assert.Empty(t, got.Ring)
	want := tileRamp(plated.plate.ToHct())
	assert.Equal(t, want.Glyph, got.Glyph)
	assert.Equal(t, want.Back, got.Back)

	toned := spec
	toned.tone, toned.style = 80, StyleNeutral
	assert.Equal(t, "#1e88e5", toned.tileFor(plated).Tile, "no tone, style or guard touches a matched plate")

	for _, seed := range []color.Hct{red, navy} {
		for _, dark := range []bool{true, false} {
			s := spec
			s.dark = dark
			got := s.tileFor(logo{seed: seed, seeded: true})
			tile := hctOf(t, got.Tile)
			assert.Zero(t, got.Reach)
			assert.InDelta(t, seed.Hue, tile.Hue, 3, "not harmonized")
			assert.GreaterOrEqual(t, contrast.RatioOfTones(tile.Tone, seed.Tone), minTileContrast-0.05, "guarded against the logo")
		}
	}
	assert.Greater(t, hctOf(t, spec.tileFor(logo{seed: red, seeded: true}).Tile).Chroma, tonalMaxChroma+5, "no style cap")

	assert.Equal(t, tileOf(appTile(primary, spec)), spec.tileFor(logo{}), "a colorless logo takes the theme hue")
}

func TestRingTiles(t *testing.T) {
	primary := hctOf(t, "#69b2ff")
	red := logo{seed: hctOf(t, "#e53935"), seeded: true}
	tests := []struct {
		name            string
		spec            tileSpec
		logo            logo
		tile, glyph     float64
		ringHue         float64
		guardedFromLogo bool
	}{
		{name: "dark", spec: tileSpec{tone: ToneAuto, dark: true}, logo: red, tile: 17, glyph: 90, ringHue: red.seed.Hue},
		{name: "light", spec: tileSpec{tone: ToneAuto}, logo: red, tile: 98, glyph: 20, ringHue: red.seed.Hue},
		{name: "no seed rings in the theme hue", spec: tileSpec{tone: ToneAuto, dark: true}, tile: 17, glyph: 90, ringHue: primary.Hue},
		{name: "a set tile tone", spec: tileSpec{tone: 12, dark: true}, logo: red, tile: 12, glyph: 90, ringHue: red.seed.Hue},
		{name: "a set tone near the ring turns the ring the other way", spec: tileSpec{tone: 85, dark: true}, logo: logo{seed: color.Hct{Hue: 140, Chroma: 40, Tone: 30}, seeded: true}, tile: 85, glyph: 20, ringHue: 140},
		{name: "the tile is guarded against the logo", spec: tileSpec{tone: 50, dark: true}, logo: red, guardedFromLogo: true, ringHue: red.seed.Hue},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			tc.spec.color, tc.spec.primary, tc.spec.keyHue, tc.spec.style = TileRing, primary, primary.Hue, StyleContent
			got := tc.spec.tileFor(tc.logo)
			tile, ring := hctOf(t, got.Tile), hctOf(t, got.Ring)
			if tc.guardedFromLogo {
				assert.GreaterOrEqual(t, contrast.RatioOfTones(tile.Tone, red.seed.Tone), minTileContrast-0.05)
			} else {
				assert.InDelta(t, tc.tile, tile.Tone, 0.6)
				assert.InDelta(t, tc.glyph, toneOf(t, got.Glyph), 0.6)
			}
			assert.LessOrEqual(t, tile.Chroma, ringTileMaxChroma+1.0, "a neutral tile whatever the style")
			assert.InDelta(t, tc.ringHue, ring.Hue, 3, "the ring takes the logo's hue, unharmonized")
			assert.Greater(t, ring.Chroma, 30.0)
			assert.GreaterOrEqual(t, ratio(t, got.Ring, got.Tile), minTileContrast-0.05)
			assert.Zero(t, got.Reach)
		})
	}
}

func TestRingTilesOnAGrayTheme(t *testing.T) {
	ramp := Ramp{Front: "#c6c6c6", Glyph: "#303030", Back: "#9a9a9a"}
	for _, hex := range []string{"#c6c6c6", "#808080", "#ffffff", "#000000"} {
		for _, dark := range []bool{true, false} {
			primary := hctOf(t, hex)
			spec := tileSpec{color: TileRing, primary: primary, keyHue: primary.Hue, style: StyleTonal, tone: ToneAuto, dark: dark}
			shell, dux := spec.ownPalettes(ramp, true)
			for name, p := range map[string]tileJSON{"unseeded vendor app": spec.tileFor(logo{}), "shell": *shell, "dux": *dux} {
				ring := hctOf(t, p.Ring)
				assert.LessOrEqual(t, ring.Chroma, ringTileMaxChroma+1.0, "%s dark=%v %s: a gray theme rings in gray, not %s", hex, dark, name, p.Ring)
				assert.GreaterOrEqual(t, ratio(t, p.Ring, p.Tile), minTileContrast-0.05, "%s dark=%v %s", hex, dark, name)
			}
			red := spec.tileFor(logo{seed: hctOf(t, "#e53935"), seeded: true})
			assert.Greater(t, hctOf(t, red.Ring).Chroma, 30.0, "%s dark=%v: a colored logo keeps its colored ring", hex, dark)
		}
	}
}

// writeSVG writes a 16×16 icon from its body.
func writeSVG(t *testing.T, path, body string) {
	t.Helper()
	require.NoError(t, os.WriteFile(path, []byte(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">`+body+`</svg>`), 0o644))
}

func TestSelfBuiltPackEdgeAndRingTiles(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	icons := t.TempDir()
	plated := filepath.Join(icons, "plated.svg")
	writeSVG(t, plated, `<circle cx="8" cy="8" r="8" fill="#1e88e5"/><circle cx="8" cy="8" r="3" fill="#ffffff"/>`)
	bare := filepath.Join(icons, "bare.svg")
	writeSVG(t, bare, `<rect width="8" height="8" fill="#e53935"/><rect x="8" y="8" width="8" height="8" fill="#e53935"/>`+
		`<rect x="8" width="8" height="8" fill="#ffffff"/><rect y="8" width="8" height="8" fill="#ffffff"/>`)
	sources, err := json.Marshal(map[string]any{"apps": map[string]string{
		"org.plated.App": plated, "org.bare.App": bare, "org.old.App": filepath.Join(icons, "old.xpm"), "dev.duxlabs.Files": plated,
	}})
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(e.bin, "sources"), sources, 0o644))
	primary, red := hctOf(t, "#69b2ff"), hctOf(t, "#e53935")

	tiles := func(o Options) map[string]tileJSON {
		t.Helper()
		state, err := Apply(o)
		require.NoError(t, err)
		var parsed struct {
			Apps map[string]tileJSON `json:"apps"`
		}
		require.NoError(t, json.Unmarshal([]byte(e.overlay(state.Applied, "tiles.json")), &parsed))
		assert.ElementsMatch(t, []string{"org.plated.App", "org.bare.App", "org.old.App"}, keys(parsed.Apps), "the pack's own apps keep the theme tile")
		return parsed.Apps
	}

	o := e.opts()
	o.TileColor = TileEdge
	edge := tiles(o)
	assert.Equal(t, "#1e88e5", edge["org.plated.App"].Tile)
	assert.InDelta(t, 1, edge["org.plated.App"].Reach, 0.03)
	bareTile := hctOf(t, edge["org.bare.App"].Tile)
	assert.Zero(t, edge["org.bare.App"].Reach, "no plate, no reach")
	assert.InDelta(t, red.Hue, bareTile.Hue, 3, "the seed as it is")
	assert.GreaterOrEqual(t, contrast.RatioOfTones(bareTile.Tone, red.Tone), minTileContrast-0.1)
	assert.InDelta(t, 30, toneOf(t, edge["org.old.App"].Tile), 0.6, "an unsampled logo takes the theme-hue fallback")
	assert.InDelta(t, primary.Hue, hctOf(t, edge["org.old.App"].Tile).Hue, 2)

	o.AppStyle = AppThemed
	for name, p := range tiles(o) {
		assert.Zero(t, p.Reach, name)
		assert.NotEqual(t, "#1e88e5", p.Tile, name)
	}

	o.AppStyle, o.TileColor = AppColor, TileRing
	for name, p := range tiles(o) {
		assert.InDelta(t, ringTileToneDark, toneOf(t, p.Tile), 0.6, name)
		assert.GreaterOrEqual(t, ratio(t, p.Ring, p.Tile), minTileContrast, name)
	}
	ring := tiles(o)
	assert.InDelta(t, red.Hue, hctOf(t, ring["org.bare.App"].Ring).Hue, 3)
	assert.InDelta(t, primary.Hue, hctOf(t, ring["org.old.App"].Ring).Hue, 3)
}

func TestOwnPalettes(t *testing.T) {
	primary := hctOf(t, "#69b2ff")
	ramp, err := NewRamp("#69b2ff", "#003055")
	require.NoError(t, err)
	spec := tileSpec{primary: primary, keyHue: primary.Hue, style: StyleTonal, tone: ToneAuto, dark: true}

	// The shell icons wear what a vendor app with no colors of its own wears, so a dock reads as one set.
	for _, tile := range []string{TileTheme, TileApp, TileEdge, TileRing} {
		for _, dark := range []bool{true, false} {
			for _, tone := range []int{ToneAuto, 30, 55} {
				s := spec
				s.color, s.dark, s.tone = tile, dark, tone
				name := fmt.Sprintf("%s dark=%v tone=%d", tile, dark, tone)

				// No per-app tiles: every vendor app has the theme tile.
				shell, dux := s.ownPalettes(ramp, false)
				assert.Nil(t, shell, "%s: the theme tile, like the vendor apps", name)
				assert.Nil(t, dux, name)

				if tile == TileRing {
					continue
				}
				shell, dux = s.ownPalettes(ramp, true)
				require.NotNil(t, shell, name)
				assert.Equal(t, s.tileFor(logo{}), *shell, "%s: an unseeded vendor app's tile", name)
				assert.Nil(t, dux, "%s: the dux art keeps the theme tile", name)
			}
		}
	}

	tests := []struct {
		name             string
		dark             bool
		tone             int
		tile, shellGlyph float64
	}{
		{name: "dark", dark: true, tone: ToneAuto, tile: ringTileToneDark, shellGlyph: ringGlyphToneDark},
		{name: "light", tone: ToneAuto, tile: ringTileToneLight, shellGlyph: ringGlyphToneLight},
		{name: "a set tile tone", dark: true, tone: 12, tile: 12, shellGlyph: ringGlyphToneDark},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			s := spec
			s.color, s.dark, s.tone = TileRing, tc.dark, tc.tone
			shell, dux := s.ownPalettes(ramp, true)
			require.NotNil(t, shell)
			require.NotNil(t, dux)
			for name, p := range map[string]*tileJSON{"shell": shell, "dux": dux} {
				tile, ring := hctOf(t, p.Tile), hctOf(t, p.Ring)
				assert.InDelta(t, tc.tile, tile.Tone, 0.6, name)
				assert.LessOrEqual(t, tile.Chroma, ringTileMaxChroma+1.0, "%s: the vendor apps' neutral tile", name)
				assert.InDelta(t, primary.Hue, ring.Hue, 3, "%s: a theme-hued ring", name)
				assert.Greater(t, ring.Chroma, 30.0, name)
				assert.GreaterOrEqual(t, ratio(t, p.Ring, p.Tile), minTileContrast-0.05, name)
				assert.Zero(t, p.Reach, name)
			}
			glyph := hctOf(t, shell.Glyph)
			assert.InDelta(t, tc.shellGlyph, glyph.Tone, 0.6)
			assert.InDelta(t, primary.Hue, glyph.Hue, 3)
			assert.Equal(t, hexOf(color.Hct{Hue: primary.Hue, Chroma: primary.Chroma, Tone: tc.shellGlyph}.ToARGB()), shell.Glyph,
				"the shell glyph keeps the primary's chroma")
			assert.Empty(t, shell.Tint)

			duxTile := hctOf(t, dux.Tile)
			assert.InDelta(t, backOf(duxTile).Tone, toneOf(t, dux.Back), 0.6, "the dux back as tileRamp derives it")
			vendor := s.tileFor(logo{})
			untinted := *dux
			untinted.Tint = ""
			assert.Equal(t, vendor, untinted, "the palette an unseeded vendor app gets, Tint aside")
			assert.Equal(t, ramp.Front, dux.Tint, "the dux art keeps today's tile hue")
			assert.InDelta(t, glyphOf(duxTile).Tone, toneOf(t, dux.Glyph), 0.6, "the dux glyph as tileRamp derives it")
		})
	}
}

func TestSelfBuiltPackOwnPalettes(t *testing.T) {
	e := newSelfEnv(t)
	icons := t.TempDir()
	red := filepath.Join(icons, "red.svg")
	writeSVG(t, red, `<rect width="16" height="16" fill="#e53935"/>`)
	sources, err := json.Marshal(map[string]any{"apps": map[string]string{"org.red.App": red, "dev.duxlabs.Files": red}})
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(e.bin, "sources"), sources, 0o644))
	primary := hctOf(t, "#69b2ff")

	read := func(o Options) tilesFile {
		t.Helper()
		state, err := Apply(o)
		require.NoError(t, err)
		var parsed tilesFile
		require.NoError(t, json.Unmarshal([]byte(e.overlay(state.Applied, "tiles.json")), &parsed))
		return parsed
	}

	o := e.opts()
	ramp, err := NewRamp("#69b2ff", "#003055")
	require.NoError(t, err)
	themed, err := Apply(o)
	require.NoError(t, err)
	assert.NoFileExists(t, filepath.Join(themed.Dir, "tiles.json"), "theme tiles: the shell icons wear the theme tile, like every vendor app")

	// A tile tone moves every own icon, the shell icons too, with the theme tile.
	o.TileTone = 30
	dark, err := Apply(o)
	require.NoError(t, err)
	assert.NoFileExists(t, filepath.Join(dark.Dir, "tiles.json"), "the shell icons share the theme ramp")
	folder := strings.Fields(e.overlay(dark.Applied, "scalable/places/folder.svg"))
	assert.InDelta(t, 30, toneOf(t, folder[0]), 0.6, "every own icon, the shell icons too, on the tone-30 tile")
	o.TileTone = ToneAuto

	// Per-app tiles put the shell icons on the tile an unseeded vendor app gets, so a dock reads as one set.
	for _, tile := range []string{TileApp, TileEdge} {
		o.TileColor = tile
		got := read(o)
		assert.Equal(t, []string{"org.red.App"}, keys(got.Apps), tile)
		spec, err := o.tileSpec("#69b2ff")
		require.NoError(t, err)
		require.NotNil(t, got.Shell, tile)
		assert.Equal(t, spec.tileFor(logo{}), *got.Shell, tile)
		assert.Less(t, toneOf(t, got.Shell.Tile), 50.0, "%s: dark mode, a dark tile", tile)
		assert.Nil(t, got.Dux, "%s: the dux art keeps the theme tile", tile)
	}

	o.TileColor, o.Mode = TileTheme, "light"
	light, err := Apply(o)
	require.NoError(t, err)
	assert.NoFileExists(t, filepath.Join(light.Dir, "tiles.json"), "light theme tiles pass no --tiles")

	for _, mode := range []string{"dark", "light"} {
		o.TileColor, o.Mode = TileRing, mode
		got := read(o)
		assert.Equal(t, []string{"org.red.App"}, keys(got.Apps), mode)
		require.NotNil(t, got.Shell, mode)
		require.NotNil(t, got.Dux, mode)
		front := "#005e9e"
		if mode == "dark" {
			front = ramp.Front
		}
		assert.Equal(t, front, got.Dux.Tint, mode)
		hue := primary.Hue
		if mode == "light" {
			hue = hctOf(t, "#005e9e").Hue
		}
		for name, p := range map[string]*tileJSON{"shell": got.Shell, "dux": got.Dux} {
			assert.LessOrEqual(t, hctOf(t, p.Tile).Chroma, ringTileMaxChroma+1.0, "%s %s", mode, name)
			assert.InDelta(t, hue, hctOf(t, p.Ring).Hue, 3, "%s %s", mode, name)
			assert.GreaterOrEqual(t, ratio(t, p.Ring, p.Tile), minTileContrast, "%s %s", mode, name)
		}
	}
}

func TestUniformTile(t *testing.T) {
	blue, gray := hctOf(t, "#69b2ff"), hctOf(t, "#808080")
	tests := []struct {
		name              string
		primary           color.Hct
		app               string
		dark              bool
		tone              int
		tile, glyph, back float64
		tileMax, glyphMax float64
		tileMin, glyphMin float64
		bare, bareMax     float64
	}{
		{name: "themed dark", primary: blue, app: AppThemed, dark: true, tone: ToneAuto, tile: 36, glyph: 94, back: 26, tileMax: 40, glyphMax: 16, tileMin: 35, glyphMin: 12, bare: 80, bareMax: 40},
		{name: "themed light", primary: blue, app: AppThemed, tone: ToneAuto, tile: 84, glyph: 24, back: 72, tileMax: 40, glyphMax: 42, tileMin: 28, glyphMin: 30, bare: 40, bareMax: 40},
		{name: "monochrome dark", primary: blue, app: AppMonochrome, dark: true, tone: ToneAuto, tile: 26, glyph: 90, back: 16, tileMax: 4, glyphMax: 4, tileMin: 2, glyphMin: 2, bare: 80, bareMax: 4},
		{name: "monochrome light", primary: blue, app: AppMonochrome, tone: ToneAuto, tile: 88, glyph: 20, back: 76, tileMax: 4, glyphMax: 4, tileMin: 2, glyphMin: 2, bare: 40, bareMax: 4},
		{name: "a set tone moves the tile and the glyph turns to read on it", primary: blue, app: AppThemed, dark: true, tone: 20, tile: 20, glyph: 94, back: 10, tileMax: 40, glyphMax: 16, bare: 80, bareMax: 40},
		{name: "a set light tone in dark mode", primary: blue, app: AppThemed, dark: true, tone: 80, tile: 80, glyph: 24, back: 70, tileMax: 40, glyphMax: 42, bare: 80, bareMax: 40},
		{name: "a set dark tone in light mode", primary: blue, app: AppMonochrome, tone: 30, tile: 30, glyph: 90, back: 18, tileMax: 4, glyphMax: 4, bare: 40, bareMax: 4},
		{name: "a gray theme stays gray", primary: gray, app: AppMonochrome, dark: true, tone: ToneAuto, tile: 26, glyph: 90, back: 16, tileMax: 1.5, glyphMax: 1.5, bare: 80, bareMax: 1.5},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			s := tileSpec{color: TileRing, primary: tc.primary, keyHue: tc.primary.Hue, style: StyleContent, tone: tc.tone, dark: tc.dark, app: tc.app}
			got := s.uniformTile()
			tile, glyph, back := hctOf(t, got.Tile), hctOf(t, got.Glyph), hctOf(t, got.Back)
			assert.InDelta(t, tc.tile, tile.Tone, 0.6)
			assert.InDelta(t, tc.glyph, glyph.Tone, 0.6)
			assert.InDelta(t, tc.back, back.Tone, 0.6)
			assert.LessOrEqual(t, tile.Chroma, tc.tileMax+1)
			assert.LessOrEqual(t, glyph.Chroma, tc.glyphMax+1)
			assert.GreaterOrEqual(t, tile.Chroma, tc.tileMin)
			assert.GreaterOrEqual(t, glyph.Chroma, tc.glyphMin)
			if tile.Chroma > 10 {
				assert.InDelta(t, tc.primary.Hue, tile.Hue, 3, "the theme hue")
			}
			assert.Empty(t, got.Ring)
			assert.Zero(t, got.Reach)

			// The tile-free copy sits on the panel: a mode tone in the theme hue, whatever the tile tone.
			bare := hctOf(t, got.Bare)
			assert.InDelta(t, tc.bare, bare.Tone, 0.6)
			assert.LessOrEqual(t, bare.Chroma, tc.bareMax+1)
			if bare.Chroma > 10 {
				assert.InDelta(t, tc.primary.Hue, bare.Hue, 3, "the theme hue")
			}
			auto := s
			auto.tone = ToneAuto
			assert.Equal(t, auto.uniformTile().Bare, got.Bare)

			assert.True(t, s.uniform())
			shell, dux := s.uniformPalettes()
			assert.Equal(t, got, *shell)
			assert.Equal(t, got.Glyph, dux.Tint, "the dux art is painted in the glyph color")
			dux.Tint = ""
			assert.Equal(t, got, *dux)
		})
	}
}

func TestSelfBuiltPackThemedStyles(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	icons := t.TempDir()
	red := filepath.Join(icons, "red.png")
	writePNG(t, red, imgcolor.NRGBA{R: 0xe5, G: 0x39, B: 0x35, A: 0xff})
	green := filepath.Join(icons, "green.png")
	writePNG(t, green, imgcolor.NRGBA{R: 0x2e, G: 0x7d, B: 0x32, A: 0xff})
	vector := filepath.Join(icons, "vector.svg")
	writeSVG(t, vector, `<circle cx="8" cy="8" r="8" fill="#1e88e5"/><circle cx="8" cy="8" r="3" fill="#ffffff"/>`)
	write := func(apps map[string]string) {
		t.Helper()
		data, err := json.Marshal(map[string]any{"apps": apps})
		require.NoError(t, err)
		require.NoError(t, os.WriteFile(filepath.Join(e.bin, "sources"), data, 0o644))
	}
	write(map[string]string{"org.red.App": red, "org.green.App": green, "org.vector.App": vector, "org.old.App": filepath.Join(icons, "old.xpm"), "dev.duxlabs.Files": red})
	read := func(o Options) (State, tilesFile) {
		t.Helper()
		state, err := Apply(o)
		require.NoError(t, err)
		var parsed tilesFile
		require.NoError(t, json.Unmarshal([]byte(e.overlay(state.Applied, "tiles.json")), &parsed))
		return state, parsed
	}
	cutouts := filepath.Join(e.state, CutoutsDir)

	for _, style := range []string{AppThemed, AppMonochrome} {
		// Per-app tile options apply only to the color style.
		for _, tileColor := range []string{TileTheme, TileRing} {
			o := e.opts()
			o.AppStyle, o.TileColor = style, tileColor
			name := style + " " + tileColor
			state, got := read(o)
			assert.Equal(t, style, strings.Fields(e.overlay(state.Applied, "scalable/places/folder.svg"))[3], name)
			assert.ElementsMatch(t, []string{"org.red.App", "org.green.App", "org.vector.App", "org.old.App"}, keys(got.Apps), name)
			spec, err := o.tileSpec("#69b2ff")
			require.NoError(t, err)
			want := spec.uniformTile()
			assert.Contains(t, e.overlay(state.Applied, "tiles.json"), `"bare":"`+want.Bare+`"`, name)
			for app, p := range got.Apps {
				p.Cutout = ""
				assert.Equal(t, want, p, "%s %s: one tile for every app", name, app)
			}
			shell, dux := spec.uniformPalettes()
			assert.Equal(t, shell, got.Shell, name)
			assert.Equal(t, dux, got.Dux, name)

			// Only rasters are cut; the pack draws an SVG's glyph itself.
			assert.Empty(t, got.Apps["org.vector.App"].Cutout, name)
			assert.Empty(t, got.Apps["org.old.App"].Cutout, name)
			for _, app := range []string{"org.red.App", "org.green.App"} {
				path := got.Apps[app].Cutout
				require.True(t, filepath.IsAbs(path), "%s %s: %q", name, app, path)
				assert.Equal(t, cutouts, filepath.Dir(path))
				f, err := os.Open(path)
				require.NoError(t, err)
				img, err := png.Decode(f)
				f.Close()
				require.NoError(t, err)
				assert.Equal(t, image.Rect(0, 0, colorseed.CutoutDim, colorseed.CutoutDim), img.Bounds())
			}
		}
	}

	// A theme change reuses every cut-out: a forged one proves the file is read, not cut again.
	o := e.opts()
	o.AppStyle = AppThemed
	_, before := read(o)
	forged := before.Apps["org.red.App"].Cutout
	require.NoError(t, os.WriteFile(forged, []byte("forged"), 0o644))
	e.colors("#a1d39a", "#0a390f")
	_, after := read(o)
	assert.Equal(t, forged, after.Apps["org.red.App"].Cutout)
	data, err := os.ReadFile(forged)
	require.NoError(t, err)
	assert.Equal(t, "forged", string(data))
	assert.NotEqual(t, before.Apps["org.red.App"].Tile, after.Apps["org.red.App"].Tile)

	blank := filepath.Join(icons, "blank.png")
	f, err := os.Create(blank)
	require.NoError(t, err)
	require.NoError(t, png.Encode(f, image.NewNRGBA(image.Rect(0, 0, 32, 32))))
	require.NoError(t, f.Close())
	write(map[string]string{"org.green.App": green, "org.blank.App": blank})
	_, got := read(o)
	assert.Empty(t, got.Apps["org.blank.App"].Cutout)
	assert.NoFileExists(t, forged, "a cut-out no listed logo uses is dropped")
	entries, err := os.ReadDir(cutouts)
	require.NoError(t, err)
	var names []string
	for _, entry := range entries {
		names = append(names, filepath.Ext(entry.Name()))
	}
	assert.ElementsMatch(t, []string{".png", noCutoutExt}, names)

	// A pack that cannot list its apps still puts the shell and dux icons on the one tile.
	e.flag("dump-fail")
	_, failed := read(o)
	assert.Empty(t, failed.Apps)
	require.NotNil(t, failed.Shell)
	require.NotNil(t, failed.Dux)
	assert.Equal(t, failed.Shell.Glyph, failed.Dux.Tint)
}

// Only a logo that was read and cannot be cut is remembered as having no cut-out; a read error is retried.
func TestCutLogoMarksOnlyWhatItRead(t *testing.T) {
	icons, out := t.TempDir(), t.TempDir()
	red := filepath.Join(icons, "red.png")
	writePNG(t, red, imgcolor.NRGBA{R: 0xe5, G: 0x39, B: 0x35, A: 0xff})
	blank := filepath.Join(icons, "blank.png")
	f, err := os.Create(blank)
	require.NoError(t, err)
	require.NoError(t, png.Encode(f, image.NewNRGBA(image.Rect(0, 0, 32, 32))))
	require.NoError(t, f.Close())
	garbage := filepath.Join(icons, "garbage.png")
	require.NoError(t, os.WriteFile(garbage, []byte("not a png"), 0o644))

	tests := []struct {
		name          string
		src           string
		cut, ruledOut bool
	}{
		{name: "a logo with a mark", src: red, cut: true},
		{name: "a logo with no mark", src: blank, ruledOut: true},
		{name: "a file that is no image", src: garbage, ruledOut: true},
		{name: "a logo gone since it was listed", src: filepath.Join(icons, "gone.png")},
		{name: "a logo that cannot be read", src: icons},
	}
	for i, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			dst := filepath.Join(out, fmt.Sprintf("%d.png", i))
			assert.Equal(t, tc.cut, cutLogo(tc.src, dst))
			assert.Equal(t, tc.cut, isFile(dst))
			assert.Equal(t, tc.ruledOut, isFile(strings.TrimSuffix(dst, ".png")+noCutoutExt))
		})
	}
}

// A pack with no --app-style takes the themed style as --mono.
func TestSelfBuiltPackBeforeAppStyle(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	e.flag("no-app-style")
	for style, want := range map[string]string{AppColor: "no", AppThemed: "yes", AppMonochrome: "yes"} {
		state := e.apply(style)
		assert.Equal(t, want, strings.Fields(e.overlay(state.Applied, "scalable/places/folder.svg"))[3], style)
	}
	dumped, err := os.ReadFile(filepath.Join(e.bin, "dumped"))
	require.NoError(t, err)
	assert.Equal(t, "yes", strings.Fields(string(dumped))[3], "the listing gets --mono too")
}
