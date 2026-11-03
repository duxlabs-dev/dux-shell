package plugins

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/spf13/afero"
)

type Manager struct {
	fs         afero.Fs
	pluginsDir string
	lockPath   string
	gitClient  GitClient
}

func NewManager() (*Manager, error) {
	return NewManagerWithFs(afero.NewOsFs())
}

func NewManagerWithFs(fs afero.Fs) (*Manager, error) {
	pluginsDir := getPluginsDir()
	return &Manager{
		fs:         fs,
		pluginsDir: pluginsDir,
		lockPath:   getPluginLockPath(),
		gitClient:  &realGitClient{},
	}, nil
}

func getPluginsDir() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		log.Error("failed to get user config dir", "err", err)
		return ""
	}
	path := filepath.Join(configDir, "dms", "plugins")
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		return resolved
	}
	if resolved, err := filepath.EvalSymlinks(filepath.Dir(path)); err == nil {
		return filepath.Join(resolved, "plugins")
	}
	return path
}

func getPluginLockPath() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		log.Error("failed to get user config dir", "err", err)
		return ""
	}
	return filepath.Join(configDir, "dms", "plugins.lock.json")
}

func (m *Manager) IsInstalled(plugin Plugin) (bool, error) {
	path, err := m.findInstalledPath(plugin.ID)
	if err != nil {
		return false, err
	}
	return path != "", nil
}

func (m *Manager) findInstalledPath(pluginID string) (string, error) {
	// Check user plugins directory
	path, err := m.findInDir(m.pluginsDir, pluginID)
	if err != nil {
		return "", err
	}
	if path != "" {
		return path, nil
	}

	// Check system plugins directory
	systemDir := "/etc/xdg/quickshell/dms-plugins"
	return m.findInDir(systemDir, pluginID)
}

// isSafePluginPathComponent rejects ids that aren't a single path component,
// so filepath.Join can't resolve (and later RemoveAll) outside the plugins dir
func isSafePluginPathComponent(s string) bool {
	if s == "" || s == "." || s == ".." {
		return false
	}
	return !strings.ContainsAny(s, "/\\")
}

func (m *Manager) findInDir(dir, pluginID string) (string, error) {
	if !isSafePluginPathComponent(pluginID) {
		return "", fmt.Errorf("invalid plugin id: %q", pluginID)
	}

	// First, check if folder with exact ID name exists
	exactPath := filepath.Join(dir, pluginID)
	if exists, _ := afero.DirExists(m.fs, exactPath); exists {
		return exactPath, nil
	}

	// Scan all folders and check plugin.json for matching ID
	exists, err := afero.DirExists(m.fs, dir)
	if err != nil || !exists {
		return "", nil
	}

	entries, err := afero.ReadDir(m.fs, dir)
	if err != nil {
		return "", nil
	}

	for _, entry := range entries {
		name := entry.Name()
		if name == ".repos" || strings.HasSuffix(name, ".meta") {
			continue
		}

		fullPath := filepath.Join(dir, name)
		isPlugin := entry.IsDir() || entry.Mode()&os.ModeSymlink != 0
		if !isPlugin {
			if info, err := m.fs.Stat(fullPath); err == nil && info.IsDir() {
				isPlugin = true
			}
		}

		if isPlugin && m.getPluginID(fullPath) == pluginID {
			return fullPath, nil
		}
	}

	return "", nil
}

func (m *Manager) Install(plugin Plugin) error {
	if !isSafePluginPathComponent(plugin.ID) {
		return fmt.Errorf("invalid plugin id: %q", plugin.ID)
	}

	pluginPath := filepath.Join(m.pluginsDir, plugin.ID)
	repoPath := pluginPath

	exists, err := afero.DirExists(m.fs, pluginPath)
	if err != nil {
		return fmt.Errorf("failed to check if plugin exists: %w", err)
	}

	if exists {
		return fmt.Errorf("plugin already installed: %s", plugin.Name)
	}
	if strings.TrimSpace(plugin.Repo) == "" {
		return fmt.Errorf("plugin repository is required")
	}
	if err := validatePluginRepo(plugin.Repo); err != nil {
		return err
	}
	if err := validatePluginRepoPath(plugin.Path); err != nil {
		return err
	}
	if _, err := m.ensureLockfile(); err != nil {
		return err
	}

	if err := m.fs.MkdirAll(m.pluginsDir, 0o755); err != nil {
		return fmt.Errorf("failed to create plugins directory: %w", err)
	}

	reposDir := filepath.Join(m.pluginsDir, ".repos")
	if err := m.fs.MkdirAll(reposDir, 0o755); err != nil {
		return fmt.Errorf("failed to create repos directory: %w", err)
	}

	if plugin.Path != "" {
		repoName := m.getRepoName(plugin.Repo)
		repoPath = filepath.Join(reposDir, repoName)

		repoExists, err := afero.DirExists(m.fs, repoPath)
		if err != nil {
			return fmt.Errorf("failed to check if repo exists: %w", err)
		}

		if !repoExists {
			if err := m.gitClient.PlainClone(repoPath, plugin.Repo); err != nil {
				m.fs.RemoveAll(repoPath) //nolint:errcheck
				return fmt.Errorf("failed to clone repository: %w", err)
			}
		} else {
			// Pull latest changes if repo already exists
			if err := m.gitClient.Pull(repoPath); err != nil {
				// If pull fails (e.g., corrupted shallow clone), delete and re-clone
				if err := m.fs.RemoveAll(repoPath); err != nil {
					return fmt.Errorf("failed to remove corrupted repository: %w", err)
				}

				if err := m.gitClient.PlainClone(repoPath, plugin.Repo); err != nil {
					return fmt.Errorf("failed to re-clone repository: %w", err)
				}
			}
		}

		sourcePath := filepath.Join(repoPath, plugin.Path)
		sourceExists, err := afero.DirExists(m.fs, sourcePath)
		if err != nil {
			return fmt.Errorf("failed to check plugin path: %w", err)
		}
		if !sourceExists {
			return fmt.Errorf("plugin path does not exist in repository: %s", plugin.Path)
		}

		if err := m.createSymlink(sourcePath, pluginPath); err != nil {
			return fmt.Errorf("failed to create symlink: %w", err)
		}
		metaPath := pluginPath + ".meta"
		metaContent := fmt.Sprintf("repo=%s\npath=%s\nrepodir=%s", plugin.Repo, plugin.Path, repoName)
		if err := afero.WriteFile(m.fs, metaPath, []byte(metaContent), 0o644); err != nil {
			m.fs.Remove(pluginPath) //nolint:errcheck
			return fmt.Errorf("failed to write plugin repository metadata: %w", err)
		}

	} else {
		if err := m.gitClient.PlainClone(pluginPath, plugin.Repo); err != nil {
			m.fs.RemoveAll(pluginPath) //nolint:errcheck
			return fmt.Errorf("failed to clone plugin: %w", err)
		}
	}

	if err := m.recordInstalledPlugin(plugin, repoPath); err != nil {
		if plugin.Path != "" {
			m.fs.Remove(pluginPath)           //nolint:errcheck
			m.fs.Remove(pluginPath + ".meta") //nolint:errcheck
		} else {
			m.fs.RemoveAll(pluginPath) //nolint:errcheck
		}
		return fmt.Errorf("failed to update plugin lockfile: %w", err)
	}

	return nil
}

func (m *Manager) getRepoName(repoURL string) string {
	hash := sha256.Sum256([]byte(repoURL))
	return hex.EncodeToString(hash[:])[:16]
}

func (m *Manager) createSymlink(source, dest string) error {
	if symlinkFs, ok := m.fs.(afero.Symlinker); ok {
		return symlinkFs.SymlinkIfPossible(source, dest)
	}
	return os.Symlink(source, dest)
}

func (m *Manager) Update(plugin Plugin) error {
	lock, err := m.ensureLockfile()
	if err != nil {
		return err
	}
	if locked, ok := lock.Plugins[plugin.ID]; ok {
		plugin.Repo = locked.Repo
		plugin.Path = locked.Path
	}

	pluginPath, err := m.findInstalledPath(plugin.ID)
	if err != nil {
		return fmt.Errorf("failed to find plugin: %w", err)
	}

	if pluginPath == "" {
		return fmt.Errorf("plugin not installed: %s", plugin.Name)
	}

	if strings.HasPrefix(pluginPath, "/etc/xdg/quickshell/dms-plugins") {
		return fmt.Errorf("cannot update system plugin: %s", plugin.Name)
	}
	if plugin.Repo == "" {
		plugin.Repo, err = m.gitClient.OriginURL(pluginPath)
		if err != nil {
			return fmt.Errorf("failed to read plugin origin: %w", err)
		}
	}

	repoPath := m.repositoryPath(plugin.ID, LockedPlugin{Repo: plugin.Repo, Path: plugin.Path})
	if err := m.gitClient.Pull(repoPath); err != nil {
		if err := m.fs.RemoveAll(repoPath); err != nil {
			return fmt.Errorf("failed to remove corrupted plugin repository: %w", err)
		}
		if err := m.gitClient.PlainClone(repoPath, plugin.Repo); err != nil {
			return fmt.Errorf("failed to re-clone plugin repository: %w", err)
		}
	}

	if err := m.recordInstalledPlugin(plugin, repoPath); err != nil {
		if locked, ok := lock.Plugins[plugin.ID]; ok {
			m.gitClient.CheckoutRevision(repoPath, locked.Commit) //nolint:errcheck
		}
		return err
	}
	return nil
}

func (m *Manager) Uninstall(plugin Plugin) error {
	lock, err := m.ensureLockfile()
	if err != nil {
		return err
	}
	if locked, ok := lock.Plugins[plugin.ID]; ok {
		plugin.Repo = locked.Repo
		plugin.Path = locked.Path
	}

	pluginPath, err := m.findInstalledPath(plugin.ID)
	if err != nil {
		return fmt.Errorf("failed to find plugin: %w", err)
	}

	if pluginPath == "" {
		return fmt.Errorf("plugin not installed: %s", plugin.Name)
	}

	if strings.HasPrefix(pluginPath, "/etc/xdg/quickshell/dms-plugins") {
		return fmt.Errorf("cannot uninstall system plugin: %s", plugin.Name)
	}
	updatedLock := lock.Clone()
	delete(updatedLock.Plugins, plugin.ID)
	if err := m.lockStore().Write(updatedLock); err != nil {
		return err
	}
	rollbackLock := func(err error) error {
		if rollbackErr := m.lockStore().Write(lock); rollbackErr != nil {
			return fmt.Errorf("%w (also failed to restore plugin lockfile: %v)", err, rollbackErr)
		}
		return err
	}

	metaPath := pluginPath + ".meta"
	if plugin.Path != "" {
		reposDir := filepath.Join(m.pluginsDir, ".repos")
		repoName := m.getRepoName(plugin.Repo)
		repoPath := filepath.Join(reposDir, repoName)

		shouldCleanup, err := m.shouldCleanupRepo(plugin.Repo, plugin.ID)
		if err != nil {
			return rollbackLock(fmt.Errorf("failed to check repo cleanup: %w", err))
		}

		if err := m.fs.Remove(pluginPath); err != nil {
			return rollbackLock(fmt.Errorf("failed to remove symlink: %w", err))
		}

		if metaExists, _ := afero.Exists(m.fs, metaPath); metaExists {
			if err := m.fs.Remove(metaPath); err != nil {
				return rollbackLock(fmt.Errorf("failed to remove metadata: %w", err))
			}
		}

		if shouldCleanup {
			if err := m.fs.RemoveAll(repoPath); err != nil {
				return rollbackLock(fmt.Errorf("failed to cleanup repository: %w", err))
			}
		}
	} else {
		if err := m.fs.RemoveAll(pluginPath); err != nil {
			return rollbackLock(fmt.Errorf("failed to remove plugin: %w", err))
		}
	}

	return nil
}

func (m *Manager) shouldCleanupRepo(repoURL, excludePlugin string) (bool, error) {
	lock, err := m.ensureLockfile()
	if err != nil {
		return false, err
	}
	for id, plugin := range lock.Plugins {
		if id == excludePlugin {
			continue
		}
		if plugin.Repo == repoURL && plugin.Path != "" {
			return false, nil
		}
	}

	return true, nil
}

func (m *Manager) ListInstalled() ([]string, error) {
	installedMap := make(map[string]bool)

	exists, err := afero.DirExists(m.fs, m.pluginsDir)
	if err != nil {
		return nil, err
	}

	if exists {
		entries, err := afero.ReadDir(m.fs, m.pluginsDir)
		if err != nil {
			return nil, fmt.Errorf("failed to read plugins directory: %w", err)
		}

		for _, entry := range entries {
			name := entry.Name()
			if name == ".repos" || strings.HasSuffix(name, ".meta") {
				continue
			}

			fullPath := filepath.Join(m.pluginsDir, name)
			isPlugin := false

			if entry.IsDir() {
				isPlugin = true
			} else if entry.Mode()&os.ModeSymlink != 0 {
				isPlugin = true
			} else {
				info, err := m.fs.Stat(fullPath)
				if err == nil && info.IsDir() {
					isPlugin = true
				}
			}

			if isPlugin {
				// Read plugin.json to get the actual plugin ID
				pluginID := m.getPluginID(fullPath)
				if pluginID != "" {
					installedMap[pluginID] = true
				}
			}
		}
	}

	systemPluginsDir := "/etc/xdg/quickshell/dms-plugins"
	systemExists, err := afero.DirExists(m.fs, systemPluginsDir)
	if err == nil && systemExists {
		entries, err := afero.ReadDir(m.fs, systemPluginsDir)
		if err == nil {
			for _, entry := range entries {
				if entry.IsDir() {
					fullPath := filepath.Join(systemPluginsDir, entry.Name())
					// Read plugin.json to get the actual plugin ID
					pluginID := m.getPluginID(fullPath)
					if pluginID != "" {
						installedMap[pluginID] = true
					}
				}
			}
		}
	}

	var installed []string
	for name := range installedMap {
		installed = append(installed, name)
	}

	return installed, nil
}

// getPluginID reads the plugin.json file and returns the plugin ID
func (m *Manager) getPluginID(pluginPath string) string {
	manifest := m.getPluginManifest(pluginPath)
	if manifest == nil {
		return ""
	}
	return manifest.ID
}

func (m *Manager) getPluginManifest(pluginPath string) *pluginManifest {
	manifestPath := filepath.Join(pluginPath, "plugin.json")
	data, err := afero.ReadFile(m.fs, manifestPath)
	if err != nil {
		return nil
	}

	var manifest pluginManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return nil
	}

	return &manifest
}

type pluginManifest struct {
	ID     string          `json:"id"`
	Name   string          `json:"name"`
	Lyrics *LyricsProvider `json:"lyrics"`
}

func (m *Manager) GetPluginsDir() string {
	return m.pluginsDir
}

func (m *Manager) UninstallByIDOrName(idOrName string) error {
	pluginPath, err := m.findInstalledPathByIDOrName(idOrName)
	if err != nil {
		return err
	}
	if pluginPath == "" {
		return fmt.Errorf("plugin not found: %s", idOrName)
	}

	if strings.HasPrefix(pluginPath, "/etc/xdg/quickshell/dms-plugins") {
		return fmt.Errorf("cannot uninstall system plugin: %s", idOrName)
	}
	manifest := m.getPluginManifest(pluginPath)
	if manifest != nil {
		lock, err := m.ensureLockfile()
		if err != nil {
			return err
		}
		if locked, ok := lock.Plugins[manifest.ID]; ok {
			return m.Uninstall(Plugin{ID: manifest.ID, Name: manifest.Name, Repo: locked.Repo, Path: locked.Path})
		}
	}

	metaPath := pluginPath + ".meta"
	metaExists, _ := afero.Exists(m.fs, metaPath)

	if metaExists {
		if err := m.fs.Remove(pluginPath); err != nil {
			return fmt.Errorf("failed to remove symlink: %w", err)
		}
		if err := m.fs.Remove(metaPath); err != nil {
			return fmt.Errorf("failed to remove metadata: %w", err)
		}
	} else {
		if err := m.fs.RemoveAll(pluginPath); err != nil {
			return fmt.Errorf("failed to remove plugin: %w", err)
		}
	}

	return nil
}

func (m *Manager) UpdateByIDOrName(idOrName string) error {
	pluginPath, err := m.findInstalledPathByIDOrName(idOrName)
	if err != nil {
		return err
	}
	if pluginPath == "" {
		return fmt.Errorf("plugin not found: %s", idOrName)
	}

	if strings.HasPrefix(pluginPath, "/etc/xdg/quickshell/dms-plugins") {
		return fmt.Errorf("cannot update system plugin: %s", idOrName)
	}
	manifest := m.getPluginManifest(pluginPath)
	if manifest != nil {
		lock, err := m.ensureLockfile()
		if err != nil {
			return err
		}
		if locked, ok := lock.Plugins[manifest.ID]; ok {
			return m.Update(Plugin{ID: manifest.ID, Name: manifest.Name, Repo: locked.Repo, Path: locked.Path})
		}
	}

	metaPath := pluginPath + ".meta"
	metaExists, _ := afero.Exists(m.fs, metaPath)

	if metaExists {
		// Plugin is from monorepo, but we don't know the repo URL without registry
		// Just try to pull from existing .git in the symlink target
		return fmt.Errorf("cannot update monorepo plugin without registry info: %s", idOrName)
	}

	// Standalone plugin - just pull
	if err := m.gitClient.Pull(pluginPath); err != nil {
		return fmt.Errorf("failed to update plugin: %w", err)
	}
	if manifest == nil {
		return nil
	}
	repo, err := m.gitClient.OriginURL(pluginPath)
	if err != nil {
		return fmt.Errorf("failed to read plugin origin: %w", err)
	}
	return m.recordInstalledPlugin(Plugin{ID: manifest.ID, Name: manifest.Name, Repo: repo}, pluginPath)
}

func (m *Manager) findInstalledPathByIDOrName(idOrName string) (string, error) {
	path, err := m.findInDirByIDOrName(m.pluginsDir, idOrName)
	if err != nil {
		return "", err
	}
	if path != "" {
		return path, nil
	}

	systemDir := "/etc/xdg/quickshell/dms-plugins"
	return m.findInDirByIDOrName(systemDir, idOrName)
}

func (m *Manager) findInDirByIDOrName(dir, idOrName string) (string, error) {
	if !isSafePluginPathComponent(idOrName) {
		return "", fmt.Errorf("invalid plugin id/name: %q", idOrName)
	}

	// Check exact folder name match first
	exactPath := filepath.Join(dir, idOrName)
	if exists, _ := afero.DirExists(m.fs, exactPath); exists {
		return exactPath, nil
	}

	exists, err := afero.DirExists(m.fs, dir)
	if err != nil || !exists {
		return "", nil
	}

	entries, err := afero.ReadDir(m.fs, dir)
	if err != nil {
		return "", nil
	}

	for _, entry := range entries {
		name := entry.Name()
		if name == ".repos" || strings.HasSuffix(name, ".meta") {
			continue
		}

		fullPath := filepath.Join(dir, name)
		isPlugin := entry.IsDir() || entry.Mode()&os.ModeSymlink != 0
		if !isPlugin {
			if info, err := m.fs.Stat(fullPath); err == nil && info.IsDir() {
				isPlugin = true
			}
		}

		if !isPlugin {
			continue
		}

		manifest := m.getPluginManifest(fullPath)
		if manifest == nil {
			continue
		}

		if manifest.ID == idOrName || manifest.Name == idOrName {
			return fullPath, nil
		}
	}

	return "", nil
}

func (m *Manager) HasUpdates(pluginID string, plugin Plugin) (hasUpdates bool, diffURL string, err error) {
	lock, err := m.ensureLockfile()
	if err != nil {
		return false, "", err
	}
	if locked, ok := lock.Plugins[pluginID]; ok {
		plugin.Repo = locked.Repo
		plugin.Path = locked.Path
	}

	pluginPath, err := m.findInstalledPath(pluginID)
	if err != nil {
		return false, "", fmt.Errorf("failed to find plugin: %w", err)
	}

	if pluginPath == "" {
		return false, "", fmt.Errorf("plugin not installed: %s", pluginID)
	}

	if strings.HasPrefix(pluginPath, "/etc/xdg/quickshell/dms-plugins") {
		return false, "", nil
	}

	repoPath := pluginPath
	if plugin.Path != "" {
		repoPath = m.repositoryPath(pluginID, LockedPlugin{Repo: plugin.Repo, Path: plugin.Path})
	}
	if resolved, err := filepath.EvalSymlinks(repoPath); err == nil {
		repoPath = resolved
	}
	hasUp, localHash, remoteHash, err := m.gitClient.HasUpdates(repoPath)

	if err != nil {
		return false, "", err
	}

	diffURL = plugin.Repo
	if diffURL != "" {
		diffURL = strings.TrimSuffix(diffURL, ".git")
		if hasUp && len(localHash) >= 7 && len(remoteHash) >= 7 {
			diffURL = fmt.Sprintf("%s/compare/%s...%s", diffURL, localHash[:7], remoteHash[:7])
		}
	}
	return hasUp, diffURL, nil
}
