package plugins

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/spf13/afero"
)

func (m *Manager) lockStore() *LockStore {
	lockPath := m.lockPath
	if lockPath == "" {
		lockPath = filepath.Join(filepath.Dir(m.pluginsDir), "plugins.lock.json")
	}
	return NewLockStore(m.fs, lockPath)
}

func (m *Manager) GetLockfilePath() string {
	return m.lockStore().Path()
}

func (m *Manager) EnsureLockfile() error {
	_, err := m.ensureLockfile()
	return err
}

func (m *Manager) ensureLockfile() (PluginLockfile, error) {
	store := m.lockStore()
	exists, err := store.Exists()
	if err != nil {
		return PluginLockfile{}, fmt.Errorf("failed to check plugin lockfile: %w", err)
	}
	if exists {
		return store.Load()
	}

	lock, _, err := m.SnapshotLockfile()
	if err != nil {
		return PluginLockfile{}, err
	}
	if err := store.Write(lock); err != nil {
		return PluginLockfile{}, err
	}
	return lock, nil
}

func (m *Manager) SnapshotLockfile() (PluginLockfile, []string, error) {
	lock := NewPluginLockfile()
	warnings := []string{}

	exists, err := afero.DirExists(m.fs, m.pluginsDir)
	if err != nil {
		return PluginLockfile{}, nil, fmt.Errorf("failed to check plugins directory: %w", err)
	}
	if !exists {
		return lock, warnings, nil
	}

	entries, err := afero.ReadDir(m.fs, m.pluginsDir)
	if err != nil {
		return PluginLockfile{}, nil, fmt.Errorf("failed to read plugins directory: %w", err)
	}

	for _, entry := range entries {
		name := entry.Name()
		if name == ".repos" || strings.HasSuffix(name, ".meta") {
			continue
		}

		pluginPath := filepath.Join(m.pluginsDir, name)
		manifest := m.getPluginManifest(pluginPath)
		if manifest == nil || manifest.ID == "" {
			continue
		}

		locked, repoPath, err := m.lockedPluginFromInstall(pluginPath)
		if err != nil {
			warnings = append(warnings, fmt.Sprintf("%s: %v", manifest.ID, err))
			continue
		}
		commit, err := m.gitClient.CurrentRevision(repoPath)
		if err != nil {
			warnings = append(warnings, fmt.Sprintf("%s: cannot read git revision: %v", manifest.ID, err))
			continue
		}
		locked.Commit = commit
		lock.SetRepositoryCommit(locked.Repo, commit)
		lock.Plugins[manifest.ID] = locked
	}

	if err := lock.Validate(); err != nil {
		return PluginLockfile{}, warnings, err
	}
	return lock, warnings, nil
}

func (m *Manager) lockedPluginFromInstall(pluginPath string) (LockedPlugin, string, error) {
	metaPath := pluginPath + ".meta"
	if metaExists, _ := afero.Exists(m.fs, metaPath); metaExists {
		data, err := afero.ReadFile(m.fs, metaPath)
		if err != nil {
			return LockedPlugin{}, "", fmt.Errorf("failed to read legacy metadata: %w", err)
		}
		metadata := parseLegacyPluginMetadata(string(data))
		repo := metadata["repo"]
		path := metadata["path"]
		repoDir := metadata["repodir"]
		if repo == "" || repoDir == "" {
			return LockedPlugin{}, "", fmt.Errorf("legacy metadata is incomplete")
		}
		if err := validatePluginRepo(repo); err != nil {
			return LockedPlugin{}, "", err
		}
		if !isSafePluginPathComponent(repoDir) {
			return LockedPlugin{}, "", fmt.Errorf("legacy repository directory is invalid")
		}
		if err := validatePluginRepoPath(path); err != nil {
			return LockedPlugin{}, "", err
		}
		return LockedPlugin{Repo: repo, Path: path}, filepath.Join(m.pluginsDir, ".repos", repoDir), nil
	}

	repo, err := m.gitClient.OriginURL(pluginPath)
	if err != nil {
		return LockedPlugin{}, "", fmt.Errorf("plugin is not a managed git checkout")
	}
	if err := validatePluginRepo(repo); err != nil {
		return LockedPlugin{}, "", err
	}
	return LockedPlugin{Repo: repo}, pluginPath, nil
}

func parseLegacyPluginMetadata(data string) map[string]string {
	metadata := make(map[string]string)
	for line := range strings.SplitSeq(data, "\n") {
		key, value, ok := strings.Cut(line, "=")
		if ok {
			metadata[strings.TrimSpace(key)] = strings.TrimSpace(value)
		}
	}
	return metadata
}

func (m *Manager) recordInstalledPlugin(plugin Plugin, repoPath string) error {
	lock, err := m.ensureLockfile()
	if err != nil {
		return err
	}
	commit, err := m.gitClient.CurrentRevision(repoPath)
	if err != nil {
		return fmt.Errorf("failed to read installed plugin revision: %w", err)
	}

	lock.SetRepositoryCommit(plugin.Repo, commit)
	lock.Plugins[plugin.ID] = LockedPlugin{
		Repo:   plugin.Repo,
		Path:   plugin.Path,
		Commit: commit,
	}
	return m.lockStore().Write(lock)
}

func (m *Manager) WriteCurrentLockfile(outputPath string) ([]string, error) {
	lock, warnings, err := m.SnapshotLockfile()
	if err != nil {
		return warnings, err
	}
	if err := m.lockStore().Write(lock); err != nil {
		return warnings, err
	}
	if outputPath != "" && outputPath != m.GetLockfilePath() {
		if err := NewLockStore(m.fs, outputPath).Write(lock); err != nil {
			return warnings, err
		}
	}
	return warnings, nil
}

func (m *Manager) RestoreFromLockfile(sourcePath string, prune bool) error {
	if sourcePath == "" {
		sourcePath = m.GetLockfilePath()
	}
	sourceStore := NewLockStore(m.fs, sourcePath)
	exists, err := sourceStore.Exists()
	if err != nil {
		return fmt.Errorf("failed to check plugin lockfile: %w", err)
	}
	if !exists {
		return fmt.Errorf("plugin lockfile not found: %s", sourcePath)
	}
	target, err := sourceStore.Load()
	if err != nil {
		return err
	}
	current, err := m.ensureLockfile()
	if err != nil {
		return err
	}

	for _, id := range target.IDs() {
		wanted := target.Plugins[id]
		installedPath, err := m.findInstalledPath(id)
		if err != nil {
			return err
		}

		if installedPath != "" {
			existing, managed := current.Plugins[id]
			if !managed {
				return fmt.Errorf("plugin %q is already installed but is not managed by the lockfile", id)
			}
			if existing.Repo != wanted.Repo || existing.Path != wanted.Path {
				if err := m.UninstallByIDOrName(id); err != nil {
					return err
				}
				installedPath = ""
			}
		}

		plugin := Plugin{ID: id, Name: id, Repo: wanted.Repo, Path: wanted.Path}
		newlyInstalled := installedPath == ""
		if installedPath == "" {
			if err := m.Install(plugin); err != nil {
				return fmt.Errorf("failed to restore plugin %q: %w", id, err)
			}
		}

		repoPath := m.repositoryPath(id, wanted)
		previousCommit, err := m.gitClient.CurrentRevision(repoPath)
		if err != nil {
			if newlyInstalled {
				m.UninstallByIDOrName(id) //nolint:errcheck
			}
			return fmt.Errorf("failed to read current revision for plugin %q: %w", id, err)
		}
		if err := m.gitClient.CheckoutRevision(repoPath, wanted.Commit); err != nil {
			if newlyInstalled {
				if rollbackErr := m.UninstallByIDOrName(id); rollbackErr != nil {
					return fmt.Errorf("failed to restore plugin %q at %s: %w (also failed to remove the partial install: %v)", id, wanted.Commit, err, rollbackErr)
				}
			}
			return fmt.Errorf("failed to restore plugin %q at %s: %w", id, wanted.Commit, err)
		}
		rollback := func(restoreErr error) error {
			if newlyInstalled {
				if rollbackErr := m.UninstallByIDOrName(id); rollbackErr != nil {
					return fmt.Errorf("%w (also failed to remove the partial install: %v)", restoreErr, rollbackErr)
				}
				return restoreErr
			}
			if rollbackErr := m.gitClient.CheckoutRevision(repoPath, previousCommit); rollbackErr != nil {
				return fmt.Errorf("%w (also failed to restore revision %s: %v)", restoreErr, previousCommit, rollbackErr)
			}
			return restoreErr
		}
		pluginPath := installedPath
		if pluginPath == "" {
			pluginPath = filepath.Join(m.pluginsDir, id)
		}
		if actualID := m.getPluginID(pluginPath); actualID != id {
			return rollback(fmt.Errorf("restored plugin %q has manifest id %q", id, actualID))
		}
		if err := m.recordInstalledPlugin(plugin, repoPath); err != nil {
			return rollback(err)
		}
		current, err = m.lockStore().Load()
		if err != nil {
			return err
		}
	}

	if prune {
		for _, id := range current.IDs() {
			if _, wanted := target.Plugins[id]; wanted {
				continue
			}
			if err := m.UninstallByIDOrName(id); err != nil {
				return fmt.Errorf("failed to prune plugin %q: %w", id, err)
			}
		}
		return m.lockStore().Write(target)
	}

	merged, err := m.lockStore().Load()
	if err != nil {
		return err
	}
	for id, plugin := range target.Plugins {
		merged.SetRepositoryCommit(plugin.Repo, plugin.Commit)
		merged.Plugins[id] = plugin
	}
	return m.lockStore().Write(merged)
}

func (m *Manager) repositoryPath(pluginID string, plugin LockedPlugin) string {
	if plugin.Path != "" {
		return filepath.Join(m.pluginsDir, ".repos", m.getRepoName(plugin.Repo))
	}
	if installedPath, err := m.findInDir(m.pluginsDir, pluginID); err == nil && installedPath != "" {
		return installedPath
	}
	return filepath.Join(m.pluginsDir, pluginID)
}
