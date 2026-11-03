package themes

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/duxlabs-dev/dux-shell/core/internal/gitssh"
	"github.com/duxlabs-dev/dux-shell/core/internal/registries"
	"github.com/go-git/go-git/v6"
	"github.com/spf13/afero"
)

type ColorScheme struct {
	Primary                 string `json:"primary,omitempty"`
	PrimaryText             string `json:"primaryText,omitempty"`
	PrimaryContainer        string `json:"primaryContainer,omitempty"`
	Secondary               string `json:"secondary,omitempty"`
	Surface                 string `json:"surface,omitempty"`
	SurfaceText             string `json:"surfaceText,omitempty"`
	SurfaceVariant          string `json:"surfaceVariant,omitempty"`
	SurfaceVariantText      string `json:"surfaceVariantText,omitempty"`
	SurfaceTint             string `json:"surfaceTint,omitempty"`
	Background              string `json:"background,omitempty"`
	BackgroundText          string `json:"backgroundText,omitempty"`
	Outline                 string `json:"outline,omitempty"`
	SurfaceContainer        string `json:"surfaceContainer,omitempty"`
	SurfaceContainerHigh    string `json:"surfaceContainerHigh,omitempty"`
	SurfaceContainerHighest string `json:"surfaceContainerHighest,omitempty"`
	Error                   string `json:"error,omitempty"`
	Warning                 string `json:"warning,omitempty"`
	Info                    string `json:"info,omitempty"`
}

type ThemeVariant struct {
	ID    string      `json:"id"`
	Name  string      `json:"name"`
	Dark  ColorScheme `json:"dark"`
	Light ColorScheme `json:"light"`
}

type ThemeFlavor struct {
	ID    string      `json:"id"`
	Name  string      `json:"name"`
	Dark  ColorScheme `json:"dark"`
	Light ColorScheme `json:"light"`
}

type ThemeAccent struct {
	ID           string                 `json:"id"`
	Name         string                 `json:"name"`
	FlavorColors map[string]ColorScheme `json:"-"`
}

func (a *ThemeAccent) UnmarshalJSON(data []byte) error {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	a.FlavorColors = make(map[string]ColorScheme)
	var mErr error
	for key, value := range raw {
		switch key {
		case "id":
			mErr = errors.Join(mErr, json.Unmarshal(value, &a.ID))
		case "name":
			mErr = errors.Join(mErr, json.Unmarshal(value, &a.Name))
		default:
			var colors ColorScheme
			if err := json.Unmarshal(value, &colors); err == nil {
				a.FlavorColors[key] = colors
			} else {
				mErr = errors.Join(mErr, fmt.Errorf("failed to unmarshal flavor colors for key %s: %w", key, err))
			}
		}
	}
	return mErr
}

func (a ThemeAccent) MarshalJSON() ([]byte, error) {
	m := map[string]any{
		"id":   a.ID,
		"name": a.Name,
	}
	for k, v := range a.FlavorColors {
		m[k] = v
	}
	return json.Marshal(m)
}

type MultiVariantDefaults struct {
	Dark  map[string]string `json:"dark,omitempty"`
	Light map[string]string `json:"light,omitempty"`
}

type ThemeVariants struct {
	Type     string                `json:"type,omitempty"`
	Default  string                `json:"default,omitempty"`
	Defaults *MultiVariantDefaults `json:"defaults,omitempty"`
	Options  []ThemeVariant        `json:"options,omitempty"`
	Flavors  []ThemeFlavor         `json:"flavors,omitempty"`
	Accents  []ThemeAccent         `json:"accents,omitempty"`
}

type ThemeWCAGGroup struct {
	Level     string   `json:"level"`
	MinRatio  float64  `json:"minRatio"`
	WorstPair []string `json:"worstPair,omitempty"`
}

type ThemeWCAGBreakdown struct {
	Name      string `json:"name"`
	Mode      string `json:"mode"`
	Level     string `json:"level"`
	BodyLevel string `json:"bodyLevel"`
}

type ThemeWCAGMode struct {
	Level     string               `json:"level"`
	MinRatio  float64              `json:"minRatio"`
	WorstPair []string             `json:"worstPair,omitempty"`
	Body      *ThemeWCAGGroup      `json:"body,omitempty"`
	Accent    *ThemeWCAGGroup      `json:"accent,omitempty"`
	NonText   *ThemeWCAGGroup      `json:"nonText,omitempty"`
	Variants  map[string]string    `json:"variants,omitempty"`
	Breakdown []ThemeWCAGBreakdown `json:"breakdown,omitempty"`
}

type ThemeWCAG struct {
	Level string         `json:"level"`
	Dark  *ThemeWCAGMode `json:"dark,omitempty"`
	Light *ThemeWCAGMode `json:"light,omitempty"`
}

type Theme struct {
	ID          string         `json:"id"`
	Name        string         `json:"name"`
	Version     string         `json:"version"`
	Author      string         `json:"author"`
	Description string         `json:"description"`
	Dark        ColorScheme    `json:"dark"`
	Light       ColorScheme    `json:"light"`
	Variants    *ThemeVariants `json:"variants,omitempty"`
	WCAG        *ThemeWCAG     `json:"wcag,omitempty"`
	PreviewPath string         `json:"-"`
	SourceDir   string         `json:"sourceDir,omitempty"`
}

type GitClient interface {
	PlainClone(path string, url string) error
	Pull(path string) error
	OriginURL(path string) (string, error)
}

type realGitClient struct{}

func (g *realGitClient) PlainClone(path string, url string) error {
	_, err := git.PlainClone(path, &git.CloneOptions{
		URL:           url,
		Progress:      os.Stdout,
		ClientOptions: gitssh.ClientOptions(),
	})
	return err
}

func (g *realGitClient) Pull(path string) error {
	repo, err := git.PlainOpen(path)
	if err != nil {
		return err
	}

	worktree, err := repo.Worktree()
	if err != nil {
		return err
	}

	err = worktree.Pull(&git.PullOptions{ClientOptions: gitssh.ClientOptions()})
	if err != nil && err.Error() != "already up-to-date" {
		return err
	}

	return nil
}

func (g *realGitClient) OriginURL(path string) (string, error) {
	repo, err := git.PlainOpen(path)
	if err != nil {
		return "", err
	}
	remote, err := repo.Remote("origin")
	if err != nil {
		return "", err
	}
	urls := remote.Config().URLs
	if len(urls) == 0 {
		return "", errors.New("origin remote has no URL")
	}
	return urls[0], nil
}

type Registry struct {
	fs         afero.Fs
	cacheDir   string
	registries []registries.Source
	themes     []Theme
	git        GitClient
}

func NewRegistry() (*Registry, error) {
	return NewRegistryWithFs(afero.NewOsFs())
}

func NewRegistryWithFs(fs afero.Fs) (*Registry, error) {
	sources, err := registries.Active(fs)
	if err != nil {
		return nil, err
	}
	return &Registry{
		fs:         fs,
		cacheDir:   getCacheDir(),
		registries: sources,
		git:        &realGitClient{},
	}, nil
}

func (r *Registry) cacheDirFor(src registries.Source) string {
	return filepath.Join(r.cacheDir, src.Name)
}

func getCacheDir() string {
	return filepath.Join(os.TempDir(), "dankdots-plugin-registry")
}

// A cached clone is reused only when its origin still matches the configured
// URL; renamed or re-pointed registries re-clone instead of pulling from the
// stale remote.
func (r *Registry) updateOne(src registries.Source) error {
	dir := r.cacheDirFor(src)
	exists, err := afero.DirExists(r.fs, dir)
	if err != nil {
		return fmt.Errorf("failed to check cache directory: %w", err)
	}

	if exists {
		origin, originErr := r.git.OriginURL(dir)
		if originErr == nil && origin == src.URL && r.git.Pull(dir) == nil {
			return nil
		}
		if err := r.fs.RemoveAll(dir); err != nil {
			return fmt.Errorf("failed to remove stale registry cache: %w", err)
		}
	}

	if err := r.fs.MkdirAll(filepath.Dir(dir), 0o755); err != nil {
		return fmt.Errorf("failed to create cache directory: %w", err)
	}
	if err := r.git.PlainClone(dir, src.URL); err != nil {
		return fmt.Errorf("failed to clone: %w", err)
	}
	return nil
}

// A registry without a themes/ directory is a valid plugins-only registry.
func (r *Registry) loadThemesFrom(dir string) ([]Theme, error) {
	themesDir := filepath.Join(dir, "themes")
	entries, err := afero.ReadDir(r.fs, themesDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to read themes directory: %w", err)
	}

	var themes []Theme
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		themeDir := filepath.Join(themesDir, entry.Name())
		themeFile := filepath.Join(themeDir, "theme.json")

		data, err := afero.ReadFile(r.fs, themeFile)
		if err != nil {
			continue
		}

		var theme Theme
		if err := json.Unmarshal(data, &theme); err != nil {
			continue
		}

		if theme.ID == "" {
			theme.ID = entry.Name()
		}
		theme.SourceDir = entry.Name()
		theme.WCAG = loadThemeWCAG(r.fs, themeDir)

		previewPath := filepath.Join(themeDir, "preview.svg")
		if exists, _ := afero.Exists(r.fs, previewPath); exists {
			theme.PreviewPath = previewPath
		}

		themes = append(themes, theme)
	}
	return themes, nil
}

// Pre-multi-registry caches were a single clone at the base dir; the per-name
// layout nests under it, so a leftover clone is deleted wholesale first.
func (r *Registry) resetLegacyCache() {
	if exists, _ := afero.DirExists(r.fs, filepath.Join(r.cacheDir, ".git")); exists {
		_ = r.fs.RemoveAll(r.cacheDir)
	}
}

// Update refreshes every configured registry, aggregating themes in
// declaration order (first occurrence of an ID wins). A failing registry is
// reported in the joined error but does not block the others.
func (r *Registry) Update() error {
	unlock, err := registries.LockCache()
	if err != nil {
		return err
	}
	defer unlock()

	r.resetLegacyCache()
	r.themes = []Theme{}
	seen := make(map[string]struct{})
	var errs []error
	for _, src := range r.registries {
		if err := r.updateOne(src); err != nil {
			errs = append(errs, fmt.Errorf("registry %s: %w", src.Name, err))
			continue
		}
		themes, err := r.loadThemesFrom(r.cacheDirFor(src))
		if err != nil {
			errs = append(errs, fmt.Errorf("registry %s: %w", src.Name, err))
			continue
		}
		for _, t := range themes {
			if _, dup := seen[t.ID]; dup {
				continue
			}
			seen[t.ID] = struct{}{}
			r.themes = append(r.themes, t)
		}
	}
	return errors.Join(errs...)
}

func loadThemeWCAG(fs afero.Fs, themeDir string) *ThemeWCAG {
	data, err := afero.ReadFile(fs, filepath.Join(themeDir, "wcag.json"))
	if err != nil {
		return nil
	}

	var wcag ThemeWCAG
	if err := json.Unmarshal(data, &wcag); err != nil {
		return nil
	}

	return &wcag
}

func (r *Registry) List() ([]Theme, error) {
	if len(r.themes) == 0 {
		if err := r.Update(); err != nil && len(r.themes) == 0 {
			return nil, err
		}
	}

	return SortByFirstParty(r.themes), nil
}

func (r *Registry) Search(query string) ([]Theme, error) {
	allThemes, err := r.List()
	if err != nil {
		return nil, err
	}

	if query == "" {
		return allThemes, nil
	}

	return SortByFirstParty(FuzzySearch(query, allThemes)), nil
}

func (r *Registry) Get(idOrName string) (*Theme, error) {
	themes, err := r.List()
	if err != nil {
		return nil, err
	}

	for _, t := range themes {
		if t.ID == idOrName {
			return &t, nil
		}
	}

	for _, t := range themes {
		if t.Name == idOrName {
			return &t, nil
		}
	}

	return nil, fmt.Errorf("theme not found: %s", idOrName)
}

func (r *Registry) GetThemeSourcePath(themeID string) string {
	// Themes may live under any registry's subdir. Search them all; first hit wins.
	for _, cfg := range r.registries {
		candidate := filepath.Join(r.cacheDirFor(cfg), "themes", themeID, "theme.json")
		if exists, _ := afero.Exists(r.fs, candidate); exists {
			return candidate
		}
	}
	if len(r.registries) == 0 {
		return ""
	}
	// Fallback to first registry (legacy path semantics).
	return filepath.Join(r.cacheDirFor(r.registries[0]), "themes", themeID, "theme.json")
}

func (r *Registry) GetThemeDir(themeID string) string {
	for _, cfg := range r.registries {
		candidate := filepath.Join(r.cacheDirFor(cfg), "themes", themeID)
		if exists, _ := afero.DirExists(r.fs, candidate); exists {
			return candidate
		}
	}
	if len(r.registries) == 0 {
		return ""
	}
	return filepath.Join(r.cacheDirFor(r.registries[0]), "themes", themeID)
}

func SortByFirstParty(themes []Theme) []Theme {
	return themes
}
