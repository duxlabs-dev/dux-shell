package network

import (
	"sync"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/godbus/dbus/v5"
)

type NetworkStatus string

const (
	StatusDisconnected NetworkStatus = "disconnected"
	StatusEthernet     NetworkStatus = "ethernet"
	StatusWiFi         NetworkStatus = "wifi"
	StatusCellular     NetworkStatus = "cellular"
	StatusVPN          NetworkStatus = "vpn"
)

type ConnectionPreference string

const (
	PreferenceAuto     ConnectionPreference = "auto"
	PreferenceWiFi     ConnectionPreference = "wifi"
	PreferenceEthernet ConnectionPreference = "ethernet"
	PreferenceCellular ConnectionPreference = "cellular"
)

type WiFiNetwork struct {
	SSID        string `json:"ssid"`
	BSSID       string `json:"bssid"`
	Signal      uint8  `json:"signal"`
	Secured     bool   `json:"secured"`
	Enterprise  bool   `json:"enterprise"`
	Connected   bool   `json:"connected"`
	Saved       bool   `json:"saved"`
	Autoconnect bool   `json:"autoconnect"`
	Hidden      bool   `json:"hidden"`
	OutOfRange  bool   `json:"outOfRange"`
	Frequency   uint32 `json:"frequency"`
	Mode        string `json:"mode"`
	Rate        uint32 `json:"rate"`
	Channel     uint32 `json:"channel"`
	Device      string `json:"device,omitempty"`
}

type WiFiDevice struct {
	Name      string        `json:"name"`
	HwAddress string        `json:"hwAddress"`
	State     string        `json:"state"`
	Connected bool          `json:"connected"`
	APCapable bool          `json:"apCapable"`
	SSID      string        `json:"ssid,omitempty"`
	BSSID     string        `json:"bssid,omitempty"`
	Signal    uint8         `json:"signal,omitempty"`
	IP        string        `json:"ip,omitempty"`
	Networks  []WiFiNetwork `json:"networks"`
}

type EthernetDevice struct {
	Name      string `json:"name"`
	HwAddress string `json:"hwAddress"`
	State     string `json:"state"`
	Connected bool   `json:"connected"`
	IP        string `json:"ip,omitempty"`
	Speed     uint32 `json:"speed,omitempty"`
	Driver    string `json:"driver,omitempty"`
}

type CellularDevice struct {
	Name        string `json:"name"`
	HwAddress   string `json:"hwAddress"`
	State       string `json:"state"`
	Connected   bool   `json:"connected"`
	IP          string `json:"ip,omitempty"`
	Driver      string `json:"driver,omitempty"`
	Description string `json:"description,omitempty"`
	// SignalQuality is a 0-100 percentage from ModemManager, 0 when unknown.
	SignalQuality uint32 `json:"signalQuality"`
	AccessTech    string `json:"accessTech,omitempty"`
}

type VPNProfile struct {
	Name        string            `json:"name"`
	UUID        string            `json:"uuid"`
	Type        string            `json:"type"`
	ServiceType string            `json:"serviceType"`
	RemoteHost  string            `json:"remoteHost,omitempty"`
	Username    string            `json:"username,omitempty"`
	Autoconnect bool              `json:"autoconnect"`
	Data        map[string]string `json:"data,omitempty"`
}

type VPNActive struct {
	Name       string            `json:"name"`
	UUID       string            `json:"uuid"`
	Device     string            `json:"device,omitempty"`
	State      string            `json:"state,omitempty"`
	Type       string            `json:"type"`
	Plugin     string            `json:"serviceType"`
	IP         string            `json:"ip,omitempty"`
	Gateway    string            `json:"gateway,omitempty"`
	RemoteHost string            `json:"remoteHost,omitempty"`
	Username   string            `json:"username,omitempty"`
	MTU        uint32            `json:"mtu,omitempty"`
	Data       map[string]string `json:"data,omitempty"`
}

type VPNState struct {
	Profiles []VPNProfile `json:"profiles"`
	Active   []VPNActive  `json:"activeConnections"`
}

type NetworkState struct {
	Backend                 string               `json:"backend"`
	NetworkStatus           NetworkStatus        `json:"networkStatus"`
	Preference              ConnectionPreference `json:"preference"`
	EthernetIP              string               `json:"ethernetIP"`
	EthernetDevice          string               `json:"ethernetDevice"`
	EthernetConnected       bool                 `json:"ethernetConnected"`
	EthernetConnectionUuid  string               `json:"ethernetConnectionUuid"`
	EthernetDevices         []EthernetDevice     `json:"ethernetDevices"`
	CellularIP              string               `json:"cellularIP"`
	CellularDevice          string               `json:"cellularDevice"`
	CellularConnected       bool                 `json:"cellularConnected"`
	CellularEnabled         bool                 `json:"cellularEnabled"`
	CellularHardwareEnabled bool                 `json:"cellularHardwareEnabled"`
	CellularConnectionUuid  string               `json:"cellularConnectionUuid"`
	CellularDevices         []CellularDevice     `json:"cellularDevices"`
	CellularConnections     []WiredConnection    `json:"cellularConnections"`
	WiFiIP                  string               `json:"wifiIP"`
	WiFiDevice              string               `json:"wifiDevice"`
	WiFiConnected           bool                 `json:"wifiConnected"`
	WiFiEnabled             bool                 `json:"wifiEnabled"`
	WiFiSSID                string               `json:"wifiSSID"`
	WiFiBSSID               string               `json:"wifiBSSID"`
	WiFiSignal              uint8                `json:"wifiSignal"`
	WiFiNetworks            []WiFiNetwork        `json:"wifiNetworks"`
	SavedWiFiNetworks       []WiFiNetwork        `json:"savedWifiNetworks"`
	WiFiDevices             []WiFiDevice         `json:"wifiDevices"`
	HotspotSupported        bool                 `json:"hotspotSupported"`
	HotspotAvailable        bool                 `json:"hotspotAvailable"`
	HotspotConfigured       bool                 `json:"hotspotConfigured"`
	HotspotEnabled          bool                 `json:"hotspotEnabled"`
	HotspotActivating       bool                 `json:"hotspotActivating"`
	HotspotSecured          bool                 `json:"hotspotSecured"`
	HotspotSSID             string               `json:"hotspotSSID"`
	HotspotDevice           string               `json:"hotspotDevice"`
	HotspotBand             string               `json:"hotspotBand"`
	HotspotLastError        string               `json:"hotspotLastError"`
	WiredConnections        []WiredConnection    `json:"wiredConnections"`
	VPNProfiles             []VPNProfile         `json:"vpnProfiles"`
	VPNActive               []VPNActive          `json:"vpnActive"`
	IsConnecting            bool                 `json:"isConnecting"`
	ConnectingSSID          string               `json:"connectingSSID"`
	ConnectingDevice        string               `json:"connectingDevice,omitempty"`
	LastError               string               `json:"lastError"`
	VPNError                string               `json:"vpnError"`
	VPNErrorUuid            string               `json:"vpnErrorUuid"`
}

type ConnectionRequest struct {
	SSID              string `json:"ssid"`
	Password          string `json:"password,omitempty"`
	Username          string `json:"username,omitempty"`
	AnonymousIdentity string `json:"anonymousIdentity,omitempty"`
	DomainSuffixMatch string `json:"domainSuffixMatch,omitempty"`
	Interactive       bool   `json:"interactive,omitempty"`
	Hidden            bool   `json:"hidden,omitempty"`
	Device            string `json:"device,omitempty"`
	EAPMethod         string `json:"eapMethod,omitempty"`
	Phase2Auth        string `json:"phase2Auth,omitempty"`
	CACertPath        string `json:"caCertPath,omitempty"`
	ClientCertPath    string `json:"clientCertPath,omitempty"`
	PrivateKeyPath    string `json:"privateKeyPath,omitempty"`
	UseSystemCACerts  *bool  `json:"useSystemCACerts,omitempty"`
}

type HotspotRequest struct {
	SSID     string `json:"ssid"`
	Password string `json:"password,omitempty"`
	Device   string `json:"device,omitempty"`
	Band     string `json:"band,omitempty"`
}

type WiredConnection struct {
	Path     dbus.ObjectPath `json:"path"`
	ID       string          `json:"id"`
	UUID     string          `json:"uuid"`
	Type     string          `json:"type"`
	IsActive bool            `json:"isActive"`
}

type PriorityUpdate struct {
	Preference ConnectionPreference `json:"preference"`
}

type Manager struct {
	backend               Backend
	state                 *NetworkState
	stateMutex            sync.RWMutex
	subscribers           syncmap.Map[string, chan NetworkState]
	stopChan              chan struct{}
	dirty                 chan struct{}
	priorityMutex         sync.Mutex
	notifierWg            sync.WaitGroup
	lastNotifiedState     *NetworkState
	credentialSubscribers syncmap.Map[string, chan CredentialPrompt]
}

type EventType string

const (
	EventStateChanged    EventType = "state_changed"
	EventNetworksUpdated EventType = "networks_updated"
	EventConnecting      EventType = "connecting"
	EventConnected       EventType = "connected"
	EventDisconnected    EventType = "disconnected"
	EventError           EventType = "error"
)

type NetworkEvent struct {
	Type EventType    `json:"type"`
	Data NetworkState `json:"data"`
}

type PromptRequest struct {
	Name           string      `json:"name"`
	SSID           string      `json:"ssid"`
	ConnType       string      `json:"connType"`
	VpnService     string      `json:"vpnService"`
	SettingName    string      `json:"setting"`
	Fields         []string    `json:"fields"`
	FieldsInfo     []FieldInfo `json:"fieldsInfo"`
	Hints          []string    `json:"hints"`
	Reason         string      `json:"reason"`
	ConnectionId   string      `json:"connectionId"`
	ConnectionUuid string      `json:"connectionUuid"`
	ConnectionPath string      `json:"connectionPath"`
}

type PromptReply struct {
	Secrets map[string]string `json:"secrets"`
	Save    bool              `json:"save"`
	Cancel  bool              `json:"cancel"`
}

type FieldInfo struct {
	Name     string `json:"name"`
	Label    string `json:"label"`
	IsSecret bool   `json:"isSecret"`
}

type CredentialPrompt struct {
	Token          string      `json:"token"`
	Name           string      `json:"name"`
	SSID           string      `json:"ssid"`
	ConnType       string      `json:"connType"`
	VpnService     string      `json:"vpnService"`
	Setting        string      `json:"setting"`
	Fields         []string    `json:"fields"`
	FieldsInfo     []FieldInfo `json:"fieldsInfo"`
	Hints          []string    `json:"hints"`
	Reason         string      `json:"reason"`
	ConnectionId   string      `json:"connectionId"`
	ConnectionUuid string      `json:"connectionUuid"`
}

type NetworkInfoResponse struct {
	SSID  string        `json:"ssid"`
	Bands []WiFiNetwork `json:"bands"`
}

type WiredNetworkInfoResponse struct {
	UUID   string        `json:"uuid"`
	IFace  string        `json:"iface"`
	Driver string        `json:"driver"`
	HwAddr string        `json:"hwAddr"`
	Speed  string        `json:"speed"`
	IPv4   WiredIPConfig `json:"IPv4s"`
	IPv6   WiredIPConfig `json:"IPv6s"`
}

type WiredIPConfig struct {
	IPs     []string `json:"ips"`
	Gateway string   `json:"gateway"`
	DNS     string   `json:"dns"`
}

type VPNPlugin struct {
	Name           string   `json:"name"`
	ServiceType    string   `json:"serviceType"`
	Program        string   `json:"program,omitempty"`
	Supports       []string `json:"supports,omitempty"`
	FileExtensions []string `json:"fileExtensions"`
}

type VPNConfig struct {
	UUID        string            `json:"uuid"`
	Name        string            `json:"name"`
	Type        string            `json:"type"`
	ServiceType string            `json:"serviceType,omitempty"`
	Autoconnect bool              `json:"autoconnect"`
	Data        map[string]string `json:"data,omitempty"`
}

type VPNImportResult struct {
	Success     bool   `json:"success"`
	UUID        string `json:"uuid,omitempty"`
	Name        string `json:"name,omitempty"`
	ServiceType string `json:"serviceType,omitempty"`
	Error       string `json:"error,omitempty"`
}
