package server

import (
	"context"
	"encoding/json"
	"net"
	"testing"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/bluez"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/network"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetCapabilities(t *testing.T) {
	originalNetworkManager := networkManager
	defer func() { networkManager = originalNetworkManager }()

	t.Run("capabilities without network manager", func(t *testing.T) {
		networkManager = nil
		caps := getCapabilities()
		assert.NotContains(t, caps.Capabilities, "network")
	})

	t.Run("capabilities with network manager", func(t *testing.T) {
		networkManager = &network.Manager{}
		caps := getCapabilities()
		assert.Contains(t, caps.Capabilities, "network")
	})

	t.Run("niri capabilities from the probe", func(t *testing.T) {
		original := niriCapabilities
		defer func() { niriCapabilities = original }()
		niriCapabilities = func() []string { return []string{config.NiriCapBindsNext, config.NiriCapConfigNext} }
		caps := getCapabilities()
		assert.Contains(t, caps.Capabilities, "niri.binds-next")
		assert.Contains(t, caps.Capabilities, "niri.config-next")
	})
}

func TestCupsCapabilityIsSticky(t *testing.T) {
	originalEverAvailable := cupsEverAvailable
	originalSubscriberCount := cupsSubscriberCount
	defer func() {
		cupsEverAvailable = originalEverAvailable
		cupsSubscriberCount = originalSubscriberCount
	}()

	cupsEverAvailable = false
	assert.NotContains(t, getCapabilities().Capabilities, "cups")

	cupsEverAvailable = true
	cupsSubscriberCount = 1
	assert.Contains(t, getCapabilities().Capabilities, "cups")

	releaseCupsSubscriber()
	assert.Equal(t, 0, cupsSubscriberCount)
	assert.Contains(t, getCapabilities().Capabilities, "cups", "capability must survive the manager shutting down")

	releaseCupsSubscriber()
	assert.Equal(t, 0, cupsSubscriberCount, "release must not drive the subscriber count negative")
}

type mockConn struct {
	net.Conn
	written []byte
}

func (m *mockConn) Write(b []byte) (n int, err error) {
	m.written = append(m.written, b...)
	return len(b), nil
}

func (m *mockConn) Close() error {
	return nil
}

func (m *mockConn) SetWriteDeadline(t time.Time) error { return nil }

func TestExclusiveServiceRequiresExplicitSubscription(t *testing.T) {
	tests := []struct {
		name       string
		services   []string
		includeAll bool
		want       bool
	}{
		{name: "explicit", services: []string{"mpris.command"}, want: true},
		{name: "all excluded", services: []string{"all"}, want: false},
		{name: "regular service via all", services: []string{"all"}, includeAll: true, want: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service := "mpris.command"
			if tt.includeAll {
				service = "bluetooth"
			}
			assert.Equal(t, tt.want, serviceSubscribed(tt.services, service, tt.includeAll))
		})
	}
}

func TestSubscriptionCancellationPromotesMPRISWaiter(t *testing.T) {
	originalBluezManager := bluezManager
	manager := &bluez.Manager{}
	bluezManager = manager
	defer func() { bluezManager = originalBluezManager }()

	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()
	defer serverConn.Close()

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		handleSubscribe(ctx, ipc.NewConnWriter(serverConn), ipc.Request{
			ID:     42,
			Method: "subscribe",
			Params: map[string]any{"services": []any{"mpris.command"}},
		})
	}()

	require.NoError(t, clientConn.SetReadDeadline(time.Now().Add(2*time.Second)))
	decoder := json.NewDecoder(clientConn)
	var ownerLease string
	for ownerLease == "" {
		var response ipc.Response[ServiceEvent]
		require.NoError(t, decoder.Decode(&response))
		if response.Result == nil || response.Result.Service != "mpris.command" {
			continue
		}
		data, ok := response.Result.Data.(map[string]any)
		require.True(t, ok)
		ownerLease, _ = data["lease"].(string)
	}
	require.NotEmpty(t, ownerLease)

	waiter, err := manager.SubscribePlayerCommands("waiter")
	require.NoError(t, err)
	select {
	case event := <-waiter:
		t.Fatalf("waiting subscriber received unexpected event: %#v", event)
	default:
	}

	cancel()

	select {
	case event := <-waiter:
		require.NotEmpty(t, event.Lease)
		assert.NotEqual(t, ownerLease, event.Lease)
	case <-time.After(2 * time.Second):
		t.Fatal("waiting MPRIS subscriber was not promoted after connection cancellation")
	}
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("subscription handler did not stop after connection cancellation")
	}

	manager.UnsubscribePlayerCommands("waiter")
}
