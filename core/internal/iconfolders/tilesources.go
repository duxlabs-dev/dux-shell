package iconfolders

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/atomicfile"
	"github.com/duxlabs-dev/dux-go/material/color"
	"github.com/duxlabs-dev/dux-go/material/quantizer"
	"github.com/duxlabs-dev/dux-shell/core/internal/colorseed"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

const (
	// PlateSeedsFile caches what each app logo was sampled to in the state dir, so rebuilds after every theme change stay cheap.
	PlateSeedsFile = "icon-plate-seeds.json"
	// plateSeedsVersion changes whenever an entry would sample differently; an older cache is dropped.
	plateSeedsVersion = 3

	dumpTimeout  = 30 * time.Second
	probeTimeout = 10 * time.Second
	// The pack's own apps keep the theme tile.
	ownAppPrefix = "dev.duxlabs."
	// A logo is small; the quantizer sees at most this many pixels on a side.
	tileSampleDim = 128
	tileMaxColors = 128
	// Below this a logo reads as gray, black or white, and keeps the theme tile.
	minSeedChroma = 8.0
	// Anything bigger is not an app logo worth decoding.
	tileMaxFileSize = 8 << 20
	tileWorkers     = 4
)

var tileFormats = []string{".svg", ".svgz", ".png", ".jpg", ".jpeg"}

// dumpWarned keeps the log to one line per generator while its source listing keeps failing.
var dumpWarned sync.Map

// probedFlags holds the generatorFlags of each generator, as the file was when probed.
var probedFlags sync.Map

type generatorFile struct {
	path    string
	size    int64
	modTime int64
}

// generatorFlags is what the generator's --help lists. A pack rejects a flag from after its time,
// which would fail the whole build, so each is passed only when listed.
type generatorFlags struct {
	// tiles is --tiles, and with it --tile and --dump-sources.
	tiles      bool
	appStyle   bool
	ownTone    bool
	filesStyle bool
}

func parseGeneratorFlags(help []byte) generatorFlags {
	has := func(flag string) bool { return bytes.Contains(help, []byte(flag)) }
	return generatorFlags{
		tiles: has("--tiles"), appStyle: has("--app-style"),
		ownTone: has("--own-tone"), filesStyle: has("--files-style"),
	}
}

// probeGenerator runs the generator's --help once per file; upgrading the pack changes the file,
// so it is probed again. A probe that fails lists nothing.
func probeGenerator(generator string) generatorFlags {
	info, err := os.Stat(generator)
	if err != nil {
		return generatorFlags{}
	}
	key := generatorFile{path: generator, size: info.Size(), modTime: info.ModTime().UnixNano()}
	if flags, ok := probedFlags.Load(key); ok {
		return flags.(generatorFlags)
	}
	ctx, cancel := context.WithTimeout(context.Background(), probeTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, generator, "--help")
	cmd.WaitDelay = time.Second
	output, err := cmd.CombinedOutput()
	if err != nil {
		// Not cached: a probe that timed out says nothing about the pack.
		log.Warnf("Icon tiles: %s --help failed, keeping the theme tiles: %v", generator, err)
		return generatorFlags{}
	}
	flags := parseGeneratorFlags(output)
	if _, seen := probedFlags.LoadOrStore(key, flags); !seen && !flags.tiles {
		log.Infof("Icon tiles: %s is too old for tiles, keeping the theme tiles", generator)
	}
	return flags
}

// supportsTiles reports whether the generator lists --tiles, as probeGenerator probes it.
func supportsTiles(generator string) bool {
	return probeGenerator(generator).tiles
}

// flagsOf is what a generator lists once supportsTiles has answered: a tiled one's probe is cached,
// and an untiled one, too old or not probed, is taken to list nothing.
func flagsOf(generator string, tiled bool) generatorFlags {
	if !tiled {
		return generatorFlags{}
	}
	return probeGenerator(generator)
}

// tiles writes the generator's --tiles file, or returns "" when every icon keeps the theme tile;
// tiled says the generator takes the file, as supportsTiles probes it.
func (o *Options) tiles(generator, primary string, ramp Ramp, tiled bool) (string, func()) {
	noop := func() {}
	if !tiled {
		return "", noop
	}
	spec, err := o.tileSpec(primary)
	if err != nil {
		log.Warnf("Icon tiles: %v", err)
		return "", noop
	}
	flags := flagsOf(generator, tiled)
	file := tilesFile{Apps: map[string]tileJSON{}}
	switch {
	case spec.uniform():
		file.Apps = o.uniformTiles(generator, spec, ramp, flags)
		file.Shell, file.Dux = spec.uniformPalettes()
	default:
		if spec.color != TileTheme {
			maps.Copy(file.Apps, o.appTiles(generator, spec, ramp, flags))
		}
		file.Shell, file.Dux = spec.ownPalettes(ramp, len(file.Apps) > 0)
	}
	if file.empty() {
		return "", noop
	}
	path, err := writeTiles(file)
	if err != nil {
		log.Warnf("Icon tiles: %v", err)
		return "", noop
	}
	return path, func() { os.Remove(path) }
}

// appTiles colors each app from its own logo, or returns none to keep the theme tiles.
func (o *Options) appTiles(generator string, spec tileSpec, ramp Ramp, flags generatorFlags) map[string]tileJSON {
	sources := o.listSources(generator, ramp, flags)
	if sources == nil {
		return nil
	}
	// Only absolute paths in a format a logo can be sampled from; the rest take the fallback below.
	sampled := sourcesIn(sources, tileFormats)
	seeds := loadPlateSeeds(o.StateDir)
	logos := seeds.resolve(sampled, o.colorSource())
	seeds.save(sampled)

	apps := map[string]tileJSON{}
	for name := range sources {
		apps[name] = spec.tileFor(logos[name])
	}
	return apps
}

// uniformTiles puts every app on the themed styles' one tile, with the cut-out of its raster logo where
// one was made. Apps the pack cannot list fall back to the pack's own uniform tile, as the shell icons wear.
func (o *Options) uniformTiles(generator string, spec tileSpec, ramp Ramp, flags generatorFlags) map[string]tileJSON {
	sources := o.listSources(generator, ramp, flags)
	if sources == nil {
		return map[string]tileJSON{}
	}
	cutouts := o.cutouts(sourcesIn(sources, cutoutFormats))
	tile := spec.uniformTile()
	apps := make(map[string]tileJSON, len(sources))
	for name, path := range sources {
		t := tile
		t.Cutout = cutouts[path]
		apps[name] = t
	}
	return apps
}

// listSources is the pack's app icon sources, or nil when it cannot list them, logged once until it can again.
func (o *Options) listSources(generator string, ramp Ramp, flags generatorFlags) map[string]string {
	sources, err := o.dumpSources(generator, ramp, flags)
	if err != nil {
		if _, seen := dumpWarned.LoadOrStore(generator, true); !seen {
			log.Warnf("Icon tiles: %s cannot list its app icons, keeping the theme tiles: %v", generator, err)
		}
		return nil
	}
	dumpWarned.Delete(generator)
	return sources
}

// sourcesIn keeps the absolute paths in one of formats.
func sourcesIn(sources map[string]string, formats []string) map[string]string {
	kept := map[string]string{}
	for name, path := range sources {
		if filepath.IsAbs(path) && slices.Contains(formats, strings.ToLower(filepath.Ext(path))) {
			kept[name] = path
		}
	}
	return kept
}

func writeTiles(file tilesFile) (string, error) {
	data, err := json.Marshal(file)
	if err != nil {
		return "", err
	}
	f, err := os.CreateTemp("", SelfBuilt+"-tiles-*.json")
	if err != nil {
		return "", err
	}
	defer f.Close()
	if _, err := f.Write(append(data, '\n')); err != nil {
		os.Remove(f.Name())
		return "", err
	}
	return f.Name(), nil
}

// dumpSources asks the pack which file each app icon is built from.
func (o *Options) dumpSources(generator string, ramp Ramp, flags generatorFlags) (map[string]string, error) {
	// No digest, so a listing that fails is not taken for one that found nothing.
	o.listedFingerprint = "-"
	ctx, cancel := context.WithTimeout(context.Background(), dumpTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, generator, append([]string{"--dump-sources"}, o.styleArgs(ramp, flags)...)...)
	cmd.WaitDelay = time.Second
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		lines := strings.Split(strings.TrimSpace(stderr.String()), "\n")
		return nil, fmt.Errorf("%w: %s", err, lines[len(lines)-1])
	}
	var dump struct {
		Apps        map[string]string `json:"apps"`
		Fingerprint string            `json:"fingerprint"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &dump); err != nil {
		return nil, fmt.Errorf("bad --dump-sources output: %w", err)
	}
	o.listedFingerprint = dump.Fingerprint
	sources := map[string]string{}
	for name, path := range dump.Apps {
		if name != "" && !strings.HasPrefix(name, ownAppPrefix) {
			sources[name] = path
		}
	}
	return sources, nil
}

// plateSeed is one logo's seed and the plate it is drawn on, either "" for none, for the file as it was when sampled.
type plateSeed struct {
	Size    int64   `json:"size"`
	ModTime int64   `json:"modTime"`
	Seed    string  `json:"seed"`
	Plate   string  `json:"plate,omitempty"`
	Reach   float64 `json:"reach,omitempty"`
}

type plateSeeds struct {
	path    string
	Version int                  `json:"version"`
	Entries map[string]plateSeed `json:"entries"`
	dirty   bool
}

// plateSeedKey joins a logo's path and color source; the source never holds a "|", so the last one splits them.
func plateSeedKey(path, source string) string {
	return path + "|" + source
}

func plateSeedPath(key string) string {
	if i := strings.LastIndex(key, "|"); i >= 0 {
		return key[:i]
	}
	return key
}

func loadPlateSeeds(stateDir string) *plateSeeds {
	c := &plateSeeds{path: filepath.Join(stateDir, PlateSeedsFile), Version: plateSeedsVersion, Entries: map[string]plateSeed{}}
	data, err := os.ReadFile(c.path)
	if err != nil {
		return c
	}
	// A cache with no version never matches this one.
	c.Version = 0
	if json.Unmarshal(data, c) != nil || c.Entries == nil || c.Version != plateSeedsVersion {
		c.Version, c.Entries, c.dirty = plateSeedsVersion, map[string]plateSeed{}, true
	}
	return c
}

// resolve returns what each app's logo was sampled to, sampling only logos the cache does not hold as they are now.
// An app whose logo has neither a usable color nor a plate, or cannot be read, is left out.
func (c *plateSeeds) resolve(sources map[string]string, source string) map[string]logo {
	type job struct {
		path string
		key  string
		size int64
		mod  int64
	}
	seeds := map[string]plateSeed{}
	var jobs []job
	queued := map[string]bool{}
	for _, path := range sources {
		info, err := os.Stat(path)
		if err != nil || !info.Mode().IsRegular() || info.Size() > tileMaxFileSize {
			continue
		}
		key := plateSeedKey(path, source)
		if entry, ok := c.Entries[key]; ok && entry.Size == info.Size() && entry.ModTime == info.ModTime().UnixNano() {
			seeds[path] = entry
			continue
		}
		if !queued[key] {
			queued[key] = true
			jobs = append(jobs, job{path: path, key: key, size: info.Size(), mod: info.ModTime().UnixNano()})
		}
	}

	var mu sync.Mutex
	parallel(jobs, func(j job) {
		entry := sampleLogo(j.path, source)
		entry.Size, entry.ModTime = j.size, j.mod
		mu.Lock()
		seeds[j.path] = entry
		c.Entries[j.key] = entry
		c.dirty = true
		mu.Unlock()
	})

	found := map[string]logo{}
	for name, path := range sources {
		entry, ok := seeds[path]
		if !ok {
			continue
		}
		var l logo
		if hct, err := parseHct(entry.Seed); entry.Seed != "" && err == nil {
			l.seed, l.seeded = hct, true
		}
		var plate color.ARGB
		if entry.Plate != "" && plate.UnmarshalText([]byte(entry.Plate)) == nil && entry.Reach > 0 {
			l.plate, l.plated, l.reach = plate, true, entry.Reach
		}
		if l.seeded || l.plated {
			found[name] = l
		}
	}
	return found
}

// save drops the logos no app uses and writes the cache if anything changed.
func (c *plateSeeds) save(sources map[string]string) {
	used := map[string]bool{}
	for _, path := range sources {
		used[path] = true
	}
	for key := range c.Entries {
		if !used[plateSeedPath(key)] {
			delete(c.Entries, key)
			c.dirty = true
		}
	}
	if !c.dirty {
		return
	}
	data, err := json.Marshal(c)
	if err != nil {
		return
	}
	if err := atomicfile.WriteFileMkdir(c.path, append(data, '\n'), 0o644, 0o755); err != nil {
		log.Warnf("Icon tiles: failed to write %s: %v", c.path, err)
	}
	c.dirty = false
}

// sampleLogo returns the logo's seed and plate as hex, "" for none; a broken file is logged, never fatal.
func sampleLogo(path, source string) (entry plateSeed) {
	defer func() {
		if r := recover(); r != nil {
			log.Warnf("Icon tiles: skipping %s: %v", path, r)
			entry = plateSeed{}
		}
	}()
	img, err := colorseed.IconImage(path, tileSampleDim)
	if err != nil {
		log.Warnf("Icon tiles: skipping %s: %v", path, err)
		return plateSeed{}
	}
	// Stored and reused as hex, so a cached seed gives the same tile as a fresh one.
	if hct, ok := seedOf(img, source); ok {
		entry.Seed = hct.ToARGB().HexRGB()
	}
	if plate, ok := colorseed.Plate(img); ok {
		entry.Plate, entry.Reach = plate.HexRGB(), colorseed.Reach(img)
	}
	return entry
}

func seedOf(img image.Image, source string) (color.Hct, bool) {
	pixels := colorseed.Pixels(img, tileSampleDim, colorseed.HalfOpaque)
	if len(pixels) == 0 {
		return color.Hct{}, false
	}
	population := quantizer.QuantizeCelebi(pixels, tileMaxColors)
	if source == SourceCommon {
		return colorseed.Common(population, minSeedChroma)
	}
	// Score always settles on something; on a gray logo that is a gray.
	hct, ok := colorseed.Score(population)
	return hct, ok && hct.Chroma >= minSeedChroma
}

// parallel runs fn over jobs on at most tileWorkers goroutines, all done when it returns.
func parallel[T any](jobs []T, fn func(T)) {
	if len(jobs) == 0 {
		return
	}
	var wg sync.WaitGroup
	work := make(chan T)
	for range min(tileWorkers, runtime.NumCPU(), len(jobs)) {
		wg.Go(func() {
			for j := range work {
				fn(j)
			}
		})
	}
	for _, j := range jobs {
		work <- j
	}
	close(work)
	wg.Wait()
}
