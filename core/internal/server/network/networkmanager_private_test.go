package network

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/require"
)

// Refuse before constructing anything that might use the library's SystemBus.
func requireOpenConnectPrivateBus(t *testing.T) string {
	t.Helper()
	address := os.Getenv("DMS_TEST_NM_PRIVATE_BUS")
	if address == "" {
		t.Skip("run testdata/run-private-networkmanager.sh for isolated NetworkManager")
	}
	require.Equal(t, "unix:path=/run/test-system-bus", address)
	require.Equal(t, address, os.Getenv("DBUS_SYSTEM_BUS_ADDRESS"))
	require.Equal(t, address, os.Getenv("DBUS_SESSION_BUS_ADDRESS"))
	raw, err := os.ReadFile("/proc/self/uid_map")
	require.NoError(t, err)
	var inside, outside, count uint64
	_, err = fmt.Sscanf(string(raw), "%d %d %d", &inside, &outside, &count)
	require.NoError(t, err)
	require.Zero(t, inside)
	require.NotZero(t, outside)
	require.Equal(t, uint64(1), count)
	for _, kind := range []string{"net", "mnt"} {
		host := os.Getenv("DMS_TEST_HOST_" + strings.ToUpper(kind) + "_NS")
		require.NotEmpty(t, host)
		current, err := os.Readlink("/proc/self/ns/" + kind)
		require.NoError(t, err)
		require.NotEqual(t, host, current)
	}
	mounts, err := os.ReadFile("/proc/self/mountinfo")
	require.NoError(t, err)
	for _, path := range []string{"/run", "/etc/NetworkManager", "/var/lib/NetworkManager", "/usr/lib/NetworkManager/VPN", "/usr/lib64/NetworkManager/VPN", "/usr/local/lib/NetworkManager/VPN", "/etc/NetworkManager/VPN"} {
		canonical, err := filepath.EvalSymlinks(path)
		require.NoError(t, err)
		found := false
		for _, line := range strings.Split(string(mounts), "\n") {
			fields := strings.Fields(line)
			if len(fields) > 6 && (fields[4] == canonical || strings.HasPrefix(canonical, fields[4]+"/")) && strings.Contains(line, " - tmpfs ") {
				found = true
			}
		}
		require.True(t, found, "requires private tmpfs at %s", path)
	}
	return address
}

func connectPrivateNetworkManager(t *testing.T) *dbus.Conn {
	t.Helper()
	bus, err := dbus.Connect(requireOpenConnectPrivateBus(t))
	require.NoError(t, err)
	t.Cleanup(func() { bus.Close() })
	nm := bus.Object(dbusNMInterface, dbus.ObjectPath(dbusNMPath))
	privateEventually(t, "private NetworkManager ready", func() bool {
		v, err := nm.GetProperty(dbusNMInterface + ".Version")
		if err != nil {
			return false
		}
		version, ok := v.Value().(string)
		require.True(t, ok && version != "", "invalid NetworkManager version %v", v.Value())
		t.Logf("isolated NetworkManager version %s", version)
		return true
	})
	var activatable []string
	require.NoError(t, bus.BusObject().Call("org.freedesktop.DBus.ListActivatableNames", 0).Store(&activatable))
	require.Equal(t, []string{"org.freedesktop.DBus"}, activatable, "private bus must not activate any services")
	return bus
}

func privateCommand(t *testing.T, name string, args ...string) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	require.NoError(t, err, "%s %v: %s", name, args, out)
	return string(out)
}

func privateEventually(t *testing.T, what string, ready func() bool) {
	t.Helper()
	require.Eventually(t, ready, 15*time.Second, 20*time.Millisecond, what)
}
