package network

import (
	"context"
	"fmt"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const privatePluginPath dbus.ObjectPath = "/org/freedesktop/NetworkManager/VPN/Plugin"
const privatePluginInterface = "org.freedesktop.NetworkManager.VPN.Plugin"

type privateOpenConnectPlugin struct {
	bus         *dbus.Conn
	mu          sync.Mutex
	state       uint32
	connects    chan map[string]string
	disconnects chan struct{}
}

func (p *privateOpenConnectPlugin) NeedSecrets(settings map[string]map[string]dbus.Variant) (string, *dbus.Error) {
	secrets, _ := settings["vpn"]["secrets"].Value().(map[string]string)
	for _, field := range []string{"cookie", "gateway", "gwcert", "resolve"} {
		if secrets[field] == "" {
			return "vpn", nil
		}
	}
	return "", nil
}
func (p *privateOpenConnectPlugin) Connect(settings map[string]map[string]dbus.Variant) *dbus.Error {
	secrets, _ := settings["vpn"]["secrets"].Value().(map[string]string)
	p.connects <- maps.Clone(secrets)
	return nil
}
func (p *privateOpenConnectPlugin) ConnectInteractive(settings map[string]map[string]dbus.Variant, details map[string]dbus.Variant) *dbus.Error {
	return p.Connect(settings)
}
func (p *privateOpenConnectPlugin) Disconnect() *dbus.Error {
	p.mu.Lock()
	p.state = 6
	p.mu.Unlock()
	if err := p.bus.Emit(privatePluginPath, privatePluginInterface+".StateChanged", uint32(6)); err != nil {
		return dbus.MakeFailedError(err)
	}
	p.disconnects <- struct{}{}
	return nil
}
func (p *privateOpenConnectPlugin) Get(iface, name string) (dbus.Variant, *dbus.Error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return dbus.MakeVariant(p.state), nil
}
func (p *privateOpenConnectPlugin) GetAll(iface string) (map[string]dbus.Variant, *dbus.Error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return map[string]dbus.Variant{"State": dbus.MakeVariant(p.state)}, nil
}
func (p *privateOpenConnectPlugin) complete(t *testing.T) {
	t.Helper()
	privateCommand(t, "ip", "link", "add", "nmtestvpn0", "type", "dummy")
	privateCommand(t, "ip", "link", "set", "nmtestvpn0", "up")
	config := map[string]dbus.Variant{
		"tundev": dbus.MakeVariant("nmtestvpn0"), "has-ip4": dbus.MakeVariant(true),
		"has-ip6": dbus.MakeVariant(false), "can-persist": dbus.MakeVariant(false), "gateway": dbus.MakeVariant(uint32(16908480)),
	}
	ip4 := map[string]dbus.Variant{"address": dbus.MakeVariant(uint32(40121286)), "prefix": dbus.MakeVariant(uint32(24)), "never-default": dbus.MakeVariant(true)}
	require.NoError(t, p.bus.Emit(privatePluginPath, privatePluginInterface+".Config", config))
	require.NoError(t, p.bus.Emit(privatePluginPath, privatePluginInterface+".Ip4Config", ip4))
	p.mu.Lock()
	p.state = 4
	p.mu.Unlock()
	require.NoError(t, p.bus.Emit(privatePluginPath, privatePluginInterface+".StateChanged", uint32(4)))
}

func TestOpenConnectHelperPrivateNetworkManager(t *testing.T) {
	bus := connectPrivateNetworkManager(t)
	nmObj := bus.Object(dbusNMInterface, dbus.ObjectPath(dbusNMPath))

	pluginBus, err := dbus.Connect(os.Getenv("DMS_TEST_NM_PRIVATE_BUS"))
	require.NoError(t, err)
	t.Cleanup(func() { pluginBus.Close() })
	plugin := &privateOpenConnectPlugin{bus: pluginBus, state: 1, connects: make(chan map[string]string, 16), disconnects: make(chan struct{}, 16)}
	require.NoError(t, pluginBus.Export(plugin, privatePluginPath, privatePluginInterface))
	require.NoError(t, pluginBus.Export(plugin, privatePluginPath, dbusPropsInterface))
	reply, err := pluginBus.RequestName(openConnectHelperService, dbus.NameFlagDoNotQueue)
	require.NoError(t, err)
	require.Equal(t, dbus.RequestNameReplyPrimaryOwner, reply)
	privateCommand(t, "nmcli", "connection", "add", "type", "dummy", "ifname", "nmtest0", "con-name", "dms-synthetic-base", "ipv4.method", "manual", "ipv4.addresses", "192.0.2.2/24", "ipv4.gateway", "192.0.2.1", "ipv6.method", "disabled")
	privateCommand(t, "nmcli", "--wait", "12", "connection", "up", "dms-synthetic-base")

	dir := t.TempDir()
	helper := filepath.Join(dir, "auth-helper")
	require.NoError(t, os.WriteFile(helper, []byte(privateOpenConnectHelperPython), 0700))
	require.NoError(t, os.WriteFile(filepath.Join(dir, "mode"), []byte("success"), 0600))
	backend, err := NewNetworkManagerBackend()
	require.NoError(t, err)
	backend.settings, err = gonetworkmanager.NewSettings()
	require.NoError(t, err)
	backend.openConnectHelperFinder = func() (string, error) { return helper, nil }
	require.NoError(t, backend.startSignalPump())
	agent, err := NewSecretAgent(nil, nil, backend)
	require.NoError(t, err)
	backend.secretAgent = agent
	t.Cleanup(backend.Close)

	profile := map[string]map[string]dbus.Variant{
		"connection": {"id": dbus.MakeVariant("dms-synthetic-helper"), "type": dbus.MakeVariant("vpn"), "autoconnect": dbus.MakeVariant(false)},
		"vpn": {"service-type": dbus.MakeVariant(openConnectHelperService), "data": dbus.MakeVariant(map[string]string{
			"gateway": "invalid.example", "protocol": "anyconnect", "password-flags": "0", "unknown-secret-flags": "0", "xmlconfig-flags": "0", "form:main:username-flags": "0", "custom-sentinel": "keep-me",
		}), "secrets": dbus.MakeVariant(map[string]string{"password": "DUMMY-OLD-GENERIC-PASSWORD", "unknown-secret": "DUMMY-UNKNOWN-SECRET", "xmlconfig": "aW5pdGlhbA==", "form:main:username": "initial-user"})},
		"ipv4":  {"method": dbus.MakeVariant("auto"), "never-default": dbus.MakeVariant(true), "route-metric": dbus.MakeVariant(int64(321)), "dns": dbus.MakeVariant([]uint32{890007744}), "dns-search": dbus.MakeVariant([]string{"synthetic.invalid"}), "routes": dbus.MakeVariant([][]uint32{{uint32(7340230), 24, 0, 37}})},
		"ipv6":  {"method": dbus.MakeVariant("link-local"), "never-default": dbus.MakeVariant(true)},
		"proxy": {"method": dbus.MakeVariant(int32(0))},
	}
	var path dbus.ObjectPath
	require.NoError(t, bus.Object(dbusNMInterface, dbus.ObjectPath(dbusNMSettingsPath)).Call(dbusNMSettingsInterface+".AddConnection", 0, profile).Store(&path))
	obj := bus.Object(dbusNMInterface, path)
	t.Cleanup(func() { require.NoError(t, obj.Call(dbusNMSettingsConnectionInterface+".Delete", 0).Err) })
	settings := func() map[string]map[string]dbus.Variant {
		var result map[string]map[string]dbus.Variant
		require.NoError(t, obj.Call(dbusNMSettingsConnectionInterface+".GetSettings", 0).Store(&result))
		return result
	}
	before := settings()
	uuid := before["connection"]["uuid"].Value().(string)
	connection, err := gonetworkmanager.NewConnection(path)
	require.NoError(t, err)
	stored := func() map[string]string {
		secrets, err := backend.readStoredOpenConnectSecrets(connection, uuid, openConnectHelperService, before["vpn"]["data"].Value().(map[string]string))
		require.NoError(t, err)
		return secrets["vpn"]["secrets"].(map[string]string)
	}
	initialSecrets := stored()
	persisted := func() map[string]string {
		filename, err := obj.GetProperty(dbusNMSettingsConnectionInterface + ".Filename")
		require.NoError(t, err)
		require.True(t, strings.HasPrefix(filename.Value().(string), "/etc/NetworkManager/system-connections/"))
		raw, err := os.ReadFile(filename.Value().(string))
		require.NoError(t, err)
		result := map[string]string{}
		section := ""
		for _, line := range strings.Split(string(raw), "\n") {
			if strings.HasPrefix(line, "[") {
				section = line
				continue
			}
			if key, value, ok := strings.Cut(line, "="); ok && section == "[vpn-secrets]" {
				result[key] = value
			}
		}
		return result
	}
	require.Equal(t, initialSecrets, persisted())
	count := func() int {
		raw, _ := os.ReadFile(filepath.Join(dir, "count"))
		n, _ := strconv.Atoi(string(raw))
		return n
	}
	registryEmpty := func() bool {
		backend.openConnectHelperMu.Lock()
		defer backend.openConnectHelperMu.Unlock()
		return len(backend.openConnectHelperAttempts) == 0
	}
	active := func() dbus.ObjectPath {
		v, err := nmObj.GetProperty(dbusNMInterface + ".ActiveConnections")
		if err != nil {
			return ""
		}
		for _, p := range v.Value().([]dbus.ObjectPath) {
			v, err := bus.Object(dbusNMInterface, p).GetProperty(dbusNMActiveConnInterface + ".Uuid")
			if err == nil && v.Value() == uuid {
				return p
			}
		}
		return ""
	}
	stateIs := func(p dbus.ObjectPath, iface, prop string, expected uint32) bool {
		v, err := bus.Object(dbusNMInterface, p).GetProperty(iface + "." + prop)
		return err == nil && v.Value() == expected
	}
	checkPreserved := func(t *testing.T) {
		now := settings()
		for _, section := range []string{"ipv4", "ipv6", "proxy"} {
			require.Equal(t, before[section], now[section], "full typed %s settings survive", section)
		}
		data := now["vpn"]["data"].Value().(map[string]string)
		require.Equal(t, "keep-me", data["custom-sentinel"])
		for _, key := range []string{"cookie", "gateway", "gwcert", "resolve"} {
			require.Equal(t, "2", data[key+"-flags"])
		}
		secret := persisted()
		require.Equal(t, initialSecrets["password"], secret["password"])
		require.Equal(t, initialSecrets["unknown-secret"], secret["unknown-secret"])
		for _, key := range []string{"cookie", "gateway", "gwcert", "resolve"} {
			require.NotContains(t, secret, key)
		}
	}
	disconnect := func(t *testing.T) {
		p := active()
		require.NotEmpty(t, p)
		require.NoError(t, nmObj.Call(dbusNMInterface+".DeactivateConnection", 0, p).Err)
		privateEventually(t, "VPN removed", func() bool { return active() == "" })
		privateEventually(t, "helper registry cleared", registryEmpty)
		select {
		case <-plugin.disconnects:
		case <-time.After(10 * time.Second):
			t.Fatal("plugin did not disconnect")
		}
		// NM may already remove the dummy interface during deactivation.
		if exec.Command("ip", "link", "show", "nmtestvpn0").Run() == nil {
			privateCommand(t, "ip", "link", "delete", "nmtestvpn0")
		}
		privateEventually(t, "DMS no longer connecting", func() bool { s, _ := backend.GetCurrentState(); return !s.IsConnectingVPN })
	}
	var previousCookie string
	for attempt := 1; attempt <= 2; attempt++ {
		label := "dms-prepares-unprepared-profile"
		if attempt == 2 {
			label = "bare-nmcli-fresh-reconnect"
		}
		t.Run(label, func(t *testing.T) {
			previous := persisted()
			var cliDone chan error
			if attempt == 1 {
				require.NotContains(t, settings()["vpn"]["data"].Value(), "cookie-flags")
				require.NoError(t, backend.ConnectVPN(uuid, false))
			} else {
				s, err := backend.GetCurrentState()
				require.NoError(t, err)
				require.False(t, s.IsConnectingVPN)
				cliDone = make(chan error, 1)
				go func() {
					ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
					defer cancel()
					out, err := exec.CommandContext(ctx, "nmcli", "--wait", "12", "connection", "up", "uuid", uuid).CombinedOutput()
					if err != nil {
						err = fmt.Errorf("%w: %s", err, out)
					}
					cliDone <- err
				}()
			}
			var delivered map[string]string
			select {
			case delivered = <-plugin.connects:
			case <-time.After(15 * time.Second):
				t.Fatal("real NM never delivered helper secrets to plugin")
			}
			require.Equal(t, attempt, count(), "one helper invocation per activation")
			require.NotEmpty(t, delivered["cookie"])
			require.NotEqual(t, previousCookie, delivered["cookie"])
			previousCookie = delivered["cookie"]
			require.Equal(t, "192.0.2.1:443", delivered["gateway"])
			require.Equal(t, "DUMMY-CERT-HASH", delivered["gwcert"])
			require.Equal(t, "invalid.example:192.0.2.1", delivered["resolve"])
			input, err := os.ReadFile(filepath.Join(dir, fmt.Sprintf("input-%d", attempt)))
			require.NoError(t, err)
			require.NotContains(t, string(input), "DUMMY-OLD-GENERIC-PASSWORD")
			require.NotContains(t, string(input), "DUMMY-UNKNOWN-SECRET")
			require.Contains(t, string(input), "SECRET_KEY=xmlconfig\nSECRET_VAL="+previous["xmlconfig"]+"\n")
			require.Contains(t, string(input), "SECRET_KEY=form:main:username\nSECRET_VAL="+previous["form:main:username"]+"\n")
			for _, key := range []string{"lasthost", "save_passwords", "autoconnect"} {
				if value, ok := previous[key]; ok {
					require.Contains(t, string(input), "SECRET_KEY="+key+"\nSECRET_VAL="+value+"\n")
				}
			}
			require.True(t, strings.HasSuffix(string(input), "DONE\n\nQUIT\n\n"))
			require.Equal(t, previous, persisted(), "helper preferences must remain staged before terminal success")
			p := active()
			require.NotEmpty(t, p)
			privateEventually(t, "NM waiting for plugin IP config", func() bool { return stateIs(p, dbusNMVPNConnInterface, "VpnState", 3) })
			plugin.complete(t)
			privateEventually(t, "real VPN activated", func() bool {
				return stateIs(p, dbusNMVPNConnInterface, "VpnState", 5) && stateIs(p, dbusNMActiveConnInterface, "State", 2)
			})
			if cliDone != nil {
				select {
				case err := <-cliDone:
					require.NoError(t, err)
				case <-time.After(15 * time.Second):
					t.Fatal("external nmcli did not finish")
				}
			}
			privateEventually(t, "success metadata saved and attempt released", registryEmpty)
			t.Logf("real NM VPN state=5, active state=2; helper invocation=%d, fresh cookie; external nmcli=%t", attempt, cliDone != nil)
			assert.Equal(t, map[string]string{
				"form:main:username": fmt.Sprintf("synthetic-user-%d", attempt), "xmlconfig": "c3ludGhldGlj",
				"lasthost": "invalid.example", "save_passwords": "no", "autoconnect": "no",
			}, openConnectHelperMetadata(persisted()), "terminal success must persist all helper metadata")
			checkPreserved(t)
			disconnect(t)
		})
	}
	for _, mode := range []string{"malformed", "nonzero", "cancel", "block"} {
		t.Run(mode, func(t *testing.T) {
			previous := persisted()
			n := count() + 1
			require.NoError(t, os.WriteFile(filepath.Join(dir, "mode"), []byte(mode), 0600))
			require.NoError(t, backend.ConnectVPN(uuid, false))
			privateEventually(t, "fake helper invoked", func() bool { return count() >= n })
			if mode == "block" {
				privateEventually(t, "blocking helper ready", func() bool { _, err := os.Stat(filepath.Join(dir, fmt.Sprintf("blocked-%d", n))); return err == nil })
				raw, err := os.ReadFile(filepath.Join(dir, fmt.Sprintf("pid-%d", n)))
				require.NoError(t, err)
				pid, err := strconv.Atoi(string(raw))
				require.NoError(t, err)
				p := active()
				require.NotEmpty(t, p)
				require.NoError(t, nmObj.Call(dbusNMInterface+".DeactivateConnection", 0, p).Err)
				privateEventually(t, "cancelled helper is killed and reaped", func() bool { return syscall.Kill(pid, 0) == syscall.ESRCH })
				t.Log("real NM deactivation cancelled and reaped the blocking helper")
			}
			privateEventually(t, "failed activation removed", func() bool { return active() == "" })
			privateEventually(t, "failure releases helper attempt", registryEmpty)
			require.Equal(t, previous, persisted(), "failed or cancelled helper cannot persist preferences")
			require.Equal(t, n, count())
			require.Empty(t, plugin.connects, "invalid helper response must never reach Connect")
		})
	}
	t.Run("reconnect-after-cancellation", func(t *testing.T) {
		require.NoError(t, os.WriteFile(filepath.Join(dir, "mode"), []byte("success"), 0600))
		n := count() + 1
		require.NoError(t, backend.ConnectVPN(uuid, false))
		select {
		case delivered := <-plugin.connects:
			require.NotEqual(t, previousCookie, delivered["cookie"])
		case <-time.After(15 * time.Second):
			t.Fatal("reconnect did not reach plugin")
		}
		p := active()
		require.NotEmpty(t, p)
		privateEventually(t, "reconnect waiting for config", func() bool { return stateIs(p, dbusNMVPNConnInterface, "VpnState", 3) })
		plugin.complete(t)
		privateEventually(t, "reconnect activated", func() bool {
			return stateIs(p, dbusNMVPNConnInterface, "VpnState", 5) && stateIs(p, dbusNMActiveConnInterface, "State", 2)
		})
		privateEventually(t, "reconnect metadata persisted", registryEmpty)
		require.Equal(t, n, count())
		assert.Equal(t, fmt.Sprintf("synthetic-user-%d", n), persisted()["form:main:username"], "terminal success must persist helper metadata")
		checkPreserved(t)
		disconnect(t)
	})
	t.Run("concurrent-secret-edit-aborts-metadata-save", func(t *testing.T) {
		previous := persisted()
		var armed atomic.Bool
		armed.Store(true)
		edited := make(chan error, 1)
		// Forward to the real agent, inserting a competing system-password edit
		// exactly during its scoped metadata read. No production seam is replaced.
		getSecrets := func(conn map[string]nmVariantMap, requestPath dbus.ObjectPath, setting string, hints []string, flags uint32) (nmSettingMap, *dbus.Error) {
			if requestPath == path && backend.isReadingOpenConnectSecrets(uuid, path) && armed.CompareAndSwap(true, false) {
				var latest map[string]map[string]dbus.Variant
				err := obj.Call(dbusNMSettingsConnectionInterface+".GetSettings", 0).Store(&latest)
				if err == nil {
					secrets := maps.Clone(previous)
					secrets["password"] = "DUMMY-CONCURRENT-PASSWORD"
					latest["vpn"]["secrets"] = dbus.MakeVariant(secrets)
					err = normalizeLegacyIPv6Settings(latest["ipv6"])
				}
				if err == nil {
					err = obj.Call(dbusNMSettingsConnectionInterface+".Update2", 0, latest, uint32(1), map[string]dbus.Variant{}).Err
				}
				edited <- err
				if err != nil {
					return nil, dbus.MakeFailedError(err)
				}
			}
			return agent.GetSecrets(conn, requestPath, setting, hints, flags)
		}
		require.NoError(t, agent.conn.ExportMethodTable(map[string]any{
			"GetSecrets": getSecrets, "CancelGetSecrets": agent.CancelGetSecrets,
			"SaveSecrets": agent.SaveSecrets, "DeleteSecrets": agent.DeleteSecrets,
		}, agent.objPath, nmSecretAgentIface))
		defer func() { require.NoError(t, agent.conn.Export(agent, agent.objPath, nmSecretAgentIface)) }()
		require.NoError(t, backend.ConnectVPN(uuid, false))
		select {
		case <-plugin.connects:
		case <-time.After(15 * time.Second):
			t.Fatal("activation did not reach plugin")
		}
		p := active()
		require.NotEmpty(t, p)
		privateEventually(t, "activation waiting for config", func() bool { return stateIs(p, dbusNMVPNConnInterface, "VpnState", 3) })
		plugin.complete(t)
		select {
		case err := <-edited:
			require.NoError(t, err)
		case <-time.After(15 * time.Second):
			t.Fatal("scoped metadata read was not intercepted")
		}
		privateEventually(t, "conflicting metadata save released", registryEmpty)
		expected := maps.Clone(previous)
		expected["password"] = "DUMMY-CONCURRENT-PASSWORD"
		require.Equal(t, expected, persisted(), "preserve competing secret edit and do not save stale metadata")
		for _, section := range []string{"ipv4", "ipv6", "proxy"} {
			require.Equal(t, before[section], settings()[section])
		}
		disconnect(t)
	})

	for _, strictPKI := range []bool{false, true} {
		t.Run(fmt.Sprintf("fortinet-production-connect-strict-pki=%t", strictPKI), func(t *testing.T) {
			privateEventually(t, "previous VPN stopped", func() bool {
				s, err := backend.GetCurrentState()
				return err == nil && !s.IsConnectingVPN && active() == "" && registryEmpty()
			})
			binDir := t.TempDir()
			require.NoError(t, os.WriteFile(filepath.Join(binDir, "openconnect"), []byte(privateFortinetOpenConnectPython), 0700))
			t.Setenv("PATH", binDir+":"+os.Getenv("PATH"))
			caFile := filepath.Join(binDir, "synthetic-ca.pem")
			require.NoError(t, os.WriteFile(caFile, []byte("DUMMY-CA-NOT-A-CERTIFICATE\n"), 0600))
			mode := "success"
			if strictPKI {
				mode = "strict-pki"
			}
			require.NoError(t, os.WriteFile(filepath.Join(binDir, "mode"), []byte(mode), 0600))

			updated := settings()
			data := maps.Clone(updated["vpn"]["data"].Value().(map[string]string))
			data["protocol"], data["authtype"], data["username"] = "fortinet", "password", "synthetic-user"
			data["gateway"] = "invalid.example:443"
			secrets := persisted()
			secrets["password"] = "DUMMY-FORTINET-PASSWORD"
			if strictPKI {
				data["prevent_invalid_cert"], data["cacert"] = "yes", caFile
				data["certificate:invalid.example:443-flags"] = "0"
				secrets["certificate:invalid.example:443"] = "pin-sha256:DUMMY-STORED-PIN"
			}
			updated["vpn"]["data"] = dbus.MakeVariant(data)
			updated["vpn"]["secrets"] = dbus.MakeVariant(secrets)
			require.NoError(t, normalizeLegacyIPv6Settings(updated["ipv6"]))
			require.NoError(t, obj.Call(dbusNMSettingsConnectionInterface+".Update2", 0, updated, uint32(1), map[string]dbus.Variant{}).Err)
			profileBefore, secretsBefore := settings(), persisted()
			require.Equal(t, secrets, secretsBefore)
			helperCount := count()
			var helperFinds atomic.Int32
			backend.openConnectHelperFinder = func() (string, error) {
				helperFinds.Add(1)
				return helper, nil
			}
			broker := &fakePromptBroker{asked: make(chan PromptRequest, 8)}
			backend.promptBroker = broker

			type handoff struct {
				flags         uint32
				before, after *cachedOpenConnectAuth
				out           nmSettingMap
				err           *dbus.Error
			}
			handoffs := make(chan handoff, 16)
			getSecrets := func(conn map[string]nmVariantMap, requestPath dbus.ObjectPath, setting string, hints []string, flags uint32) (nmSettingMap, *dbus.Error) {
				backend.cachedOpenConnectMu.Lock()
				cached := backend.cachedOpenConnectAuth
				backend.cachedOpenConnectMu.Unlock()
				out, dbusErr := agent.GetSecrets(conn, requestPath, setting, hints, flags)
				backend.cachedOpenConnectMu.Lock()
				after := backend.cachedOpenConnectAuth
				backend.cachedOpenConnectMu.Unlock()
				if requestPath == path && cached != nil {
					handoffs <- handoff{flags: flags, before: cached, after: after, out: out, err: dbusErr}
				}
				return out, dbusErr
			}
			require.NoError(t, agent.conn.ExportMethodTable(map[string]any{
				"GetSecrets": getSecrets, "CancelGetSecrets": agent.CancelGetSecrets,
				"SaveSecrets": agent.SaveSecrets, "DeleteSecrets": agent.DeleteSecrets,
			}, agent.objPath, nmSecretAgentIface))
			defer func() { require.NoError(t, agent.conn.Export(agent, agent.objPath, nmSecretAgentIface)) }()

			err := backend.ConnectVPN(uuid, false)
			if strictPKI {
				require.ErrorContains(t, err, "OpenConnect authentication failed")
				require.NotContains(t, err.Error(), "DUMMY-FORTINET-PASSWORD")
				require.Empty(t, active(), "strict PKI failure must precede activation")
				require.Empty(t, plugin.connects)
				require.Empty(t, handoffs)
				s, err := backend.GetCurrentState()
				require.NoError(t, err)
				require.False(t, s.IsConnectingVPN)
			} else {
				require.NoError(t, err)
				select {
				case delivered := <-plugin.connects:
					for key, value := range map[string]string{
						"cookie": "DUMMY-FORTINET-COOKIE", "gateway": "invalid.example:443",
						"gwcert": "pin-sha256:DUMMY-FORTINET-CERT", "resolve": "invalid.example:192.0.2.1",
					} {
						require.Equal(t, value, delivered[key], "real NM plugin received %s", key)
					}
				case <-time.After(15 * time.Second):
					t.Fatal("real NM never delivered Fortinet preauthentication to plugin")
				}
				for _, flags := range []uint32{4, 5} {
					select {
					case h := <-handoffs:
						require.Equal(t, flags, h.flags, "real NM must use noninteractive then interactive handoff")
						if flags == 4 {
							require.NotNil(t, h.err)
							require.Equal(t, "org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", h.err.Name)
							require.Nil(t, h.out)
							require.Same(t, h.before, h.after, "flags=4 must preserve cache")
						} else {
							require.Nil(t, h.err)
							require.Equal(t, "DUMMY-FORTINET-COOKIE", h.out["vpn"]["secrets"].Value().(map[string]string)["cookie"])
							require.Nil(t, h.after, "flags=5 must consume cache")
						}
					case <-time.After(15 * time.Second):
						t.Fatalf("no real agent handoff for flags=%d", flags)
					}
				}
				p := active()
				require.NotEmpty(t, p)
				privateEventually(t, "Fortinet waiting for config", func() bool { return stateIs(p, dbusNMVPNConnInterface, "VpnState", 3) })
				plugin.complete(t)
				privateEventually(t, "Fortinet activated", func() bool {
					return stateIs(p, dbusNMVPNConnInterface, "VpnState", 5) && stateIs(p, dbusNMActiveConnInterface, "State", 2)
				})
				t.Log("production ConnectVPN read stored Fortinet password, preauthenticated, handed off once via real NM flags=4 then 5, and reached VPN state=5")
				disconnect(t)
			}
			args, err := os.ReadFile(filepath.Join(binDir, "args"))
			require.NoError(t, err)
			expectedArgs := []string{"--protocol=fortinet", "--user=synthetic-user", "--passwd-on-stdin", "--non-inter"}
			if strictPKI {
				expectedArgs = append(expectedArgs, "--cafile="+caFile)
			}
			expectedArgs = append(expectedArgs, "--authenticate", "invalid.example:443")
			require.Equal(t, strings.Join(expectedArgs, "\n")+"\n", string(args), "no certificate bypass or stored pin")
			input, err := os.ReadFile(filepath.Join(binDir, "stdin"))
			require.NoError(t, err)
			require.Equal(t, "DUMMY-FORTINET-PASSWORD\n", string(input))
			attempts, err := os.ReadFile(filepath.Join(binDir, "attempts"))
			require.NoError(t, err)
			require.Equal(t, "attempt\n", string(attempts), "no retry")
			require.Zero(t, helperFinds.Load(), "Fortinet must not discover the AnyConnect helper")
			require.Equal(t, helperCount, count(), "Fortinet must not invoke the AnyConnect helper")
			require.Empty(t, broker.asked, "stored password and strict PKI must not prompt")
			profileAfter := settings()
			if !strictPKI {
				// NM owns the last-successful-activation timestamp.
				require.GreaterOrEqual(t, profileAfter["connection"]["timestamp"].Value().(uint64), profileBefore["connection"]["timestamp"].Value().(uint64))
				profileBefore["connection"]["timestamp"] = profileAfter["connection"]["timestamp"]
			}
			require.Equal(t, profileBefore, profileAfter, "full profile and IP settings must survive")
			require.Equal(t, secretsBefore, persisted(), "all persistent secrets must survive without session secrets")
			backend.cachedOpenConnectMu.Lock()
			cached := backend.cachedOpenConnectAuth
			backend.cachedOpenConnectMu.Unlock()
			require.Nil(t, cached)
		})
	}
}

const privateFortinetOpenConnectPython = `#!/usr/bin/python3
import pathlib, sys
root = pathlib.Path(__file__).parent
mode = (root / 'mode').read_text()
assert mode in ('success', 'strict-pki')
expected = ['--protocol=fortinet', '--user=synthetic-user', '--passwd-on-stdin', '--non-inter']
if mode == 'strict-pki':
    expected += ['--cafile=' + str(root / 'synthetic-ca.pem')]
expected += ['--authenticate', 'invalid.example:443']
assert sys.argv[1:] == expected, 'refusing unexpected arguments'
payload = sys.stdin.read()
assert payload == 'DUMMY-FORTINET-PASSWORD\n', 'refusing unexpected stdin'
(root / 'args').write_text('\n'.join(sys.argv[1:]) + '\n')
(root / 'stdin').write_text(payload)
with (root / 'attempts').open('a') as attempts:
    attempts.write('attempt\n')
if mode == 'strict-pki':
    print('Add --servercert pin-sha256:DUMMY-SUGGESTED-PIN', file=sys.stderr)
    sys.exit(1)
print("COOKIE='DUMMY-FORTINET-COOKIE'")
print("HOST='192.0.2.1'")
print("CONNECT_URL='https://redirect.invalid.example/ignored'")
print("FINGERPRINT='pin-sha256:DUMMY-FORTINET-CERT'")
print("RESOLVE='invalid.example:192.0.2.1'")
`

const privateOpenConnectHelperPython = `#!/usr/bin/python3
import os, pathlib, signal, sys
root = pathlib.Path(__file__).parent
payload = sys.stdin.read()
count = root / 'count'
n = int(count.read_text()) + 1 if count.exists() else 1
(root / ('input-%d' % n)).write_text(payload)
(root / ('pid-%d' % n)).write_text(str(os.getpid()))
count.write_text(str(n))
assert payload.endswith('DONE\n\nQUIT\n\n')
assert 'DUMMY-OLD-GENERIC-PASSWORD' not in payload
assert 'DUMMY-UNKNOWN-SECRET' not in payload
assert '-i' in sys.argv
assert sys.argv[sys.argv.index('-s') + 1] == 'org.freedesktop.NetworkManager.openconnect'
mode = (root / 'mode').read_text()
if mode == 'block':
    (root / ('blocked-%d' % n)).touch()
    while True:
        signal.pause()
values = ['cookie', 'arbitrary synthetic cookie %d = !' % n, 'gateway', '192.0.2.1:443', 'gwcert', 'DUMMY-CERT-HASH', 'resolve', 'invalid.example:192.0.2.1', 'form:main:username', 'synthetic-user-%d' % n, 'xmlconfig', 'c3ludGhldGlj', 'lasthost', 'invalid.example', 'save_passwords', 'no', 'autoconnect', 'no']
if mode == 'cancel':
    values[1] = ''
if mode == 'malformed':
    sys.stdout.write('xmlconfig\nUNSAVED\ncookie\nunterminated')
else:
    sys.stdout.write('\n'.join(values) + '\n\n\n')
if mode == 'nonzero':
    sys.exit(7)
`
