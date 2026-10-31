package network

import (
	"context"
	"fmt"
	"maps"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestOpenConnectAgentFlagsPrivateNetworkManager(t *testing.T) {
	bus := connectPrivateNetworkManager(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	const service = "org.freedesktop.NetworkManager"
	const connInterface = service + ".Settings.Connection"
	for _, populated := range []bool{false, true} {
		t.Run(fmt.Sprintf("populated=%t", populated), func(t *testing.T) {
			vpnData := map[string]string{
				"gateway": "invalid.example", "protocol": "anyconnect", "cookie-flags": "2",
				"custom-sentinel": "keep-me", "password-flags": "0", "cert-pass-flags": "0",
			}
			dummySecrets := map[string]string{"password": "DUMMY-PASSWORD-NOT-REAL", "cert-pass": "DUMMY-CERT-NOT-REAL"}
			profile := map[string]map[string]dbus.Variant{
				"connection": {
					"id":   dbus.MakeVariant(fmt.Sprintf("dms-synthetic-%d", time.Now().UnixNano())),
					"type": dbus.MakeVariant("vpn"), "autoconnect": dbus.MakeVariant(false),
				},
				"vpn": {
					"service-type": dbus.MakeVariant(service + ".openconnect"),
					"user-name":    dbus.MakeVariant("synthetic-user"),
					"data":         dbus.MakeVariant(vpnData), "secrets": dbus.MakeVariant(dummySecrets),
				},
				"ipv4":  {"method": dbus.MakeVariant("auto"), "never-default": dbus.MakeVariant(true), "route-metric": dbus.MakeVariant(int64(321))},
				"proxy": {"method": dbus.MakeVariant(int32(0))},
			}
			if populated {
				ip := func(s string) []byte { return []byte(net.ParseIP(s).To16()) }
				profile["ipv6"] = map[string]dbus.Variant{
					"method":        dbus.MakeVariant("manual"),
					"addresses":     dbus.MakeVariant([]nmLegacyIPv6Address{{ip("2001:db8::2"), 64, ip("2001:db8::1")}}),
					"routes":        dbus.MakeVariant([]nmLegacyIPv6Route{{ip("2001:db8:1::"), 64, ip("2001:db8::1"), 37}}),
					"dns":           dbus.MakeVariant([][]byte{ip("2001:db8::53")}),
					"dns-search":    dbus.MakeVariant([]string{"synthetic.invalid"}),
					"never-default": dbus.MakeVariant(true),
				}
			}
			var path dbus.ObjectPath
			require.NoError(t, bus.Object(service, "/org/freedesktop/NetworkManager/Settings").CallWithContext(ctx, service+".Settings.AddConnection", 0, profile).Store(&path))
			obj := bus.Object(service, path)
			t.Cleanup(func() { assert.NoError(t, obj.Call(connInterface+".Delete", 0).Err) })
			get := func(method string, args ...any) map[string]map[string]dbus.Variant {
				var settings map[string]map[string]dbus.Variant
				require.NoError(t, obj.CallWithContext(ctx, connInterface+"."+method, 0, args...).Store(&settings))
				return settings
			}
			before := get("GetSettings")
			secretsBefore := get("GetSecrets", "vpn")
			require.Equal(t, dummySecrets, secretsBefore["vpn"]["secrets"].Value())
			for _, field := range []string{"addresses", "routes"} {
				value, ok := before["ipv6"][field]
				require.True(t, ok, "NM must expose legacy ipv6.%s", field)
				tuples, ok := value.Value().([][]any)
				require.True(t, ok, "must exercise actual decoded tuples, got %T", value.Value())
				if populated {
					require.Len(t, tuples, 1)
				} else {
					require.Empty(t, tuples)
				}
			}
			data := map[string]string{"stale": "discard"}
			updates := 0
			call := func(method string, result any, args ...any) error {
				if method == connInterface+".Update2" {
					updates++
					settings := args[0].(map[string]map[string]dbus.Variant)
					for _, section := range settings {
						require.NotContains(t, section, "secrets")
					}
					require.Equal(t, uint32(1), args[1])
				}
				return obj.CallWithContext(ctx, method, 0, args...).Store(result)
			}
			require.NoError(t, updateOpenConnectAgentFlags(data, call))
			expectedData := maps.Clone(before["vpn"]["data"].Value().(map[string]string))
			for _, field := range []string{"cookie", "gateway", "gwcert", "resolve"} {
				expectedData[field+"-flags"] = "2"
			}
			before["vpn"]["data"] = dbus.MakeVariant(expectedData)
			assert.Equal(t, before, get("GetSettings"), "full settings must survive except four flags")
			assert.Equal(t, expectedData, data)
			assert.Equal(t, secretsBefore, get("GetSecrets", "vpn"), "stored dummy secrets must survive secret-free Update2")
			require.NoError(t, updateOpenConnectAgentFlags(data, call))
			assert.Equal(t, 1, updates, "second call must not update")
			t.Log("real Go GetSettings/Update2: IPv6 tuples, full settings, flags, dummy secrets and idempotence preserved")
		})
	}
	t.Run("saved-password-real-agent", func(t *testing.T) {
		testStoredOpenConnectPasswordPrivateNetworkManager(t, ctx, bus)
	})
}

// The library constructor uses SystemBus; this adapter keeps every call on the
// explicitly supplied private bus, decoding GetSecrets like the library does.
type privateNMSecretConnection struct {
	gonetworkmanager.Connection
	obj dbus.BusObject
}

func (c *privateNMSecretConnection) GetPath() dbus.ObjectPath { return c.obj.Path() }

func (c *privateNMSecretConnection) GetSecrets(setting string) (gonetworkmanager.ConnectionSettings, error) {
	var raw map[string]map[string]dbus.Variant
	if err := c.obj.Call("org.freedesktop.NetworkManager.Settings.Connection.GetSecrets", 0, setting).Store(&raw); err != nil {
		return nil, err
	}
	out := gonetworkmanager.ConnectionSettings{}
	for setting, properties := range raw {
		out[setting] = map[string]any{}
		for key, value := range properties {
			out[setting][key] = value.Value()
		}
	}
	return out, nil
}

func testStoredOpenConnectPasswordPrivateNetworkManager(t *testing.T, ctx context.Context, bus *dbus.Conn) {
	const service = "org.freedesktop.NetworkManager"
	const connInterface = service + ".Settings.Connection"
	const dummyPassword = "DUMMY-PASSWORD-NOT-REAL"
	b := &NetworkManagerBackend{state: &BackendState{}, dbusConn: bus}
	broker := &fakePromptBroker{asked: make(chan PromptRequest, 1)}
	agent := &SecretAgent{conn: bus, objPath: agentObjectPath, id: "com.danklinux.SyntheticTestAgent", backend: b, prompts: broker}
	require.NoError(t, bus.Export(agent, agent.objPath, nmSecretAgentIface))
	require.NoError(t, bus.Export(agent, agent.objPath, "org.freedesktop.DBus.Introspectable"))
	t.Cleanup(agent.unexport)
	mgr := bus.Object(service, nmAgentManagerPath)
	require.NoError(t, mgr.CallWithContext(ctx, nmAgentManagerIface+".Register", 0, agent.id).Err)
	t.Cleanup(func() { assert.NoError(t, mgr.Call(nmAgentManagerIface+".Unregister", 0).Err) })

	data := map[string]string{
		"gateway": "invalid.example", "protocol": "fortinet", "authtype": "password",
		"username": "synthetic-user", "password-flags": "0",
		"cookie-flags": "2", "gateway-flags": "2", "gwcert-flags": "2", "resolve-flags": "2",
	}
	addProfile := func(name string, secrets map[string]string) (*privateNMSecretConnection, string) {
		profile := map[string]map[string]dbus.Variant{
			"connection": {"id": dbus.MakeVariant(name), "type": dbus.MakeVariant("vpn"), "autoconnect": dbus.MakeVariant(false)},
			"vpn":        {"service-type": dbus.MakeVariant(service + ".openconnect"), "data": dbus.MakeVariant(data), "secrets": dbus.MakeVariant(secrets)},
		}
		var path dbus.ObjectPath
		require.NoError(t, bus.Object(service, "/org/freedesktop/NetworkManager/Settings").CallWithContext(ctx, service+".Settings.AddConnection", 0, profile).Store(&path))
		obj := bus.Object(service, path)
		t.Cleanup(func() { assert.NoError(t, obj.Call(connInterface+".Delete", 0).Err) })
		var settings map[string]map[string]dbus.Variant
		require.NoError(t, obj.CallWithContext(ctx, connInterface+".GetSettings", 0).Store(&settings))
		return &privateNMSecretConnection{obj: obj}, settings["connection"]["uuid"].Value().(string)
	}
	conn, uuid := addProfile("dms-synthetic-saved-password", map[string]string{"password": dummyPassword})
	_, err := conn.GetSecrets("vpn")
	require.Error(t, err, "the real unmarked Go agent must reproduce the stored-password lookup failure")
	t.Logf("unmarked lookup reproduced failure: %v", err)
	stored, err := b.readStoredOpenConnectSecrets(conn, uuid, service+".openconnect", data)
	require.NoError(t, err)
	require.Equal(t, map[string]string{"password": dummyPassword}, stored["vpn"]["secrets"])
	assert.False(t, b.isReadingOpenConnectSecrets(uuid, conn.GetPath()))
	_, err = conn.GetSecrets("vpn")
	require.Error(t, err, "completed read must not change subsequent external lookups")

	binDir := t.TempDir()
	script := `#!/bin/sh
IFS= read -r password
[ "$password" = "DUMMY-PASSWORD-NOT-REAL" ] || exit 10
user_seen=no
for arg in "$@"; do
  case "$arg" in
    --user=synthetic-user) user_seen=yes ;;
    *DUMMY-PASSWORD*) exit 11 ;;
  esac
done
[ "$user_seen" = yes ] || exit 12
printf '%s\n' "COOKIE='DUMMY-COOKIE'" "HOST='invalid.example'"
`
	require.NoError(t, os.WriteFile(filepath.Join(binDir, "openconnect"), []byte(script), 0o755))
	t.Setenv("PATH", binDir)
	require.Nil(t, b.promptBroker, "handler has no prompt broker to fall back to")
	result, err := b.handleOpenConnectPasswordAuth(ctx, conn, "synthetic saved password", uuid, service+".openconnect", data)
	require.NoError(t, err)
	require.Equal(t, "DUMMY-COOKIE", result.Cookie)
	assert.Empty(t, broker.asked, "agent must not prompt")
	assert.False(t, b.state.IsConnectingVPN, "must read before activation state is set")
	assert.False(t, b.isReadingOpenConnectSecrets(uuid, conn.GetPath()))
	assert.Nil(t, b.pendingVPNSave)
	assert.Nil(t, b.cachedVPNCreds)
	assert.Nil(t, b.cachedOpenConnectAuth)

	missing := &privateNMSecretConnection{obj: bus.Object(service, "/org/freedesktop/NetworkManager/Settings/missing")}
	_, err = b.readStoredOpenConnectSecrets(missing, uuid, service+".openconnect", data)
	require.Error(t, err)
	assert.False(t, b.isReadingOpenConnectSecrets(uuid, missing.GetPath()), "D-Bus error must clear marker")

	firstTime, firstUUID := addProfile("dms-synthetic-first-time", map[string]string{})
	b.promptBroker = &fakePromptBroker{asked: make(chan PromptRequest, 1), reply: PromptReply{Secrets: map[string]string{"password": dummyPassword}}}
	result, err = b.handleOpenConnectPasswordAuth(ctx, firstTime, "synthetic first time", firstUUID, service+".openconnect", data)
	require.NoError(t, err)
	require.Equal(t, "DUMMY-COOKIE", result.Cookie)
	prompt := <-b.promptBroker.(*fakePromptBroker).asked
	assert.Equal(t, []string{"password"}, prompt.Fields)
	assert.Empty(t, broker.asked, "only the handler should prompt for first-time credentials")
	assert.False(t, b.isReadingOpenConnectSecrets(firstUUID, firstTime.GetPath()))
	t.Log("real registered Go agent: unmarked failure, scoped system password read, prompt-free reconnect, D-Bus error cleanup and first-time prompt verified; no VPN activation")
}
