package models

import (
	"bufio"
	"encoding/json"
	"net"
	"testing"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/pubsub"
	"github.com/stretchr/testify/require"
)

type stubManager struct {
	broker pubsub.Broker[int]
	state  int
}

func (m *stubManager) Subscribe(id string) chan int       { return m.broker.Subscribe(id) }
func (m *stubManager) Unsubscribe(id string, ch chan int) { m.broker.Unsubscribe(id, ch) }
func (m *stubManager) GetState() int                      { return m.state }

func TestStreamMappedSubscription_IncludeIDAndUnsubscribe(t *testing.T) {
	mgr := &stubManager{state: 10}
	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()

	writer := ipc.NewConnWriter(serverConn)
	done := make(chan struct{})
	go func() {
		defer close(done)
		StreamMappedSubscription(writer, ipc.Request{ID: 7}, mgr, "c1", true, func(v int) int {
			return v * 2
		})
	}()

	reader := bufio.NewReader(clientConn)
	readResp := func() ipc.Response[int] {
		line, err := reader.ReadBytes('\n')
		require.NoError(t, err)
		var resp ipc.Response[int]
		require.NoError(t, json.Unmarshal(line, &resp))
		return resp
	}

	first := readResp()
	require.Equal(t, 7, first.ID)
	require.NotNil(t, first.Result)
	require.Equal(t, 20, *first.Result)

	mgr.broker.Publish(15)
	second := readResp()
	require.Equal(t, 7, second.ID)
	require.NotNil(t, second.Result)
	require.Equal(t, 30, *second.Result)

	mgr.broker.Close()
	<-done
	require.Equal(t, 0, mgr.broker.Len())
}

func TestStreamSubscription_OmitsStreamID(t *testing.T) {
	mgr := &stubManager{state: 1}
	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()

	writer := ipc.NewConnWriter(serverConn)
	done := make(chan struct{})
	go func() {
		defer close(done)
		StreamSubscription(writer, ipc.Request{ID: 9}, mgr, "c1", false)
	}()

	reader := bufio.NewReader(clientConn)
	readResp := func() ipc.Response[int] {
		line, err := reader.ReadBytes('\n')
		require.NoError(t, err)
		var resp ipc.Response[int]
		require.NoError(t, json.Unmarshal(line, &resp))
		return resp
	}

	first := readResp()
	require.Equal(t, 9, first.ID)
	require.Equal(t, 1, *first.Result)

	mgr.broker.Publish(2)
	second := readResp()
	require.Equal(t, 0, second.ID)
	require.Equal(t, 2, *second.Result)

	mgr.broker.Close()
	<-done
}
