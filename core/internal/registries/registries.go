package registries

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/clipolicy"
	"github.com/spf13/afero"
)

const (
	OfficialName = "official"
	officialURL  = "https://github.com/duxlabs-dev/dux-plugin-registry.git"
)

// Source identifies a registry repository. Name doubles as the per-registry
// cache subdirectory, so it is restricted to a filesystem-safe slug.
type Source struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

func (s Source) Official() bool {
	return s.Name == OfficialName
}

var nameRe = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,31}$`)

func configPath() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("failed to get user config dir: %w", err)
	}
	return filepath.Join(configDir, "dms", "registries.json"), nil
}

// Load returns the official registry followed by any user-configured extras.
// A missing or unreadable config yields just the official registry.
func Load(fs afero.Fs) []Source {
	sources := []Source{{Name: OfficialName, URL: officialURL}}

	path, err := configPath()
	if err != nil {
		return sources
	}
	data, err := afero.ReadFile(fs, path)
	if err != nil {
		return sources
	}
	var extras []Source
	if err := json.Unmarshal(data, &extras); err != nil {
		return sources
	}
	for _, s := range extras {
		if !nameRe.MatchString(s.Name) || s.Name == OfficialName || s.URL == "" {
			continue
		}
		sources = append(sources, s)
	}
	return sources
}

// Active returns the registries to fetch from: none when the CLI policy
// disables them, otherwise Load.
func Active(fs afero.Fs) ([]Source, error) {
	disabled, err := clipolicy.RegistriesDisabled(fs)
	if err != nil {
		return nil, err
	}
	if disabled {
		return nil, nil
	}
	return Load(fs), nil
}

func saveExtras(fs afero.Fs, extras []Source) error {
	path, err := configPath()
	if err != nil {
		return err
	}
	if err := fs.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("failed to create config dir: %w", err)
	}
	data, err := json.MarshalIndent(extras, "", "  ")
	if err != nil {
		return err
	}
	return afero.WriteFile(fs, path, append(data, '\n'), 0o644)
}

func loadExtras(fs afero.Fs) []Source {
	sources := Load(fs)
	return sources[1:]
}

func Add(fs afero.Fs, name, url string) error {
	name = strings.TrimSpace(name)
	url = strings.TrimSpace(url)

	if !nameRe.MatchString(name) {
		return fmt.Errorf("invalid registry name %q: use 1-32 lowercase letters, digits or hyphens", name)
	}
	if name == OfficialName {
		return fmt.Errorf("registry name %q is reserved", OfficialName)
	}
	if url == "" {
		return fmt.Errorf("registry URL is required")
	}

	extras := loadExtras(fs)
	for _, s := range extras {
		if s.Name == name {
			return fmt.Errorf("registry %q already exists", name)
		}
		if s.URL == url {
			return fmt.Errorf("registry %q already uses this URL", s.Name)
		}
	}

	return saveExtras(fs, append(extras, Source{Name: name, URL: url}))
}

func Remove(fs afero.Fs, name string) error {
	if name == OfficialName {
		return fmt.Errorf("the official registry cannot be removed")
	}

	extras := loadExtras(fs)
	kept := make([]Source, 0, len(extras))
	for _, s := range extras {
		if s.Name != name {
			kept = append(kept, s)
		}
	}
	if len(kept) == len(extras) {
		return fmt.Errorf("registry %q not found", name)
	}

	return saveExtras(fs, kept)
}
