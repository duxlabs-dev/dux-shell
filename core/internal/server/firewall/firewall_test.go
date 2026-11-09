package firewall

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
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
		{Kind: KindService, Action: ActionDrop, Target: "Apache Full", Source: "10.0.0.0/8"},
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
		{Kind: KindPort, Action: ActionAllow, Target: "65536", Proto: ProtoTCP},
		{Kind: KindPort, Action: ActionAllow, Target: "22-10", Proto: ProtoTCP},
		{Kind: KindPort, Action: ActionAllow, Target: "22-30", Proto: ProtoBoth},
		{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Source: `1.2.3.4" drop`},
		{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Source: "fe80::1%eth0"},
		{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Name: "it's mine"},
		{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Name: "two\nlines"},
		{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Name: strings.Repeat("a", maxRuleNameLength+1)},
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
		{RuleSpec{Kind: KindService, Action: ActionDrop, Target: "ssh"},
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
		{RuleSpec{Kind: KindPort, Action: ActionDrop, Target: "53", Proto: ProtoBoth}, []string{"deny", "53"}},
		{RuleSpec{Kind: KindPort, Action: ActionAllow, Target: "6000-6007", Proto: ProtoUDP}, []string{"allow", "6000:6007/udp"}},
		{RuleSpec{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Source: "10.0.0.1"},
			[]string{"allow", "from", "10.0.0.1", "to", "any", "port", "22", "proto", "tcp"}},
		{RuleSpec{Kind: KindService, Action: ActionReject, Target: "OpenSSH", Source: "10.0.0.0/8"},
			[]string{"reject", "from", "10.0.0.0/8", "to", "any", "app", "OpenSSH"}},
		{RuleSpec{Kind: KindPort, Action: ActionAllow, Target: "22", Proto: ProtoTCP, Name: "my ssh"},
			[]string{"allow", "22/tcp", "comment", "my ssh"}},
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
ufw deny from fd00::/8 to any port 6000:6007
ufw allow from 192.168.1.0/24 to any app 'Apache Full'
ufw allow 8080/tcp comment 'web dev'
ufw allow from 10.0.0.1 to any port 22 proto tcp comment 'jump host'
ufw allow from bogus to any port 22
ufw limit 22/tcp comment 'brute force'
ufw limit 22/tcp
ufw allow out 443/tcp
ufw route allow in on eth0 out on eth1
`

func TestParseUFWAdded(t *testing.T) {
	assert.Equal(t, []Rule{
		{ID: "allow 22/tcp", Kind: KindPort, Action: "allow", Target: "22", Proto: "tcp"},
		{ID: "deny 6000:6007/udp", Kind: KindPort, Action: "drop", Target: "6000-6007", Proto: "udp"},
		{ID: "allow 53", Kind: KindPort, Action: "allow", Target: "53"},
		{ID: "allow OpenSSH", Kind: KindService, Action: "allow", Target: "OpenSSH"},
		{ID: "reject 'Apache Full'", Kind: KindService, Action: "reject", Target: "Apache Full"},
		{ID: "allow from 10.0.0.0/8 to any port 80 proto tcp", Kind: KindPort, Action: "allow", Target: "80", Proto: "tcp", Source: "10.0.0.0/8"},
		{ID: "deny from fd00::/8 to any port 6000:6007", Kind: KindPort, Action: "drop", Target: "6000-6007", Source: "fd00::/8"},
		{ID: "allow from 192.168.1.0/24 to any app 'Apache Full'", Kind: KindService, Action: "allow", Target: "Apache Full", Source: "192.168.1.0/24"},
		{ID: "allow 8080/tcp comment 'web dev'", Kind: KindPort, Action: "allow", Target: "8080", Proto: "tcp", Name: "web dev"},
		{ID: "allow from 10.0.0.1 to any port 22 proto tcp comment 'jump host'", Kind: KindPort, Action: "allow", Target: "22", Proto: "tcp", Source: "10.0.0.1", Name: "jump host"},
		{ID: "allow from bogus to any port 22", Kind: KindRaw, Raw: "allow from bogus to any port 22"},
		{ID: "limit 22/tcp comment 'brute force'", Kind: KindRaw, Raw: "limit 22/tcp", Name: "brute force"},
		{ID: "limit 22/tcp", Kind: KindRaw, Raw: "limit 22/tcp"},
		{ID: "allow out 443/tcp", Kind: KindRaw, Raw: "allow out 443/tcp"},
		{ID: "route allow in on eth0 out on eth1", Kind: KindRaw, Raw: "route allow in on eth0 out on eth1"},
	}, parseUFWAdded(ufwAddedFixture))

	assert.Empty(t, parseUFWAdded("Added user rules (see 'ufw status' for running firewall):\n(None)"))
}

func TestParseUFWFiles(t *testing.T) {
	assert.Equal(t, []string{"Apache Full", "OpenSSH"}, parseUFWApps("Available applications:\n  Apache Full\n  OpenSSH\n"))
	assert.Equal(t, &Defaults{Incoming: "drop", Outgoing: "allow"},
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

func TestHelperUpdateRuleKeepsPosition(t *testing.T) {
	tests := []struct {
		name       string
		id         string
		params     map[string]any
		failDelete bool
		want       [][]string
	}{
		{"an action change on a service rewrites it in place", "allow OpenSSH",
			map[string]any{"kind": "service", "action": "drop", "target": "OpenSSH", "proto": "tcp"}, false,
			[][]string{{"deny", "OpenSSH"}}},
		{"a new target is inserted where the old rule was", "allow 53",
			map[string]any{"kind": "port", "action": "allow", "target": "54", "proto": "udp"}, false,
			[][]string{{"insert", "3", "allow", "54/udp"}, {"--force", "delete", "allow", "53"}}},
		{"an IPv6-only rule is outside the IPv4 numbering", "deny from fd00::/8 to any port 6000:6007",
			map[string]any{"kind": "port", "action": "drop", "target": "6000-6007", "proto": "udp", "source": "fd00::/8"}, false,
			[][]string{{"deny", "from", "fd00::/8", "to", "any", "port", "6000:6007", "proto", "udp"}, {"--force", "delete", "deny", "from", "fd00::/8", "to", "any", "port", "6000:6007"}}},
		{"a failed delete takes the new rule out again", "allow 53",
			map[string]any{"kind": "port", "action": "allow", "target": "54", "proto": "udp", "name": "dns"}, true,
			[][]string{{"insert", "3", "allow", "54/udp", "comment", "dns"}, {"--force", "delete", "allow", "53"}, {"--force", "delete", "allow", "54/udp"}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var calls [][]string
			helper := newTestHelper(&calls)
			run := helper.run
			helper.run = func(args ...string) (string, error) {
				out, err := run(args...)
				if tt.failDelete && fmt.Sprint(args) == "[--force delete allow 53]" {
					return "", errors.New("boom")
				}
				return out, err
			}
			tt.params["id"] = tt.id
			_, err := helper.Call("rule.update", tt.params)
			assert.Equal(t, tt.failDelete, err != nil, "%v", err)
			assert.Equal(t, tt.want, calls)
		})
	}
}

type fakeBus struct {
	running     bool
	authorized  bool
	authErr     error
	interactive []string
	calls       []string
	failOn      map[string]error
	inUse       string
	unloaded    []string
}

func (f *fakeBus) Running() bool { return f.running }

func (f *fakeBus) Authorized(_ context.Context, action string, interactive bool) (bool, error) {
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
		if method == firewalldConfig+".getZoneNames" {
			*out = append(*out, f.unloaded...)
		}
	case *map[string]map[string][]string:
		*out = map[string]map[string][]string{"home": {"interfaces": {"eno1"}}}
		if f.inUse != "" {
			(*out)[f.inUse] = map[string][]string{"interfaces": {"eno2"}}
		}
	case *string:
		*out = "home"
		if method == firewalldName+".getDefaultZone" && f.inUse == "dflt" {
			*out = f.inUse
		}
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
		{ID: `raw:rule service name="ftp" drop`, Kind: KindService, Action: ActionDrop, Target: "ftp"},
	}, state.Zones[0].Rules)
}

func TestParseRichRule(t *testing.T) {
	tests := []struct {
		rich string
		want Rule
	}{
		{`rule family="ipv4" source address="10.0.0.0/8" port port="80" protocol="tcp" accept`,
			Rule{Kind: KindPort, Action: ActionAllow, Target: "80", Proto: "tcp", Source: "10.0.0.0/8"}},
		{`rule port port="6000-6007" protocol="udp" reject`,
			Rule{Kind: KindPort, Action: ActionReject, Target: "6000-6007", Proto: "udp"}},
		{`rule family="ipv6" source address="fd00::/8" service name="ssh" drop`,
			Rule{Kind: KindService, Action: ActionDrop, Target: "ssh", Source: "fd00::/8"}},
		{`rule family="ipv4" source NOT address="10.0.0.0/8" service name="ssh" accept`,
			Rule{Kind: KindRaw, Raw: `rule family="ipv4" source NOT address="10.0.0.0/8" service name="ssh" accept`}},
		{`rule priority="-10" service name="ssh" accept`,
			Rule{Kind: KindRaw, Raw: `rule priority="-10" service name="ssh" accept`}},
		{`rule service name="ssh" log prefix="ssh" accept`,
			Rule{Kind: KindRaw, Raw: `rule service name="ssh" log prefix="ssh" accept`}},
		{`rule family="ipv4" source address="not-an-ip" service name="ssh" accept`,
			Rule{Kind: KindRaw, Raw: `rule family="ipv4" source address="not-an-ip" service name="ssh" accept`}},
	}
	for _, tt := range tests {
		tt.want.ID = KindRaw + ":" + tt.rich
		assert.Equal(t, tt.want, parseRichRule(tt.rich), tt.rich)
	}

	// What AddRule writes must read back as the same rule, or editing it would change it.
	for _, spec := range []RuleSpec{
		{Kind: KindPort, Action: ActionDrop, Target: "22", Proto: ProtoTCP, Source: "192.168.1.0/24"},
		{Kind: KindService, Action: ActionReject, Target: "ssh"},
	} {
		item := specItems(spec)[0]
		rule := parseRichRule(item.value)
		back, err := rule.spec()
		require.NoError(t, err)
		assert.Equal(t, spec, back)
	}
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
}

func TestItemFromID(t *testing.T) {
	item, err := itemFromID(`raw:rule service name="ftp:x" drop`)
	require.NoError(t, err)
	assert.Equal(t, firewalldItem{kind: KindRaw, value: `rule service name="ftp:x" drop`}, item)
	_, err = itemFromID("port:80")
	assert.Error(t, err)
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

	t.Run("returns to the old permanent zone when the new one refuses", func(t *testing.T) {
		bus := &failOnceBus{fakeBus: fakeBus{running: true, authorized: true}, method: firewalldConfigZone + ".addInterface"}
		err := (&firewalldBackend{bus: bus}).SetInterfaceZone("eno1", "public")
		assert.ErrorContains(t, err, "boom")
		assert.Equal(t, []string{
			firewalldConfig + ".getZoneOfInterface",
			firewalldConfig + ".getZoneByName", firewalldConfigZone + ".removeInterface",
			firewalldConfig + ".getZoneByName", firewalldConfigZone + ".addInterface",
			firewalldConfig + ".getZoneByName", firewalldConfigZone + ".addInterface",
		}, bus.calls)
	})
}

type failOnceBus struct {
	fakeBus
	method string
	failed bool
}

func (b *failOnceBus) Call(path, method string, args []any, ret ...any) error {
	if method == b.method && !b.failed {
		b.failed = true
		b.calls = append(b.calls, method)
		return errors.New("boom")
	}
	return b.fakeBus.Call(path, method, args, ret...)
}

func TestFirewalldListServicesStaysOffFirewalldWhileLocked(t *testing.T) {
	bus := &fakeBus{running: true}
	_, err := (&firewalldBackend{bus: bus}).ListServices()
	assert.ErrorIs(t, err, errHelperLocked)
	assert.Empty(t, bus.calls)
	assert.Empty(t, bus.interactive)
}

type blockingPromptBus struct {
	fakeBus
	entered chan struct{}
}

func (b *blockingPromptBus) Authorized(ctx context.Context, _ string, interactive bool) (bool, error) {
	if !interactive {
		return false, nil
	}
	close(b.entered)
	<-ctx.Done()
	return false, ErrAuthDismissed
}

func TestFirewalldCloseEndsOpenPrompt(t *testing.T) {
	bus := &blockingPromptBus{fakeBus: fakeBus{running: true}, entered: make(chan struct{})}
	backend := &firewalldBackend{bus: bus}

	result := make(chan error, 1)
	go func() { result <- backend.Unlock() }()
	<-bus.entered
	backend.Close()

	assert.ErrorIs(t, <-result, ErrAuthDismissed)
}

func TestInstalledFindsSbinOutsidePath(t *testing.T) {
	sbin := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(sbin, "ufw"), []byte("#!/bin/sh\n"), 0o755))
	t.Setenv("PATH", "")
	t.Setenv("HOME", t.TempDir())
	previous := sbinDirs
	sbinDirs = []string{sbin}
	t.Cleanup(func() { sbinDirs = previous })

	assert.Equal(t, []string{BackendUFW}, Installed())
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

// Polkit keeps a temporary authorization per action, not per user.
type perActionBus struct {
	fakeBus
	granted map[string]bool
}

func (b *perActionBus) Authorized(_ context.Context, action string, interactive bool) (bool, error) {
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
	assert.Equal(t, map[string]bool{actionConfig: true}, bus.granted, "unlock must cover edits too")
}

type lapsingBus struct {
	fakeBus
	lapsed atomic.Bool
}

func (b *lapsingBus) Authorized(context.Context, string, bool) (bool, error) {
	return !b.lapsed.Load(), nil
}

func TestFirewalldRelocksWhenAuthorizationLapses(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		bus := &lapsingBus{fakeBus: fakeBus{running: true}}
		backend := &firewalldBackend{bus: bus}

		// NewManager takes its first snapshot before Start hands over notify.
		_, err := backend.Snapshot()
		require.NoError(t, err)
		var notified atomic.Int32
		backend.mu.Lock()
		backend.notify = func() { notified.Add(1) }
		backend.mu.Unlock()

		time.Sleep(3 * relockPoll)
		synctest.Wait()
		assert.Zero(t, notified.Load())

		bus.lapsed.Store(true)
		time.Sleep(relockPoll)
		synctest.Wait()
		assert.Equal(t, int32(1), notified.Load())
		assert.Nil(t, backend.relock, "a locked page must stay idle")
	})

	t.Run("a closed backend stays idle", func(t *testing.T) {
		backend := &firewalldBackend{bus: &fakeBus{running: true, authorized: true}}
		backend.Close()
		_, err := backend.Snapshot()
		require.NoError(t, err)
		assert.Nil(t, backend.relock)
	})
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

func TestUFWUnlockGivesUpOnAbandonedPrompt(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		b := &ufwBackend{notify: func() {}, startHelp: func(ctx context.Context) (ufwHelper, error) {
			<-ctx.Done()
			return nil, ErrAuthDismissed
		}}
		result := make(chan error, 1)
		go func() { result <- b.Unlock() }()

		time.Sleep(promptTimeout + time.Second)
		synctest.Wait()
		select {
		case err := <-result:
			assert.ErrorIs(t, err, ErrAuthDismissed)
		default:
			t.Fatal("Unlock still holds the write lock")
		}
	})
}

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

func TestZoneManagement(t *testing.T) {
	const (
		add    = firewalldConfig + ".addZone2"
		rename = firewalldConfigZone + ".rename"
		remove = firewalldConfigZone + ".remove"
		reload = firewalldName + ".reload"
	)
	newBackend := func() (*firewalldBackend, *fakeBus) {
		bus := &fakeBus{running: true, authorized: true}
		return &firewalldBackend{bus: bus}, bus
	}

	t.Run("add creates the zone and reloads", func(t *testing.T) {
		b, bus := newBackend()
		require.NoError(t, b.AddZone("lab"))
		assert.Equal(t, []string{add, reload}, bus.calls[len(bus.calls)-2:])
	})
	t.Run("add loads a saved zone that was never loaded", func(t *testing.T) {
		bus := &fakeBus{running: true, authorized: true, unloaded: []string{"myzone"}}
		b := &firewalldBackend{bus: bus}
		require.NoError(t, b.AddZone("myzone"))
		assert.NotContains(t, bus.calls, add)
		assert.Equal(t, reload, bus.calls[len(bus.calls)-1])
	})
	t.Run("add rejects bad, managed and existing names before writing", func(t *testing.T) {
		for _, name := range []string{"", "has space", "bad/name", "waytoolongzonenameforfirewalld", "docker", "libvirt-x", "home"} {
			b, bus := newBackend()
			assert.Error(t, b.AddZone(name), name)
			assert.NotContains(t, bus.calls, add, name)
		}
	})
	t.Run("rename and remove touch only free custom zones", func(t *testing.T) {
		b, bus := newBackend()
		require.NoError(t, b.RenameZone("lab", "lab2"))
		require.NoError(t, b.RemoveZone("lab"))
		assert.Contains(t, bus.calls, rename)
		assert.Contains(t, bus.calls, remove)
		assert.Equal(t, reload, bus.calls[len(bus.calls)-1])
	})
	t.Run("built in, managed, default and active zones are refused", func(t *testing.T) {
		for _, name := range []string{"public", "docker", "home"} {
			b, bus := newBackend()
			assert.Error(t, b.RenameZone(name, "lab2"), name)
			assert.Error(t, b.RemoveZone(name), name)
			assert.NotContains(t, bus.calls, rename)
			assert.NotContains(t, bus.calls, remove)
		}
	})
	t.Run("default and active custom zones are refused", func(t *testing.T) {
		for _, inUse := range []string{"dflt", "lab"} {
			bus := &fakeBus{running: true, authorized: true, inUse: inUse}
			b := &firewalldBackend{bus: bus}
			assert.Error(t, b.RenameZone(inUse, "lab2"), inUse)
			assert.Error(t, b.RemoveZone(inUse), inUse)
			assert.NotContains(t, bus.calls, rename)
			assert.NotContains(t, bus.calls, remove)
		}
	})
	t.Run("rename onto an existing zone is refused", func(t *testing.T) {
		b, bus := newBackend()
		assert.Error(t, b.RenameZone("lab", "home"))
		assert.NotContains(t, bus.calls, rename)
	})
	t.Run("ufw has no zones", func(t *testing.T) {
		u := &ufwBackend{}
		assert.Error(t, u.AddZone("lab"))
		assert.Error(t, u.RenameZone("lab", "lab2"))
		assert.Error(t, u.RemoveZone("lab"))
	})
}

type ruleBackend struct {
	fakeBackend
	rules   []Rule
	failNew bool
	calls   []string
}

func (b *ruleBackend) Snapshot() (State, error) {
	return State{Backend: BackendUFW, Active: true, Rules: b.rules}, nil
}

func (b *ruleBackend) RemoveRule(_, id string) error {
	b.calls = append(b.calls, "remove "+id)
	return nil
}

func (b *ruleBackend) AddRule(_ string, spec RuleSpec) error {
	args := strings.Join(spec.ufwArgs(), " ")
	b.calls = append(b.calls, "add "+args)
	if b.failNew && spec.Target != "53" {
		return errors.New("rejected")
	}
	return nil
}

func TestUpdateRule(t *testing.T) {
	rules := []Rule{
		{ID: "allow 53 comment 'dns'", Kind: KindPort, Action: ActionAllow, Target: "53", Name: "dns"},
		{ID: "limit 22/tcp", Kind: KindRaw, Raw: "limit 22/tcp"},
	}
	edited := RuleSpec{Kind: KindPort, Action: ActionDrop, Target: "54", Proto: ProtoUDP}

	tests := []struct {
		name    string
		id      string
		spec    RuleSpec
		failNew bool
		wantErr bool
		want    []string
	}{
		{"replaces the rule", rules[0].ID, edited, false, false,
			[]string{"remove allow 53 comment 'dns'", "add deny 54/udp"}},
		{"restores the old rule when the new one fails", rules[0].ID, edited, true, true,
			[]string{"remove allow 53 comment 'dns'", "add deny 54/udp", "add allow 53 comment dns"}},
		{"leaves raw rules alone", rules[1].ID, edited, false, true, nil},
		{"leaves unknown rules alone", "allow 9/tcp", edited, false, true, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			backend := &ruleBackend{fakeBackend: fakeBackend{name: BackendUFW, running: true}, rules: rules, failNew: tt.failNew}
			err := newManager(nil, backend).UpdateRule("", tt.id, tt.spec)
			assert.Equal(t, tt.wantErr, err != nil, "%v", err)
			assert.Equal(t, tt.want, backend.calls)
		})
	}
}
