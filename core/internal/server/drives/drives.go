// Package drives lists physical drives with a SMART summary read from UDisks2.
package drives

import (
	"math"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-go/dbusutil"
	"github.com/godbus/dbus/v5"
)

const (
	udisksPrefix        = "org.freedesktop.UDisks2."
	ifaceDrive          = udisksPrefix + "Drive"
	ifaceATA            = udisksPrefix + "Drive.Ata"
	ifaceNVMe           = udisksPrefix + "NVMe.Controller"
	ifaceBlock          = udisksPrefix + "Block"
	ifacePartition      = udisksPrefix + "Partition"
	ifacePartitionTable = udisksPrefix + "PartitionTable"
	ifaceFilesystem     = udisksPrefix + "Filesystem"
	ifaceEncrypted      = udisksPrefix + "Encrypted"
	ifaceSwapspace      = udisksPrefix + "Swapspace"
)

type objectMap = map[dbus.ObjectPath]map[string]map[string]dbus.Variant

type ListResult struct {
	Drives         []Drive `json:"drives"`
	Smartctl       string  `json:"smartctl"`
	InstallCommand string  `json:"installCommand"`
}

// QueueInfo is the kernel block queue setup from /sys/block/<name>/queue.
type QueueInfo struct {
	Scheduler     string `json:"scheduler,omitempty"`
	LogicalBlock  int    `json:"logicalBlock,omitempty"`
	PhysicalBlock int    `json:"physicalBlock,omitempty"`
	WriteCache    string `json:"writeCache,omitempty"`
	Trim          bool   `json:"trim"`
	Depth         int    `json:"depth,omitempty"`
}

type Drive struct {
	ID            string      `json:"id"`
	Model         string      `json:"model"`
	Serial        string      `json:"serial,omitempty"`
	Firmware      string      `json:"firmware,omitempty"`
	Size          uint64      `json:"size"`
	Kind          string      `json:"kind"`
	Device        string      `json:"device"`
	Name          string      `json:"name"`
	Removable     bool        `json:"removable"`
	ConnectionBus string      `json:"connectionBus,omitempty"`
	RotationRate  int32       `json:"rotationRate,omitempty"`
	Asleep        bool        `json:"asleep"`
	SmartUpdated  uint64      `json:"smartUpdated,omitempty"`
	Temperature   *float64    `json:"temperature,omitempty"`
	Health        string      `json:"health,omitempty"`
	WWN           string      `json:"wwn,omitempty"`
	TableType     string      `json:"tableType,omitempty"`
	Link          string      `json:"link,omitempty"`
	Queue         *QueueInfo  `json:"queue,omitempty"`
	NVMe          *NVMeSmart  `json:"nvme,omitempty"`
	ATA           *ATASmart   `json:"ata,omitempty"`
	Partitions    []Partition `json:"partitions"`
}

type NVMeSmart struct {
	CriticalWarning []string `json:"criticalWarning"`
	AvailableSpare  *uint64  `json:"availableSpare,omitempty"`
	SpareThreshold  *uint64  `json:"spareThreshold,omitempty"`
	PercentUsed     *uint64  `json:"percentUsed,omitempty"`
	MediaErrors     *uint64  `json:"mediaErrors,omitempty"`
	DataRead        *uint64  `json:"dataRead,omitempty"`
	DataWritten     *uint64  `json:"dataWritten,omitempty"`
	UnsafeShutdowns *uint64  `json:"unsafeShutdowns,omitempty"`
	PowerOnHours    *uint64  `json:"powerOnHours,omitempty"`
	SelftestStatus  string   `json:"selftestStatus,omitempty"`
}

type ATASmart struct {
	ReallocatedSectors   *int64  `json:"reallocatedSectors,omitempty"`
	PendingSectors       *int64  `json:"pendingSectors,omitempty"`
	OfflineUncorrectable *int64  `json:"offlineUncorrectable,omitempty"`
	CRCErrors            *int64  `json:"crcErrors,omitempty"`
	PowerOnHours         *uint64 `json:"powerOnHours,omitempty"`
	StartStopCount       *int64  `json:"startStopCount,omitempty"`
	LoadCycleCount       *int64  `json:"loadCycleCount,omitempty"`
	SpinUpTimeMs         *int64  `json:"spinUpTimeMs,omitempty"`
	SelftestStatus       string  `json:"selftestStatus,omitempty"`
	Failing              bool    `json:"failing,omitempty"`
}

type Partition struct {
	Device     string `json:"device"`
	Number     uint32 `json:"number"`
	Size       uint64 `json:"size"`
	FSType     string `json:"fsType,omitempty"`
	Label      string `json:"label,omitempty"`
	MountPoint string `json:"mountPoint,omitempty"`
	Encrypted  bool   `json:"encrypted"`
	Encryption string `json:"encryption,omitempty"`
	Swap       bool   `json:"swap,omitempty"`
	offset     uint64
}

// ataAttribute mirrors one element of Drive.Ata.SmartGetAttributes' a(ysqiiixia{sv}).
type ataAttribute struct {
	ID         byte
	Name       string
	Flags      uint16
	Value      int32
	Worst      int32
	Threshold  int32
	Pretty     int64
	PrettyUnit int32
	Expansion  map[string]dbus.Variant
}

const prettyUnitMs = 2

// buildDrives turns UDisks objects and per-drive SMART reads into the drive list.
// cache holds the last attribute-derived ATA summary per drive id: it is filled
// from fresh attributes and read back for drives that are asleep or whose read failed.
func buildDrives(objects objectMap, nvmeAttrs map[dbus.ObjectPath]map[string]dbus.Variant,
	ataAttrs map[dbus.ObjectPath][]ataAttribute, asleep map[dbus.ObjectPath]bool, cache map[string]ATASmart,
) []Drive {
	wholeBlock := map[dbus.ObjectPath]dbus.ObjectPath{}
	cleartext := map[dbus.ObjectPath]dbus.ObjectPath{}
	for p, ifaces := range objects {
		blk, ok := ifaces[ifaceBlock]
		if !ok {
			continue
		}
		if backing := dbusutil.GetOr(blk, "CryptoBackingDevice", dbus.ObjectPath("/")); backing != "/" {
			cleartext[backing] = p
		}
		if _, isPart := ifaces[ifacePartition]; isPart {
			continue
		}
		drv := dbusutil.GetOr(blk, "Drive", dbus.ObjectPath("/"))
		if drv == "/" {
			continue
		}
		if prev, ok := wholeBlock[drv]; !ok || p < prev {
			wholeBlock[drv] = p
		}
	}

	drives := []Drive{}
	for p, ifaces := range objects {
		props, ok := ifaces[ifaceDrive]
		if !ok {
			continue
		}
		blockPath, ok := wholeBlock[p]
		if !ok {
			continue
		}
		// UDisks leaves Drive.Size at 0 for some NVMe drives; the whole-disk block knows it.
		size, _ := uintProp(props, "Size")
		if size == 0 {
			size, _ = uintProp(objects[blockPath][ifaceBlock], "Size")
		}
		if size == 0 {
			continue
		}
		device := byteString(dbusutil.GetOr(objects[blockPath][ifaceBlock], "Device", []byte(nil)))
		d := Drive{
			ID:            dbusutil.GetOr(props, "Id", path.Base(string(p))),
			Model:         dbusutil.GetOr(props, "Model", ""),
			Serial:        dbusutil.GetOr(props, "Serial", ""),
			Firmware:      dbusutil.GetOr(props, "Revision", ""),
			Size:          size,
			Device:        device,
			Name:          path.Base(device),
			Removable:     dbusutil.GetOr(props, "Removable", false),
			WWN:           dbusutil.GetOr(props, "WWN", ""),
			TableType:     dbusutil.GetOr(objects[blockPath][ifacePartitionTable], "Type", ""),
			ConnectionBus: dbusutil.GetOr(props, "ConnectionBus", ""),
			RotationRate:  dbusutil.GetOr(props, "RotationRate", int32(0)),
			Kind:          driveKind(ifaces),
			Partitions:    partitions(objects, blockPath, cleartext),
		}
		d.Queue = queueInfo(d.Name)
		if ctrl, ok := ifaces[ifaceNVMe]; ok {
			fillNVMe(&d, ctrl, nvmeAttrs[p])
			d.Link = pcieLink(d.Name)
		} else {
			d.Link = sataLink(d.Name)
		}
		if ata, ok := ifaces[ifaceATA]; ok && dbusutil.GetOr(ata, "SmartSupported", false) && dbusutil.GetOr(ata, "SmartEnabled", false) {
			d.Asleep = asleep[p]
			fillATA(&d, ata, ataAttrs[p], cache)
		}
		drives = append(drives, d)
	}
	slices.SortFunc(drives, func(a, b Drive) int { return strings.Compare(a.Name, b.Name) })
	return drives
}

func driveKind(ifaces map[string]map[string]dbus.Variant) string {
	if _, ok := ifaces[ifaceNVMe]; ok {
		return "nvme"
	}
	props := ifaces[ifaceDrive]
	for _, m := range dbusutil.GetOr(props, "MediaCompatibility", []string(nil)) {
		if strings.HasPrefix(m, "optical") || strings.HasPrefix(m, "flash") {
			return "other"
		}
	}
	rate, ok := dbusutil.Get[int32](props, "RotationRate")
	switch {
	case !ok:
		return "other"
	case rate == 0:
		return "ssd"
	default:
		return "hdd"
	}
}

func partitions(objects objectMap, table dbus.ObjectPath, cleartext map[dbus.ObjectPath]dbus.ObjectPath) []Partition {
	parts := []Partition{}
	for p, ifaces := range objects {
		part, ok := ifaces[ifacePartition]
		if !ok || dbusutil.GetOr(part, "Table", dbus.ObjectPath("/")) != table {
			continue
		}
		blk := ifaces[ifaceBlock]
		size, _ := uintProp(part, "Size")
		offset, _ := uintProp(part, "Offset")
		pt := Partition{
			Device:     byteString(dbusutil.GetOr(blk, "Device", []byte(nil))),
			Number:     dbusutil.GetOr(part, "Number", uint32(0)),
			Size:       size,
			FSType:     dbusutil.GetOr(blk, "IdType", ""),
			Label:      dbusutil.GetOr(blk, "IdLabel", ""),
			MountPoint: mountPoint(ifaces[ifaceFilesystem]),
			offset:     offset,
		}
		if _, ok := ifaces[ifaceEncrypted]; ok {
			pt.Encrypted = true
		}
		if pt.FSType == "crypto_LUKS" {
			pt.Encryption = "LUKS" + dbusutil.GetOr(blk, "IdVersion", "")
		}
		_, pt.Swap = ifaces[ifaceSwapspace]
		// An unlocked LUKS partition is mounted through its cleartext mapping.
		if ct, ok := cleartext[p]; ok {
			pt.Encrypted = true
			ctBlk := objects[ct][ifaceBlock]
			pt.FSType = dbusutil.GetOr(ctBlk, "IdType", pt.FSType)
			pt.Label = dbusutil.GetOr(ctBlk, "IdLabel", pt.Label)
			pt.MountPoint = mountPoint(objects[ct][ifaceFilesystem])
			_, pt.Swap = objects[ct][ifaceSwapspace]
		}
		parts = append(parts, pt)
	}
	slices.SortFunc(parts, func(a, b Partition) int {
		switch {
		case a.offset < b.offset:
			return -1
		case a.offset > b.offset:
			return 1
		}
		return 0
	})
	return parts
}

func mountPoint(fs map[string]dbus.Variant) string {
	best := ""
	for _, raw := range dbusutil.GetOr(fs, "MountPoints", [][]byte(nil)) {
		mp := byteString(raw)
		if mp == "/" {
			return mp
		}
		if mp != "" && (best == "" || len(mp) < len(best)) {
			best = mp
		}
	}
	return best
}

func fillNVMe(d *Drive, ctrl, attrs map[string]dbus.Variant) {
	n := &NVMeSmart{
		CriticalWarning: dbusutil.GetOr(ctrl, "SmartCriticalWarning", []string{}),
		SelftestStatus:  dbusutil.GetOr(ctrl, "SmartSelftestStatus", ""),
		AvailableSpare:  optUint(attrs, "avail_spare"),
		SpareThreshold:  optUint(attrs, "spare_thresh"),
		PercentUsed:     optUint(attrs, "percent_used"),
		MediaErrors:     optUint(attrs, "media_errors"),
		DataRead:        optUint(attrs, "total_data_read"),
		DataWritten:     optUint(attrs, "total_data_written"),
		UnsafeShutdowns: optUint(attrs, "unsafe_shutdowns"),
		PowerOnHours:    optUint(ctrl, "SmartPowerOnHours"),
	}
	d.NVMe = n
	d.SmartUpdated, _ = uintProp(ctrl, "SmartUpdated")
	d.Temperature = celsius(ctrl)
	if d.SmartUpdated == 0 && attrs == nil {
		return
	}
	switch {
	case slices.ContainsFunc(n.CriticalWarning, func(w string) bool { return w != "" }):
		d.Health = "failing"
	case n.AvailableSpare != nil && n.SpareThreshold != nil && *n.AvailableSpare < *n.SpareThreshold:
		d.Health = "warning"
	default:
		d.Health = "ok"
	}
}

func fillATA(d *Drive, props map[string]dbus.Variant, attrs []ataAttribute, cache map[string]ATASmart) {
	var a ATASmart
	var cached bool
	switch {
	case d.Asleep || attrs == nil:
		a, cached = cache[d.ID]
	default:
		a = summarizeATA(attrs)
		cache[d.ID] = a
	}
	a.Failing = dbusutil.GetOr(props, "SmartFailing", false)
	a.SelftestStatus = dbusutil.GetOr(props, "SmartSelftestStatus", "")
	if secs, ok := uintProp(props, "SmartPowerOnSeconds"); ok && secs > 0 {
		h := secs / 3600
		a.PowerOnHours = &h
	}
	d.ATA = &a
	d.SmartUpdated, _ = uintProp(props, "SmartUpdated")
	d.Temperature = celsius(props)

	if d.SmartUpdated == 0 && attrs == nil && !cached {
		return
	}
	positive := func(p *int64) bool { return p != nil && *p > 0 }
	switch {
	case a.Failing:
		d.Health = "failing"
	case positive(a.ReallocatedSectors) || positive(a.PendingSectors) || positive(a.OfflineUncorrectable):
		d.Health = "warning"
	default:
		d.Health = "ok"
	}
}

func summarizeATA(attrs []ataAttribute) ATASmart {
	var a ATASmart
	for _, at := range attrs {
		if at.PrettyUnit == 0 {
			continue
		}
		val := at.Pretty
		switch at.Name {
		case "reallocated-sector-count":
			a.ReallocatedSectors = &val
		case "current-pending-sector":
			a.PendingSectors = &val
		case "offline-uncorrectable":
			a.OfflineUncorrectable = &val
		case "udma-crc-error-count":
			a.CRCErrors = &val
		case "start-stop-count":
			a.StartStopCount = &val
		case "load-cycle-count":
			a.LoadCycleCount = &val
		case "spin-up-time":
			if at.PrettyUnit == prettyUnitMs {
				a.SpinUpTimeMs = &val
			}
		}
	}
	return a
}

// celsius converts UDisks' SmartTemperature (Kelvin; uint16 on NVMe, double on ATA).
func celsius(props map[string]dbus.Variant) *float64 {
	v, ok := props["SmartTemperature"]
	if !ok {
		return nil
	}
	var k float64
	switch t := v.Value().(type) {
	case float64:
		k = t
	default:
		u, ok := toUint(t)
		if !ok {
			return nil
		}
		k = float64(u)
	}
	if k <= 0 {
		return nil
	}
	c := math.Round((k-273.15)*10) / 10
	return &c
}

func uintProp(m map[string]dbus.Variant, key string) (uint64, bool) {
	v, ok := m[key]
	if !ok {
		return 0, false
	}
	return toUint(v.Value())
}

func optUint(m map[string]dbus.Variant, key string) *uint64 {
	u, ok := uintProp(m, key)
	if !ok {
		return nil
	}
	return &u
}

func toUint(v any) (uint64, bool) {
	switch n := v.(type) {
	case byte:
		return uint64(n), true
	case uint16:
		return uint64(n), true
	case uint32:
		return uint64(n), true
	case uint64:
		return n, true
	case int16:
		return uint64(max(n, 0)), true
	case int32:
		return uint64(max(n, 0)), true
	case int64:
		return uint64(max(n, 0)), true
	}
	return 0, false
}

func byteString(b []byte) string {
	return strings.TrimRight(string(b), "\x00")
}

var (
	sysClassNVMe    = "/sys/class/nvme"
	sysClassNVMeSub = "/sys/class/nvme-subsystem"
	sysClassATALink = "/sys/class/ata_link"
	sysBlock        = "/sys/block"
)

func readSysfs(parts ...string) string {
	b, err := os.ReadFile(filepath.Join(parts...))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// queueInfo reads the block queue attributes, which the kernel serves from memory.
func queueInfo(name string) *QueueInfo {
	dir := filepath.Join(sysBlock, name, "queue")
	if _, err := os.Stat(dir); err != nil {
		return nil
	}
	num := func(f string) int {
		n, _ := strconv.Atoi(readSysfs(dir, f))
		return n
	}
	return &QueueInfo{
		Scheduler:     activeScheduler(readSysfs(dir, "scheduler")),
		LogicalBlock:  num("logical_block_size"),
		PhysicalBlock: num("physical_block_size"),
		WriteCache:    readSysfs(dir, "write_cache"),
		Trim:          num("discard_granularity") > 0,
		Depth:         num("nr_requests"),
	}
}

// activeScheduler picks the bracketed entry of "[none] mq-deadline kyber bfq".
func activeScheduler(list string) string {
	for _, s := range strings.Fields(list) {
		if strings.HasPrefix(s, "[") && strings.HasSuffix(s, "]") {
			return s[1 : len(s)-1]
		}
	}
	return ""
}

var ataPortRe = regexp.MustCompile(`^ata(\d+)$`)

// sataLink formats the negotiated SATA speed of a disk, e.g. "SATA 6.0 Gbps". The disk's device path runs through
// its ataN port, whose first link holds the speed. Empty for anything that is not on an ATA port.
func sataLink(name string) string {
	target, err := filepath.EvalSymlinks(filepath.Join(sysBlock, name, "device"))
	if err != nil {
		return ""
	}
	for _, part := range strings.Split(target, string(filepath.Separator)) {
		m := ataPortRe.FindStringSubmatch(part)
		if m == nil {
			continue
		}
		if spd := readSysfs(sysClassATALink, "link"+m[1], "sata_spd"); spd != "" && spd != "<unknown>" {
			return "SATA " + spd
		}
		return ""
	}
	return ""
}

var nvmeNameRe = regexp.MustCompile(`^nvme(\d+)(?:c(\d+))?n\d+$`)

var nvmeCtrlRe = regexp.MustCompile(`^nvme\d+$`)

// nvmeController maps a block name to its controller. In nvmeXcYnZ, Y is the
// controller. In nvmeXnZ, X is the subsystem instance, so resolve through sysfs.
func nvmeController(name string) string {
	m := nvmeNameRe.FindStringSubmatch(name)
	if m == nil {
		return ""
	}
	if m[2] != "" {
		return "nvme" + m[2]
	}
	if t, err := os.Readlink(filepath.Join(sysBlock, name, "device")); err == nil && nvmeCtrlRe.MatchString(filepath.Base(t)) {
		return filepath.Base(t)
	}
	// Multipath head: the device link points at the subsystem; use its first controller.
	ents, _ := os.ReadDir(filepath.Join(sysClassNVMeSub, "nvme-subsys"+m[1]))
	for _, e := range ents {
		if nvmeCtrlRe.MatchString(e.Name()) {
			return e.Name()
		}
	}
	return ""
}

var pcieGen = map[string]string{"2.5": "1.0", "5": "2.0", "8": "3.0", "16": "4.0", "32": "5.0", "64": "6.0"}

// pcieLink formats the negotiated link of an NVMe namespace's controller, e.g.
// "PCIe 4.0 x4". Reads only sysfs attributes, so a suspended device stays asleep.
// Returns "" when the files are missing or unrecognized.
func pcieLink(name string) string {
	ctrl := nvmeController(name)
	if ctrl == "" {
		return ""
	}
	read := func(f string) string {
		b, err := os.ReadFile(filepath.Join(sysClassNVMe, ctrl, "device", f))
		if err != nil {
			return ""
		}
		return strings.TrimSpace(string(b))
	}
	speed, _, _ := strings.Cut(read("current_link_speed"), " ")
	gen, ok := pcieGen[strings.TrimSuffix(speed, ".0")]
	if !ok {
		return ""
	}
	if width, err := strconv.Atoi(read("current_link_width")); err == nil && width > 0 {
		return "PCIe " + gen + " x" + strconv.Itoa(width)
	}
	return ""
}
