package drives

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type props = map[string]dbus.Variant

func v(x any) dbus.Variant { return dbus.MakeVariant(x) }

func ay(s string) []byte { return append([]byte(s), 0) }

func mounts(paths ...string) [][]byte {
	out := make([][]byte, len(paths))
	for i, p := range paths {
		out[i] = ay(p)
	}
	return out
}

const (
	bdPath   = "/org/freedesktop/UDisks2/block_devices/"
	drvPath  = "/org/freedesktop/UDisks2/drives/"
	samsung  = drvPath + "Samsung_SSD_990_PRO_2TB"
	lexar    = drvPath + "Lexar_SSD_NM790_4TB"
	hddDrive = drvPath + "WDC_WD40EFRX"
)

func nvmeDrive(id, model string, size uint64, kelvin uint16) map[string]props {
	return map[string]props{
		ifaceDrive: {
			"Id": v(id), "Model": v(model), "Serial": v(id + "-SN"), "Revision": v("3B2QJXD7"), "Size": v(size),
			"RotationRate": v(int32(0)), "ConnectionBus": v(""), "Removable": v(false),
		},
		ifaceNVMe: {
			"SmartUpdated": v(uint64(1791034891)), "SmartCriticalWarning": v([]string{}),
			"SmartPowerOnHours": v(uint64(1740)), "SmartTemperature": v(kelvin),
			"SmartSelftestStatus": v("success"),
		},
	}
}

func block(dev, drive string, size uint64, extra map[string]props) map[string]props {
	b := map[string]props{
		ifaceBlock: {
			"Device": v(ay(dev)), "Drive": v(dbus.ObjectPath(drive)), "Size": v(size),
			"IdType": v(""), "IdLabel": v(""), "CryptoBackingDevice": v(dbus.ObjectPath("/")),
		},
	}
	for iface, p := range extra {
		if iface == ifaceBlock {
			for k, val := range p {
				b[ifaceBlock][k] = val
			}
			continue
		}
		b[iface] = p
	}
	return b
}

func partition(table string, number uint32, offset, size uint64) props {
	return props{"Table": v(dbus.ObjectPath(table)), "Number": v(number), "Offset": v(offset), "Size": v(size)}
}

func machineFixture() objectMap {
	return objectMap{
		samsung: nvmeDrive("Samsung-SSD-990-PRO-2TB", "Samsung SSD 990 PRO 2TB", 2000398934016, 318),
		lexar:   nvmeDrive("Lexar-SSD-NM790-4TB", "Lexar SSD NM790 4TB", 4096805658624, 319),
		bdPath + "nvme0n1": block("/dev/nvme0n1", samsung, 2000398934016, map[string]props{
			ifacePartitionTable: {},
		}),
		// listed before p1 on purpose: partitions must come back in offset order
		bdPath + "nvme0n1p2": block("/dev/nvme0n1p2", samsung, 1996001172480, map[string]props{
			ifaceBlock:     {"IdType": v("crypto_LUKS"), "IdVersion": v("2")},
			ifacePartition: partition(bdPath+"nvme0n1", 2, 4397727744, 1996001172480),
			ifaceEncrypted: {},
		}),
		bdPath + "nvme0n1p1": block("/dev/nvme0n1p1", samsung, 4395630592, map[string]props{
			ifaceBlock:      {"IdType": v("vfat")},
			ifacePartition:  partition(bdPath+"nvme0n1", 1, 2097152, 4395630592),
			ifaceFilesystem: {"MountPoints": v(mounts("/boot"))},
		}),
		bdPath + "dm_2d0": block("/dev/dm-0", "/", 1995984395264, map[string]props{
			ifaceBlock:      {"IdType": v("btrfs"), "CryptoBackingDevice": v(dbus.ObjectPath(bdPath + "nvme0n1p2"))},
			ifaceFilesystem: {"MountPoints": v(mounts("/var/log", "/home", "/"))},
		}),
		bdPath + "nvme1n1": block("/dev/nvme1n1", lexar, 4096805658624, map[string]props{
			ifacePartitionTable: {},
		}),
		bdPath + "nvme1n1p1": block("/dev/nvme1n1p1", lexar, 4096804593152, map[string]props{
			ifaceBlock:     {"IdType": v("crypto_LUKS")},
			ifacePartition: partition(bdPath+"nvme1n1", 1, 1048576, 4096804593152),
			ifaceEncrypted: {},
		}),
		bdPath + "dm_2d1": block("/dev/dm-1", "/", 4096804593152, map[string]props{
			ifaceBlock:     {"IdType": v("swap"), "CryptoBackingDevice": v(dbus.ObjectPath(bdPath + "nvme1n1p1"))},
			ifaceSwapspace: {"Active": v(true)},
		}),
	}
}

func samsungAttrs() map[string]dbus.Variant {
	return props{
		"avail_spare": v(byte(100)), "spare_thresh": v(byte(10)), "percent_used": v(byte(1)),
		"total_data_read": v(uint64(74983312896000)), "total_data_written": v(uint64(28473729024000)),
		"unsafe_shutdowns": v(uint64(96)), "media_errors": v(uint64(0)), "power_cycles": v(uint64(1189)),
	}
}

func byName(t *testing.T, drives []Drive, name string) Drive {
	t.Helper()
	for _, d := range drives {
		if d.Name == name {
			return d
		}
	}
	t.Fatalf("drive %s not found", name)
	return Drive{}
}

func TestBuildDrivesNVMeLuksMachine(t *testing.T) {
	drives := buildDrives(machineFixture(),
		map[dbus.ObjectPath]map[string]dbus.Variant{samsung: samsungAttrs()}, nil, nil, map[string]ATASmart{})

	require.Len(t, drives, 2)
	d := byName(t, drives, "nvme0n1")
	assert.Equal(t, "/dev/nvme0n1", d.Device)
	assert.Equal(t, "3B2QJXD7", d.Firmware)
	assert.Equal(t, "nvme", d.Kind)
	assert.Equal(t, uint64(2000398934016), d.Size)
	require.NotNil(t, d.Temperature)
	assert.InDelta(t, 44.9, *d.Temperature, 0.001)
	assert.Equal(t, "ok", d.Health)
	require.NotNil(t, d.NVMe)
	require.NotNil(t, d.NVMe.DataRead)
	assert.Equal(t, uint64(74983312896000), *d.NVMe.DataRead)
	require.NotNil(t, d.NVMe.PowerOnHours)
	assert.Equal(t, uint64(1740), *d.NVMe.PowerOnHours)

	require.Len(t, d.Partitions, 2)
	assert.Equal(t, "/dev/nvme0n1p1", d.Partitions[0].Device)
	assert.Equal(t, "/boot", d.Partitions[0].MountPoint)
	assert.False(t, d.Partitions[0].Encrypted)
	p2 := d.Partitions[1]
	assert.Equal(t, "/", p2.MountPoint)
	assert.True(t, p2.Encrypted)
	assert.Equal(t, "LUKS2", p2.Encryption)
	assert.Equal(t, "btrfs", p2.FSType)

	lex := byName(t, drives, "nvme1n1")
	require.Len(t, lex.Partitions, 1)
	assert.True(t, lex.Partitions[0].Encrypted)
	assert.True(t, lex.Partitions[0].Swap, "swap inside LUKS is found through the cleartext device")
	assert.False(t, d.Partitions[0].Swap)
	assert.Empty(t, lex.Partitions[0].MountPoint)
	assert.Equal(t, "ok", lex.Health, "controller properties alone are SMART data")
	assert.Nil(t, lex.NVMe.DataRead, "absent attributes stay absent")
}

func TestBuildDrivesTemperatureFromKelvin(t *testing.T) {
	objs := machineFixture()
	objs[samsung][ifaceNVMe]["SmartTemperature"] = v(uint16(318))
	d := byName(t, buildDrives(objs, nil, nil, nil, map[string]ATASmart{}), "nvme0n1")
	assert.InDelta(t, 44.9, *d.Temperature, 1e-9)

	objs[samsung][ifaceNVMe]["SmartTemperature"] = v(uint16(0))
	d = byName(t, buildDrives(objs, nil, nil, nil, map[string]ATASmart{}), "nvme0n1")
	assert.Nil(t, d.Temperature)
}

func hddFixture(rotation int32, failing bool) objectMap {
	return objectMap{
		hddDrive: {
			ifaceDrive: {
				"Id": v("WDC-WD40EFRX"), "Model": v("WDC WD40EFRX"), "Size": v(uint64(4000787030016)),
				"RotationRate": v(rotation), "ConnectionBus": v(""), "Removable": v(false),
			},
			ifaceATA: {
				"SmartSupported": v(true), "SmartEnabled": v(true), "SmartUpdated": v(uint64(1791000000)),
				"SmartFailing": v(failing), "SmartPowerOnSeconds": v(uint64(36000)),
				"SmartTemperature": v(float64(308.15)), "SmartSelftestStatus": v("success"),
			},
		},
		bdPath + "sda": block("/dev/sda", hddDrive, 4000787030016, nil),
	}
}

func ataAttrs(reallocated int64) []ataAttribute {
	return []ataAttribute{
		{ID: 5, Name: "reallocated-sector-count", Pretty: reallocated, PrettyUnit: 3},
		{ID: 197, Name: "current-pending-sector", Pretty: 0, PrettyUnit: 3},
		{ID: 198, Name: "offline-uncorrectable", Pretty: 0, PrettyUnit: 3},
		{ID: 199, Name: "udma-crc-error-count", Pretty: 4, PrettyUnit: 1},
		{ID: 4, Name: "start-stop-count", Pretty: 812, PrettyUnit: 1},
		{ID: 193, Name: "load-cycle-count", Pretty: 1200, PrettyUnit: 1},
		{ID: 3, Name: "spin-up-time", Pretty: 6250, PrettyUnit: 2},
	}
}

func TestBuildDrivesHDDAsleepUsesCache(t *testing.T) {
	cached := map[string]ATASmart{"WDC-WD40EFRX": {ReallocatedSectors: ptr(int64(7))}}
	attrs := map[dbus.ObjectPath][]ataAttribute{hddDrive: ataAttrs(0)}

	d := buildDrives(hddFixture(5400, false), nil, attrs, map[dbus.ObjectPath]bool{hddDrive: true}, cached)[0]

	assert.True(t, d.Asleep)
	assert.Equal(t, "hdd", d.Kind)
	assert.Equal(t, uint64(1791000000), d.SmartUpdated)
	require.NotNil(t, d.ATA)
	assert.Equal(t, int64(7), *d.ATA.ReallocatedSectors, "cached value, not the attribute map")
	assert.Nil(t, d.ATA.LoadCycleCount)
	assert.Equal(t, uint64(10), *d.ATA.PowerOnHours)
	assert.Equal(t, "warning", d.Health)
	assert.InDelta(t, 35.0, *d.Temperature, 1e-9)
}

func TestBuildDrivesHDDAwakeFillsCache(t *testing.T) {
	cache := map[string]ATASmart{}
	attrs := map[dbus.ObjectPath][]ataAttribute{hddDrive: ataAttrs(2)}

	d := buildDrives(hddFixture(-1, false), nil, attrs, nil, cache)[0]

	assert.False(t, d.Asleep)
	assert.Equal(t, "hdd", d.Kind)
	assert.Equal(t, "warning", d.Health)
	assert.Equal(t, int64(2), *d.ATA.ReallocatedSectors)
	assert.Equal(t, int64(4), *d.ATA.CRCErrors)
	assert.Equal(t, int64(812), *d.ATA.StartStopCount)
	assert.Equal(t, int64(1200), *d.ATA.LoadCycleCount)
	assert.Equal(t, int64(6250), *d.ATA.SpinUpTimeMs)
	assert.Equal(t, int64(2), *cache["WDC-WD40EFRX"].ReallocatedSectors)

	d = buildDrives(hddFixture(-1, false), nil, map[dbus.ObjectPath][]ataAttribute{hddDrive: ataAttrs(0)}, nil, cache)[0]
	assert.Equal(t, "ok", d.Health)
}

func TestBuildDrivesHealth(t *testing.T) {
	objs := machineFixture()
	attrs := samsungAttrs()
	attrs["avail_spare"] = v(byte(5))
	d := byName(t, buildDrives(objs, map[dbus.ObjectPath]map[string]dbus.Variant{samsung: attrs}, nil, nil, map[string]ATASmart{}), "nvme0n1")
	assert.Equal(t, "warning", d.Health)

	objs[samsung][ifaceNVMe]["SmartCriticalWarning"] = v([]string{"spare"})
	d = byName(t, buildDrives(objs, nil, nil, nil, map[string]ATASmart{}), "nvme0n1")
	assert.Equal(t, "failing", d.Health)
	assert.Equal(t, []string{"spare"}, d.NVMe.CriticalWarning)

	hdd := buildDrives(hddFixture(0, true), nil, map[dbus.ObjectPath][]ataAttribute{hddDrive: ataAttrs(0)}, nil, map[string]ATASmart{})[0]
	assert.Equal(t, "ssd", hdd.Kind)
	assert.Equal(t, "failing", hdd.Health)
	assert.True(t, hdd.ATA.Failing)
}

func TestBuildDrivesWithoutSmart(t *testing.T) {
	usb := dbus.ObjectPath(drvPath + "JMicron_bridge")
	objs := objectMap{
		usb: {ifaceDrive: {
			"Id": v("JMicron"), "Model": v("Generic"), "Size": v(uint64(500107862016)),
			"RotationRate": v(int32(0)), "ConnectionBus": v("usb"), "Removable": v(true),
		}},
		bdPath + "sdb": block("/dev/sdb", string(usb), 500107862016, nil),
		// card reader without media
		drvPath + "reader": {ifaceDrive: {"Id": v("reader"), "Size": v(uint64(0)), "RotationRate": v(int32(-1))}},
		bdPath + "sdc":     block("/dev/sdc", drvPath+"reader", 0, nil),
		// drive object without any whole-disk block
		drvPath + "orphan": {ifaceDrive: {"Id": v("orphan"), "Size": v(uint64(1))}},
		// NVMe whose Drive.Size UDisks reports as 0
		drvPath + "Micron": {ifaceDrive: {"Id": v("Micron"), "Size": v(uint64(0)), "RotationRate": v(int32(0))}},
		bdPath + "nvme0n1": block("/dev/nvme0n1", drvPath+"Micron", 2048408248320, nil),
	}

	drives := buildDrives(objs, nil, nil, nil, map[string]ATASmart{})

	require.Len(t, drives, 2)
	assert.Equal(t, "nvme0n1", drives[0].Name)
	assert.Equal(t, uint64(2048408248320), drives[0].Size)
	d := drives[1]
	assert.Equal(t, "usb", d.ConnectionBus)
	assert.True(t, d.Removable)
	assert.Empty(t, d.Health)
	assert.Nil(t, d.ATA)
	assert.Nil(t, d.Temperature)

	raw, err := json.Marshal(d)
	require.NoError(t, err)
	var m map[string]any
	require.NoError(t, json.Unmarshal(raw, &m))
	assert.NotContains(t, m, "health")
	assert.NotContains(t, m, "temperature")
	assert.Equal(t, []any{}, m["partitions"])
}

func TestBuildDrivesOptical(t *testing.T) {
	dvd := dbus.ObjectPath(drvPath + "dvd")
	objs := objectMap{
		dvd: {ifaceDrive: {
			"Id": v("dvd"), "Size": v(uint64(4700000000)), "RotationRate": v(int32(-1)),
			"MediaCompatibility": v([]string{"optical_cd", "optical_dvd"}),
		}},
		bdPath + "sr0": block("/dev/sr0", string(dvd), 4700000000, nil),
	}
	assert.Equal(t, "other", buildDrives(objs, nil, nil, nil, map[string]ATASmart{})[0].Kind)
}

func ptr[T any](x T) *T { return &x }

func TestBuildDrivesATANoSmartData(t *testing.T) {
	objs := hddFixture(5400, false)
	objs[hddDrive][ifaceATA]["SmartUpdated"] = v(uint64(0))
	d := buildDrives(objs, nil, nil, nil, map[string]ATASmart{})[0]
	assert.Empty(t, d.Health)
	require.NotNil(t, d.ATA)

	raw, err := json.Marshal(d)
	require.NoError(t, err)
	var m map[string]any
	require.NoError(t, json.Unmarshal(raw, &m))
	assert.NotContains(t, m, "health")
}

func TestSummarizeATASkipsUnknownUnit(t *testing.T) {
	a := summarizeATA([]ataAttribute{{Name: "reallocated-sector-count", Pretty: 99, PrettyUnit: 0}})
	assert.Nil(t, a.ReallocatedSectors)
}

func TestDriveKindFlashMedia(t *testing.T) {
	ifaces := map[string]map[string]dbus.Variant{ifaceDrive: {
		"RotationRate": v(int32(0)), "MediaCompatibility": v([]string{"flash", "flash_sd"}),
	}}
	assert.Equal(t, "other", driveKind(ifaces))
}

func TestPCIeLink(t *testing.T) {
	root := t.TempDir()
	old := sysClassNVMe
	sysClassNVMe = root
	t.Cleanup(func() { sysClassNVMe = old })
	oldSub, oldBlk := sysClassNVMeSub, sysBlock
	sysClassNVMeSub, sysBlock = filepath.Join(root, "sub"), filepath.Join(root, "blk")
	t.Cleanup(func() { sysClassNVMeSub, sysBlock = oldSub, oldBlk })
	write := func(ctrl, speed, width string) {
		dir := filepath.Join(root, ctrl, "device")
		require.NoError(t, os.MkdirAll(dir, 0o755))
		require.NoError(t, os.WriteFile(filepath.Join(dir, "current_link_speed"), []byte(speed), 0o644))
		require.NoError(t, os.WriteFile(filepath.Join(dir, "current_link_width"), []byte(width), 0o644))
	}
	write("nvme0", "16.0 GT/s PCIe\n", "4\n")
	write("nvme1", "2.5 GT/s PCIe\n", "1\n")
	write("nvme2", "Unknown\n", "4\n")
	write("nvme3", "8.0 GT/s PCIe\n", "2\n")
	// Multipath: subsystem 0 holds controllers nvme0 (c0) and nvme1 (c1).
	require.NoError(t, os.MkdirAll(filepath.Join(sysClassNVMeSub, "nvme-subsys0", "nvme0"), 0o755))
	require.NoError(t, os.MkdirAll(filepath.Join(sysClassNVMeSub, "nvme-subsys5", "nvme3"), 0o755))
	require.NoError(t, os.MkdirAll(filepath.Join(sysBlock, "nvme0n1"), 0o755))
	require.NoError(t, os.Symlink("../../nvme-subsys0", filepath.Join(sysBlock, "nvme0n1", "device")))
	require.NoError(t, os.MkdirAll(filepath.Join(sysBlock, "nvme5n1"), 0o755))
	require.NoError(t, os.Symlink("../../nvme-subsys5", filepath.Join(sysBlock, "nvme5n1", "device")))
	require.NoError(t, os.MkdirAll(filepath.Join(sysBlock, "nvme1n1"), 0o755))
	require.NoError(t, os.Symlink("../../nvme1", filepath.Join(sysBlock, "nvme1n1", "device")))
	assert.Equal(t, "PCIe 4.0 x4", pcieLink("nvme0n1"))
	assert.Equal(t, "PCIe 1.0 x1", pcieLink("nvme1n1"))
	assert.Equal(t, "PCIe 3.0 x2", pcieLink("nvme5n1"))
	assert.Equal(t, "PCIe 3.0 x2", pcieLink("nvme0c3n1"))
	assert.Equal(t, "PCIe 1.0 x1", pcieLink("nvme0c1n1"))
	assert.Equal(t, "PCIe 4.0 x4", pcieLink("nvme1c0n1"))
	assert.Empty(t, pcieLink("nvme2n1"))
	assert.Empty(t, pcieLink("nvme9n1"))
	assert.Empty(t, pcieLink("sda"))
}

func TestQueueInfoAndSataLink(t *testing.T) {
	root := t.TempDir()
	oldBlk, oldLink := sysBlock, sysClassATALink
	sysBlock, sysClassATALink = filepath.Join(root, "block"), filepath.Join(root, "ata_link")
	t.Cleanup(func() { sysBlock, sysClassATALink = oldBlk, oldLink })

	queue := filepath.Join(sysBlock, "sda", "queue")
	require.NoError(t, os.MkdirAll(queue, 0o755))
	for f, v := range map[string]string{
		"scheduler": "[mq-deadline] none kyber\n", "logical_block_size": "512\n", "physical_block_size": "4096\n",
		"write_cache": "write back\n", "discard_granularity": "0\n", "nr_requests": "64\n",
	} {
		require.NoError(t, os.WriteFile(filepath.Join(queue, f), []byte(v), 0o644))
	}
	port := filepath.Join(root, "devices", "pci0000:00", "0000:00:17.0", "ata3", "host2", "target2:0:0", "2:0:0:0")
	require.NoError(t, os.MkdirAll(port, 0o755))
	require.NoError(t, os.Symlink(port, filepath.Join(sysBlock, "sda", "device")))
	link := filepath.Join(sysClassATALink, "link3")
	require.NoError(t, os.MkdirAll(link, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(link, "sata_spd"), []byte("6.0 Gbps\n"), 0o644))

	assert.Equal(t, &QueueInfo{Scheduler: "mq-deadline", LogicalBlock: 512, PhysicalBlock: 4096, WriteCache: "write back", Depth: 64}, queueInfo("sda"))
	assert.Equal(t, "SATA 6.0 Gbps", sataLink("sda"))
	assert.Nil(t, queueInfo("sdz"))
	assert.Equal(t, "", sataLink("sdz"))
}
