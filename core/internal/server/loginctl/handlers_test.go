package loginctl

import (
	"bytes"
	"encoding/json"
	"net"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	mockdbus "github.com/duxlabs-dev/dux-shell/core/internal/mocks/github.com/godbus/dbus/v5"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
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

func TestHandleGetState(t *testing.T) {
	manager := &Manager{
		state: &SessionState{
			SessionID:    "1",
			Locked:       false,
			Active:       true,
			SessionType:  "wayland",
			SessionClass: "user",
			UserName:     "testuser",
		},
		stateMutex: sync.RWMutex{},
	}

	mc := newMockNetConn()
	conn := ipc.NewConnWriter(mc)
	req := ipc.Request{ID: 123, Method: "loginctl.getState"}

	handleGetState(conn, req, manager)

	var resp ipc.Response[SessionState]
	err := json.NewDecoder(mc.writeBuf).Decode(&resp)
	require.NoError(t, err)

	assert.Equal(t, 123, resp.ID)
	assert.Empty(t, resp.Error)
	require.NotNil(t, resp.Result)
	assert.Equal(t, "1", resp.Result.SessionID)
	assert.False(t, resp.Result.Locked)
	assert.True(t, resp.Result.Active)
}

func TestHandleLock(t *testing.T) {
	t.Run("successful lock", func(t *testing.T) {
		mockSessionObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: nil}
		mockSessionObj.EXPECT().Call("org.freedesktop.login1.Session.Lock", dbus.Flags(0)).Return(mockCall)

		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			sessionObj: mockSessionObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{ID: 123, Method: "loginctl.lock"}
		handleLock(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
		require.NotNil(t, resp.Result)
		assert.True(t, resp.Result.Success)
		assert.Equal(t, "locked", resp.Result.Message)
	})

	t.Run("lock fails", func(t *testing.T) {
		mockSessionObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: assert.AnError}
		mockSessionObj.EXPECT().Call("org.freedesktop.login1.Session.Lock", dbus.Flags(0)).Return(mockCall)

		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			sessionObj: mockSessionObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{ID: 123, Method: "loginctl.lock"}
		handleLock(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "failed to lock session")
	})
}

func TestHandleUnlock(t *testing.T) {
	t.Run("successful unlock", func(t *testing.T) {
		mockSessionObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: nil}
		mockSessionObj.EXPECT().Call("org.freedesktop.login1.Session.Unlock", dbus.Flags(0)).Return(mockCall)

		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			sessionObj: mockSessionObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{ID: 123, Method: "loginctl.unlock"}
		handleUnlock(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
		require.NotNil(t, resp.Result)
		assert.True(t, resp.Result.Success)
		assert.Equal(t, "unlocked", resp.Result.Message)
	})

	t.Run("unlock fails", func(t *testing.T) {
		mockSessionObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: assert.AnError}
		mockSessionObj.EXPECT().Call("org.freedesktop.login1.Session.Unlock", dbus.Flags(0)).Return(mockCall)

		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			sessionObj: mockSessionObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{ID: 123, Method: "loginctl.unlock"}
		handleUnlock(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "failed to unlock session")
	})
}

func TestHandleActivate(t *testing.T) {
	t.Run("successful activate", func(t *testing.T) {
		mockSessionObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: nil}
		mockSessionObj.EXPECT().Call("org.freedesktop.login1.Session.Activate", dbus.Flags(0)).Return(mockCall)

		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			sessionObj: mockSessionObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{ID: 123, Method: "loginctl.activate"}
		handleActivate(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
		require.NotNil(t, resp.Result)
		assert.True(t, resp.Result.Success)
		assert.Equal(t, "activated", resp.Result.Message)
	})

	t.Run("activate fails", func(t *testing.T) {
		mockSessionObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: assert.AnError}
		mockSessionObj.EXPECT().Call("org.freedesktop.login1.Session.Activate", dbus.Flags(0)).Return(mockCall)

		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			sessionObj: mockSessionObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{ID: 123, Method: "loginctl.activate"}
		handleActivate(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "failed to activate session")
	})
}

func TestHandleSetIdleHint(t *testing.T) {
	t.Run("missing idle parameter", func(t *testing.T) {
		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "loginctl.setIdleHint",
			Params: map[string]any{},
		}

		handleSetIdleHint(conn, req, manager)

		var resp ipc.Response[any]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "missing or invalid 'idle' parameter")
	})

	t.Run("successful set idle hint true", func(t *testing.T) {
		mockSessionObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: nil}
		mockSessionObj.EXPECT().Call("org.freedesktop.login1.Session.SetIdleHint", dbus.Flags(0), true).Return(mockCall)

		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			sessionObj: mockSessionObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "loginctl.setIdleHint",
			Params: map[string]any{
				"idle": true,
			},
		}

		handleSetIdleHint(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
		require.NotNil(t, resp.Result)
		assert.True(t, resp.Result.Success)
		assert.Equal(t, "idle hint set", resp.Result.Message)
	})

	t.Run("set idle hint fails", func(t *testing.T) {
		mockSessionObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: assert.AnError}
		mockSessionObj.EXPECT().Call("org.freedesktop.login1.Session.SetIdleHint", dbus.Flags(0), false).Return(mockCall)

		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			sessionObj: mockSessionObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "loginctl.setIdleHint",
			Params: map[string]any{
				"idle": false,
			},
		}

		handleSetIdleHint(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "failed to set idle hint")
	})
}

func TestHandleTerminate(t *testing.T) {
	t.Run("successful terminate", func(t *testing.T) {
		mockSessionObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: nil}
		mockSessionObj.EXPECT().Call("org.freedesktop.login1.Session.Terminate", dbus.Flags(0)).Return(mockCall)

		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			sessionObj: mockSessionObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{ID: 123, Method: "loginctl.terminate"}
		handleTerminate(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
		require.NotNil(t, resp.Result)
		assert.True(t, resp.Result.Success)
		assert.Equal(t, "terminated", resp.Result.Message)
	})

	t.Run("terminate fails", func(t *testing.T) {
		mockSessionObj := mockdbus.NewMockBusObject(t)
		mockCall := &dbus.Call{Err: assert.AnError}
		mockSessionObj.EXPECT().Call("org.freedesktop.login1.Session.Terminate", dbus.Flags(0)).Return(mockCall)

		manager := &Manager{
			state:      &SessionState{},
			stateMutex: sync.RWMutex{},
			sessionObj: mockSessionObj,
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{ID: 123, Method: "loginctl.terminate"}
		handleTerminate(conn, req, manager)

		var resp ipc.Response[models.SuccessResult]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Contains(t, resp.Error, "failed to terminate session")
	})
}

func TestHandleRequest(t *testing.T) {
	manager := &Manager{
		state: &SessionState{
			SessionID: "1",
			Locked:    false,
		},
		stateMutex: sync.RWMutex{},
	}

	t.Run("unknown method", func(t *testing.T) {
		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "loginctl.unknown",
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
			Method: "loginctl.getState",
		}

		HandleRequest(conn, req, manager)

		var resp ipc.Response[SessionState]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.Empty(t, resp.Error)
	})
}

func TestHandleSetLockBeforeSuspend(t *testing.T) {
	on, off := true, false
	tests := []struct {
		name    string
		managed *bool
		request bool
		want    bool
		wantErr bool
	}{
		{name: "unmanaged", request: true, want: true},
		{name: "managed, same value", managed: &on, request: true, want: true},
		{name: "managed on, request off", managed: &on, request: false, want: true, wantErr: true},
		{name: "managed off, request on", managed: &off, request: true, want: false, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager := &Manager{lockPolicy: LockPolicy{LockBeforeSuspend: tt.managed}}
			manager.applyLockPolicy()

			mc := newMockNetConn()
			conn := ipc.NewConnWriter(mc)
			HandleRequest(conn, ipc.Request{ID: 7, Method: "loginctl.setLockBeforeSuspend", Params: map[string]any{"enabled": tt.request}}, manager)

			var resp ipc.Response[models.SuccessResult]
			require.NoError(t, json.NewDecoder(mc.writeBuf).Decode(&resp))
			if tt.wantErr {
				assert.Equal(t, "lock before suspend is managed by administrator policy", resp.Error)
			} else {
				assert.Empty(t, resp.Error)
			}
			assert.Equal(t, tt.want, manager.lockBeforeSuspend.Load())
		})
	}
}

func TestHandleSetSleepInhibitorEnabled(t *testing.T) {
	on, off := true, false
	tests := []struct {
		name    string
		policy  LockPolicy
		request bool
		want    bool
		wantErr bool
	}{
		{name: "unmanaged", request: false, want: false},
		{name: "both managed on, request off", policy: LockPolicy{LockBeforeSuspend: &on, LoginctlLockIntegration: &on}, request: false, want: true, wantErr: true},
		{name: "both managed on, request on", policy: LockPolicy{LockBeforeSuspend: &on, LoginctlLockIntegration: &on}, request: true, want: true},
		{name: "lock before suspend managed off", policy: LockPolicy{LockBeforeSuspend: &off}, request: true, want: false, wantErr: true},
		{name: "integration managed off", policy: LockPolicy{LoginctlLockIntegration: &off}, request: true, want: false, wantErr: true},
		{name: "lock before suspend managed on, integration left to the user", policy: LockPolicy{LockBeforeSuspend: &on}, request: false, want: false},
		{name: "integration managed on, lock before suspend left to the user", policy: LockPolicy{LoginctlLockIntegration: &on}, request: false, want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager := &Manager{lockPolicy: tt.policy}
			manager.applyLockPolicy()
			inhibit, err := os.CreateTemp(t.TempDir(), "inhibit")
			require.NoError(t, err)
			held := manager.sleepInhibitorEnabled.Load()
			if held {
				manager.inhibitFile = inhibit
			}

			mc := newMockNetConn()
			conn := ipc.NewConnWriter(mc)
			HandleRequest(conn, ipc.Request{ID: 7, Method: "loginctl.setSleepInhibitorEnabled", Params: map[string]any{"enabled": tt.request}}, manager)

			var resp ipc.Response[models.SuccessResult]
			require.NoError(t, json.NewDecoder(mc.writeBuf).Decode(&resp))
			if tt.wantErr {
				assert.Equal(t, "the sleep inhibitor is managed by administrator policy", resp.Error)
				assert.Equal(t, held, manager.inhibitFile != nil, "a refused request leaves the inhibitor as it was")
			} else {
				assert.Empty(t, resp.Error)
			}
			assert.Equal(t, tt.want, manager.sleepInhibitorEnabled.Load())
		})
	}
}
