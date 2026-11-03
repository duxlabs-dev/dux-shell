package netfetch

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestTransportIsSharedPerDialShape(t *testing.T) {
	plain := Options{Timeout: time.Second}
	require.Same(t, transportFor(plain), transportFor(plain))
	require.Same(t, transportFor(plain), transportFor(Options{Timeout: time.Minute}))
	require.NotSame(t, transportFor(plain), transportFor(Options{ConnectTimeout: 3 * time.Second}))
	require.NotSame(t, transportFor(plain), transportFor(Options{IPv4Only: true}))
	require.NotZero(t, transportFor(plain).IdleConnTimeout)
}

func TestRepeatedFetchesReuseOneConnection(t *testing.T) {
	var mu sync.Mutex
	var conns []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		conns = append(conns, r.RemoteAddr)
		mu.Unlock()
		w.Write([]byte("ok"))
	}))
	defer server.Close()

	opts := Options{ConnectTimeout: 2 * time.Second, Timeout: 5 * time.Second}
	for range 3 {
		_, err := Bytes(context.Background(), server.URL, opts)
		require.NoError(t, err)
	}

	require.Len(t, conns, 3)
	require.Equal(t, conns[0], conns[1])
	require.Equal(t, conns[0], conns[2])
}

func TestBytesConditionalMaxBytes(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(make([]byte, 2048))
	}))
	defer server.Close()

	_, err := BytesConditional(context.Background(), server.URL, "", Options{Timeout: 5 * time.Second, MaxBytes: 1024})
	require.Error(t, err)

	res, err := BytesConditional(context.Background(), server.URL, "", Options{Timeout: 5 * time.Second, MaxBytes: 4096})
	require.NoError(t, err)
	require.Len(t, res.Body, 2048)
}
