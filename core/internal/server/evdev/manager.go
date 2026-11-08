package evdev

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/fsnotify/fsnotify"
	evdev "github.com/holoplot/go-evdev"
)

const (
	evKeyType      = 0x01
	evLedType      = 0x11
	keyCapslockKey = 58
	keyNumlockKey  = 69
	ledCapslockKey = 1
	ledNumlockKey  = 0
	keyStateOn     = 1
)

type EvdevDevice interface {
	Name() (string, error)
	Path() string
	Close() error
	ReadOne() (*evdev.InputEvent, error)
	State(t evdev.EvType) (evdev.StateMap, error)
}

type Manager struct {
	devices        []EvdevDevice
	devicesMutex   sync.RWMutex
	monitoredPaths map[string]bool
	state          State
	stateMutex     sync.RWMutex
	subscribers    syncmap.Map[string, chan State]
	closeChan      chan struct{}
	closeOnce      sync.Once
	watcher        *fsnotify.Watcher
}

func NewManager() (*Manager, error) {
	devices, err := findKeyboards()
	if err != nil {
		return nil, fmt.Errorf("failed to find keyboards: %w", err)
	}

	initialCapsLock, _ := capsLockFromDevices(devices)
	initialNumLock, _ := numLockFromDevices(devices)

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Warnf("Failed to create fsnotify watcher, hotplug detection disabled: %v", err)
		watcher = nil
	} else if err := watcher.Add("/dev/input"); err != nil {
		log.Warnf("Failed to watch /dev/input, hotplug detection disabled: %v", err)
		watcher.Close()
		watcher = nil
	}

	monitoredPaths := make(map[string]bool)
	for _, device := range devices {
		monitoredPaths[device.Path()] = true
	}

	m := &Manager{
		devices:        devices,
		monitoredPaths: monitoredPaths,
		state:          State{Available: true, CapsLock: initialCapsLock, NumLock: initialNumLock},

		closeChan: make(chan struct{}),
		watcher:   watcher,
	}

	for i, device := range devices {
		go m.monitorDevice(device, i)
	}

	if watcher != nil {
		go m.watchForNewKeyboards()
	}

	return m, nil
}

func armNonBlocking(device EvdevDevice) {
	nb, ok := device.(interface{ NonBlock() error })
	if !ok {
		return
	}
	if err := nb.NonBlock(); err != nil {
		log.Debugf("evdev: non-blocking mode for %s: %v", device.Path(), err)
	}
}

func capsLockFromDevices(devices []EvdevDevice) (bool, bool) {
	return lockStateFromDevices(devices, ledCapslockKey)
}

func numLockFromDevices(devices []EvdevDevice) (bool, bool) {
	return lockStateFromDevices(devices, ledNumlockKey)
}

func lockStateFromDevices(devices []EvdevDevice, ledCode int) (bool, bool) {
	for _, device := range devices {
		if device == nil {
			continue
		}

		ledStates, err := device.State(evLedType)
		armNonBlocking(device)
		if err != nil {
			continue
		}
		state, ok := ledStates[evdev.EvCode(ledCode)]
		if !ok {
			continue
		}
		return state, true
	}

	return false, false
}

func findKeyboards() ([]EvdevDevice, error) {
	pattern := "/dev/input/event*"
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return nil, fmt.Errorf("failed to glob input devices: %w", err)
	}

	if len(matches) == 0 {
		return nil, fmt.Errorf("no input devices found")
	}

	var keyboards []EvdevDevice
	for _, path := range matches {
		device, err := evdev.OpenWithFlags(path, os.O_RDONLY)
		if err != nil {
			continue
		}

		if !isKeyboard(device) {
			device.Close()
			continue
		}

		deviceName, _ := device.Name()
		armNonBlocking(device)
		log.Debugf("Found keyboard: %s at %s", deviceName, path)
		keyboards = append(keyboards, device)
	}

	if len(keyboards) == 0 {
		return nil, fmt.Errorf("no keyboard device found")
	}

	return keyboards, nil
}

func isKeyboard(device EvdevDevice) bool {
	deviceName, err := device.Name()
	if err != nil {
		return false
	}

	name := strings.ToLower(deviceName)

	switch {
	case strings.Contains(name, "keyboard"):
		return true
	case strings.Contains(name, "kbd"):
		return true
	case strings.Contains(name, "input") && strings.Contains(name, "key"):
		return true
	}

	keyStates, err := device.State(evKeyType)
	if err != nil {
		return false
	}

	hasKeyA := len(keyStates) > 30
	hasKeyZ := len(keyStates) > 44
	hasEnter := len(keyStates) > 28

	return hasKeyA && hasKeyZ && hasEnter && len(keyStates) > 100
}

func (m *Manager) watchForNewKeyboards() {
	defer func() {
		if r := recover(); r != nil {
			log.Errorf("Panic in keyboard hotplug monitor: %v", r)
		}
	}()

	for {
		select {
		case <-m.closeChan:
			return
		case event, ok := <-m.watcher.Events:
			if !ok {
				return
			}

			if !strings.HasPrefix(filepath.Base(event.Name), "event") {
				continue
			}

			if event.Op&fsnotify.Create == fsnotify.Create {
				time.Sleep(100 * time.Millisecond)

				m.devicesMutex.Lock()
				if m.monitoredPaths[event.Name] {
					m.devicesMutex.Unlock()
					continue
				}

				device, err := evdev.OpenWithFlags(event.Name, os.O_RDONLY)
				if err != nil {
					m.devicesMutex.Unlock()
					continue
				}

				if !isKeyboard(device) {
					device.Close()
					m.devicesMutex.Unlock()
					continue
				}

				deviceName, _ := device.Name()
				armNonBlocking(device)
				log.Debugf("Hotplugged keyboard: %s at %s", deviceName, event.Name)

				m.devices = append(m.devices, device)
				m.monitoredPaths[event.Name] = true
				deviceIndex := len(m.devices) - 1
				m.devicesMutex.Unlock()

				go m.monitorDevice(device, deviceIndex)
			} else if event.Op&fsnotify.Remove == fsnotify.Remove {
				m.devicesMutex.Lock()
				if !m.monitoredPaths[event.Name] {
					m.devicesMutex.Unlock()
					continue
				}

				delete(m.monitoredPaths, event.Name)
				for i, device := range m.devices {
					if device != nil && device.Path() == event.Name {
						log.Debugf("Keyboard removed: %s", event.Name)
						device.Close()
						m.devices[i] = nil
						break
					}
				}
				m.devicesMutex.Unlock()
			}

		case err, ok := <-m.watcher.Errors:
			if !ok {
				return
			}
			log.Warnf("Keyboard hotplug watcher error: %v", err)
		}
	}
}

func (m *Manager) monitorDevice(device EvdevDevice, deviceIndex int) {
	defer func() {
		if r := recover(); r != nil {
			log.Errorf("Panic in evdev monitor: %v", r)
		}
	}()

	for {
		select {
		case <-m.closeChan:
			return
		default:
		}

		event, err := device.ReadOne()
		if err != nil {
			if isClosedError(err) {
				return
			}
			log.Warnf("Failed to read evdev event: %v", err)
			time.Sleep(100 * time.Millisecond)
			continue
		}

		if event == nil {
			continue
		}

		if event.Type == evKeyType && (event.Code == keyCapslockKey || event.Code == keyNumlockKey) && event.Value == keyStateOn {
			time.Sleep(50 * time.Millisecond)
			ledCode := ledCapslockKey
			if event.Code == keyNumlockKey {
				ledCode = ledNumlockKey
			}
			m.readAndUpdateLockState(deviceIndex, ledCode)
		} else if event.Type == evLedType && (event.Code == ledCapslockKey || event.Code == ledNumlockKey) {
			m.updateLockStateDirect(int(event.Code), event.Value == keyStateOn)
		}
	}
}

func isClosedError(err error) bool {
	if err == nil {
		return false
	}

	errStr := err.Error()
	switch {
	case strings.Contains(errStr, "closed"):
		return true
	case strings.Contains(errStr, "bad file descriptor"):
		return true
	default:
		return false
	}
}

func (m *Manager) readAndUpdateLockState(deviceIndex int, ledCode int) {
	m.devicesMutex.RLock()
	if deviceIndex >= len(m.devices) {
		m.devicesMutex.RUnlock()
		return
	}
	ordered := make([]EvdevDevice, 0, len(m.devices))
	ordered = append(ordered, m.devices[deviceIndex])
	for i, device := range m.devices {
		if i == deviceIndex {
			continue
		}
		ordered = append(ordered, device)
	}
	m.devicesMutex.RUnlock()

	lockState, ok := lockStateFromDevices(ordered, ledCode)
	if !ok {
		log.Debugf("No keyboard LED state available for LED code %d", ledCode)
		return
	}

	m.updateLockStateDirect(ledCode, lockState)
}

func (m *Manager) readAndUpdateCapsLockState(deviceIndex int) {
	m.readAndUpdateLockState(deviceIndex, ledCapslockKey)
}

func (m *Manager) updateLockStateDirect(ledCode int, enabled bool) {
	m.stateMutex.Lock()
	var current *bool
	switch ledCode {
	case ledCapslockKey:
		current = &m.state.CapsLock
	case ledNumlockKey:
		current = &m.state.NumLock
	default:
		m.stateMutex.Unlock()
		return
	}
	if *current == enabled {
		m.stateMutex.Unlock()
		return
	}

	*current = enabled
	newState := m.state
	m.stateMutex.Unlock()

	log.Debugf("Keyboard lock LED %d state: %v", ledCode, enabled)
	m.notifySubscribers(newState)
}

func (m *Manager) GetState() State {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	return m.state
}

func (m *Manager) Subscribe(id string) chan State {
	ch := make(chan State, 16)
	m.subscribers.Store(id, ch)
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)
	}
}

func (m *Manager) notifySubscribers(state State) {
	m.subscribers.Range(func(key string, ch chan State) bool {
		select {
		case ch <- state:
		default:
		}
		return true
	})
}

func (m *Manager) Close() {
	m.closeOnce.Do(func() {
		close(m.closeChan)

		if m.watcher != nil {
			m.watcher.Close()
		}

		m.devicesMutex.Lock()
		for _, device := range m.devices {
			if device == nil {
				continue
			}
			if err := device.Close(); err != nil && !isClosedError(err) {
				log.Warnf("Error closing evdev device: %v", err)
			}
		}
		m.devicesMutex.Unlock()

		m.subscribers.Range(func(key string, ch chan State) bool {
			close(ch)
			m.subscribers.Delete(key)
			return true
		})
	})
}

func InitializeManager() (*Manager, error) {
	if os.Getuid() != 0 && !hasInputGroupAccess() {
		return nil, fmt.Errorf("insufficient permissions to access input devices. Add your user to the 'input' group: `sudo usermod -a -G input $USER` or run `dms setup`")
	}

	return NewManager()
}

func hasInputGroupAccess() bool {
	pattern := "/dev/input/event*"
	matches, err := filepath.Glob(pattern)
	if err != nil || len(matches) == 0 {
		return false
	}

	testFile, err := os.Open(matches[0])
	if err != nil {
		return false
	}
	testFile.Close()
	return true
}
