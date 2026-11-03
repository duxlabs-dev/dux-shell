package matugen

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

// Options.IconTheme defaults to this UI label rather than a real icon theme name.
const qtenginePlaceholderIconTheme = "System Default"

// QtengineActive reports whether qtengine is the selected Qt platform theme. Qt
// never auto-loads a platform theme plugin, so the env var is necessary for it
// to be in use. Mirrors the QML guard in ThemeColorsTab.qml.
func QtengineActive() bool {
	return os.Getenv("QT_QPA_PLATFORMTHEME") == "qtengine" ||
		os.Getenv("QT_QPA_PLATFORMTHEME_QT6") == "qtengine"
}

// QtengineConfigPath returns the config qtengine serves both Qt5 and Qt6 from.
func QtengineConfigPath() string {
	return qtengineConfigPath("")
}

// QtengineColorSchemePath returns the KColorScheme file DMS points qtengine at.
func QtengineColorSchemePath() string {
	return filepath.Join(utils.XDGDataHome(), "color-schemes", "DankMatugen.colors")
}

// SyncQtengineConfig merges the DMS colour scheme path and icon theme into
// qtengine's config, preserving every other key, and writes it atomically. The
// write's mtime bump is what trips qtengine's watcher and repaints running apps.
// Map round trip rather than a typed struct so keys from qtengine versions we
// have not seen survive.
func SyncQtengineConfig(iconTheme string) error {
	return SyncQtengineConfigAt("", iconTheme)
}

// SyncQtengineConfigAt behaves like SyncQtengineConfig but writes below the
// explicitly supplied config directory. An empty directory follows
// XDG_CONFIG_HOME, preserving the standalone CLI's default behaviour.
func SyncQtengineConfigAt(configDir, iconTheme string) error {
	path := qtengineConfigPath(configDir)

	// Empty file and JSON null are both "not set" to qtengine; a top-level null
	// unmarshals to a nil map, which would panic on write.
	cfg := map[string]any{}
	data, err := os.ReadFile(path)
	switch {
	case err == nil:
		if len(bytes.TrimSpace(data)) > 0 {
			if err := json.Unmarshal(data, &cfg); err != nil {
				return fmt.Errorf("refusing to overwrite unparseable %s: %w", path, err)
			}
		}
	case !os.IsNotExist(err):
		return fmt.Errorf("failed to read %s: %w", path, err)
	}
	if cfg == nil {
		cfg = map[string]any{}
	}

	theme := map[string]any{}
	if existing := cfg["theme"]; existing != nil {
		obj, isObject := existing.(map[string]any)
		if !isObject {
			return fmt.Errorf("refusing to overwrite %s: %q is %T, not an object", path, "theme", existing)
		}
		theme = obj
	}

	// Only written if the file exists: qtengine resolves a missing path to an
	// empty config and resets the palette to its built-in default.
	scheme := QtengineColorSchemePath()
	if _, err := os.Stat(scheme); err == nil {
		theme["colorScheme"] = scheme
	}
	if iconTheme != "" && iconTheme != qtenginePlaceholderIconTheme {
		theme["iconTheme"] = iconTheme
	}
	cfg["theme"] = theme

	out, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to encode %s: %w", path, err)
	}
	out = append(out, '\n')

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("failed to create %s: %w", dir, err)
	}

	// Same directory so the rename is atomic; an in-place truncate risks a torn
	// read by qtengine's watcher.
	tmp, err := os.CreateTemp(dir, "config-*.json.tmp")
	if err != nil {
		return fmt.Errorf("failed to create temp config in %s: %w", dir, err)
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)

	if _, err := tmp.Write(out); err != nil {
		tmp.Close()
		return fmt.Errorf("failed to write %s: %w", tmpPath, err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("failed to close %s: %w", tmpPath, err)
	}
	if err := os.Chmod(tmpPath, 0o644); err != nil {
		return fmt.Errorf("failed to set mode on %s: %w", tmpPath, err)
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return fmt.Errorf("failed to replace %s: %w", path, err)
	}

	return nil
}

func qtengineConfigPath(configDir string) string {
	if configDir == "" {
		configDir = utils.XDGConfigHome()
	}
	return filepath.Join(configDir, "qtengine", "config.json")
}
