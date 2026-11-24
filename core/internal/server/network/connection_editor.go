package network

type ConnectionProfile struct {
	UUID          string `json:"uuid"`
	ID            string `json:"id"`
	Type          string `json:"type"`
	Device        string `json:"device,omitempty"`
	InterfaceName string `json:"interfaceName,omitempty"`
	Active        bool   `json:"active"`
	ActiveState   string `json:"activeState,omitempty"`
	Autoconnect   bool   `json:"autoconnect"`
	Timestamp     uint64 `json:"timestamp"`
	// Unsaved is true for profiles that live in memory only.
	Unsaved bool `json:"unsaved"`
	// CanModify is false only when polkit denies modification outright.
	CanModify bool `json:"canModify"`
	// SSID is set for Wi-Fi profiles whose SSID is valid UTF-8.
	SSID string `json:"ssid,omitempty"`
	// Controller and PortType are set for every port profile (connection.controller, else master).
	Controller string `json:"controller,omitempty"`
	PortType   string `json:"portType,omitempty"`
}

// ConnectionEditorBackend is implemented by backends that can edit arbitrary
// saved profiles. Detect it with a type assertion.
type ConnectionEditorBackend interface {
	ListConnectionProfiles() ([]ConnectionProfile, error)
	GetConnectionSettings(uuid string, withSecrets bool) (map[string]map[string]any, error)
	UpdateConnectionSettings(uuid string, patch SettingsPatch, persist bool) error
	AddConnectionProfile(settings SettingsPatch, persist bool) (string, error)
	DeleteConnectionProfile(uuid string) error
	DuplicateConnectionProfile(uuid, name string) (string, error)
	// ActivateConnectionProfile lets NM pick the device when device is empty.
	ActivateConnectionProfile(uuid, device string) error
	// DeactivateConnectionProfile is a no-op for a profile that isn't active.
	DeactivateConnectionProfile(uuid string) error
	// FirewallZones returns an empty list when firewalld isn't running.
	FirewallZones() ([]string, error)
	// ExportConnectionProfile writes a WireGuard or VPN profile to an absolute path with mode 0600.
	ExportConnectionProfile(uuid, path string) error
	// CheckConnectivity forces a NetworkManager connectivity probe and returns the resulting state name.
	CheckConnectivity() (string, error)
	SetConnectivityCheckEnabled(enabled bool) error
}
