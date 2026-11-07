package firewall

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	firewalldName       = "org.fedoraproject.FirewallD1"
	firewalldPath       = "/org/fedoraproject/FirewallD1"
	firewalldConfigPath = "/org/fedoraproject/FirewallD1/config"
	firewalldZoneIface  = firewalldName + ".zone"
	firewalldConfig     = firewalldName + ".config"
	firewalldConfigZone = firewalldName + ".config.zone"

	actionConfig     = firewalldName + ".config"
	actionConfigInfo = firewalldName + ".config.info"

	polkitName      = "org.freedesktop.PolicyKit1"
	polkitPath      = "/org/freedesktop/PolicyKit1/Authority"
	polkitCheckAuth = "org.freedesktop.PolicyKit1.Authority.CheckAuthorization"

	dbusDaemonIface = "org.freedesktop.DBus"

	callTimeout   = 15 * time.Second
	promptTimeout = 5 * time.Minute
)

// Docker, NetworkManager and libvirt rewrite these zones, so edits would not last.
func isManagedZone(name string) bool {
	return name == "docker" || name == "nm-shared" || strings.HasPrefix(name, "libvirt")
}

type firewalldBus interface {
	Running() bool
	Authorized(action string, interactive bool) (bool, error)
	Call(path, method string, args []any, ret ...any) error
}

type systemBus struct {
	conn *dbus.Conn
}

func (b *systemBus) Running() bool {
	var owned bool
	obj := b.conn.Object(dbusDaemonIface, "/org/freedesktop/DBus")
	if err := obj.Call(dbusDaemonIface+".NameHasOwner", 0, firewalldName).Store(&owned); err != nil {
		return false
	}
	return owned
}

type polkitSubject struct {
	Kind    string
	Details map[string]dbus.Variant
}

// Authorized asks polkit directly. firewalld's own check always allows interaction and
// blocks its main loop while a prompt is open, so nothing gated may reach firewalld first.
func (b *systemBus) Authorized(action string, interactive bool) (bool, error) {
	names := b.conn.Names()
	if len(names) == 0 {
		return false, errors.New("no bus name")
	}
	subject := polkitSubject{
		Kind:    "system-bus-name",
		Details: map[string]dbus.Variant{"name": dbus.MakeVariant(names[0])},
	}
	flags, timeout := uint32(0), callTimeout
	if interactive {
		flags, timeout = 1, promptTimeout
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	var result struct {
		Authorized bool
		Challenge  bool
		Details    map[string]string
	}
	call := b.conn.Object(polkitName, polkitPath).CallWithContext(ctx, polkitCheckAuth, 0,
		subject, action, map[string]string{}, flags, "")
	if call.Err != nil {
		return false, call.Err
	}
	if err := call.Store(&result); err != nil {
		return false, err
	}
	if result.Authorized {
		return true, nil
	}
	if !interactive {
		return false, nil
	}
	if result.Details["polkit.dismissed"] != "" {
		return false, ErrAuthDismissed
	}
	return false, errors.New("authorization failed, is a polkit agent running?")
}

func (b *systemBus) Call(path, method string, args []any, ret ...any) error {
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	call := b.conn.Object(firewalldName, dbus.ObjectPath(path)).CallWithContext(ctx, method, 0, args...)
	if call.Err != nil {
		return call.Err
	}
	if len(ret) == 0 {
		return nil
	}
	return call.Store(ret...)
}

type firewalldBackend struct {
	bus  firewalldBus
	conn *dbus.Conn

	signals chan *dbus.Signal
	stop    chan struct{}
	wg      sync.WaitGroup
}

func newFirewalldBackend() (*firewalldBackend, error) {
	conn, err := dbus.SystemBus()
	if err != nil {
		return nil, fmt.Errorf("system bus connection failed: %w", err)
	}
	return &firewalldBackend{bus: &systemBus{conn: conn}, conn: conn}, nil
}

func (b *firewalldBackend) Name() string  { return BackendFirewalld }
func (b *firewalldBackend) Running() bool { return b.bus.Running() }

func (b *firewalldBackend) Snapshot() (State, error) {
	state := State{Backend: BackendFirewalld, Zones: []Zone{}, Rules: []Rule{}, Warnings: []string{}}
	if !b.Running() {
		return state, nil
	}
	state.Active = true

	var names []string
	if err := b.bus.Call(firewalldPath, firewalldZoneIface+".getZones", nil, &names); err != nil {
		return state, err
	}
	var active map[string]map[string][]string
	if err := b.bus.Call(firewalldPath, firewalldZoneIface+".getActiveZones", nil, &active); err != nil {
		return state, err
	}
	if err := b.bus.Call(firewalldPath, firewalldName+".getDefaultZone", nil, &state.DefaultZone); err != nil {
		return state, err
	}

	authorized, err := b.bus.Authorized(actionConfigInfo, false)
	if err != nil {
		log.Warnf("[Firewall] polkit check failed: %v", err)
	}
	state.Locked = !authorized

	for _, name := range names {
		binding, isActive := active[name]
		zone := Zone{
			Name:       name,
			Active:     isActive,
			ReadOnly:   isManagedZone(name),
			Interfaces: append([]string{}, binding["interfaces"]...),
			Rules:      []Rule{},
		}
		if authorized {
			rules, err := b.readZoneRules(name)
			if err != nil {
				return state, err
			}
			zone.Rules = rules
		}
		state.Zones = append(state.Zones, zone)
	}
	return state, nil
}

type firewalldPort struct {
	Port  string
	Proto string
}

func (b *firewalldBackend) readZoneRules(zone string) ([]Rule, error) {
	var settings map[string]dbus.Variant
	if err := b.bus.Call(firewalldPath, firewalldZoneIface+".getZoneSettings2", []any{zone}, &settings); err != nil {
		return nil, err
	}

	rules := []Rule{}
	var services []string
	if value, ok := settings["services"]; ok {
		if err := value.Store(&services); err != nil {
			return nil, err
		}
	}
	for _, service := range services {
		rules = append(rules, Rule{ID: KindService + ":" + service, Kind: KindService, Action: ActionAllow, Target: service})
	}

	var ports []firewalldPort
	if value, ok := settings["ports"]; ok {
		if err := value.Store(&ports); err != nil {
			return nil, err
		}
	}
	for _, port := range ports {
		rules = append(rules, Rule{ID: KindPort + ":" + port.Port + "/" + port.Proto, Kind: KindPort, Action: ActionAllow, Target: port.Port, Proto: port.Proto})
	}

	var richRules []string
	if value, ok := settings["rules_str"]; ok {
		if err := value.Store(&richRules); err != nil {
			return nil, err
		}
	}
	for _, rich := range richRules {
		rules = append(rules, Rule{ID: KindRaw + ":" + rich, Kind: KindRaw, Raw: rich})
	}
	return rules, nil
}

func (b *firewalldBackend) Unlock() error {
	if !b.Running() {
		return errors.New("firewalld is not running")
	}
	return b.authorize(actionConfigInfo)
}

func (b *firewalldBackend) authorizeWrite() error {
	return b.authorize(actionConfig)
}

func (b *firewalldBackend) authorize(action string) error {
	authorized, err := b.bus.Authorized(action, true)
	if err != nil {
		return err
	}
	if !authorized {
		return errors.New("not authorized")
	}
	return nil
}

type firewalldItem struct {
	kind  string
	value string
	proto string
}

func specItems(spec RuleSpec) []firewalldItem {
	items := []firewalldItem{}
	for _, proto := range spec.protocols() {
		switch {
		case spec.needsRichRule():
			items = append(items, firewalldItem{kind: KindRaw, value: spec.richRule(proto)})
		case spec.Kind == KindService:
			items = append(items, firewalldItem{kind: KindService, value: spec.Target})
		default:
			items = append(items, firewalldItem{kind: KindPort, value: spec.Target, proto: proto})
		}
	}
	return items
}

func itemFromID(id string) (firewalldItem, error) {
	kind, value, ok := strings.Cut(id, ":")
	if !ok || value == "" {
		return firewalldItem{}, fmt.Errorf("invalid rule id: %q", id)
	}
	switch kind {
	case KindService, KindRaw:
		return firewalldItem{kind: kind, value: value}, nil
	case KindPort:
		port, proto, ok := strings.Cut(value, "/")
		if !ok {
			return firewalldItem{}, fmt.Errorf("invalid rule id: %q", id)
		}
		return firewalldItem{kind: kind, value: port, proto: proto}, nil
	}
	return firewalldItem{}, fmt.Errorf("invalid rule id: %q", id)
}

func (i firewalldItem) method(verb string) string {
	switch i.kind {
	case KindService:
		return verb + "Service"
	case KindPort:
		return verb + "Port"
	}
	return verb + "RichRule"
}

func (i firewalldItem) args() []any {
	if i.kind == KindPort {
		return []any{i.value, i.proto}
	}
	return []any{i.value}
}

// Permanent alone would need a reload, which drops runtime state owned by other tools.
func (b *firewalldBackend) applyItem(zone string, item firewalldItem, add bool) error {
	verb, benign := "remove", "NOT_ENABLED"
	if add {
		verb, benign = "add", "ALREADY_ENABLED"
	}

	configPath, err := b.configZonePath(zone)
	if err != nil {
		return err
	}
	method := item.method(verb)
	err = b.bus.Call(configPath, firewalldConfigZone+"."+method, item.args())
	if err != nil && !strings.Contains(err.Error(), benign) {
		return err
	}

	runtimeArgs := append([]any{zone}, item.args()...)
	if add {
		runtimeArgs = append(runtimeArgs, int32(0))
	}
	err = b.bus.Call(firewalldPath, firewalldZoneIface+"."+method, runtimeArgs)
	if err != nil && !strings.Contains(err.Error(), benign) {
		return fmt.Errorf("saved, but not applied until firewalld reloads: %w", err)
	}
	return nil
}

func (b *firewalldBackend) configZonePath(zone string) (string, error) {
	var path dbus.ObjectPath
	if err := b.bus.Call(firewalldConfigPath, firewalldConfig+".getZoneByName", []any{zone}, &path); err != nil {
		return "", err
	}
	return string(path), nil
}

// An interface can sit in only one permanent zone, so it has to leave the old one first.
func (b *firewalldBackend) SetInterfaceZone(iface, zone string) error {
	if isManagedZone(zone) {
		return fmt.Errorf("zone %s is managed by another program", zone)
	}
	if err := b.authorizeWrite(); err != nil {
		return err
	}

	var previous string
	if err := b.bus.Call(firewalldConfigPath, firewalldConfig+".getZoneOfInterface", []any{iface}, &previous); err != nil {
		return err
	}
	if previous != zone {
		if previous != "" {
			if err := b.changePermanentInterface(previous, iface, "remove", "NOT_ENABLED"); err != nil {
				return err
			}
		}
		if err := b.changePermanentInterface(zone, iface, "add", "ALREADY_ENABLED"); err != nil {
			return err
		}
	}

	err := b.bus.Call(firewalldPath, firewalldZoneIface+".changeZoneOfInterface", []any{zone, iface})
	if err != nil {
		return fmt.Errorf("saved, but not applied until firewalld reloads: %w", err)
	}
	return nil
}

func (b *firewalldBackend) changePermanentInterface(zone, iface, verb, benign string) error {
	path, err := b.configZonePath(zone)
	if err != nil {
		return err
	}
	err = b.bus.Call(path, firewalldConfigZone+"."+verb+"Interface", []any{iface})
	if err != nil && !strings.Contains(err.Error(), benign) {
		return err
	}
	return nil
}

func (b *firewalldBackend) AddRule(zone string, spec RuleSpec) error {
	if isManagedZone(zone) {
		return fmt.Errorf("zone %s is managed by another program", zone)
	}
	if err := b.authorizeWrite(); err != nil {
		return err
	}
	for _, item := range specItems(spec) {
		if err := b.applyItem(zone, item, true); err != nil {
			return err
		}
	}
	return nil
}

func (b *firewalldBackend) RemoveRule(zone, id string) error {
	if isManagedZone(zone) {
		return fmt.Errorf("zone %s is managed by another program", zone)
	}
	item, err := itemFromID(id)
	if err != nil {
		return err
	}
	if err := b.authorizeWrite(); err != nil {
		return err
	}
	return b.applyItem(zone, item, false)
}

func (b *firewalldBackend) SetDefaults(change DefaultsChange) error {
	if change.Zone == "" {
		return errors.New("a zone is required")
	}
	if err := b.authorizeWrite(); err != nil {
		return err
	}
	return b.bus.Call(firewalldPath, firewalldName+".setDefaultZone", []any{change.Zone})
}

func (b *firewalldBackend) ListServices() ([]Service, error) {
	var names []string
	if err := b.bus.Call(firewalldPath, firewalldName+".listServices", nil, &names); err != nil {
		return nil, err
	}
	slices.Sort(names)

	services := make([]Service, 0, len(names))
	for _, name := range names {
		services = append(services, Service{Name: name, Ports: b.servicePorts(name)})
	}
	return services, nil
}

func (b *firewalldBackend) servicePorts(name string) []string {
	var settings map[string]dbus.Variant
	if err := b.bus.Call(firewalldPath, firewalldName+".getServiceSettings2", []any{name}, &settings); err != nil {
		return nil
	}
	var ports []firewalldPort
	if value, ok := settings["ports"]; ok {
		if err := value.Store(&ports); err != nil {
			return nil
		}
	}
	out := make([]string, 0, len(ports))
	for _, port := range ports {
		out = append(out, port.Port+"/"+port.Proto)
	}
	return out
}

var firewalldZoneSignals = []string{
	"ServiceAdded", "ServiceRemoved", "PortAdded", "PortRemoved", "RichRuleAdded", "RichRuleRemoved",
	"InterfaceAdded", "InterfaceRemoved", "ZoneOfInterfaceChanged", "ZoneUpdated",
}

func firewalldMatchRules() [][]dbus.MatchOption {
	rules := [][]dbus.MatchOption{
		{dbus.WithMatchSender(firewalldName), dbus.WithMatchInterface(firewalldName), dbus.WithMatchMember("DefaultZoneChanged")},
		{dbus.WithMatchSender(firewalldName), dbus.WithMatchInterface(firewalldName), dbus.WithMatchMember("Reloaded")},
		{dbus.WithMatchSender(dbusDaemonIface), dbus.WithMatchInterface(dbusDaemonIface), dbus.WithMatchMember("NameOwnerChanged"), dbus.WithMatchArg(0, firewalldName)},
	}
	for _, member := range firewalldZoneSignals {
		rules = append(rules, []dbus.MatchOption{dbus.WithMatchSender(firewalldName), dbus.WithMatchInterface(firewalldZoneIface), dbus.WithMatchMember(member)})
	}
	return rules
}

// The system bus is shared process-wide, so other managers' signals land on this channel too.
func isFirewalldSignal(sig *dbus.Signal) bool {
	if sig == nil {
		return false
	}
	if sig.Name == dbusDaemonIface+".NameOwnerChanged" {
		return len(sig.Body) > 0 && sig.Body[0] == firewalldName
	}
	return strings.HasPrefix(sig.Name, firewalldName+".")
}

func (b *firewalldBackend) Start(notify func()) error {
	for _, rule := range firewalldMatchRules() {
		if err := b.conn.AddMatchSignal(rule...); err != nil {
			return err
		}
	}
	b.signals = make(chan *dbus.Signal, 64)
	b.stop = make(chan struct{})
	b.conn.Signal(b.signals)

	b.wg.Go(func() {
		for {
			select {
			case <-b.stop:
				return
			case sig, ok := <-b.signals:
				if !ok {
					return
				}
				if isFirewalldSignal(sig) {
					notify()
				}
			}
		}
	})
	return nil
}

func (b *firewalldBackend) Close() {
	if b.stop == nil {
		return
	}
	close(b.stop)
	b.conn.RemoveSignal(b.signals)
	b.wg.Wait()
	for _, rule := range firewalldMatchRules() {
		_ = b.conn.RemoveMatchSignal(rule...)
	}
	b.stop = nil
}
