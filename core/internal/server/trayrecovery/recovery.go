package trayrecovery

import (
	"context"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	sniWatcherDest   = "org.kde.StatusNotifierWatcher"
	sniWatcherPath   = "/StatusNotifierWatcher"
	sniWatcherIface  = "org.kde.StatusNotifierWatcher"
	sniItemIface     = "org.kde.StatusNotifierItem"
	dbusIface        = "org.freedesktop.DBus"
	propsIface       = "org.freedesktop.DBus.Properties"
	probeTimeout     = 300 * time.Millisecond
	connProbeTimeout = 150 * time.Millisecond
	batchSize        = 30
)

var excludedPrefixes = []string{
	"org.freedesktop.",
	"org.gnome.",
	"org.kde.StatusNotifier",
	"com.canonical.AppMenu",
	"org.mpris.",
	"org.pipewire.",
	"org.pulseaudio",
	"fi.epitaph",
	"quickshell",
	"org.kde.quickshell",
}

func (m *Manager) recoverTrayItems() {
	registeredItems := m.getRegisteredItems()
	allNames := m.getDBusNames()
	if allNames == nil {
		return
	}

	registeredConnIDs := m.buildRegisteredConnIDs(registeredItems)

	count := len(registeredItems)
	log.Infof("TrayRecoveryService: scanning DBus for unregistered SNI items (%d already registered)...", count)

	m.scanWellKnownNames(allNames, registeredItems, registeredConnIDs)
	m.scanConnectionIDs(allNames, registeredItems, registeredConnIDs)
}

func (m *Manager) getRegisteredItems() []string {
	obj := m.conn.Object(sniWatcherDest, sniWatcherPath)
	variant, err := obj.GetProperty(sniWatcherIface + ".RegisteredStatusNotifierItems")
	if err != nil {
		log.Warnf("TrayRecoveryService: failed to get registered items: %v", err)
		return nil
	}

	switch v := variant.Value().(type) {
	case []string:
		return v
	case []any:
		items := make([]string, 0, len(v))
		for _, elem := range v {
			if s, ok := elem.(string); ok {
				items = append(items, s)
			}
		}
		return items
	}
	return nil
}

func (m *Manager) getDBusNames() []string {
	var names []string
	err := m.conn.BusObject().Call(dbusIface+".ListNames", 0).Store(&names)
	if err != nil {
		log.Warnf("TrayRecoveryService: failed to list bus names: %v", err)
		return nil
	}
	return names
}

func (m *Manager) getNameOwner(name string) string {
	var owner string
	err := m.conn.BusObject().Call(dbusIface+".GetNameOwner", 0, name).Store(&owner)
	if err != nil {
		return ""
	}
	return owner
}

// buildRegisteredConnIDs resolves every registered SNI item (well-known name
// or :1.xxx connection ID) to a canonical connection ID. This prevents
// duplicates in both directions.
func (m *Manager) buildRegisteredConnIDs(registeredItems []string) map[string]bool {
	connIDs := make(map[string]bool, len(registeredItems))
	for _, item := range registeredItems {
		name := extractName(item)
		if strings.HasPrefix(name, ":1.") {
			connIDs[name] = true
		} else {
			owner := m.getNameOwner(name)
			if owner != "" {
				connIDs[owner] = true
			}
		}
	}
	return connIDs
}

// scanWellKnownNames probes well-known names (e.g. DinoX, nm-applet) for
// unregistered SNI items and re-registers them.
func (m *Manager) scanWellKnownNames(allNames []string, registeredItems []string, registeredConnIDs map[string]bool) {
	registeredRaw := strings.Join(registeredItems, "\n")

	for _, name := range allNames {
		if strings.HasPrefix(name, ":") {
			continue
		}

		if strings.Contains(registeredRaw, name) {
			continue
		}

		// Skip if this name's connection ID is already in the registered set
		// (handles the case where the app registered via connection ID instead)
		connForName := m.getNameOwner(name)
		if connForName != "" && registeredConnIDs[connForName] {
			continue
		}

		if isExcludedName(name) {
			continue
		}

		short := shortName(name)
		objectPaths := []string{
			"/StatusNotifierItem",
			"/org/ayatana/NotificationItem/" + short,
		}

		for _, objPath := range objectPaths {
			if m.probeSNI(name, objPath, probeTimeout) {
				m.registerSNI(name)
				// Update set so the connection-ID section won't double-register this app
				if connForName != "" {
					registeredConnIDs[connForName] = true
				}
				break
			}
		}
	}
}

// scanConnectionIDs probes all :1.xxx connections in parallel for unregistered
// SNI items (e.g. Vesktop, Electron apps). Most non-SNI connections return an
// error instantly, so this is fast.
func (m *Manager) scanConnectionIDs(allNames []string, registeredItems []string, registeredConnIDs map[string]bool) {
	registeredRaw := strings.Join(registeredItems, "\n")
	registeredLower := strings.ToLower(registeredRaw)

	var wg sync.WaitGroup
	sem := make(chan struct{}, batchSize)

	for _, name := range allNames {
		if !strings.HasPrefix(name, ":1.") {
			continue
		}
		if registeredConnIDs[name] {
			continue
		}

		sem <- struct{}{}
		wg.Add(1)
		go func(conn string) {
			defer wg.Done()
			defer func() { <-sem }()

			sniID := m.getSNIId(conn, connProbeTimeout)
			if sniID == "" {
				return
			}

			// Skip if an item with the same Id is already registered (case-insensitive)
			if strings.Contains(registeredLower, strings.ToLower(sniID)) {
				return
			}

			m.registerSNI(conn)
			log.Infof("TrayRecovery: re-registered %s (Id: %s)", conn, sniID)
		}(name)
	}
	wg.Wait()
}

func (m *Manager) probeSNI(dest, path string, timeout time.Duration) bool {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	obj := m.conn.Object(dest, dbus.ObjectPath(path))
	var props map[string]dbus.Variant
	err := obj.CallWithContext(ctx, propsIface+".GetAll", 0, sniItemIface).Store(&props)
	if err != nil {
		return false
	}

	_, hasID := props["Id"]
	return hasID
}

func (m *Manager) getSNIId(dest string, timeout time.Duration) string {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	obj := m.conn.Object(dest, "/StatusNotifierItem")
	var variant dbus.Variant
	err := obj.CallWithContext(ctx, propsIface+".Get", 0, sniItemIface, "Id").Store(&variant)
	if err != nil {
		return ""
	}

	id, _ := variant.Value().(string)
	return id
}

func (m *Manager) registerSNI(name string) {
	obj := m.conn.Object(sniWatcherDest, sniWatcherPath)
	call := obj.Call(sniWatcherIface+".RegisterStatusNotifierItem", 0, name)
	if call.Err != nil {
		log.Warnf("TrayRecovery: failed to register %s: %v", name, call.Err)
		return
	}
	log.Infof("TrayRecovery: re-registered %s", name)
}

func extractName(item string) string {
	if before, _, ok := strings.Cut(item, "/"); ok {
		return before
	}
	return item
}

func shortName(name string) string {
	parts := strings.Split(name, ".")
	if len(parts) > 0 {
		return parts[len(parts)-1]
	}
	return name
}

func isExcludedName(name string) bool {
	for _, prefix := range excludedPrefixes {
		if strings.HasPrefix(name, prefix) {
			return true
		}
	}
	return false
}
