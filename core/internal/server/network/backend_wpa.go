package network

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

// Default ctrl_interface directory on FreeBSD and minimal Linux setups; see
// https://man.freebsd.org/cgi/man.cgi?query=wpa_supplicant.conf&sektion=5
const wpaSupplicantCtrlDir = "/var/run/wpa_supplicant"

type wpaConnectAttempt struct {
	ssid            string
	netID           int
	saved           bool
	newlyAdded      bool
	prompted        bool
	sawTempDisabled bool
	finalized       bool
	deadline        time.Time
	mu              sync.Mutex
}

type WpaSupplicantBackend struct {
	ctrlDir       string
	ifname        string
	physicalWiFi  string
	cmd           *wpaCtrlConn
	monitor       *wpaCtrlConn
	state         *BackendState
	stateMutex    sync.RWMutex
	promptBroker  PromptBroker
	onStateChange func()

	stopChan     chan struct{}
	sigWG        sync.WaitGroup
	curAttempt   *wpaConnectAttempt
	attemptMutex sync.RWMutex

	savedIDs   map[string]int
	savedIDsMu sync.Mutex

	recentScans   map[string]time.Time
	recentScansMu sync.Mutex
}

func NewWpaSupplicantBackend() (*WpaSupplicantBackend, error) {
	return &WpaSupplicantBackend{
		ctrlDir: wpaSupplicantCtrlDir,
		state: &BackendState{
			Backend:      "wpa_supplicant",
			WiFiNetworks: []WiFiNetwork{},
		},
		stopChan:    make(chan struct{}),
		savedIDs:    make(map[string]int),
		recentScans: make(map[string]time.Time),
	}, nil
}

func discoverWpaInterfaces(ctrlDir string) ([]string, error) {
	entries, err := os.ReadDir(ctrlDir)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", ctrlDir, err)
	}

	var names []string
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		// wpa_supplicant creates an extra p2p-dev-<ifname> management socket
		// when built with CONFIG_P2P; it is not a station interface.
		if strings.HasPrefix(entry.Name(), "p2p-dev-") {
			continue
		}
		names = append(names, entry.Name())
	}

	sort.Strings(names)
	return names, nil
}

func discoverFreeBSDWiFiHardware() string {
	out, err := exec.Command("/sbin/sysctl", "-n", "net.wlan.devices").Output()
	if err != nil {
		return ""
	}

	fields := strings.Fields(string(out))
	if len(fields) == 0 {
		return ""
	}

	return fields[0]
}

func (b *WpaSupplicantBackend) Initialize() error {
	b.physicalWiFi = discoverFreeBSDWiFiHardware()

	names, err := discoverWpaInterfaces(b.ctrlDir)
	if err != nil || len(names) == 0 {
		b.stateMutex.Lock()
		b.state.WiFiEnabled = false

		if b.physicalWiFi != "" {
			b.state.WiFiDevice = b.physicalWiFi
			log.Infof(
				"FreeBSD Wi-Fi hardware %s found, but no wlan/wpa_supplicant control socket is configured",
				b.physicalWiFi,
			)
		} else {
			log.Info("wpa_supplicant unavailable; continuing with Ethernet-only networking")
		}

		b.stateMutex.Unlock()
		b.updateEthernetState()
		return nil
	}

	b.ifname = names[0]
	if len(names) > 1 {
		log.Infof("wpa_supplicant manages %d interfaces; using %s", len(names), b.ifname)
	}

	conn, err := newWpaCtrlConn(filepath.Join(b.ctrlDir, b.ifname))
	if err != nil {
		return fmt.Errorf("failed to open wpa_ctrl socket: %w", err)
	}
	b.cmd = conn

	reply, err := b.cmd.request("PING")
	if err != nil {
		b.cmd.close()
		return fmt.Errorf("wpa_supplicant not responding on %s: %w", b.ifname, err)
	}
	if reply != "PONG" {
		b.cmd.close()
		return fmt.Errorf("unexpected PING reply from wpa_supplicant: %s", reply)
	}

	b.stateMutex.Lock()
	b.state.WiFiDevice = b.ifname
	b.state.WiFiEnabled = true
	b.stateMutex.Unlock()

	if err := b.updateSavedWiFiNetworks(); err != nil {
		log.Warnf("Failed to get initial saved WiFi networks: %v", err)
	}

	if err := b.updateState(); err != nil {
		b.cmd.close()
		return fmt.Errorf("failed to get initial state: %w", err)
	}

	if _, err := b.updateWiFiNetworks(); err != nil {
		log.Warnf("Failed to get initial WiFi networks: %v", err)
	}

	if err := b.ScanWiFi(); err != nil {
		log.Debugf("Initial WiFi scan not started: %v", err)
	}

	return nil
}

func (b *WpaSupplicantBackend) Close() {
	b.StopMonitoring()

	if b.monitor != nil {
		_ = b.monitor.send("DETACH")
		b.monitor.close()
	}
	if b.cmd != nil {
		b.cmd.close()
	}
}

func (b *WpaSupplicantBackend) GetCurrentState() (*BackendState, error) {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()

	state := *b.state
	state.WiFiNetworks = append([]WiFiNetwork(nil), b.state.WiFiNetworks...)
	state.SavedWiFiNetworks = append([]WiFiNetwork(nil), b.state.SavedWiFiNetworks...)
	state.EthernetDevices = append([]EthernetDevice(nil), b.state.EthernetDevices...)
	state.WiredConnections = append([]WiredConnection(nil), b.state.WiredConnections...)
	state.WiFiDevices = b.getWiFiDevicesLocked()

	return &state, nil
}

func (b *WpaSupplicantBackend) GetPromptBroker() PromptBroker {
	return b.promptBroker
}

func (b *WpaSupplicantBackend) SetPromptBroker(broker PromptBroker) error {
	if broker == nil {
		return fmt.Errorf("broker cannot be nil")
	}

	b.promptBroker = broker
	return nil
}

func (b *WpaSupplicantBackend) SubmitCredentials(token string, secrets map[string]string, save bool) error {
	if b.promptBroker == nil {
		return fmt.Errorf("prompt broker not initialized")
	}

	return b.promptBroker.Resolve(token, PromptReply{
		Secrets: secrets,
		Save:    save,
		Cancel:  false,
	})
}

func (b *WpaSupplicantBackend) CancelCredentials(token string) error {
	if b.promptBroker == nil {
		return fmt.Errorf("prompt broker not initialized")
	}

	return b.promptBroker.Resolve(token, PromptReply{
		Cancel: true,
	})
}

func (b *WpaSupplicantBackend) StopMonitoring() {
	select {
	case <-b.stopChan:
		return
	default:
		close(b.stopChan)
	}
	b.sigWG.Wait()
}

func (b *WpaSupplicantBackend) promptForPSK(ssid, reason string) (string, bool) {
	if b.promptBroker == nil {
		return "", false
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	go func() {
		select {
		case <-b.stopChan:
			cancel()
		case <-ctx.Done():
		}
	}()

	token, err := b.promptBroker.Ask(ctx, PromptRequest{
		SSID:        ssid,
		SettingName: "802-11-wireless-security",
		Fields:      []string{"psk"},
		Reason:      reason,
	})
	if err != nil {
		log.Warnf("failed to request credentials for %s: %v", ssid, err)
		return "", false
	}

	reply, err := b.promptBroker.Wait(ctx, token)
	if err != nil || reply.Cancel {
		return "", false
	}

	psk, ok := reply.Secrets["psk"]
	if !ok || psk == "" {
		return "", false
	}

	return psk, true
}

func (b *WpaSupplicantBackend) storeSavedIDs(ids map[string]int) {
	b.savedIDsMu.Lock()
	b.savedIDs = ids
	b.savedIDsMu.Unlock()
}

func (b *WpaSupplicantBackend) savedNetworkID(ssid string) (int, bool) {
	b.savedIDsMu.Lock()
	defer b.savedIDsMu.Unlock()
	id, ok := b.savedIDs[ssid]
	return id, ok
}

func (b *WpaSupplicantBackend) seenInRecentScan(ssid string) bool {
	b.recentScansMu.Lock()
	defer b.recentScansMu.Unlock()
	lastSeen, ok := b.recentScans[ssid]
	return ok && time.Since(lastSeen) < 30*time.Second
}

func (b *WpaSupplicantBackend) setConnectError(code string) {
	b.stateMutex.Lock()
	b.state.IsConnecting = false
	b.state.ConnectingSSID = ""
	b.state.LastError = code
	b.stateMutex.Unlock()
}
