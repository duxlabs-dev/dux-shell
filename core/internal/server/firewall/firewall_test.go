package firewall

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"testing/synctest"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRuleSpecValidate(t *testing.T) {
	valid := []RuleSpec{
		{Kind: KindService, Action: ActionAllow, Target: "ssh"},
		{Kind: KindService, Action: ActionDeny, Target: "Apache Full", Source: "10.0.0.0/8"},
		{Kind: KindPort, Action: ActionReject, Target: "22", Proto: ProtoBoth},
		{Kind: KindPort, Action: ActionAllow, Target: "6000-6007", Proto: ProtoTCP, Source: "fd00::1"},
	}
	for _, spec := range valid {
		assert.NoError(t, spec.Validate(), "%+v", spec)
	}

	invalid := []RuleSpec{
		{Kind: KindService, Action: "limit", Target: "ssh"},
		{Kind: "raw", Action: ActionAllow, Target: "ssh"},
		{Kind: KindService, Action: ActionAllow, Target: "-x"},
		{Kind: KindService, Action: ActionAllow, Target: `ssh" accept rule`},
		{Kind: KindService, Action: ActionAllow, Target: "ssh\nallow 22"},
		{Kind: KindPort, Action: ActionAllow, Target: "0", Proto: ProtoTCP},
		{Kind: KindPort, Action: ActionAllow, Target: "65536", Proto: ProtoTCP},
		{Kind: KindPort, Action: ActionAllow, Target: "+22", Proto: ProtoTCP},
		{Kind: KindPort, Action: ActionAllow, Target: "22-10", Proto: ProtoTCP},
		{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: "icmp"},
		{Kind: KindPort, Action: ActionAllow, Target: "22-30", Proto: ProtoBoth},
		{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Source: `1.2.3.4" drop`},
		{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Source: `fe80::1%x" foo="`},
		{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Source: "fe80::1%eth0"},
		{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Source: "fe80::1%eth0/64"},
	}
	for _, spec := range invalid {
		assert.Error(t, spec.Validate(), "%+v", spec)
	}
}

func TestSpecItems(t *testing.T) {
	tests := []struct {
		spec RuleSpec
		want []firewalldItem
	}{
		{RuleSpec{Kind: KindService, Action: ActionAllow, Target: "ssh"},
			[]firewalldItem{{kind: KindService, value: "ssh"}}},
		{RuleSpec{Kind: KindPort, Action: ActionAllow, Target: "53", Proto: ProtoBoth},
			[]firewalldItem{{kind: KindPort, value: "53", proto: "tcp"}, {kind: KindPort, value: "53", proto: "udp"}}},
		{RuleSpec{Kind: KindService, Action: ActionDeny, Target: "ssh"},
			[]firewalldItem{{kind: KindRaw, value: `rule service name="ssh" drop`}}},
		{RuleSpec{Kind: KindPort, Action: ActionAllow, Target: "80", Proto: ProtoTCP, Source: "10.0.0.0/8"},
			[]firewalldItem{{kind: KindRaw, value: `rule family="ipv4" source address="10.0.0.0/8" port port="80" protocol="tcp" accept`}}},
		{RuleSpec{Kind: KindService, Action: ActionReject, Target: "ssh", Source: "fd00::/8"},
			[]firewalldItem{{kind: KindRaw, value: `rule family="ipv6" source address="fd00::/8" service name="ssh" reject`}}},
	}
	for _, tt := range tests {
		assert.Equal(t, tt.want, specItems(tt.spec))
	}
}

func TestUFWArgs(t *testing.T) {
	tests := []struct {
		spec RuleSpec
		want []string
	}{
		{RuleSpec{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP}, []string{"allow", "22/tcp"}},
		{RuleSpec{Kind: KindPort, Action: ActionDeny, Target: "53", Proto: ProtoBoth}, []string{"deny", "53"}},
		{RuleSpec{Kind: KindPort, Action: ActionAllow, Target: "6000-6007", Proto: ProtoUDP}, []string{"allow", "6000:6007/udp"}},
		{RuleSpec{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Source: "10.0.0.1"},
			[]string{"allow", "from", "10.0.0.1", "to", "any", "port", "22", "proto", "tcp"}},
		{RuleSpec{Kind: KindService, Action: ActionAllow, Target: "Apache Full"}, []string{"allow", "Apache Full"}},
		{RuleSpec{Kind: KindService, Action: ActionReject, Target: "OpenSSH", Source: "10.0.0.0/8"},
			[]string{"reject", "from", "10.0.0.0/8", "to", "any", "app", "OpenSSH"}},
	}
	for _, tt := range tests {
		assert.Equal(t, tt.want, tt.spec.ufwArgs())
	}
}

const ufwAddedFixture = `Added user rules (see 'ufw status' for running firewall):
ufw allow 22/tcp
ufw deny 6000:6007/udp
ufw allow 53
ufw allow OpenSSH
ufw reject 'Apache Full'
ufw allow from 10.0.0.0/8 to any port 80 proto tcp
ufw limit 22/tcp
ufw allow out 443/tcp
ufw route allow in on eth0 out on eth1
`

func TestParseUFWAdded(t *testing.T) {
	assert.Equal(t, []Rule{
		{ID: "allow 22/tcp", Kind: KindPort, Action: "allow", Target: "22", Proto: "tcp"},
		{ID: "deny 6000:6007/udp", Kind: KindPort, Action: "deny", Target: "6000-6007", Proto: "udp"},
		{ID: "allow 53", Kind: KindPort, Action: "allow", Target: "53"},
		{ID: "allow OpenSSH", Kind: KindService, Action: "allow", Target: "OpenSSH"},
		{ID: "reject 'Apache Full'", Kind: KindService, Action: "reject", Target: "Apache Full"},
		{ID: "allow from 10.0.0.0/8 to any port 80 proto tcp", Kind: KindRaw, Raw: "allow from 10.0.0.0/8 to any port 80 proto tcp"},
		{ID: "limit 22/tcp", Kind: KindRaw, Raw: "limit 22/tcp"},
		{ID: "allow out 443/tcp", Kind: KindRaw, Raw: "allow out 443/tcp"},
		{ID: "route allow in on eth0 out on eth1", Kind: KindRaw, Raw: "route allow in on eth0 out on eth1"},
	}, parseUFWAdded(ufwAddedFixture))

	assert.Empty(t, parseUFWAdded("Added user rules (see 'ufw status' for running firewall):\n(None)"))
}

func TestParseUFWFiles(t *testing.T) {
	assert.Equal(t, []string{"Apache Full", "OpenSSH"}, parseUFWApps("Available applications:\n  Apache Full\n  OpenSSH\n"))
	assert.Equal(t, &Defaults{Incoming: "deny", Outgoing: "allow"},
		parseUFWDefaults("IPV6=yes\nDEFAULT_INPUT_POLICY=\"DROP\"\nDEFAULT_OUTPUT_POLICY=\"ACCEPT\"\n"))
	assert.True(t, parseUFWEnabled("# comment\nENABLED=yes\nLOGLEVEL=low\n"))
	assert.False(t, parseUFWEnabled("ENABLED=no\n"))
	assert.False(t, parseUFWEnabled("LOGLEVEL=low\n"))
}

func TestUFWDeleteArgs(t *testing.T) {
	tests := []struct {
		spec string
		want []string
	}{
		{"allow 22/tcp", []string{"--force", "delete", "allow", "22/tcp"}},
		{"reject 'Apache Full'", []string{"--force", "delete", "reject", "Apache Full"}},
		{"allow 22 comment 'my rule'", []string{"--force", "delete", "allow", "22", "comment", "my rule"}},
		{"route allow in on eth0", []string{"--force", "route", "delete", "allow", "in", "on", "eth0"}},
	}
	for _, tt := range tests {
		got, err := ufwDeleteArgs(tt.spec)
		require.NoError(t, err)
		assert.Equal(t, tt.want, got)
	}
	_, err := ufwDeleteArgs("allow 'unbalanced")
	assert.Error(t, err)
}

func newTestHelper(calls *[][]string) *Helper {
	return &Helper{
		run: func(args ...string) (string, error) {
			switch fmt.Sprint(args) {
			case "[show added]":
				return ufwAddedFixture, nil
			case "[app list]":
				return "Available applications:\n  Apache Full\n  OpenSSH\n", nil
			}
			*calls = append(*calls, args)
			return "", nil
		},
		defaults: func() (string, error) { return "", nil },
	}
}

func TestHelperRejectsAnythingUnlisted(t *testing.T) {
	var calls [][]string
	helper := newTestHelper(&calls)

	rejected := []struct {
		method string
		params map[string]any
	}{
		{"exec", map[string]any{"cmd": "sh"}},
		{"rule.delete", map[string]any{"spec": "allow 9999/tcp"}},
		{"rule.delete", map[string]any{"spec": "--force reset"}},
		{"rule.add", map[string]any{"kind": "service", "action": "allow", "target": "NotAnApp"}},
		{"rule.add", map[string]any{"kind": "port", "action": "allow", "target": "--dry-run", "proto": "tcp"}},
		{"rule.add", map[string]any{"kind": "port", "action": "reset", "target": "22", "proto": "tcp"}},
		{"default.set", map[string]any{"direction": "routed", "policy": "allow"}},
		{"default.set", map[string]any{"direction": "incoming", "policy": "--force"}},
	}
	for _, tt := range rejected {
		_, err := helper.Call(tt.method, tt.params)
		assert.Error(t, err, "%s %v", tt.method, tt.params)
	}
	assert.Empty(t, calls, "a rejected request must not reach ufw")

	_, err := helper.Call("rule.delete", map[string]any{"spec": "allow 22/tcp"})
	require.NoError(t, err)
	_, err = helper.Call("rule.add", map[string]any{"kind": "service", "action": "allow", "target": "Apache Full"})
	require.NoError(t, err)
	assert.Equal(t, [][]string{{"--force", "delete", "allow", "22/tcp"}, {"allow", "Apache Full"}}, calls)
}

type fakeBus struct {
	running     bool
	authorized  bool
	authErr     error
	interactive []string
	calls       []string
	failOn      map[string]error
}

func (f *fakeBus) Running() bool { return f.running }

func (f *fakeBus) Authorized(action string, interactive bool) (bool, error) {
	if interactive {
		f.interactive = append(f.interactive, action)
		return f.authorized, f.authErr
	}
	return f.authorized, nil
}

func (f *fakeBus) Call(path, method string, args []any, ret ...any) error {
	f.calls = append(f.calls, method)
	if err, ok := f.failOn[method]; ok {
		return err
	}
	if len(ret) == 0 {
		return nil
	}
	switch out := ret[0].(type) {
	case *[]string:
		*out = []string{"home", "docker"}
	case *map[string]map[string][]string:
		*out = map[string]map[string][]string{"home": {"interfaces": {"eno1"}}}
	case *string:
		*out = "home"
	case *dbus.ObjectPath:
		*out = "/org/fedoraproject/FirewallD1/config/zone/1"
	case *map[string]dbus.Variant:
		*out = map[string]dbus.Variant{
			"services":  dbus.MakeVariant([]string{"ssh"}),
			"ports":     dbus.MakeVariantWithSignature([][]any{{"80", "tcp"}}, dbus.ParseSignatureMust("a(ss)")),
			"rules_str": dbus.MakeVariant([]string{`rule service name="ftp" drop`}),
		}
	}
	return nil
}

// The shell runs 24/7: a refresh that reached a gated method would pop a password dialog unprompted.
func TestSnapshotNeverPromptsWhileLocked(t *testing.T) {
	bus := &fakeBus{running: true, authorized: false}
	backend := &firewalldBackend{bus: bus}

	state, err := backend.Snapshot()
	require.NoError(t, err)

	assert.True(t, state.Locked)
	assert.Empty(t, bus.interactive)
	assert.NotContains(t, bus.calls, firewalldZoneIface+".getZoneSettings2")
	assert.Equal(t, "home", state.DefaultZone)
	require.Len(t, state.Zones, 2)
	assert.Equal(t, []string{"eno1"}, state.Zones[0].Interfaces)
	assert.True(t, state.Zones[0].Active)
	assert.True(t, state.Zones[1].ReadOnly)
}

func TestSnapshotReadsRulesWhenAuthorized(t *testing.T) {
	backend := &firewalldBackend{bus: &fakeBus{running: true, authorized: true}}

	state, err := backend.Snapshot()
	require.NoError(t, err)

	assert.False(t, state.Locked)
	assert.Equal(t, []Rule{
		{ID: "service:ssh", Kind: KindService, Action: ActionAllow, Target: "ssh"},
		{ID: "port:80/tcp", Kind: KindPort, Action: ActionAllow, Target: "80", Proto: "tcp"},
		{ID: `raw:rule service name="ftp" drop`, Kind: KindRaw, Raw: `rule service name="ftp" drop`},
	}, state.Zones[0].Rules)
}

func TestFirewalldWrites(t *testing.T) {
	spec := RuleSpec{Kind: KindService, Action: ActionAllow, Target: "ssh"}
	permanent := firewalldConfigZone + ".addService"
	runtime := firewalldZoneIface + ".addService"

	t.Run("writes permanent and runtime after authorizing", func(t *testing.T) {
		bus := &fakeBus{running: true, authorized: true}
		require.NoError(t, (&firewalldBackend{bus: bus}).AddRule("home", spec))
		assert.Equal(t, []string{actionConfig}, bus.interactive)
		assert.Equal(t, []string{firewalldConfig + ".getZoneByName", permanent, runtime}, bus.calls)
	})

	t.Run("dismissed prompt reaches no gated method", func(t *testing.T) {
		bus := &fakeBus{running: true, authErr: ErrAuthDismissed}
		err := (&firewalldBackend{bus: bus}).AddRule("home", spec)
		assert.ErrorIs(t, err, ErrAuthDismissed)
		assert.Empty(t, bus.calls)
	})

	t.Run("already present counts as success", func(t *testing.T) {
		bus := &fakeBus{running: true, authorized: true, failOn: map[string]error{
			permanent: errors.New("ALREADY_ENABLED: ssh"),
			runtime:   errors.New("ALREADY_ENABLED: 'ssh' already in 'home'"),
		}}
		assert.NoError(t, (&firewalldBackend{bus: bus}).AddRule("home", spec))
	})

	t.Run("reports a runtime failure after a permanent success", func(t *testing.T) {
		bus := &fakeBus{running: true, authorized: true, failOn: map[string]error{runtime: errors.New("boom")}}
		err := (&firewalldBackend{bus: bus}).AddRule("home", spec)
		assert.ErrorContains(t, err, "not applied")
	})

	t.Run("refuses managed zones", func(t *testing.T) {
		bus := &fakeBus{running: true, authorized: true}
		assert.Error(t, (&firewalldBackend{bus: bus}).AddRule("docker", spec))
		assert.Error(t, (&firewalldBackend{bus: bus}).RemoveRule("libvirt", "service:ssh"))
		assert.Empty(t, bus.interactive)
	})

	t.Run("removes the rich rule from its id", func(t *testing.T) {
		item, err := itemFromID(`raw:rule service name="ftp:x" drop`)
		require.NoError(t, err)
		assert.Equal(t, firewalldItem{kind: KindRaw, value: `rule service name="ftp:x" drop`}, item)
		_, err = itemFromID("port:80")
		assert.Error(t, err)
	})
}

func TestSetInterfaceZone(t *testing.T) {
	t.Run("leaves the old permanent zone before joining the new one", func(t *testing.T) {
		bus := &fakeBus{running: true, authorized: true}
		require.NoError(t, (&firewalldBackend{bus: bus}).SetInterfaceZone("eno1", "public"))
		assert.Equal(t, []string{
			firewalldConfig + ".getZoneOfInterface",
			firewalldConfig + ".getZoneByName", firewalldConfigZone + ".removeInterface",
			firewalldConfig + ".getZoneByName", firewalldConfigZone + ".addInterface",
			firewalldZoneIface + ".changeZoneOfInterface",
		}, bus.calls)
	})

	t.Run("refuses managed zones before authorizing", func(t *testing.T) {
		bus := &fakeBus{running: true, authorized: true}
		assert.Error(t, (&firewalldBackend{bus: bus}).SetInterfaceZone("eno1", "docker"))
		assert.Empty(t, bus.interactive)
	})
}

type fakeBackend struct {
	Backend
	name    string
	running bool
	moved   []string
}

func (f *fakeBackend) SetInterfaceZone(iface, zone string) error {
	f.moved = append(f.moved, iface+"="+zone)
	return nil
}

func (f *fakeBackend) Name() string  { return f.name }
func (f *fakeBackend) Running() bool { return f.running }
func (f *fakeBackend) Snapshot() (State, error) {
	return State{Backend: f.name, Active: f.running}, nil
}

func TestBackendSelection(t *testing.T) {
	tests := []struct {
		name         string
		fw, ufw      *fakeBackend
		wantBackend  string
		wantConflict bool
	}{
		{"firewalld running wins", &fakeBackend{name: BackendFirewalld, running: true}, &fakeBackend{name: BackendUFW}, BackendFirewalld, false},
		{"stopped firewalld falls to ufw", &fakeBackend{name: BackendFirewalld}, &fakeBackend{name: BackendUFW}, BackendUFW, false},
		{"both running conflict", &fakeBackend{name: BackendFirewalld, running: true}, &fakeBackend{name: BackendUFW, running: true}, BackendFirewalld, true},
		{"only stopped firewalld", &fakeBackend{name: BackendFirewalld}, nil, BackendFirewalld, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var ufw Backend
			if tt.ufw != nil {
				ufw = tt.ufw
			}
			state := newManager(tt.fw, ufw).GetState()
			assert.Equal(t, tt.wantBackend, state.Backend)
			assert.Equal(t, tt.wantConflict, state.Conflict)
		})
	}
}

type idleHelper struct{}

func (idleHelper) Call(string, map[string]any, any) error { return nil }
func (idleHelper) Close()                                 {}

func TestHelperLifetime(t *testing.T) {
	unlocked := func(t *testing.T) *ufwBackend {
		b := &ufwBackend{startHelp: func(context.Context) (ufwHelper, error) { return idleHelper{}, nil }, notify: func() {}}
		require.NoError(t, b.Unlock())
		t.Cleanup(b.Close)
		return b
	}
	addRule := func(b *ufwBackend) error { return b.AddRule("", RuleSpec{}) }
	listServices := func(b *ufwBackend) error {
		_, err := b.ListServices()
		return err
	}
	advance := func(d time.Duration) {
		time.Sleep(d)
		synctest.Wait()
	}

	t.Run("reads do not extend it", func(t *testing.T) {
		synctest.Test(t, func(t *testing.T) {
			b := unlocked(t)
			advance(helperIdle - time.Second)
			require.NoError(t, listServices(b))
			advance(2 * time.Second)
			assert.ErrorIs(t, listServices(b), errHelperLocked)
		})
	})

	t.Run("writes extend it", func(t *testing.T) {
		synctest.Test(t, func(t *testing.T) {
			b := unlocked(t)
			advance(helperIdle - time.Second)
			require.NoError(t, addRule(b))
			advance(2 * time.Second)
			assert.NoError(t, listServices(b))
		})
	})

	t.Run("writes cannot pass the hard cap", func(t *testing.T) {
		synctest.Test(t, func(t *testing.T) {
			b := unlocked(t)
			start := time.Now()
			for time.Since(start) < helperMaxLife-time.Minute {
				advance(time.Minute)
				require.NoError(t, addRule(b))
			}
			advance(time.Minute + time.Second)
			assert.ErrorIs(t, addRule(b), errHelperLocked)
		})
	})
}

func TestHandleSetInterfaceZone(t *testing.T) {
	backend := &fakeBackend{name: BackendFirewalld, running: true}
	manager := newManager(backend, nil)
	call := func(params map[string]any) ipc.Response[json.RawMessage] {
		server, client := net.Pipe()
		defer server.Close()
		defer client.Close()
		go HandleRequest(ipc.NewConnWriter(server), ipc.Request{ID: 1, Method: "firewall.setInterfaceZone", Params: params}, manager)
		var response ipc.Response[json.RawMessage]
		require.NoError(t, json.NewDecoder(client).Decode(&response))
		return response
	}

	assert.Empty(t, call(map[string]any{"interface": "eno1", "zone": "public"}).Error)
	assert.Equal(t, []string{"eno1=public"}, backend.moved)

	assert.NotEmpty(t, call(map[string]any{"zone": "public"}).Error)
	assert.NotEmpty(t, call(map[string]any{"interface": "eno1"}).Error)
	assert.Len(t, backend.moved, 1)
}

type changingBackend struct {
	fakeBackend
	revision atomic.Int64
}

func (b *changingBackend) Snapshot() (State, error) {
	return State{Backend: b.name, DefaultZone: fmt.Sprint(b.revision.Add(1))}, nil
}

func TestUnsubscribeDuringRefreshDoesNotPanic(t *testing.T) {
	manager := newManager(&changingBackend{fakeBackend: fakeBackend{name: BackendFirewalld}}, nil)
	done := make(chan struct{})
	var wg sync.WaitGroup
	wg.Go(func() {
		for {
			select {
			case <-done:
				return
			default:
				manager.refresh()
			}
		}
	})
	for i := range 20000 {
		id := fmt.Sprint(i)
		manager.Subscribe(id)
		manager.Unsubscribe(id)
	}
	close(done)
	wg.Wait()
}

// Polkit keeps a temporary authorization per action, not per user.
type perActionBus struct {
	fakeBus
	granted map[string]bool
}

func (b *perActionBus) Authorized(action string, interactive bool) (bool, error) {
	if interactive {
		b.granted[action] = true
	}
	return b.granted[action], nil
}

func TestFirewalldUnlockRevealsRules(t *testing.T) {
	bus := &perActionBus{fakeBus: fakeBus{running: true}, granted: map[string]bool{}}
	backend := &firewalldBackend{bus: bus}

	require.NoError(t, backend.Unlock())

	state, err := backend.Snapshot()
	require.NoError(t, err)
	assert.False(t, state.Locked)
}

type scriptedHelper struct {
	idleHelper
	status   string
	stateErr error
}

func (h *scriptedHelper) Call(method string, _ map[string]any, out any) error {
	switch method {
	case "status":
		*out.(*string) = h.status
	case "state":
		return h.stateErr
	}
	return nil
}

func newUnlockedUFW(t *testing.T, helper ufwHelper, conf string) *ufwBackend {
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "ufw.conf"), []byte(conf), 0o600))
	b := &ufwBackend{
		configDir: dir,
		hasIface:  func(string) bool { return false },
		notify:    func() {},
		startHelp: func(context.Context) (ufwHelper, error) { return helper, nil },
	}
	require.NoError(t, b.Unlock())
	t.Cleanup(b.Close)
	return b
}

func TestUFWRunningPrefersLiveStatus(t *testing.T) {
	enabled := "ENABLED=yes\n"
	assert.False(t, newUnlockedUFW(t, &scriptedHelper{status: "Status: inactive\n"}, enabled).Running())
	assert.True(t, newUnlockedUFW(t, &scriptedHelper{status: "Status: active\nLogging: on\n"}, "ENABLED=no\n").Running())

	locked := newUnlockedUFW(t, idleHelper{}, enabled)
	locked.Close()
	assert.True(t, locked.Running(), "falls back to the config while locked")
}

func TestUFWReadFailureIsNotLocked(t *testing.T) {
	helper := &scriptedHelper{status: "Status: active\n", stateErr: errors.New("ufw exploded")}
	b := newUnlockedUFW(t, helper, "ENABLED=yes\n")

	state := newManager(nil, b).GetState()
	assert.False(t, state.Locked)
	assert.Equal(t, "ufw exploded", state.Error)

	helper.stateErr = errHelperGone
	state = newManager(nil, b).GetState()
	assert.True(t, state.Locked)
	assert.Empty(t, state.Error)
}

type closeCountingHelper struct {
	idleHelper
	closed atomic.Int32
}

func (h *closeCountingHelper) Close() { h.closed.Add(1) }

func TestUFWUnlockFinishingAfterClose(t *testing.T) {
	helper := &closeCountingHelper{}
	entered, release := make(chan struct{}), make(chan struct{})
	var promptCtx context.Context
	b := &ufwBackend{notify: func() {}, startHelp: func(ctx context.Context) (ufwHelper, error) {
		promptCtx = ctx
		close(entered)
		<-release
		return helper, nil
	}}

	result := make(chan error, 1)
	go func() { result <- b.Unlock() }()
	<-entered
	b.Close()
	assert.Error(t, promptCtx.Err(), "closing must end the open password prompt")
	close(release)

	assert.ErrorIs(t, <-result, ErrAuthDismissed)
	assert.Equal(t, int32(1), helper.closed.Load())
	assert.ErrorIs(t, b.call("state", nil, nil), errHelperLocked)
}
