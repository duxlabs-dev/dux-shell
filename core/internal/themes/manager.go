package themes

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/version"
	"github.com/spf13/afero"
)

type Manager struct {
	fs        afero.Fs
	themesDir string
}

func NewManager() (*Manager, error) {
	return NewManagerWithFs(afero.NewOsFs())
}

func NewManagerWithFs(fs afero.Fs) (*Manager, error) {
	themesDir := getThemesDir()
	return &Manager{
		fs:        fs,
		themesDir: themesDir,
	}, nil
}

func getThemesDir() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		log.Error("failed to get user config dir", "err", err)
		return ""
	}
	return filepath.Join(configDir, "dms", "themes")
}

func (m *Manager) IsInstalled(theme Theme) (bool, error) {
	path := m.getInstalledPath(theme.ID)
	exists, err := afero.Exists(m.fs, path)
	if err != nil {
		return false, err
	}
	return exists, nil
}

func (m *Manager) getInstalledDir(themeID string) string {
	return filepath.Join(m.themesDir, themeID)
}

func (m *Manager) getInstalledPath(themeID string) string {
	return filepath.Join(m.getInstalledDir(themeID), "theme.json")
}

func (m *Manager) Install(theme Theme, registryThemeDir string) error {
	themeDir := m.getInstalledDir(theme.ID)

	exists, err := afero.DirExists(m.fs, themeDir)
	if err != nil {
		return fmt.Errorf("failed to check if theme exists: %w", err)
	}

	if exists {
		return fmt.Errorf("theme already installed: %s", theme.Name)
	}

	if err := m.fs.MkdirAll(themeDir, 0o755); err != nil {
		return fmt.Errorf("failed to create theme directory: %w", err)
	}

	data, err := json.MarshalIndent(theme, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal theme: %w", err)
	}

	themePath := filepath.Join(themeDir, "theme.json")
	if err := afero.WriteFile(m.fs, themePath, data, 0o644); err != nil {
		return fmt.Errorf("failed to write theme file: %w", err)
	}

	m.copyPreviewFiles(registryThemeDir, themeDir, theme)
	return nil
}

func (m *Manager) copyPreviewFiles(srcDir, dstDir string, theme Theme) {
	previews := []string{"preview-dark.svg", "preview-light.svg"}

	if theme.Variants != nil {
		for _, v := range theme.Variants.Options {
			previews = append(previews,
				fmt.Sprintf("preview-%s.svg", v.ID),
				fmt.Sprintf("preview-%s-dark.svg", v.ID),
				fmt.Sprintf("preview-%s-light.svg", v.ID),
			)
		}
	}

	for _, preview := range previews {
		srcPath := filepath.Join(srcDir, preview)
		if exists, _ := afero.Exists(m.fs, srcPath); !exists {
			continue
		}
		data, err := afero.ReadFile(m.fs, srcPath)
		if err != nil {
			continue
		}
		dstPath := filepath.Join(dstDir, preview)
		_ = afero.WriteFile(m.fs, dstPath, data, 0o644)
	}
}

func (m *Manager) InstallFromRegistry(registry *Registry, themeID string) error {
	theme, err := registry.Get(themeID)
	if err != nil {
		return err
	}

	registryThemeDir := registry.GetThemeDir(theme.SourceDir)
	return m.Install(*theme, registryThemeDir)
}

func (m *Manager) Update(theme Theme) error {
	themePath := m.getInstalledPath(theme.ID)

	exists, err := afero.Exists(m.fs, themePath)
	if err != nil {
		return fmt.Errorf("failed to check if theme exists: %w", err)
	}

	if !exists {
		return fmt.Errorf("theme not installed: %s", theme.Name)
	}

	data, err := json.MarshalIndent(theme, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal theme: %w", err)
	}

	if err := afero.WriteFile(m.fs, themePath, data, 0o644); err != nil {
		return fmt.Errorf("failed to write theme file: %w", err)
	}

	return nil
}

func (m *Manager) Uninstall(theme Theme) error {
	return m.UninstallByID(theme.ID)
}

func (m *Manager) UninstallByID(themeID string) error {
	themeDir := m.getInstalledDir(themeID)

	exists, err := afero.DirExists(m.fs, themeDir)
	if err != nil {
		return fmt.Errorf("failed to check if theme exists: %w", err)
	}

	if !exists {
		return fmt.Errorf("theme not installed: %s", themeID)
	}

	if err := m.fs.RemoveAll(themeDir); err != nil {
		return fmt.Errorf("failed to remove theme: %w", err)
	}

	return nil
}

func (m *Manager) ListInstalled() ([]string, error) {
	exists, err := afero.DirExists(m.fs, m.themesDir)
	if err != nil {
		return nil, err
	}

	if !exists {
		return []string{}, nil
	}

	entries, err := afero.ReadDir(m.fs, m.themesDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read themes directory: %w", err)
	}

	var installed []string
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		themeID := entry.Name()
		themePath := filepath.Join(m.themesDir, themeID, "theme.json")
		if exists, _ := afero.Exists(m.fs, themePath); exists {
			installed = append(installed, themeID)
		}
	}

	return installed, nil
}

func (m *Manager) GetInstalledTheme(themeID string) (*Theme, error) {
	themePath := m.getInstalledPath(themeID)

	data, err := afero.ReadFile(m.fs, themePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read theme file: %w", err)
	}

	var theme Theme
	if err := json.Unmarshal(data, &theme); err != nil {
		return nil, fmt.Errorf("failed to parse theme file: %w", err)
	}

	return &theme, nil
}

func (m *Manager) HasUpdates(themeID string, registryTheme Theme) (bool, error) {
	installed, err := m.GetInstalledTheme(themeID)
	if err != nil {
		return false, err
	}

	return version.CompareVersions(installed.Version, registryTheme.Version) < 0, nil
}

func (m *Manager) GetThemesDir() string {
	return m.themesDir
}
