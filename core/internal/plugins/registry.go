package plugins

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/gitssh"
	"github.com/duxlabs-dev/dux-shell/core/internal/registries"
	"github.com/go-git/go-git/v6"
	"github.com/go-git/go-git/v6/plumbing"
	"github.com/spf13/afero"
)

type Plugin struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Capabilities []string `json:"capabilities"`
	Category     string   `json:"category"`
	Repo         string   `json:"repo"`
	Path         string   `json:"path,omitempty"`
	Author       string   `json:"author"`
	Description  string   `json:"description"`
	Dependencies []string `json:"dependencies,omitempty"`
	Compositors  []string `json:"compositors"`
	Distro       []string `json:"distro"`
	Screenshot   string   `json:"screenshot,omitempty"`
	RequiresDMS  string   `json:"requires_dms,omitempty"`
	Featured     bool     `json:"featured,omitempty"`
}

type GitClient interface {
	PlainClone(path string, url string) error
	Pull(path string) error
	OriginURL(path string) (string, error)
	HasUpdates(path string) (hasUpdates bool, localHash string, remoteHash string, err error)
	CurrentRevision(path string) (string, error)
	CheckoutRevision(path string, revision string) error
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
	if err != nil && !errors.Is(err, git.NoErrAlreadyUpToDate) {
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

func (g *realGitClient) HasUpdates(path string) (bool, string, string, error) {
	repo, err := git.PlainOpen(path)
	if err != nil {
		return false, "", "", err
	}

	head, err := repo.Head()
	if err != nil {
		return false, "", "", err
	}

	remote, err := repo.Remote("origin")
	if err != nil {
		return false, "", "", err
	}

	refs, err := remote.List(&git.ListOptions{ClientOptions: gitssh.ClientOptions()})
	if err != nil {
		return false, "", "", err
	}

	var remoteHead string
	for _, ref := range refs {
		if ref.Name().IsBranch() {
			if ref.Name().Short() == "main" || ref.Name().Short() == "master" {
				remoteHead = ref.Hash().String()
				break
			}
		}
	}

	localHash := head.Hash()
	if remoteHead == "" {
		return false, localHash.String(), "", nil
	}
	if localHash.String() == remoteHead {
		return false, localHash.String(), remoteHead, nil
	}

	remoteCommit, err := repo.CommitObject(plumbing.NewHash(remoteHead))
	if errors.Is(err, plumbing.ErrObjectNotFound) {
		return true, localHash.String(), remoteHead, nil
	}
	if err != nil {
		return false, "", "", err
	}
	headCommit, err := repo.CommitObject(localHash)
	if err != nil {
		return false, "", "", err
	}
	contained, err := remoteCommit.IsAncestor(headCommit)
	if err != nil {
		return false, "", "", err
	}
	return !contained, localHash.String(), remoteHead, nil
}

func (g *realGitClient) CurrentRevision(path string) (string, error) {
	repo, err := git.PlainOpen(path)
	if err != nil {
		return "", err
	}
	head, err := repo.Head()
	if err != nil {
		return "", err
	}
	return head.Hash().String(), nil
}

func (g *realGitClient) CheckoutRevision(path string, revision string) error {
	if !gitCommitPattern.MatchString(revision) {
		return fmt.Errorf("invalid git revision %q", revision)
	}

	repo, err := git.PlainOpen(path)
	if err != nil {
		return err
	}
	hash := plumbing.NewHash(revision)
	if _, objectErr := repo.CommitObject(hash); objectErr != nil {
		if _, remoteErr := repo.Remote("origin"); remoteErr != nil {
			return fmt.Errorf("revision %s is not available in repository: %w", revision, objectErr)
		}
		fetchErr := repo.Fetch(&git.FetchOptions{ClientOptions: gitssh.ClientOptions()})
		if fetchErr != nil && fetchErr != git.NoErrAlreadyUpToDate {
			return fmt.Errorf("failed to fetch locked revision: %w", fetchErr)
		}
	}
	if _, err := repo.CommitObject(hash); err != nil {
		return fmt.Errorf("revision %s is not available in repository: %w", revision, err)
	}
	worktree, err := repo.Worktree()
	if err != nil {
		return err
	}
	return worktree.Reset(&git.ResetOptions{Commit: hash, Mode: git.HardReset})
}

type Registry struct {
	fs         afero.Fs
	cacheDir   string
	registries []registries.Source
	plugins    []Plugin
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

// A registry without a plugins/ directory is a valid themes-only registry.
func (r *Registry) loadPluginsFrom(dir string) ([]Plugin, error) {
	pluginsDir := filepath.Join(dir, "plugins")
	entries, err := afero.ReadDir(r.fs, pluginsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to read plugins directory: %w", err)
	}

	var plugins []Plugin
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}

		data, err := afero.ReadFile(r.fs, filepath.Join(pluginsDir, entry.Name()))
		if err != nil {
			continue
		}

		var plugin Plugin
		if err := json.Unmarshal(data, &plugin); err != nil {
			continue
		}

		if plugin.ID == "" {
			plugin.ID = strings.TrimSuffix(entry.Name(), ".json")
		}

		plugins = append(plugins, plugin)
	}
	return plugins, nil
}

// Pre-multi-registry caches were a single clone at the base dir; the per-name
// layout nests under it, so a leftover clone is deleted wholesale first.
func (r *Registry) resetLegacyCache() {
	if exists, _ := afero.DirExists(r.fs, filepath.Join(r.cacheDir, ".git")); exists {
		_ = r.fs.RemoveAll(r.cacheDir)
	}
}

// Update refreshes every configured registry, aggregating plugins in
// declaration order (first occurrence of an ID wins). A failing registry is
// reported in the joined error but does not block the others.
func (r *Registry) Update() error {
	unlock, err := registries.LockCache()
	if err != nil {
		return err
	}
	defer unlock()

	r.resetLegacyCache()
	r.plugins = []Plugin{}
	seen := make(map[string]struct{})
	var errs []error
	for _, src := range r.registries {
		if err := r.updateOne(src); err != nil {
			errs = append(errs, fmt.Errorf("registry %s: %w", src.Name, err))
			continue
		}
		plugins, err := r.loadPluginsFrom(r.cacheDirFor(src))
		if err != nil {
			errs = append(errs, fmt.Errorf("registry %s: %w", src.Name, err))
			continue
		}
		for _, p := range plugins {
			if _, dup := seen[p.ID]; dup {
				continue
			}
			seen[p.ID] = struct{}{}
			r.plugins = append(r.plugins, p)
		}
	}
	return errors.Join(errs...)
}

func (r *Registry) List() ([]Plugin, error) {
	if len(r.plugins) == 0 {
		if err := r.Update(); err != nil && len(r.plugins) == 0 {
			return nil, err
		}
	}

	return SortByFirstParty(r.plugins), nil
}

func (r *Registry) Search(query string) ([]Plugin, error) {
	allPlugins, err := r.List()
	if err != nil {
		return nil, err
	}

	if query == "" {
		return allPlugins, nil
	}

	return SortByFirstParty(FuzzySearch(query, allPlugins)), nil
}

func (r *Registry) Get(idOrName string) (*Plugin, error) {
	plugins, err := r.List()
	if err != nil {
		return nil, err
	}

	// First, try to find by ID (preferred method)
	for _, p := range plugins {
		if p.ID == idOrName {
			return &p, nil
		}
	}

	// Fallback to name for backward compatibility
	for _, p := range plugins {
		if p.Name == idOrName {
			return &p, nil
		}
	}

	return nil, fmt.Errorf("plugin not found: %s", idOrName)
}
