package brightness

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

func isIgnorableI2CBus(busno int) bool {
	name := getI2CDeviceSysfsName(busno)
	if name == "DPMST" {
		return false
	}
	driver := getI2CSysfsDriver(busno)

	if name != "" && isIgnorableI2CDeviceName(name, driver) {
		log.Debugf("i2c-%d: ignoring '%s' (driver: %s)", busno, name, driver)
		return true
	}

	// Only probe display adapters (0x03xxxx) and docking stations (0x0axxxx)
	class := getI2CDeviceSysfsClass(busno)
	if class == 0 {
		// No PCI class says nothing about a platform adapter, but a real adapter always has a name.
		return name == ""
	}

	classHigh := class & 0xFFFF0000
	ignorable := (classHigh != 0x030000 && classHigh != 0x0A0000)
	if ignorable {
		log.Debugf("i2c-%d: ignoring class 0x%08x", busno, class)
	}
	return ignorable
}

func isIgnorableI2CDeviceName(name, driver string) bool {
	ignorablePrefixes := []string{
		"SMBus",
		"Synopsys DesignWare",
		"soc:i2cdsi",
		"smu",
		"mac-io",
		"u4",
		"AMDGPU SMU",            // AMD Navi2+ - probing hangs GPU
		"AMDGPU DM i2c OEM bus", // RGB controllers, not displays
	}

	for _, prefix := range ignorablePrefixes {
		if strings.HasPrefix(name, prefix) {
			return true
		}
	}

	// nouveau driver: only nvkm-* buses are valid
	if driver == "nouveau" && !strings.HasPrefix(name, "nvkm-") {
		return true
	}

	return false
}

func getI2CDeviceSysfsName(busno int) string {
	path := fmt.Sprintf("/sys/bus/i2c/devices/i2c-%d/name", busno)
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func getI2CDeviceSysfsClass(busno int) uint32 {
	paths := []string{
		fmt.Sprintf("/sys/bus/i2c/devices/i2c-%d", busno),
		fmt.Sprintf("/sys/bus/i2c/devices/i2c-%d/device", busno),
		fmt.Sprintf("/sys/bus/i2c/devices/i2c-%d/i2c-dev/i2c-%d/device", busno, busno),
	}
	for _, path := range paths {
		adapter := findI2CAdapter(path)
		if adapter == "" {
			continue
		}
		data, err := os.ReadFile(filepath.Join(adapter, "class"))
		if err != nil {
			continue
		}
		class, err := strconv.ParseUint(strings.TrimPrefix(strings.TrimSpace(string(data)), "0x"), 16, 32)
		if err == nil && class != 0 {
			return uint32(class)
		}
	}
	return 0
}

func getI2CSysfsDriver(busno int) string {
	adapter := findI2CAdapter(fmt.Sprintf("/sys/bus/i2c/devices/i2c-%d", busno))
	if adapter == "" {
		return ""
	}
	module, err := filepath.EvalSymlinks(filepath.Join(adapter, "driver", "module"))
	if err != nil {
		return ""
	}
	return filepath.Base(module)
}

// The nearest ancestor under /sys/devices carrying a class attribute.
func findI2CAdapter(path string) string {
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return ""
	}
	for strings.HasPrefix(resolved, "/sys/devices") {
		if info, err := os.Stat(filepath.Join(resolved, "class")); err == nil && info.Mode().IsRegular() {
			return resolved
		}
		resolved = filepath.Dir(resolved)
	}
	return ""
}

// Drivers that keep the DRM connector edid, status and dpms attributes current; nvidia does not.
var sysfsReliableDrivers = []string{"i915", "xe", "amdgpu", "radeon", "nouveau"}

var (
	drmConnectorPattern = regexp.MustCompile(`^card[0-9]+-`)
	i2cBusPattern       = regexp.MustCompile(`^i2c-([0-9]+)$`)
)

type ddcBusVerdict int

const (
	ddcBusSkip ddcBusVerdict = iota
	ddcBusHasEDID
	ddcBusNeedsEDIDRead
)

func ddcBusVerdictFor(busno int, connectors map[int]string) ddcBusVerdict {
	name := getI2CDeviceSysfsName(busno)
	displayLink := name == "DisplayLink I2C Adapter"
	reliable := slices.Contains(sysfsReliableDrivers, getI2CSysfsDriver(busno))

	connector, mapped := connectors[busno]
	if !mapped {
		if reliable && !displayLink && name != "DPMST" && len(connectors) > 0 {
			return ddcBusSkip
		}
		return ddcBusNeedsEDIDRead
	}
	if strings.Contains(connector, "-eDP-") || strings.Contains(connector, "-LVDS-") {
		return ddcBusSkip
	}
	if reliable || displayLink {
		if len(drmConnectorAttr(connector, "edid")) >= 128 {
			return ddcBusHasEDID
		}
		return ddcBusSkip
	}
	if strings.TrimSpace(drmConnectorAttr(connector, "status")) == "disconnected" {
		return ddcBusSkip
	}
	return ddcBusNeedsEDIDRead
}

func ddcDisplayAsleep(busno int, connectors map[int]string) bool {
	connector, mapped := connectors[busno]
	if !mapped || !slices.Contains(sysfsReliableDrivers, getI2CSysfsDriver(busno)) {
		return false
	}
	return strings.TrimSpace(drmConnectorAttr(connector, "dpms")) != "On"
}

func drmConnectorsByBus() map[int]string {
	return drmConnectorsByBusIn("/sys/class/drm")
}

func drmConnectorsByBusIn(root string) map[int]string {
	connectors := map[int]string{}
	entries, err := os.ReadDir(root)
	if err != nil {
		return connectors
	}
	for _, entry := range entries {
		name := entry.Name()
		if !drmConnectorPattern.MatchString(name) {
			continue
		}
		for _, busno := range drmConnectorBuses(name, filepath.Join(root, name)) {
			connectors[busno] = name
		}
	}
	return connectors
}

// amdgpu gives a DP connector two buses, the aux channel under i2c-N and the hardware i2c bus
// behind ddc, and a DP++ to HDMI adapter answers only on the ddc one (#3724).
func drmConnectorBuses(name, dir string) []int {
	buses := []int{}
	if busno, ok := i2cSubdirBus(filepath.Join(dir, "ddc", "i2c-dev")); ok {
		buses = append(buses, busno)
	}
	if !strings.Contains(name, "-DP-") {
		return buses
	}
	if busno, ok := i2cSubdirBus(dir); ok {
		buses = append(buses, busno)
	}
	return buses
}

func i2cSubdirBus(dir string) (int, bool) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0, false
	}
	for _, entry := range entries {
		match := i2cBusPattern.FindStringSubmatch(entry.Name())
		if match == nil {
			continue
		}
		if busno, err := strconv.Atoi(match[1]); err == nil {
			return busno, true
		}
	}
	return 0, false
}

func drmConnectorAttr(connector, attr string) string {
	data, err := os.ReadFile(filepath.Join("/sys/class/drm", connector, attr))
	if err != nil {
		return ""
	}
	return string(data)
}

var edidHeader = []byte{0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00}

func isValidEDID(edid []byte) bool {
	if len(edid) < 128 || !bytes.Equal(edid[:8], edidHeader) {
		return false
	}
	var sum byte
	for _, b := range edid[:128] {
		sum += b
	}
	return sum == 0
}

// A panel with neither a monitor name nor a serial descriptor is a laptop panel.
func isLaptopEDID(edid []byte) bool {
	return edidDescriptorText(edid, 0xfc) == "" && edidDescriptorText(edid, 0xff) == ""
}

func edidDescriptorText(edid []byte, tag byte) string {
	text := ""
	for i := range 4 {
		descriptor := edid[54+i*18 : 72+i*18]
		if descriptor[0] != 0 || descriptor[1] != 0 || descriptor[2] != 0 || descriptor[4] != 0 || descriptor[3] != tag {
			continue
		}
		raw := descriptor[5:18]
		if end := bytes.IndexByte(raw, 0x0a); end >= 0 {
			raw = raw[:end]
		}
		text = strings.TrimRight(string(raw), " \t\n\v\f\r")
	}
	return text
}
