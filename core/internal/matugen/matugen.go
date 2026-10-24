package matugen

import (
	"bytes"
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/dank16"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"github.com/godbus/dbus/v5"
	"github.com/lucasb-eyer/go-colorful"
)

var ErrNoChanges = errors.New("no color changes")

type ColorMode string

const (
	ColorModeDark  ColorMode = "dark"
	ColorModeLight ColorMode = "light"
	ColorModeSmart ColorMode = "smart"
)

type TemplateKind int

const (
	TemplateKindNormal TemplateKind = iota
	TemplateKindTerminal
	TemplateKindGTK
	TemplateKindVSCode
	TemplateKindEmacs
)

type TemplateDef struct {
	ID                 string
	Commands           []string
	Flatpaks           []string
	ConfigDirs         []string
	ConfigFile         string
	FlatpakConfigPath  string
	Kind               TemplateKind
	RunUnconditionally bool
	RequiredEnv        string
}

var templateRegistry = []TemplateDef{
	{ID: "gtk", Kind: TemplateKindGTK, RunUnconditionally: true},
	{ID: "niri", Commands: []string{"niri"}, ConfigFile: "niri.toml"},
	{ID: "hyprland", Commands: []string{"Hyprland"}, ConfigFile: "hyprland.toml"},
	{ID: "mangowc", Commands: []string{"mango"}, ConfigFile: "mangowc.toml", RequiredEnv: "MANGO_INSTANCE_SIGNATURE"},
	{ID: "qt5ct", Commands: []string{"qt5ct"}, ConfigFile: "qt5ct.toml"},
	{ID: "qt6ct", Commands: []string{"qt6ct"}, ConfigFile: "qt6ct.toml"},
	{ID: "fcitx5", Commands: []string{"fcitx5"}, ConfigDirs: []string{"fcitx5"}, ConfigFile: "fcitx5.toml"},
	{ID: "firefox", Commands: []string{"firefox"}, ConfigFile: "firefox.toml"},
	{ID: "pywalfox", Commands: []string{"pywalfox"}, ConfigFile: "pywalfox.toml"},
	{ID: "zenbrowser", Commands: []string{"zen", "zen-browser", "zen-beta", "zen-twilight"}, Flatpaks: []string{"app.zen_browser.zen"}, ConfigFile: "zenbrowser.toml"},
	{ID: "vesktop", Commands: []string{"vesktop"}, Flatpaks: []string{"dev.vencord.Vesktop"}, ConfigDirs: []string{"vesktop"}, ConfigFile: "vesktop.toml", FlatpakConfigPath: "dev.vencord.Vesktop/config"},
	{ID: "vencord", Commands: []string{"discord", "Discord", "discord-canary", "DiscordCanary"}, Flatpaks: []string{"com.discordapp.Discord", "com.discordapp.DiscordCanary"}, ConfigDirs: []string{"Vencord"}, ConfigFile: "vencord.toml"},
	{ID: "equibop", Commands: []string{"equibop"}, ConfigDirs: []string{"equibop"}, ConfigFile: "equibop.toml"},
	{ID: "ghostty", Commands: []string{"ghostty"}, ConfigFile: "ghostty.toml", Kind: TemplateKindTerminal},
	{ID: "kitty", Commands: []string{"kitty"}, ConfigFile: "kitty.toml", Kind: TemplateKindTerminal},
	{ID: "foot", Commands: []string{"foot"}, ConfigFile: "foot.toml", Kind: TemplateKindTerminal},
	{ID: "alacritty", Commands: []string{"alacritty"}, ConfigFile: "alacritty.toml", Kind: TemplateKindTerminal},
	{ID: "wezterm", Commands: []string{"wezterm"}, ConfigFile: "wezterm.toml", Kind: TemplateKindTerminal},
	{ID: "nvim", Commands: []string{"nvim"}, ConfigFile: "neovim.toml", Kind: TemplateKindTerminal},
	{ID: "dgop", Commands: []string{"dgop"}, ConfigFile: "dgop.toml"},
	{ID: "kcolorscheme", ConfigFile: "kcolorscheme.toml", RunUnconditionally: true},
	{ID: "vscode", Kind: TemplateKindVSCode},
	{ID: "emacs", Commands: []string{"emacs"}, ConfigFile: "emacs.toml", Kind: TemplateKindEmacs},
	{ID: "zed", Commands: []string{"zed", "zeditor", "zedit"}, ConfigFile: "zed.toml"},
}

func (c *ColorMode) GTKTheme() string {
	switch *c {
	case ColorModeDark:
		return "adw-gtk3-dark"
	default:
		return "adw-gtk3"
	}
}

// GTKRefreshTheme is the built-in theme the gtk-theme round trip passes through
// to make GTK3 reload gtk.css. It must match the mode's polarity: an empty or
// light name resolves to Adwaita, and toolkit-following apps (Chromium/Electron
// without a settings portal) latch light when the restore lands mid-repaint.
func (c *ColorMode) GTKRefreshTheme() string {
	switch *c {
	case ColorModeDark:
		return "HighContrastInverse"
	default:
		return "Adwaita"
	}
}

var (
	matugenVersionMu      sync.Mutex
	matugenVersionOK      bool
	matugenSupportsCOE    bool
	matugenIsV4           bool
	matugenIsV42          bool
	matugenSupportsPrefer bool
	matugenVersionStr     string
)

type Options struct {
	StateDir            string
	ShellDir            string
	ConfigDir           string
	Kind                string
	Value               string
	Mode                ColorMode
	IconTheme           string
	MatugenType         string
	Contrast            float64
	SourceMode          string
	SeedColor           string
	Spec                string
	RunUserTemplates    bool
	ColorsOnly          bool
	StockColors         string
	SyncModeWithPortal  bool
	TerminalsAlwaysDark bool
	TerminalOpacity     int
	TerminalPalette     string
	ContrastOverrides   ContrastOverrides
	SkipTemplates       string
	AppChecker          utils.AppChecker

	// Set by buildOnce for the terminal config header.
	terminalContrast []Adjustment
}

type ColorsOutput struct {
	Colors struct {
		Dark  map[string]string `json:"dark"`
		Light map[string]string `json:"light"`
	} `json:"colors"`
}

type SchemeColors struct {
	Primary   string `json:"primary"`
	Secondary string `json:"secondary"`
	Tertiary  string `json:"tertiary"`
}

type SchemePreview struct {
	Dark  SchemeColors `json:"dark"`
	Light SchemeColors `json:"light"`
}

func schemeColors(output, mode string) SchemeColors {
	return SchemeColors{
		Primary:   extractMatugenColor(output, "primary", mode),
		Secondary: extractMatugenColor(output, "secondary", mode),
		Tertiary:  extractMatugenColor(output, "tertiary", mode),
	}
}

func nestedSchemeColors(colors, mode string) SchemeColors {
	return SchemeColors{
		Primary:   extractNestedColor(colors, "primary", mode),
		Secondary: extractNestedColor(colors, "secondary", mode),
		Tertiary:  extractNestedColor(colors, "tertiary", mode),
	}
}

var previewSchemeTypes = []string{
	"scheme-tonal-spot",
	"scheme-vibrant",
	"scheme-content",
	"scheme-expressive",
	"scheme-fidelity",
	"scheme-fruit-salad",
	"scheme-monochrome",
	"scheme-neutral",
	"scheme-rainbow",
}

func PreviewSchemes(sourceColor string, contrast float64, imagePath, spec string) (map[string]SchemePreview, error) {
	if sourceColor == "" {
		return nil, fmt.Errorf("source color is required")
	}

	previews := make(map[string]SchemePreview, len(previewSchemeTypes)+1)
	for _, schemeType := range previewSchemeTypes {
		if UsesSpecGenerator(spec, schemeType) {
			colors, err := GenerateSpecColors(sourceColor, schemeType, contrast, ColorModeDark, spec)
			if err != nil {
				return nil, fmt.Errorf("preview %s: %w", schemeType, err)
			}
			previews[schemeType] = SchemePreview{Dark: nestedSchemeColors(colors, "dark"), Light: nestedSchemeColors(colors, "light")}
			continue
		}
		output, err := runMatugenDryRun(&Options{
			Kind:        "hex",
			Value:       sourceColor,
			Mode:        ColorModeDark,
			MatugenType: schemeType,
			Contrast:    contrast,
		})
		if err != nil {
			return nil, fmt.Errorf("preview %s: %w", schemeType, err)
		}

		dark := schemeColors(output, "dark")
		light := schemeColors(output, "light")
		if dark.Primary == "" || light.Primary == "" {
			return nil, fmt.Errorf("preview %s: primary colors missing from matugen output", schemeType)
		}
		previews[schemeType] = SchemePreview{Dark: dark, Light: light}
	}

	previews["scheme-smart"] = smartSchemePreview(previews["scheme-tonal-spot"], sourceColor, contrast, imagePath)
	return previews, nil
}

func smartSchemePreview(fallback SchemePreview, sourceColor string, contrast float64, imagePath string) SchemePreview {
	flags, err := detectMatugenVersion()
	if err != nil || !flags.isV42 {
		return fallback
	}
	opts := &Options{
		Kind:        "hex",
		Value:       sourceColor,
		Mode:        ColorModeDark,
		MatugenType: "scheme-smart",
		Contrast:    contrast,
	}
	if imagePath != "" {
		opts.Kind = "image"
		opts.Value = imagePath
	}
	_, cleanup, err := stageImageSource(opts)
	if err != nil {
		log.Warnf("Smart scheme preview failed falling back to tonal-spot: %v", err)
		return fallback
	}
	defer cleanup()
	output, err := runMatugenDryRun(opts)
	if err != nil {
		log.Warnf("Smart scheme preview failed falling back to tonal-spot: %v", err)
		return fallback
	}
	dark := schemeColors(output, "dark")
	light := schemeColors(output, "light")
	if dark.Primary == "" || light.Primary == "" {
		log.Warn("Smart scheme preview failed falling back to tonal-spot: primary colors missing from matugen output")
		return fallback
	}
	return SchemePreview{Dark: dark, Light: light}
}

func (o *Options) ColorsOutput() string {
	return filepath.Join(o.StateDir, "dms-colors.json")
}

func (o *Options) colorsStaging() string {
	return o.ColorsOutput() + ".tmp"
}

func (o *Options) ShouldSkipTemplate(name string) bool {
	if o.SkipTemplates == "" {
		return false
	}
	for skip := range strings.SplitSeq(o.SkipTemplates, ",") {
		if strings.TrimSpace(skip) == name {
			return true
		}
	}
	return false
}

func acquireMatugenLock(stateDir string) (*os.File, error) {
	f, err := os.OpenFile(filepath.Join(stateDir, "matugen.lock"), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, fmt.Errorf("failed to open matugen lock: %w", err)
	}

	deadline := time.Now().Add(45 * time.Second)
	for {
		switch err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err {
		case nil:
			return f, nil
		case syscall.EWOULDBLOCK:
			if time.Now().After(deadline) {
				f.Close()
				return nil, fmt.Errorf("timed out waiting for matugen lock")
			}
			time.Sleep(100 * time.Millisecond)
		default:
			f.Close()
			return nil, fmt.Errorf("failed to lock matugen: %w", err)
		}
	}
}

func releaseMatugenLock(f *os.File) {
	if f == nil {
		return
	}
	_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	f.Close()
}

func Run(opts Options) error {
	if opts.StateDir == "" {
		return fmt.Errorf("state-dir is required")
	}
	if opts.ShellDir == "" {
		return fmt.Errorf("shell-dir is required")
	}
	if opts.ConfigDir == "" {
		return fmt.Errorf("config-dir is required")
	}
	if opts.Kind == "" {
		return fmt.Errorf("kind is required")
	}
	if opts.Value == "" {
		return fmt.Errorf("value is required")
	}
	if opts.Mode == "" {
		opts.Mode = ColorModeDark
	}
	if opts.MatugenType == "" {
		opts.MatugenType = "scheme-tonal-spot"
	}
	if opts.IconTheme == "" {
		opts.IconTheme = "System Default"
	}
	if opts.AppChecker == nil {
		opts.AppChecker = utils.DefaultAppChecker{}
	}

	if err := os.MkdirAll(opts.StateDir, 0o755); err != nil {
		return fmt.Errorf("failed to create state dir: %w", err)
	}

	lock, err := acquireMatugenLock(opts.StateDir)
	if err != nil {
		return err
	}
	defer releaseMatugenLock(lock)

	log.Infof("Building theme: %s %s (%s)", opts.Kind, opts.Value, opts.Mode)

	changed, buildErr := buildOnce(&opts)
	if buildErr != nil {
		return buildErr
	}

	if opts.SyncModeWithPortal {
		syncColorScheme(opts.Mode)
	}

	if !changed {
		log.Info("No color changes detected, skipping refresh")
		return ErrNoChanges
	}

	log.Info("Done")
	return nil
}

func buildOnce(opts *Options) (bool, error) {
	defer os.Remove(opts.colorsStaging())

	flags, err := detectMatugenVersion()
	if err != nil {
		return false, err
	}
	sourceImage, cleanup, err := stageImageSource(opts)
	if err != nil {
		return false, err
	}
	defer cleanup()
	smartJSON, err := resolveSmartMode(opts, flags)
	if err != nil {
		return false, err
	}
	seeds := loadSeedCache(opts.StateDir)

	tmpDir, err := os.MkdirTemp("", "matugen-templates-*")
	if err != nil {
		return false, fmt.Errorf("failed to create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	oldColors, _ := os.ReadFile(opts.ColorsOutput())

	var primaryDark, primaryLight, surfaceDark, surfaceLight, containerDark, containerLight string
	var dank16JSON string
	var importArgs, args []string
	var built *builtPalettes

	if opts.StockColors == "" && opts.SeedColor != "" {
		seed, err := NormalizeHexColor(opts.SeedColor)
		if err != nil {
			return false, err
		}
		log.Infof("Seed color override: %s -> %s", opts.Value, seed)
		opts.Kind = "hex"
		opts.Value = seed
		opts.SourceMode = SourceModeDominant
	}

	if opts.StockColors == "" && opts.Kind == "image" && opts.SourceMode == SourceModeColorful {
		seed, err := seeds.resolve(sourceImage, opts.SourceMode, flags.version, func() (string, error) {
			return ExtractSourceColor(opts.Value)
		})
		if err != nil {
			log.Warnf("Colorful source extraction failed for %s, using matugen's own: %v", opts.Value, err)
		} else {
			log.Infof("Colorful source color: %s -> %s", opts.Value, seed)
			opts.Kind = "hex"
			opts.Value = seed
		}
	}

	if opts.StockColors != "" {
		log.Info("Using stock/custom theme colors with matugen base")
		primaryDark = extractNestedColor(opts.StockColors, "primary", "dark")
		primaryLight = extractNestedColor(opts.StockColors, "primary", "light")
		surfaceDark = extractNestedColor(opts.StockColors, "surface", "dark")
		surfaceLight = extractNestedColor(opts.StockColors, "surface", "light")
		containerDark = extractNestedColor(opts.StockColors, "primary_container", "dark")
		containerLight = extractNestedColor(opts.StockColors, "primary_container", "light")

		if primaryDark == "" {
			return false, fmt.Errorf("failed to extract primary dark from stock colors")
		}
		if primaryLight == "" {
			primaryLight = primaryDark
		}

		built = buildPalettes(opts, dank16Seeds{primaryDark, primaryLight, surfaceDark, surfaceLight, containerDark, containerLight}, opts.StockColors, false)
		dank16JSON = built.Dank16JSON
		colors := cmp.Or(built.AdjustedRoles, opts.StockColors)
		importArgs = []string{"--import-json-string", buildImportData(dank16JSON, "", colors, []paletteInjection{built.termInjection()})}

		log.Info("Running matugen color hex with stock color overrides")
		args = []string{"color", "hex", primaryDark, "-m", string(opts.Mode), "-t", opts.MatugenType}
	} else {
		log.Infof("Using dynamic theme from %s: %s", opts.Kind, opts.Value)

		if opts.Kind == "image" {
			seed, err := seeds.resolve(sourceImage, opts.SourceMode, flags.version, func() (string, error) {
				if seed, err := matugenSeed(smartJSON); err == nil {
					return seed, nil
				}
				output, err := runMatugenDryRun(opts)
				if err != nil {
					return "", err
				}
				return matugenSeed(output)
			})
			if err != nil {
				log.Warnf("Seed resolution failed for %s, running matugen on the image: %v", sourceImage, err)
			} else {
				log.Infof("Seed color: %s -> %s", sourceImage, seed)
				opts.Kind = "hex"
				opts.Value = seed
			}
		}

		matJSON, err := runMatugenDryRun(opts)
		if err != nil {
			return false, fmt.Errorf("matugen dry-run failed: %w", err)
		}

		// The 2025 spec is generated here from the seed matugen settled on and
		// overrides matugen's own roles through the import, so templates,
		// {{image}} and the user's own config keep working unchanged.
		var specColors string
		if UsesSpecGenerator(opts.Spec, opts.MatugenType) {
			seed := opts.Value
			if opts.Kind != "hex" {
				seed = extractMatugenColor(matJSON, "source_color", "dark")
			}
			specColors, err = GenerateSpecColors(seed, opts.MatugenType, opts.Contrast, opts.Mode, opts.Spec)
			if err != nil {
				return false, fmt.Errorf("spec %s palette failed: %w", opts.Spec, err)
			}
		}

		extract := func(role, mode string) string {
			if specColors != "" {
				return extractNestedColor(specColors, role, mode)
			}
			return extractMatugenColor(matJSON, role, mode)
		}
		primaryDark = extract("primary", "dark")
		primaryLight = extract("primary", "light")
		surfaceDark = extract("surface", "dark")
		surfaceLight = extract("surface", "light")
		containerDark = extract("primary_container", "dark")
		containerLight = extract("primary_container", "light")

		if primaryDark == "" {
			return false, fmt.Errorf("failed to extract primary color")
		}
		if primaryLight == "" {
			primaryLight = primaryDark
		}

		rolesSrc, wrapped := specColors, false
		if rolesSrc == "" {
			rolesSrc, wrapped = matJSON, true
		}
		built = buildPalettes(opts, dank16Seeds{primaryDark, primaryLight, surfaceDark, surfaceLight, containerDark, containerLight}, rolesSrc, wrapped)
		dank16JSON = built.Dank16JSON
		colors := cmp.Or(built.AdjustedRoles, specColors)
		injections := append([]paletteInjection{built.termInjection()}, InjectedPalettes(opts.ConfigDir, sourceImage, opts.Mode)...)
		importArgs = []string{"--import-json-string", buildImportData(dank16JSON, sourceImage, colors, injections)}

		log.Infof("Running matugen %s with dank16 injection", opts.Kind)
		switch opts.Kind {
		case "hex":
			args = []string{"color", "hex", opts.Value}
		default:
			args = []string{opts.Kind, opts.Value}
		}
		args = append(args, "-m", string(opts.Mode), "-t", opts.MatugenType)
	}
	args = appendContrastArg(args, opts.Contrast)
	args = append(args, importArgs...)

	opts.terminalContrast = built.Contrast.terminalAdjustments(opts.TerminalsAlwaysDark)
	primaryDark = built.Contrast.adjusted("colors.primary", "dark", primaryDark)
	primaryLight = built.Contrast.adjusted("colors.primary", "light", primaryLight)

	changed, err := renderColors(opts, args, tmpDir, oldColors, built)
	if err != nil {
		return false, err
	}
	if opts.ColorsOnly {
		return changed, nil
	}
	if err := renderTemplates(opts, args, tmpDir); err != nil {
		return false, err
	}
	signalTerminals(opts)
	if !changed {
		return false, nil
	}

	if isDMSGTKActive(opts.ConfigDir) {
		switch opts.Mode {
		case ColorModeLight:
			syncAccentColor(primaryLight)
		default:
			syncAccentColor(primaryDark)
		}
		refreshGTKTheme(opts.Mode)
		refreshGTKColorScheme()
	}

	if isDMSKDEColorSchemeActive(opts.ConfigDir) {
		applyKDEColorScheme(opts.Mode)
	}

	if !opts.ShouldSkipTemplate("qt6ct") && appExists(opts.AppChecker, []string{"qt6ct"}, nil) {
		refreshQt6ct()
	}

	// kcolorscheme writes the .colors file qtengine is pointed at, so with that
	// template off there is nothing to point to and the config would name a
	// scheme DMS no longer generates.
	if !opts.ShouldSkipTemplate("qtengine") && !opts.ShouldSkipTemplate("kcolorscheme") && QtengineActive() {
		if err := SyncQtengineConfigAt(opts.ConfigDir, opts.IconTheme); err != nil {
			log.Warnf("Failed to sync qtengine config: %v", err)
		}
	}

	if !opts.ShouldSkipTemplate("fcitx5") && appExists(opts.AppChecker, []string{"fcitx5"}, nil) {
		refreshFcitx5()
	}

	return true, nil
}

// The shell only needs dms-colors.json, so it is rendered and committed on its own before the template pass.
func renderColors(opts *Options, args []string, tmpDir string, oldColors []byte, built *builtPalettes) (bool, error) {
	colorsOpts := *opts
	colorsOpts.ColorsOnly = true
	cfgPath, err := writeMergedConfig(&colorsOpts, tmpDir, "colors.toml")
	if err != nil {
		return false, err
	}
	if err := runMatugen(append(slices.Clone(args), "-c", cfgPath), opts.SourceMode); err != nil {
		return false, err
	}
	newColors, err := os.ReadFile(opts.colorsStaging())
	if err != nil {
		return false, fmt.Errorf("matugen did not produce colors output: %w", err)
	}
	if newColors, err = withPaletteRecord(newColors, &built.Term, built.Contrast); err != nil {
		return false, fmt.Errorf("failed to add terminal palette to colors output: %w", err)
	}
	if err := os.WriteFile(opts.colorsStaging(), newColors, 0o644); err != nil {
		return false, fmt.Errorf("failed to write colors output: %w", err)
	}
	if bytes.Equal(oldColors, newColors) && len(oldColors) > 0 {
		return false, nil
	}
	if err := os.Rename(opts.colorsStaging(), opts.ColorsOutput()); err != nil {
		return false, fmt.Errorf("failed to commit colors output: %w", err)
	}
	return true, nil
}

func renderTemplates(opts *Options, args []string, tmpDir string) error {
	cfgPath, err := writeMergedConfig(opts, tmpDir, "templates.toml")
	if err != nil {
		return err
	}
	return runMatugen(append(slices.Clone(args), "-c", cfgPath), opts.SourceMode)
}

func writeMergedConfig(opts *Options, tmpDir, name string) (string, error) {
	cfgFile, err := os.Create(filepath.Join(tmpDir, name))
	if err != nil {
		return "", fmt.Errorf("failed to create temp config: %w", err)
	}
	defer cfgFile.Close()
	if err := buildMergedConfig(opts, cfgFile, tmpDir); err != nil {
		return "", fmt.Errorf("failed to build config: %w", err)
	}
	return cfgFile.Name(), nil
}

func appendContrastArg(args []string, contrast float64) []string {
	if contrast == 0 {
		return args
	}
	return append(args, "--contrast", strconv.FormatFloat(contrast, 'f', -1, 64))
}

// buildImportData is the JSON passed to matugen's --import-json-string. image is
// set only when the source was rewritten from a wallpaper to a hex color, where
// matugen leaves {{image}} unset and templates using it would render "Null".
// colors, when set, is a full role map that replaces matugen's own palette.
// Each injection is exposed under its own namespace (e.g. {{mypalette.color0}}),
// skipping any name already emitted so the object stays valid.
func buildImportData(dank16JSON, image, colors string, injections []paletteInjection) string {
	fields := []string{fmt.Sprintf(`"dank16": %s`, dank16JSON)}
	if image != "" {
		path, _ := json.Marshal(image)
		fields = append(fields, fmt.Sprintf(`"image": %s`, path))
	}
	if colors != "" {
		fields = append(fields, fmt.Sprintf(`"colors": %s`, colors))
	}
	seen := map[string]bool{"dank16": true, "image": true, "colors": true}
	for _, inj := range injections {
		if inj.Namespace == "" || inj.JSON == "" || seen[inj.Namespace] {
			continue
		}
		seen[inj.Namespace] = true
		nsKey, _ := json.Marshal(inj.Namespace)
		fields = append(fields, fmt.Sprintf(`%s: %s`, nsKey, inj.JSON))
	}
	return "{" + strings.Join(fields, ", ") + "}"
}

func userConfigSection(opts *Options) string {
	if !opts.RunUserTemplates || opts.ConfigDir == "" {
		return "[config]\n\n"
	}
	data, err := os.ReadFile(filepath.Join(opts.ConfigDir, "matugen", "config.toml"))
	if err != nil {
		return "[config]\n\n"
	}
	section := extractTOMLSection(string(data), "[config]", "[templates]")
	if section == "" {
		return "[config]\n\n"
	}
	return section + "\n"
}

func buildMergedConfig(opts *Options, cfgFile *os.File, tmpDir string) error {
	userConfigPath := filepath.Join(opts.ConfigDir, "matugen", "config.toml")

	cfgFile.WriteString(userConfigSection(opts))

	baseConfigPath := filepath.Join(opts.ShellDir, "matugen", "configs", "base.toml")
	if data, err := os.ReadFile(baseConfigPath); err == nil {
		content := string(data)
		lines := strings.SplitSeq(content, "\n")
		for line := range lines {
			if strings.TrimSpace(line) == "[config]" {
				continue
			}
			cfgFile.WriteString(substituteVars(line, opts.ShellDir) + "\n")
		}
		cfgFile.WriteString("\n")
	}

	fmt.Fprintf(cfgFile, `[templates.dank]
input_path = '%s/matugen/templates/dank.json'
output_path = '%s'

`, opts.ShellDir, opts.colorsStaging())

	if opts.ColorsOnly {
		return nil
	}

	homeDir, _ := os.UserHomeDir()
	for _, tmpl := range templateRegistry {
		if opts.ShouldSkipTemplate(tmpl.ID) {
			continue
		}
		if !templateSessionActive(tmpl) {
			continue
		}

		switch tmpl.Kind {
		case TemplateKindGTK:
			switch opts.Mode {
			case ColorModeLight:
				appendConfig(opts, cfgFile, nil, nil, nil, "gtk3-light.toml")
			default:
				appendConfig(opts, cfgFile, nil, nil, nil, "gtk3-dark.toml")
			}
		case TemplateKindTerminal:
			appendTerminalConfig(opts, cfgFile, tmpDir, tmpl.Commands, tmpl.Flatpaks, tmpl.ConfigFile)
		case TemplateKindVSCode:
			for _, editor := range vscodeEditors {
				appendVSCodeConfig(cfgFile, editor.name, editor.extensionsDir(homeDir), opts.ShellDir)
			}
		case TemplateKindEmacs:
			if utils.EmacsConfigDir() != "" {
				appendConfig(opts, cfgFile, tmpl.Commands, tmpl.Flatpaks, tmpl.ConfigDirs, tmpl.ConfigFile)
			}
		default:
			flatpaks := tmpl.Flatpaks
			if tmpl.FlatpakConfigPath != "" {
				flatpaks = nil
			}
			appendConfig(opts, cfgFile, tmpl.Commands, flatpaks, tmpl.ConfigDirs, tmpl.ConfigFile)
			if tmpl.FlatpakConfigPath != "" {
				appendFlatpakConfig(opts, cfgFile, tmpl.Flatpaks, tmpl.ConfigFile, tmpl.FlatpakConfigPath)
			}
		}
	}

	if opts.RunUserTemplates {
		if data, err := os.ReadFile(userConfigPath); err == nil {
			templatesSection := extractTOMLSection(string(data), "[templates]", "")
			if templatesSection != "" {
				cfgFile.WriteString(templatesSection)
				cfgFile.WriteString("\n")
			}
		}
	}

	userPluginConfigDir := filepath.Join(opts.ConfigDir, "matugen", "dms", "configs")
	if entries, err := os.ReadDir(userPluginConfigDir); err == nil {
		for _, entry := range entries {
			if !strings.HasSuffix(entry.Name(), ".toml") {
				continue
			}
			if data, err := os.ReadFile(filepath.Join(userPluginConfigDir, entry.Name())); err == nil {
				cfgFile.WriteString(string(data))
				cfgFile.WriteString("\n")
			}
		}
	}

	return nil
}

func appendConfig(
	opts *Options,
	cfgFile *os.File,
	checkCmd []string,
	checkFlatpaks []string,
	checkConfigDirs []string,
	fileName string,
) {
	appendConfigContent(opts, cfgFile, checkCmd, checkFlatpaks, checkConfigDirs, fileName, "")
}

func appendFlatpakConfig(opts *Options, cfgFile *os.File, checkFlatpaks []string, fileName, configPath string) {
	appendConfigContent(opts, cfgFile, nil, checkFlatpaks, nil, fileName, configPath)
}

func appendConfigContent(
	opts *Options,
	cfgFile *os.File,
	checkCmd []string,
	checkFlatpaks []string,
	checkConfigDirs []string,
	fileName string,
	flatpakConfigPath string,
) {
	configPath := filepath.Join(opts.ShellDir, "matugen", "configs", fileName)
	if _, err := os.Stat(configPath); err != nil {
		return
	}
	if !appExists(opts.AppChecker, checkCmd, checkFlatpaks) && !configDirExists(checkConfigDirs) {
		log.Debugf("Skipping template %s: app not detected", strings.TrimSuffix(fileName, ".toml"))
		return
	}
	data, err := os.ReadFile(configPath)
	if err != nil {
		return
	}
	content := string(data)
	if flatpakConfigPath != "" {
		content = strings.ReplaceAll(content, "'CONFIG_DIR/", "'FLATPAK_CONFIG_DIR/"+flatpakConfigPath+"/")
		lines := strings.Split(content, "\n")
		for i, line := range lines {
			if strings.HasPrefix(line, "[templates.") && strings.HasSuffix(line, "]") {
				lines[i] = strings.TrimSuffix(line, "]") + "-flatpak]"
			}
		}
		content = strings.Join(lines, "\n")
	}
	cfgFile.WriteString(substituteVars(content, opts.ShellDir))
	cfgFile.WriteString("\n")
}

func appendTerminalConfig(opts *Options, cfgFile *os.File, tmpDir string, checkCmd []string, checkFlatpaks []string, fileName string) {
	configPath := filepath.Join(opts.ShellDir, "matugen", "configs", fileName)
	if _, err := os.Stat(configPath); err != nil {
		return
	}
	if !appExists(opts.AppChecker, checkCmd, checkFlatpaks) {
		log.Debugf("Skipping template %s: app not detected", strings.TrimSuffix(fileName, ".toml"))
		return
	}
	data, err := os.ReadFile(configPath)
	if err != nil {
		return
	}

	content := string(data)

	if !opts.TerminalsAlwaysDark && !terminalOpacityManaged(opts) && len(opts.terminalContrast) == 0 {
		cfgFile.WriteString(substituteVars(content, opts.ShellDir))
		cfgFile.WriteString("\n")
		return
	}

	lines := strings.SplitSeq(content, "\n")
	for line := range lines {
		if !strings.Contains(line, "input_path") || !strings.Contains(line, "SHELL_DIR/matugen/templates/") {
			continue
		}

		start := strings.Index(line, "'SHELL_DIR/matugen/templates/")
		if start == -1 {
			continue
		}
		end := strings.Index(line[start+1:], "'")
		if end == -1 {
			continue
		}
		templateName := line[start+len("'SHELL_DIR/matugen/templates/") : start+1+end]
		origPath := filepath.Join(opts.ShellDir, "matugen", "templates", templateName)

		origData, err := os.ReadFile(origPath)
		if err != nil {
			continue
		}

		modified := applyTerminalTemplate(templateName, string(origData), opts)
		tmpPath := filepath.Join(tmpDir, templateName)
		if err := os.WriteFile(tmpPath, []byte(modified), 0o644); err != nil {
			continue
		}

		content = strings.ReplaceAll(content,
			fmt.Sprintf("'SHELL_DIR/matugen/templates/%s'", templateName),
			fmt.Sprintf("'%s'", tmpPath))
	}

	cfgFile.WriteString(substituteVars(content, opts.ShellDir))
	cfgFile.WriteString("\n")
}

func commentMarker(templateName string) string {
	if strings.HasSuffix(templateName, ".lua") {
		return "--"
	}
	return "#"
}

func terminalOpacityManaged(opts *Options) bool {
	return opts.TerminalOpacity >= 1 && opts.TerminalOpacity <= 99
}

func applyTerminalTemplate(name, content string, opts *Options) string {
	if opts.TerminalsAlwaysDark {
		content = strings.ReplaceAll(content, ".default.", ".dark.")
	}
	content = contrastHeader(opts.terminalContrast, commentMarker(name)) + content
	if !terminalOpacityManaged(opts) {
		return content
	}
	v := strconv.FormatFloat(float64(opts.TerminalOpacity)/100, 'f', -1, 64)
	var snippet string
	switch name {
	case "kitty.conf":
		snippet = "background_opacity " + v + "\ndynamic_background_opacity yes\n"
	case "foot.ini":
		snippet = "alpha=" + v + "\n"
	case "ghostty.conf":
		snippet = "background-opacity = " + v + "\n"
	case "alacritty.toml":
		snippet = "[window]\nopacity = " + v + "\n"
	default:
		return content
	}
	if content != "" && !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	return content + snippet
}

func templateSessionActive(tmpl TemplateDef) bool {
	if tmpl.RequiredEnv == "" {
		return true
	}
	socket := os.Getenv(tmpl.RequiredEnv)
	if socket == "" {
		return false
	}
	_, err := os.Stat(socket)
	return err == nil
}

func configDirExists(names []string) bool {
	configHome := utils.XDGConfigHome()
	if configHome == "" {
		return false
	}
	for _, name := range names {
		info, err := os.Stat(filepath.Join(configHome, name))
		if err == nil && info.IsDir() {
			return true
		}
	}
	return false
}

func appExists(checker utils.AppChecker, checkCmd []string, checkFlatpaks []string) bool {
	// Both nil is treated as "skip check" / unconditionally run
	if checkCmd == nil && checkFlatpaks == nil {
		return true
	}
	if checkCmd != nil && checker.AnyCommandExists(checkCmd...) {
		return true
	}
	if checkFlatpaks != nil && checker.AnyFlatpakExists(checkFlatpaks...) {
		return true
	}
	return false
}

type vscodeEditor struct {
	name    string
	dataDir string
}

var vscodeEditors = []vscodeEditor{
	{"vscode", ".vscode"},
	{"codium", ".vscode-oss"},
	{"cursor", ".cursor"},
	{"windsurf", ".windsurf"},
	{"positron", ".positron"},
	{"antigravity", ".antigravity-ide"},
	{"vscode-insiders", ".vscode-insiders"},
}

func (e vscodeEditor) extensionsDir(homeDir string) string {
	return filepath.Join(homeDir, e.dataDir, "extensions")
}

func appendVSCodeConfig(cfgFile *os.File, name, extBaseDir, shellDir string) {
	pattern := filepath.Join(extBaseDir, "danklinux.dms-theme-*")
	matches, err := filepath.Glob(pattern)
	if err != nil || len(matches) == 0 {
		return
	}

	extDir := matches[0]
	templateDir := filepath.Join(shellDir, "matugen", "templates")
	fmt.Fprintf(cfgFile, `[templates.dms%sdefault]
input_path = '%s/vscode-color-theme-default.json'
output_path = '%s/themes/dankshell-default.json'

[templates.dms%sdark]
input_path = '%s/vscode-color-theme-dark.json'
output_path = '%s/themes/dankshell-dark.json'

[templates.dms%slight]
input_path = '%s/vscode-color-theme-light.json'
output_path = '%s/themes/dankshell-light.json'

`, name, templateDir, extDir,
		name, templateDir, extDir,
		name, templateDir, extDir)
	log.Infof("Added %s theme config (extension found at %s)", name, extDir)
}

func substituteVars(content, shellDir string) string {
	result := strings.ReplaceAll(content, "'SHELL_DIR/", "'"+shellDir+"/")
	result = strings.ReplaceAll(result, "'CONFIG_DIR/", "'"+utils.XDGConfigHome()+"/")
	result = strings.ReplaceAll(result, "'DATA_DIR/", "'"+utils.XDGDataHome()+"/")
	result = strings.ReplaceAll(result, "'CACHE_DIR/", "'"+utils.XDGCacheHome()+"/")
	if homeDir, err := os.UserHomeDir(); err == nil {
		result = strings.ReplaceAll(result, "'FLATPAK_CONFIG_DIR/", "'"+filepath.Join(homeDir, ".var", "app")+"/")
	}
	if emacsDir := utils.EmacsConfigDir(); emacsDir != "" {
		result = strings.ReplaceAll(result, "'EMACS_DIR/", "'"+emacsDir+"/")
	}
	return result
}

func extractTOMLSection(content, startMarker, endMarker string) string {
	startIdx := strings.Index(content, startMarker)
	if startIdx == -1 {
		return ""
	}

	if endMarker == "" {
		return content[startIdx:]
	}

	endIdx := strings.Index(content[startIdx:], endMarker)
	if endIdx == -1 {
		return content[startIdx:]
	}
	return content[startIdx : startIdx+endIdx]
}

type matugenFlags struct {
	supportsCOE    bool
	isV4           bool
	isV42          bool
	supportsPrefer bool
	version        string
}

func detectMatugenVersion() (matugenFlags, error) {
	matugenVersionMu.Lock()
	defer matugenVersionMu.Unlock()

	if matugenVersionOK {
		return matugenFlags{matugenSupportsCOE, matugenIsV4, matugenIsV42, matugenSupportsPrefer, matugenVersionStr}, nil
	}

	return detectMatugenVersionLocked()
}

func SupportsSmart() bool {
	flags, err := detectMatugenVersion()
	return err == nil && flags.isV42
}

func redetectMatugenVersion(old matugenFlags) (matugenFlags, bool) {
	matugenVersionMu.Lock()
	defer matugenVersionMu.Unlock()

	matugenVersionOK = false
	flags, err := detectMatugenVersionLocked()
	if err != nil {
		return old, false
	}
	changed := flags.supportsCOE != old.supportsCOE || flags.isV4 != old.isV4 || flags.isV42 != old.isV42 ||
		flags.supportsPrefer != old.supportsPrefer
	return flags, changed
}

func detectMatugenVersionLocked() (matugenFlags, error) {
	cmd := exec.Command("matugen", "--version")
	cmd.Env = utils.EnvWithUserBinPath(nil)
	output, err := cmd.Output()
	if err != nil {
		return matugenFlags{}, fmt.Errorf("failed to get matugen version: %w", err)
	}

	versionStr := strings.TrimSpace(string(output))
	versionStr = strings.TrimPrefix(versionStr, "matugen ")

	parts := strings.Split(versionStr, ".")
	if len(parts) < 2 {
		return matugenFlags{}, fmt.Errorf("unexpected matugen version format: %q", versionStr)
	}

	major, err := strconv.Atoi(parts[0])
	if err != nil {
		return matugenFlags{}, fmt.Errorf("failed to parse matugen major version %q: %w", parts[0], err)
	}

	minor, err := strconv.Atoi(parts[1])
	if err != nil {
		return matugenFlags{}, fmt.Errorf("failed to parse matugen minor version %q: %w", parts[1], err)
	}

	matugenSupportsCOE = major > 3 || (major == 3 && minor >= 1)
	matugenIsV4 = major >= 4
	matugenIsV42 = major > 4 || (major == 4 && minor >= 2)
	// --prefer landed in 4.1; 4.0.x has --source-color-index but not --prefer,
	// and clap aborts on an unknown argument rather than ignoring it.
	matugenSupportsPrefer = major > 4 || (major == 4 && minor >= 1)
	matugenVersionStr = versionStr
	matugenVersionOK = true

	if matugenSupportsCOE {
		log.Debugf("Matugen %s detected: continue-on-error support enabled", versionStr)
	}
	if matugenIsV4 {
		log.Debugf("Matugen %s detected: using v4 compatibility flags", versionStr)
	}
	if matugenIsV4 && !matugenSupportsPrefer {
		log.Debugf("Matugen %s detected: --prefer unavailable, source modes fall back to the dominant color", versionStr)
	}
	return matugenFlags{matugenSupportsCOE, matugenIsV4, matugenIsV42, matugenSupportsPrefer, matugenVersionStr}, nil
}

func buildMatugenArgs(baseArgs []string, flags matugenFlags, sourceMode string) []string {
	args := make([]string, 0, len(baseArgs)+4)
	if flags.supportsCOE {
		args = append(args, "--continue-on-error")
	}
	args = append(args, baseArgs...)
	// matugen 3 has neither flag. matugen 4's --source-color-index help notes
	// "In earlier versions the default was 0", so omitting both on v3 gives the
	// same seed the flag would have asked for.
	if flags.isV4 {
		args = append(args, sourceSelectionArgs(sourceMode, flags.supportsPrefer)...)
	}
	return args
}

func runMatugen(baseArgs []string, sourceMode string) error {
	flags, err := detectMatugenVersion()
	if err != nil {
		return err
	}

	runErr := execMatugen(buildMatugenArgs(baseArgs, flags, sourceMode))
	if runErr == nil {
		return nil
	}

	log.Warnf("Matugen failed (v4=%v): %v", flags.isV4, runErr)

	newFlags, changed := redetectMatugenVersion(flags)
	if !changed {
		return runErr
	}

	log.Warnf("Matugen version changed (v4: %v -> %v), retrying", flags.isV4, newFlags.isV4)
	return execMatugen(buildMatugenArgs(baseArgs, newFlags, sourceMode))
}

// matugen's stderr is echoed as before and its tail travels in the error, so a failure
// reaching the shell through the socket still names the broken template or option.
func execMatugen(args []string) error {
	cmd := exec.Command("matugen", args...)
	cmd.Env = utils.EnvWithUserBinPath(nil)
	cmd.Stdout = os.Stdout
	var stderr bytes.Buffer
	cmd.Stderr = io.MultiWriter(os.Stderr, &stderr)
	err := cmd.Run()
	if err == nil {
		return nil
	}
	tail := stderrTail(stderr.String(), 6)
	if tail == "" {
		return fmt.Errorf("matugen: %w", err)
	}
	return fmt.Errorf("matugen: %w\n%s", err, tail)
}

var ansiEscapeRe = regexp.MustCompile(`\x1b\[[0-9;]*[a-zA-Z]`)

func stderrTail(output string, maxLines int) string {
	var lines []string
	for _, line := range strings.Split(ansiEscapeRe.ReplaceAllString(output, ""), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			lines = append(lines, line)
		}
	}
	if len(lines) > maxLines {
		lines = lines[len(lines)-maxLines:]
	}
	return strings.Join(lines, "\n")
}

func runMatugenDryRun(opts *Options) (string, error) {
	flags, err := detectMatugenVersion()
	if err != nil {
		return "", err
	}

	output, dryErr := execDryRun(opts, flags)
	if dryErr == nil {
		return output, nil
	}

	log.Warnf("Matugen dry-run failed (v4=%v): %v", flags.isV4, dryErr)

	newFlags, changed := redetectMatugenVersion(flags)
	if !changed {
		return "", dryErr
	}

	log.Warnf("Matugen version changed (v4: %v -> %v), retrying dry-run", flags.isV4, newFlags.isV4)
	return execDryRun(opts, newFlags)
}

// matugen aborts on a config file it cannot deserialize, and without -c it
// reads the user's own ~/.config/matugen/config.toml, so a dry run gets a
// config of its own instead of inheriting whatever is there.
func writeDryRunConfig(opts *Options) (string, error) {
	cfgFile, err := os.CreateTemp("", "matugen-dryrun-*.toml")
	if err != nil {
		return "", fmt.Errorf("failed to create dry-run config: %w", err)
	}
	defer cfgFile.Close()

	section := userConfigSection(opts)
	if idx := strings.Index(section, "\n[templates"); idx != -1 {
		section = section[:idx+1]
	}
	cfgFile.WriteString(section)
	cfgFile.WriteString("[templates]\n")
	return cfgFile.Name(), nil
}

func execDryRun(opts *Options, flags matugenFlags) (string, error) {
	cfgPath, err := writeDryRunConfig(opts)
	if err != nil {
		return "", err
	}
	defer os.Remove(cfgPath)

	var baseArgs []string
	switch opts.Kind {
	case "hex":
		baseArgs = []string{"color", "hex", opts.Value}
	default:
		baseArgs = []string{opts.Kind, opts.Value}
	}
	baseArgs = append(baseArgs, "-m", string(opts.Mode), "-t", opts.MatugenType, "-c", cfgPath, "--json", "hex", "--dry-run")
	baseArgs = appendContrastArg(baseArgs, opts.Contrast)
	if flags.isV4 {
		baseArgs = append(baseArgs, sourceSelectionArgs(opts.SourceMode, flags.supportsPrefer)...)
		baseArgs = append(baseArgs, "--old-json-output")
	}

	cmd := exec.Command("matugen", baseArgs...)
	cmd.Env = utils.EnvWithUserBinPath(nil)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	output, err := cmd.Output()
	if err != nil {
		if tail := stderrTail(stderr.String(), 6); tail != "" {
			return "", fmt.Errorf("matugen %v failed (v4=%v): %s", baseArgs, flags.isV4, tail)
		}
		return "", fmt.Errorf("matugen %v failed (v4=%v): %w", baseArgs, flags.isV4, err)
	}
	clean := string(output)
	// Some matugen builds print a warning line to stdout (e.g. scheme-smart
	// falling back to defaults for a non-image source) ahead of the JSON
	// payload. The pretty-printed JSON always opens with a line containing
	// only '{', so drop anything before that
	if !strings.HasPrefix(clean, "{") {
		if idx := strings.Index(clean, "\n{\n"); idx != -1 {
			clean = clean[idx+1:]
		}
	}
	return strings.ReplaceAll(clean, "\n", ""), nil
}

func extractMatugenColor(jsonStr, colorName, variant string) string {
	var data map[string]any
	if err := json.Unmarshal([]byte(jsonStr), &data); err != nil {
		return ""
	}

	colors, ok := data["colors"].(map[string]any)
	if !ok {
		return ""
	}

	colorData, ok := colors[colorName].(map[string]any)
	if !ok {
		return ""
	}

	variantData, ok := colorData[variant].(string)
	if !ok {
		return ""
	}

	return variantData
}

func extractTopLevelString(jsonStr, key string) string {
	var data map[string]any
	if err := json.Unmarshal([]byte(jsonStr), &data); err != nil {
		return ""
	}
	if val, ok := data[key].(string); ok {
		return val
	}
	return ""
}

func resolveSmartMode(opts *Options, flags matugenFlags) (string, error) {
	if opts.MatugenType == "scheme-smart" && !flags.isV42 {
		return "", fmt.Errorf("scheme-smart requires matugen 4.2+")
	}
	if opts.Mode != ColorModeSmart {
		return "", nil
	}
	if !flags.isV42 {
		return "", fmt.Errorf("smart mode requires matugen 4.2+")
	}
	if opts.Kind != "image" || opts.StockColors != "" {
		opts.Mode = ColorModeDark
		return "", nil
	}
	output, err := runMatugenDryRun(opts)
	if err != nil {
		return "", fmt.Errorf("smart mode resolution failed: %w", err)
	}
	resolved := extractTopLevelString(output, "mode")
	if resolved != string(ColorModeLight) && resolved != string(ColorModeDark) {
		return "", fmt.Errorf("smart mode resolution returned unexpected mode %q", resolved)
	}
	log.Infof("Smart mode resolved to %s", resolved)
	opts.Mode = ColorMode(resolved)
	return output, nil
}

func matugenSeed(dryRunJSON string) (string, error) {
	seed := extractMatugenColor(dryRunJSON, "source_color", "dark")
	if seed == "" {
		return "", fmt.Errorf("matugen output has no source_color")
	}
	return seed, nil
}

func extractNestedColor(jsonStr, colorName, variant string) string {
	var data map[string]any
	if err := json.Unmarshal([]byte(jsonStr), &data); err != nil {
		return ""
	}

	colorData, ok := data[colorName].(map[string]any)
	if !ok {
		return ""
	}

	variantData, ok := colorData[variant].(map[string]any)
	if !ok {
		return ""
	}

	color, ok := variantData["color"].(string)
	if !ok {
		return ""
	}

	return color
}

type dank16Seeds struct {
	PrimaryDark, PrimaryLight, SurfaceDark, SurfaceLight, ContainerDark, ContainerLight string
}

func generateDank16Variants(s dank16Seeds, mode ColorMode, profile string) dank16.VariantPalette {
	return dank16.GenerateVariantPalette(dank16.VariantOptions{
		PrimaryDark:     s.PrimaryDark,
		PrimaryLight:    s.PrimaryLight,
		BackgroundDark:  s.SurfaceDark,
		BackgroundLight: s.SurfaceLight,
		ContainerDark:   s.ContainerDark,
		ContainerLight:  s.ContainerLight,
		UseDPS:          true,
		IsLightMode:     mode == ColorModeLight,
		Profile:         profile,
	})
}

type builtPalettes struct {
	Dank16JSON    string
	Term          dank16.VariantPalette
	AdjustedRoles string
	Contrast      contrastResult
}

// The terminal palette only reaches the terminal templates; editor themes and user templates keep dank16.
func (b *builtPalettes) termInjection() paletteInjection {
	return paletteInjection{Namespace: "dank16term", JSON: dank16.GenerateVariantJSON(b.Term)}
}

// rolesSrc is matugen output when wrapped, else a bare role map. AdjustedRoles stays "" when no
// role moved, so the theme's own roles are imported unchanged.
func buildPalettes(opts *Options, seeds dank16Seeds, rolesSrc string, wrapped bool) *builtPalettes {
	d16 := generateDank16Variants(seeds, opts.Mode, "")
	b := &builtPalettes{Term: generateDank16Variants(seeds, opts.Mode, opts.TerminalPalette)}

	// Roles are read even with nothing to change: the audit measures them, and terminal colors against colors.background.
	roles := rolesFromJSON(rolesSrc, wrapped)
	b.Contrast = applyContrast(opts.ContrastOverrides, roles, map[string]*dank16.VariantPalette{"dank16": &d16, "dank16term": &b.Term}, opts.Mode)
	if b.Contrast.rolesChanged() {
		b.AdjustedRoles = roles.importJSON()
	}
	b.Dank16JSON = dank16.GenerateVariantJSON(d16)
	return b
}

func rolesFromJSON(src string, wrapped bool) roleMap {
	var data map[string]any
	if err := json.Unmarshal([]byte(src), &data); err != nil {
		log.Warnf("contrast: cannot read theme roles: %v", err)
		return roleMap{}
	}
	if wrapped {
		data, _ = data["colors"].(map[string]any)
	}
	return parseRoleMap(data)
}

func isDMSGTKActive(configDir string) bool {
	gtkCSS := filepath.Join(configDir, "gtk-4.0", "gtk.css")

	info, err := os.Lstat(gtkCSS)
	if err != nil {
		return false
	}

	if info.Mode()&os.ModeSymlink != 0 {
		target, err := os.Readlink(gtkCSS)
		return err == nil && strings.Contains(target, "dank-colors.css")
	}

	data, err := os.ReadFile(gtkCSS)
	return err == nil && strings.Contains(string(data), "dank-colors.css")
}

// isDMSKDEColorSchemeActive only flips the scheme when the user is already on a
// DankMatugen one, leaving Breeze (or anything else) untouched.
func isDMSKDEColorSchemeActive(configDir string) bool {
	data, err := os.ReadFile(filepath.Join(configDir, "kdeglobals"))
	if err != nil {
		return false
	}

	inGeneral := false
	for line := range strings.SplitSeq(string(data), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[") {
			inGeneral = line == "[General]"
			continue
		}
		if !inGeneral {
			continue
		}
		if name, ok := strings.CutPrefix(line, "ColorScheme="); ok {
			return strings.HasPrefix(strings.TrimSpace(name), "DankMatugen")
		}
	}
	return false
}

func applyKDEColorScheme(mode ColorMode) {
	if !utils.CommandExists("plasma-apply-colorscheme") {
		return
	}

	scheme := "DankMatugenDark"
	if mode == ColorModeLight {
		scheme = "DankMatugenLight"
	}

	log.Infof("Applying KDE color scheme: %s", scheme)
	if err := exec.Command("plasma-apply-colorscheme", scheme).Run(); err != nil {
		log.Warnf("Failed to apply KDE color scheme: %v", err)
	}
}

func gtkThemeInstalled(theme string) bool {
	home, _ := os.UserHomeDir()
	candidates := []string{
		filepath.Join(home, ".local/share/themes", theme),
		filepath.Join(home, ".themes", theme),
		filepath.Join("/usr/share/themes", theme),
		filepath.Join("/usr/local/share/themes", theme),
	}
	for _, dir := range candidates {
		if info, err := os.Stat(dir); err == nil && info.IsDir() {
			return true
		}
	}
	return false
}

func refreshGTKTheme(mode ColorMode) {
	theme := mode.GTKTheme()
	if !gtkThemeInstalled(theme) {
		log.Infof("Skipping gtk-theme refresh: %s is not installed", theme)
		return
	}
	if err := utils.GsettingsSet("org.gnome.desktop.interface", "gtk-theme", mode.GTKRefreshTheme()); err != nil {
		log.Warnf("Failed to reset gtk-theme: %v", err)
	}
	if err := utils.GsettingsSet("org.gnome.desktop.interface", "gtk-theme", theme); err != nil {
		log.Warnf("Failed to set gtk-theme: %v", err)
	}
}

var colorSchemeEchoHook func(scheme string)

func SetColorSchemeEchoHook(hook func(scheme string)) {
	colorSchemeEchoHook = hook
}

func expectColorSchemeEcho(scheme string) {
	if colorSchemeEchoHook != nil {
		colorSchemeEchoHook(scheme)
	}
}

// The color-scheme round trip is the only mechanism that makes running GTK4
// apps reload ~/.config/gtk-4.0 CSS (a gtk-theme flip does not). But apps
// following the portal color-scheme (Chromium) can drop the restore signal
// mid-repaint and latch the wrong mode, so this is opt-in.
func refreshGTKColorScheme() {
	if os.Getenv("DMS_ENABLE_GTK_REFRESH") != "1" {
		return
	}
	output, err := utils.GsettingsGet("org.gnome.desktop.interface", "color-scheme")
	if err != nil {
		return
	}
	current := strings.Trim(output, "'")

	var toggle string
	if current == "prefer-dark" {
		toggle = "default"
	} else {
		toggle = "prefer-dark"
	}

	expectColorSchemeEcho(toggle)
	if err := utils.GsettingsSet("org.gnome.desktop.interface", "color-scheme", toggle); err != nil {
		log.Warnf("Failed to toggle color-scheme for GTK refresh: %v", err)
		return
	}
	time.Sleep(50 * time.Millisecond)
	expectColorSchemeEcho(current)
	if err := utils.GsettingsSet("org.gnome.desktop.interface", "color-scheme", current); err != nil {
		log.Warnf("Failed to restore color-scheme for GTK refresh: %v", err)
	}
}

func refreshQt6ct() {
	confPath := filepath.Join(utils.XDGConfigHome(), "qt6ct", "qt6ct.conf")
	now := time.Now()
	if err := os.Chtimes(confPath, now, now); err != nil {
		log.Warnf("Failed to touch qt6ct.conf: %v", err)
	}
}

func refreshFcitx5() {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		log.Debugf("Failed to connect to session bus for Fcitx5 refresh: %v", err)
		return
	}
	defer conn.Close()

	obj := conn.Object("org.fcitx.Fcitx5", dbus.ObjectPath("/controller"))
	if err := obj.Call("org.fcitx.Fcitx.Controller1.ReloadAddonConfig", dbus.FlagNoAutoStart, "classicui").Err; err != nil {
		log.Debugf("Failed to refresh Fcitx5 theme: %v", err)
	}
}

func signalTerminals(opts *Options) {
	if !opts.ShouldSkipTemplate("kitty") && appExists(opts.AppChecker, []string{"kitty"}, nil) {
		signalByName("kitty", syscall.SIGUSR1)
		signalByName(".kitty-wrapped", syscall.SIGUSR1)
	}
	if !opts.ShouldSkipTemplate("ghostty") && appExists(opts.AppChecker, []string{"ghostty"}, nil) {
		signalByName("ghostty", syscall.SIGUSR2)
		signalByName(".ghostty-wrappe", syscall.SIGUSR2)
	}
}

func syncColorScheme(mode ColorMode) {
	scheme := "prefer-dark"
	if mode == ColorModeLight {
		scheme = "default"
	}

	if cur, err := utils.GsettingsGet("org.gnome.desktop.interface", "color-scheme"); err == nil {
		cur = strings.Trim(cur, "'")
		if cur == scheme || (mode == ColorModeLight && cur == "prefer-light") {
			return
		}
	}

	if err := utils.GsettingsSet("org.gnome.desktop.interface", "color-scheme", scheme); err != nil {
		log.Warnf("Failed to sync color-scheme: %v", err)
	}
}

var adwaitaAccents = []struct {
	name   string
	colors []colorful.Color
}{
	{"blue", hexColors("#3f8ae5", "#438de6", "#a4caee")},
	{"green", hexColors("#26a269", "#39ac76", "#81d5ad")},
	{"orange", hexColors("#f17738", "#ff7800", "#ffc994")},
	{"pink", hexColors("#e4358a", "#e64392", "#f9b3d5")},
	{"purple", hexColors("#954ab5", "#9c46b9", "#d099d6")},
	{"red", hexColors("#e84053", "#e01b24", "#f2a1a5")},
	{"slate", hexColors("#557b9f", "#6a8daf", "#b4c6d6")},
	{"teal", hexColors("#129eb0", "#2190a4", "#7bdff4")},
	{"yellow", hexColors("#cbac10", "#d4b411", "#f5c211")},
}

func hexColors(hexes ...string) []colorful.Color {
	out := make([]colorful.Color, len(hexes))
	for i, h := range hexes {
		out[i], _ = colorful.Hex(h)
	}
	return out
}

func closestAdwaitaAccent(primaryHex string) string {
	c, err := colorful.Hex(primaryHex)
	if err != nil {
		return "blue"
	}

	best := "blue"
	bestDist := math.MaxFloat64
	for _, a := range adwaitaAccents {
		for _, ref := range a.colors {
			d := c.DistanceCIEDE2000(ref)
			if d < bestDist {
				bestDist = d
				best = a.name
			}
		}
	}
	return best
}

func syncAccentColor(primaryHex string) {
	accent := closestAdwaitaAccent(primaryHex)
	if cur, err := utils.GsettingsGet("org.gnome.desktop.interface", "accent-color"); err == nil && strings.Trim(cur, "'") == accent {
		return
	}
	log.Infof("Setting GNOME accent color: %s", accent)
	if err := utils.GsettingsSet("org.gnome.desktop.interface", "accent-color", accent); err != nil {
		log.Warnf("Failed to set accent-color: %v", err)
	}
}

type TemplateCheck struct {
	ID       string `json:"id"`
	Detected bool   `json:"detected"`
}

func CheckTemplates(checker utils.AppChecker) []TemplateCheck {
	if checker == nil {
		checker = utils.DefaultAppChecker{}
	}

	homeDir, _ := os.UserHomeDir()
	checks := make([]TemplateCheck, 0, len(templateRegistry)+1)

	for _, tmpl := range templateRegistry {
		detected := false

		switch {
		case tmpl.RunUnconditionally:
			detected = true
		case tmpl.Kind == TemplateKindVSCode:
			detected = checkVSCodeExtension(homeDir)
		case tmpl.Kind == TemplateKindEmacs:
			detected = appExists(checker, tmpl.Commands, tmpl.Flatpaks) && utils.EmacsConfigDir() != ""
		default:
			detected = (appExists(checker, tmpl.Commands, tmpl.Flatpaks) || configDirExists(tmpl.ConfigDirs)) && templateSessionActive(tmpl)
		}

		checks = append(checks, TemplateCheck{ID: tmpl.ID, Detected: detected})
	}

	// qtengine is not a matugen template and ships no binary, so it has no
	// templateRegistry entry to detect; the settings row still needs an honest
	// indicator, which is the platform theme env var.
	checks = append(checks, TemplateCheck{ID: "qtengine", Detected: QtengineActive()})

	return checks
}

func checkVSCodeExtension(homeDir string) bool {
	for _, editor := range vscodeEditors {
		pattern := filepath.Join(editor.extensionsDir(homeDir), "danklinux.dms-theme-*")
		if matches, err := filepath.Glob(pattern); err == nil && len(matches) > 0 {
			return true
		}
	}
	return false
}
