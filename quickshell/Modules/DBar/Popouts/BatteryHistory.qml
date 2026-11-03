import QtQuick
import qs.Services
import "BatteryHistory.js" as History

Item {
    id: root

    property bool active: false
    property string nativePath: ""
    property bool historyEnabled: true
    property var samples: []
    property real temperature: 0
    property real rangeEnd: 0
    property real rangeStart: 0
    property bool loading: false
    property string devicePath: ""
    property var previousSample: null
    property int generation: 0
    readonly property bool busAvailable: DMSService.isConnected && DMSService.capabilities.includes("dbus")

    onActiveChanged: reset()
    onNativePathChanged: {
        devicePath = "";
        previousSample = null;
        samples = [];
        temperature = 0;
        reset();
    }
    onBusAvailableChanged: {
        devicePath = "";
        previousSample = null;
        if (!busAvailable) {
            samples = [];
            temperature = 0;
        }
        reset();
    }

    function reset() {
        generation++;
        loading = false;
        refreshTimer.restart();
    }

    function refresh() {
        if (!active || !busAvailable || !nativePath || loading)
            return;
        loading = true;
        const request = ++generation;
        if (devicePath) {
            readDevice(devicePath, request);
            return;
        }
        DMSService.dbusCall("system", "org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.UPower", "EnumerateDevices", [], response => {
            if (request !== root.generation)
                return;
            const paths = response.result?.values?.[0];
            if (response.error || !Array.isArray(paths) || paths.length === 0) {
                root.loading = false;
                return;
            }
            let pending = paths.length;
            for (const path of paths) {
                DMSService.dbusGetAllProperties("system", "org.freedesktop.UPower", path, "org.freedesktop.UPower.Device", reply => {
                    if (request !== root.generation)
                        return;
                    pending--;
                    if (!reply.error && reply.result?.NativePath === root.nativePath) {
                        root.devicePath = path;
                        root.readHistory(reply.result, request);
                        return;
                    }
                    if (pending === 0 && !root.devicePath)
                        root.loading = false;
                });
            }
        });
    }

    function readDevice(path, request) {
        DMSService.dbusGetAllProperties("system", "org.freedesktop.UPower", path, "org.freedesktop.UPower.Device", response => {
            if (request !== root.generation)
                return;
            if (response.error || response.result?.NativePath !== root.nativePath) {
                root.devicePath = "";
                root.samples = [];
                root.temperature = 0;
                root.loading = false;
                return;
            }
            root.readHistory(response.result, request);
        });
    }

    function readHistory(properties, request) {
        temperature = typeof properties.Temperature === "number" && isFinite(properties.Temperature) ? properties.Temperature : 0;
        rangeEnd = Math.floor(Date.now() / 1000);
        if (!historyEnabled || !properties.HasHistory) {
            samples = [];
            loading = false;
            return;
        }
        fetchHistory(properties, request, 604800);
    }

    function fetchHistory(properties, request, timespan) {
        DMSService.dbusCall("system", "org.freedesktop.UPower", devicePath, "org.freedesktop.UPower.Device", "GetHistory", ["charge", timespan, 240], response => {
            if (request !== root.generation)
                return;
            const rows = History.normalize(response.result?.values?.[0], 0, root.rangeEnd);
            if (!response.error && rows.length === 0 && timespan > 0 && root.previousSample === null) {
                root.fetchHistory(properties, request, 0);
                return;
            }
            if (rows.length > 0 || timespan === 0)
                root.previousSample = rows[rows.length - 1] ?? [];
            const available = rows.length > 0 ? rows : root.previousSample?.length ? [root.previousSample] : [];
            root.rangeStart = Math.min(root.rangeEnd - 14400, Math.max(root.rangeEnd - 604800, available[0]?.[0] ?? root.rangeEnd));
            root.samples = response.error ? [] : History.windowSamples(available, root.rangeStart, root.rangeEnd, [root.rangeEnd, properties.Percentage, properties.State]);
            root.loading = false;
        });
    }

    Timer {
        id: refreshTimer
        interval: 0
        onTriggered: root.refresh()
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.active && root.busAvailable && root.nativePath !== ""
        onTriggered: root.refresh()
    }
}
