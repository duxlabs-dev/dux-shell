package firewall

import (
	"errors"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const (
	BackendFirewalld = "firewalld"
	BackendUFW       = "ufw"
	BackendNone      = "none"

	WarningDockerBypass = "dockerBypass"
)

var ErrAuthDismissed = errors.New("authorization dismissed")

type Rule struct {
	ID     string `json:"id"`
	Kind   string `json:"kind"`
	Action string `json:"action,omitempty"`
	Target string `json:"target,omitempty"`
	Proto  string `json:"proto,omitempty"`
	Source string `json:"source,omitempty"`
	Raw    string `json:"raw,omitempty"`
}

type Zone struct {
	Name       string   `json:"name"`
	Active     bool     `json:"active"`
	ReadOnly   bool     `json:"readOnly"`
	Interfaces []string `json:"interfaces"`
	Rules      []Rule   `json:"rules"`
}

type Defaults struct {
	Incoming string `json:"incoming"`
	Outgoing string `json:"outgoing"`
}

type State struct {
	Backend     string    `json:"backend"`
	Installed   []string  `json:"installed"`
	Active      bool      `json:"active"`
	Conflict    bool      `json:"conflict"`
	Locked      bool      `json:"locked"`
	DefaultZone string    `json:"defaultZone,omitempty"`
	Defaults    *Defaults `json:"defaults,omitempty"`
	Zones       []Zone    `json:"zones"`
	Rules       []Rule    `json:"rules"`
	Warnings    []string  `json:"warnings"`
	Error       string    `json:"error,omitempty"`
}

type DefaultsChange struct {
	Zone     string
	Incoming string
	Outgoing string
}

type Service struct {
	Name  string   `json:"name"`
	Ports []string `json:"ports"`
}

type Backend interface {
	Name() string
	Running() bool
	Snapshot() (State, error)
	Unlock() error
	AddRule(zone string, spec RuleSpec) error
	RemoveRule(zone, id string) error
	SetDefaults(change DefaultsChange) error
	SetInterfaceZone(iface, zone string) error
	ListServices() ([]Service, error)
	Start(notify func()) error
	Close()
}

func Installed() []string {
	installed := []string{}
	if utils.CommandExists("firewalld") {
		installed = append(installed, BackendFirewalld)
	}
	if utils.CommandExists("ufw") {
		installed = append(installed, BackendUFW)
	}
	return installed
}
