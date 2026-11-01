package plugins

import (
	"errors"
	"path/filepath"
	"testing"

	"github.com/spf13/afero"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setupTestManager(t *testing.T) (*Manager, afero.Fs, string) {
	t.Helper()
	fs := afero.NewMemMapFs()
	pluginsDir := "/test-plugins"
	manager := &Manager{
		fs:         fs,
		pluginsDir: pluginsDir,
		lockPath:   "/config/plugins.lock.json",
		gitClient:  &mockGitClient{},
	}
	return manager, fs, pluginsDir
}

func TestGetPluginsDir(t *testing.T) {
	t.Run("uses XDG_CONFIG_HOME when set", func(t *testing.T) {
		configHome := t.TempDir()
		t.Setenv("XDG_CONFIG_HOME", configHome)

		assert.Equal(t, filepath.Join(configHome, "dms", "plugins"), getPluginsDir())
	})

	t.Run("falls back to home directory", func(t *testing.T) {
		home := t.TempDir()
		t.Setenv("XDG_CONFIG_HOME", "")
		t.Setenv("HOME", home)

		assert.Equal(t, filepath.Join(home, ".config", "dms", "plugins"), getPluginsDir())
	})
}

func TestInstall(t *testing.T) {
	t.Run("installs plugin successfully", func(t *testing.T) {
		manager, fs, pluginsDir := setupTestManager(t)

		plugin := Plugin{
			ID:   "test-plugin",
			Name: "TestPlugin",
			Repo: "https://github.com/test/plugin",
		}

		cloneCalled := false
		mockGit := &mockGitClient{
			cloneFunc: func(path string, url string) error {
				cloneCalled = true
				assert.Equal(t, filepath.Join(pluginsDir, plugin.ID), path)
				assert.Equal(t, plugin.Repo, url)
				return fs.MkdirAll(path, 0o755)
			},
		}
		manager.gitClient = mockGit

		err := manager.Install(plugin)
		assert.NoError(t, err)
		assert.True(t, cloneCalled)

		exists, _ := afero.DirExists(fs, filepath.Join(pluginsDir, plugin.ID))
		assert.True(t, exists)
	})

	t.Run("returns error when plugin already installed", func(t *testing.T) {
		manager, fs, pluginsDir := setupTestManager(t)

		plugin := Plugin{ID: "test-plugin", Name: "TestPlugin"}
		pluginPath := filepath.Join(pluginsDir, plugin.ID)
		err := fs.MkdirAll(pluginPath, 0o755)
		require.NoError(t, err)

		err = manager.Install(plugin)
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "already installed")
	})
}

func TestManagerUpdate(t *testing.T) {
	t.Run("updates plugin successfully", func(t *testing.T) {
		manager, fs, pluginsDir := setupTestManager(t)

		plugin := Plugin{ID: "test-plugin", Name: "TestPlugin"}
		pluginPath := filepath.Join(pluginsDir, plugin.ID)
		err := fs.MkdirAll(pluginPath, 0o755)
		require.NoError(t, err)

		pullCalled := false
		mockGit := &mockGitClient{
			pullFunc: func(path string) error {
				pullCalled = true
				assert.Equal(t, pluginPath, path)
				return nil
			},
		}
		manager.gitClient = mockGit

		err = manager.Update(plugin)
		assert.NoError(t, err)
		assert.True(t, pullCalled)
	})

	t.Run("returns error when plugin not installed", func(t *testing.T) {
		manager, _, _ := setupTestManager(t)

		plugin := Plugin{ID: "non-existent", Name: "NonExistent"}
		err := manager.Update(plugin)
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "not installed")
	})
}

func TestUninstall(t *testing.T) {
	t.Run("uninstalls plugin successfully", func(t *testing.T) {
		manager, fs, pluginsDir := setupTestManager(t)

		plugin := Plugin{ID: "test-plugin", Name: "TestPlugin"}
		pluginPath := filepath.Join(pluginsDir, plugin.ID)
		err := fs.MkdirAll(pluginPath, 0o755)
		require.NoError(t, err)

		err = manager.Uninstall(plugin)
		assert.NoError(t, err)

		exists, _ := afero.DirExists(fs, pluginPath)
		assert.False(t, exists)
	})

	t.Run("returns error when plugin not installed", func(t *testing.T) {
		manager, _, _ := setupTestManager(t)

		plugin := Plugin{ID: "non-existent", Name: "NonExistent"}
		err := manager.Uninstall(plugin)
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "not installed")
	})
}

func TestListInstalled(t *testing.T) {
	t.Run("returns empty list when no plugins installed", func(t *testing.T) {
		manager, _, _ := setupTestManager(t)

		installed, err := manager.ListInstalled()
		assert.NoError(t, err)
		assert.Empty(t, installed)
	})

	t.Run("ignores files and .repos directory", func(t *testing.T) {
		manager, fs, pluginsDir := setupTestManager(t)

		err := fs.MkdirAll(pluginsDir, 0o755)
		require.NoError(t, err)
		err = fs.MkdirAll(filepath.Join(pluginsDir, "Plugin1"), 0o755)
		require.NoError(t, err)
		err = afero.WriteFile(fs, filepath.Join(pluginsDir, "Plugin1", "plugin.json"), []byte(`{"id":"Plugin1"}`), 0o644)
		require.NoError(t, err)
		err = fs.MkdirAll(filepath.Join(pluginsDir, ".repos"), 0o755)
		require.NoError(t, err)
		err = afero.WriteFile(fs, filepath.Join(pluginsDir, "README.md"), []byte("test"), 0o644)
		require.NoError(t, err)

		installed, err := manager.ListInstalled()
		assert.NoError(t, err)
		assert.Len(t, installed, 1)
		assert.Equal(t, "Plugin1", installed[0])
	})
}

func TestInstallUpdatesLockfile(t *testing.T) {
	manager, fs, pluginsDir := setupTestManager(t)
	plugin := Plugin{ID: "test-plugin", Name: "Test Plugin", Repo: "https://github.com/test/plugin.git"}
	manager.gitClient = &mockGitClient{
		cloneFunc: func(path, _ string) error {
			require.NoError(t, fs.MkdirAll(path, 0o755))
			return afero.WriteFile(fs, filepath.Join(path, "plugin.json"), []byte(`{"id":"test-plugin"}`), 0o644)
		},
		revisionFunc: func(string) (string, error) { return testCommit, nil },
	}

	require.NoError(t, manager.Install(plugin))
	lock, err := manager.lockStore().Load()
	require.NoError(t, err)
	assert.Equal(t, LockedPlugin{Repo: plugin.Repo, Commit: testCommit}, lock.Plugins[plugin.ID])
	exists, err := afero.Exists(fs, filepath.Join(pluginsDir, plugin.ID))
	require.NoError(t, err)
	assert.True(t, exists)
}

func TestUpdateRefreshesLockedCommit(t *testing.T) {
	manager, fs, pluginsDir := setupTestManager(t)
	plugin := Plugin{ID: "test-plugin", Name: "Test Plugin", Repo: "https://github.com/test/plugin.git"}
	pluginPath := filepath.Join(pluginsDir, plugin.ID)
	require.NoError(t, fs.MkdirAll(pluginPath, 0o755))
	require.NoError(t, afero.WriteFile(fs, filepath.Join(pluginPath, "plugin.json"), []byte(`{"id":"test-plugin"}`), 0o644))
	require.NoError(t, manager.lockStore().Write(PluginLockfile{
		LockfileVersion: 1,
		Plugins: map[string]LockedPlugin{
			plugin.ID: {Repo: plugin.Repo, Commit: testCommit},
		},
	}))
	newCommit := "1123456789abcdef0123456789abcdef01234567"
	manager.gitClient = &mockGitClient{
		pullFunc:     func(string) error { return nil },
		revisionFunc: func(string) (string, error) { return newCommit, nil },
	}

	require.NoError(t, manager.Update(plugin))
	lock, err := manager.lockStore().Load()
	require.NoError(t, err)
	assert.Equal(t, newCommit, lock.Plugins[plugin.ID].Commit)
}

func TestUpdateResolvesRenamedPluginDirectory(t *testing.T) {
	manager, fs, pluginsDir := setupTestManager(t)
	plugin := Plugin{ID: "test-plugin", Name: "Test Plugin", Repo: "https://github.com/test/plugin.git"}
	pluginPath := filepath.Join(pluginsDir, "renamed-dir")
	require.NoError(t, fs.MkdirAll(pluginPath, 0o755))
	require.NoError(t, afero.WriteFile(fs, filepath.Join(pluginPath, "plugin.json"), []byte(`{"id":"test-plugin"}`), 0o644))
	require.NoError(t, manager.lockStore().Write(PluginLockfile{
		LockfileVersion: 1,
		Plugins: map[string]LockedPlugin{
			plugin.ID: {Repo: plugin.Repo, Commit: testCommit},
		},
	}))
	var pulledPath string
	manager.gitClient = &mockGitClient{
		pullFunc: func(path string) error {
			pulledPath = path
			return nil
		},
		cloneFunc: func(path, _ string) error {
			t.Fatalf("unexpected clone to %s", path)
			return nil
		},
		revisionFunc: func(string) (string, error) { return testCommit, nil },
	}

	require.NoError(t, manager.Update(plugin))
	assert.Equal(t, pluginPath, pulledPath)
}

func TestUninstallRemovesLockedPlugin(t *testing.T) {
	manager, fs, pluginsDir := setupTestManager(t)
	plugin := Plugin{ID: "test-plugin", Name: "Test Plugin", Repo: "https://github.com/test/plugin.git"}
	pluginPath := filepath.Join(pluginsDir, plugin.ID)
	require.NoError(t, fs.MkdirAll(pluginPath, 0o755))
	require.NoError(t, afero.WriteFile(fs, filepath.Join(pluginPath, "plugin.json"), []byte(`{"id":"test-plugin"}`), 0o644))
	require.NoError(t, manager.lockStore().Write(PluginLockfile{
		LockfileVersion: 1,
		Plugins: map[string]LockedPlugin{
			plugin.ID: {Repo: plugin.Repo, Commit: testCommit},
		},
	}))

	require.NoError(t, manager.Uninstall(plugin))
	lock, err := manager.lockStore().Load()
	require.NoError(t, err)
	assert.NotContains(t, lock.Plugins, plugin.ID)
}

func TestRestoreFromLockfileInstallsExactCommit(t *testing.T) {
	manager, fs, _ := setupTestManager(t)
	wantedCommit := "2123456789abcdef0123456789abcdef01234567"
	incoming := PluginLockfile{
		LockfileVersion: 1,
		Plugins: map[string]LockedPlugin{
			"restored": {Repo: "https://github.com/test/restored.git", Commit: wantedCommit},
		},
	}
	require.NoError(t, NewLockStore(fs, "/incoming.lock.json").Write(incoming))
	currentCommit := testCommit
	manager.gitClient = &mockGitClient{
		cloneFunc: func(path, _ string) error {
			require.NoError(t, fs.MkdirAll(path, 0o755))
			return afero.WriteFile(fs, filepath.Join(path, "plugin.json"), []byte(`{"id":"restored"}`), 0o644)
		},
		revisionFunc: func(string) (string, error) { return currentCommit, nil },
		checkoutFunc: func(_ string, revision string) error {
			currentCommit = revision
			return nil
		},
	}

	require.NoError(t, manager.RestoreFromLockfile("/incoming.lock.json", false))
	lock, err := manager.lockStore().Load()
	require.NoError(t, err)
	assert.Equal(t, wantedCommit, lock.Plugins["restored"].Commit)
}

func TestSnapshotLockfileMigratesLegacyMonorepoMetadata(t *testing.T) {
	manager, fs, pluginsDir := setupTestManager(t)
	pluginPath := filepath.Join(pluginsDir, "legacy")
	repoPath := filepath.Join(pluginsDir, ".repos", "legacy-repo")
	require.NoError(t, fs.MkdirAll(pluginPath, 0o755))
	require.NoError(t, fs.MkdirAll(repoPath, 0o755))
	require.NoError(t, afero.WriteFile(fs, filepath.Join(pluginPath, "plugin.json"), []byte(`{"id":"legacy"}`), 0o644))
	require.NoError(t, afero.WriteFile(fs, pluginPath+".meta", []byte("repo=https://github.com/test/suite.git\npath=plugins/legacy\nrepodir=legacy-repo"), 0o644))
	manager.gitClient = &mockGitClient{
		revisionFunc: func(path string) (string, error) {
			assert.Equal(t, repoPath, path)
			return testCommit, nil
		},
	}

	lock, warnings, err := manager.SnapshotLockfile()
	require.NoError(t, err)
	assert.Empty(t, warnings)
	assert.Equal(t, LockedPlugin{
		Repo:   "https://github.com/test/suite.git",
		Path:   "plugins/legacy",
		Commit: testCommit,
	}, lock.Plugins["legacy"])
}

func TestRecordInstalledPluginUpdatesSharedRepositoryCommit(t *testing.T) {
	manager, _, _ := setupTestManager(t)
	repo := "https://github.com/test/suite.git"
	require.NoError(t, manager.lockStore().Write(PluginLockfile{
		LockfileVersion: 1,
		Plugins: map[string]LockedPlugin{
			"one": {Repo: repo, Path: "plugins/one", Commit: testCommit},
			"two": {Repo: repo, Path: "plugins/two", Commit: testCommit},
		},
	}))
	newCommit := "3123456789abcdef0123456789abcdef01234567"
	manager.gitClient = &mockGitClient{
		revisionFunc: func(string) (string, error) { return newCommit, nil },
	}

	require.NoError(t, manager.recordInstalledPlugin(Plugin{ID: "one", Repo: repo, Path: "plugins/one"}, "/repo"))
	lock, err := manager.lockStore().Load()
	require.NoError(t, err)
	assert.Equal(t, newCommit, lock.Plugins["one"].Commit)
	assert.Equal(t, newCommit, lock.Plugins["two"].Commit)
}

func TestRestoreFromLockfilePrunesManagedPlugins(t *testing.T) {
	manager, fs, pluginsDir := setupTestManager(t)
	pluginPath := filepath.Join(pluginsDir, "old")
	require.NoError(t, fs.MkdirAll(pluginPath, 0o755))
	require.NoError(t, afero.WriteFile(fs, filepath.Join(pluginPath, "plugin.json"), []byte(`{"id":"old","name":"Old"}`), 0o644))
	require.NoError(t, manager.lockStore().Write(PluginLockfile{
		LockfileVersion: 1,
		Plugins: map[string]LockedPlugin{
			"old": {Repo: "https://github.com/test/old.git", Commit: testCommit},
		},
	}))
	require.NoError(t, NewLockStore(fs, "/empty.lock.json").Write(NewPluginLockfile()))

	require.NoError(t, manager.RestoreFromLockfile("/empty.lock.json", true))
	exists, err := afero.Exists(fs, pluginPath)
	require.NoError(t, err)
	assert.False(t, exists)
	lock, err := manager.lockStore().Load()
	require.NoError(t, err)
	assert.Empty(t, lock.Plugins)
}

func TestRestoreMissingLockfileDoesNotPrune(t *testing.T) {
	manager, fs, pluginsDir := setupTestManager(t)
	pluginPath := filepath.Join(pluginsDir, "kept")
	require.NoError(t, fs.MkdirAll(pluginPath, 0o755))
	require.NoError(t, afero.WriteFile(fs, filepath.Join(pluginPath, "plugin.json"), []byte(`{"id":"kept"}`), 0o644))
	require.NoError(t, manager.lockStore().Write(PluginLockfile{
		LockfileVersion: 1,
		Plugins: map[string]LockedPlugin{
			"kept": {Repo: "https://github.com/test/kept.git", Commit: testCommit},
		},
	}))

	err := manager.RestoreFromLockfile("/missing.lock.json", true)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "not found")
	exists, statErr := afero.Exists(fs, pluginPath)
	require.NoError(t, statErr)
	assert.True(t, exists)
}

func TestRestoreFailedRevisionRemovesPartialInstall(t *testing.T) {
	manager, fs, pluginsDir := setupTestManager(t)
	incoming := PluginLockfile{
		LockfileVersion: 1,
		Plugins: map[string]LockedPlugin{
			"broken": {Repo: "https://github.com/test/broken.git", Commit: testCommit},
		},
	}
	require.NoError(t, NewLockStore(fs, "/incoming.lock.json").Write(incoming))
	manager.gitClient = &mockGitClient{
		cloneFunc: func(path, _ string) error {
			require.NoError(t, fs.MkdirAll(path, 0o755))
			return afero.WriteFile(fs, filepath.Join(path, "plugin.json"), []byte(`{"id":"broken"}`), 0o644)
		},
		revisionFunc: func(string) (string, error) { return testCommit, nil },
		checkoutFunc: func(string, string) error {
			return errors.New("revision unavailable")
		},
	}

	err := manager.RestoreFromLockfile("/incoming.lock.json", false)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "revision unavailable")
	exists, statErr := afero.Exists(fs, filepath.Join(pluginsDir, "broken"))
	require.NoError(t, statErr)
	assert.False(t, exists)
	lock, loadErr := manager.lockStore().Load()
	require.NoError(t, loadErr)
	assert.NotContains(t, lock.Plugins, "broken")
}
