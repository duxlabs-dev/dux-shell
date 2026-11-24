// Package iconfolders recolors an icon pack's folder icons into a generated overlay theme.
// Apply and Clear must not run concurrently; callers hold the matugen lock.
package iconfolders

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-go/atomicfile"
)

const (
	StateFile = "icon-folders.json"

	noIconTheme = "System Default"
	// Bump when the overlay layout changes for every recipe.
	layoutVersion = 2
)

var (
	overlayName = regexp.MustCompile(`-dms-[0-9a-f]{8}$`)
	// A crashed run leaves its staging directory behind.
	leftover = regexp.MustCompile(`^\.[^/]+-dms-[0-9a-f]{8}\.(tmp|old)-[0-9]+$`)
)

type Options struct {
	// StateDir holds dms-colors.json and the state file.
	StateDir string
	// IconTheme is the theme the user picked, never a generated name.
	IconTheme string
	Mode      string
	// IconsDir receives the overlay; empty means $XDG_DATA_HOME/icons.
	IconsDir string
	// BaseDirs are searched in order for the picked theme; empty means the XDG icon dirs.
	BaseDirs []string
	// AppStyle draws the self-built pack's app icons: AppThemed or AppMonochrome for one glyph on a shared tile,
	// AppTinted for logos repainted in their tile's tones, anything else (AppColor) for logos in their own colors.
	AppStyle string
	// Shape is the self-built pack's tile shape; empty means the pack's own default.
	Shape string
	// Gradient asks the self-built pack to shade its tiles.
	Gradient bool
	// TileColor gives each of the self-built pack's app icons a tile from its own logo: TileApp, TileEdge
	// or TileRing. Anything else, TileTheme, keeps the theme's. Only AppColor and AppTinted have per-app tiles.
	TileColor string
	// ColorSource picks an app logo's color: SourceCommon, or anything else for SourceScore.
	ColorSource string
	// TileStyle caps the app tiles' chroma: StyleContent, StyleNeutral, or anything else for StyleTonal.
	TileStyle string
	// TileTone is the HCT tone 0–100 of the self-built pack's tiles; ToneAuto (-1), not 0, keeps the theme's own.
	TileTone int
	// OwnTone asks the self-built pack to draw its own icons' glyphs at this HCT tone 0–100; ToneAuto (-1), not 0, leaves them.
	OwnTone int
	// FileStyle draws the self-built pack's files and folders: FilesColor for colored folders and file types without
	// the tile, or anything else, FilesStandard, for the theme tile.
	FileStyle string
	// Generator overrides the lookup of the self-built pack's command.
	Generator string
	// PluginDirs hold the plugins whose manifests may carry recipes; empty means the DMS plugin dirs.
	PluginDirs []string
	// PluginSettings is the file that says which plugins are enabled.
	PluginSettings string

	// listedFingerprint is what the self-built pack's source listing reported in this apply: "" when it did not
	// run, "-" when it failed.
	listedFingerprint string
}

type State struct {
	Base    string `json:"base"`
	Applied string `json:"applied"`
	Inputs  string `json:"inputs"`
	// Dir is the applied overlay; Icons maps each recolored icon to its file below it.
	Dir   string            `json:"dir"`
	Icons map[string]string `json:"icons"`
	// Bare is set when the self-built pack also wrote its app icons without the tile, under bareDir.
	Bare bool `json:"bare,omitempty"`
	// Key is what the self-built pack was built from, as ownKey and the pack's fingerprint; an apply from the
	// same inputs skips the build. Empty for a pack that does not fingerprint, and for any other theme.
	Key string `json:"key,omitempty"`
}

// ErrOccupied is returned when a directory DMS did not generate holds the overlay name.
var ErrOccupied = errors.New("a directory DMS did not generate is in the way")

// Probe codes are a contract with the settings UI, which owns the translated text.
const (
	CodeSupported        = "supported"
	CodeSystemDefault    = "system-default"
	CodeUnsupportedPack  = "unsupported-pack"
	CodeNotFound         = "not-found"
	CodeUnreadable       = "unreadable"
	CodeNoColoredFolders = "no-colored-folders"
	// The self-built pack is in the theme colors already; without its command it stays as built.
	CodeSelfColored = "self-colored"
	CodeNoGenerator = "no-generator"
)

type Probe struct {
	Supported bool   `json:"supported"`
	Code      string `json:"code"`
	Reason    string `json:"reason"`
}

// NewOptions is the zero Options with TileTone and OwnTone on ToneAuto. Build Options from it:
// a tone left at 0 is HCT tone 0, pitch-black tiles and --own-tone 0, not the automatic tone.
func NewOptions() Options {
	return Options{TileTone: ToneAuto, OwnTone: ToneAuto}
}

func (o *Options) defaults() {
	if o.IconsDir == "" {
		o.IconsDir = DefaultIconsDir()
	}
	if len(o.BaseDirs) == 0 {
		o.BaseDirs = DefaultBaseDirs()
	}
	if len(o.PluginDirs) == 0 {
		o.PluginDirs, o.PluginSettings = defaultPluginDirs()
	}
	// A consumer that read the applied name back must not make an overlay of an overlay.
	o.IconTheme = overlayName.ReplaceAllString(o.IconTheme, "")
}

func (o *Options) statePath() string {
	return filepath.Join(o.StateDir, StateFile)
}

// ReadState returns the zero State unless the file is one Apply wrote; the name reaches shell arguments.
func ReadState(stateDir string) State {
	var state State
	data, err := os.ReadFile(filepath.Join(stateDir, StateFile))
	if err != nil {
		return State{}
	}
	if json.Unmarshal(data, &state) != nil || state.Base == "" || state.Applied != appliedName(state.Base, state.Inputs) {
		return State{}
	}
	return state
}

// Qt Quick caches pixmaps by file URL, so a name must never map to different content.
func appliedName(base, inputs string) string {
	if len(inputs) < 8 {
		return ""
	}
	return base + "-dms-" + inputs[:8]
}

type candidate struct {
	theme  *theme
	recipe *recipe
	plan   func(Ramp) (*plan, error)
}

func (o *Options) candidate() (*candidate, Probe) {
	if o.IconTheme == "" || o.IconTheme == noIconTheme {
		return nil, Probe{Code: CodeSystemDefault, Reason: "No icon theme is selected"}
	}
	if o.IconTheme == SelfBuilt {
		if o.generator() == "" {
			return nil, Probe{Code: CodeNoGenerator, Reason: "The dux-icons command is not installed"}
		}
		return nil, Probe{Code: CodeSelfColored, Reason: "This icon theme already follows the theme colors"}
	}
	r := o.recipeFor(o.IconTheme)
	if r == nil {
		return nil, Probe{Code: CodeUnsupportedPack, Reason: "Folder colors are not supported for this icon theme"}
	}
	th, err := locateTheme(o.BaseDirs, o.IconTheme)
	if err != nil {
		return nil, Probe{Code: CodeNotFound, Reason: "Icon theme is not installed"}
	}
	return &candidate{
		theme:  th,
		recipe: r,
		plan: func(ramp Ramp) (*plan, error) {
			return buildPlan(scanTheme(th, o.BaseDirs), r, ramp)
		},
	}, Probe{Supported: true, Code: CodeSupported}
}

// ProbeTheme reports whether Apply would recolor the picked theme, writing nothing.
func ProbeTheme(o Options) Probe {
	o.defaults()
	c, probe := o.candidate()
	if c == nil {
		return probe
	}
	p, err := c.plan(Ramp{Front: "#000001", Back: "#000002", Glyph: "#000003"})
	if err != nil {
		return Probe{Code: CodeUnreadable, Reason: "Icon theme could not be read"}
	}
	if len(p.colored) == 0 {
		return Probe{Code: CodeNoColoredFolders, Reason: "Icon theme has no folder icons that can be recolored"}
	}
	return probe
}

// Apply generates the overlay for the picked theme; on failure it returns the previous state with the error.
func Apply(o Options) (State, error) {
	o.defaults()
	prev := ReadState(o.StateDir)
	if o.IconTheme == SelfBuilt {
		return o.applySelfBuilt(prev)
	}
	c, _ := o.candidate()
	if c == nil {
		return State{}, forget(o.StateDir)
	}

	ramp, err := loadRamp(filepath.Join(o.StateDir, "dms-colors.json"), o.Mode)
	if err != nil {
		return o.surviving(prev), err
	}

	inputs := inputsHash(c, ramp)
	name := appliedName(o.IconTheme, inputs)
	dir := filepath.Join(o.IconsDir, name)
	if prev.Applied == name && prev.Dir == dir && isGenerated(dir) {
		return prev, nil
	}

	p, err := c.plan(ramp)
	if err != nil {
		return o.surviving(prev), err
	}
	if len(p.colored) == 0 {
		return State{}, forget(o.StateDir)
	}

	if err := o.install(name, p.write); err != nil {
		return o.surviving(prev), err
	}

	return o.commit(State{Base: o.IconTheme, Applied: name, Inputs: inputs, Dir: dir, Icons: p.manifest()}, prev)
}

// commit writes the state; consumers apply the name as soon as it changes, so the directory must already exist.
func (o *Options) commit(state, prev State) (State, error) {
	data, err := json.Marshal(state)
	if err != nil {
		return o.surviving(prev), err
	}
	if err := atomicfile.WriteFileMkdir(o.statePath(), append(data, '\n'), 0o644, 0o755); err != nil {
		return o.surviving(prev), fmt.Errorf("failed to write %s: %w", o.statePath(), err)
	}

	// Running apps may still read the previous overlay until they are told the new name.
	o.prune(state.Applied, prev.Applied)
	return state, nil
}

// forget keeps the overlays: the session still has one applied until its consumer calls Clear.
func forget(stateDir string) error {
	err := os.Remove(filepath.Join(stateDir, StateFile))
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	return err
}

// Clear removes the state file and every generated overlay, whatever theme is picked.
func Clear(o Options) error {
	o.defaults()
	if err := forget(o.StateDir); err != nil {
		return err
	}
	o.prune()
	return nil
}

func (o *Options) surviving(prev State) State {
	if prev.Base != o.IconTheme || !isGenerated(filepath.Join(o.IconsDir, prev.Applied)) {
		return State{}
	}
	return prev
}

// install skips a name already generated: names are derived from everything that decides content.
func (o *Options) install(name string, write func(root string) error) error {
	target := filepath.Join(o.IconsDir, name)
	if isGenerated(target) {
		return nil
	}
	if _, err := os.Lstat(target); err == nil {
		return fmt.Errorf("%s: %w", target, ErrOccupied)
	}
	if err := os.MkdirAll(o.IconsDir, 0o755); err != nil {
		return err
	}
	tmp := filepath.Join(o.IconsDir, "."+name+".tmp-"+strconv.Itoa(os.Getpid()))
	defer os.RemoveAll(tmp)

	if err := os.RemoveAll(tmp); err != nil {
		return err
	}
	if err := write(tmp); err != nil {
		return fmt.Errorf("failed to write %s: %w", tmp, err)
	}
	return os.Rename(tmp, target)
}

// remove renames first so an interrupted delete never leaves a half-deleted overlay under a live name.
func (o *Options) remove(name string) error {
	aside := filepath.Join(o.IconsDir, "."+name+".old-"+strconv.Itoa(os.Getpid()))
	if err := os.Rename(filepath.Join(o.IconsDir, name), aside); err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil
		}
		return err
	}
	return os.RemoveAll(aside)
}

// prune deletes unkept generated overlays, never a directory without the generated key.
func (o *Options) prune(keep ...string) {
	entries, err := os.ReadDir(o.IconsDir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		name := entry.Name()
		switch {
		case !entry.IsDir():
		case leftover.MatchString(name):
			os.RemoveAll(filepath.Join(o.IconsDir, name))
		case !slices.Contains(keep, name) && isGenerated(filepath.Join(o.IconsDir, name)):
			_ = o.remove(name)
		}
	}
}

// isGenerated guards reuse and deletion: only a directory this package wrote qualifies.
func isGenerated(dir string) bool {
	if !overlayName.MatchString(filepath.Base(dir)) {
		return false
	}
	data, err := readPlain(filepath.Join(dir, "index.theme"))
	return err == nil && bytes.Contains(data, []byte("\n"+generatedKey+"\n"))
}

func inputsHash(c *candidate, ramp Ramp) string {
	sum := sha256.Sum256([]byte(strings.Join([]string{
		c.theme.name,
		c.theme.stamp,
		c.recipe.name,
		c.recipe.version,
		strconv.Itoa(layoutVersion),
		ramp.Front,
		ramp.Back,
		ramp.Glyph,
	}, "\x00")))
	return hex.EncodeToString(sum[:16])
}
