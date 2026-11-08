package tailscale

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnstate"
)

type mockConn struct {
	*bytes.Buffer
}

func (m *mockConn) Close() error                       { return nil }
func (m *mockConn) LocalAddr() net.Addr                { return nil }
func (m *mockConn) RemoteAddr() net.Addr               { return nil }
func (m *mockConn) SetDeadline(t time.Time) error      { return nil }
func (m *mockConn) SetReadDeadline(t time.Time) error  { return nil }
func (m *mockConn) SetWriteDeadline(t time.Time) error { return nil }

func handlerTestManager() *Manager {
	client := &mockClient{
		watchFn: func(ctx context.Context, mask ipn.NotifyWatchOpt) (ipnBusWatcher, error) {
			<-ctx.Done()
			return nil, ctx.Err()
		},
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) {
			return runningStatus(), nil
		},
	}
	m := newManager(client)
	m.RefreshState()
	return m
}

func TestHandleGetStatus(t *testing.T) {
	m := handlerTestManager()
	defer m.Close()

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{ID: 1, Method: "tailscale.getStatus"}
	handleGetStatus(conn, req, m)

	var resp ipc.Response[TailscaleState]
	err := json.NewDecoder(buf).Decode(&resp)
	require.NoError(t, err)
	assert.Equal(t, 1, resp.ID)
	assert.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Connected)
	assert.Equal(t, "cachyos", resp.Result.Self.Hostname)
}

func TestHandleActions(t *testing.T) {
	cases := []struct {
		name   string
		method string
		params map[string]any
	}{
		{"connect", "tailscale.connect", nil},
		{"disconnect", "tailscale.disconnect", nil},
		{"setExitNode", "tailscale.setExitNode", map[string]any{"id": "nABC123"}},
		{"setAllowLanAccess", "tailscale.setAllowLanAccess", map[string]any{"enabled": true}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := handlerTestManager()
			defer m.Close()

			buf := &bytes.Buffer{}
			conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

			req := ipc.Request{ID: 1, Method: tc.method, Params: tc.params}
			HandleRequest(conn, req, m)

			var resp ipc.Response[models.SuccessResult]
			require.NoError(t, json.NewDecoder(buf).Decode(&resp))
			assert.Equal(t, 1, resp.ID)
			assert.Empty(t, resp.Error)
			require.NotNil(t, resp.Result)
			assert.True(t, resp.Result.Success)
		})
	}
}

func TestHandleAction_BackendError(t *testing.T) {
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		editPrefsFn: func(ctx context.Context, mp *ipn.MaskedPrefs) (*ipn.Prefs, error) {
			return nil, fmt.Errorf("backend rejected edit")
		},
	}
	m := newManager(client)
	defer m.Close()

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{ID: 1, Method: "tailscale.connect"}
	HandleRequest(conn, req, m)

	var resp ipc.Response[models.SuccessResult]
	require.NoError(t, json.NewDecoder(buf).Decode(&resp))
	assert.Nil(t, resp.Result)
	assert.Contains(t, resp.Error, "backend rejected edit")
}

func TestHandleRequest_UnknownMethod(t *testing.T) {
	m := handlerTestManager()
	defer m.Close()

	buf := &bytes.Buffer{}
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})

	req := ipc.Request{ID: 1, Method: "tailscale.unknownMethod"}
	HandleRequest(conn, req, m)

	var resp ipc.Response[any]
	err := json.NewDecoder(buf).Decode(&resp)
	require.NoError(t, err)
	assert.Nil(t, resp.Result)
	assert.NotEmpty(t, resp.Error)
	assert.Contains(t, resp.Error, "unknown method")
}
