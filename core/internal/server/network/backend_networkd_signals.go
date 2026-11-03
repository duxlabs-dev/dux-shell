package network

import (
	"fmt"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

var networkdMatchRules = []string{
	"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path_namespace='/org/freedesktop/network1'",
	"type='signal',interface='org.freedesktop.network1.Manager'",
}

func (b *SystemdNetworkdBackend) StartMonitoring(onStateChange func()) error {
	b.onStateChange = onStateChange

	b.signals = make(chan *dbus.Signal, 64)
	b.conn.Signal(b.signals)

	for _, rule := range networkdMatchRules {
		if err := b.conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0, rule).Err; err != nil {
			return fmt.Errorf("add match %q: %w", rule, err)
		}
	}

	b.sigWG.Add(1)
	go b.signalLoop()

	return nil
}

func (b *SystemdNetworkdBackend) StopMonitoring() {
	b.sigWG.Wait()
}

func (b *SystemdNetworkdBackend) signalLoop() {
	defer b.sigWG.Done()

	for {
		select {
		case <-b.stopChan:
			return
		case sig := <-b.signals:
			if sig == nil {
				continue
			}

			if sig.Name == "org.freedesktop.DBus.Properties.PropertiesChanged" {
				if len(sig.Body) < 2 {
					continue
				}
				iface, ok := sig.Body[0].(string)
				if !ok || iface != networkdLinkIface {
					continue
				}

				b.enumerateLinks()
				if err := b.updateState(); err != nil {
					log.Warnf("networkd state update failed: %v", err)
				}
				if b.onStateChange != nil {
					b.onStateChange()
				}
			}
		}
	}
}
