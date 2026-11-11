package loginctl

import (
	"bytes"
	"encoding/json"
	"net"
	"os"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
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
