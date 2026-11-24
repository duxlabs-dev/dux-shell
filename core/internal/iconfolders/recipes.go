package iconfolders

import (
	"bytes"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

// recipe decides which of a pack's icons carry its folder color and how they take the ramp.
type recipe struct {
	name string
	// version changes with the recipe's output, so existing overlays regenerate.
	version string
	matches func(theme string) bool
	source  func(context, icon string) bool
	// Hidden names are the pack's own color variant, reached only through symlinks.
	hidden func(icon string) bool
	// Palette variants are not carried: 38 MB to copy, and a generic-fallback lookup would get the recolored folder.
	palette func(base map[string]bool) func(icon string) bool
	recolor func(svg []byte, ramp Ramp) ([]byte, bool)
}

// recipeData is a recipe as JSON: the files under recipes/ and the iconFolders entries of a plugin manifest.
type recipeData struct {
	// Themes, Icons and Stock are path.Match patterns over theme and icon names.
	Themes []string `json:"themes"`
	Icons  []string `json:"icons"`
	// Stock icons are the pack's own color variant: recolored, but shown only under the names linked to them.
	Stock []string `json:"stock"`
	// Palette names the stock variant of a pack that also ships every folder in other colors.
	Palette string `json:"palette"`
	// Colors gives a pack color its role, or one role per occurrence in a file with the last repeating.
	Colors map[string]roles `json:"colors"`
}

type roles []string

func (r *roles) UnmarshalJSON(data []byte) error {
	var one string
	if json.Unmarshal(data, &one) == nil {
		*r = roles{one}
		return nil
	}
	return json.Unmarshal(data, (*[]string)(r))
}

const (
	maxRecipeEntries = 256
	systemPluginsDir = "/etc/xdg/quickshell/dms-plugins"
)

var (
	//go:embed recipes/*.json
	recipeFiles embed.FS

	// Plugin recipes come after these, so a plugin never changes a pack DMS already knows.
	builtin = []*recipe{embedded("papirus"), breeze, embedded("adwaita"), embedded("tela"), embedded("colloid")}

	breeze = &recipe{
		name:    "breeze",
		version: "1",
		matches: func(theme string) bool { return theme == "breeze" || theme == "breeze-dark" },
		source:  func(context, _ string) bool { return context == "places" },
		recolor: recolorBreeze,
	}

	hexColor      = regexp.MustCompile(`#[0-9a-fA-F]{6}\b`)
	recipeColor   = regexp.MustCompile(`^#[0-9a-f]{6}$`)
	recipePalette = regexp.MustCompile(`^[a-z]+-[a-z0-9]+$`)

	svgTag          = regexp.MustCompile(`<[A-Za-z][^<>]*>`)
	breezeAccent    = regexp.MustCompile(`\s+class="ColorScheme-Accent"`)
	breezeText      = regexp.MustCompile(`\s+class="ColorScheme-Text"`)
	breezeOpacity   = regexp.MustCompile(`\s*fill-opacity:\s*[0-9.]+;?`)
	breezeBackStyle = regexp.MustCompile(`fill-opacity:\s*0?\.33\b`)
	breezeBackAttr  = regexp.MustCompile(`fill-opacity="0?\.33"`)
	ownFill         = regexp.MustCompile(`(^|[\s";])fill\s*[:=]`)
	currentColor    = []byte("currentColor")
)

func embedded(name string) *recipe {
	raw, err := recipeFiles.ReadFile("recipes/" + name + ".json")
	if err == nil {
		var r *recipe
		if r, err = parseRecipe(name, raw); err == nil {
			return r
		}
	}
	panic(fmt.Sprintf("recipes/%s.json: %v", name, err))
}

// parseRecipe takes untrusted input: all a recipe can do is swap colors in the SVG text of icons its patterns name.
func parseRecipe(name string, raw []byte) (*recipe, error) {
	var d recipeData
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&d); err != nil {
		return nil, err
	}

	switch {
	case len(d.Themes) == 0:
		return nil, errors.New("no themes")
	case len(d.Icons)+len(d.Stock) == 0:
		return nil, errors.New("no icons")
	case len(d.Themes)+len(d.Icons)+len(d.Stock)+len(d.Colors) > maxRecipeEntries:
		return nil, errors.New("too many entries")
	case d.Palette != "" && !recipePalette.MatchString(d.Palette):
		return nil, fmt.Errorf("bad palette %q", d.Palette)
	}
	for _, pattern := range slices.Concat(d.Themes, d.Icons, d.Stock) {
		// A pattern starts with the name it is about, so no recipe claims every theme or icon.
		if _, err := path.Match(pattern, ""); err != nil || pattern == "" || strings.ContainsAny(pattern[:1], `*?[\`) {
			return nil, fmt.Errorf("bad pattern %q", pattern)
		}
	}
	front := false
	for color, roles := range d.Colors {
		if !recipeColor.MatchString(color) || len(roles) == 0 {
			return nil, fmt.Errorf("bad color %q", color)
		}
		for _, role := range roles {
			if role != "front" && role != "back" && role != "glyph" {
				return nil, fmt.Errorf("bad role %q", role)
			}
			front = front || role == "front"
		}
	}
	if !front {
		return nil, errors.New("no front color")
	}

	sum := sha256.Sum256(raw)
	r := &recipe{
		name:    name,
		version: hex.EncodeToString(sum[:8]),
		matches: func(theme string) bool { return matchAny(d.Themes, theme) },
		// Toolkits paint symbolic icons themselves.
		source: func(_, icon string) bool {
			return !strings.HasSuffix(icon, "-symbolic") && (matchAny(d.Icons, icon) || matchAny(d.Stock, icon))
		},
		hidden:  func(icon string) bool { return matchAny(d.Stock, icon) },
		recolor: d.recolor,
	}
	if d.Palette != "" {
		r.palette = func(base map[string]bool) func(string) bool { return paletteOf(d.Palette, base) }
	}
	return r, nil
}

func matchAny(patterns []string, name string) bool {
	return slices.ContainsFunc(patterns, func(pattern string) bool {
		ok, _ := path.Match(pattern, name)
		return ok
	})
}

// recolor leaves a file without a front color alone: it shares a color with the folders but is not one.
func (d *recipeData) recolor(svg []byte, ramp Ramp) ([]byte, bool) {
	paint := map[string]string{"front": ramp.Front, "back": ramp.Back, "glyph": ramp.Glyph}
	seen := map[string]int{}
	front := false
	out := hexColor.ReplaceAllFunc(svg, func(m []byte) []byte {
		color := strings.ToLower(string(m))
		roles := d.Colors[color]
		if len(roles) == 0 {
			return m
		}
		role := roles[min(seen[color], len(roles)-1)]
		seen[color]++
		front = front || role == "front"
		return []byte(paint[role])
	})
	if !front {
		return svg, false
	}
	return out, true
}

// isFolderName reports names an overlay keeps even when they shadow base icons.
func isFolderName(icon string) bool {
	switch icon {
	case "folder", "inode-directory", "stock_folder", "gtk-directory":
		return true
	}
	return strings.HasPrefix(icon, "folder-") || strings.HasPrefix(icon, "folder_") || strings.HasPrefix(icon, "user-")
}

func (o *Options) recipeFor(theme string) *recipe {
	match := func(r *recipe) bool { return r.matches(theme) }
	if i := slices.IndexFunc(builtin, match); i >= 0 {
		return builtin[i]
	}
	plugins := o.pluginRecipes()
	if i := slices.IndexFunc(plugins, match); i >= 0 {
		return plugins[i]
	}
	return nil
}

func defaultPluginDirs() ([]string, string) {
	config, err := os.UserConfigDir()
	if err != nil {
		return []string{systemPluginsDir}, ""
	}
	dirs := []string{filepath.Join(config, "dms", "plugins"), systemPluginsDir}
	// The shell's plugin service honors the same policy switch.
	if os.Getenv("DMS_POLICY_DISABLE_USER_PLUGINS") == "1" {
		dirs = dirs[1:]
	}
	return dirs, filepath.Join(config, "dms", "plugin_settings.json")
}

// pluginRecipes reads the iconFolders block of every enabled plugin on each call, so a switch in the shell needs no restart.
func (o *Options) pluginRecipes() []*recipe {
	settings := map[string]struct {
		Enabled bool `json:"enabled"`
	}{}
	if data, err := readPlain(o.PluginSettings); err == nil {
		_ = json.Unmarshal(data, &settings)
	}

	// User plugins come first, so one stands in for the system plugin that covers the same pack.
	var found []*recipe
	for _, dir := range o.PluginDirs {
		entries, _ := os.ReadDir(dir)
		for _, entry := range entries {
			var manifest struct {
				ID          string            `json:"id"`
				IconFolders []json.RawMessage `json:"iconFolders"`
			}
			data, err := readPlain(filepath.Join(dir, entry.Name(), "plugin.json"))
			if err != nil || json.Unmarshal(data, &manifest) != nil || len(manifest.IconFolders) == 0 {
				continue
			}
			if !settings[manifest.ID].Enabled {
				continue
			}
			for i, raw := range manifest.IconFolders {
				r, err := parseRecipe(fmt.Sprintf("plugin:%s:%d", manifest.ID, i), raw)
				if err != nil {
					log.Warnf("icon folders: skipping recipe %d of plugin %s: %v", i, manifest.ID, err)
					continue
				}
				found = append(found, r)
			}
		}
	}
	return found
}

// paletteOf reads the colors from the pack itself, so new releases need no change here.
func paletteOf(stock string, base map[string]bool) func(string) bool {
	prefix := stock[:strings.IndexByte(stock, '-')+1]
	var folders []string
	for icon := range base {
		if folder, ok := strings.CutPrefix(icon, stock+"-"); ok {
			folders = append(folders, folder)
		}
	}
	colors := map[string]bool{}
	for icon := range base {
		color, ok := strings.CutPrefix(icon, prefix)
		if !ok || len(folders) == 0 || strings.Contains(color, "-") {
			continue
		}
		complete := !slices.ContainsFunc(folders, func(folder string) bool { return !base[prefix+color+"-"+folder] })
		if complete {
			colors[color] = true
		}
	}
	return func(icon string) bool {
		rest, folder := strings.CutPrefix(icon, prefix)
		color, _, _ := strings.Cut(rest, "-")
		return folder && colors[color]
	}
}

// Colors are inline: KIconLoader swaps the stylesheet for the KDE scheme when FollowsColorScheme is set.
func recolorBreeze(svg []byte, ramp Ramp) ([]byte, bool) {
	changed := false
	out := svgTag.ReplaceAllFunc(svg, func(tag []byte) []byte {
		switch {
		case breezeAccent.Match(tag) && bytes.Contains(tag, currentColor):
			changed = true
			return bytes.ReplaceAll(breezeAccent.ReplaceAll(tag, nil), currentColor, []byte(ramp.Front))
		case breezeText.Match(tag) && bytes.Contains(tag, currentColor):
			// Glyphs at 0.6 opacity leave on_primary under 3:1 on some schemes, so the opacity is dropped.
			tag = bytes.ReplaceAll(breezeOpacity.ReplaceAll(tag, nil), []byte(`;"`), []byte(`"`))
			return bytes.ReplaceAll(breezeText.ReplaceAll(tag, nil), currentColor, []byte(ramp.Glyph))
		case bytes.Contains(tag, []byte("class=")) || ownFill.Match(tag):
			return tag
		}
		// The back plate is a translucent black shape over the accent body.
		tag = breezeBackStyle.ReplaceAll(tag, []byte("fill:"+ramp.Back))
		return breezeBackAttr.ReplaceAll(tag, []byte(`fill="`+ramp.Back+`"`))
	})
	if !changed {
		return svg, false
	}
	return out, true
}
