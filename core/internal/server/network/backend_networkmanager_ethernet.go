package network

import (
	"errors"
	"fmt"
	"maps"
	"net"
	"slices"
	"strconv"
	"strings"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

func (b *NetworkManagerBackend) GetWiredConnections() ([]WiredConnection, error) {
	return b.listEthernetConnections()
}

func (b *NetworkManagerBackend) GetWiredNetworkDetails(uuid string) (*WiredNetworkInfoResponse, error) {
	var dev gonetworkmanager.Device
	for _, info := range b.sortedEthernetDevices() {
		if activeConnectionUUID(info.device) == uuid {
			dev = info.device
			break
		}
	}
	if dev == nil && b.ethernetDevice != nil {
		dev = b.ethernetDevice.(gonetworkmanager.Device)
	}
	if dev == nil {
		return nil, fmt.Errorf("no ethernet device available")
	}

	iface, _ := dev.GetPropertyInterface()
	driver, _ := dev.GetPropertyDriver()

	hwAddr := "Not available"
	var speed uint32 = 0
	wiredDevice, err := gonetworkmanager.NewDeviceWired(dev.GetPath())
	if err == nil {
		hwAddr, _ = wiredDevice.GetPropertyHwAddress()
		speed, _ = wiredDevice.GetPropertySpeed()
	}
	var ipv4Config WiredIPConfig
	var ipv6Config WiredIPConfig

	activeConn, err := dev.GetPropertyActiveConnection()
	if err == nil && activeConn != nil {
		ip4Config, err := activeConn.GetPropertyIP4Config()
		if err == nil && ip4Config != nil {
			var ips []string
			addresses, err := ip4Config.GetPropertyAddressData()
			if err == nil && len(addresses) > 0 {
				for _, addr := range addresses {
					ips = append(ips, fmt.Sprintf("%s/%s", addr.Address, strconv.Itoa(int(addr.Prefix))))
				}
			}

			gateway, _ := ip4Config.GetPropertyGateway()
			dnsAddrs := ""
			dns, err := ip4Config.GetPropertyNameserverData()
			if err == nil && len(dns) > 0 {
				for _, d := range dns {
					if len(dnsAddrs) > 0 {
						dnsAddrs = strings.Join([]string{dnsAddrs, d.Address}, "; ")
					} else {
						dnsAddrs = d.Address
					}
				}
			}

			ipv4Config = WiredIPConfig{
				IPs:     ips,
				Gateway: gateway,
				DNS:     dnsAddrs,
			}
		}

		ip6Config, err := activeConn.GetPropertyIP6Config()
		if err == nil && ip6Config != nil {
			var ips []string
			addresses, err := ip6Config.GetPropertyAddressData()
			if err == nil && len(addresses) > 0 {
				for _, addr := range addresses {
					ips = append(ips, fmt.Sprintf("%s/%s", addr.Address, strconv.Itoa(int(addr.Prefix))))
				}
			}

			gateway, _ := ip6Config.GetPropertyGateway()
			dnsAddrs := ""
			dns, err := ip6Config.GetPropertyNameservers()
			if err == nil && len(dns) > 0 {
				for _, d := range dns {
					if len(d) == 16 {
						ip := net.IP(d)
						if len(dnsAddrs) > 0 {
							dnsAddrs = strings.Join([]string{dnsAddrs, ip.String()}, "; ")
						} else {
							dnsAddrs = ip.String()
						}
					}
				}
			}

			ipv6Config = WiredIPConfig{
				IPs:     ips,
				Gateway: gateway,
				DNS:     dnsAddrs,
			}
		}
	}

	return &WiredNetworkInfoResponse{
		UUID:   uuid,
		IFace:  iface,
		Driver: driver,
		HwAddr: hwAddr,
		Speed:  strconv.Itoa(int(speed)),
		IPv4:   ipv4Config,
		IPv6:   ipv6Config,
	}, nil
}

// nmAutoConnection stands in for the "/" connection path; only GetPath is ever called on it.
type nmAutoConnection struct{ gonetworkmanager.Connection }

func (nmAutoConnection) GetPath() dbus.ObjectPath { return "/" }

type wiredProfile struct {
	conn      gonetworkmanager.Connection
	id        string
	uuid      string
	ifaceName string
	mac       []byte
	isPort    bool
}

func profileFitsEthernetDevice(ifaceName string, mac []byte, devName, devHw string) bool {
	if ifaceName != "" && ifaceName != devName {
		return false
	}
	return len(mac) == 0 || strings.EqualFold(net.HardwareAddr(mac).String(), devHw)
}

// fits reports whether the profile can serve the device. Bond and bridge ports never do.
func (p wiredProfile) fits(devName, devHw string) bool {
	return !p.isPort && profileFitsEthernetDevice(p.ifaceName, p.mac, devName, devHw)
}

func (b *NetworkManagerBackend) listWiredProfiles() ([]wiredProfile, error) {
	settingsMgr, err := b.networkManagerSettings()
	if err != nil {
		return nil, err
	}
	connections, err := settingsMgr.ListConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to get connections: %w", err)
	}

	profiles := make([]wiredProfile, 0)
	for _, conn := range connections {
		settings, err := conn.GetSettings()
		if err != nil {
			log.Errorf("unable to get settings for %s: %v", conn.GetPath(), err)
			continue
		}
		connMeta := settings["connection"]
		if connType, _ := connMeta["type"].(string); connType != "802-3-ethernet" {
			continue
		}
		p := wiredProfile{conn: conn}
		p.id, _ = connMeta["id"].(string)
		p.uuid, _ = connMeta["uuid"].(string)
		p.ifaceName, _ = connMeta["interface-name"].(string)
		p.mac, _ = settings["802-3-ethernet"]["mac-address"].([]byte)
		controller, _ := connMeta["controller"].(string)
		master, _ := connMeta["master"].(string)
		p.isPort = controller != "" || master != ""
		profiles = append(profiles, p)
	}
	return profiles, nil
}

func (b *NetworkManagerBackend) sortedEthernetDevices() []*ethernetDeviceInfo {
	snapshot := b.ethernetDevicesSnapshot()
	devices := make([]*ethernetDeviceInfo, 0, len(snapshot))
	for _, name := range slices.Sorted(maps.Keys(snapshot)) {
		devices = append(devices, snapshot[name])
	}
	return devices
}

func activeConnectionUUID(dev gonetworkmanager.Device) string {
	ac, err := dev.GetPropertyActiveConnection()
	if err != nil || ac == nil {
		return ""
	}
	uuid, _ := ac.GetPropertyUUID()
	return uuid
}

func (b *NetworkManagerBackend) refreshEthernet() {
	b.updateAllEthernetDevices()
	b.updateEthernetState()
	b.listEthernetConnections()
	b.updatePrimaryConnection()

	if b.onStateChange != nil {
		b.onStateChange()
	}
}

func (b *NetworkManagerBackend) ConnectEthernet() error {
	for _, info := range b.sortedEthernetDevices() {
		state, _ := info.device.GetPropertyState()
		if state == gonetworkmanager.NmDeviceStateUnavailable || state == gonetworkmanager.NmDeviceStateUnmanaged {
			continue
		}
		return b.ConnectEthernetDevice(info.name)
	}
	return fmt.Errorf("no ethernet device available")
}

func (b *NetworkManagerBackend) ConnectEthernetDevice(device string) error {
	info, ok := b.ethernetDeviceByIface(device)
	if !ok {
		return fmt.Errorf("ethernet device %s not found", device)
	}

	profiles, err := b.listWiredProfiles()
	if err != nil {
		return err
	}
	fits := slices.ContainsFunc(profiles, func(p wiredProfile) bool {
		return p.fits(info.name, info.profileMAC())
	})

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	if fits {
		// The "/" connection lets NM pick the best profile for the device.
		if _, err := nm.ActivateConnection(nmAutoConnection{}, info.device, nil); err != nil {
			return fmt.Errorf("failed to activate ethernet: %w", err)
		}
	} else {
		settings := map[string]map[string]any{
			"connection": {"id": "Wired connection", "type": "802-3-ethernet"},
		}
		if _, err := nm.AddAndActivateConnection(settings, info.device); err != nil {
			return fmt.Errorf("failed to create and activate ethernet: %w", err)
		}
	}

	b.refreshEthernet()
	return nil
}

func (b *NetworkManagerBackend) DisconnectEthernet() error {
	devices := b.sortedEthernetDevices()
	if len(devices) == 0 {
		return fmt.Errorf("no ethernet device available")
	}

	var errs []error
	for _, info := range devices {
		if err := b.deactivateEthernetDevice(info); err != nil {
			errs = append(errs, err)
		}
	}

	b.refreshEthernet()
	return errors.Join(errs...)
}

func (b *NetworkManagerBackend) DisconnectEthernetDevice(device string) error {
	info, ok := b.ethernetDeviceByIface(device)
	if !ok {
		return fmt.Errorf("ethernet device %s not found", device)
	}

	if err := b.deactivateEthernetDevice(info); err != nil {
		return err
	}

	b.refreshEthernet()
	return nil
}

func (b *NetworkManagerBackend) deactivateEthernetDevice(info *ethernetDeviceInfo) error {
	active, err := info.device.GetPropertyActiveConnection()
	if err != nil {
		return fmt.Errorf("failed to get active connection of %s: %w", info.name, err)
	}
	if active == nil {
		return nil
	}

	if err := info.device.Disconnect(); err != nil {
		return fmt.Errorf("failed to disconnect %s: %w", info.name, err)
	}
	return nil
}

func (b *NetworkManagerBackend) ActivateWiredConnection(uuid, device string) error {
	var dev gonetworkmanager.Device
	if device != "" {
		info, ok := b.ethernetDeviceByIface(device)
		if !ok {
			return fmt.Errorf("ethernet device %s not found", device)
		}
		dev = info.device
	}

	settingsMgr, err := b.networkManagerSettings()
	if err != nil {
		return err
	}
	conn, err := settingsMgr.GetConnectionByUUID(uuid)
	if err != nil || conn == nil {
		return fmt.Errorf("connection with UUID %s not found", uuid)
	}

	nm := b.nmConn.(gonetworkmanager.NetworkManager)
	if _, err := nm.ActivateConnection(conn, dev, nil); err != nil {
		return fmt.Errorf("error activation connection: %w", err)
	}

	b.refreshEthernet()
	return nil
}

func (b *NetworkManagerBackend) listEthernetConnections() ([]WiredConnection, error) {
	devices := b.sortedEthernetDevices()
	if len(devices) == 0 {
		return nil, fmt.Errorf("no ethernet device available")
	}

	profiles, err := b.listWiredProfiles()
	if err != nil {
		return nil, err
	}

	activeUUIDs, err := b.getActiveConnections()
	if err != nil {
		return nil, fmt.Errorf("failed to get active wired connections: %w", err)
	}

	activeDevice := make(map[string]string, len(devices))
	fit := make(map[string][]string, len(devices))
	for _, info := range devices {
		if uuid := activeConnectionUUID(info.device); uuid != "" {
			activeDevice[uuid] = info.name
		}
		for _, p := range profiles {
			if p.fits(info.name, info.profileMAC()) {
				fit[info.name] = append(fit[info.name], p.uuid)
			}
		}
	}

	wiredConfigs := make([]WiredConnection, 0, len(profiles))
	currentUuid := ""
	for _, p := range profiles {
		wiredConfigs = append(wiredConfigs, WiredConnection{
			Path:     p.conn.GetPath(),
			ID:       p.id,
			UUID:     p.uuid,
			Type:     "802-3-ethernet",
			IsActive: activeUUIDs[p.uuid],
			Device:   activeDevice[p.uuid],
		})
		if activeUUIDs[p.uuid] {
			currentUuid = p.uuid
		}
	}

	b.stateMutex.Lock()
	b.state.EthernetConnectionUuid = currentUuid
	b.state.WiredConnections = wiredConfigs
	b.ethernetProfileFit = fit
	for i := range b.state.EthernetDevices {
		b.state.EthernetDevices[i].ProfileUUIDs = append([]string{}, fit[b.state.EthernetDevices[i].Name]...)
	}
	b.stateMutex.Unlock()

	return wiredConfigs, nil
}

func (b *NetworkManagerBackend) GetEthernetDevices() []EthernetDevice {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()
	return append([]EthernetDevice(nil), b.state.EthernetDevices...)
}

func (b *NetworkManagerBackend) updateAllEthernetDevices() {
	ethernetDevices := b.sortedEthernetDevices()
	devices := make([]EthernetDevice, 0, len(ethernetDevices))

	for _, info := range ethernetDevices {
		name := info.name
		state, _ := info.device.GetPropertyState()
		connected := state == gonetworkmanager.NmDeviceStateActivated
		driver, _ := info.device.GetPropertyDriver()

		var ip string
		var speed uint32 = 0
		if connected {
			ip = b.getDeviceIP(info.device)
		}
		if info.wired != nil {
			speed, _ = info.wired.GetPropertySpeed()
		}

		stateStr := "disconnected"
		switch state {
		case gonetworkmanager.NmDeviceStateActivated:
			stateStr = "activated"
		case gonetworkmanager.NmDeviceStatePrepare:
			stateStr = "preparing"
		case gonetworkmanager.NmDeviceStateConfig:
			stateStr = "configuring"
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

		devices = append(devices, EthernetDevice{
			Name:      name,
			HwAddress: info.hwAddress,
			State:     stateStr,
			Connected: connected,
			IP:        ip,
			Speed:     speed,
			Driver:    driver,

			ConnectionUUID: activeConnectionUUID(info.device),
		})
	}

	// Read the fit under the write lock so a concurrent profile scan isn't overwritten.
	b.stateMutex.Lock()
	for i := range devices {
		devices[i].ProfileUUIDs = append([]string{}, b.ethernetProfileFit[devices[i].Name]...)
	}
	b.state.EthernetDevices = devices
	b.stateMutex.Unlock()
}
