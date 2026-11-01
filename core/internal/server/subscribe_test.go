package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"testing"
	"testing/synctest"
	"time"

	"github.com/duxlabs-dev/dux-go/files"
	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/apppicker"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wlroutput"
	"github.com/stretchr/testify/require"
)

func TestSubscribeStreams(t *testing.T) {
	for _, snapshot := range []bool{false, true} {
		t.Run(fmt.Sprintf("snapshot=%t", snapshot), func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				originalPicker, originalOutput := appPickerManager, wlrOutputManager
				appPickerManager = apppicker.NewManager()
				wlrOutputManager = &wlroutput.Manager{}
				defer func() {
					appPickerManager.Close()
					appPickerManager, wlrOutputManager = originalPicker, originalOutput
				}()

				services := []any{"browser", 123, "unavailable"}
				if snapshot {
					services = append(services, "wlroutput")
				}
				serverConn, clientConn := net.Pipe()
				defer serverConn.Close()
				defer clientConn.Close()
				writer := ipc.NewConnWriter(serverConn)
				done := make(chan struct{})
				go func() {
					defer close(done)
					handleSubscribe(context.Background(), writer, ipc.Request{ID: 24, Params: map[string]any{"services": services}})
				}()

				decoder := json.NewDecoder(clientConn)
				readEvent := func(service string, expected any) {
					t.Helper()
					var response ipc.Response[struct {
						Service string          `json:"service"`
						Data    json.RawMessage `json:"data"`
					}]
					require.NoError(t, decoder.Decode(&response))
					require.Equal(t, 24, response.ID)
					require.Empty(t, response.Error)
					require.NotNil(t, response.Result)
					require.Equal(t, service, response.Result.Service)
					data, err := json.Marshal(expected)
					require.NoError(t, err)
					require.JSONEq(t, string(data), string(response.Result.Data))
				}

				readEvent("server", getServerInfo())
				if snapshot {
					readEvent("wlroutput", wlrOutputManager.GetState())
				}
				event := apppicker.OpenEvent{Target: "https://example.com", RequestType: "url"}
				appPickerManager.RequestOpen(event)
				readEvent("browser.open_requested", event)

				notifyCapabilityChange()
				readEvent("server", getServerInfo())
				require.NoError(t, clientConn.Close())
				appPickerManager.RequestOpen(event)
				<-done
				synctest.Wait()
				_, subscribed := capabilitySubscribers.Load(fmt.Sprintf("meta-client-%p-capabilities", writer))
				require.False(t, subscribed)
			})
		})
	}
}

func TestSubscribeInitialWriteFailure(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		serverConn, clientConn := net.Pipe()
		defer serverConn.Close()
		require.NoError(t, clientConn.Close())
		writer := ipc.NewConnWriter(serverConn)
		handleSubscribe(context.Background(), writer, ipc.Request{Params: map[string]any{"services": []any{"unavailable"}}})
		synctest.Wait()
		_, subscribed := capabilitySubscribers.Load(fmt.Sprintf("meta-client-%p-capabilities", writer))
		require.False(t, subscribed)
	})
}

func TestSubscribeFilesDeliversWatchBatches(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		original := filesService
		filesService = files.NewService(&filesEvents, t.TempDir(), nil)
		defer func() {
			filesService.Close()
			filesService = original
		}()

		type stream struct {
			conn    net.Conn
			decoder *json.Decoder
			cancel  context.CancelFunc
			done    chan struct{}
		}
		subscribe := func(services ...any) stream {
			serverConn, clientConn := net.Pipe()
			ctx, cancel := context.WithCancel(context.Background())
			s := stream{conn: clientConn, decoder: json.NewDecoder(clientConn), cancel: cancel, done: make(chan struct{})}
			go func() {
				defer close(s.done)
				defer serverConn.Close()
				handleSubscribe(ctx, ipc.NewConnWriter(serverConn), ipc.Request{ID: 25, Params: map[string]any{"services": services}})
			}()
			var first ipc.Response[ServiceEvent]
			require.NoError(t, s.decoder.Decode(&first))
			require.Equal(t, "server", first.Result.Service)
			return s
		}
		next := func(s stream) (ipc.Response[json.RawMessage], error) {
			require.NoError(t, s.conn.SetReadDeadline(time.Now().Add(time.Second)))
			var response ipc.Response[json.RawMessage]
			return response, s.decoder.Decode(&response)
		}

		subscriber := subscribe("browser", "files")
		bystander := subscribe("browser")

		payload := map[string]any{"watchId": "w1", "kind": "batch", "seq": float64(1), "removed": []any{"old.txt"}}
		filesEvents.Publish("files:w1", payload)
		filesEvents.Publish("sizes", map[string]any{"scanId": "s1", "done": true})

		response, err := next(subscriber)
		require.NoError(t, err)
		require.Equal(t, 25, response.ID)
		require.JSONEq(t, `{"service":"files","data":{"watchId":"w1","kind":"batch","seq":1,"removed":["old.txt"]}}`, string(*response.Result))

		_, err = next(subscriber)
		require.True(t, errors.Is(err, os.ErrDeadlineExceeded), "the sizes topic is not forwarded, got %v", err)
		_, err = next(bystander)
		require.True(t, errors.Is(err, os.ErrDeadlineExceeded), "a client without the files service gets no batches, got %v", err)

		for _, s := range []stream{subscriber, bystander} {
			s.cancel()
			<-s.done
			require.NoError(t, s.conn.Close())
		}
		synctest.Wait()
		subscribers := 0
		filesEvents.subscribers.Range(func(string, chan any) bool {
			subscribers++
			return true
		})
		require.Zero(t, subscribers, "no channel outlives its subscription")
	})
}
