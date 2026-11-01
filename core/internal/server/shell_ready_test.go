package server

import (
	"context"
	"encoding/json"
	"os"
	"testing"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/duxlabs-dev/dux-shell/core/internal/systemd"
	"github.com/stretchr/testify/require"
)

func TestShellReadyAcknowledgesUIBeforeServices(t *testing.T) {
	t.Setenv("NOTIFY_SOCKET", "/nonexistent/notify")
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent")
	mux := newRequestMux(systemd.NewReadiness())
	for range 2 {
		response := callShellReady(t, mux, os.Getpid())
		require.Empty(t, response.Error)
		require.NotNil(t, response.Result)
		require.True(t, response.Result.Success)
	}
}

func TestShellReadyRejectsInvalidPID(t *testing.T) {
	mux := newRequestMux(systemd.NewReadiness())
	for _, pid := range []int{0, -1, 1 << 32} {
		response := callShellReady(t, mux, pid)
		require.Equal(t, "invalid shell pid", response.Error)
		require.Nil(t, response.Result)
	}
}

func callShellReady(t *testing.T, mux *ipc.Mux, pid int) ipc.Response[models.SuccessResult] {
	t.Helper()
	conn := &mockConn{}
	mux.ServeIPC(context.Background(), ipc.NewConnWriter(conn), ipc.Request{
		ID: 42, Method: "shell.ready", Params: map[string]any{"pid": float64(pid)},
	}, nil)
	var response ipc.Response[models.SuccessResult]
	require.NoError(t, json.Unmarshal(conn.written, &response))
	return response
}
