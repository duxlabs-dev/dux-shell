package network

import (
	"fmt"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

func isCellularConnectionType(connType string) bool {
	return connType == "gsm" || connType == "cdma"
}

func (b *NetworkManagerBackend) GetCellularConnections() ([]WiredConnection, error) {
	return b.listCellularConnections()
}

func (b *NetworkManagerBackend) GetCellularDevices() []CellularDevice {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()
	return append([]CellularDevice(nil), b.state.CellularDevices...)
}

func (b *NetworkManagerBackend) GetCellularEnabled() (bool, error) {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	return nm.GetPropertyWwanEnabled()
}

func (b *NetworkManagerBackend) SetCellularEnabled(enabled bool) error {
	conn := b.dbusConn
	closeConn := false
	if conn == nil {
		var err error
		conn, err = dbus.ConnectSystemBus()
		if err != nil {
			return fmt.Errorf("failed to connect to system bus: %w", err)
		}
		closeConn = true
	}
	if closeConn {
		defer conn.Close()
	}

	obj := conn.Object(dbusNMInterface, dbus.ObjectPath(dbusNMPath))
	if err := obj.SetProperty(dbusNMInterface+".WwanEnabled", dbus.MakeVariant(enabled)); err != nil {
		return fmt.Errorf("failed to set cellular enabled: %w", err)
	}

	b.updateCellularRadioState()
	b.refreshCellularState()

	return nil
}

func (b *NetworkManagerBackend) ConnectCellular() error {
	if b.cellularDevice == nil {
		return fmt.Errorf("no cellular modem available")
	}

	if err := b.ensureCellularEnabled(); err != nil {
		return err
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	dev := b.cellularDevice.(gonetworkmanager.Device)

	settingsMgr, err := gonetworkmanager.NewSettings()
	if err != nil {
		return fmt.Errorf("failed to get settings: %w", err)
	}

	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return fmt.Errorf("failed to get connections: %w", err)
	}

	for _, conn := range connections {
		connSettings, err := conn.GetSettings()
		if err != nil {
			continue
		}

		if connMeta, ok := connSettings["connection"]; ok {
			if connType, ok := connMeta["type"].(string); ok && isCellularConnectionType(connType) {
				if _, err := nm.ActivateConnection(conn, dev, nil); err != nil {
					return fmt.Errorf("failed to activate cellular connection: %w", err)
				}

				b.refreshCellularState()
				return nil
			}
		}
	}

	settings := map[string]map[string]any{
		"connection": {
			"id":   "Mobile broadband",
			"type": "gsm",
		},
		"gsm": {
			"auto-config": true,
		},
		"ipv4": {
			"method": "auto",
		},
		"ipv6": {
			"method": "auto",
		},
	}

	if _, err := nm.AddAndActivateConnection(settings, dev); err != nil {
		// Older NetworkManager/ModemManager stacks reject gsm.auto-config
		delete(settings["gsm"], "auto-config")
		if _, retryErr := nm.AddAndActivateConnection(settings, dev); retryErr != nil {
			return fmt.Errorf("failed to create and activate cellular connection: %w", retryErr)
		}
	}

	b.refreshCellularState()
	return nil
}

func (b *NetworkManagerBackend) refreshCellularState() {
	b.updateAllCellularDevices()
	b.updateCellularState()
	b.listCellularConnections()
	b.updatePrimaryConnection()
	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *NetworkManagerBackend) DisconnectCellular() error {
	if b.cellularDevice == nil {
		return fmt.Errorf("no cellular modem available")
	}

	dev := b.cellularDevice.(gonetworkmanager.Device)
	if err := dev.Disconnect(); err != nil {
		return fmt.Errorf("failed to disconnect cellular modem: %w", err)
	}

	b.refreshCellularState()

	return nil
}

func (b *NetworkManagerBackend) DisconnectCellularDevice(device string) error {
	info, ok := b.cellularDeviceByIface(device)
	if !ok {
		return fmt.Errorf("cellular modem %s not found", device)
	}

	if err := info.device.Disconnect(); err != nil {
		return fmt.Errorf("failed to disconnect %s: %w", device, err)
	}

	b.refreshCellularState()

	return nil
}

func (b *NetworkManagerBackend) ActivateCellularConnection(uuid string) error {
	if b.cellularDevice == nil {
		return fmt.Errorf("no cellular modem available")
	}

	if err := b.ensureCellularEnabled(); err != nil {
		return err
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	dev := b.cellularDevice.(gonetworkmanager.Device)

	settingsMgr, err := gonetworkmanager.NewSettings()
	if err != nil {
		return fmt.Errorf("failed to get settings: %w", err)
	}

	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return fmt.Errorf("failed to get connections: %w", err)
	}

	var targetConnection gonetworkmanager.Connection
	for _, conn := range connections {
		settings, err := conn.GetSettings()
		if err != nil {
			continue
		}

		connectionSettings := settings["connection"]
		connType, _ := connectionSettings["type"].(string)
		connUUID, _ := connectionSettings["uuid"].(string)
		if connUUID == uuid && isCellularConnectionType(connType) {
			targetConnection = conn
			break
		}
	}

	if targetConnection == nil {
		return fmt.Errorf("cellular connection with UUID %s not found", uuid)
	}

	if _, err := nm.ActivateConnection(targetConnection, dev, nil); err != nil {
		return fmt.Errorf("failed to activate cellular connection: %w", err)
	}

	b.refreshCellularState()

	return nil
}

func (b *NetworkManagerBackend) listCellularConnections() ([]WiredConnection, error) {
	if b.cellularDevice == nil {
		b.stateMutex.Lock()
		b.state.CellularConnectionUuid = ""
		b.state.CellularConnections = []WiredConnection{}
		b.stateMutex.Unlock()
		return nil, nil
	}

	s := b.settings
	if s == nil {
		settings, err := gonetworkmanager.NewSettings()
		if err != nil {
			return nil, fmt.Errorf("failed to get settings: %w", err)
		}
		b.settings = settings
		s = settings
	}

	settingsMgr := s.(gonetworkmanager.Settings)
	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to get connections: %w", err)
	}

	activeUUIDs, err := b.getActiveConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to get active cellular connections: %w", err)
	}

	configs := make([]WiredConnection, 0)
	currentUUID := ""
	for _, connection := range connections {
		path := connection.GetPath()
		settings, err := connection.GetSettings()
		if err != nil {
			log.Errorf("unable to get settings for %s: %v", path, err)
			continue
		}

		connectionSettings := settings["connection"]
		connType, _ := connectionSettings["type"].(string)
		connID, _ := connectionSettings["id"].(string)
		connUUID, _ := connectionSettings["uuid"].(string)

		if isCellularConnectionType(connType) {
			configs = append(configs, WiredConnection{
				Path:     path,
				ID:       connID,
				UUID:     connUUID,
				Type:     connType,
				IsActive: activeUUIDs[connUUID],
			})
			if activeUUIDs[connUUID] {
				currentUUID = connUUID
			}
		}
	}

	b.stateMutex.Lock()
	b.state.CellularConnectionUuid = currentUUID
	b.state.CellularConnections = configs
	b.stateMutex.Unlock()

	return configs, nil
}

func (b *NetworkManagerBackend) updateAllCellularDevices() {
	cellularDevices := b.cellularDevicesSnapshot()
	devices := make([]CellularDevice, 0, len(cellularDevices))

	for name, info := range cellularDevices {
		state, _ := info.device.GetPropertyState()
		connected := state == gonetworkmanager.NmDeviceStateActivated
		driver, _ := info.device.GetPropertyDriver()

		var ip string
		if connected {
			ip = b.getDeviceIP(info.device)
		}

		stateStr := "disconnected"
		switch state {
		case gonetworkmanager.NmDeviceStateActivated:
			stateStr = "activated"
		case gonetworkmanager.NmDeviceStatePrepare:
			stateStr = "preparing"
		case gonetworkmanager.NmDeviceStateConfig:
			stateStr = "configuring"
		case gonetworkmanager.NmDeviceStateNeedAuth:
			stateStr = "need-auth"
		case gonetworkmanager.NmDeviceStateIpConfig:
			stateStr = "ip-config"
		case gonetworkmanager.NmDeviceStateIpCheck:
			stateStr = "ip-check"
		case gonetworkmanager.NmDeviceStateSecondaries:
			stateStr = "secondaries"
		case gonetworkmanager.NmDeviceStateDeactivating:
			stateStr = "deactivating"
		case gonetworkmanager.NmDeviceStateFailed:
			stateStr = "failed"
		case gonetworkmanager.NmDeviceStateUnavailable:
			stateStr = "unavailable"
		case gonetworkmanager.NmDeviceStateUnmanaged:
			stateStr = "unmanaged"
		}

		modem, _ := b.modemForIface(name, len(cellularDevices))

		devices = append(devices, CellularDevice{
			Name:          name,
			HwAddress:     info.hwAddress,
			State:         stateStr,
			Connected:     connected,
			IP:            ip,
			Driver:        driver,
			Description:   info.description,
			SignalQuality: modem.signalQuality,
			AccessTech:    modem.accessTech,
		})
	}

	b.stateMutex.Lock()
	b.state.CellularDevices = devices
	b.stateMutex.Unlock()
}

func (b *NetworkManagerBackend) ensureCellularEnabled() error {
	enabled, err := b.GetCellularEnabled()
	if err != nil {
		return fmt.Errorf("failed to get cellular radio state: %w", err)
	}
	if enabled {
		return nil
	}
	return b.SetCellularEnabled(true)
}

func (b *NetworkManagerBackend) updateCellularRadioState() {
	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	enabled, enabledErr := nm.GetPropertyWwanEnabled()
	hardwareEnabled, hardwareErr := nm.GetPropertyWwanHardwareEnabled()

	b.stateMutex.Lock()
	if enabledErr == nil {
		b.state.CellularEnabled = enabled
	}
	if hardwareErr == nil {
		b.state.CellularHardwareEnabled = hardwareEnabled
	}
	b.stateMutex.Unlock()
}
