package server

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/files"
	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/apppicker"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/clipboard"
	"github.com/stretchr/testify/require"
)

func TestRouteRequestUnavailableManagers(t *testing.T) {
	tests := []struct {
		method string
		err    string
	}{
		{"network.getState", "network manager not initialized"},
		{"theme.auto.getState", "theme mode manager not initialized"},
		{"wallpaper.getState", "wallpaper manager not initialized"},
		{"loginctl.getState", "loginctl manager not initialized"},
		{"freedesktop.getState", "freedesktop manager not initialized"},
		{"wayland.gamma.getState", "wayland manager not initialized"},
		{"bluetooth.getState", "bluetooth manager not initialized"},
		{"browser.open", "apppicker manager not initialized"},
		{"apppicker.open", "apppicker manager not initialized"},
		{"tailscale.getState", "Tailscale not available"},
		{"brightness.getState", "brightness manager not initialized"},
		{"wlroutput.getState", "wlroutput manager not initialized"},
		{"evdev.getState", "evdev manager not initialized"},
		{"dbus.subscribe", "dbus manager not initialized"},
		{"clipboard.getState", "clipboard manager not initialized"},
		{"location.getState", "location manager not initialized"},
		{"wellbeing.getState", "wellbeing manager not initialized"},
		{"notify.invoke", "notification action manager not initialized"},
		{"sysupdate.getState", "sysupdate manager not initialized"},
		{"files.list", "files service not initialized"},
	}
	for _, tt := range tests {
		t.Run(tt.method, func(t *testing.T) {
			conn := &mockConn{}
			RouteRequest(context.Background(), ipc.NewConnWriter(conn), ipc.Request{ID: 17, Method: tt.method})
			require.JSONEq(t, `{"id":17,"error":"`+tt.err+`"}`, string(conn.written))
		})
	}
}

func TestRouteRequestUnknownMethods(t *testing.T) {
	for _, method := range []string{"", "missing", "network", "networking.getState", "theme.auto", "matugen.missing", "plugins.missing", "themes.missing", "registries.missing", "mime.missing", "dgop.missing", "drives.missing", "lyrics.missing"} {
		t.Run(method, func(t *testing.T) {
			conn := &mockConn{}
			RouteRequest(context.Background(), ipc.NewConnWriter(conn), ipc.Request{ID: 18, Method: method})
			require.JSONEq(t, `{"id":18,"error":"unknown method: `+method+`"}`, string(conn.written))
		})
	}
}

func TestRouteRequestExactMethods(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	conn := &mockConn{}
	writer := ipc.NewConnWriter(conn)
	RouteRequest(context.Background(), writer, ipc.Request{Method: "ping"})
	require.JSONEq(t, `{"result":"pong"}`, string(conn.written))

	conn.written = nil
	RouteRequest(context.Background(), writer, ipc.Request{ID: 19, Method: "getServerInfo"})
	var info ipc.Response[ServerInfo]
	require.NoError(t, json.Unmarshal(conn.written, &info))
	require.Equal(t, 19, info.ID)
	require.NotNil(t, info.Result)
	require.Equal(t, getServerInfo(), *info.Result)

	conn.written = nil
	RouteRequest(context.Background(), writer, ipc.Request{ID: 20, Method: "clipboard.setConfig", Params: map[string]any{"maxHistory": float64(42)}})
	require.JSONEq(t, `{"id":20,"result":{"success":true,"message":"config updated"}}`, string(conn.written))

	conn.written = nil
	RouteRequest(context.Background(), writer, ipc.Request{ID: 21, Method: "clipboard.getConfig"})
	var config ipc.Response[clipboard.Config]
	require.NoError(t, json.Unmarshal(conn.written, &config))
	require.Equal(t, 21, config.ID)
	require.NotNil(t, config.Result)
	expected := clipboard.DefaultConfig()
	expected.MaxHistory = 42
	require.Equal(t, expected, *config.Result)
}

func TestRouteRequestBrowserAlias(t *testing.T) {
	original := appPickerManager
	appPickerManager = apppicker.NewManager()
	t.Cleanup(func() {
		appPickerManager.Close()
		appPickerManager = original
	})
	events := appPickerManager.Subscribe("route-test")
	for _, method := range []string{"browser.open", "apppicker.open"} {
		t.Run(method, func(t *testing.T) {
			conn := &mockConn{}
			RouteRequest(context.Background(), ipc.NewConnWriter(conn), ipc.Request{ID: 22, Method: method, Params: map[string]any{"url": "https://example.com"}})
			require.JSONEq(t, `{"id":22,"result":"ok"}`, string(conn.written))
			select {
			case event := <-events:
				require.Equal(t, apppicker.OpenEvent{Target: "https://example.com", RequestType: "url"}, event)
			default:
				t.Fatal("missing apppicker event")
			}
		})
	}
	conn := &mockConn{}
	RouteRequest(context.Background(), ipc.NewConnWriter(conn), ipc.Request{ID: 23, Method: "browser.missing"})
	require.JSONEq(t, `{"id":23,"error":"unknown method"}`, string(conn.written))
}

func useFilesService(t *testing.T) {
	t.Helper()
	original := filesService
	filesService = files.NewService(&filesEvents, t.TempDir(), nil)
	filesService.AttachOnOpen()
	t.Cleanup(func() {
		filesService.Close()
		filesService = original
	})
}

func TestRouteRequestFiles(t *testing.T) {
	useFilesService(t)
	root := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(root, "a.txt"), nil, 0o644))

	conn := &mockConn{}
	RouteRequest(context.Background(), ipc.NewConnWriter(conn), ipc.Request{ID: 24, Method: "files.list", Params: map[string]any{"path": root}})
	var listed ipc.Response[struct {
		Path    string           `json:"path"`
		Entries []map[string]any `json:"entries"`
	}]
	require.NoError(t, json.Unmarshal(conn.written, &listed))
	require.Equal(t, 24, listed.ID)
	require.NotNil(t, listed.Result)
	require.Equal(t, root, listed.Result.Path)
	require.Len(t, listed.Result.Entries, 1)
	require.Equal(t, "a.txt", listed.Result.Entries[0]["name"])

	conn.written = nil
	RouteRequest(context.Background(), ipc.NewConnWriter(conn), ipc.Request{ID: 25, Method: "files.missing"})
	require.JSONEq(t, `{"id":25,"error":"unknown files method: files.missing","code":"NOTSUPPORTED"}`, string(conn.written))
}

func TestFilesWatchLivesAsLongAsTheConnection(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	useFilesService(t)

	s := New()
	require.NoError(t, s.Listen())
	ctx, cancel := context.WithCancel(context.Background())
	served := make(chan error, 1)
	go func() { served <- s.ipc.Serve(ctx) }()
	t.Cleanup(func() {
		cancel()
		require.NoError(t, <-served)
	})

	conn, err := net.Dial("unix", s.SocketPath())
	require.NoError(t, err)
	defer conn.Close()
	require.NoError(t, conn.SetDeadline(time.Now().Add(5*time.Second)))
	decoder := json.NewDecoder(conn)

	var caps ipc.Capabilities
	require.NoError(t, decoder.Decode(&caps))
	require.Contains(t, caps.Capabilities, "files")

	require.NoError(t, json.NewEncoder(conn).Encode(ipc.Request{ID: 1, Method: "files.watch", Params: map[string]any{"path": t.TempDir()}}))
	var opened ipc.Response[struct {
		WatchID string `json:"watchId"`
	}]
	require.NoError(t, decoder.Decode(&opened))
	require.NotNil(t, opened.Result)
	watchID := opened.Result.WatchID
	require.NotEmpty(t, watchID)

	pageWatch := func() string {
		mc := &mockConn{}
		RouteRequest(context.Background(), ipc.NewConnWriter(mc), ipc.Request{ID: 2, Method: "files.list", Params: map[string]any{"watchId": watchID}})
		return string(mc.written)
	}
	require.Contains(t, pageWatch(), `"watchId":"`+watchID+`"`, "the watch outlives the request that opened it")

	require.NoError(t, conn.Close())
	require.Eventually(t, func() bool {
		return pageWatch() == `{"id":2,"error":"unknown watch: `+watchID+`","code":"EINVAL"}`+"\n"
	}, 5*time.Second, 10*time.Millisecond, "closing the connection closes its watches")
}

func BenchmarkRouteRequest(b *testing.B) {
	conn := &mockConn{}
	writer := ipc.NewConnWriter(conn)
	req := ipc.Request{ID: 1, Method: "ping"}
	b.ReportAllocs()
	for b.Loop() {
		conn.written = conn.written[:0]
		RouteRequest(context.Background(), writer, req)
	}
}

// Routing only: the no-network invariant itself is TestLookupWithoutConsentNeverFetches.
func TestRouteLyricsGetWithoutConsentStaysLocal(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	conn := &mockConn{}
	RouteRequest(context.Background(), ipc.NewConnWriter(conn), ipc.Request{ID: 19, Method: "lyrics.get", Params: map[string]any{
		"title":  "Snake Eater",
		"artist": "Cynthia Harrell",
	}})
	require.Contains(t, string(conn.written), `"found":false`)
}
