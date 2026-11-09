package firewall

import (
	"errors"
	"path/filepath"
	"slices"

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
	Name   string `json:"name,omitempty"`
	Raw    string `json:"raw,omitempty"`
}

type Zone struct {
	Name       string   `json:"name"`
	Active     bool     `json:"active"`
	ReadOnly   bool     `json:"readOnly"`
	Builtin    bool     `json:"builtin"`
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
	AddZone(name string) error
	RenameZone(name, newName string) error
	RemoveZone(name string) error
	ListServices() ([]Service, error)
	Start(notify func()) error
	Close()
}

// Debian-style user PATHs leave out sbin, where both firewalls are installed.
var sbinDirs = []string{"/usr/sbin", "/sbin"}

func commandInstalled(name string) bool {
	if utils.CommandExists(name) {
		return true
	}
	return slices.ContainsFunc(sbinDirs, func(dir string) bool {
		return utils.CommandExists(filepath.Join(dir, name))
	})
}

func Installed() []string {
	installed := []string{}
	if commandInstalled("firewalld") {
		installed = append(installed, BackendFirewalld)
	}
	if commandInstalled("ufw") {
		installed = append(installed, BackendUFW)
	}
	return installed
}
