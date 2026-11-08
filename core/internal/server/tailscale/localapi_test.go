package tailscale

import (
	"context"
	"io"
	"net"
	"net/http"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLocalClient_Wire(t *testing.T) {
	type call struct {
		method, uri, body string
	}
	calls := make(chan call, 3)
	mux := http.NewServeMux()
	mux.HandleFunc("/localapi/v0/", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		calls <- call{r.Method, r.URL.RequestURI(), string(body)}
		switch r.URL.Path {
		case "/localapi/v0/status":
			io.WriteString(w, `{"BackendState":"Running","Version":"1.94.2"}`)
		case "/localapi/v0/prefs":
			io.WriteString(w, `{"ExitNodeAllowLANAccess":true}`)
		case "/localapi/v0/watch-ipn-bus":
			io.WriteString(w, "{\"Version\":\"a\"}\n{\"Version\":\"b\"}\n")
		}
	})
	sock := filepath.Join(t.TempDir(), "ts.sock")
	ln, err := net.Listen("unix", sock)
	require.NoError(t, err)
	srv := &http.Server{Handler: mux}
	go srv.Serve(ln)
	defer srv.Close()

	c := newLocalClient(sock)
	ctx := context.Background()

	status, err := c.Status(ctx)
	require.NoError(t, err)
	assert.Equal(t, "Running", status.BackendState)
	assert.Equal(t, call{"GET", "/localapi/v0/status", ""}, <-calls)

	p, err := c.GetPrefs(ctx)
	require.NoError(t, err)
	assert.True(t, p.ExitNodeAllowLANAccess)
	<-calls

	require.NoError(t, c.EditPrefs(ctx, &maskedPrefs{ExitNodeIDSet: true, ExitNodeIPSet: true}))
	assert.Equal(t, call{"PATCH", "/localapi/v0/prefs", `{"ExitNodeIDSet":true,"ExitNodeIPSet":true}`}, <-calls)

	w, err := c.WatchIPNBus(ctx, notifyInitialState|notifyPeerPatches)
	require.NoError(t, err)
	defer w.Close()
	assert.Equal(t, call{"GET", "/localapi/v0/watch-ipn-bus?mask=32770", ""}, <-calls)
	for range 2 {
		_, err = w.Next()
		require.NoError(t, err)
	}
	_, err = w.Next()
	assert.Error(t, err)
}

func TestLocalClient_ErrorBody(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/localapi/v0/prefs", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		io.WriteString(w, `{"error":"invalid exit node"}`)
	})
	sock := filepath.Join(t.TempDir(), "ts.sock")
	ln, err := net.Listen("unix", sock)
	require.NoError(t, err)
	srv := &http.Server{Handler: mux}
	go srv.Serve(ln)
	defer srv.Close()

	err = newLocalClient(sock).EditPrefs(context.Background(), &maskedPrefs{})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "invalid exit node")
}
