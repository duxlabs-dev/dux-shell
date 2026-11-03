package systemd

import (
	"context"
	"math"
	"os"
	"testing"
	"testing/synctest"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/prop"
	"github.com/stretchr/testify/require"
	"golang.org/x/sys/unix"
)

type readinessSystemdManager struct {
	pid  uint32
	unit dbus.ObjectPath
}

func (m *readinessSystemdManager) GetUnitByPID(pid uint32) (dbus.ObjectPath, *dbus.Error) {
	if pid != m.pid {
		return "", dbus.NewError("org.freedesktop.systemd1.NoSuchUnit", nil)
	}
	return m.unit, nil
}

func readinessSystemdBus(t *testing.T, timeout time.Duration) *dbus.Conn {
	t.Helper()
	bus := shellReadyBus(t)
	reply, err := bus.RequestName("org.freedesktop.systemd1", dbus.NameFlagDoNotQueue)
	require.NoError(t, err)
	require.Equal(t, dbus.RequestNameReplyPrimaryOwner, reply)
	manager := &readinessSystemdManager{pid: uint32(os.Getpid()), unit: "/org/freedesktop/systemd1/unit/custom_2eservice"}
	require.NoError(t, bus.Export(manager, "/org/freedesktop/systemd1", "org.freedesktop.systemd1.Manager"))
	var now unix.Timespec
	require.NoError(t, unix.ClockGettime(unix.CLOCK_MONOTONIC, &now))
	_, err = prop.Export(bus, manager.unit, prop.Map{
		"org.freedesktop.systemd1.Service": {
			"TimeoutStartUSec":                {Value: uint64(timeout.Microseconds())},
			"ExecMainStartTimestampMonotonic": {Value: uint64(now.Nano() / 1000)},
		},
	})
	require.NoError(t, err)
	return bus
}

func TestReadinessUsesServiceStartupTimeout(t *testing.T) {
	readinessSystemdBus(t, 150*time.Millisecond)
	socket := notifySocket(t)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	NewReadiness().Wait(ctx)
	require.NoError(t, ctx.Err(), "must use the service timeout, not wait for parent cancellation")
	require.Equal(t, "READY=1\nSTATUS=Shell started with a readiness warning: shell readiness timed out: UI did not report readiness", readNotification(t, socket))
}

func TestRemainingStartupTimeout(t *testing.T) {
	for _, tc := range []struct {
		name      string
		timeoutUS uint64
		elapsedUS uint64
		want      time.Duration
	}{
		{"unit_timeout", 90_000_000, 0, 85 * time.Second},
		{"override", 180_000_000, 0, 175 * time.Second},
		{"elapsed_startup", 90_000_000, 30_000_000, 55 * time.Second},
		{"short_timeout", 2_000_000, 500_000, 1300 * time.Millisecond},
		{"expired", 90_000_000, 85_000_000, 0},
		{"past_deadline", 90_000_000, 100_000_000, 0},
		{"infinity", math.MaxUint64, 100_000_000, -1},
		{"disabled", 0, 100_000_000, -1},
		{"overflow", math.MaxUint64 - 1, 0, time.Duration(math.MaxInt64/int64(time.Microsecond)) * time.Microsecond},
	} {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, remainingStartupTimeout(tc.timeoutUS, tc.elapsedUS))
		})
	}
}

func TestReadinessUnlimitedTimeout(t *testing.T) {
	for _, uiReady := range []bool{false, true} {
		synctest.Test(t, func(t *testing.T) {
			r := NewReadiness()
			if uiReady {
				r.ShellReady(42)
			}
			ctx, cancel := context.WithCancel(context.Background())
			go func() {
				time.Sleep(2 * time.Minute)
				cancel()
			}()
			start := time.Now()
			err := r.wait(ctx, -1, func(context.Context, uint32) (bool, error) { return false, nil })
			require.NoError(t, err)
			require.Equal(t, 2*time.Minute, time.Since(start))
		})
	}
}
