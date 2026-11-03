package network

import (
	"bufio"
	"fmt"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

// Event strings per WPA_EVENT_* in contrib/wpa/src/common/wpa_ctrl.h
// (freebsd-src).
const (
	wpaEventConnected    = "CTRL-EVENT-CONNECTED"
	wpaEventDisconnected = "CTRL-EVENT-DISCONNECTED"
	wpaEventScanResults  = "CTRL-EVENT-SCAN-RESULTS"
	wpaEventTempDisabled = "CTRL-EVENT-SSID-TEMP-DISABLED"
)

const (
	wpaMonitorReadTimeout    = 5 * time.Second
	wpaMonitorPingInterval   = 30 * time.Second
	wpaMonitorReconnectDelay = 2 * time.Second
)

const freeBSDRouteRefreshDebounce = 250 * time.Millisecond

type wpaEvent struct {
	priority int
	name     string
	args     string
}

func isRelevantFreeBSDRouteEvent(line string) bool {
	return strings.Contains(line, "RTM_IFINFO") ||
		strings.Contains(line, "RTM_NEWADDR") ||
		strings.Contains(line, "RTM_DELADDR") ||
		strings.Contains(line, "RTM_IFANNOUNCE")
}

func (b *WpaSupplicantBackend) startEthernetMonitor() error {
	cmd := exec.Command("/sbin/route", "-n", "monitor")

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("failed to open route monitor output: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start route monitor: %w", err)
	}

	b.sigWG.Add(1)
	go func() {
		defer b.sigWG.Done()

		processDone := make(chan error, 1)
		go func() {
			processDone <- cmd.Wait()
		}()

		// Kill the route monitor when the backend shuts down. cmd.Wait above
		// remains responsible for reaping the child process.
		go func() {
			select {
			case <-b.stopChan:
				if cmd.Process != nil {
					_ = cmd.Process.Kill()
				}
			case <-processDone:
			}
		}()

		refresh := make(chan struct{}, 1)
		scanDone := make(chan struct{})

		go func() {
			defer close(scanDone)

			scanner := bufio.NewScanner(stdout)
			for scanner.Scan() {
				if !isRelevantFreeBSDRouteEvent(scanner.Text()) {
					continue
				}

				// A single interface transition can generate several route
				// messages. Queue at most one pending refresh and debounce
				// the burst before rescanning interfaces.
				select {
				case refresh <- struct{}{}:
				default:
				}
			}

			if err := scanner.Err(); err != nil {
				select {
				case <-b.stopChan:
				default:
					log.Warnf("FreeBSD route monitor read failed: %v", err)
				}
			}
		}()

		var debounce *time.Timer
		var debounceC <-chan time.Time

		stopDebounce := func() {
			if debounce == nil {
				return
			}

			if !debounce.Stop() {
				select {
				case <-debounce.C:
				default:
				}
			}

			debounceC = nil
		}

		defer stopDebounce()

		for {
			select {
			case <-b.stopChan:
				return

			case err := <-processDone:
				if err != nil {
					select {
					case <-b.stopChan:
					default:
						log.Warnf("FreeBSD route monitor stopped: %v", err)
					}
				}
				return

			case <-scanDone:
				// stdout closed. The processDone case will normally follow,
				// but there is nothing left to monitor meanwhile.
				return

			case <-refresh:
				if debounce == nil {
					debounce = time.NewTimer(freeBSDRouteRefreshDebounce)
					debounceC = debounce.C
					continue
				}

				if !debounce.Stop() {
					select {
					case <-debounce.C:
					default:
					}
				}

				debounce.Reset(freeBSDRouteRefreshDebounce)
				debounceC = debounce.C

			case <-debounceC:
				debounceC = nil

				b.updateEthernetState()

				if b.onStateChange != nil {
					b.onStateChange()
				}
			}
		}
	}()

	return nil
}

func parseWpaEventLine(line string) (wpaEvent, bool) {
	if len(line) < 3 || line[0] != '<' {
		return wpaEvent{}, false
	}

	end := strings.IndexByte(line, '>')
	if end < 0 {
		return wpaEvent{}, false
	}

	priority, err := strconv.Atoi(line[1:end])
	if err != nil {
		return wpaEvent{}, false
	}

	rest := line[end+1:]
	name, args, _ := strings.Cut(rest, " ")
	if name == "" {
		return wpaEvent{}, false
	}

	return wpaEvent{
		priority: priority,
		name:     name,
		args:     args,
	}, true
}

// Args format: id=%d ssid="%s" auth_failures=%u duration=%d reason=%s, per
// wpas_auth_failed in contrib/wpa/wpa_supplicant/wpa_supplicant.c
// (freebsd-src); the SSID is printf_encoded inside the quotes.
func parseWpaTempDisabled(args string) (ssid string, reason string) {
	if _, after, ok := strings.Cut(args, `ssid="`); ok {
		raw := after
		if end := indexUnescapedQuote(raw); end >= 0 {
			ssid = decodeWpaSSIDText(raw[:end])
		}
	}

	for field := range strings.FieldsSeq(args) {
		if value, ok := strings.CutPrefix(field, "reason="); ok {
			reason = value
			break
		}
	}

	return ssid, reason
}

func indexUnescapedQuote(s string) int {
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '\\':
			i++
		case '"':
			return i
		}
	}

	return -1
}

func (b *WpaSupplicantBackend) StartMonitoring(onStateChange func()) error {
	b.onStateChange = onStateChange

	// Ethernet is independent of wpa_supplicant. On FreeBSD an Ethernet-only
	// machine (or a machine whose wlan clone is not configured yet) still needs
	// link/address updates, but should not poll interfaces for the shell lifetime.
	if b.cmd == nil || b.ifname == "" {
		return b.startEthernetMonitor()
	}

	monitor, err := newWpaCtrlConn(filepath.Join(b.ctrlDir, b.ifname))
	if err != nil {
		return fmt.Errorf("failed to open wpa_ctrl monitor socket: %w", err)
	}

	if err := monitor.attach(); err != nil {
		monitor.close()
		return fmt.Errorf("failed to attach wpa_ctrl monitor: %w", err)
	}

	b.monitor = monitor

	b.sigWG.Add(1)
	go b.monitorLoop()

	return nil
}

func (b *WpaSupplicantBackend) monitorLoop() {
	defer b.sigWG.Done()

	lastActivity := time.Now()
	pingOutstanding := false
	var pingSent time.Time

	for {
		select {
		case <-b.stopChan:
			return
		default:
		}

		msg, err := b.monitor.readDatagram(wpaMonitorReadTimeout)

		switch {
		case err == nil:
			lastActivity = time.Now()

			if strings.HasPrefix(msg, "<") {
				b.handleEvent(msg)
				continue
			}

			if msg == "PONG" {
				pingOutstanding = false
			}

		case isWpaCtrlTimeout(err):
			if pingOutstanding && time.Since(pingSent) > wpaCtrlRequestTimeout {
				b.reattachMonitor()
				pingOutstanding = false
				lastActivity = time.Now()
				continue
			}

			if !pingOutstanding && time.Since(lastActivity) > wpaMonitorPingInterval {
				if b.monitor.send("PING") != nil {
					b.reattachMonitor()
					lastActivity = time.Now()
					continue
				}

				pingOutstanding = true
				pingSent = time.Now()
			}

		default:
			b.reattachMonitor()
			pingOutstanding = false
			lastActivity = time.Now()
		}
	}
}

func (b *WpaSupplicantBackend) reattachMonitor() {
	for {
		select {
		case <-b.stopChan:
			return
		default:
		}

		if err := b.monitor.reconnect(); err == nil {
			if err := b.monitor.attach(); err == nil {
				break
			}
		}

		select {
		case <-b.stopChan:
			return
		case <-time.After(wpaMonitorReconnectDelay):
		}
	}

	log.Infof("wpa_supplicant monitor reattached on %s", b.ifname)

	if err := b.updateSavedWiFiNetworks(); err != nil {
		log.Warnf("failed to refresh saved networks after wpa reattach: %v", err)
	}

	if err := b.updateState(); err != nil {
		log.Warnf("failed to refresh state after wpa reattach: %v", err)
	}

	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *WpaSupplicantBackend) handleEvent(raw string) {
	event, ok := parseWpaEventLine(raw)
	if !ok {
		return
	}

	switch event.name {
	case wpaEventScanResults:
		b.handleScanResults()

	case wpaEventConnected:
		b.handleConnected()

	case wpaEventDisconnected:
		b.handleDisconnected()

	case wpaEventTempDisabled:
		b.handleTempDisabled(event.args)
	}
}

func (b *WpaSupplicantBackend) handleScanResults() {
	if _, err := b.updateWiFiNetworks(); err != nil {
		log.Warnf("failed to update WiFi networks after scan: %v", err)
		return
	}

	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *WpaSupplicantBackend) handleConnected() {
	if err := b.updateState(); err != nil {
		log.Warnf("failed to update wpa state after connect event: %v", err)
	}

	b.attemptMutex.RLock()
	att := b.curAttempt
	b.attemptMutex.RUnlock()

	b.stateMutex.RLock()
	currentSSID := b.state.WiFiSSID
	b.stateMutex.RUnlock()

	if att != nil && att.ssid == currentSSID {
		b.finalizeAttempt(att, "")

		b.attemptMutex.Lock()
		if b.curAttempt == att {
			b.curAttempt = nil
		}
		b.attemptMutex.Unlock()

		return
	}

	if err := b.updateSavedWiFiNetworks(); err != nil {
		log.Warnf("failed to refresh saved networks after connect event: %v", err)
	}

	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *WpaSupplicantBackend) handleDisconnected() {
	if err := b.updateState(); err != nil {
		log.Warnf("failed to update wpa state after disconnect event: %v", err)
	}

	if err := b.updateSavedWiFiNetworks(); err != nil {
		log.Warnf("failed to refresh saved networks after disconnect event: %v", err)
	}

	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *WpaSupplicantBackend) handleTempDisabled(args string) {
	ssid, reason := parseWpaTempDisabled(args)

	b.attemptMutex.RLock()
	att := b.curAttempt
	b.attemptMutex.RUnlock()

	if att == nil || att.ssid != ssid {
		return
	}

	att.mu.Lock()
	att.sawTempDisabled = true
	att.mu.Unlock()

	code := errdefs.ErrConnectionFailed

	// WRONG_KEY is the reason wpas_auth_failed reports for a PSK mismatch
	// (could_be_psk_mismatch path in contrib/wpa/wpa_supplicant/events.c).
	if reason == "WRONG_KEY" {
		code = errdefs.ErrBadCredentials
	}

	b.finalizeAttempt(att, code)

	b.attemptMutex.Lock()
	if b.curAttempt == att {
		b.curAttempt = nil
	}
	b.attemptMutex.Unlock()
}
