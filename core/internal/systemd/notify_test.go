package systemd

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"testing/synctest"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/prop"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/sys/unix"
)

func shellReadyBus(t *testing.T) *dbus.Conn {
	t.Helper()
	if _, err := exec.LookPath("dbus-daemon"); err != nil {
		t.Skip("requires dbus-daemon for an isolated session bus")
	}
	cmd := exec.Command("dbus-daemon", "--session", "--nofork", "--nopidfile", "--print-address=1")
	stdout, err := cmd.StdoutPipe()
	require.NoError(t, err)
	require.NoError(t, cmd.Start())
	t.Cleanup(func() {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
	})
	scanner := bufio.NewScanner(stdout)
	require.True(t, scanner.Scan(), "session bus did not provide an address")
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", scanner.Text())
	conn, err := dbus.ConnectSessionBus()
	require.NoError(t, err)
	t.Cleanup(func() { conn.Close() })
	return conn
}

func shellReadyTray(t *testing.T, bus *dbus.Conn) *prop.Properties {
	t.Helper()
	for _, name := range []string{"org.kde.StatusNotifierWatcher", fmt.Sprintf("org.kde.StatusNotifierHost-%d-test", os.Getpid())} {
		reply, err := bus.RequestName(name, dbus.NameFlagDoNotQueue)
		require.NoError(t, err)
		require.Equal(t, dbus.RequestNameReplyPrimaryOwner, reply)
	}
	properties, err := prop.Export(bus, "/StatusNotifierWatcher", prop.Map{
		"org.kde.StatusNotifierWatcher": {
			"IsStatusNotifierHostRegistered": {Value: true},
		},
	})
	require.NoError(t, err)
	return properties
}

func TestShellServicesWaitForNotificationsAndTray(t *testing.T) {
	bus := shellReadyBus(t)
	check := func(want bool) {
		t.Helper()
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		ready, _, err := shellServicesReady(ctx, bus, uint32(os.Getpid()))
		require.NoError(t, err)
		require.Equal(t, want, ready)
	}
	check(false)
	properties := shellReadyTray(t, bus)
	check(false)
	_, err := bus.RequestName("org.freedesktop.Notifications", dbus.NameFlagDoNotQueue)
	require.NoError(t, err)
	check(true)
	host := fmt.Sprintf("org.kde.StatusNotifierHost-%d-test", os.Getpid())
	_, err = bus.ReleaseName(host)
	require.NoError(t, err)
	check(false)
	_, err = bus.RequestName(host, dbus.NameFlagDoNotQueue)
	require.NoError(t, err)
	_, err = bus.ReleaseName("org.kde.StatusNotifierWatcher")
	require.NoError(t, err)
	check(false)
	_, err = bus.RequestName("org.kde.StatusNotifierWatcher", dbus.NameFlagDoNotQueue)
	require.NoError(t, err)
	properties.SetMust("org.kde.StatusNotifierWatcher", "IsStatusNotifierHostRegistered", false)
	check(false)
	properties.SetMust("org.kde.StatusNotifierWatcher", "IsStatusNotifierHostRegistered", true)
	check(true)
}

func TestReadinessExternalNotifications(t *testing.T) {
	bus := shellReadyBus(t)
	shellReadyTray(t, bus)
	pid := shellReadyForeignOwner(t, "org.freedesktop.Notifications")
	socket := notifySocket(t)
	readiness := NewReadiness()
	readiness.ShellReady(uint32(os.Getpid()))
	readiness.Wait(context.Background())
	assert.Equal(t, fmt.Sprintf("READY=1\nSTATUS=Ready; notifications handled by external process (PID %d)", pid), readNotification(t, socket))
}

func TestReadinessForeignOwner(t *testing.T) {
	if name := os.Getenv("DMS_TEST_TRAY_HOST"); name != "" {
		bus, err := dbus.ConnectSessionBus()
		require.NoError(t, err)
		defer bus.Close()
		reply, err := bus.RequestName(name, dbus.NameFlagDoNotQueue)
		require.NoError(t, err)
		require.Equal(t, dbus.RequestNameReplyPrimaryOwner, reply)
		fmt.Println("host claimed")
		_, _ = io.Copy(io.Discard, os.Stdin)
		return
	}
	bus := readinessSystemdBus(t, 500*time.Millisecond)
	shellReadyTray(t, bus)
	_, err := bus.RequestName("org.freedesktop.Notifications", dbus.NameFlagDoNotQueue)
	require.NoError(t, err)
	host := fmt.Sprintf("org.kde.StatusNotifierHost-%d-test", os.Getpid())
	_, err = bus.ReleaseName(host)
	require.NoError(t, err)
	ownerPID := shellReadyForeignOwner(t, host)
	socket := notifySocket(t)
	readiness := NewReadiness()
	readiness.ShellReady(uint32(os.Getpid()))
	readiness.Wait(context.Background())
	assert.Equal(t, fmt.Sprintf("READY=1\nSTATUS=Shell started with a readiness warning: shell readiness timed out: %s is already owned by another process (PID %d)", host, ownerPID), readNotification(t, socket))
}

func TestReadinessCancellationDoesNotNotify(t *testing.T) {
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent")
	for _, uiReady := range []bool{false, true} {
		t.Run(fmt.Sprintf("ui_ready=%t", uiReady), func(t *testing.T) {
			socket := notifySocket(t)
			synctest.Test(t, func(t *testing.T) {
				r := NewReadiness()
				if uiReady {
					r.ShellReady(uint32(os.Getpid()))
				}
				ctx, cancel := context.WithCancel(context.Background())
				go func() {
					time.Sleep(time.Second)
					cancel()
				}()
				r.Wait(ctx)
			})
			raw, err := socket.SyscallConn()
			require.NoError(t, err)
			require.NoError(t, raw.Control(func(fd uintptr) {
				var buf [1024]byte
				_, _, err := unix.Recvfrom(int(fd), buf[:], unix.MSG_DONTWAIT)
				require.ErrorIs(t, err, unix.EAGAIN, "must not send READY or STATUS while stopping")
			}))
		})
	}
}

func TestReadinessTimeoutReportsPendingService(t *testing.T) {
	for _, tc := range []struct {
		stage  string
		reason string
	}{
		{"notifications", "notification service has no D-Bus owner"},
		{"watcher", "tray watcher has no D-Bus owner"},
		{"host", "shell tray host is not registered on D-Bus"},
		{"registration", "tray watcher did not report a registered host"},
	} {
		t.Run(tc.stage, func(t *testing.T) {
			bus := readinessSystemdBus(t, 150*time.Millisecond)
			if tc.stage != "notifications" {
				_, err := bus.RequestName("org.freedesktop.Notifications", dbus.NameFlagDoNotQueue)
				require.NoError(t, err)
			}
			if tc.stage == "host" || tc.stage == "registration" {
				props := shellReadyTray(t, bus)
				if tc.stage == "host" {
					_, err := bus.ReleaseName(fmt.Sprintf("org.kde.StatusNotifierHost-%d-test", os.Getpid()))
					require.NoError(t, err)
				} else {
					props.SetMust("org.kde.StatusNotifierWatcher", "IsStatusNotifierHostRegistered", false)
				}
			}
			socket := notifySocket(t)
			r := NewReadiness()
			r.ShellReady(uint32(os.Getpid()))
			r.Wait(context.Background())
			require.Equal(t, "READY=1\nSTATUS=Shell started with a readiness warning: shell readiness timed out: "+tc.reason, readNotification(t, socket))
			require.Eventually(t, func() bool {
				var names []string
				if err := bus.BusObject().Call("org.freedesktop.DBus.ListNames", 0).Store(&names); err != nil {
					return false
				}
				for _, name := range names {
					if strings.HasPrefix(name, ":") && name != bus.Names()[0] {
						return false
					}
				}
				return true
			}, time.Second, time.Millisecond, "readiness must close both startup and service-check connections")
		})
	}
}

func TestReadinessWithoutSystemd(t *testing.T) {
	t.Setenv("NOTIFY_SOCKET", "")
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent")
	NewReadiness().Wait(context.Background())
}

func TestReadinessReportsTimeoutWithoutUI(t *testing.T) {
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent")
	socket := notifySocket(t)
	synctest.Test(t, func(t *testing.T) {
		NewReadiness().Wait(context.Background())
	})
	assert.Equal(t, "READY=1\nSTATUS=Shell started with a readiness warning: shell readiness timed out: UI did not report readiness", readNotification(t, socket))
}

func TestReadinessLogsNotificationFailure(t *testing.T) {
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent")
	var output bytes.Buffer
	logger := log.GetLogger()
	level := logger.GetLevel()
	logger.SetOutput(&output)
	log.SetLevel("warn")
	t.Cleanup(func() {
		logger.SetOutput(os.Stderr)
		logger.SetLevel(level)
	})
	for _, tc := range []struct {
		name string
		path string
		want string
	}{
		{"invalid_address", "invalid", "invalid NOTIFY_SOCKET address"},
		{"delivery_failure", filepath.Join(t.TempDir(), "missing"), "shell readiness timed out: UI did not report readiness"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			output.Reset()
			t.Setenv("NOTIFY_SOCKET", tc.path)
			synctest.Test(t, func(t *testing.T) {
				NewReadiness().Wait(context.Background())
			})
			message := output.String()
			require.Equal(t, 1, strings.Count(message, "Could not report shell readiness:"))
			require.Contains(t, message, tc.want)
			if tc.name == "delivery_failure" {
				require.Contains(t, message, "no such file or directory")
				require.NotContains(t, message, "Shell started with a readiness warning:")
			}
		})
	}
}

type readinessWatcher struct {
	mu      sync.Mutex
	senders []dbus.Sender
}

func (w *readinessWatcher) Get(_, _ string, sender dbus.Sender) (dbus.Variant, *dbus.Error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.senders = append(w.senders, sender)
	return dbus.MakeVariant(len(w.senders) >= 3), nil
}

func TestReadinessReusesBusConnectionWhileWaitingForTray(t *testing.T) {
	bus := shellReadyBus(t)
	shellReadyTray(t, bus)
	_, err := bus.RequestName("org.freedesktop.Notifications", dbus.NameFlagDoNotQueue)
	require.NoError(t, err)
	watcher := &readinessWatcher{}
	require.NoError(t, bus.Export(watcher, "/StatusNotifierWatcher", "org.freedesktop.DBus.Properties"))
	socket := notifySocket(t)
	r := NewReadiness()
	r.ShellReady(uint32(os.Getpid()))
	r.Wait(context.Background())
	require.Equal(t, "READY=1", readNotification(t, socket))
	watcher.mu.Lock()
	defer watcher.mu.Unlock()
	require.Len(t, watcher.senders, 3)
	require.Equal(t, watcher.senders[0], watcher.senders[1])
	require.Equal(t, watcher.senders[0], watcher.senders[2])
	require.Eventually(t, func() bool {
		var owned bool
		err := bus.BusObject().Call("org.freedesktop.DBus.NameHasOwner", 0, string(watcher.senders[0])).Store(&owned)
		return err == nil && !owned
	}, time.Second, time.Millisecond, "readiness must close its bus connection after success")
}

func notifySocket(t *testing.T) *net.UnixConn {
	t.Helper()
	path := filepath.Join(t.TempDir(), "notify")
	socket, err := net.ListenUnixgram("unixgram", &net.UnixAddr{Name: path, Net: "unixgram"})
	require.NoError(t, err)
	t.Cleanup(func() { socket.Close() })
	t.Setenv("NOTIFY_SOCKET", path)
	return socket
}

func readNotification(t *testing.T, socket *net.UnixConn) string {
	t.Helper()
	require.NoError(t, socket.SetReadDeadline(time.Now().Add(time.Second)))
	var message [1024]byte
	n, _, err := socket.ReadFromUnix(message[:])
	require.NoError(t, err)
	return string(message[:n])
}

func shellReadyForeignOwner(t *testing.T, name string) int {
	t.Helper()
	cmd := exec.Command(os.Args[0], "-test.run=^TestReadinessForeignOwner$")
	cmd.Env = append(os.Environ(), "DMS_TEST_TRAY_HOST="+name)
	stdin, err := cmd.StdinPipe()
	require.NoError(t, err)
	stdout, err := cmd.StdoutPipe()
	require.NoError(t, err)
	require.NoError(t, cmd.Start())
	t.Cleanup(func() {
		_ = stdin.Close()
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
	})
	scanner := bufio.NewScanner(stdout)
	require.True(t, scanner.Scan())
	require.Equal(t, "host claimed", scanner.Text())

	return cmd.Process.Pid
}
