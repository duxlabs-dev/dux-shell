package network

type Backend interface {
	Initialize() error
	Close()

	GetWiFiEnabled() (bool, error)
	SetWiFiEnabled(enabled bool) error

	GetCellularEnabled() (bool, error)
	SetCellularEnabled(enabled bool) error

	ScanWiFi() error
	ScanWiFiDevice(device string) error
	GetWiFiNetworkDetails(ssid string) (*NetworkInfoResponse, error)
	GetWiFiQRCodeContent(ssid string) (string, error)
	GetWiFiDevices() []WiFiDevice

	ConnectWiFi(req ConnectionRequest) error
	DisconnectWiFi() error
	DisconnectWiFiDevice(device string) error
	ForgetWiFiNetwork(ssid string) error
	SetWiFiAutoconnect(ssid string, autoconnect bool) error

	GetEthernetDevices() []EthernetDevice
	GetWiredConnections() ([]WiredConnection, error)
	GetWiredNetworkDetails(uuid string) (*WiredNetworkInfoResponse, error)
	ConnectEthernet() error
	ConnectEthernetDevice(device string) error
	DisconnectEthernet() error
	DisconnectEthernetDevice(device string) error
	// ActivateWiredConnection lets NM pick the device when device is "".
	ActivateWiredConnection(uuid, device string) error

	GetCellularDevices() []CellularDevice
	GetCellularConnections() ([]WiredConnection, error)
	ConnectCellular() error
	DisconnectCellular() error
	DisconnectCellularDevice(device string) error
	ActivateCellularConnection(uuid string) error

	ListVPNProfiles() ([]VPNProfile, error)
	ListActiveVPN() ([]VPNActive, error)
	ConnectVPN(uuidOrName string, singleActive bool) error
	DisconnectVPN(uuidOrName string) error
	DisconnectAllVPN() error
	ClearVPNCredentials(uuidOrName string) error
	ListVPNPlugins() ([]VPNPlugin, error)
	ImportVPN(filePath string, name string) (*VPNImportResult, error)
	GetVPNConfig(uuidOrName string) (*VPNConfig, error)
	UpdateVPNConfig(uuid string, updates map[string]any) error
	SetVPNCredentials(uuid string, username string, password string, save bool) error
	DeleteVPN(uuidOrName string) error

	GetCurrentState() (*BackendState, error)

	StartMonitoring(onStateChange func()) error
	StopMonitoring()

	GetPromptBroker() PromptBroker
	SetPromptBroker(broker PromptBroker) error
	SubmitCredentials(token string, secrets map[string]string, save bool) error
	CancelCredentials(token string) error
}

type HotspotBackend interface {
	ConfigureHotspot(req HotspotRequest) error
	StartHotspot() error
	StopHotspot() error
	GetHotspotSecrets() (string, error)
}

type BackendState struct {
	Backend                    string
	ConnectionProfilesRevision uint64
	NetworkStatus              NetworkStatus
	EthernetIP                 string
	EthernetDevice             string
	EthernetConnected          bool
	EthernetConnectionUuid     string
	EthernetDevices            []EthernetDevice
	CellularIP                 string
	CellularDevice             string
	CellularConnected          bool
	CellularEnabled            bool
	CellularHardwareEnabled    bool
	CellularConnectionUuid     string
	CellularDevices            []CellularDevice
	CellularConnections        []WiredConnection
	WiFiIP                     string
	WiFiDevice                 string
	WiFiConnected              bool
	WiFiEnabled                bool
	WiFiSSID                   string
	WiFiBSSID                  string
	WiFiSignal                 uint8
	WiFiNetworks               []WiFiNetwork
	SavedWiFiNetworks          []WiFiNetwork
	WiFiDevices                []WiFiDevice
	HotspotAvailable           bool
	HotspotConfigured          bool
	HotspotEnabled             bool
	HotspotActivating          bool
	HotspotSecured             bool
	HotspotSSID                string
	HotspotDevice              string
	HotspotBand                string
	HotspotLastError           string
	HotspotChannel             uint32
	HotspotAddress             string
	HotspotUUID                string
	HotspotSecurity            string
	HotspotHidden              bool
	Connectivity               string
	ConnectivityCheckEnabled   bool
	ConnectivityCheckAvailable bool
	ConnectivityCheckURI       string
	WiredConnections           []WiredConnection
	VPNProfiles                []VPNProfile
	VPNActive                  []VPNActive
	IsConnecting               bool
	ConnectingSSID             string
	ConnectingDevice           string
	ConnectingPreExisting      bool
	IsConnectingVPN            bool
	ConnectingVPNUUID          string
	LastError                  string
	VPNError                   string
	VPNErrorUuid               string
}
