package drives

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/dbusutil"
	"github.com/godbus/dbus/v5"
)

const (
	udisksDest  = "org.freedesktop.UDisks2"
	udisksPath  = "/org/freedesktop/UDisks2"
	callTimeout = 2 * time.Second
)

var standby = struct {
	sync.Mutex
	cache map[string]ATASmart
}{cache: map[string]ATASmart{}}

// List reads drives from UDisks2. It never calls SmartUpdate, and it asks rotating
// ATA drives for their power state before reading attributes so a sleeping disk stays asleep.
func List() (ListResult, error) {
	conn, err := dbus.SystemBus()
	if err != nil {
		return ListResult{}, fmt.Errorf("system bus: %w", err)
	}
	drives, err := listDrives(conn)
	if err != nil {
		return ListResult{}, err
	}
	return ListResult{Drives: drives, Smartctl: smartctlPath(), InstallCommand: installCommand()}, nil
}

func listDrives(conn *dbus.Conn) ([]Drive, error) {
	var objects objectMap
	if err := call(conn, udisksPath, "org.freedesktop.DBus.ObjectManager.GetManagedObjects", &objects); err != nil {
		if udisksAbsent(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("udisks2: %w", err)
	}

	nvmeAttrs := map[dbus.ObjectPath]map[string]dbus.Variant{}
	ataAttrs := map[dbus.ObjectPath][]ataAttribute{}
	asleep := map[dbus.ObjectPath]bool{}
	baseOptions := map[string]dbus.Variant{"auth.no_user_interaction": dbus.MakeVariant(true)}
	ataAttrOptions := map[string]dbus.Variant{"auth.no_user_interaction": dbus.MakeVariant(true), "nowakeup": dbus.MakeVariant(true)}
	for p, ifaces := range objects {
		if _, ok := ifaces[ifaceDrive]; !ok {
			continue
		}
		if _, ok := ifaces[ifaceNVMe]; ok {
			var attrs map[string]dbus.Variant
			if call(conn, p, ifaceNVMe+".SmartGetAttributes", &attrs, baseOptions) == nil {
				nvmeAttrs[p] = attrs
			}
			continue
		}
		ata, ok := ifaces[ifaceATA]
		if !ok || !dbusutil.GetOr(ata, "SmartSupported", false) || !dbusutil.GetOr(ata, "SmartEnabled", false) {
			continue
		}
		if dbusutil.GetOr(ifaces[ifaceDrive], "RotationRate", int32(0)) != 0 {
			var state byte
			if call(conn, p, ifaceATA+".PmGetState", &state, baseOptions) != nil {
				continue
			}
			// CHECK POWER MODE: 0x00 Standby_z, 0x01 Standby_y; both mean spun down.
			if state <= 0x01 {
				asleep[p] = true
				continue
			}
		}
		var attrs []ataAttribute
		if call(conn, p, ifaceATA+".SmartGetAttributes", &attrs, ataAttrOptions) == nil {
			ataAttrs[p] = attrs
		}
	}

	standby.Lock()
	defer standby.Unlock()
	return buildDrives(objects, nvmeAttrs, ataAttrs, asleep, standby.cache), nil
}

// udisksAbsent is true when udisksd isn't running; calls never start it.
func udisksAbsent(err error) bool {
	var busErr dbus.Error
	return errors.As(err, &busErr) && (busErr.Name == "org.freedesktop.DBus.Error.ServiceUnknown" ||
		busErr.Name == "org.freedesktop.DBus.Error.NameHasNoOwner")
}

func call(conn *dbus.Conn, p dbus.ObjectPath, method string, out any, args ...any) error {
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	return conn.Object(udisksDest, p).CallWithContext(ctx, method, dbus.FlagNoAutoStart, args...).Store(out)
}
