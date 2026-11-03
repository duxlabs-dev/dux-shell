package evdev

import (
	"bytes"
	"encoding/json"
	"errors"
	"net"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/duxlabs-dev/dux-go/ipc"
	mocks "github.com/duxlabs-dev/dux-shell/core/internal/mocks/evdev"
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

func TestHandleRequest(t *testing.T) {
	t.Run("getState request", func(t *testing.T) {
		mockDevice := mocks.NewMockEvdevDevice(t)
		mockDevice.EXPECT().ReadOne().Return(nil, errors.New("test")).Maybe()

		m := &Manager{
			devices:   []EvdevDevice{mockDevice},
			state:     State{Available: true, CapsLock: true},
			closeChan: make(chan struct{}),
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     123,
			Method: "evdev.getState",
			Params: map[string]any{},
		}

		HandleRequest(conn, req, m)

		var resp ipc.Response[State]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 123, resp.ID)
		assert.NotNil(t, resp.Result)
		assert.True(t, resp.Result.Available)
		assert.True(t, resp.Result.CapsLock)
	})

	t.Run("unknown method", func(t *testing.T) {
		mockDevice := mocks.NewMockEvdevDevice(t)
		mockDevice.EXPECT().ReadOne().Return(nil, errors.New("test")).Maybe()

		m := &Manager{
			devices:   []EvdevDevice{mockDevice},
			state:     State{Available: true, CapsLock: false},
			closeChan: make(chan struct{}),
		}

		mc := newMockNetConn()
		conn := ipc.NewConnWriter(mc)
		req := ipc.Request{
			ID:     456,
			Method: "evdev.unknownMethod",
			Params: map[string]any{},
		}

		HandleRequest(conn, req, m)

		var resp ipc.Response[any]
		err := json.NewDecoder(mc.writeBuf).Decode(&resp)
		require.NoError(t, err)

		assert.Equal(t, 456, resp.ID)
		assert.NotEmpty(t, resp.Error)
		assert.Contains(t, resp.Error, "unknown method")
	})
}
