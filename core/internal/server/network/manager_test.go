package network

import (
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestStateChangedMeaningfully_HotspotFields(t *testing.T) {
	tests := []struct {
		name string
		old  NetworkState
		new  NetworkState
	}{
		{
			name: "supported",
			old:  NetworkState{},
			new:  NetworkState{HotspotSupported: true},
		},
		{
			name: "available",
			old:  NetworkState{},
			new:  NetworkState{HotspotAvailable: true},
		},
		{
			name: "configured",
			old:  NetworkState{},
			new:  NetworkState{HotspotConfigured: true},
		},
		{
			name: "enabled",
			old:  NetworkState{},
			new:  NetworkState{HotspotEnabled: true},
		},
		{
			name: "ssid",
			old:  NetworkState{HotspotSSID: "DMS Hotspot"},
			new:  NetworkState{HotspotSSID: "Other Hotspot"},
		},
		{
			name: "device",
			old:  NetworkState{HotspotDevice: "wlan0"},
			new:  NetworkState{HotspotDevice: "wlan1"},
		},
		{
			name: "band",
			old:  NetworkState{HotspotBand: "bg"},
			new:  NetworkState{HotspotBand: "a"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.True(t, stateChangedMeaningfully(&tt.old, &tt.new))
		})
	}
}

func TestStateChangedMeaningfully_WiFiDeviceFields(t *testing.T) {
	device := func(mutate func(d *WiFiDevice)) []WiFiDevice {
		d := WiFiDevice{Name: "wlan1", State: "disconnected", Signal: 60}
		if mutate != nil {
			mutate(&d)
		}
		return []WiFiDevice{d}
	}

	tests := []struct {
		name    string
		mutate  func(d *WiFiDevice)
		changed bool
	}{
		{name: "state", mutate: func(d *WiFiDevice) { d.State = "connecting" }, changed: true},
		{name: "connected", mutate: func(d *WiFiDevice) { d.Connected = true }, changed: true},
		{name: "apCapable", mutate: func(d *WiFiDevice) { d.APCapable = true }, changed: true},
		{name: "ssid", mutate: func(d *WiFiDevice) { d.SSID = "HomeNet" }, changed: true},
		{name: "signal jitter is ignored", mutate: func(d *WiFiDevice) { d.Signal = 63 }, changed: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			old := NetworkState{WiFiDevices: device(nil)}
			new := NetworkState{WiFiDevices: device(tt.mutate)}
			assert.Equal(t, tt.changed, stateChangedMeaningfully(&old, &new))
		})
	}
}

func TestStateChangedMeaningfully_PrimarySignalJitterDoesNotVetoOtherChanges(t *testing.T) {
	old := NetworkState{
		WiFiSignal:  60,
		WiFiDevices: []WiFiDevice{{Name: "wlan1", State: "disconnected"}},
	}
	new := NetworkState{
		WiFiSignal:  63,
		WiFiDevices: []WiFiDevice{{Name: "wlan1", State: "connected", Connected: true}},
	}
	assert.True(t, stateChangedMeaningfully(&old, &new), "insignificant signal jitter must not suppress a device change")

	jitterOnlyOld := NetworkState{WiFiSignal: 60}
	jitterOnlyNew := NetworkState{WiFiSignal: 63}
	assert.False(t, stateChangedMeaningfully(&jitterOnlyOld, &jitterOnlyNew), "insignificant signal jitter alone must stay debounced")
}

type testHotspotBackend struct {
	*IWDBackend
	configureCalled  bool
	startCalled      bool
	stopCalled       bool
	getSecretsCalled bool
	configureReq     HotspotRequest
	secrets          string
}

func (b *testHotspotBackend) ConfigureHotspot(req HotspotRequest) error {
	b.configureCalled = true
	b.configureReq = req

	b.stateMutex.Lock()
	b.state.HotspotAvailable = true
	b.state.HotspotConfigured = true
	b.state.HotspotSSID = req.SSID
	b.state.HotspotDevice = req.Device
	b.state.HotspotBand = req.Band
	b.stateMutex.Unlock()

	return nil
}

func (b *testHotspotBackend) StartHotspot() error {
	b.startCalled = true

	b.stateMutex.Lock()
	b.state.HotspotEnabled = true
	b.stateMutex.Unlock()

	return nil
}

func (b *testHotspotBackend) StopHotspot() error {
	b.stopCalled = true

	b.stateMutex.Lock()
	b.state.HotspotEnabled = false
	b.stateMutex.Unlock()

	return nil
}

func (b *testHotspotBackend) GetHotspotSecrets() (string, error) {
	b.getSecretsCalled = true
	return b.secrets, nil
}

func TestManager_HotspotUnsupportedBackend(t *testing.T) {
	backend, err := NewIWDBackend()
	assert.NoError(t, err)

	backend.stateMutex.Lock()
	backend.state.HotspotAvailable = true
	backend.state.HotspotConfigured = true
	backend.state.HotspotEnabled = true
	backend.state.HotspotSSID = "Should Not Leak"
	backend.state.HotspotDevice = "wlan0"
	backend.state.HotspotBand = "bg"
	backend.stateMutex.Unlock()

	manager := NewTestManager(backend, &NetworkState{})
	assert.NoError(t, manager.syncStateFromBackend())

	state := manager.GetState()
	assert.False(t, state.HotspotSupported)
	assert.False(t, state.HotspotAvailable)
	assert.False(t, state.HotspotConfigured)
	assert.False(t, state.HotspotEnabled)
	assert.Empty(t, state.HotspotSSID)
	assert.Empty(t, state.HotspotDevice)
	assert.Empty(t, state.HotspotBand)

	assert.ErrorIs(t, manager.ConfigureHotspot(HotspotRequest{SSID: "DMS Hotspot"}), ErrHotspotNotSupported)
	assert.ErrorIs(t, manager.StartHotspot(), ErrHotspotNotSupported)
	assert.ErrorIs(t, manager.StopHotspot(), ErrHotspotNotSupported)

	_, err = manager.GetHotspotSecrets()
	assert.ErrorIs(t, err, ErrHotspotNotSupported)
}

func TestManager_HotspotSupportedBackend(t *testing.T) {
	iwdBackend, err := NewIWDBackend()
	assert.NoError(t, err)

	backend := &testHotspotBackend{IWDBackend: iwdBackend}
	manager := NewTestManager(backend, &NetworkState{})

	req := HotspotRequest{
		SSID:     "DMS Hotspot",
		Password: "hunter2-password",
		Device:   "wlan0",
		Band:     "bg",
	}

	err = manager.ConfigureHotspot(req)
	assert.NoError(t, err)
	assert.True(t, backend.configureCalled)
	assert.Equal(t, req, backend.configureReq)

	state := manager.GetState()
	assert.True(t, state.HotspotSupported)
	assert.True(t, state.HotspotAvailable)
	assert.True(t, state.HotspotConfigured)
	assert.Equal(t, "DMS Hotspot", state.HotspotSSID)
	assert.Equal(t, "wlan0", state.HotspotDevice)
	assert.Equal(t, "bg", state.HotspotBand)

	err = manager.StartHotspot()
	assert.NoError(t, err)
	assert.True(t, backend.startCalled)
	assert.True(t, manager.GetState().HotspotEnabled)

	err = manager.StopHotspot()
	assert.NoError(t, err)
	assert.True(t, backend.stopCalled)
	assert.False(t, manager.GetState().HotspotEnabled)

	backend.secrets = "hunter2-password"
	password, err := manager.GetHotspotSecrets()
	assert.NoError(t, err)
	assert.True(t, backend.getSecretsCalled)
	assert.Equal(t, "hunter2-password", password)
}

func TestManager_NotifySubscribers_Debounce(t *testing.T) {
	manager := &Manager{
		state: &NetworkState{
			NetworkStatus: StatusWiFi,
		},
		stateMutex: sync.RWMutex{},
		stopChan:   make(chan struct{}),
		dirty:      make(chan struct{}, 1),
	}
	manager.notifierWg.Add(1)
	go manager.notifier()

	ch := make(chan NetworkState, 10)
	manager.subscribers.Store("test-client", ch)

	manager.notifySubscribers()
	manager.notifySubscribers()
	manager.notifySubscribers()

	receivedCount := 0
	timeout := time.After(200 * time.Millisecond)
	for {
		select {
		case <-ch:
			receivedCount++
		case <-timeout:
			assert.Equal(t, 1, receivedCount, "should receive exactly one debounced update")
			close(manager.stopChan)
			manager.notifierWg.Wait()
			return
		}
	}
}

func TestManager_Close(t *testing.T) {
	manager := &Manager{
		state:      &NetworkState{},
		stateMutex: sync.RWMutex{},
		stopChan:   make(chan struct{}),
	}

	ch1 := make(chan NetworkState, 1)
	ch2 := make(chan NetworkState, 1)
	manager.subscribers.Store("client1", ch1)
	manager.subscribers.Store("client2", ch2)

	manager.Close()

	select {
	case <-manager.stopChan:
	case <-time.After(100 * time.Millisecond):
		t.Fatal("stopChan not closed")
	}

	_, ok1 := <-ch1
	_, ok2 := <-ch2
	assert.False(t, ok1, "ch1 should be closed")
	assert.False(t, ok2, "ch2 should be closed")

	count := 0
	manager.subscribers.Range(func(key string, ch chan NetworkState) bool { count++; return true })
	assert.Equal(t, 0, count)
}

func TestStateChangedMeaningfully_CellularDeviceFields(t *testing.T) {
	device := func(mutate func(d *CellularDevice)) []CellularDevice {
		d := CellularDevice{Name: "cdc-wdm0", State: "disconnected", SignalQuality: 60, AccessTech: "lte"}
		if mutate != nil {
			mutate(&d)
		}
		return []CellularDevice{d}
	}

	tests := []struct {
		name    string
		mutate  func(d *CellularDevice)
		changed bool
	}{
		{name: "accessTech", mutate: func(d *CellularDevice) { d.AccessTech = "5gnr" }, changed: true},
		{name: "signal", mutate: func(d *CellularDevice) { d.SignalQuality = 80 }, changed: true},
		{name: "signal jitter is ignored", mutate: func(d *CellularDevice) { d.SignalQuality = 63 }, changed: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			old := NetworkState{CellularDevices: device(nil)}
			new := NetworkState{CellularDevices: device(tt.mutate)}
			assert.Equal(t, tt.changed, stateChangedMeaningfully(&old, &new))
		})
	}
}
