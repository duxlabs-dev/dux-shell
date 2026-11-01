package evdev

import (
	"errors"
	"testing"

	evdev "github.com/holoplot/go-evdev"
	"github.com/stretchr/testify/assert"

	mocks "github.com/duxlabs-dev/dux-shell/core/internal/mocks/evdev"
)

func TestManager_Unsubscribe(t *testing.T) {
	mockDevice := mocks.NewMockEvdevDevice(t)
	mockDevice.EXPECT().ReadOne().Return(nil, errors.New("test")).Maybe()

	m := &Manager{
		devices:        []EvdevDevice{mockDevice},
		monitoredPaths: make(map[string]bool),
		state:          State{Available: true, CapsLock: false},
		closeChan:      make(chan struct{}),
	}

	ch := m.Subscribe("test-client")
	count := 0
	m.subscribers.Range(func(key string, ch chan State) bool {
		count++
		return true
	})
	assert.Equal(t, 1, count)

	m.Unsubscribe("test-client")
	count = 0
	m.subscribers.Range(func(key string, ch chan State) bool {
		count++
		return true
	})
	assert.Equal(t, 0, count)

	select {
	case _, ok := <-ch:
		assert.False(t, ok, "channel should be closed")
	default:
		t.Error("channel should be closed")
	}
}

func TestManager_UpdateCapsLock(t *testing.T) {
	mockDevice := mocks.NewMockEvdevDevice(t)
	mockDevice.EXPECT().ReadOne().Return(nil, errors.New("test")).Maybe()

	m := &Manager{
		devices:        []EvdevDevice{mockDevice},
		monitoredPaths: make(map[string]bool),
		state:          State{Available: true, CapsLock: false},
		closeChan:      make(chan struct{}),
	}

	ch := m.Subscribe("test-client")

	ledStateOn := evdev.StateMap{ledCapslockKey: true}
	mockDevice.EXPECT().State(evdev.EvType(evLedType)).Return(ledStateOn, nil).Once()

	go func() {
		m.readAndUpdateCapsLockState(0)
	}()

	newState := <-ch
	assert.True(t, newState.CapsLock)

	ledStateOff := evdev.StateMap{ledCapslockKey: false}
	mockDevice.EXPECT().State(evdev.EvType(evLedType)).Return(ledStateOff, nil).Once()

	go func() {
		m.readAndUpdateCapsLockState(0)
	}()

	newState = <-ch
	assert.False(t, newState.CapsLock)
}

func TestManager_Close(t *testing.T) {
	mockDevice := mocks.NewMockEvdevDevice(t)
	mockDevice.EXPECT().Close().Return(nil).Once()
	mockDevice.EXPECT().ReadOne().Return(nil, errors.New("test")).Maybe()

	m := &Manager{
		devices:        []EvdevDevice{mockDevice},
		monitoredPaths: make(map[string]bool),
		state:          State{Available: true, CapsLock: false},
		closeChan:      make(chan struct{}),
	}

	ch1 := m.Subscribe("client1")
	ch2 := m.Subscribe("client2")

	m.Close()

	select {
	case _, ok := <-ch1:
		assert.False(t, ok, "channel 1 should be closed")
	default:
		t.Error("channel 1 should be closed")
	}

	select {
	case _, ok := <-ch2:
		assert.False(t, ok, "channel 2 should be closed")
	default:
		t.Error("channel 2 should be closed")
	}

	count := 0
	m.subscribers.Range(func(key string, ch chan State) bool {
		count++
		return true
	})
	assert.Equal(t, 0, count)

	m.Close()
}

func TestIsKeyboard(t *testing.T) {
	tests := []struct {
		name     string
		devName  string
		expected bool
	}{
		{"keyboard in name", "AT Translated Set 2 keyboard", true},
		{"kbd in name", "USB kbd", true},
		{"input and key", "input key device", true},
		{"random device", "Mouse", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockDevice := mocks.NewMockEvdevDevice(t)
			mockDevice.EXPECT().Name().Return(tt.devName, nil).Once()

			if !tt.expected {
				mockDevice.EXPECT().State(evdev.EvType(evKeyType)).Return(evdev.StateMap{}, nil).Maybe()
			}

			result := isKeyboard(mockDevice)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestIsKeyboard_ErrorHandling(t *testing.T) {
	mockDevice := mocks.NewMockEvdevDevice(t)
	mockDevice.EXPECT().Name().Return("", errors.New("device error")).Once()

	result := isKeyboard(mockDevice)
	assert.False(t, result)
}

func TestManager_MonitorDevice(t *testing.T) {
	t.Run("caps lock key press updates state", func(t *testing.T) {
		mockDevice := mocks.NewMockEvdevDevice(t)

		capsLockEvent := &evdev.InputEvent{
			Type:  evKeyType,
			Code:  keyCapslockKey,
			Value: keyStateOn,
		}

		ledState := evdev.StateMap{ledCapslockKey: true}

		mockDevice.EXPECT().ReadOne().Return(capsLockEvent, nil).Once()
		mockDevice.EXPECT().State(evdev.EvType(evLedType)).Return(ledState, nil).Once()
		mockDevice.EXPECT().ReadOne().Return(nil, errors.New("stop")).Maybe()
		mockDevice.EXPECT().Close().Return(nil).Maybe()

		m := &Manager{
			devices:   []EvdevDevice{mockDevice},
			state:     State{Available: true, CapsLock: false},
			closeChan: make(chan struct{}),
		}

		ch := m.Subscribe("test")

		go m.monitorDevice(mockDevice, 0)

		state := <-ch
		assert.True(t, state.CapsLock)

		m.Close()
	})
}

func TestIsClosedError(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected bool
	}{
		{"nil error", nil, false},
		{"closed error", errors.New("device closed"), true},
		{"bad file descriptor", errors.New("bad file descriptor"), true},
		{"other error", errors.New("some other error"), false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := isClosedError(tt.err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestNotifySubscribers(t *testing.T) {
	mockDevice := mocks.NewMockEvdevDevice(t)
	mockDevice.EXPECT().ReadOne().Return(nil, errors.New("test")).Maybe()
	mockDevice.EXPECT().Close().Return(nil).Maybe()

	m := &Manager{
		devices:        []EvdevDevice{mockDevice},
		monitoredPaths: make(map[string]bool),
		state:          State{Available: true, CapsLock: false},
		closeChan:      make(chan struct{}),
	}

	ch1 := m.Subscribe("client1")
	ch2 := m.Subscribe("client2")

	newState := State{Available: true, CapsLock: true}
	go m.notifySubscribers(newState)

	state1 := <-ch1
	state2 := <-ch2

	assert.Equal(t, newState, state1)
	assert.Equal(t, newState, state2)

	m.Close()
}

func TestCapsLockFromDevices(t *testing.T) {
	t.Run("caps lock is off", func(t *testing.T) {
		mockDevice := mocks.NewMockEvdevDevice(t)
		ledState := evdev.StateMap{
			ledCapslockKey: false,
		}
		mockDevice.EXPECT().State(evdev.EvType(evLedType)).Return(ledState, nil).Once()

		result, ok := capsLockFromDevices([]EvdevDevice{mockDevice})
		assert.True(t, ok)
		assert.False(t, result)
	})

	t.Run("error reading LED state", func(t *testing.T) {
		mockDevice := mocks.NewMockEvdevDevice(t)
		mockDevice.EXPECT().State(evdev.EvType(evLedType)).Return(nil, errors.New("read error")).Once()

		result, ok := capsLockFromDevices([]EvdevDevice{mockDevice})
		assert.False(t, ok)
		assert.False(t, result)
	})

	t.Run("falls back past device without LED state", func(t *testing.T) {
		noLedDevice := mocks.NewMockEvdevDevice(t)
		noLedDevice.EXPECT().State(evdev.EvType(evLedType)).Return(evdev.StateMap{}, nil).Once()

		ledDevice := mocks.NewMockEvdevDevice(t)
		ledState := evdev.StateMap{
			ledCapslockKey: true,
		}
		ledDevice.EXPECT().State(evdev.EvType(evLedType)).Return(ledState, nil).Once()

		result, ok := capsLockFromDevices([]EvdevDevice{noLedDevice, nil, ledDevice})
		assert.True(t, ok)
		assert.True(t, result)
	})
}
