package tailscale

import (
	"bytes"
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os/user"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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
		watchFn: blockingWatch,
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
		{"setPrefs", "tailscale.setPrefs", map[string]any{"acceptRoutes": true}},
		{"login", "tailscale.login", nil},
		{"logout", "tailscale.logout", nil},
		{"switchProfile", "tailscale.switchProfile", map[string]any{"id": "p2"}},
		{"removeProfile", "tailscale.removeProfile", map[string]any{"id": "p2"}},
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
		editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error {
			return fmt.Errorf("backend rejected edit")
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

func callHandler[T any](t *testing.T, m *Manager, method string, params map[string]any) ipc.Response[T] {
	t.Helper()
	buf := &bytes.Buffer{}
	HandleRequest(ipc.NewConnWriter(&mockConn{Buffer: buf}), ipc.Request{ID: 1, Method: method, Params: params}, m)
	var resp ipc.Response[T]
	require.NoError(t, json.NewDecoder(buf).Decode(&resp))
	return resp
}

func TestHandleRequestErrors(t *testing.T) {
	client := &mockClient{
		watchFn:     blockingWatch,
		statusFn:    func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error { return errAccessDenied },
		profileStatusFn: func(ctx context.Context) (loginProfile, []loginProfile, error) {
			return loginProfile{ID: "a"}, []loginProfile{{ID: "a"}, {ID: "b"}}, nil
		},
	}
	m := newManager(client)
	m.RefreshState()
	defer m.Close()
	for _, tc := range []struct {
		method string
		params map[string]any
		want   string
	}{
		{"tailscale.setPrefs", map[string]any{}, "no changes"},
		{"tailscale.setPrefs", map[string]any{"acceptDns": "yes"}, "invalid 'acceptDns' parameter"},
		{"tailscale.setPrefs", map[string]any{"advertiseRoutes": []any{1}}, "advertiseRoutes must be a list of strings"},
		{"tailscale.setPrefs", map[string]any{"acceptRoutes": true}, "access denied"},
		{"tailscale.switchProfile", nil, ""},
		{"tailscale.removeProfile", nil, "profile id is required"},
		{"tailscale.removeProfile", map[string]any{"id": 5}, "profile id is required"},
		{"tailscale.removeProfile", map[string]any{"id": "a"}, "current account"},
	} {
		resp := callHandler[map[string]any](t, m, tc.method, tc.params)
		assert.Nil(t, resp.Result)
		assert.Contains(t, resp.Error, tc.want)
		assert.NotEmpty(t, resp.Error)
	}
	assert.Empty(t, client.deleted)
}

func TestHandleGrantOperator(t *testing.T) {
	denied, code := true, 126
	m := newManager(&mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		profileStatusFn: func(ctx context.Context) (loginProfile, []loginProfile, error) {
			if denied {
				return loginProfile{}, nil, errAccessDenied
			}
			return loginProfile{ID: "a"}, []loginProfile{{ID: "a"}}, nil
		},
	})
	defer m.Close()

	oldLook, oldUser, oldRun, oldStat := operatorLookPath, operatorCurrentUser, operatorRunner, operatorStat
	t.Cleanup(func() {
		operatorLookPath, operatorCurrentUser, operatorRunner, operatorStat = oldLook, oldUser, oldRun, oldStat
	})
	var got []string
	entered, release := make(chan struct{}), make(chan struct{})
	operatorStat = rootStat
	operatorLookPath = func(n string) (string, error) { return "/usr/bin/" + n, nil }
	operatorCurrentUser = func() (*user.User, error) { return &user.User{Username: "tester"}, nil }
	operatorRunner = func(ctx context.Context, argv []string) ([]byte, int, error) {
		got = argv
		if code == 126 {
			close(entered)
			<-release
		}
		return nil, code, nil
	}

	resp := callHandler[ProfilesResult](t, m, "tailscale.profiles", nil)
	assert.False(t, resp.Result.CanOperate)
	assert.True(t, resp.Result.GrantAvailable)

	// Request params must not reach the command; a second request waits out the first.
	first := make(chan string)
	go func() {
		first <- callHandler[ProfilesResult](t, m, "tailscale.grantOperator", map[string]any{"user": "root"}).Error
	}()
	<-entered
	assert.Equal(t, "a permission request is already open", callHandler[ProfilesResult](t, m, "tailscale.grantOperator", nil).Error)
	close(release)
	assert.Equal(t, "permission not granted", <-first)
	assert.Equal(t, []string{"/usr/bin/pkexec", "/usr/bin/tailscale", "set", "--operator=tester"}, got)

	code, denied = 0, false
	resp = callHandler[ProfilesResult](t, m, "tailscale.grantOperator", nil)
	require.Empty(t, resp.Error)
	assert.True(t, resp.Result.CanOperate)
}

func TestHandleAddProfile(t *testing.T) {
	oldLook, oldUser, oldRun, oldStat := operatorLookPath, operatorCurrentUser, operatorRunner, operatorStat
	t.Cleanup(func() {
		operatorLookPath, operatorCurrentUser, operatorRunner, operatorStat = oldLook, oldUser, oldRun, oldStat
	})
	operatorStat = rootStat
	operatorLookPath = func(n string) (string, error) { return "/usr/bin/" + n, nil }
	operatorCurrentUser = func() (*user.User, error) { return &user.User{Username: "tester"}, nil }

	for name, tc := range map[string]struct {
		server    any
		code      int
		out       string
		fromEmpty bool
		after     string
		denied    bool
		want      string
		logins    int
		noCalls   bool
	}{
		"cancelled":       {code: 126, want: "permission not granted"},
		"same profile":    {code: 1, after: "a", want: "tailscale login failed: cli says no"},
		"left without op": {code: 1, denied: true, want: "tailscale login failed: cli says no"},
		"new empty":       {code: 1, after: "", logins: 1},
		"already in":      {code: 0, after: "b"},
		"invalid server":  {server: "https://u:p@hs.lan", want: "login server", noCalls: true},
		"server not text": {server: 5, want: "invalid 'server' parameter", noCalls: true},
		"null server":     {server: "nil", want: "invalid 'server' parameter", noCalls: true},
		"empty to empty":  {fromEmpty: true, code: 1, after: "", want: "tailscale login failed: cli says no"},
		"empty, waited": {fromEmpty: true, code: 1, after: "", logins: 1,
			out: "timeout waiting for Tailscale service to enter a Running state; check health"},
	} {
		t.Run(name, func(t *testing.T) {
			var ran []string
			operatorRunner = func(ctx context.Context, argv []string) ([]byte, int, error) {
				ran = argv
				out := cmp.Or(tc.out, "cli says no\n")
				return []byte(out), tc.code, nil
			}
			calls := 0
			client := &mockClient{
				watchFn:  blockingWatch,
				statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
				profileStatusFn: func(ctx context.Context) (loginProfile, []loginProfile, error) {
					calls++
					if calls == 1 {
						if tc.fromEmpty {
							return loginProfile{}, nil, nil
						}
						return loginProfile{ID: "a"}, nil, nil
					}
					if tc.denied {
						return loginProfile{}, nil, errAccessDenied
					}
					return loginProfile{ID: tc.after}, nil, nil
				},
			}
			m := newManager(client)
			defer m.Close()

			params := map[string]any{}
			switch tc.server {
			case nil:
			case "nil":
				params["server"] = nil
			default:
				params["server"] = tc.server
			}
			resp := callHandler[models.SuccessResult](t, m, "tailscale.addProfile", params)
			if tc.want != "" {
				assert.Contains(t, resp.Error, tc.want)
			} else {
				require.Empty(t, resp.Error)
				assert.True(t, resp.Result.Success)
			}
			assert.Equal(t, tc.logins, client.logins)
			if tc.noCalls {
				assert.Nil(t, ran)
				assert.Zero(t, calls)
			} else {
				assert.Equal(t, "--login-server="+defaultLoginServer, ran[4])
			}
		})
	}
}
