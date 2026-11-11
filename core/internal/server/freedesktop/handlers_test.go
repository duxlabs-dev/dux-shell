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

func TestHandleSetIconFile(t *testing.T) {
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
}
