package firewall

import (
	"context"
	"errors"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/fsnotify/fsnotify"
)

const (
	ufwConfigDir   = "/etc/ufw"
	ufwDefaultFile = "/etc/default/ufw"
	helperIdle     = 5 * time.Minute
	helperMaxLife  = 30 * time.Minute
)

var (
	simpleUFWRule = regexp.MustCompile(`^(allow|deny|reject) ([0-9]+(?::[0-9]+)?)(?:/(tcp|udp))?$`)
	appUFWRule    = regexp.MustCompile(`^(allow|deny|reject) ('[^']+'|[A-Za-z][A-Za-z0-9_.+-]*)$`)
)

type ufwHelper interface {
	Call(method string, params map[string]any, out any) error
	Close()
}

type ufwRawState struct {
	Added    string `json:"added"`
	Apps     string `json:"apps"`
	Defaults string `json:"defaults"`
}

type ufwBackend struct {
	configDir  string
	startHelp  func(context.Context) (ufwHelper, error)
	hasIface   func(string) bool
	mu         sync.Mutex
	helper     ufwHelper
	idleTimer  *time.Timer
	expiresAt  time.Time
	closed     bool
	cancelAuth context.CancelFunc
	notify     func()
	watcher    *fsnotify.Watcher
	watcherEnd sync.WaitGroup
}

func newUFWBackend() *ufwBackend {
	return &ufwBackend{
		configDir: ufwConfigDir,
		startHelp: startProcessHelper,
		hasIface: func(name string) bool {
			_, err := net.InterfaceByName(name)
			return err == nil
		},
		notify: func() {},
	}
}

func (b *ufwBackend) Name() string { return BackendUFW }

// ENABLED=yes only records intent: without ufw.service no rules load after a reboot.
// Only root can see the live state, so the config has to do while locked.
func (b *ufwBackend) Running() bool {
	var status string
	if err := b.call("status", nil, &status); err == nil {
		return parseUFWStatus(status)
	}
	data, err := os.ReadFile(filepath.Join(b.configDir, "ufw.conf"))
	if err != nil {
		return false
	}
	return parseUFWEnabled(string(data))
}

func parseUFWStatus(status string) bool {
	return strings.HasPrefix(strings.TrimSpace(status), "Status: active")
}

func parseUFWEnabled(conf string) bool {
	for line := range strings.Lines(conf) {
		key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
		if ok && key == "ENABLED" {
			return strings.EqualFold(strings.Trim(value, `"' `), "yes")
		}
	}
	return false
}

func (b *ufwBackend) Snapshot() (State, error) {
	state := State{Backend: BackendUFW, Active: b.Running(), Zones: []Zone{}, Rules: []Rule{}, Warnings: []string{}}
	if state.Active && b.hasIface("docker0") {
		state.Warnings = append(state.Warnings, WarningDockerBypass)
	}

	raw, err := b.readRaw()
	if errors.Is(err, errHelperGone) {
		log.Warnf("[Firewall] ufw helper failed: %v", err)
	}
	if errors.Is(err, errHelperGone) || errors.Is(err, errHelperLocked) {
		state.Locked = true
		return state, nil
	}
	if err != nil {
		return state, err
	}
	state.Rules = parseUFWAdded(raw.Added)
	state.Defaults = parseUFWDefaults(raw.Defaults)
	return state, nil
}

var errHelperLocked = errors.New("unlock the firewall first")

func (b *ufwBackend) readRaw() (ufwRawState, error) {
	var raw ufwRawState
	err := b.call("state", nil, &raw)
	return raw, err
}

func (b *ufwBackend) call(method string, params map[string]any, out any) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.helper == nil {
		return errHelperLocked
	}
	if method != "state" && method != "status" && b.idleTimer != nil {
		b.idleTimer.Reset(min(helperIdle, time.Until(b.expiresAt)))
	}
	err := b.helper.Call(method, params, out)
	if errors.Is(err, errHelperGone) {
		b.dropHelperLocked()
	}
	return err
}

func (b *ufwBackend) dropHelperLocked() {
	if b.idleTimer != nil {
		b.idleTimer.Stop()
		b.idleTimer = nil
	}
	if b.helper != nil {
		b.helper.Close()
		b.helper = nil
	}
}

func (b *ufwBackend) Unlock() error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	b.mu.Lock()
	if b.closed {
		b.mu.Unlock()
		return ErrAuthDismissed
	}
	if b.helper != nil {
		b.mu.Unlock()
		return nil
	}
	b.cancelAuth = cancel
	b.mu.Unlock()

	// Outside the lock: this waits on the password prompt.
	helper, err := b.startHelp(ctx)
	if err != nil {
		return err
	}

	b.mu.Lock()
	defer b.mu.Unlock()
	if b.closed {
		helper.Close()
		return ErrAuthDismissed
	}
	if b.helper != nil {
		helper.Close()
		return nil
	}
	b.helper = helper
	b.expiresAt = time.Now().Add(helperMaxLife)
	b.idleTimer = time.AfterFunc(helperIdle, func() {
		b.mu.Lock()
		b.dropHelperLocked()
		b.mu.Unlock()
		b.notify()
	})
	return nil
}

func (b *ufwBackend) AddRule(_ string, spec RuleSpec) error {
	return b.call("rule.add", map[string]any{
		"kind": spec.Kind, "action": spec.Action, "target": spec.Target, "proto": spec.Proto, "source": spec.Source,
	}, nil)
}

func (b *ufwBackend) RemoveRule(_, id string) error {
	return b.call("rule.delete", map[string]any{"spec": id}, nil)
}

func (b *ufwBackend) SetDefaults(change DefaultsChange) error {
	for direction, policy := range map[string]string{"incoming": change.Incoming, "outgoing": change.Outgoing} {
		if policy == "" {
			continue
		}
		if err := b.call("default.set", map[string]any{"direction": direction, "policy": policy}, nil); err != nil {
			return err
		}
	}
	return nil
}

func (b *ufwBackend) SetInterfaceZone(_, _ string) error {
	return errors.New("ufw has no zones")
}

func (b *ufwBackend) ListServices() ([]Service, error) {
	raw, err := b.readRaw()
	if err != nil {
		return nil, err
	}
	var services []Service
	for _, app := range parseUFWApps(raw.Apps) {
		services = append(services, Service{Name: app})
	}
	return services, nil
}

func (b *ufwBackend) Start(notify func()) error {
	b.mu.Lock()
	b.notify = notify
	b.mu.Unlock()

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	if err := watcher.Add(b.configDir); err != nil {
		_ = watcher.Close()
		return err
	}
	b.watcher = watcher
	b.watcherEnd.Go(func() {
		for {
			select {
			case event, ok := <-watcher.Events:
				if !ok {
					return
				}
				switch filepath.Base(event.Name) {
				case "ufw.conf", "user.rules", "user6.rules":
					notify()
				}
			case _, ok := <-watcher.Errors:
				if !ok {
					return
				}
			}
		}
	})
	return nil
}

func (b *ufwBackend) Close() {
	b.mu.Lock()
	b.closed = true
	if b.cancelAuth != nil {
		b.cancelAuth()
	}
	b.dropHelperLocked()
	b.mu.Unlock()
	if b.watcher == nil {
		return
	}
	_ = b.watcher.Close()
	b.watcherEnd.Wait()
	b.watcher = nil
}

func parseUFWAdded(output string) []Rule {
	rules := []Rule{}
	for line := range strings.Lines(output) {
		spec, ok := strings.CutPrefix(strings.TrimSpace(line), "ufw ")
		if !ok {
			continue
		}
		rules = append(rules, parseUFWRule(spec))
	}
	return rules
}

func parseUFWRule(spec string) Rule {
	if m := simpleUFWRule.FindStringSubmatch(spec); m != nil {
		return Rule{ID: spec, Kind: KindPort, Action: m[1], Target: strings.ReplaceAll(m[2], ":", "-"), Proto: m[3]}
	}
	if m := appUFWRule.FindStringSubmatch(spec); m != nil {
		return Rule{ID: spec, Kind: KindService, Action: m[1], Target: strings.Trim(m[2], "'")}
	}
	return Rule{ID: spec, Kind: KindRaw, Raw: spec}
}

func parseUFWApps(output string) []string {
	apps := []string{}
	for line := range strings.Lines(output) {
		if !strings.HasPrefix(line, "  ") {
			continue
		}
		if app := strings.TrimSpace(line); app != "" {
			apps = append(apps, app)
		}
	}
	return apps
}

// ufw only prints defaults while active, and the file also holds them while inactive.
func parseUFWDefaults(file string) *Defaults {
	defaults := Defaults{}
	for line := range strings.Lines(file) {
		key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok {
			continue
		}
		switch key {
		case "DEFAULT_INPUT_POLICY":
			defaults.Incoming = ufwPolicyName(value)
		case "DEFAULT_OUTPUT_POLICY":
			defaults.Outgoing = ufwPolicyName(value)
		}
	}
	return &defaults
}

func ufwPolicyName(value string) string {
	switch strings.Trim(value, `"' `) {
	case "ACCEPT":
		return ActionAllow
	case "REJECT":
		return ActionReject
	case "DROP":
		return ActionDeny
	}
	return ""
}
