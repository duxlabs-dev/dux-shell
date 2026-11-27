pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Common
import qs.Services
import "Drives.js" as Drives
import "SysmonDevices.js" as SysmonDevices
import "SysmonHistory.js" as SysmonHistory
import "ProcessSort.js" as ProcessSort

Singleton {
    id: root
    readonly property var log: Log.scoped("DgopService")

    signal statsUpdated

    property int refCount: 0
    readonly property bool powerSaver: pollingActive && PowerProfileWatcher.currentProfile === PowerProfile.PowerSaver
    property int updateInterval: powerSaver ? 6000 : 3000
    property int primeGeneration: -1
    property bool isUpdating: false
    property bool pendingUpdate: false
    property int subscriptionGeneration: 0
    readonly property bool pollingActive: dgopAvailable && refCount > 0 && enabledModules.length > 0
    readonly property bool dgopAvailable: DMSService.isConnected && DMSService.capabilities.includes("dgop")
    property bool sessionGpuIdsSeeded: false
    property bool _metaWanted: false
    property bool _metaLoaded: false

    property var moduleRefCounts: ({})
    property var enabledModules: []
    property var gpuPciIds: []
    property var gpuPciIdRefCounts: ({})
    property int processLimit: 20
    // Views that search processes need every process, not just the top ones by CPU
    property int fullProcessListRefs: 0
    property string processSort: "cpu"
    property bool noCpu: false

    // Cursor data for accurate CPU calculations
    property string cpuCursor: ""
    property string procCursor: ""
    property string diskRateCursor: ""
    property string netRateCursor: ""
    property string gpuCursor: ""
    property int cpuSampleCount: 0

    property real cpuUsage: 0
    property real cpuFrequency: 0
    property real cpuTemperature: 0
    property int cpuCores: 1
    property string cpuModel: ""
    property var perCoreCpuUsage: []

    property real memoryUsage: 0
    property real totalMemoryMB: 0
    property real usedMemoryMB: 0
    property real freeMemoryMB: 0
    property real availableMemoryMB: 0
    property int totalMemoryKB: 0
    property int usedMemoryKB: 0
    property int totalSwapKB: 0
    property int usedSwapKB: 0

    property real networkRxRate: 0
    property real networkTxRate: 0
    property var lastNetworkStats: null
    property var networkInterfaces: []

    property real diskReadRate: 0
    property real diskWriteRate: 0
    property var lastDiskStats: null
    property var diskMounts: []
    property bool diskMountsRequested: false
    property var diskDevices: []
    property var diskRates: []
    property var netRates: []
    property var memoryInfo: null
    property var bios: null
    property var cpuInfo: null
    property var sensors: []
    property var memoryModules: null
    property var availableModules: []

    property var processes: []
    property var allProcesses: []
    property string currentSort: "cpu"
    property bool sortAscending: false
    property var availableGpus: []
    // availableGpus plus the cards bound to a VM, which only the system info lists.
    property var detectedGpus: []

    property string kernelVersion: ""
    property string distribution: ""
    property string hostname: ""
    property string architecture: ""
    property string loadAverage: ""
    property int processCount: 0
    property int threadCount: 0
    property int openFileCount: 0
    property string initSystem: ""
    property string bootTime: ""
    property string motherboard: ""
    property string biosVersion: ""
    property string uptime: ""
    property string shortUptime: ""

    readonly property int historySize: 60
    readonly property int historyRetentionMs: 1800000
    property var historyStore: null
    property int historyRevision: 0

    // Bucket averages (NaN = gap) for a device's value; bindings that call it update per recorded sample.
    function history(deviceKey, value, rangeMs, points) {
        if (historyRevision === 0 || !historyStore)
            return [];
        const interval = updateInterval;
        const span = rangeMs ?? historySize * interval;
        const buckets = Math.min(points ?? historySize, Math.max(1, Math.round(span / interval)));
        return SysmonHistory.range(historyStore, SysmonHistory.key(deviceKey, value), span, buckets, 15000, Date.now());
    }

    // Deprecated for plugins, use history(deviceKey, value, rangeMs, points).
    readonly property var cpuHistory: legacyHistory("cpu", "usage", 1)
    readonly property var memoryHistory: legacyHistory("memory", "used", 1)
    readonly property var networkHistory: ({
            "rx": legacyHistory("net", "down", 1024),
            "tx": legacyHistory("net", "up", 1024)
        })
    readonly property var diskHistory: ({
            "read": legacyHistory("disk", "read", 1048576),
            "write": legacyHistory("disk", "write", 1048576)
        })

    function legacyHistory(deviceKey, value, divisor) {
        return history(deviceKey, value).filter(v => isFinite(v)).map(v => v / divisor);
    }

    function ensureMeta() {
        _metaWanted = true;
        if (_metaLoaded || !dgopAvailable)
            return;
        _metaLoaded = true;
        initializeModules();
        initializeSystemMetadata();
        initializeGpuMetadata();
    }

    function addRef(modules = null) {
        ensureMeta();
        refCount++;
        let modulesChanged = false;

        if (modules) {
            const modulesToAdd = Array.isArray(modules) ? modules : [modules];
            for (const module of modulesToAdd) {
                const currentCount = moduleRefCounts[module] || 0;
                moduleRefCounts[module] = currentCount + 1;

                // Add to enabled modules if not already there
                if (enabledModules.indexOf(module) === -1) {
                    enabledModules.push(module);
                    modulesChanged = true;
                }
            }
        }

        if (modulesChanged) {
            subscriptionGeneration++;
            primeGeneration = subscriptionGeneration;
        }

        if (hasModule("system"))
            updateUptime();

        // Deferred so refs added together (a window and its pages) share one request.
        if (modulesChanged || refCount === 1) {
            enabledModules = enabledModules.slice(); // Force property change
            moduleRefCounts = Object.assign({}, moduleRefCounts); // Force property change
            Qt.callLater(updateAllStats);
        } else if (gpuPciIds.length > 0 && refCount > 0) {
            // If we have GPU PCI IDs and active modules, make sure to update
            // This handles the case where PCI IDs were loaded after modules were added
            Qt.callLater(updateAllStats);
        }
    }

    // Searching only the top processes by CPU makes idle matches appear and
    // vanish between refreshes (#3641), so a search asks for the whole list.
    function requestFullProcessList() {
        fullProcessListRefs++;
        if (fullProcessListRefs === 1)
            updateAllStats();
    }

    function releaseFullProcessList() {
        fullProcessListRefs = Math.max(0, fullProcessListRefs - 1);
    }

    function removeRef(modules = null) {
        refCount = Math.max(0, refCount - 1);
        let modulesChanged = false;

        if (modules) {
            const modulesToRemove = Array.isArray(modules) ? modules : [modules];
            for (const module of modulesToRemove) {
                const currentCount = moduleRefCounts[module] || 0;
                if (currentCount > 1) {
                    moduleRefCounts[module] = currentCount - 1;
                } else if (currentCount === 1) {
                    delete moduleRefCounts[module];
                    const index = enabledModules.indexOf(module);
                    if (index > -1) {
                        enabledModules.splice(index, 1);
                        modulesChanged = true;
                    }
                }
            }
        }

        if (!modulesChanged)
            return;
        subscriptionGeneration++;
        enabledModules = enabledModules.slice();
        moduleRefCounts = Object.assign({}, moduleRefCounts);
        releaseUnusedData();
        pendingUpdate = pollingActive && isUpdating;
        if (!pollingActive)
            primeTimer.stop();
    }

    function hasModule(module) {
        return refCount > 0 && (enabledModules.includes(module) || enabledModules.includes("all"));
    }

    function releaseUnusedData() {
        if (!hasModule("cpu")) {
            cpuCursor = "";
            cpuSampleCount = 0;
            perCoreCpuUsage = [];
            cpuInfo = null;
        }
        if (!hasModule("memory"))
            memoryInfo = null;
        if (!hasModule("disk-rate")) {
            diskRateCursor = "";
            diskRates = [];
        }
        if (!hasModule("net-rate")) {
            netRateCursor = "";
            netRates = [];
        }
        if (!hasModule("gpu"))
            gpuCursor = "";
        if (!hasModule("sensors"))
            sensors = [];
        if (!hasModule("memory-modules"))
            memoryModules = null;
        if (!hasModule("network")) {
            networkInterfaces = [];
            lastNetworkStats = null;
            networkRxRate = 0;
            networkTxRate = 0;
        }
        if (!hasModule("disk")) {
            diskDevices = [];
            lastDiskStats = null;
            diskReadRate = 0;
            diskWriteRate = 0;
        }
        if (!hasModule("processes")) {
            procCursor = "";
            allProcesses = [];
            processes = [];
        } else if (!hasModule("process-gpu") || !hasModule("process-io") || !hasModule("process-net") || !hasModule("process-members")) {
            const noGpu = !hasModule("process-gpu");
            const noIo = !hasModule("process-io");
            const noNet = !hasModule("process-net");
            const noMembers = !hasModule("process-members");
            allProcesses = allProcesses.map(p => Object.assign({}, p, noGpu ? {
                    "gpu": null,
                    "gpuVideo": null,
                    "vramKB": null,
                    "gpuGttKB": null,
                    "gpuUnmonitored": true
                } : {}, noIo ? {
                    "diskRead": null,
                    "diskWrite": null
                } : {}, noNet ? {
                    "connections": null,
                    "localConnections": null,
                    "remotes": [],
                    "netRx": null,
                    "netTx": null,
                    "netPartial": false
                } : {}, noMembers ? {
                    "children": []
                } : {}));
            applySorting();
        }
    }

    function setGpuMonitoring(pciId, on) {
        if (!pciId)
            return;
        const ids = SessionData.enabledGpuPciIds ? SessionData.enabledGpuPciIds.slice() : [];
        const idx = ids.indexOf(pciId);
        if (on && idx === -1) {
            ids.push(pciId);
            addGpuPciId(pciId);
        } else if (!on && idx !== -1) {
            ids.splice(idx, 1);
            removeGpuPciId(pciId);
        } else {
            return;
        }
        SessionData.setEnabledGpuPciIds(ids);
        if (refCount > 0)
            updateAllStats();
    }

    function gpuHeldByWidget(pciId) {
        const id = String(pciId).toLowerCase();
        const held = Object.keys(gpuPciIdRefCounts).some(k => k.toLowerCase() === id && gpuPciIdRefCounts[k] > 0);
        return held && !(SessionData.enabledGpuPciIds || []).some(e => String(e).toLowerCase() === id);
    }

    function addGpuPciId(pciId) {
        ensureMeta();
        const currentCount = gpuPciIdRefCounts[pciId] || 0;
        gpuPciIdRefCounts[pciId] = currentCount + 1;

        // Add to gpuPciIds array if not already there
        if (!gpuPciIds.includes(pciId)) {
            gpuPciIds = gpuPciIds.concat([pciId]);
        }

        gpuPciIdRefCounts = Object.assign({}, gpuPciIdRefCounts);
    }

    function removeGpuPciId(pciId) {
        const currentCount = gpuPciIdRefCounts[pciId] || 0;
        if (currentCount > 1) {
            gpuPciIdRefCounts[pciId] = currentCount - 1;
        } else if (currentCount === 1) {
            // Remove completely when count reaches 0
            delete gpuPciIdRefCounts[pciId];
            const index = gpuPciIds.indexOf(pciId);
            if (index > -1) {
                gpuPciIds = gpuPciIds.slice();
                gpuPciIds.splice(index, 1);
            }
            if (gpuPciIds.length === 0)
                gpuCursor = "";

            // Clear temperature data for this GPU when no longer monitored
            if (availableGpus && availableGpus.length > 0) {
                const updatedGpus = availableGpus.slice();
                for (var i = 0; i < updatedGpus.length; i++) {
                    if (updatedGpus[i].pciId === pciId) {
                        updatedGpus[i] = Object.assign({}, updatedGpus[i], {
                            "temperature": 0
                        });
                    }
                }
                availableGpus = updatedGpus;
            }
        }

        // Force property change notification
        gpuPciIdRefCounts = Object.assign({}, gpuPciIdRefCounts);
    }

    function updateAllStats() {
        if (!pollingActive) {
            pendingUpdate = false;
            return;
        }
        if (isUpdating) {
            pendingUpdate = true;
            return;
        }

        const params = buildMetaParams();
        if (!params) {
            pendingUpdate = false;
            return;
        }

        isUpdating = true;
        const generation = subscriptionGeneration;
        const asRoot = unlocked;
        request("dgop.meta", params, response => {
            if (!response.result) {
                log.warn("dgop.meta failed:", response.error || "empty result");
            } else if (pollingActive && generation === subscriptionGeneration) {
                parseData(response.result);
                // Per-process rates of a module just added need a second sample; take it soon, like the first CPU sample.
                if (generation === primeGeneration) {
                    primeGeneration = -1;
                    primeTimer.restart();
                }
            }
            if (asRoot && unlockLoading && ++_rootSamples >= 2)
                unlockLoading = false;

            isUpdating = false;
            if (pendingUpdate && pollingActive) {
                pendingUpdate = false;
                // A reply dropped for a module change is refetched at once; otherwise wait so CPU deltas aren't noise.
                if (generation !== subscriptionGeneration)
                    Qt.callLater(updateAllStats);
                else
                    primeTimer.restart();
            }
        });
    }

    // After a user action. Waits so CPU deltas aren't noise.
    function refreshSoon() {
        if (pollingActive)
            primeTimer.restart();
    }

    function initializeGpuMetadata() {
        if (!dgopAvailable)
            return;
        DMSService.sendRequest("dgop.gpu", null, response => {
            if (!response.result) {
                log.warn("dgop.gpu failed:", response.error || "empty result");
                return;
            }
            // A poll may have answered first with live stats; this identity-only list would blank them.
            if (availableGpus.length === 0)
                parseData(response.result);
        });
    }

    // On-demand fields of one process (IO totals, swap, open files, systemd unit); callback gets null on failure.
    function fetchProcessDetail(pid, callback) {
        request("dgop.process", {
            "pid": pid
        }, response => callback(response.result ?? null));
    }

    // Unlocked: a root helper (one polkit prompt) answers dgop requests and runs process actions.
    readonly property bool unlocked: helper.running && helper.ready
    readonly property bool unlocking: helper.running && !helper.ready
    // Unlocked, but the rates read as root aren't in yet: they need two samples.
    property bool unlockLoading: false
    property int _rootSamples: 0
    property var _helperCallbacks: ({})
    property int _helperNextId: 1

    // lock() closes stdin; a closed channel is not reopened by a later start, so turn it back on first.
    function unlock() {
        if (helper.running)
            return;
        helper.stdinEnabled = true;
        helper.running = true;
    }

    function lock() {
        if (helper.running)
            helper.stdinEnabled = false;
    }

    // Through the unlocked helper while it runs, otherwise through the DMS background process.
    function request(method, params, callback) {
        if (!unlocked) {
            DMSService.sendRequest(method, params, callback);
            return;
        }
        const id = _helperNextId++;
        if (callback)
            _helperCallbacks[id] = callback;
        helper.write(JSON.stringify({
            "id": id,
            "method": method,
            "params": params ?? {}
        }) + "\n");
    }

    Process {
        id: helper

        property bool ready: false
        property string lastError: ""

        command: ["pkexec", Proc.dmsBin, "sysmon-helper"]
        stdinEnabled: true
        onStarted: {
            ready = false;
            write(JSON.stringify({
                "id": 0,
                "method": "dgop.modules"
            }) + "\n");
        }

        onExited: (code, status) => {
            // pkexec exits 126 when the password prompt is dismissed; anything else before ready is a real failure.
            if (!ready && code !== 0 && code !== 126) {
                root.log.warn("sysmon helper failed:", code, lastError);
                ToastService.showError(I18n.tr("Failed to unlock", "toast title when the system monitor could not get root access"), lastError);
            }
            ready = false;
            root.unlockLoading = false;
            lastError = "";
            const pending = root._helperCallbacks;
            root._helperCallbacks = {};
            for (const id in pending)
                pending[id]({
                    "error": "locked"
                });
        }
        stderr: SplitParser {
            onRead: line => helper.lastError = line
        }
        stdout: SplitParser {
            onRead: line => {
                let response;
                try {
                    response = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (response.id === 0) {
                    helper.ready = !response.error;
                    if (helper.ready && root.pollingActive) {
                        root._rootSamples = 0;
                        root.unlockLoading = true;
                        Qt.callLater(root.updateAllStats);
                    }
                    return;
                }
                const callback = root._helperCallbacks[response.id];
                delete root._helperCallbacks[response.id];
                if (callback)
                    callback(response);
            }
        }
    }

    function initializeModules() {
        DMSService.sendRequest("dgop.modules", null, response => {
            if (!response.result) {
                log.warn("dgop.modules failed:", response.error || "empty result");
                return;
            }
            availableModules = response.result.available ?? [];
            if (pollingActive)
                updateAllStats();
        });
    }

    // GetMeta fails the whole call on an unknown module, so never send one dgop didn't list.
    function isModuleAvailable(module) {
        if (availableModules.length > 0)
            return availableModules.includes(module);
        return !["sensors", "memory-modules", "process-gpu", "process-io", "process-net", "process-members"].includes(module);
    }

    function initializeSystemMetadata() {
        if (!dgopAvailable)
            return;
        DMSService.sendRequest("dgop.meta", {
            modules: ["hardware", "system"]
        }, response => {
            if (!response.result) {
                log.warn("Initial system metadata request failed:", response.error || "empty result");
                return;
            }
            parseData(response.result);
        });
    }

    function initializeDiskMounts() {
        if (!dgopAvailable || diskMountsRequested || hasModule("diskmounts"))
            return;
        if (!SettingsData.controlCenterWidgets.some(widget => widget.id === "diskUsage" && widget.enabled !== false))
            return;
        diskMountsRequested = true;
        const previousMounts = diskMounts;
        DMSService.sendRequest("dgop.meta", {
            modules: ["diskmounts"]
        }, response => {
            if (!response.result?.diskmounts) {
                log.warn("Initial disk mounts request failed:", response.error || "empty result");
                return;
            }
            if (diskMounts !== previousMounts)
                return;
            diskMounts = response.result.diskmounts;
        });
    }

    Connections {
        target: SettingsData
        function onControlCenterWidgetsChanged() {
            root.initializeDiskMounts();
        }
    }

    function buildMetaParams() {
        if (enabledModules.length === 0)
            return null;

        // Without enabled GPUs the gpu module adds nothing to the identity list fetched once by initializeGpuMetadata.
        const finalModules = enabledModules.filter(module => ((module !== "gpu" && module !== "process-gpu") || gpuPciIds.length > 0) && (module === "all" || isModuleAvailable(module)));

        const params = {};
        if (enabledModules.indexOf("all") !== -1) {
            params.modules = ["all"];
        } else if (finalModules.length > 0) {
            params.modules = finalModules;
        } else {
            return null;
        }

        // Cursor data enables accurate CPU percentages between samples
        if ((enabledModules.includes("cpu") || enabledModules.includes("all")) && cpuCursor) {
            params.cpuCursor = cpuCursor;
        }
        if ((enabledModules.includes("processes") || enabledModules.includes("all")) && procCursor) {
            params.procCursor = procCursor;
        }
        if (enabledModules.includes("disk-rate") && diskRateCursor) {
            params.diskRateCursor = diskRateCursor;
        }
        if (enabledModules.includes("net-rate") && netRateCursor) {
            params.netRateCursor = netRateCursor;
        }
        if (finalModules.includes("net-rate")) {
            params.netRateAllInterfaces = true;
        }
        if (finalModules.includes("gpu") && gpuCursor) {
            params.gpuCursor = gpuCursor;
        }

        params.gpuPciIds = gpuPciIds;

        if (enabledModules.indexOf("processes") !== -1 || enabledModules.indexOf("all") !== -1) {
            const sort = dgopSort();
            params.sort = sort || "cpu";
            // 0 means no limit in dgop
            params.limit = fullProcessListRefs > 0 ? 0 : 100;
            if (noCpu) {
                params.noCpu = true;
            }
        }

        return params;
    }

    // dgop cuts the limit after its own sort, so a limited list is only right when that sort is the table's.
    function dgopSort() {
        if (sortAscending)
            return "";
        switch (currentSort) {
        case "cpu":
        case "memory":
        case "pid":
            return currentSort;
        case "gpu":
        case "vram":
            return gpuPciIds.length > 0 && enabledModules.includes("process-gpu") && isModuleAvailable("process-gpu") ? currentSort : "";
        }
        return "";
    }

    function parseData(data) {
        const sampleTime = Date.now();
        const samples = [];
        const departed = [];
        let diskDeparted = null;
        if (hasModule("cpu") && data.cpu) {
            const cpu = data.cpu;
            cpuSampleCount++;

            cpuUsage = Math.round((cpu.usage || 0) * 10) / 10;
            cpuFrequency = Math.round(cpu.frequency || 0);
            cpuTemperature = Math.round(cpu.temperature || 0);
            cpuCores = cpu.count || 1;
            cpuModel = cpu.model || "";
            perCoreCpuUsage = cpu.coreUsage || [];
            cpuInfo = cpu;
            samples.push([SysmonHistory.key("cpu", "usage"), cpuUsage]);
            if (cpuTemperature > 0)
                samples.push([SysmonHistory.key("cpu", "temp"), cpuTemperature]);
            if (cpuFrequency > 0)
                samples.push([SysmonHistory.key("cpu", "clock"), cpuFrequency]);
            for (let i = 0; i < perCoreCpuUsage.length; i++)
                samples.push([SysmonHistory.key("cpu", "thread" + i), perCoreCpuUsage[i]]);

            if (cpu.cursor) {
                cpuCursor = cpu.cursor;
            }

            if (cpuSampleCount === 1) {
                primeTimer.restart();
            }
        }

        if (hasModule("memory") && data.memory) {
            const mem = data.memory;
            const totalKB = mem.total || 0;
            const availableKB = mem.available || 0;
            const freeKB = mem.free || 0;
            const usedKB = mem.used !== undefined ? mem.used : (totalKB - availableKB);

            totalMemoryMB = Math.round(totalKB / 1024);
            availableMemoryMB = Math.round(availableKB / 1024);
            freeMemoryMB = Math.round(freeKB / 1024);
            usedMemoryMB = Math.round(usedKB / 1024);
            const rawMemUsage = mem.usedPercent !== undefined ? mem.usedPercent : (totalKB > 0 ? ((totalKB - availableKB) / totalKB) * 100 : 0);
            memoryUsage = Math.round(rawMemUsage * 10) / 10;

            totalMemoryKB = totalKB;
            usedMemoryKB = usedKB;
            totalSwapKB = mem.swaptotal || 0;
            usedSwapKB = (mem.swaptotal || 0) - (mem.swapfree || 0);

            memoryInfo = mem;
            samples.push([SysmonHistory.key("memory", "used"), memoryUsage]);
            if (totalSwapKB > 0)
                samples.push([SysmonHistory.key("memory", "swap"), usedSwapKB / totalSwapKB * 100]);
        }

        if (hasModule("network") && data.network && Array.isArray(data.network)) {
            networkInterfaces = data.network;

            let totalRx = 0;
            let totalTx = 0;
            for (const iface of data.network) {
                totalRx += iface.rx || 0;
                totalTx += iface.tx || 0;
            }

            if (lastNetworkStats) {
                const timeDiff = Math.max(1, sampleTime - lastNetworkStats.time) / 1000;
                const rxDiff = totalRx - lastNetworkStats.rx;
                const txDiff = totalTx - lastNetworkStats.tx;
                networkRxRate = Math.max(0, rxDiff / timeDiff);
                networkTxRate = Math.max(0, txDiff / timeDiff);
                samples.push([SysmonHistory.key("net", "down"), networkRxRate], [SysmonHistory.key("net", "up"), networkTxRate]);
            }
            lastNetworkStats = {
                "time": sampleTime,
                "rx": totalRx,
                "tx": totalTx
            };
        }

        if (hasModule("disk") && data.disk && Array.isArray(data.disk)) {
            diskDevices = data.disk;

            const wholeDisks = SysmonDevices.sumWholeDisks(data.disk, "read", "write");
            const totalRead = wholeDisks.read * 512;
            const totalWrite = wholeDisks.write * 512;

            if (lastDiskStats) {
                const timeDiff = Math.max(1, sampleTime - lastDiskStats.time) / 1000;
                const readDiff = totalRead - lastDiskStats.read;
                const writeDiff = totalWrite - lastDiskStats.write;
                diskReadRate = Math.max(0, readDiff / timeDiff);
                diskWriteRate = Math.max(0, writeDiff / timeDiff);
                samples.push([SysmonHistory.key("disk", "read"), diskReadRate], [SysmonHistory.key("disk", "write"), diskWriteRate]);
            }
            lastDiskStats = {
                "time": sampleTime,
                "read": totalRead,
                "write": totalWrite
            };
        }

        if (hasModule("disk-rate") && data.diskrate && Array.isArray(data.diskrate.disks)) {
            const hadCursor = diskRateCursor !== "";
            const rates = [];
            for (const d of data.diskrate.disks) {
                const entry = {
                    device: d.device,
                    readRate: d.readrate,
                    writeRate: d.writerate,
                    readTotal: d.readtotal,
                    writeTotal: d.writetotal
                };
                if (d.busy !== undefined)
                    entry.busy = d.busy;
                if (d.responseTime !== undefined)
                    entry.responseTime = d.responseTime;
                rates.push(entry);
            }
            diskRates = rates;
            if (data.diskrate.cursor)
                diskRateCursor = data.diskrate.cursor;
            const whole = rates.filter(r => SysmonDevices.isWholeDisk(r.device));
            const keys = whole.map(r => SysmonDevices.deviceKey("disk", r.device));
            if (hadCursor) {
                for (let i = 0; i < whole.length; i++)
                    samples.push([SysmonHistory.key(keys[i], "read"), whole[i].readRate || 0], [SysmonHistory.key(keys[i], "write"), whole[i].writeRate || 0]);
            }
            diskDeparted = ["disk", keys];
            departed.push(diskDeparted);
        }

        if (hasModule("diskmounts") && Array.isArray(data.diskmounts)) {
            const space = Drives.usedSpace(DriveService.drives, data.diskmounts, "", "");
            if (space)
                samples.push([SysmonHistory.key("disk", "space"), space.percent]);
            for (const d of DriveService.drives || []) {
                const dev = d.name || d.device;
                if (!SysmonDevices.isWholeDisk(dev))
                    continue;
                const own = Drives.usedSpace(DriveService.drives, data.diskmounts, dev, "");
                if (!own)
                    continue;
                const key = SysmonDevices.deviceKey("disk", dev);
                samples.push([SysmonHistory.key(key, "space"), own.percent]);
                if (diskDeparted)
                    diskDeparted[1].push(key);
            }
        }

        if (hasModule("net-rate") && data.netrate && Array.isArray(data.netrate.interfaces)) {
            const hadCursor = netRateCursor !== "";
            const rates = data.netrate.interfaces.map(i => {
                const entry = {
                    iface: i.interface,
                    rxRate: i.rxrate,
                    txRate: i.txrate,
                    rxTotal: i.rxtotal,
                    txTotal: i.txtotal
                };
                for (const key of ["mtu", "speed", "duplex", "linkType", "driver", "ipv4", "ipv6"]) {
                    if (i[key] !== undefined)
                        entry[key] = i[key];
                }
                return entry;
            });
            netRates = rates;
            if (data.netrate.cursor)
                netRateCursor = data.netrate.cursor;
            const keys = rates.map(r => SysmonDevices.deviceKey("net", r.iface));
            if (hadCursor) {
                for (let i = 0; i < rates.length; i++)
                    samples.push([SysmonHistory.key(keys[i], "down"), rates[i].rxRate || 0], [SysmonHistory.key(keys[i], "up"), rates[i].txRate || 0]);
            }
            departed.push(["net", keys]);
        }

        const gpuData = data.gpu?.gpus ?? data.gpus;
        if (Array.isArray(gpuData)) {
            detectedGpus = gpuData.map(gpu => Object.assign({}, gpu, {
                    "displayName": gpu.displayName || gpu.name || "Unknown GPU",
                    "fullName": gpu.fullName || gpu.name || "Unknown GPU",
                    "temperature": gpu.temperature || 0
                }));
            availableGpus = SysmonDevices.hostGpus(detectedGpus);
        }

        // dgop fills state and stats only for the GPUs in gpuPciIds.
        if (hasModule("gpu") && Array.isArray(data.gpu?.gpus)) {
            gpuCursor = data.gpu.cursor ?? "";
            const read = data.gpu.gpus.filter(g => g.state);
            for (const g of read) {
                if (g.state !== "active" || g.usage === undefined)
                    continue;
                const key = SysmonDevices.deviceKey("gpu", SysmonDevices.gpuSlot(g));
                samples.push([SysmonHistory.key(key, "usage"), g.usage]);
                if (g.memoryUsed !== undefined && g.memoryTotal > 0)
                    samples.push([SysmonHistory.key(key, "vram"), g.memoryUsed / g.memoryTotal * 100]);
                if (g.temperature > 0)
                    samples.push([SysmonHistory.key(key, "temp"), g.temperature]);
                if (g.power !== undefined)
                    samples.push([SysmonHistory.key(key, "power"), g.power]);
            }
            departed.push(["gpu", data.gpu.gpus.map(g => SysmonDevices.deviceKey("gpu", SysmonDevices.gpuSlot(g)))]);
        }

        if (hasModule("sensors") && data.sensors && Array.isArray(data.sensors.sensors))
            sensors = data.sensors.sensors;

        if (hasModule("memory-modules") && data.memorymodules)
            memoryModules = data.memorymodules;

        recordHistory(sampleTime, samples, departed);

        if (hasModule("diskmounts") && data.diskmounts) {
            diskMountsRequested = true;
            diskMounts = data.diskmounts || [];
        }

        if (hasModule("processes") && data.processes && Array.isArray(data.processes)) {
            if (data.cursor) {
                procCursor = data.cursor;
            }

            allProcesses = data.processes.map(proc => toProcess(proc));
            applySorting();
        }

        if (data.system?.boottime) {
            bootTime = data.system.boottime;
            updateUptime();
        }

        if (hasModule("system") && data.system) {
            const sys = data.system;
            loadAverage = sys.loadavg || "";
            processCount = sys.processes || 0;
            threadCount = sys.threads || 0;
            openFileCount = sys.openFiles || 0;
        }

        const hwData = data.hardware || ((data.hostname || data.kernel || data.distro || data.arch) ? data : null);
        if (hwData) {
            hostname = hwData.hostname || "";
            kernelVersion = hwData.kernel || "";
            distribution = hwData.distro || "";
            architecture = hwData.arch || "";
            initSystem = hwData.initSystem || "";
            motherboard = (hwData.bios && hwData.bios.motherboard) || "";
            biosVersion = (hwData.bios && hwData.bios.version) || "";
            bios = hwData.bios ?? null;
        }

        statsUpdated();
    }

    function recordHistory(time, samples, departed) {
        if (!historyStore && (samples.length === 0 || !pollingActive))
            return;
        if (!historyStore)
            historyStore = SysmonHistory.create(900);
        let changed = false;
        for (const d of departed)
            changed = SysmonHistory.dropDevices(historyStore, d[0], d[1]) || changed;
        changed = SysmonHistory.record(historyStore, time, samples) || changed;
        changed = SysmonHistory.prune(historyStore, time - historyRetentionMs) || changed;
        if (changed)
            historyRevision++;
    }

    // A merged row's members carry their root's pid, so the root's own row has a key apart from the merged one.
    function toProcess(proc, memberOf) {
        return {
            "pid": proc.pid || 0,
            "ppid": proc.ppid || 0,
            "cpu": proc.cpu || 0,
            "memoryPercent": proc.memoryPercent || proc.pssPercent || 0,
            "memoryKB": proc.memoryKB || proc.pssKB || 0,
            "rssKB": proc.rssKB ?? null,
            "command": proc.command || "",
            "fullCommand": proc.fullCommand || "",
            "executablePath": proc.executablePath || "",
            "username": proc.username || "",
            "childCount": proc.childCount || 0,
            "pticks": proc.pticks || 0,
            "status": proc.status || "",
            "threads": proc.threads ?? null,
            "nice": proc.nice ?? null,
            "startTime": proc.startTime ?? null,
            "gpu": gpuPciIds.length > 0 ? (proc.gpu ?? null) : null,
            "gpuVideo": gpuPciIds.length > 0 ? (proc.gpuVideo ?? null) : null,
            "vramKB": gpuPciIds.length > 0 ? (proc.vramKB ?? null) : null,
            "gpuGttKB": gpuPciIds.length > 0 ? (proc.gpuGttKB ?? null) : null,
            "gpuUnmonitored": gpuPciIds.length > 0 ? (proc.gpuUnmonitored ?? false) : true,
            "diskRead": proc.diskRead ?? null,
            "diskWrite": proc.diskWrite ?? null,
            "connections": proc.connections ?? null,
            "localConnections": proc.localConnections ?? null,
            "remotes": proc.remotes ?? [],
            "netRx": proc.netRx ?? null,
            "netTx": proc.netTx ?? null,
            "netPartial": proc.netPartial ?? false,
            "displayName": (proc.command && proc.command.length > 15) ? proc.command.substring(0, 15) + "..." : (proc.command || ""),
            "key": memberOf === undefined ? String(proc.pid || 0) : memberOf + "/" + (proc.pid || 0),
            "memberOf": memberOf,
            "children": hasModule("process-members") ? (proc.children ?? []).map(c => toProcess(c, proc.pid || 0)) : []
        };
    }

    function findProcess(pid, memberOf) {
        const row = allProcesses.find(p => p.pid === (memberOf ?? pid));
        return memberOf === undefined ? row : row?.children.find(c => c.pid === pid);
    }

    function formatSystemMemory(memoryKB) {
        const mem = memoryKB || 0;
        if (mem === 0) {
            return "--";
        }
        if (mem < 1024 * 1024) {
            return (mem / 1024).toFixed(0) + " MB";
        } else {
            return (mem / (1024 * 1024)).toFixed(1) + " GB";
        }
    }

    function updateUptime() {
        if (!bootTime) {
            uptime = "";
            shortUptime = "";
            return;
        }

        const bootDate = new Date(bootTime.replace(" ", "T"));
        if (isNaN(bootDate.getTime())) {
            uptime = "";
            shortUptime = "";
            return;
        }

        const now = new Date();
        const seconds = Math.floor((now - bootDate) / 1000);
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);

        const parts = [];
        if (days > 0)
            parts.push(`${days} day${days === 1 ? "" : "s"}`);
        if (hours > 0)
            parts.push(`${hours} hour${hours === 1 ? "" : "s"}`);
        if (minutes > 0)
            parts.push(`${minutes} minute${minutes === 1 ? "" : "s"}`);

        uptime = parts.length > 0 ? `up ${parts.join(", ")}` : `up ${seconds} seconds`;

        var shortStr = "up";
        if (days > 0)
            shortStr += ` ${days}d`;
        if (hours > 0)
            shortStr += ` ${hours}h`;
        if (minutes > 0)
            shortStr += ` ${minutes}m`;
        shortUptime = shortStr;
    }

    function setSortBy(newSortBy) {
        if (newSortBy !== currentSort)
            changeSort(newSortBy, false);
    }

    function toggleSort(column) {
        changeSort(column, column === currentSort ? !sortAscending : false);
    }

    // A limited list sorted by something else lacks rows the new order needs, so fetch again right away.
    function changeSort(column, ascending) {
        const before = dgopSort();
        currentSort = column;
        sortAscending = ascending;
        applySorting();
        if (before !== "" && dgopSort() !== before)
            updateAllStats();
    }

    // Name, PID and priority read ascending by default, so sortAscending inverts for them.
    function processComparator() {
        const naturallyAscending = currentSort === "name" || currentSort === "pid" || currentSort === "nice";
        return ProcessSort.compare(currentSort, sortAscending !== naturallyAscending);
    }

    function applySorting() {
        if (!allProcesses || allProcesses.length === 0)
            return;

        const sorted = allProcesses.slice().sort(processComparator());
        processes = sorted.slice(0, processLimit);
    }

    Timer {
        id: primeTimer
        interval: Timing.second
        onTriggered: root.updateAllStats()
    }

    Timer {
        id: updateTimer
        interval: root.updateInterval
        running: root.pollingActive
        repeat: true
        triggeredOnStart: true
        onTriggered: root.updateAllStats()
    }

    // Frees the store once its newest sample has aged out of every range.
    Timer {
        id: historyRetentionTimer
        interval: root.historyRetentionMs
        onTriggered: {
            root.historyStore = null;
            root.historyRevision++;
        }
    }

    onPollingActiveChanged: {
        if (pollingActive)
            historyRetentionTimer.stop();
        else if (historyStore)
            historyRetentionTimer.restart();
    }

    onDgopAvailableChanged: {
        if (!dgopAvailable) {
            availableModules = [];
            _metaLoaded = false;
            return;
        }

        if (_metaWanted)
            ensureMeta();
        initializeDiskMounts();

        if (!sessionGpuIdsSeeded && SessionData.enabledGpuPciIds && SessionData.enabledGpuPciIds.length > 0) {
            sessionGpuIdsSeeded = true;
            for (const pciId of SessionData.enabledGpuPciIds) {
                addGpuPciId(pciId);
            }
        }
    }
}
