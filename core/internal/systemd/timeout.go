package systemd

import (
	"context"
	"fmt"
	"math"
	"os"
	"time"

	"github.com/godbus/dbus/v5"
	"golang.org/x/sys/unix"
)

func startupTimeout(parent context.Context) (time.Duration, error) {
	ctx, cancel := context.WithTimeout(parent, time.Second)
	defer cancel()
	conn, err := dbus.ConnectSessionBus(dbus.WithContext(ctx))
	if err != nil {
		return 0, err
	}
	defer conn.Close()

	var unit dbus.ObjectPath
	err = conn.Object("org.freedesktop.systemd1", "/org/freedesktop/systemd1").CallWithContext(ctx,
		"org.freedesktop.systemd1.Manager.GetUnitByPID", dbus.FlagNoAutoStart, uint32(os.Getpid())).Store(&unit)
	if err != nil {
		return 0, fmt.Errorf("get own systemd unit: %w", err)
	}
	obj := conn.Object("org.freedesktop.systemd1", unit)
	var timeout, started dbus.Variant
	err = obj.CallWithContext(ctx, "org.freedesktop.DBus.Properties.Get", dbus.FlagNoAutoStart,
		"org.freedesktop.systemd1.Service", "TimeoutStartUSec").Store(&timeout)
	if err != nil {
		return 0, fmt.Errorf("get TimeoutStartUSec: %w", err)
	}
	var timeoutUS uint64
	if err := timeout.Store(&timeoutUS); err != nil {
		return 0, err
	}
	if timeoutUS == math.MaxUint64 || timeoutUS == 0 {
		return -1, nil
	}
	err = obj.CallWithContext(ctx, "org.freedesktop.DBus.Properties.Get", dbus.FlagNoAutoStart,
		"org.freedesktop.systemd1.Service", "ExecMainStartTimestampMonotonic").Store(&started)
	if err != nil {
		return 0, fmt.Errorf("get unit startup timestamp: %w", err)
	}
	var startedUS uint64
	if err := started.Store(&startedUS); err != nil {
		return 0, err
	}
	var now unix.Timespec
	if err := unix.ClockGettime(unix.CLOCK_MONOTONIC, &now); err != nil {
		return 0, err
	}
	nowUS := uint64(now.Nano() / 1000)
	if startedUS == 0 || startedUS > nowUS {
		return 0, fmt.Errorf("invalid unit startup timestamp: %d", startedUS)
	}
	return remainingStartupTimeout(timeoutUS, nowUS-startedUS), nil
}

func remainingStartupTimeout(timeoutUS, elapsedUS uint64) time.Duration {
	if timeoutUS == math.MaxUint64 || timeoutUS == 0 {
		return -1
	}
	// Leave time to report startup status before systemd expires its deadline.
	budgetUS := timeoutUS - min(timeoutUS/10, uint64((5*time.Second).Microseconds()))
	if elapsedUS >= budgetUS {
		return 0
	}
	return time.Duration(min(budgetUS-elapsedUS, uint64(math.MaxInt64/int64(time.Microsecond)))) * time.Microsecond
}
