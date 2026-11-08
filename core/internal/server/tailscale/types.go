package tailscale

// TailscaleState represents the current state of the Tailscale daemon.
type TailscaleState struct {
	Connected              bool           `json:"connected"`
	Version                string         `json:"version"`
	BackendState           string         `json:"backendState"`
	MagicDNSSuffix         string         `json:"magicDnsSuffix"`
	TailnetName            string         `json:"tailnetName"`
	ExitNodeAllowLANAccess bool           `json:"exitNodeAllowLanAccess"`
	Self                   Peer           `json:"self"`
	Peers                  []Peer         `json:"peers"`
	Prefs                  TailscalePrefs `json:"prefs"`
	AuthURL                string         `json:"authUrl,omitempty"`
}

// TailscalePrefs is the subset of tailscaled prefs DMS exposes.
type TailscalePrefs struct {
	AcceptRoutes      bool     `json:"acceptRoutes"`
	AcceptDNS         bool     `json:"acceptDns"`
	ShieldsUp         bool     `json:"shieldsUp"`
	RunSSH            bool     `json:"runSsh"`
	Hostname          string   `json:"hostname"`
	OperatorUser      string   `json:"operatorUser"`
	ControlURL        string   `json:"controlUrl"`
	AdvertiseExitNode bool     `json:"advertiseExitNode"`
	AdvertiseRoutes   []string `json:"advertiseRoutes"` // without the two default routes
}

// PrefsPatch holds the prefs to change; nil fields stay untouched.
type PrefsPatch struct {
	AcceptRoutes      *bool
	AcceptDNS         *bool
	ShieldsUp         *bool
	RunSSH            *bool
	AdvertiseExitNode *bool
	Hostname          *string
	AdvertiseRoutes   *[]string
}

type TailscaleProfile struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Tailnet string `json:"tailnet"`
}

// ProfilesResult lists the accounts. CanOperate is false when tailscaled
// denies LocalAPI writes to this process.
type ProfilesResult struct {
	CanOperate     bool               `json:"canOperate"`
	GrantAvailable bool               `json:"grantAvailable"`
	Current        string             `json:"current"`
	Profiles       []TailscaleProfile `json:"profiles"`
}

type ExitNodeSuggestion struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// Peer represents a single node in the Tailscale network.
type Peer struct {
	ID             string   `json:"id"`
	Hostname       string   `json:"hostname"`
	DNSName        string   `json:"dnsName"`
	TailscaleIP    string   `json:"tailscaleIp"`
	TailscaleIPv6  string   `json:"tailscaleIpv6,omitempty"`
	OS             string   `json:"os"`
	Online         bool     `json:"online"`
	LastSeen       string   `json:"lastSeen,omitempty"`
	ExitNode       bool     `json:"exitNode"`
	ExitNodeOption bool     `json:"exitNodeOption"`
	Tags           []string `json:"tags,omitempty"`
	Owner          string   `json:"owner"`
	Relay          string   `json:"relay,omitempty"`
	Active         bool     `json:"active"`
	RxBytes        int64    `json:"rxBytes"`
	TxBytes        int64    `json:"txBytes"`
}
