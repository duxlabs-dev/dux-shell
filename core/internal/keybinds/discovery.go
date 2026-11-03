package keybinds

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type DiscoveryConfig struct {
	SearchPaths []string
}

func DefaultDiscoveryConfig() *DiscoveryConfig {
	var searchPaths []string

	configDir, err := os.UserConfigDir()
	if err == nil && configDir != "" {
		searchPaths = append(searchPaths, filepath.Join(configDir, "dms", "cheatsheets"))
	}

	configDirs := os.Getenv("XDG_CONFIG_DIRS")
	if configDirs != "" {
		for dir := range strings.SplitSeq(configDirs, ":") {
			if dir != "" {
				searchPaths = append(searchPaths, filepath.Join(dir, "dms", "cheatsheets"))
			}
		}
	}

	return &DiscoveryConfig{
		SearchPaths: searchPaths,
	}
}

func (d *DiscoveryConfig) FindJSONFiles() ([]string, error) {
	var files []string

	for _, searchPath := range d.SearchPaths {
		expandedPath, err := utils.ExpandPath(searchPath)
		if err != nil {
			continue
		}

		if _, err := os.Stat(expandedPath); os.IsNotExist(err) {
			continue
		}

		entries, err := os.ReadDir(expandedPath)
		if err != nil {
			continue
		}

		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}

			if !strings.HasSuffix(entry.Name(), ".json") {
				continue
			}

			fullPath := filepath.Join(expandedPath, entry.Name())
			files = append(files, fullPath)
		}
	}

	return files, nil
}

type JSONProviderFactory func(filePath string) (Provider, error)

var jsonProviderFactory JSONProviderFactory

func SetJSONProviderFactory(factory JSONProviderFactory) {
	jsonProviderFactory = factory
}

func AutoDiscoverProviders(registry *Registry, config *DiscoveryConfig) error {
	if config == nil {
		config = DefaultDiscoveryConfig()
	}

	if jsonProviderFactory == nil {
		return nil
	}

	files, err := config.FindJSONFiles()
	if err != nil {
		return fmt.Errorf("failed to discover JSON files: %w", err)
	}

	for _, file := range files {
		provider, err := jsonProviderFactory(file)
		if err != nil {
			continue
		}

		if err := registry.Register(provider); err != nil {
			continue
		}
	}

	return nil
}
