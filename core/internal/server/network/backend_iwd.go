package network

import (
	"fmt"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	iwdBusName               = "net.connman.iwd"
	iwdObjectPath            = "/"
	iwdAdapterInterface      = "net.connman.iwd.Adapter"
	iwdDeviceInterface       = "net.connman.iwd.Device"
	iwdStationInterface      = "net.connman.iwd.Station"
	iwdNetworkInterface      = "net.connman.iwd.Network"
	iwdKnownNetworkInterface = "net.connman.iwd.KnownNetwork"
	dbusObjectManager        = "org.freedesktop.DBus.ObjectManager"
	dbusPropertiesInterface  = "org.freedesktop.DBus.Properties"
)

type connectAttempt struct {
	ssid           string
	netPath        dbus.ObjectPath
	saved          bool
	start          time.Time
	deadline       time.Time
	sawAuthish     bool
	connectedAt    time.Time
	sawIPConfig    bool
	sawPromptRetry bool
	finalized      bool
	mu             sync.Mutex
}

type IWDBackend struct {
	conn          *dbus.Conn
	state         *BackendState
	stateMutex    sync.RWMutex
	promptBroker  PromptBroker
	onStateChange func()

	devicePath  dbus.ObjectPath
	stationPath dbus.ObjectPath
	adapterPath dbus.ObjectPath

	iwdAgent *IWDAgent

	stopChan      chan struct{}
	sigWG         sync.WaitGroup
	curAttempt    *connectAttempt
	attemptMutex  sync.RWMutex
	recentScans   map[string]time.Time
	recentScansMu sync.Mutex
	pendingPSK    *pendingReplacementPSK
	pendingPSKMu  sync.Mutex
}

type pendingReplacementPSK struct {
	ssid    string
	psk     string
	expires time.Time
}

func (b *IWDBackend) storePendingPSK(ssid, psk string) {
	b.pendingPSKMu.Lock()
	b.pendingPSK = &pendingReplacementPSK{
		ssid:    ssid,
		psk:     psk,
		expires: time.Now().Add(30 * time.Second),
	}
	b.pendingPSKMu.Unlock()
}

func (b *IWDBackend) takePendingPSK(ssid string) (string, bool) {
	b.pendingPSKMu.Lock()
	defer b.pendingPSKMu.Unlock()

	pending := b.pendingPSK
	if pending == nil || pending.ssid != ssid || time.Now().After(pending.expires) {
		return "", false
	}

	b.pendingPSK = nil
	return pending.psk, true
}

func NewIWDBackend() (*IWDBackend, error) {
	backend := &IWDBackend{
		state: &BackendState{
			Backend:     "iwd",
			WiFiEnabled: true,
		},
		stopChan:    make(chan struct{}),
		recentScans: make(map[string]time.Time),
	}

	return backend, nil
}

func (b *IWDBackend) Initialize() error {
	conn, err := dbus.SystemBus()
	if err != nil {
		return fmt.Errorf("failed to connect to system bus: %w", err)
	}
	b.conn = conn

	if err := b.discoverDevices(); err != nil {
		return fmt.Errorf("failed to discover iwd devices: %w", err)
	}

	if err := b.updateSavedWiFiNetworks(); err != nil {
		log.Warnf("Failed to get initial saved WiFi networks: %v", err)
	}

	if err := b.updateState(); err != nil {
		return fmt.Errorf("failed to get initial state: %w", err)
	}

	return nil
}

func (b *IWDBackend) Close() {
	close(b.stopChan)
	b.sigWG.Wait()

	if b.iwdAgent != nil {
		b.iwdAgent.Close()
	}
}

func (b *IWDBackend) discoverDevices() error {
	obj := b.conn.Object(iwdBusName, iwdObjectPath)

	var objects map[dbus.ObjectPath]map[string]map[string]dbus.Variant
	err := obj.Call(dbusObjectManager+".GetManagedObjects", 0).Store(&objects)
	if err != nil {
		return fmt.Errorf("failed to get managed objects: %w", err)
	}

	return b.applyManagedObjects(objects)
}

func (b *IWDBackend) applyManagedObjects(objects map[dbus.ObjectPath]map[string]map[string]dbus.Variant) error {
	b.stationPath = ""
	b.devicePath = ""
	b.adapterPath = ""

	for path, interfaces := range objects {
		if _, hasStation := interfaces[iwdStationInterface]; hasStation {
			b.stationPath = path
		}
		if _, hasDevice := interfaces[iwdDeviceInterface]; hasDevice {
			b.devicePath = path
			b.applyDeviceProps(interfaces[iwdDeviceInterface])
		}
		if _, hasAdapter := interfaces[iwdAdapterInterface]; hasAdapter {
			b.adapterPath = path
		}
	}

	if b.devicePath == "" {
		return fmt.Errorf("no WiFi device found")
	}
	if b.stationPath == "" {
		b.stateMutex.Lock()
		b.state.WiFiEnabled = false
		b.state.WiFiConnected = false
		b.state.NetworkStatus = StatusDisconnected
		b.state.WiFiNetworks = nil
		b.stateMutex.Unlock()
		log.Infof("iwd device %s has no station interface; treating WiFi as disabled", b.devicePath)
	}

	return nil
}

func (b *IWDBackend) applyDeviceProps(props map[string]dbus.Variant) {
	if nameVar, ok := props["Name"]; ok {
		if name, ok := nameVar.Value().(string); ok {
			b.stateMutex.Lock()
			b.state.WiFiDevice = name
			b.stateMutex.Unlock()
		}
	}
	if poweredVar, ok := props["Powered"]; ok {
		if powered, ok := poweredVar.Value().(bool); ok {
			b.stateMutex.Lock()
			b.state.WiFiEnabled = powered
			b.stateMutex.Unlock()
		}
	}
}

// setDevice records a device that appeared at a new path, which is what
// happens when iwd restarts and recreates wlan0. It returns the path it
// replaced so the caller can move the signal match over.
func (b *IWDBackend) setDevice(path dbus.ObjectPath, props map[string]dbus.Variant) (prev dbus.ObjectPath, changed bool) {
	if path == "" || path == b.devicePath {
		return "", false
	}
	prev = b.devicePath
	b.devicePath = path
	b.applyDeviceProps(props)
	return prev, true
}

func (b *IWDBackend) clearDevice(path dbus.ObjectPath) bool {
	if path == "" || path != b.devicePath {
		return false
	}
	b.devicePath = ""
	b.stateMutex.Lock()
	b.state.WiFiEnabled = false
	b.stateMutex.Unlock()
	return true
}

func (b *IWDBackend) GetCurrentState() (*BackendState, error) {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()

	state := *b.state
	state.WiFiNetworks = append([]WiFiNetwork(nil), b.state.WiFiNetworks...)
	state.SavedWiFiNetworks = append([]WiFiNetwork(nil), b.state.SavedWiFiNetworks...)
	state.WiredConnections = append([]WiredConnection(nil), b.state.WiredConnections...)
	state.WiFiDevices = b.getWiFiDevicesLocked()

	return &state, nil
}

func (b *IWDBackend) OnUserCanceledPrompt() {
	b.stateMutex.RLock()
	cancelledSSID := b.state.ConnectingSSID
	b.stateMutex.RUnlock()

	b.setConnectError("user-canceled")

	if cancelledSSID != "" {
		if err := b.ForgetWiFiNetwork(cancelledSSID); err != nil {
			log.Warnf("failed to forget cancelled WiFi network %s: %v", cancelledSSID, err)
		}
	}

	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *IWDBackend) OnPromptRetry(ssid string) {
	b.attemptMutex.RLock()
	att := b.curAttempt
	b.attemptMutex.RUnlock()

	if att != nil && att.ssid == ssid {
		att.mu.Lock()
		att.sawPromptRetry = true
		att.mu.Unlock()
	}
}

func (b *IWDBackend) MarkIPConfigSeen() {
	b.attemptMutex.RLock()
	att := b.curAttempt
	b.attemptMutex.RUnlock()
	if att != nil {
		att.mu.Lock()
		att.sawIPConfig = true
		att.mu.Unlock()
	}
}

func (b *IWDBackend) GetPromptBroker() PromptBroker {
	return b.promptBroker
}

func (b *IWDBackend) SetPromptBroker(broker PromptBroker) error {
	if broker == nil {
		return fmt.Errorf("broker cannot be nil")
	}

	b.promptBroker = broker
	return nil
}

func (b *IWDBackend) SubmitCredentials(token string, secrets map[string]string, save bool) error {
	if b.promptBroker == nil {
		return fmt.Errorf("prompt broker not initialized")
	}

	return b.promptBroker.Resolve(token, PromptReply{
		Secrets: secrets,
		Save:    save,
		Cancel:  false,
	})
}

func (b *IWDBackend) CancelCredentials(token string) error {
	if b.promptBroker == nil {
		return fmt.Errorf("prompt broker not initialized")
	}

	return b.promptBroker.Resolve(token, PromptReply{
		Cancel: true,
	})
}

func (b *IWDBackend) StopMonitoring() {
	select {
	case <-b.stopChan:
		return
	default:
		close(b.stopChan)
	}
	b.sigWG.Wait()
}
