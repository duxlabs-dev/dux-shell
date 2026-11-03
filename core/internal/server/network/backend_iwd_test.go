package network

import (
	"context"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
)

func TestIWDBackend_OnPromptRetry(t *testing.T) {
	backend, _ := NewIWDBackend()

	att := &connectAttempt{
		ssid:     "TestNetwork",
		netPath:  "/net/connman/iwd/0/1/test",
		start:    time.Now(),
		deadline: time.Now().Add(15 * time.Second),
	}

	backend.attemptMutex.Lock()
	backend.curAttempt = att
	backend.attemptMutex.Unlock()

	backend.OnPromptRetry("TestNetwork")

	att.mu.Lock()
	assert.True(t, att.sawPromptRetry, "sawPromptRetry should be true after OnPromptRetry")
	att.mu.Unlock()
}

func TestIWDBackend_OnPromptRetry_WrongSSID(t *testing.T) {
	backend, _ := NewIWDBackend()

	att := &connectAttempt{
		ssid:     "TestNetwork",
		netPath:  "/net/connman/iwd/0/1/test",
		start:    time.Now(),
		deadline: time.Now().Add(15 * time.Second),
	}

	backend.attemptMutex.Lock()
	backend.curAttempt = att
	backend.attemptMutex.Unlock()

	backend.OnPromptRetry("DifferentNetwork")

	att.mu.Lock()
	assert.False(t, att.sawPromptRetry, "sawPromptRetry should remain false for different SSID")
	att.mu.Unlock()
}

func TestIWDBackend_ClassifyAttempt_BadCredentials_PromptRetry(t *testing.T) {
	backend, _ := NewIWDBackend()

	att := &connectAttempt{
		ssid:           "TestNetwork",
		netPath:        "/test",
		start:          time.Now().Add(-5 * time.Second),
		deadline:       time.Now().Add(10 * time.Second),
		sawPromptRetry: true,
	}

	code := backend.classifyAttempt(att)
	assert.Equal(t, "bad-credentials", code)
}

func TestIWDBackend_ClassifyAttempt_DhcpTimeout(t *testing.T) {
	backend, _ := NewIWDBackend()

	att := &connectAttempt{
		ssid:        "TestNetwork",
		netPath:     "/test",
		start:       time.Now().Add(-13 * time.Second),
		deadline:    time.Now().Add(2 * time.Second),
		sawAuthish:  true,
		sawIPConfig: false,
	}

	code := backend.classifyAttempt(att)
	assert.Equal(t, "dhcp-timeout", code)
}

func TestIWDBackend_ClassifyAttempt_AssocTimeout(t *testing.T) {
	backend, _ := NewIWDBackend()

	att := &connectAttempt{
		ssid:     "TestNetwork",
		netPath:  "/test",
		start:    time.Now().Add(-5 * time.Second),
		deadline: time.Now().Add(10 * time.Second),
	}

	backend.recentScansMu.Lock()
	backend.recentScans["TestNetwork"] = time.Now()
	backend.recentScansMu.Unlock()

	code := backend.classifyAttempt(att)
	assert.Equal(t, "assoc-timeout", code)
}

func TestIWDBackend_ClassifyAttempt_NoSuchSSID(t *testing.T) {
	backend, _ := NewIWDBackend()

	att := &connectAttempt{
		ssid:     "TestNetwork",
		netPath:  "/test",
		start:    time.Now().Add(-5 * time.Second),
		deadline: time.Now().Add(10 * time.Second),
	}

	code := backend.classifyAttempt(att)
	assert.Equal(t, "no-such-ssid", code)
}

func TestIWDBackend_MapIwdDBusError(t *testing.T) {
	backend, _ := NewIWDBackend()

	testCases := []struct {
		name     string
		expected string
	}{
		{"net.connman.iwd.Error.AlreadyConnected", "already-connected"},
		{"net.connman.iwd.Error.AuthenticationFailed", "bad-credentials"},
		{"net.connman.iwd.Error.NotFound", "no-such-ssid"},
		{"net.connman.iwd.Error.NotSupported", "connection-failed"},
		{"net.connman.iwd.Agent.Error.Canceled", "user-canceled"},
		{"net.connman.iwd.Error.Unknown", "connection-failed"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			code := backend.mapIwdDBusError(tc.name)
			assert.Equal(t, tc.expected, code)
		})
	}
}

func TestIWDBackend_ApplyManagedObjects_DeviceWithoutStation(t *testing.T) {
	backend, _ := NewIWDBackend()

	err := backend.applyManagedObjects(map[dbus.ObjectPath]map[string]map[string]dbus.Variant{
		"/net/connman/iwd/0/1": {
			iwdDeviceInterface: {
				"Name":    dbus.MakeVariant("wlan0"),
				"Powered": dbus.MakeVariant(false),
			},
		},
	})

	assert.NoError(t, err)
	assert.Equal(t, dbus.ObjectPath("/net/connman/iwd/0/1"), backend.devicePath)
	assert.Empty(t, backend.stationPath)

	state, err := backend.GetCurrentState()
	assert.NoError(t, err)
	assert.Equal(t, "wlan0", state.WiFiDevice)
	assert.False(t, state.WiFiEnabled)
	assert.False(t, state.WiFiConnected)
}

func TestIWDBackend_ApplyManagedObjects_NoDevice(t *testing.T) {
	backend, _ := NewIWDBackend()

	err := backend.applyManagedObjects(map[dbus.ObjectPath]map[string]map[string]dbus.Variant{
		"/net/connman/iwd/0": {
			iwdAdapterInterface: {},
		},
	})

	assert.ErrorContains(t, err, "no WiFi device found")
}

func TestIWDSavedWiFiProfilesFromManagedObjects(t *testing.T) {
	objects := map[dbus.ObjectPath]map[string]map[string]dbus.Variant{
		"/net/connman/iwd/known_network/1": {
			iwdKnownNetworkInterface: {
				"Name":        dbus.MakeVariant("Home"),
				"AutoConnect": dbus.MakeVariant(false),
				"Hidden":      dbus.MakeVariant(true),
				"Type":        dbus.MakeVariant("psk"),
			},
		},
		"/net/connman/iwd/known_network/2": {
			iwdKnownNetworkInterface: {
				"Name": dbus.MakeVariant("Office"),
				"Type": dbus.MakeVariant("8021x"),
			},
		},
		"/net/connman/iwd/known_network/3": {
			iwdKnownNetworkInterface: {
				"Name": dbus.MakeVariant("Cafe"),
				"Type": dbus.MakeVariant("open"),
			},
		},
		"/net/connman/iwd/network/1": {
			iwdNetworkInterface: {
				"Name": dbus.MakeVariant("VisibleOnly"),
			},
		},
	}

	profiles := iwdSavedWiFiProfilesFromManagedObjects(objects)

	assert.Len(t, profiles, 3)
	assert.False(t, profiles["Home"].Autoconnect)
	assert.True(t, profiles["Home"].Hidden)
	assert.True(t, profiles["Home"].Secured)
	assert.False(t, profiles["Home"].Enterprise)

	assert.True(t, profiles["Office"].Autoconnect)
	assert.True(t, profiles["Office"].Secured)
	assert.True(t, profiles["Office"].Enterprise)

	assert.True(t, profiles["Cafe"].Autoconnect)
	assert.False(t, profiles["Cafe"].Secured)
	assert.False(t, profiles["Cafe"].Enterprise)
}

func TestIWDWiFiNetworksFromVisibleIncludesConnectedHiddenFallback(t *testing.T) {
	profiles := map[string]savedWiFiProfile{
		"Home": {
			Autoconnect: true,
			Secured:     true,
			Hidden:      true,
			Mode:        "infrastructure",
		},
	}
	visible := []WiFiNetwork{
		{
			SSID:    "Cafe",
			Signal:  42,
			Secured: false,
		},
	}

	networks := iwdWiFiNetworksFromVisible(visible, profiles, "Home", true, 68)
	savedNetworks := savedWiFiNetworksFromProfiles(profiles, map[string]WiFiNetwork{
		networks[0].SSID: networks[0],
		networks[1].SSID: networks[1],
	}, "Home", true)

	assert.Len(t, networks, 2)
	assert.Equal(t, "Cafe", networks[0].SSID)
	assert.False(t, networks[0].Connected)

	assert.Equal(t, "Home", networks[1].SSID)
	assert.True(t, networks[1].Connected)
	assert.True(t, networks[1].Hidden)
	assert.True(t, networks[1].Saved)
	assert.True(t, networks[1].Autoconnect)
	assert.Equal(t, uint8(68), networks[1].Signal)

	assert.Len(t, savedNetworks, 1)
	assert.Equal(t, "Home", savedNetworks[0].SSID)
	assert.True(t, savedNetworks[0].Connected)
	assert.False(t, savedNetworks[0].OutOfRange)
}

func TestConnectAttempt_Finalization(t *testing.T) {
	backend, _ := NewIWDBackend()
	backend.state = &BackendState{}

	att := &connectAttempt{
		ssid:     "TestNetwork",
		netPath:  "/test",
		start:    time.Now(),
		deadline: time.Now().Add(15 * time.Second),
	}

	backend.finalizeAttempt(att, "bad-credentials")

	att.mu.Lock()
	assert.True(t, att.finalized)
	att.mu.Unlock()

	backend.stateMutex.RLock()
	assert.False(t, backend.state.IsConnecting)
	assert.Empty(t, backend.state.ConnectingSSID)
	assert.Equal(t, "bad-credentials", backend.state.LastError)
	backend.stateMutex.RUnlock()
}

func TestIWDBackend_PendingPSK(t *testing.T) {
	backend, _ := NewIWDBackend()

	_, ok := backend.takePendingPSK("Home")
	assert.False(t, ok)

	backend.storePendingPSK("Home", "newpass")

	_, ok = backend.takePendingPSK("Other")
	assert.False(t, ok, "pending PSK should not match a different SSID")

	psk, ok := backend.takePendingPSK("Home")
	assert.True(t, ok)
	assert.Equal(t, "newpass", psk)

	_, ok = backend.takePendingPSK("Home")
	assert.False(t, ok, "pending PSK should be consumed on take")

	backend.storePendingPSK("Home", "newpass")
	backend.pendingPSKMu.Lock()
	backend.pendingPSK.expires = time.Now().Add(-time.Second)
	backend.pendingPSKMu.Unlock()

	_, ok = backend.takePendingPSK("Home")
	assert.False(t, ok, "expired pending PSK should not be returned")
}

type fakePromptBroker struct {
	asked    chan PromptRequest
	reply    PromptReply
	replyErr error
}

func (f *fakePromptBroker) Ask(ctx context.Context, req PromptRequest) (string, error) {
	f.asked <- req
	return "token", nil
}

func (f *fakePromptBroker) Wait(ctx context.Context, token string) (PromptReply, error) {
	return f.reply, f.replyErr
}

func (f *fakePromptBroker) Resolve(token string, reply PromptReply) error { return nil }

func (f *fakePromptBroker) Cancel(path string, setting string) error { return nil }

func TestIWDBackend_BadCredentialsSavedNetwork_PromptsReplacement(t *testing.T) {
	backend, _ := NewIWDBackend()
	backend.state = &BackendState{}
	broker := &fakePromptBroker{
		asked: make(chan PromptRequest, 1),
		reply: PromptReply{Cancel: true},
	}
	backend.promptBroker = broker

	att := &connectAttempt{
		ssid:     "Home",
		netPath:  "/test",
		saved:    true,
		start:    time.Now(),
		deadline: time.Now().Add(15 * time.Second),
	}

	backend.finalizeAttempt(att, "bad-credentials")

	select {
	case req := <-broker.asked:
		assert.Equal(t, "Home", req.SSID)
		assert.Equal(t, "wrong-password", req.Reason)
		assert.Equal(t, []string{"psk"}, req.Fields)
	case <-time.After(time.Second):
		t.Fatal("expected replacement credentials prompt for saved network")
	}
}

func TestIWDBackend_BadCredentialsUnsavedNetwork_NoReplacementPrompt(t *testing.T) {
	backend, _ := NewIWDBackend()
	backend.state = &BackendState{}
	broker := &fakePromptBroker{
		asked: make(chan PromptRequest, 1),
		reply: PromptReply{Cancel: true},
	}
	backend.promptBroker = broker

	att := &connectAttempt{
		ssid:     "Home",
		netPath:  "/test",
		start:    time.Now(),
		deadline: time.Now().Add(15 * time.Second),
	}

	backend.finalizeAttempt(att, "bad-credentials")
	backend.sigWG.Wait()

	assert.Empty(t, broker.asked, "unsaved network should not trigger a replacement prompt")
}

func TestIWDBackend_BadCredentialsAfterPromptRetry_NoReplacementPrompt(t *testing.T) {
	backend, _ := NewIWDBackend()
	backend.state = &BackendState{}
	broker := &fakePromptBroker{
		asked: make(chan PromptRequest, 1),
		reply: PromptReply{Cancel: true},
	}
	backend.promptBroker = broker

	att := &connectAttempt{
		ssid:           "Home",
		netPath:        "/test",
		saved:          true,
		sawPromptRetry: true,
		start:          time.Now(),
		deadline:       time.Now().Add(15 * time.Second),
	}

	backend.finalizeAttempt(att, "bad-credentials")
	backend.sigWG.Wait()

	assert.Empty(t, broker.asked, "attempt that already prompted should not trigger a replacement prompt")
}

func TestConnectAttempt_DoubleFinalization(t *testing.T) {
	backend, _ := NewIWDBackend()
	backend.state = &BackendState{}

	att := &connectAttempt{
		ssid:     "TestNetwork",
		netPath:  "/test",
		start:    time.Now(),
		deadline: time.Now().Add(15 * time.Second),
	}

	backend.finalizeAttempt(att, "bad-credentials")
	backend.finalizeAttempt(att, "dhcp-timeout")

	backend.stateMutex.RLock()
	assert.Equal(t, "bad-credentials", backend.state.LastError)
	backend.stateMutex.RUnlock()
}

func TestIWDBackend_SetDevice_FollowsRecreatedDevice(t *testing.T) {
	backend, _ := NewIWDBackend()
	err := backend.applyManagedObjects(map[dbus.ObjectPath]map[string]map[string]dbus.Variant{
		"/net/connman/iwd/0/3": {
			iwdDeviceInterface:  {"Name": dbus.MakeVariant("wlan0"), "Powered": dbus.MakeVariant(true)},
			iwdStationInterface: {},
		},
	})
	assert.NoError(t, err)

	// iwd restarts: the old objects go away and wlan0 comes back with a new ifindex.
	assert.True(t, backend.handleStationRemoved("/net/connman/iwd/0/3"))
	assert.True(t, backend.clearDevice("/net/connman/iwd/0/3"))

	prev, changed := backend.setDevice("/net/connman/iwd/0/7", map[string]dbus.Variant{
		"Name":    dbus.MakeVariant("wlan0"),
		"Powered": dbus.MakeVariant(true),
	})

	assert.True(t, changed)
	assert.Empty(t, prev)
	assert.Equal(t, dbus.ObjectPath("/net/connman/iwd/0/7"), backend.devicePath)

	enabled, _ := backend.GetWiFiEnabled()
	assert.True(t, enabled, "Wi-Fi must be enabled again once the recreated device reports Powered")
}

func TestIWDBackend_SetDevice_ReplacesPathWithoutRemovalSignal(t *testing.T) {
	backend, _ := NewIWDBackend()
	backend.devicePath = "/net/connman/iwd/0/3"

	prev, changed := backend.setDevice("/net/connman/iwd/0/7", map[string]dbus.Variant{
		"Powered": dbus.MakeVariant(true),
	})

	assert.True(t, changed)
	assert.Equal(t, dbus.ObjectPath("/net/connman/iwd/0/3"), prev)
	assert.Equal(t, dbus.ObjectPath("/net/connman/iwd/0/7"), backend.devicePath)
}

func TestIWDBackend_SetDevice_SamePathIsNoop(t *testing.T) {
	backend, _ := NewIWDBackend()
	backend.devicePath = "/net/connman/iwd/0/3"

	_, changed := backend.setDevice("/net/connman/iwd/0/3", map[string]dbus.Variant{
		"Powered": dbus.MakeVariant(false),
	})
	assert.False(t, changed)

	_, changed = backend.setDevice("", nil)
	assert.False(t, changed)
}

func TestIWDBackend_ClearDevice(t *testing.T) {
	backend, _ := NewIWDBackend()
	backend.devicePath = "/net/connman/iwd/0/3"

	assert.False(t, backend.clearDevice("/net/connman/iwd/0/9"), "unrelated path must be ignored")
	assert.Equal(t, dbus.ObjectPath("/net/connman/iwd/0/3"), backend.devicePath)

	assert.True(t, backend.clearDevice("/net/connman/iwd/0/3"))
	assert.Empty(t, backend.devicePath)

	enabled, _ := backend.GetWiFiEnabled()
	assert.False(t, enabled)
	assert.ErrorContains(t, backend.SetWiFiEnabled(true), "no WiFi device available")
}
