package matugen

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

// paletteEntry runs an external command that emits a JSON object of colors and
// merges it into matugen's render data under Namespace, so user templates can
// reference e.g. {{mypalette.color0}}. The palette logic stays entirely in the
// command; DMS only runs it and forwards the result.
type paletteEntry struct {
	Enabled bool   `json:"enabled"`
	Command string `json:"command"`
	// Args are passed verbatim; {image} and {mode} are substituted, and the same
	// values are exported as $DMS_WALLPAPER and $DMS_MODE.
	Args []string `json:"args"`
	// OutputFile is where the command writes its JSON (also exported as
	// $DMS_PALETTE_OUT); when empty DMS reads the command's stdout instead.
	// {image}/{mode} are substituted here too.
	OutputFile string `json:"output_file"`
	// Namespace is the palette's key in matugen's import data. When empty it
	// falls back to a positional name (palette1, palette2, ...).
	Namespace string `json:"namespace"`
}

// paletteInjectConfig accepts both a {"palettes": [...]} list and a bare single
// palette object, so a file written before multi-palette support still loads.
type paletteInjectConfig struct {
	Palettes []paletteEntry `json:"palettes"`
	paletteEntry
}

// paletteInjection is a resolved palette: its namespace and the compact JSON its
// command produced.
type paletteInjection struct {
	Namespace string
	JSON      string
}

// loadPaletteInjectConfig returns the enabled palettes, or nil when the config
// is absent. A bare single-object file is normalized into a one-element list.
func loadPaletteInjectConfig(configDir string) ([]paletteEntry, error) {
	if configDir == "" {
		return nil, nil
	}
	path := filepath.Join(configDir, "matugen", "palette-inject.json")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var cfg paletteInjectConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}

	entries := cfg.Palettes
	if len(entries) == 0 && cfg.Command != "" {
		entries = []paletteEntry{cfg.paletteEntry}
	}

	out := make([]paletteEntry, 0, len(entries))
	for i, e := range entries {
		if !e.Enabled || e.Command == "" {
			continue
		}
		if e.Namespace == "" {
			e.Namespace = fmt.Sprintf("palette%d", i+1)
		}
		out = append(out, e)
	}
	return out, nil
}

func substituteTokens(s, image, mode string) string {
	s = strings.ReplaceAll(s, "{image}", image)
	s = strings.ReplaceAll(s, "{mode}", mode)
	return s
}

// lookPathIn resolves command against the PATH in env rather than the process
// environment, so binaries in user bin dirs (e.g. ~/.local/bin) are found.
// exec.Command resolves cmd.Path from the current process PATH at construction
// time, so setting cmd.Env alone is not enough.
func lookPathIn(command string, env []string) (string, error) {
	isExecutable := func(p string) bool {
		info, err := os.Stat(p)
		return err == nil && !info.IsDir() && info.Mode()&0o111 != 0
	}
	if strings.ContainsRune(command, os.PathSeparator) {
		if isExecutable(command) {
			return command, nil
		}
		return "", fmt.Errorf("not executable: %s", command)
	}
	var pathVal string
	for _, e := range env {
		if strings.HasPrefix(e, "PATH=") {
			pathVal = strings.TrimPrefix(e, "PATH=")
		}
	}
	for _, dir := range filepath.SplitList(pathVal) {
		if dir == "" {
			continue
		}
		candidate := filepath.Join(dir, command)
		if isExecutable(candidate) {
			return candidate, nil
		}
	}
	return "", fmt.Errorf("%q not found in PATH", command)
}

// runPaletteEntry runs one palette command and returns its compact JSON, or ""
// on any failure: a bad command must never break a theme build.
func runPaletteEntry(e paletteEntry, imagePath string, mode ColorMode) string {
	env := append(utils.EnvWithUserBinPath(nil),
		"DMS_WALLPAPER="+imagePath,
		"DMS_MODE="+string(mode),
	)
	resolved, err := lookPathIn(e.Command, env)
	if err != nil {
		log.Warnf("palette-inject: command %q not found: %v", e.Command, err)
		return ""
	}

	modeStr := string(mode)
	outputFile := substituteTokens(e.OutputFile, imagePath, modeStr)

	args := make([]string, 0, len(e.Args))
	for _, a := range e.Args {
		args = append(args, substituteTokens(a, imagePath, modeStr))
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, resolved, args...)
	cmd.WaitDelay = time.Second
	cmd.Env = append(env, "DMS_PALETTE_OUT="+outputFile)

	var raw []byte
	if outputFile != "" {
		if out, err := cmd.CombinedOutput(); err != nil {
			log.Warnf("palette-inject: command failed: %v: %s", err, strings.TrimSpace(string(out)))
			return ""
		}
		raw, err = os.ReadFile(outputFile)
		if err != nil {
			log.Warnf("palette-inject: reading output_file %s: %v", outputFile, err)
			return ""
		}
	} else {
		out, err := cmd.Output()
		if err != nil {
			log.Warnf("palette-inject: command failed: %v", err)
			return ""
		}
		raw = out
	}

	// The command must emit a JSON object; values may be nested (e.g. pywal's
	// {"colors": {...}, "special": {...}}), which matugen resolves through the
	// import as {{name.colors.color0}}.
	var palette map[string]json.RawMessage
	if err := json.Unmarshal(raw, &palette); err != nil {
		log.Warnf("palette-inject: palette must be a JSON object: %v", err)
		return ""
	}
	if len(palette) == 0 {
		log.Warn("palette-inject: command produced an empty palette")
		return ""
	}
	compact, err := json.Marshal(palette)
	if err != nil {
		log.Warnf("palette-inject: re-marshal failed: %v", err)
		return ""
	}
	log.Infof("palette-inject: %s produced %d keys under %q", e.Command, len(palette), e.Namespace)
	return string(compact)
}

// InjectedPalettes runs every enabled palette command for imagePath and returns
// the resolved injections in config order, skipping any that fail. It returns
// nil when the feature is off. mode is "dark"/"light".
func InjectedPalettes(configDir, imagePath string, mode ColorMode) []paletteInjection {
	if imagePath == "" {
		return nil
	}
	entries, err := loadPaletteInjectConfig(configDir)
	if err != nil {
		log.Warnf("palette-inject: %v", err)
		return nil
	}

	injections := make([]paletteInjection, 0, len(entries))
	for _, e := range entries {
		if palJSON := runPaletteEntry(e, imagePath, mode); palJSON != "" {
			injections = append(injections, paletteInjection{Namespace: e.Namespace, JSON: palJSON})
		}
	}
	return injections
}
