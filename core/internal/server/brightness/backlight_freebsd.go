package brightness

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"unsafe"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"golang.org/x/sys/unix"
)

// sys/sys/backlight.h: brightness is a 0-100 percent;
// BACKLIGHTGETSTATUS/BACKLIGHTUPDATESTATUS = _IOWR('G', 0/1, struct
// backlight_props{uint32 brightness; uint32 nlevels; uint32 levels[100]}).
const (
	backlightDevDir       = "/dev/backlight"
	backlightGetStatus    = 0xc1984700
	backlightUpdateStatus = 0xc1984701
)

type backlightProps struct {
	brightness uint32
	nlevels    uint32
	levels     [100]uint32
}

type BacklightBackend struct {
	devices syncmap.Map[string, string]
}

func NewBacklightBackend() (*BacklightBackend, error) {
	b := &BacklightBackend{}
	if err := b.scanDevices(); err != nil {
		return nil, err
	}
	return b, nil
}

func isGenericBacklightName(name string) bool {
	rest, ok := strings.CutPrefix(name, "backlight")
	if !ok || rest == "" {
		return false
	}
	for _, r := range rest {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func (b *BacklightBackend) scanDevices() error {
	entries, err := os.ReadDir(backlightDevDir)
	if err != nil {
		return fmt.Errorf("read %s: %w", backlightDevDir, err)
	}

	// backlight_register (sys/dev/backlight/backlight.c) publishes each unit
	// as backlight/backlightN plus a driver-named alias for the same cdev;
	// dedupe on the device number and keep the descriptive alias.
	names := make(map[uint64]string)
	for _, entry := range entries {
		var st unix.Stat_t
		if err := unix.Stat(filepath.Join(backlightDevDir, entry.Name()), &st); err != nil {
			continue
		}
		rdev := uint64(st.Rdev)
		current, exists := names[rdev]
		if exists && !isGenericBacklightName(current) {
			continue
		}
		names[rdev] = entry.Name()
	}

	for _, name := range names {
		b.devices.Store("backlight:"+name, filepath.Join(backlightDevDir, name))
	}
	return nil
}

func backlightIoctl(fd int, req uint, props *backlightProps) error {
	_, _, errno := unix.Syscall(unix.SYS_IOCTL, uintptr(fd), uintptr(req), uintptr(unsafe.Pointer(props)))
	if errno != 0 {
		return errno
	}
	return nil
}

func readBrightness(path string) (int, error) {
	fd, err := unix.Open(path, unix.O_RDWR, 0)
	if err != nil {
		return 0, err
	}
	defer unix.Close(fd)

	var props backlightProps
	if err := backlightIoctl(fd, backlightGetStatus, &props); err != nil {
		return 0, err
	}
	return int(props.brightness), nil
}

func (b *BacklightBackend) Rescan() error {
	return b.scanDevices()
}

func (b *BacklightBackend) GetDevices() ([]Device, error) {
	devices := make([]Device, 0)

	b.devices.Range(func(id, path string) bool {
		brightness, err := readBrightness(path)
		if err != nil {
			log.Debugf("failed to read brightness for %s: %v", id, err)
			return true
		}

		devices = append(devices, Device{
			Class:          ClassBacklight,
			ID:             id,
			Name:           strings.TrimPrefix(id, "backlight:"),
			Current:        brightness,
			Max:            100,
			CurrentPercent: brightness,
			Backend:        "backlight",
		})
		return true
	})

	return devices, nil
}

func (b *BacklightBackend) SetBrightnessWithExponent(id string, percent int, exponential bool, exponent float64) error {
	if percent < 0 || percent > 100 {
		return fmt.Errorf("percent out of range: %d", percent)
	}

	path, ok := b.devices.Load(id)
	if !ok {
		return fmt.Errorf("device not found: %s", id)
	}

	value := percent
	switch {
	case percent == 0:
		value = 1
	case exponential:
		value = 1 + int(math.Round(math.Pow(float64(percent-1)/99.0, exponent)*99.0))
	}

	fd, err := unix.Open(path, unix.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("open %s: %w", path, err)
	}
	defer unix.Close(fd)

	props := backlightProps{brightness: uint32(value)}
	if err := backlightIoctl(fd, backlightUpdateStatus, &props); err != nil {
		return fmt.Errorf("set brightness: %w", err)
	}

	log.Debugf("set %s to %d%% (hw %d) via backlight(4)", id, percent, value)
	return nil
}
