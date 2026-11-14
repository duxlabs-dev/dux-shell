package plugins

import (
	"testing"

	"github.com/spf13/afero"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testCommit = "0123456789abcdef0123456789abcdef01234567"

func TestPluginLockfileValidation(t *testing.T) {
	tests := []struct {
		name string
		lock PluginLockfile
		want string
	}{
		{
			name: "rejects unsupported version",
			lock: PluginLockfile{LockfileVersion: 2, Plugins: map[string]LockedPlugin{}},
			want: "unsupported plugin lockfile version",
		},
		{
			name: "rejects unsafe id",
			lock: PluginLockfile{LockfileVersion: 1, Plugins: map[string]LockedPlugin{"../bad": {Repo: "repo", Commit: testCommit}}},
			want: "invalid locked plugin id",
		},
		{
			name: "rejects unsafe repository path",
			lock: PluginLockfile{LockfileVersion: 1, Plugins: map[string]LockedPlugin{"bad": {Repo: "repo", Path: "../bad", Commit: testCommit}}},
			want: "invalid repository path",
		},
		{
			name: "rejects abbreviated commit",
			lock: PluginLockfile{LockfileVersion: 1, Plugins: map[string]LockedPlugin{"bad": {Repo: "repo", Commit: "abc123"}}},
			want: "invalid commit",
		},
		{
			name: "rejects repository credentials",
			lock: PluginLockfile{LockfileVersion: 1, Plugins: map[string]LockedPlugin{"bad": {Repo: "https://token@example.com/plugin.git", Commit: testCommit}}},
			want: "must not contain credentials",
		},
		{
			name: "rejects ssh password",
			lock: PluginLockfile{LockfileVersion: 1, Plugins: map[string]LockedPlugin{"bad": {Repo: "ssh://git:secret@example.com/plugin.git", Commit: testCommit}}},
			want: "must not contain credentials",
		},
		{
			name: "rejects conflicting monorepo commits",
			lock: PluginLockfile{LockfileVersion: 1, Plugins: map[string]LockedPlugin{
				"one": {Repo: "repo", Commit: testCommit},
				"two": {Repo: "repo", Commit: "1123456789abcdef0123456789abcdef01234567"},
			}},
			want: "must use the same commit",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.lock.Validate()
			require.Error(t, err)
			assert.Contains(t, err.Error(), tt.want)
		})
	}
}

func TestPluginLockfileAcceptsSSHRemotes(t *testing.T) {
	repos := []string{
		"https://github.com/user/plugin.git",
		"ssh://git@github.com/user/plugin.git",
		"git@github.com:user/plugin.git",
	}

	for _, repo := range repos {
		t.Run(repo, func(t *testing.T) {
			lock := PluginLockfile{LockfileVersion: 1, Plugins: map[string]LockedPlugin{
				"plugin": {Repo: repo, Commit: testCommit},
			}}
			assert.NoError(t, lock.Validate())
		})
	}
}

func TestMissingPluginLockfileIsEmpty(t *testing.T) {
	store := NewLockStore(afero.NewMemMapFs(), "/config/plugins.lock.json")
	lock, err := store.Load()
	require.NoError(t, err)
	assert.Equal(t, pluginLockfileVersion, lock.LockfileVersion)
	assert.Empty(t, lock.Plugins)
}
