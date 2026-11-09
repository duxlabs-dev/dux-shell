package network

import (
	"fmt"
	"net"
	"strings"
)

func (b *SystemdNetworkdBackend) GetWiredConnections() ([]WiredConnection, error) {
	b.linksMutex.RLock()
	defer b.linksMutex.RUnlock()

	var conns []WiredConnection
	for name, link := range b.links {
		if !link.isWired() {
			continue
		}

		active := link.opState == "routable" || link.opState == "carrier"
		conns = append(conns, WiredConnection{
			Path:     link.path,
			ID:       name,
			UUID:     "wired:" + name,
			Type:     "ethernet",
			IsActive: active,
		})
	}

	return conns, nil
}

func (b *SystemdNetworkdBackend) GetWiredNetworkDetails(id string) (*WiredNetworkInfoResponse, error) {
	ifname := strings.TrimPrefix(id, "wired:")

	b.linksMutex.RLock()
	_, exists := b.links[ifname]
	b.linksMutex.RUnlock()

	if !exists {
		return nil, fmt.Errorf("interface %s not found", ifname)
	}

	iface, err := net.InterfaceByName(ifname)
	if err != nil {
		return nil, fmt.Errorf("get interface: %w", err)
	}

	addrs, _ := iface.Addrs()
	var ipv4s, ipv6s []string
	for _, addr := range addrs {
		if ipnet, ok := addr.(*net.IPNet); ok {
			if ipv4 := ipnet.IP.To4(); ipv4 != nil {
				ipv4s = append(ipv4s, ipnet.String())
			} else if ipv6 := ipnet.IP.To16(); ipv6 != nil {
				ipv6s = append(ipv6s, ipnet.String())
			}
		}
	}

	return &WiredNetworkInfoResponse{
		UUID:   id,
		IFace:  ifname,
		HwAddr: iface.HardwareAddr.String(),
		IPv4: WiredIPConfig{
			IPs: ipv4s,
		},
		IPv6: WiredIPConfig{
			IPs: ipv6s,
		},
	}, nil
}

func (b *SystemdNetworkdBackend) ConnectEthernet() error {
	b.linksMutex.RLock()
	var primaryWired *linkInfo
	for _, l := range b.links {
		if !l.isWired() {
			continue
		}
		primaryWired = l
		break
	}
	b.linksMutex.RUnlock()

	if primaryWired == nil {
		return fmt.Errorf("no wired interface found")
	}

	linkObj := b.conn.Object(networkdBusName, primaryWired.path)
	return linkObj.Call(networkdLinkIface+".Reconfigure", 0).Err
}

func (b *SystemdNetworkdBackend) ConnectEthernetDevice(device string) error {
	return b.ActivateWiredConnection(device, "")
}

func (b *SystemdNetworkdBackend) DisconnectEthernet() error {
	return fmt.Errorf("not supported by networkd backend")
}

func (b *SystemdNetworkdBackend) ActivateWiredConnection(id, _ string) error {
	ifname := strings.TrimPrefix(id, "wired:")

	b.linksMutex.RLock()
	link, exists := b.links[ifname]
	b.linksMutex.RUnlock()

	if !exists {
		return fmt.Errorf("interface %s not found", ifname)
	}

	linkObj := b.conn.Object(networkdBusName, link.path)
	return linkObj.Call(networkdLinkIface+".Reconfigure", 0).Err
}

func (b *SystemdNetworkdBackend) GetEthernetDevices() []EthernetDevice {
	b.stateMutex.RLock()
	defer b.stateMutex.RUnlock()
	return append([]EthernetDevice(nil), b.state.EthernetDevices...)
}

func (b *SystemdNetworkdBackend) DisconnectEthernetDevice(device string) error {
	return fmt.Errorf("not supported by networkd backend")
}
