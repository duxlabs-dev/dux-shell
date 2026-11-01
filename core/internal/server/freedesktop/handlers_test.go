package freedesktop

import (
	"bytes"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	mockdbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type mockNetConn struct {
	net.Conn
	readBuf  *bytes.Buffer
	writeBuf *bytes.Buffer
	closed   bool
}

func newMockNetConn() *mockNetConn {
	return &mockNetConn{
		readBuf:  &bytes.Buffer{},
		writeBuf: &bytes.Buffer{},
	}
}

func (m *mockNetConn) Read(b []byte) (n int, err error) {
	return m.readBuf.Read(b)
}

func (m *mockNetConn) Write(b []byte) (n int, err error) {
	return m.writeBuf.Write(b)
}

func (m *mockNetConn) Close() error {
	m.closed = true
	return nil
}

func (m *mockNetConn) SetWriteDeadline(t time.Time) error { return nil }

func mockGetAllAccountsProperties() *dbus.Call {
	props := map[string]dbus.Variant{
		"IconFile":      dbus.MakeVariant("/path/to/icon.png"),
		"RealName":      dbus.MakeVariant("Test"),
		"UserName":      dbus.MakeVariant("test"),
		"AccountType":   dbus.MakeVariant(int32(0)),
		"HomeDirectory": dbus.MakeVariant("/home/test"),
		"Shell":         dbus.MakeVariant("/bin/bash"),
		"Email":         dbus.MakeVariant(""),
		"Language":      dbus.MakeVariant(""),
		"Location":      dbus.MakeVariant(""),
		"Locked":        dbus.MakeVariant(false),
		"PasswordMode":  dbus.MakeVariant(int32(1)),
	}
	return &dbus.Call{Err: nil, Body: []any{props}}
}

func TestHandleGetState(t *testing.T) {
	manager := &Manager{
		state: &FreedeskState{
			Accounts: AccountsState{
				Available: true,
				UserName:  "testuser",
				RealName:  "Test User",
				UID:       1000,
			},
			Settings: SettingsState{
				Available:   true,
				ColorScheme: 1,
			},
		},
		stateMutex: sync.RWMutex{},
	}

	mc := newMockNetConn()
	conn := ipc.NewConnWriter(mc)
	req := ipc.Request{ID: 123, Method: "freedesktop.getState"}

	handleGetState(conn, req, manager)

	var resp ipc.Response[FreedeskState]
	err := json.NewDecoder(mc.writeBuf).Decode(&resp)
	require.NoError(t, err)

	assert.Equal(t, 123, resp.ID)
	assert.Empty(t, resp.Error)
	require.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Accounts.Available)
	assert.Equal(t, "testuser", resp.Result.Accounts.UserName)
	assert.True(t, resp.Result.Settings.Available)
	assert.Equal(t, uint32(1), resp.Result.Settings.ColorScheme)
}

func TestHandleSetIconFile(t *testing.T) {
	t.Run("missing path parameter", func(t *testing.T) {
		manager := &Manager{
			state:      &FreedeskState{},
			stateMutex: sync.RWMutex{},
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.setIconFile",
			Params: map[string]any{},
		}

		handleSetIconFile(conn, req, manager)

		var resp ipc.Response[any]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "missing or invalid 'path' parameter")
	})

	t.Run("successful set icon file", func(t *testing.T) {
		iconPath := filepath.Join(t.TempDir(), "icon.png")
		require.NoError(t, os.WriteFile(iconPath, []byte("image-bytes"), 0o600))

		mockAccountsObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: nil}
		stagedCopy := mock.MatchedBy(func(path string) bool {
			if path == iconPath {
				return false
			}
			data, err := os.ReadFile(path)
			return err == nil && string(data) == "image-bytes"
		})
		mockAccountsObj.EXPECT().Call("org.freedesktop.Accounts.User.SetIconFile", dbus.Flags(0), stagedCopy).Return(mockCall)
		mockAccountsObj.EXPECT().CallWithContext(mock.Anything, "org.freedesktop.DBus.Properties.GetAll", dbus.Flags(0), "org.freedesktop.Accounts.User").Return(mockGetAllAccountsProperties())

		manager := &Manager{
			state: &FreedeskState{
				Accounts: AccountsState{
					Available: true,
				},
			},
			stateMutex:  sync.RWMutex{},
			accountsObj: mockAccountsObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.setIconFile",
			Params: map[string]any{
				"path": iconPath,
			},
		}

		handleSetIconFile(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
		require.NotNil(t, resp.Result)
		assert.True(t, resp.Result.Success)
		assert.Equal(t, "icon file set", resp.Result.Message)
	})

	t.Run("accounts not available", func(t *testing.T) {
		manager := &Manager{
			state: &FreedeskState{
				Accounts: AccountsState{
					Available: false,
				},
			},
			stateMutex: sync.RWMutex{},
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.setIconFile",
			Params: map[string]any{
				"path": "/path/to/icon.png",
			},
		}

		handleSetIconFile(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "accounts service not available")
	})
}

func TestHandleSetRealName(t *testing.T) {
	t.Run("missing name parameter", func(t *testing.T) {
		manager := &Manager{
			state:      &FreedeskState{},
			stateMutex: sync.RWMutex{},
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.setRealName",
			Params: map[string]any{},
		}

		handleSetRealName(conn, req, manager)

		var resp ipc.Response[any]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "missing or invalid 'name' parameter")
	})

	t.Run("successful set real name", func(t *testing.T) {
		mockAccountsObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: nil}
		mockAccountsObj.EXPECT().Call("org.freedesktop.Accounts.User.SetRealName", dbus.Flags(0), "New Name").Return(mockCall)
		mockAccountsObj.EXPECT().CallWithContext(mock.Anything, "org.freedesktop.DBus.Properties.GetAll", dbus.Flags(0), "org.freedesktop.Accounts.User").Return(mockGetAllAccountsProperties())

		manager := &Manager{
			state: &FreedeskState{
				Accounts: AccountsState{
					Available: true,
				},
			},
			stateMutex:  sync.RWMutex{},
			accountsObj: mockAccountsObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.setRealName",
			Params: map[string]any{
				"name": "New Name",
			},
		}

		handleSetRealName(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
		require.NotNil(t, resp.Result)
		assert.True(t, resp.Result.Success)
		assert.Equal(t, "real name set", resp.Result.Message)
	})
}

func TestHandleSetEmail(t *testing.T) {
	t.Run("missing email parameter", func(t *testing.T) {
		manager := &Manager{
			state:      &FreedeskState{},
			stateMutex: sync.RWMutex{},
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.setEmail",
			Params: map[string]any{},
		}

		handleSetEmail(conn, req, manager)

		var resp ipc.Response[any]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "missing or invalid 'email' parameter")
	})

	t.Run("successful set email", func(t *testing.T) {
		mockAccountsObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: nil}
		mockAccountsObj.EXPECT().Call("org.freedesktop.Accounts.User.SetEmail", dbus.Flags(0), "test@example.com").Return(mockCall)
		mockAccountsObj.EXPECT().CallWithContext(mock.Anything, "org.freedesktop.DBus.Properties.GetAll", dbus.Flags(0), "org.freedesktop.Accounts.User").Return(mockGetAllAccountsProperties())

		manager := &Manager{
			state: &FreedeskState{
				Accounts: AccountsState{
					Available: true,
				},
			},
			stateMutex:  sync.RWMutex{},
			accountsObj: mockAccountsObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.setEmail",
			Params: map[string]any{
				"email": "test@example.com",
			},
		}

		handleSetEmail(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
		require.NotNil(t, resp.Result)
		assert.True(t, resp.Result.Success)
		assert.Equal(t, "email set", resp.Result.Message)
	})
}

func TestHandleSetLanguage(t *testing.T) {
	t.Run("missing language parameter", func(t *testing.T) {
		manager := &Manager{
			state:      &FreedeskState{},
			stateMutex: sync.RWMutex{},
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.setLanguage",
			Params: map[string]any{},
		}

		handleSetLanguage(conn, req, manager)

		var resp ipc.Response[any]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "missing or invalid 'language' parameter")
	})
}

func TestHandleSetLocation(t *testing.T) {
	t.Run("missing location parameter", func(t *testing.T) {
		manager := &Manager{
			state:      &FreedeskState{},
			stateMutex: sync.RWMutex{},
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.setLocation",
			Params: map[string]any{},
		}

		handleSetLocation(conn, req, manager)

		var resp ipc.Response[any]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "missing or invalid 'location' parameter")
	})
}

func TestHandleGetUserIconFile(t *testing.T) {
	t.Run("missing username parameter", func(t *testing.T) {
		manager := &Manager{
			state:      &FreedeskState{},
			stateMutex: sync.RWMutex{},
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.getUserIconFile",
			Params: map[string]any{},
		}

		handleGetUserIconFile(conn, req, manager)

		var resp ipc.Response[any]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "missing or invalid 'username' parameter")
	})

	t.Run("accounts not available", func(t *testing.T) {
		manager := &Manager{
			state: &FreedeskState{
				Accounts: AccountsState{
					Available: false,
				},
			},
			stateMutex: sync.RWMutex{},
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.accounts.getUserIconFile",
			Params: map[string]any{
				"username": "testuser",
			},
		}

		handleGetUserIconFile(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "accounts service not available")
	})
}

func TestHandleGetColorScheme(t *testing.T) {
	t.Run("settings not available", func(t *testing.T) {
		manager := &Manager{
			state: &FreedeskState{
				Settings: SettingsState{
					Available: false,
				},
			},
			stateMutex: sync.RWMutex{},
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{ID: 123, Method: "freedesktop.settings.getColorScheme"}

		handleGetColorScheme(conn, req, manager)

		var resp ipc.Response[map[string]uint32]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "settings portal not available")
	})

	t.Run("successful get color scheme", func(t *testing.T) {
		mockSettingsObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{
			Err:  nil,
			Body: []any{dbus.MakeVariant(uint32(1))},
		}
		mockSettingsObj.EXPECT().Call("org.freedesktop.portal.Settings.ReadOne", dbus.Flags(0), "org.freedesktop.appearance", "color-scheme").Return(mockCall)

		manager := &Manager{
			state: &FreedeskState{
				Settings: SettingsState{
					Available: true,
				},
			},
			stateMutex:  sync.RWMutex{},
			settingsObj: mockSettingsObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{ID: 123, Method: "freedesktop.settings.getColorScheme"}

		handleGetColorScheme(conn, req, manager)

		var resp ipc.Response[map[string]uint32]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
		require.NotNil(t, resp.Result)
		assert.Equal(t, uint32(1), (*resp.Result)["colorScheme"])
	})
}

func TestHandleRequest(t *testing.T) {
	manager := &Manager{
		state: &FreedeskState{
			Accounts: AccountsState{
				Available: true,
				UserName:  "testuser",
			},
		},
		stateMutex: sync.RWMutex{},
	}

	t.Run("unknown method", func(t *testing.T) {
		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.unknown",
		}

		HandleRequest(conn, req, manager)

		var resp ipc.Response[any]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "unknown method")
	})

	t.Run("valid method - getState", func(t *testing.T) {
		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "freedesktop.getState",
		}

		HandleRequest(conn, req, manager)

		var resp ipc.Response[FreedeskState]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
	})
}
