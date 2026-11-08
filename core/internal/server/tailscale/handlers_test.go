package tailscale

import (
	"bytes"
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
	conn := ipc.NewConnWriter(&mockConn{Buffer: buf})
	HandleRequest(conn, ipc.Request{ID: 1, Method: method, Params: params}, m)
	var resp ipc.Response[T]
	require.NoError(t, json.NewDecoder(buf).Decode(&resp))
	return resp
}

func fakeOperatorEnv(t *testing.T, found map[string]string, runner commandRunner) {
	t.Helper()
	oldLook, oldUser, oldRun, oldStat := operatorLookPath, operatorCurrentUser, operatorRunner, operatorStat
	t.Cleanup(func() {
		operatorLookPath, operatorCurrentUser, operatorRunner, operatorStat = oldLook, oldUser, oldRun, oldStat
	})
	operatorStat = fakeStat(nil)
	operatorLookPath = func(name string) (string, error) {
		if p, ok := found[name]; ok {
			return p, nil
		}
		return "", fmt.Errorf("%s not found", name)
	}
	operatorCurrentUser = func() (*user.User, error) { return &user.User{Username: "tester"}, nil }
	operatorRunner = runner
}

func TestHandleSetPrefs(t *testing.T) {
	var captured *maskedPrefs
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		getPrefsFn: func(ctx context.Context) (*prefs, error) {
			return &prefs{}, nil
		},
		editPrefsFn: func(ctx context.Context, mp *maskedPrefs) error {
			captured = mp
			return nil
		},
		checkIPFwdFn: func(ctx context.Context) error { return fmt.Errorf("IP forwarding is disabled") },
	}
	m := newManager(client)
	defer m.Close()

	resp := callHandler[map[string]any](t, m, "tailscale.setPrefs", map[string]any{
		"acceptDns":       false,
		"advertiseRoutes": []any{"10.0.0.0/8"},
	})
	require.Empty(t, resp.Error)
	require.NotNil(t, captured)
	assert.True(t, captured.CorpDNSSet)
	assert.False(t, captured.RouteAllSet)
	assert.Equal(t, prefixes("10.0.0.0/8"), captured.AdvertiseRoutes)
	assert.Equal(t, true, (*resp.Result)["success"])
	assert.Equal(t, "IP forwarding is disabled", (*resp.Result)["warning"])

	resp = callHandler[map[string]any](t, m, "tailscale.setPrefs", map[string]any{})
	assert.Contains(t, resp.Error, "no changes")

	resp = callHandler[map[string]any](t, m, "tailscale.setPrefs", map[string]any{"advertiseRoutes": []any{1}})
	assert.Equal(t, "advertiseRoutes must be a list of strings", resp.Error)

	captured = nil
	for key, bad := range map[string]any{
		"acceptRoutes":      "yes",
		"acceptDns":         1,
		"shieldsUp":         "true",
		"runSsh":            nil,
		"advertiseExitNode": []any{},
		"hostname":          false,
		"advertiseRoutes":   "10.0.0.0/8",
	} {
		resp = callHandler[map[string]any](t, m, "tailscale.setPrefs", map[string]any{"acceptDns": true, key: bad})
		assert.Equal(t, "invalid '"+key+"' parameter", resp.Error, key)
	}
	assert.Nil(t, captured)
}

func TestHandleGrantOperator(t *testing.T) {
	denied := true
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		profileStatusFn: func(ctx context.Context) (loginProfile, []loginProfile, error) {
			if denied {
				return loginProfile{}, nil, errAccessDenied
			}
			return loginProfile{ID: "a"}, []loginProfile{{ID: "a"}}, nil
		},
	}
	m := newManager(client)
	defer m.Close()

	var got []string
	code := 126
	fakeOperatorEnv(t, map[string]string{"pkexec": "/usr/bin/pkexec", "tailscale": "/usr/bin/tailscale"},
		func(ctx context.Context, argv []string) ([]byte, int, error) {
			got = argv
			return nil, code, nil
		})

	// Request params must not influence the command.
	resp := callHandler[ProfilesResult](t, m, "tailscale.grantOperator", map[string]any{"user": "root", "argv": []any{"sh"}})
	assert.Contains(t, resp.Error, "permission not granted")
	assert.Equal(t, []string{"/usr/bin/pkexec", "/usr/bin/tailscale", "set", "--operator=tester"}, got)

	code, denied = 0, false
	resp = callHandler[ProfilesResult](t, m, "tailscale.grantOperator", nil)
	require.Empty(t, resp.Error)
	require.NotNil(t, resp.Result)
	assert.True(t, resp.Result.CanOperate)
	assert.False(t, resp.Result.GrantAvailable)
}

func TestHandleGrantOperator_UsesManagerContext(t *testing.T) {
	m := newManager(&mockClient{watchFn: blockingWatch, statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil }})
	m.Close()

	var ctxErr error
	fakeOperatorEnv(t, map[string]string{"pkexec": "/usr/bin/pkexec", "tailscale": "/usr/bin/tailscale"},
		func(ctx context.Context, argv []string) ([]byte, int, error) {
			ctxErr = ctx.Err()
			return nil, 0, nil
		})
	callHandler[ProfilesResult](t, m, "tailscale.grantOperator", nil)
	assert.ErrorIs(t, ctxErr, context.Canceled)
}

func TestHandleGrantOperator_RejectsConcurrentRequest(t *testing.T) {
	m := newManager(&mockClient{watchFn: blockingWatch, statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil }})
	defer m.Close()

	entered, release := make(chan struct{}), make(chan struct{})
	fakeOperatorEnv(t, map[string]string{"pkexec": "/usr/bin/pkexec", "tailscale": "/usr/bin/tailscale"},
		func(ctx context.Context, argv []string) ([]byte, int, error) {
			close(entered)
			<-release
			return nil, 126, nil
		})

	first := make(chan string)
	go func() {
		buf := &bytes.Buffer{}
		HandleRequest(ipc.NewConnWriter(&mockConn{Buffer: buf}), ipc.Request{ID: 1, Method: "tailscale.grantOperator"}, m)
		first <- buf.String()
	}()
	<-entered

	resp := callHandler[ProfilesResult](t, m, "tailscale.grantOperator", nil)
	assert.Equal(t, "a permission request is already open", resp.Error)

	close(release)
	assert.Contains(t, <-first, "permission not granted")
}

func TestHandleProfiles_GrantAvailable(t *testing.T) {
	client := &mockClient{
		watchFn:  blockingWatch,
		statusFn: func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		profileStatusFn: func(ctx context.Context) (loginProfile, []loginProfile, error) {
			return loginProfile{}, nil, errAccessDenied
		},
	}
	m := newManager(client)
	defer m.Close()

	fakeOperatorEnv(t, map[string]string{"pkexec": "/usr/bin/pkexec", "tailscale": "/usr/bin/tailscale"}, nil)
	resp := callHandler[ProfilesResult](t, m, "tailscale.profiles", nil)
	require.Empty(t, resp.Error)
	assert.False(t, resp.Result.CanOperate)
	assert.True(t, resp.Result.GrantAvailable)

	fakeOperatorEnv(t, map[string]string{"tailscale": "/usr/bin/tailscale"}, nil)
	resp = callHandler[ProfilesResult](t, m, "tailscale.profiles", nil)
	assert.False(t, resp.Result.GrantAvailable)
}

func TestHandleAccountMethods(t *testing.T) {
	var switched string
	client := &mockClient{
		watchFn:         blockingWatch,
		statusFn:        func(ctx context.Context) (*ipnstate.Status, error) { return runningStatus(), nil },
		switchProfileFn: func(ctx context.Context, id string) error { switched = id; return nil },
		startLoginFn:    func(ctx context.Context) error { return nil },
		suggestFn: func(ctx context.Context) (ExitNodeSuggestion, error) {
			return ExitNodeSuggestion{ID: "n1", Name: "node"}, nil
		},
	}
	m := newManager(client)
	defer m.Close()

	for _, method := range []string{"tailscale.login", "tailscale.logout", "tailscale.addProfile"} {
		resp := callHandler[models.SuccessResult](t, m, method, nil)
		assert.Empty(t, resp.Error, method)
		assert.True(t, resp.Result.Success, method)
	}

	resp := callHandler[models.SuccessResult](t, m, "tailscale.switchProfile", map[string]any{"id": "p2"})
	assert.Empty(t, resp.Error)
	assert.Equal(t, "p2", switched)

	resp = callHandler[models.SuccessResult](t, m, "tailscale.switchProfile", nil)
	assert.NotEmpty(t, resp.Error)

	sug := callHandler[ExitNodeSuggestion](t, m, "tailscale.suggestExitNode", nil)
	require.Empty(t, sug.Error)
	assert.Equal(t, ExitNodeSuggestion{ID: "n1", Name: "node"}, *sug.Result)
}
