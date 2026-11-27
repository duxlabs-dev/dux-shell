pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "SysmonDevices.js" as Devices
import "Drives.js" as Drives
import "SysmonCatalog.js" as SysmonCatalog
import "../Common/Format.js" as Format

// Device identity and current values for the system monitor and its widgets. Besides the device counts,
// everything here is evaluated only when a visible consumer calls it.
Singleton {
    id: root

    readonly property var netKindOrder: ["ethernet", "wifi", "vpn", "other", "virtual", "loopback"]

    function netKindName(kind) {
        switch (kind) {
        case "ethernet":
            return I18n.tr("Ethernet");
        case "wifi":
            return I18n.tr("Wi-Fi");
        case "vpn":
            return I18n.tr("VPN");
        }
        return "";
    }

    function netIcon(kind) {
        return kind === "wifi" ? "wifi" : kind === "vpn" ? "vpn_key" : "lan";
    }

    function parseKey(key) {
        const k = typeof key === "string" ? key : "";
        const i = k.indexOf(":");
        return i < 0 ? {
            type: k,
            id: ""
        } : {
            type: k.slice(0, i),
            id: k.slice(i + 1)
        };
    }

    // A slot match wins, so a PCI id shared by twin cards only resolves to the first.
    function gpuFor(id) {
        const want = String(id || "").toLowerCase();
        if (!want)
            return null;
        const gpus = DgopService.availableGpus ?? [];
        return gpus.find(g => Devices.gpuSlot(g).toLowerCase() === want) ?? gpus.find(g => String(g.pciId || "").toLowerCase() === want) ?? null;
    }

    function gpuSleepNote() {
        return I18n.tr("Monitoring can keep it from sleeping", "system monitor: reading a GPU can stop it from suspending");
    }

    function hostGpuCount() {
        return (DgopService.availableGpus ?? []).length;
    }

    function sortedNets() {
        const rank = kind => {
            const i = netKindOrder.indexOf(kind);
            return i < 0 ? netKindOrder.length : i;
        };
        return (DgopService.netRates ?? []).map(n => ({
                    net: n,
                    kind: Devices.interfaceKind(n.iface, n.linkType)
                })).sort((a, b) => rank(a.kind) - rank(b.kind) || Devices.naturalCompare(a.net.iface, b.net.iface));
    }

    function wholeDisks() {
        const drives = DriveService.drives ?? [];
        const rank = name => {
            const i = drives.indexOf(Drives.driveFor(name, drives));
            return i < 0 ? drives.length : i;
        };
        return (DgopService.diskRates ?? []).filter(d => Devices.isWholeDisk(d.device)).sort((a, b) => rank(a.device) - rank(b.device) || Devices.naturalCompare(a.device, b.device));
    }

    function cpuEntry(group) {
        return {
            key: "cpu",
            type: "cpu",
            group: group,
            icon: "memory",
            name: I18n.tr("CPU", "processor label in system monitor"),
            hidden: false
        };
    }

    function memoryEntry(group) {
        return {
            key: "memory",
            type: "memory",
            group: group,
            icon: "developer_board",
            name: I18n.tr("Memory", "system RAM label in system monitor"),
            hidden: false
        };
    }

    function gpuEntry(g) {
        return {
            key: Devices.deviceKey("gpu", Devices.gpuSlot(g)),
            type: "gpu",
            group: I18n.tr("Graphics"),
            icon: "gpu",
            name: g.fullName,
            hidden: false,
            gpu: g
        };
    }

    function diskEntry(name, rates) {
        const drive = Drives.driveFor(name, DriveService.drives);
        return {
            key: Devices.deviceKey("disk", name),
            type: "disk",
            group: I18n.tr("Storage", "system monitor device group: disks"),
            icon: Drives.driveIcon(drive),
            name: drive?.model || name,
            hidden: false,
            drive: drive,
            disk: rates
        };
    }

    function netEntry(net, kind, sameKind) {
        return {
            key: Devices.deviceKey("net", net.iface),
            type: "net",
            group: I18n.tr("Network"),
            hidden: Devices.isHiddenByDefault(kind),
            icon: netIcon(kind),
            name: sameKind === 1 && netKindName(kind) ? netKindName(kind) : net.iface,
            net: net,
            kind: kind
        };
    }

    function aggregateEntry(type) {
        return type === "disk" ? {
            key: "disk",
            type: "disk",
            group: I18n.tr("Storage", "system monitor device group: disks"),
            icon: "storage",
            name: I18n.tr("Disks", "process list window tab name"),
            hidden: false
        } : {
            key: "net",
            type: "net",
            group: I18n.tr("Network"),
            icon: "network_check",
            name: I18n.tr("Network"),
            hidden: false
        };
    }

    // The system monitor rail's devices in its order.
    function devices(options) {
        const showHidden = !!options?.showHidden;
        const processor = I18n.tr("Processor", "system monitor device group: CPU and memory");
        const items = [cpuEntry(processor), memoryEntry(processor)];
        for (const g of DgopService.availableGpus ?? [])
            items.push(gpuEntry(g));
        if (options?.aggregates)
            items.push(aggregateEntry("disk"));
        for (const d of wholeDisks())
            items.push(diskEntry(d.device, d));
        if (options?.aggregates)
            items.push(aggregateEntry("net"));
        const shown = sortedNets().filter(n => showHidden || !Devices.isHiddenByDefault(n.kind));
        for (const n of shown)
            items.push(netEntry(n.net, n.kind, shown.filter(s => s.kind === n.kind).length));
        return items;
    }

    // A popout's device list: CPU, memory, every GPU, the entry's drive or Disks, and the entry's interface or Network.
    // A drive or interface that isn't listed keeps its row under its own name.
    function popoutDevices(deviceKey) {
        const own = parseKey(deviceKey);
        const ownEntry = own.id && (own.type === "disk" || own.type === "net") ? device(deviceKey) ?? {
            key: Devices.deviceKey(own.type, own.id),
            type: own.type,
            icon: own.type === "net" ? "lan" : "hard_drive",
            name: own.id
        } : null;
        const list = devices().filter(e => e.type === "cpu" || e.type === "memory" || e.type === "gpu");
        list.push(ownEntry?.type === "disk" ? ownEntry : aggregateEntry("disk"));
        list.push(ownEntry?.type === "net" ? ownEntry : aggregateEntry("net"));
        return list;
    }

    // The key when it is listed, else the first device of its type.
    function popoutSelection(list, key, entryType) {
        if (list.some(e => e.key === key))
            return key;
        const type = parseKey(key).type || entryType;
        return (list.find(e => e.type === type) ?? list[0])?.key ?? "";
    }

    function device(key) {
        const p = parseKey(key);
        const processor = I18n.tr("Processor", "system monitor device group: CPU and memory");
        switch (p.type) {
        case "cpu":
            return p.id ? null : cpuEntry(processor);
        case "memory":
            return p.id ? null : memoryEntry(processor);
        case "gpu":
            {
                const g = gpuFor(p.id);
                return g ? gpuEntry(g) : null;
            }
        case "disk":
            {
                if (!p.id)
                    return aggregateEntry("disk");
                const d = (DgopService.diskRates ?? []).find(r => r.device === p.id) ?? null;
                return d || Drives.driveFor(p.id, DriveService.drives) ? diskEntry(p.id, d) : null;
            }
        case "net":
            {
                if (!p.id)
                    return aggregateEntry("net");
                const nets = (DgopService.netRates ?? []).map(n => ({
                            net: n,
                            kind: Devices.interfaceKind(n.iface, n.linkType)
                        }));
                const n = nets.find(e => e.net.iface === p.id);
                return n ? netEntry(n.net, n.kind, nets.filter(e => e.kind === n.kind).length) : null;
            }
        }
        return null;
    }

    function typeName(type) {
        switch (type) {
        case "cpu":
            return I18n.tr("CPU", "processor label in system monitor");
        case "memory":
            return I18n.tr("Memory", "system RAM label in system monitor");
        case "gpu":
            return I18n.tr("GPU");
        case "disk":
            return I18n.tr("Disks", "process list window tab name");
        case "net":
            return I18n.tr("Network");
        }
        return "";
    }

    function diskCount() {
        const names = (DgopService.diskRates ?? []).map(d => d.device).filter(n => Devices.isWholeDisk(n));
        for (const d of DriveService.drives ?? []) {
            if (Devices.isWholeDisk(d.name) && names.indexOf(d.name) < 0)
                names.push(d.name);
        }
        return names.length;
    }

    // Counts as properties so readers re-run only when a count changes, not on every sample.
    readonly property int gpuTotal: hostGpuCount()
    onGpuTotalChanged: resolveGpus()
    readonly property int diskTotal: diskCount()
    readonly property int netShownTotal: (DgopService.netRates ?? []).filter(n => !Devices.isHiddenByDefault(Devices.interfaceKind(n.iface, n.linkType))).length

    // Also runs when the configs change (profile apply, reload), since those can bring pending entries after the list.
    function resolveGpus() {
        if (gpuTotal > 0)
            Qt.callLater(adoptGpus);
    }

    function adoptGpus() {
        SettingsData.resolveSysmonGpus(DgopService.availableGpus);
    }

    Connections {
        target: SettingsData
        function onBarConfigsChanged() {
            SysmonService.resolveGpus();
        }
        function onDockConfigsChanged() {
            SysmonService.resolveGpus();
        }
    }

    Component.onCompleted: resolveGpus()

    // The type name while the type has a single device, otherwise the device's own name.
    function displayName(key) {
        const p = parseKey(key);
        if (!p.id)
            return typeName(p.type);
        const single = p.type === "gpu" ? gpuTotal <= 1 : p.type === "disk" ? diskTotal <= 1 : p.type === "net" ? netShownTotal <= 1 : true;
        if (single)
            return typeName(p.type);
        switch (p.type) {
        case "gpu":
            return gpuFor(p.id)?.displayName || typeName("gpu");
        case "disk":
            return Drives.driveFor(p.id, DriveService.drives)?.model || p.id;
        }
        return p.id;
    }

    function configTitle(config) {
        const names = [];
        for (const m of Array.from(config?.metrics ?? [])) {
            const name = m && m.on !== false ? displayName(m.device) : "";
            if (name && names.indexOf(name) < 0)
                names.push(name);
        }
        return names.join(", ");
    }

    function layoutName(id) {
        switch (id) {
        case "tiles":
            return I18n.tr("Tiles", "system monitor layout and style option");
        case "list":
            return I18n.tr("List", "noun, list view mode option");
        case "bars":
            return I18n.tr("Bars", "system monitor layout option: bar meters, not the shell bars", true);
        case "graphs":
            return I18n.tr("Graphs", "system monitor layout option");
        }
        return "";
    }

    function layoutIcon(id) {
        return ({
                tiles: "grid_view",
                list: "view_list",
                bars: "bar_chart",
                graphs: "show_chart"
            })[id] ?? "";
    }

    function valueLabel(type, id) {
        switch (type + "/" + id) {
        case "cpu/usage":
        case "gpu/usage":
            return I18n.tr("Usage", "chart legend: CPU or GPU utilization");
        case "cpu/temp":
        case "gpu/temp":
            return I18n.tr("Temperature");
        case "cpu/clock":
            return I18n.tr("Clock", "CPU clock speed", true);
        case "memory/used":
        case "disk/space":
            return I18n.tr("Used", "memory in use");
        case "memory/swap":
            return I18n.tr("Swap", "swap memory label in system monitor");
        case "gpu/vram":
            return I18n.tr("VRAM", "GPU video memory");
        case "gpu/power":
            return I18n.tr("Power", "battery stat label, charge or discharge rate in watts", true);
        case "disk/read":
            return I18n.tr("Disk read", "disk read rate");
        case "disk/write":
            return I18n.tr("Disk write", "disk write rate");
        case "net/down":
            return I18n.tr("Down", "network direction");
        case "net/up":
            return I18n.tr("Up", "network direction");
        }
        return "";
    }

    function shortValueLabel(type, id) {
        switch (id) {
        case "temp":
            return I18n.tr("Temp", "system monitor list card label, short for temperature");
        case "read":
            return I18n.tr("Read", "system monitor list card label, short for disk read");
        case "write":
            return I18n.tr("Write", "system monitor list card label, short for disk write");
        }
        return valueLabel(type, id);
    }

    function valueIcon(type, id) {
        switch (id) {
        case "temp":
            return "device_thermostat";
        case "clock":
            return "speed";
        case "power":
            return "bolt";
        case "swap":
            return "swap_horiz";
        case "vram":
            return "developer_board";
        case "read":
        case "down":
            return "download";
        case "write":
        case "up":
            return "upload";
        }
        return ({
                cpu: "memory",
                memory: "developer_board",
                gpu: "gpu",
                disk: "storage",
                net: "network_check"
            })[type] ?? "";
    }

    function positive(v) {
        return v > 0 ? v : null;
    }

    function activeGpu(id) {
        const g = gpuFor(id);
        return g && g.state === "active" && Devices.gpuMonitored(DgopService.gpuPciIds, g.pciId, g.busId) ? g : null;
    }

    function read(key, id, mount = "") {
        const p = parseKey(key);
        switch (p.type) {
        case "cpu":
            if (p.id)
                return null;
            if (id === "usage")
                return DgopService.cpuSampleCount === 0 ? null : DgopService.cpuUsage;
            if (id === "temp")
                return positive(DgopService.cpuTemperature);
            if (id === "clock")
                return positive(DgopService.cpuFrequency);
            return null;
        case "memory":
            if (p.id || DgopService.memoryInfo === null)
                return null;
            if (id === "used")
                return DgopService.memoryUsage;
            if (id === "swap")
                return DgopService.totalSwapKB > 0 ? DgopService.usedSwapKB / DgopService.totalSwapKB * 100 : null;
            return null;
        case "gpu":
            {
                const g = activeGpu(p.id);
                if (!g)
                    return null;
                if (id === "usage")
                    return g.usage ?? null;
                if (id === "temp")
                    return positive(g.temperature);
                if (id === "vram")
                    return g.memoryUsed != null && g.memoryTotal > 0 ? g.memoryUsed / g.memoryTotal * 100 : null;
                if (id === "power")
                    return g.power ?? null;
                return null;
            }
        case "disk":
            {
                if (id === "space")
                    return Drives.usedSpace(DriveService.drives, DgopService.diskMounts, p.id, mount)?.percent ?? null;
                if (id !== "read" && id !== "write")
                    return null;
                if (!p.id)
                    return id === "read" ? DgopService.diskReadRate : DgopService.diskWriteRate;
                const d = (DgopService.diskRates ?? []).find(r => r.device === p.id);
                return (id === "read" ? d?.readRate : d?.writeRate) ?? null;
            }
        case "net":
            {
                if (id !== "down" && id !== "up")
                    return null;
                if (!p.id)
                    return id === "down" ? DgopService.networkRxRate : DgopService.networkTxRate;
                const n = (DgopService.netRates ?? []).find(r => r.iface === p.id);
                return (id === "down" ? n?.rxRate : n?.txRate) ?? null;
            }
        }
        return null;
    }

    function asleep(key) {
        const p = parseKey(key);
        return p.type === "gpu" && gpuFor(p.id)?.state === "suspended";
    }

    // The entries a bar widget shows. A migrated GPU entry still waiting for its device id shows its card
    // and gives no entries until dgop lists the GPU.
    function widgetMetrics(entry) {
        if (SysmonCatalog.listOf(entry?.metrics))
            return SysmonCatalog.normalizeMetrics(entry.metrics);
        if (Number.isInteger(entry?.selectedGpuIndex)) {
            const key = SysmonCatalog.legacyGpuKey(entry, DgopService.availableGpus);
            return key ? SysmonCatalog.normalizeMetrics([
                {
                    device: key,
                    vals: ["temp"]
                }
            ]) : [];
        }
        return SysmonCatalog.normalizeMetrics([
            {
                device: "cpu",
                vals: ["usage"]
            }
        ]);
    }

    // Rail text and history for a devices() entry; the rates of the aggregates are the sums DgopService keeps.
    function summary(e) {
        switch (e.type) {
        case "cpu":
            return {
                value: DgopService.cpuSampleCount === 0 ? "—" : DgopService.cpuUsage.toFixed(0) + "%",
                values: DgopService.history("cpu", "usage"),
                maximum: 100
            };
        case "memory":
            return {
                value: DgopService.memoryInfo === null ? "—" : Format.formatBytes(DgopService.usedMemoryKB * 1024, true) + " / " + Format.formatBytes(DgopService.totalMemoryKB * 1024, true),
                values: DgopService.history("memory", "used"),
                maximum: 100
            };
        case "gpu":
            {
                const g = e.gpu;
                const suspended = g.state === "suspended";
                const off = !Devices.gpuMonitored(DgopService.gpuPciIds, g.pciId, g.busId);
                return {
                    value: off ? I18n.tr("Monitoring off", "GPU monitoring is turned off in settings") : suspended ? I18n.tr("Idle", "device state") : (g.usage != null ? Math.round(g.usage) + "%" : "—"),
                    values: suspended || off ? [] : DgopService.history(e.key, "usage"),
                    maximum: 100
                };
            }
        case "disk":
            {
                const r = e.key === "disk" ? DgopService.diskReadRate : e.disk?.readRate;
                const w = e.key === "disk" ? DgopService.diskWriteRate : e.disk?.writeRate;
                return {
                    value: Format.formatRateSumOr(r, w, "—"),
                    valueTooltip: valueLabel("disk", "read") + ": " + Format.formatRateOr(r, "—") + "\n" + valueLabel("disk", "write") + ": " + Format.formatRateOr(w, "—"),
                    values: DgopService.history(e.key, "read"),
                    secondaryValues: DgopService.history(e.key, "write")
                };
            }
        default:
            {
                const rx = e.key === "net" ? DgopService.networkRxRate : e.net?.rxRate;
                const tx = e.key === "net" ? DgopService.networkTxRate : e.net?.txRate;
                return {
                    value: Format.formatRateSumOr(rx, tx, "—"),
                    valueTooltip: valueLabel("net", "down") + ": " + Format.formatRateOr(rx, "—") + "\n" + valueLabel("net", "up") + ": " + Format.formatRateOr(tx, "—"),
                    values: DgopService.history(e.key, "down"),
                    secondaryValues: DgopService.history(e.key, "up")
                };
            }
        }
    }
}
