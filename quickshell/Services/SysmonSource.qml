pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import "SysmonCatalog.js" as Catalog
import "SysmonDevices.js" as Devices
import "Drives.js" as Drives
import "../Common/Format.js" as Format

// Holds the dgop modules, drive data and GPU ids its metrics need while active, and turns the metrics into rows.
QtObject {
    id: root

    property var metrics: []
    property int rangeSeconds: 60
    property string charts: "none"
    property bool processes: false
    property string processSort: "cpu"
    property int processCount: 3
    property bool system: false
    property bool active: false

    // Rebuilt once per sample: a sample assigns many DgopService properties one by one.
    property var rows: []

    readonly property var topProcesses: {
        if (!active || !processes)
            return [];
        const field = processSort === "memory" ? "memoryKB" : "cpu";
        return (DgopService.processes || []).slice().sort((a, b) => (b[field] || 0) - (a[field] || 0)).slice(0, processCount);
    }

    readonly property var modules: Catalog.modulesFor(metrics, {
        processes: processes,
        system: system
    })

    readonly property Ref dgopRef: Ref {
        service: DgopService
        modules: root.modules
        active: root.active && root.modules.length > 0
    }

    readonly property Ref driveRef: Ref {
        service: DriveService
        active: root.active && Catalog.needsDrives(root.metrics)
    }

    readonly property var gpuIds: {
        if (!active)
            return [];
        const ids = [];
        for (const m of metrics || []) {
            if (!m.on || Catalog.typeOf(m.device) !== "gpu")
                continue;
            const g = SysmonService.gpuFor(SysmonService.parseKey(m.device).id);
            if (g?.pciId && ids.indexOf(g.pciId) < 0)
                ids.push(g.pciId);
        }
        return ids;
    }
    property var heldGpuIds: []

    readonly property Connections dgopEvents: Connections {
        target: DgopService
        enabled: root.active
        function onStatsUpdated() {
            root.scheduleRebuild();
        }
        function onAvailableGpusChanged() {
            root.scheduleRebuild();
        }
    }

    readonly property Connections driveEvents: Connections {
        target: DriveService
        enabled: root.active
        function onDrivesChanged() {
            root.scheduleRebuild();
        }
    }

    readonly property string primaryConnection: NetworkService.primaryConnection

    onActiveChanged: scheduleRebuild()
    onPrimaryConnectionChanged: scheduleRebuild()
    onMetricsChanged: scheduleRebuild()
    onChartsChanged: scheduleRebuild()
    onRangeSecondsChanged: scheduleRebuild()
    onGpuIdsChanged: syncGpus(gpuIds)
    Component.onCompleted: {
        syncGpus(gpuIds);
        scheduleRebuild();
    }
    Component.onDestruction: syncGpus([])

    function scheduleRebuild() {
        if (active)
            Qt.callLater(rebuild);
        else if (rows.length > 0)
            rows = [];
    }

    // Device names only where a type shows more than one device, so a lone GPU reads "GPU".
    function rebuild() {
        const shown = active ? (metrics || []).filter(m => m.on) : [];
        rows = shown.map(m => buildRow(m, shown.some(o => o.device !== m.device && Catalog.typeOf(o.device) === Catalog.typeOf(m.device))));
    }

    // Add before remove so an id kept across a change never drops its last ref.
    function syncGpus(wanted) {
        const old = heldGpuIds;
        heldGpuIds = wanted;
        wanted.forEach(id => {
            if (old.indexOf(id) < 0)
                DgopService.addGpuPciId(id);
        });
        old.forEach(id => {
            if (wanted.indexOf(id) < 0)
                DgopService.removeGpuPciId(id);
        });
    }

    function detail(type, id, dev, vals, mount) {
        switch (type) {
        case "cpu":
            return Catalog.shortCpuName(DgopService.cpuModel);
        case "memory":
            return DgopService.totalMemoryKB > 0 ? Format.formatBytes(DgopService.usedMemoryKB * 1024, true) + " / " + Format.formatBytes(DgopService.totalMemoryKB * 1024, true) : "";
        case "gpu":
            return dev.gpu?.driver || "";
        case "disk":
            {
                if (mount) {
                    const mt = (DgopService.diskMounts ?? []).find(e => e.mount === mount);
                    return !mt ? "" : mt.used && mt.size ? mt.used + " / " + mt.size : mt.mount;
                }
                const s = vals.indexOf("space") >= 0 ? Drives.usedSpace(DriveService.drives, DgopService.diskMounts, id, "") : null;
                if (s?.used != null && s.total > 0)
                    return Drives.formatCapacity(s.used) + " / " + Drives.formatCapacity(s.total);
                return Drives.rootMostMount(dev.drive);
            }
        case "net":
            return id || NetworkService.primaryConnection || "";
        }
        return "";
    }

    function buildRow(m, named) {
        const type = Catalog.typeOf(m.device);
        const dev = SysmonService.device(m.device);
        const key = dev?.key ?? "";
        const asleep = !!dev && SysmonService.asleep(key);
        const live = !!dev && !asleep;
        const icon = dev?.icon ?? SysmonService.valueIcon(type, "");
        const rangeMs = rangeSeconds * 1000;
        const series = {};
        const hist = id => series[id] || (series[id] = live ? DgopService.history(key, id, rangeMs, 60) : []);
        const pair = type === "disk" ? ["read", "write"] : ["down", "up"];
        let peak = 0;
        const ratePeak = () => peak || (peak = Devices.rateAxisMax(hist(pair[0]), hist(pair[1]), 65536));
        const scale = kind => {
            switch (kind) {
            case "pct":
            case "temp":
                return 100;
            case "clock":
                return DgopService.cpuInfo?.maxFrequency > 0 ? DgopService.cpuInfo.maxFrequency : 0;
            case "power":
                return dev?.gpu?.powerLimit > 0 ? dev.gpu.powerLimit : 0;
            case "rate":
                return ratePeak();
            }
            return 0;
        };
        const maximum = (kind, values) => scale(kind) || Devices.rateAxisMax(values, [], 1);

        const mount = m.mount ?? "";
        const values = m.vals.map(id => {
            const kind = Catalog.valueDef(type, id).kind;
            const value = live ? SysmonService.read(key, id, mount) : null;
            const max = scale(kind);
            // Space history is recorded per device, not per mount, so a mount gets no trend.
            const history = charts === "all" && !(mount && id === "space") ? hist(id) : [];
            return {
                id: id,
                label: SysmonService.valueLabel(type, id),
                icon: id === "usage" || id === "used" || id === "space" ? icon : SysmonService.valueIcon(type, id),
                kind: kind,
                value: value,
                text: Catalog.formatValue(kind, value),
                shortText: Catalog.formatValue(kind, value, {
                    short: true
                }),
                fraction: value !== null && max > 0 ? Math.max(0, Math.min(1, value / max)) : 0,
                level: Catalog.level(type, id, value),
                history: history,
                maximum: maximum(kind, history)
            };
        });

        const main = values[0];
        const trend = {
            values: [],
            secondaryValues: [],
            maximum: 100
        };
        if (charts !== "none" && m.graph && live) {
            if (main.kind === "rate") {
                trend.values = hist(pair[0]);
                trend.secondaryValues = hist(pair[1]);
                trend.maximum = ratePeak();
            } else if (!(mount && main.id === "space")) {
                trend.values = hist(main.id);
                trend.maximum = maximum(main.kind, trend.values);
            }
        }

        return {
            key: key,
            type: type,
            name: named ? SysmonService.displayName(m.device) : SysmonService.typeName(type),
            icon: icon,
            detail: dev ? detail(type, SysmonService.parseKey(key).id, dev, m.vals, mount) : "",
            asleep: asleep,
            missing: !dev,
            graph: m.graph,
            values: values,
            trend: trend
        };
    }
}
