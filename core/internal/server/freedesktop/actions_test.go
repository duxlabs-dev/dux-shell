package freedesktop

import (
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStageIconFile(t *testing.T) {
	t.Run("empty path is passed through", func(t *testing.T) {
		staged, cleanup, err := stageIconFile("")
		require.NoError(t, err)
		assert.Equal(t, "", staged)
		cleanup()
	})

	t.Run("missing file", func(t *testing.T) {
		_, cleanup, err := stageIconFile(filepath.Join(t.TempDir(), "missing.png"))
		assert.Error(t, err)
		cleanup()
	})

	t.Run("copies content and cleanup removes the copy", func(t *testing.T) {
		src := filepath.Join(t.TempDir(), "avatar.png")
		require.NoError(t, os.WriteFile(src, []byte("image-bytes"), 0o600))

		staged, cleanup, err := stageIconFile(src)
		require.NoError(t, err)
		assert.NotEqual(t, src, staged)

		data, err := os.ReadFile(staged)
		require.NoError(t, err)
		assert.Equal(t, []byte("image-bytes"), data)

		cleanup()
		_, err = os.Stat(staged)
		assert.True(t, os.IsNotExist(err))
	})
}

func TestManager_SetRealName(t *testing.T) {
	t.Run("accounts not available", func(t *testing.T) {
		manager := &Manager{
			state: &FreedeskState{
				Accounts: AccountsState{
					Available: false,
				},
			},
			stateMutex: sync.RWMutex{},
		}

		err := manager.SetRealName("New Name")
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "accounts service not available")
	})
}

func TestManager_SetEmail(t *testing.T) {
	t.Run("accounts not available", func(t *testing.T) {
		manager := &Manager{
			state: &FreedeskState{
				Accounts: AccountsState{
					Available: false,
				},
			},
			stateMutex: sync.RWMutex{},
		}

		err := manager.SetEmail("test@example.com")
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "accounts service not available")
	})
}

func TestManager_SetLanguage(t *testing.T) {
	t.Run("accounts not available", func(t *testing.T) {
		manager := &Manager{
			state: &FreedeskState{
				Accounts: AccountsState{
					Available: false,
				},
			},
			stateMutex: sync.RWMutex{},
		}

		err := manager.SetLanguage("en_US.UTF-8")
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "accounts service not available")
	})
}

func TestManager_SetLocation(t *testing.T) {
	t.Run("accounts not available", func(t *testing.T) {
		manager := &Manager{
			state: &FreedeskState{
				Accounts: AccountsState{
					Available: false,
				},
			},
			stateMutex: sync.RWMutex{},
		}

		err := manager.SetLocation("Test Location")
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "accounts service not available")
	})
}

func TestManager_UpdateAccountsState(t *testing.T) {
	t.Run("accounts not available", func(t *testing.T) {
		manager := &Manager{
			state: &FreedeskState{
				Accounts: AccountsState{
					Available: false,
				},
			},
			stateMutex: sync.RWMutex{},
		}

		err := manager.updateAccountsState()
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "accounts service not available")
	})
}

func TestManager_UpdateSettingsState(t *testing.T) {
	t.Run("settings not available", func(t *testing.T) {
		manager := &Manager{
			state: &FreedeskState{
				Settings: SettingsState{
					Available: false,
				},
			},
			stateMutex: sync.RWMutex{},
		}

		err := manager.updateSettingsState()
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "settings portal not available")
	})
}
