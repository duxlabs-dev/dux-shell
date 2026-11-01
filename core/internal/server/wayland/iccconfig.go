package wayland

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/screenshot"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type iccConfig struct {
	ICCProfiles      map[string]string `json:"iccProfiles,omitempty"`
	OutputTemps      map[string]int    `json:"outputTemps,omitempty"`
	OutputBrightness map[string]int    `json:"outputBrightness,omitempty"`
}

func dmsConfigDir() string {
	return filepath.Join(utils.XDGConfigHome(), "dms")
}

func iccConfigPath() string {
	return filepath.Join(dmsConfigDir(), "icc.json")
}

func ICCProfilesDir() string {
	return filepath.Join(dmsConfigDir(), "icc")
}

func resolveICCProfile(name string) string {
	if filepath.IsAbs(name) {
		return name
	}
	return filepath.Join(ICCProfilesDir(), name)
}

// Only the ICC fields persist, the shell pushes the night light state.
func LoadConfig() Config {
	migrateLegacyICCConfig()

	cfg := DefaultConfig()
	data, err := os.ReadFile(iccConfigPath())
	if err != nil {
		return cfg
	}
	var stored iccConfig
	if err := json.Unmarshal(data, &stored); err != nil {
		log.Warnf("icc: ignoring %s: %v", iccConfigPath(), err)
		return cfg
	}
	cfg.ICCProfiles = stored.ICCProfiles
	cfg.OutputTemps = stored.OutputTemps
	cfg.OutputBrightness = stored.OutputBrightness
	return cfg
}

func SaveICCConfig(cfg Config) error {
	path := iccConfigPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(iccConfig{ICCProfiles: cfg.ICCProfiles, OutputTemps: cfg.OutputTemps, OutputBrightness: cfg.OutputBrightness}, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}

func stageICCProfile(dir, src string) (string, error) {
	if filepath.Dir(filepath.Clean(src)) == filepath.Clean(dir) {
		return filepath.Base(src), nil
	}
	data, err := os.ReadFile(src)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}

	base := filepath.Base(src)
	ext := filepath.Ext(base)
	stem := strings.TrimSuffix(base, ext)
	for n := 0; ; n++ {
		name := base
		if n > 0 {
			name = fmt.Sprintf("%s-%d%s", stem, n, ext)
		}
		dest := filepath.Join(dir, name)
		existing, err := os.ReadFile(dest)
		switch {
		case errors.Is(err, fs.ErrNotExist):
			if err := os.WriteFile(dest, data, 0o644); err != nil {
				return "", err
			}
			return name, nil
		case err != nil:
			return "", err
		case bytes.Equal(existing, data):
			return name, nil
		}
	}
}

// !TODO: drop once master users have moved off <compositor>/dms/wayland.json
func migrateLegacyICCConfig() {
	if _, err := os.Stat(iccConfigPath()); !errors.Is(err, fs.ErrNotExist) {
		return
	}
	legacyDir := legacyICCDir()
	legacyPath := filepath.Join(legacyDir, "wayland.json")
	data, err := os.ReadFile(legacyPath)
	if err != nil {
		return
	}
	var cfg iccConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		log.Warnf("icc: cannot migrate %s: %v", legacyPath, err)
		return
	}

	profilesDir := ICCProfilesDir()
	legacyProfilesDir := filepath.Join(legacyDir, "icc")
	moved := make(map[string]string)
	entries, _ := os.ReadDir(legacyProfilesDir)
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		src := filepath.Join(legacyProfilesDir, entry.Name())
		name, err := stageICCProfile(profilesDir, src)
		if err != nil {
			log.Warnf("icc: cannot move %s: %v", src, err)
			continue
		}
		moved[src] = name
	}

	for output, path := range cfg.ICCProfiles {
		if name, ok := moved[filepath.Clean(path)]; ok {
			cfg.ICCProfiles[output] = name
			continue
		}
		name, err := stageICCProfile(profilesDir, path)
		if err != nil {
			log.Warnf("icc: keeping %s for %s: %v", path, output, err)
			continue
		}
		cfg.ICCProfiles[output] = name
	}

	if err := SaveICCConfig(Config{ICCProfiles: cfg.ICCProfiles, OutputTemps: cfg.OutputTemps}); err != nil {
		log.Warnf("icc: cannot migrate %s: %v", legacyPath, err)
		return
	}
	if err := os.Remove(legacyPath); err != nil {
		log.Warnf("icc: failed to remove %s: %v", legacyPath, err)
	}
	for src := range moved {
		if err := os.Remove(src); err != nil {
			log.Warnf("icc: failed to remove %s: %v", src, err)
		}
	}
	_ = os.Remove(legacyProfilesDir)
	log.Infof("icc: moved %s to %s", legacyPath, iccConfigPath())
}

func legacyICCDir() string {
	compositorDir := "niri"
	switch screenshot.DetectCompositor() {
	case screenshot.CompositorHyprland:
		compositorDir = "hypr"
	case screenshot.CompositorMango:
		compositorDir = "mango"
	}
	return filepath.Join(utils.XDGConfigHome(), compositorDir, "dms")
}
