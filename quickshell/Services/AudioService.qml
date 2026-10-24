pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/GSettings.js" as GSettings

Singleton {
    id: root
    readonly property var log: Log.scoped("AudioService")

    // Keep PipeWire completely out of the FreeBSD process. Loading the
    // Quickshell PipeWire service attempts a connection immediately, so it lives
    // in PipewireAudioBackend.qml and is only instantiated after OS detection.
    property bool audioBackendDetected: false
    property bool freebsdAudio: false
    property var nativeSinks: []
    property var nativeSources: []
    property var nativeSink: null
    property var nativeSource: null
    property bool nativeAudioSyncing: false
    property var pendingFreeBsdVolumeWrites: ({})
    property double lastFreeBsdLocalChangeMs: 0
    property int deviceRevision: 0

    readonly property var pipewireBackend: pipewireBackendLoader.item
    readonly property bool pipewireReady: pipewireBackend?.ready ?? false
    readonly property var pipewireNodes: pipewireBackend?.nodes ?? []
    readonly property var allNodes: freebsdAudio ? nativeSinks.concat(nativeSources) : pipewireNodes
    readonly property var sink: freebsdAudio ? nativeSink : (pipewireBackend?.defaultSink ?? null)
    readonly property var source: freebsdAudio ? nativeSource : (pipewireBackend?.defaultSource ?? null)

    property int refCount: 0

    function addRef() {
        refCount++;
    }

    function removeRef() {
        refCount = Math.max(0, refCount - 1);
    }

    function isPipewireVideoSource(node) {
        return !freebsdAudio && (pipewireBackend?.isVideoSource(node) ?? false);
    }

    Loader {
        id: pipewireBackendLoader
        active: root.audioBackendDetected && !root.freebsdAudio
        source: active ? "PipewireAudioBackend.qml" : ""
        onLoaded: {
            root.rebuildTypedNodeLists();
            root.deviceRevision++;
        }
    }

    Connections {
        target: pipewireBackendLoader.item
        ignoreUnknownSignals: true
        function onNodesUpdated() {
            root.adoptPendingCardSink();
            if (root.refCount === 0)
                return;
            root.rebuildTypedNodeLists();
            root.deviceRevision++;
        }
    }

    Component {
        id: freeBsdNodeComponent
        QtObject {
            id: deviceNode
            property var service: null
            property string name: ""
            property string description: ""
            property string nick: description
            property string mixerDevice: ""
            property string pcmName: ""
            property int pcmUnit: -1
            property string mixerControl: "vol"
            property bool isSink: true
            property bool isStream: false
            property var properties: ({
                    "media.class": isSink ? "Audio/Sink" : "Audio/Source",
                    "device.api": "oss",
                    "device.name": pcmName,
                    "device.description": description
                })
            property QtObject audio: QtObject {
                property real volume: 0.0
                property bool muted: false
                onVolumeChanged: {
                    if (deviceNode.service?.freebsdAudio && !deviceNode.service.nativeAudioSyncing)
                        deviceNode.service.queueFreeBsdMixerVolume(deviceNode, volume);
                }
                onMutedChanged: {
                    if (deviceNode.service?.freebsdAudio && !deviceNode.service.nativeAudioSyncing)
                        deviceNode.service.setFreeBsdMixerMute(deviceNode, muted);
                }
            }
        }
    }

    readonly property bool soundsAvailable: MultimediaService.available
    property bool playersRequested: false
    property bool soundThemeSupported: false
    property bool soundThemeResolved: false
    property string pendingSoundPlayer: ""
    property var availableSoundThemes: []
    property string currentSoundTheme: ""
    property var soundFilePaths: ({})

    readonly property var volumeChangeSound: soundsLoader.item?.volumeChangeSound ?? null
    readonly property var powerPlugSound: soundsLoader.item?.powerPlugSound ?? null
    readonly property var powerUnplugSound: soundsLoader.item?.powerUnplugSound ?? null
    readonly property var normalNotificationSound: soundsLoader.item?.normalNotificationSound ?? null
    readonly property var criticalNotificationSound: soundsLoader.item?.criticalNotificationSound ?? null
    readonly property var loginSound: soundsLoader.item?.loginSound ?? null
    readonly property var mediaDevices: soundsLoader.item?.mediaDevices ?? null
    property real notificationsVolume: 1.0
    property bool notificationsAudioMuted: false

    Loader {
        id: soundsLoader
        active: root.playersRequested && root.soundsAvailable
        source: "AudioSoundPlayers.qml"
    }

    property var deviceAliases: ({})
    property string wireplumberConfigPath: Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation)) + "/wireplumber/wireplumber.conf.d/51-dms-audio-aliases.conf"
    property bool wireplumberReloading: false

    property var sinkPorts: ({})
    property var cards: []
    property var pendingCardSwitch: null
    readonly property var switchableOutputPorts: root.collectSwitchableOutputPorts(root.cards, SessionData.hiddenOutputDeviceNames ?? [])

    readonly property int sinkMaxVolume: {
        if (freebsdAudio)
            return 100;
        const name = sink?.name ?? "";
        if (!name)
            return 100;
        return SessionData.deviceMaxVolumes[name] ?? 100;
    }

    readonly property int sinkVolumePercent: Math.min(sinkMaxVolume, Math.round((sink?.audio?.volume ?? 0) * 100))
    readonly property int sourceVolumePercent: Math.round((source?.audio?.volume ?? 0) * 100)
    readonly property int wheelVolumeStep: SettingsData.audioWheelScrollAmount

    property bool monoSettingSupported: false
    property string monoSettingBackend: ""

    signal micMuteChanged
    signal micVolumeChanged
    signal audioOutputCycled(string deviceName, string deviceIcon)
    signal deviceAliasChanged(string nodeName, string newAlias)
    signal wireplumberReloadStarted
    signal wireplumberReloadCompleted(bool success)

    function getMaxVolumePercent(node) {
        if (freebsdAudio)
            return 100;
        if (!node?.name)
            return 100;
        return SessionData.deviceMaxVolumes[node.name] ?? 100;
    }

    Connections {
        target: SessionData
        function onDeviceMaxVolumesChanged() {
            if (!root.sink?.audio)
                return;
            const maxVol = root.sinkMaxVolume;
            const currentPercent = Math.round(root.sink.audio.volume * 100);
            if (currentPercent > maxVol)
                root.sink.audio.volume = maxVol / 100;
        }
    }

    Process {
        id: loginSoundChecker
        onExited: exitCode => {
            if (exitCode === 0) {
                playLoginSound();
            }
        }
    }

    function isSinkAvailable(node) {
        const ports = sinkPorts[node?.name]?.ports;
        return !ports?.length || ports.some(port => port.availability !== "no");
    }

    function getAvailableSinks() {
        if (freebsdAudio) {
            const hidden = SessionData.hiddenOutputDeviceNames ?? [];
            return nativeSinks.filter(node => !hidden.includes(node.name));
        }
        const hidden = SessionData.hiddenOutputDeviceNames ?? [];
        return root.pipewireNodes.filter(node => node.audio && node.isSink && (SettingsData.audioShowStreamDevices || !node.isStream) && !hidden.includes(node.name) && isSinkAvailable(node));
    }

    property var typedSinks: []
    property var typedSources: []

    function rebuildTypedNodeLists() {
        if (freebsdAudio) {
            typedSinks = nativeSinks.slice();
            typedSources = nativeSources.slice();
            deviceRevision++;
            return;
        }
        const newSinks = [];
        const newSources = [];
        for (const node of root.pipewireNodes) {
            if (!node?.audio || (node.isStream && !SettingsData.audioShowStreamDevices))
                continue;
            if (node.isSink)
                newSinks.push(node);
            else
                newSources.push(node);
        }
        typedSinks = newSinks;
        typedSources = newSources;
    }

    Connections {
        target: SettingsData
        function onAudioShowStreamDevicesChanged() {
            root.rebuildTypedNodeLists();
        }
    }

    Connections {
        target: SettingsData
        function onAudioMonoChanged() {
            if (root.monoSettingSupported) {
                root.setMonoSetting(SettingsData.audioMono);
            }
        }
    }

    function setSink(node): bool {
        if (!node)
            return false;
        if (freebsdAudio)
            return setFreeBsdDefaultDevice(node);
        root.pipewireBackend.setDefaultSink(node);
        return true;
    }

    function setSource(node): bool {
        if (!node)
            return false;
        if (freebsdAudio)
            return setFreeBsdDefaultDevice(node);
        root.pipewireBackend.setDefaultSource(node);
        return true;
    }

    function setDefaultSinkByName(name) {
        if (!name)
            return false;
        if (refCount === 0)
            rebuildTypedNodeLists();
        for (const node of typedSinks) {
            if (node?.name === name)
                return setSink(node);
        }
        return false;
    }

    function setDefaultSourceByName(name) {
        if (!name)
            return false;
        if (refCount === 0)
            rebuildTypedNodeLists();
        for (const node of typedSources) {
            if (node?.name === name)
                return setSource(node);
        }
        return false;
    }

    Process {
        running: root.pipewireReady
        command: ["env", "LC_ALL=C", "pactl", "subscribe"]
        onStarted: root.refreshSinkPorts()
        onExited: root.sinkPorts = ({})
        stdout: SplitParser {
            onRead: line => {
                if (line.includes(" on card #"))
                    Qt.callLater(root.refreshSinkPorts);
            }
        }
    }

    function refreshSinkPorts(callback) {
        if (freebsdAudio) {
            sinkPorts = ({});
            if (callback)
                callback();
            return;
        }
        // ensure that parsed labels are in English
        Proc.runCommand("audio-list-sink-ports", ["env", "LC_ALL=C", "pactl", "list", "sinks"], (output, exitCode) => {
            if (exitCode === 0)
                root.sinkPorts = root.parseSinkPorts(output);
            if (callback)
                callback();
        }, 0);
    }

    function getSinkPorts(node) {
        return sinkPorts[node?.name] ?? null;
    }

    function sinkHasMultiplePorts(node) {
        return (sinkPorts[node?.name]?.ports?.length ?? 0) > 1;
    }

    function setSinkPort(sinkName, portName, callback) {
        if (freebsdAudio) {
            if (callback)
                callback(false, I18n.tr("Port switching is not available with the FreeBSD native audio backend"));
            return;
        }
        Proc.runCommand("audio-set-sink-port", ["env", "LC_ALL=C", "pactl", "set-sink-port", sinkName, portName], (output, exitCode) => {
            const ok = exitCode === 0;
            if (callback)
                callback(ok, ok ? I18n.tr("Port switched", "audio sink port switched successful message") : (output || I18n.tr("Failed to switch port", "audio sink port switch failure message")));
            if (ok)
                Qt.callLater(() => root.refreshSinkPorts());
        }, 0);
    }

    function parseSinkPorts(text) {
        const result = {};
        const lines = (text || "").split("\n");
        let current = null;
        let inPorts = false;

        function commit() {
            if (current && current.name)
                result[current.name] = {
                    active: current.active,
                    ports: current.ports
                };
        }

        for (const rawLine of lines) {
            const line = rawLine.trim();

            if (/^Sink #\d+/.test(line)) {
                commit();
                current = {
                    name: null,
                    active: "",
                    ports: []
                };
                inPorts = false;
                continue;
            }

            if (!current)
                continue;

            if (line.startsWith("Name:")) {
                current.name = line.substring(5).trim();
                inPorts = false;
                continue;
            }

            if (line === "Ports:") {
                inPorts = true;
                continue;
            }

            if (line.startsWith("Active Port:")) {
                current.active = line.substring(12).trim();
                inPorts = false;
                continue;
            }

            if (inPorts) {
                // name up to first ": ", meta is the trailing "(...)", description is whatever's in between
                const match = line.match(/^(.+?):\s+(.*)\s+\(([^()]*)\)$/);
                if (!match)
                    continue;
                const meta = match[3];
                let availability = "unknown";
                if (meta.includes("not available"))
                    availability = "no";
                else if (/\bavailable\b/.test(meta))
                    availability = "yes";
                current.ports.push({
                    name: match[1],
                    description: match[2],
                    availability: availability,
                    priority: parseInt(meta.match(/priority:?\s*(\d+)/)?.[1] ?? "0", 10)
                });
            }
        }

        commit();
        return result;
    }

    function refreshCards(callback) {
        if (freebsdAudio) {
            cards = [];
            if (callback)
                callback();
            return;
        }
        Proc.runCommand("audio-list-cards", ["env", "LC_ALL=C", "pactl", "list", "cards"], (output, exitCode) => {
            root.cards = exitCode === 0 ? root.parseCards(output) : [];
            if (callback)
                callback();
        }, 0);
    }

    function parseCards(text) {
        const cards = [];
        let card = null;
        let port = null;
        let section = "";

        function commit() {
            if (!card?.name)
                return;
            const props = card.props;
            card.description = props["device.description"] || props["device.nick"] || props["alsa.card_name"] || card.name;
            cards.push(card);
        }

        function applyProperty(target, line) {
            const match = line.match(/^([^=\s]+)\s*=\s*"(.*)"$/);
            if (match)
                target[match[1]] = match[2];
        }

        function addProfile(target, line) {
            const match = line.match(/^(.+?):\s+(.*)\s+\(([^()]*)\)$/);
            if (!match)
                return;
            const meta = match[3];
            target.profiles[match[1]] = {
                description: match[2],
                priority: parseInt(meta.match(/priority:?\s*(\d+)/)?.[1] ?? "0", 10),
                available: !/available:\s*no/.test(meta)
            };
        }

        function addPort(target, line) {
            const match = line.match(/^(.+?):\s+(.*)\s+\(([^()]*)\)$/);
            if (!match)
                return null;
            const meta = match[3];
            let availability = "unknown";
            if (meta.includes("not available"))
                availability = "no";
            else if (/\bavailable\b/.test(meta))
                availability = "yes";
            const entry = {
                name: match[1],
                description: match[2],
                type: (meta.match(/type:\s*([^,]+)/)?.[1] ?? "").trim().toLowerCase(),
                availability: availability,
                profiles: [],
                props: {}
            };
            target.ports.push(entry);
            return entry;
        }

        for (const rawLine of (text || "").split("\n")) {
            const line = rawLine.trim();

            if (/^Card #\d+/.test(line)) {
                commit();
                card = {
                    name: "",
                    description: "",
                    activeProfile: "",
                    profiles: {},
                    ports: [],
                    props: {}
                };
                port = null;
                section = "";
                continue;
            }

            if (!card)
                continue;

            if (line.startsWith("Name:")) {
                card.name = line.substring(5).trim();
                section = "";
                continue;
            }
            if (line === "Properties:") {
                section = port ? "portProps" : "cardProps";
                continue;
            }
            if (line === "Profiles:") {
                section = "profiles";
                continue;
            }
            if (line === "Ports:") {
                section = "ports";
                continue;
            }
            if (line.startsWith("Active Profile:")) {
                card.activeProfile = line.substring(15).trim();
                section = "";
                continue;
            }
            if (line.startsWith("Part of profile(s):")) {
                if (port)
                    port.profiles = line.substring(19).split(",").map(s => s.trim()).filter(s => s);
                section = "ports";
                continue;
            }

            switch (section) {
            case "cardProps":
                applyProperty(card.props, line);
                break;
            case "portProps":
                if (port)
                    applyProperty(port.props, line);
                break;
            case "profiles":
                addProfile(card, line);
                break;
            case "ports":
                port = addPort(card, line) ?? port;
                break;
            }
        }

        commit();
        return cards;
    }

    function bestOutputProfile(card, port) {
        const candidates = port.profiles.filter(name => name.startsWith("output:") && card.profiles[name]?.available);
        if (candidates.length === 0)
            return "";
        candidates.sort((a, b) => card.profiles[b].priority - card.profiles[a].priority);
        return candidates[0];
    }

    function profileSinkNames(cardName, profile) {
        if (!cardName.startsWith("alsa_card."))
            return [];
        const prefix = "alsa_output." + cardName.substring(10) + ".";
        return profile.split("+").filter(part => part.startsWith("output:")).map(part => prefix + part.substring(7));
    }

    function collectSwitchableOutputPorts(cards, hiddenSinkNames) {
        const entries = [];
        for (const card of cards || []) {
            if (!card.activeProfile || card.activeProfile === "pro-audio")
                continue;
            for (const port of card.ports) {
                if (port.availability === "no" || port.profiles.includes(card.activeProfile))
                    continue;
                if (port.profiles.some(name => name.startsWith("input:")))
                    continue;
                const profile = bestOutputProfile(card, port);
                if (!profile)
                    continue;
                if (profileSinkNames(card.name, profile).some(name => hiddenSinkNames.includes(name)))
                    continue;
                const product = port.props["device.product.name"] || "";
                entries.push({
                    cardName: card.name,
                    cardDescription: card.description,
                    portName: port.name,
                    profile: profile,
                    icon: port.type === "hdmi" ? "tv" : "speaker",
                    title: product ? `${port.description} [${product}]` : port.description
                });
            }
        }
        return entries;
    }

    function sinkBelongsToCard(node, cardName) {
        if (!node || node.isStream || !cardName)
            return false;
        if (node.properties?.["device.name"] === cardName)
            return true;
        if (!cardName.startsWith("alsa_card."))
            return false;
        return (node.name || "").startsWith("alsa_output." + cardName.substring(10) + ".");
    }

    function activateOutputPort(entry, callback) {
        if (freebsdAudio) {
            if (callback)
                callback(false, I18n.tr("Output profile switching is not available with the FreeBSD native audio backend"));
            return;
        }
        if (!entry?.cardName || !entry.profile)
            return;
        const previousSinks = root.pipewireNodes.filter(n => n.isSink && sinkBelongsToCard(n, entry.cardName)).map(n => n.name);
        Proc.runCommand("audio-set-card-profile", ["env", "LC_ALL=C", "pactl", "set-card-profile", entry.cardName, entry.profile], (output, exitCode) => {
            const ok = exitCode === 0;
            if (ok) {
                root.pendingCardSwitch = {
                    cardName: entry.cardName,
                    portName: entry.portName,
                    exclude: previousSinks
                };
                pendingCardSwitchTimer.restart();
                root.adoptPendingCardSink();
            }
            if (callback)
                callback(ok, ok ? I18n.tr("Output switched", "audio card profile switched successful message") : (output || I18n.tr("Failed to switch output", "audio card profile switch failure message")));
            Qt.callLater(() => {
                root.refreshCards();
                root.refreshSinkPorts();
            });
        }, 0);
    }

    function adoptPendingCardSink() {
        const pending = pendingCardSwitch;
        if (!pending)
            return;
        const node = root.pipewireNodes.find(n => n.isSink && sinkBelongsToCard(n, pending.cardName) && !pending.exclude.includes(n.name));
        if (!node)
            return;
        pendingCardSwitch = null;
        pendingCardSwitchTimer.stop();
        setSink(node);
        setSinkPort(node.name, pending.portName);
    }

    Timer {
        id: pendingCardSwitchTimer
        interval: 5000
        onTriggered: root.pendingCardSwitch = null
    }

    function cycleAudioOutputDirection(forward) {
        const sinks = getAvailableSinks();
        const currentName = root.sink?.name ?? "";
        const currentIndex = sinks.findIndex(s => s.name === currentName);
        if (sinks.length === 0 || (sinks.length === 1 && currentIndex === 0))
            return null;

        let nextIndex;
        if (forward) {
            nextIndex = (currentIndex + 1) % sinks.length;
        } else {
            nextIndex = (currentIndex - 1 + sinks.length) % sinks.length;
        }
        const nextSink = sinks[nextIndex];
        setDefaultSinkByName(nextSink.name);
        const name = displayName(nextSink);
        audioOutputCycled(name, sinkIcon(nextSink));
        return name;
    }

    function cycleAudioOutput() {
        return cycleAudioOutputDirection(true);
    }

    function getDeviceAlias(nodeName) {
        if (!nodeName)
            return null;
        return deviceAliases[nodeName] || null;
    }

    function hasDeviceAlias(nodeName) {
        if (!nodeName)
            return false;
        return deviceAliases.hasOwnProperty(nodeName) && deviceAliases[nodeName] !== null && deviceAliases[nodeName] !== "";
    }

    function setDeviceAlias(nodeName, customAlias) {
        if (!nodeName) {
            log.error("Cannot set alias - nodeName is empty");
            return false;
        }

        if (!customAlias || customAlias.trim() === "") {
            return removeDeviceAlias(nodeName);
        }

        const trimmedAlias = customAlias.trim();

        const updated = Object.assign({}, deviceAliases);
        updated[nodeName] = trimmedAlias;
        deviceAliases = updated;

        const btDevice = BluetoothService.deviceForNodeName(nodeName);
        if (btDevice)
            btDevice.name = trimmedAlias;

        writeWireplumberConfig();
        deviceAliasChanged(nodeName, trimmedAlias);
        return true;
    }

    function removeDeviceAlias(nodeName) {
        if (!nodeName)
            return false;

        if (!hasDeviceAlias(nodeName))
            return false;

        const updated = Object.assign({}, deviceAliases);
        delete updated[nodeName];
        deviceAliases = updated;

        // Empty BlueZ alias write resets to the device's real name.
        const btDevice = BluetoothService.deviceForNodeName(nodeName);
        if (btDevice)
            btDevice.name = "";

        writeWireplumberConfig();
        deviceAliasChanged(nodeName, "");
        return true;
    }

    function writeWireplumberConfig() {
        if (freebsdAudio)
            return;
        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation)) + "/wireplumber/wireplumber.conf.d";
        const configContent = generateWireplumberConfig();

        const shellCmd = `mkdir -p "${configDir}" && cat > "${wireplumberConfigPath}" << 'EOFCONFIG'
${configContent}
EOFCONFIG
`;

        Proc.runCommand("writeWireplumberConfig", ["sh", "-c", shellCmd], (output, exitCode) => {
            if (exitCode !== 0) {
                log.error("Failed to write WirePlumber config. Exit code:", exitCode);
                log.error("Error output:", output);
                ToastService.showError(I18n.tr("Failed to save audio config"), output || "");
                return;
            }

            reloadWireplumberConfig();
        }, 0);
    }

    function generateWireplumberConfig() {
        let config = "# Generated by Dux Shell - Audio Device Aliases\n";
        config += "# Do not edit manually - changes will be overwritten\n";
        config += "# Last updated: " + new Date().toISOString() + "\n\n";

        const aliasKeys = Object.keys(deviceAliases);
        if (aliasKeys.length === 0) {
            config += "# No device aliases configured\n";
            return config;
        }

        const alsaAliases = [];
        const bluezAliases = [];
        const otherAliases = [];

        for (const nodeName of aliasKeys) {
            const alias = deviceAliases[nodeName];
            if (!alias)
                continue;

            const rule = {
                nodeName: nodeName,
                alias: alias
            };

            if (nodeName.includes("alsa")) {
                alsaAliases.push(rule);
            } else if (nodeName.includes("bluez")) {
                bluezAliases.push(rule);
            } else {
                otherAliases.push(rule);
            }
        }

        if (alsaAliases.length > 0) {
            config += "monitor.alsa.rules = [\n";
            for (let i = 0; i < alsaAliases.length; i++) {
                const rule = alsaAliases[i];
                config += "  {\n";
                config += `    matches = [ { "node.name" = "${rule.nodeName}" } ]\n`;
                config += `    actions = { update-props = { "node.description" = "${rule.alias}" } }\n`;
                config += "  }";
                if (i < alsaAliases.length - 1)
                    config += ",";
                config += "\n";
            }
            config += "]\n\n";
        }

        if (bluezAliases.length > 0) {
            config += "monitor.bluez.rules = [\n";
            for (let i = 0; i < bluezAliases.length; i++) {
                const rule = bluezAliases[i];
                config += "  {\n";
                config += `    matches = [ { "node.name" = "${rule.nodeName}" } ]\n`;
                config += `    actions = { update-props = { "node.description" = "${rule.alias}" } }\n`;
                config += "  }";
                if (i < bluezAliases.length - 1)
                    config += ",";
                config += "\n";
            }
            config += "]\n\n";
        }

        if (otherAliases.length > 0) {
            config += "# Other device aliases (RAOP, USB, and other devices)\n";
            config += "wireplumber.rules = [\n";
            for (let i = 0; i < otherAliases.length; i++) {
                const rule = otherAliases[i];
                config += "  {\n";
                config += `    matches = [\n`;
                config += `      { "node.name" = "${rule.nodeName}" }\n`;
                config += `    ]\n`;
                config += `    actions = {\n`;
                config += `      update-props = {\n`;
                config += `        "node.description" = "${rule.alias}"\n`;
                config += `        "node.nick" = "${rule.alias}"\n`;
                config += `        "device.description" = "${rule.alias}"\n`;
                config += `      }\n`;
                config += `    }\n`;
                config += "  }";
                if (i < otherAliases.length - 1)
                    config += ",";
                config += "\n";
            }
            config += "]\n";
        }

        return config;
    }

    function reloadWireplumberConfig() {
        if (freebsdAudio)
            return;
        if (wireplumberReloading) {
            return;
        }

        wireplumberReloading = true;
        wireplumberReloadStarted();

        if (!SessionService.systemctlCommandAvailable) {
            Proc.runCommand("restartWireplumber", ["sh", "-c", "pkill -x wireplumber; sleep 1"], () => {
                Quickshell.execDetached(["wireplumber"]);
                wireplumberReloading = false;
                ToastService.showInfo(I18n.tr("Audio system restarted"), I18n.tr("Device names updated"));
                wireplumberReloadCompleted(true);
            }, 5000);
            return;
        }

        Proc.runCommand("restartWireplumber", ["systemctl", "--user", "restart", "wireplumber"], (output, exitCode) => {
            wireplumberReloading = false;

            if (exitCode === 0) {
                ToastService.showInfo(I18n.tr("Audio system restarted"), I18n.tr("Device names updated"));
                wireplumberReloadCompleted(true);
            } else {
                log.error("Failed to restart WirePlumber:", output);
                ToastService.showError(I18n.tr("Failed to restart audio system"), output);
                wireplumberReloadCompleted(false);
            }
        }, 5000);
    }

    function loadDeviceAliases() {
        const configPath = wireplumberConfigPath;

        Proc.runCommand("readWireplumberConfig", ["cat", configPath], (output, exitCode) => {
            if (exitCode !== 0) {
                log.debug("No existing WirePlumber config found");
                return;
            }

            const aliases = {};
            const lines = output.split('\n');
            let currentNodeName = null;

            for (const line of lines) {
                const nodeNameMatch = line.match(/"node\.name"\s*=\s*"([^"]+)"/);
                if (nodeNameMatch) {
                    currentNodeName = nodeNameMatch[1];
                }

                const descriptionMatch = line.match(/"node\.description"\s*=\s*"([^"]+)"/);
                if (descriptionMatch && currentNodeName) {
                    aliases[currentNodeName] = descriptionMatch[1];
                    currentNodeName = null;
                }
            }

            if (Object.keys(aliases).length > 0) {
                deviceAliases = aliases;
                log.debug("Loaded", Object.keys(aliases).length, "device aliases");
            }
        }, 0);
    }

    Connections {
        target: root.sink?.audio ?? null
        enabled: SettingsData.soundsEnabled && SettingsData.soundVolumeChanged

        function onVolumeChanged() {
            if (SessionData.suppressOSD)
                return;
            root.playVolumeChangeSoundIfEnabled();
        }
    }

    Connections {
        target: root.source?.audio ?? null

        function onMutedChanged() {
            root.micMuteChanged();
        }
    }

    function checkSoundThemeSupport() {
        Proc.runCommand("checkSoundThemeSupport", ["sh", "-c", GSettings.getCmd("org.gnome.desktop.sound", "theme-name")], (output, exitCode) => {
            soundThemeSupported = (output || "").trim().length > 0;
            if (!soundThemeSupported) {
                markSoundThemeResolved();
                return;
            }
            scanSoundThemes();
            getCurrentSoundTheme();
        }, 0);
    }

    function scanSoundThemes() {
        const xdgDataDirs = Quickshell.env("XDG_DATA_DIRS");
        const searchPaths = xdgDataDirs && xdgDataDirs.trim() !== "" ? xdgDataDirs.split(":").concat(Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericDataLocation))) : ["/usr/share", "/usr/local/share", Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericDataLocation))];

        const basePaths = searchPaths.map(p => p + "/sounds").join(" ");
        const script = `
            for base_dir in ${basePaths}; do
                [ -d "$base_dir" ] || continue
                for theme_dir in "$base_dir"/*; do
                    [ -d "$theme_dir/stereo" ] || continue
                    basename "$theme_dir"
                done
            done | sort -u
        `;

        Proc.runCommand("scanSoundThemes", ["sh", "-c", script], (output, exitCode) => {
            if (exitCode === 0 && output.trim()) {
                const themes = output.trim().split('\n').filter(t => t && t.length > 0);
                availableSoundThemes = themes;
            } else {
                availableSoundThemes = [];
            }
        }, 0);
    }

    function getCurrentSoundTheme() {
        Proc.runCommand("getCurrentSoundTheme", ["sh", "-c", GSettings.getCmd("org.gnome.desktop.sound", "theme-name")], (output, exitCode) => {
            currentSoundTheme = output.trim();
            log.debug("Current system sound theme:", currentSoundTheme || "none");
            if (currentSoundTheme && SettingsData.useSystemSoundTheme) {
                discoverSoundFiles(currentSoundTheme);
                return;
            }
            markSoundThemeResolved();
        }, 0);
    }

    function setSoundTheme(themeName) {
        if (!themeName || themeName === currentSoundTheme) {
            return;
        }

        Proc.runCommand("setSoundTheme", ["sh", "-c", GSettings.setCmd("org.gnome.desktop.sound", "theme-name", themeName)], (output, exitCode) => {
            if (exitCode === 0) {
                currentSoundTheme = themeName;
                if (SettingsData.useSystemSoundTheme) {
                    discoverSoundFiles(themeName);
                }
            }
        }, 0);
    }

    function selectSoundTheme(themeName) {
        if (!themeName) {
            SettingsData.set("useSystemSoundTheme", false);
            return;
        }
        if (themeName === currentSoundTheme) {
            SettingsData.set("useSystemSoundTheme", true);
            return;
        }
        Proc.runCommand("setSoundTheme", ["sh", "-c", GSettings.setCmd("org.gnome.desktop.sound", "theme-name", themeName)], (output, exitCode) => {
            if (exitCode !== 0)
                return;
            currentSoundTheme = themeName;
            if (SettingsData.useSystemSoundTheme) {
                discoverSoundFiles(themeName);
                return;
            }
            SettingsData.set("useSystemSoundTheme", true);
        }, 0);
    }

    function refreshSoundThemes() {
        if (!soundThemeSupported)
            return;
        scanSoundThemes();
    }

    function discoverSoundFiles(themeName) {
        if (!themeName) {
            soundFilePaths = {};
            markSoundThemeResolved();
            return;
        }

        const xdgDataDirs = Quickshell.env("XDG_DATA_DIRS");
        const searchPaths = xdgDataDirs && xdgDataDirs.trim() !== "" ? xdgDataDirs.split(":").concat(Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericDataLocation))) : ["/usr/share", "/usr/local/share", Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericDataLocation))];

        const extensions = ["oga", "ogg", "wav", "mp3", "flac"];
        const themesToSearch = themeName !== "freedesktop" ? `${themeName} freedesktop` : themeName;

        const script = `
            for event_key in audio-volume-change power-plug power-unplug message message-new-instant desktop-login; do
                found=0

                case "$event_key" in
                    message)
                        names="dialog-information message message-lowpriority bell"
                        ;;
                    message-new-instant)
                        names="dialog-warning message-new-instant message-highlight"
                        ;;
                    *)
                        names="$event_key"
                        ;;
                esac

                for theme in ${themesToSearch}; do
                    for event_name in $names; do
                        for base_path in ${searchPaths.join(" ")}; do
                            theme_dir="$base_path/sounds/$theme"
                            [ -d "$theme_dir" ] || continue
                            file_path=$(find -L "$theme_dir" \\( ${extensions.map(e => `-name "$event_name.${e}"`).join(" -o ")} \\) -print 2>/dev/null | sort | head -1)
                            if [ -n "$file_path" ]; then
                                echo "$event_key=$file_path"
                                found=1
                                break
                            fi
                        done
                        [ $found -eq 1 ] && break
                    done
                    [ $found -eq 1 ] && break
                done
            done
            exit 0
        `;

        Proc.runCommand("discoverSoundFiles", ["sh", "-c", script], (output, exitCode) => {
            const paths = {};
            if (exitCode === 0 && output.trim()) {
                const lines = output.trim().split('\n');
                for (let line of lines) {
                    const parts = line.split('=');
                    if (parts.length === 2) {
                        paths[parts[0]] = "file://" + parts[1];
                    }
                }
            }
            soundFilePaths = paths;
            markSoundThemeResolved();
        }, 0);
    }

    function markSoundThemeResolved() {
        soundThemeResolved = true;
        const player = pendingSoundPlayer;
        pendingSoundPlayer = "";
        if (player)
            playSound(player);
    }

    function getSoundPath(soundEvent) {
        const soundMap = {
            "audio-volume-change": "../assets/sounds/freedesktop/audio-volume-change.wav",
            "power-plug": "../assets/sounds/plasma/power-plug.wav",
            "power-unplug": "../assets/sounds/plasma/power-unplug.wav",
            "message": "../assets/sounds/freedesktop/message.wav",
            "message-new-instant": "../assets/sounds/freedesktop/message-new-instant.wav",
            "desktop-login": "../assets/sounds/freedesktop/desktop-login.wav"
        };

        const specialConditions = {
            "smooth": ["audio-volume-change"]
        };

        const themeLower = currentSoundTheme.toLowerCase();
        if (SettingsData.useSystemSoundTheme && specialConditions[themeLower]?.includes(soundEvent)) {
            const bundledPath = Qt.resolvedUrl(soundMap[soundEvent] || "../assets/sounds/freedesktop/message.wav");
            log.debug("Using bundled sound (special condition) for", soundEvent, ":", bundledPath);
            return bundledPath;
        }

        if (SettingsData.useSystemSoundTheme && soundFilePaths[soundEvent]) {
            log.debug("Using system sound for", soundEvent, ":", soundFilePaths[soundEvent]);
            return soundFilePaths[soundEvent];
        }

        const bundledPath = Qt.resolvedUrl(soundMap[soundEvent] || "../assets/sounds/freedesktop/message.wav");
        log.debug("Using bundled sound for", soundEvent, ":", bundledPath);
        return bundledPath;
    }

    function reloadSounds() {
        log.debug("Reloading sounds, useSystemSoundTheme:", SettingsData.useSystemSoundTheme, "currentSoundTheme:", currentSoundTheme);
        if (!SettingsData.useSystemSoundTheme) {
            soundFilePaths = {};
            markSoundThemeResolved();
            return;
        }
        soundThemeResolved = false;
        if (currentSoundTheme) {
            discoverSoundFiles(currentSoundTheme);
            return;
        }
        getCurrentSoundTheme();
    }

    function isMediaPlaying() {
        return MprisController.activePlayer?.isPlaying ?? false;
    }

    function shouldMuteForMedia() {
        return SettingsData.muteSoundsWhenMediaPlaying && isMediaPlaying();
    }

    function ensurePlayers() {
        if (!SettingsData.soundsEnabled)
            return;
        MultimediaService.ensureProbed();
        playersRequested = true;
    }

    function playSound(playerName) {
        if (!SettingsData.soundsEnabled)
            return;
        ensurePlayers();
        // before the theme paths land the player holds the bundled file, and the source swap stops it
        if (SettingsData.useSystemSoundTheme && !soundThemeResolved) {
            pendingSoundPlayer = playerName;
            return;
        }
        const player = root[playerName];
        if (!soundsAvailable || !player || notificationsAudioMuted || shouldMuteForMedia())
            return;
        player.play();
    }

    function playVolumeChangeSound() {
        playSound("volumeChangeSound");
    }

    function playPowerPlugSound() {
        playSound("powerPlugSound");
    }

    function playPowerUnplugSound() {
        playSound("powerUnplugSound");
    }

    function playNormalNotificationSound() {
        playSound("normalNotificationSound");
    }

    function playCriticalNotificationSound() {
        playSound("criticalNotificationSound");
    }

    function playLoginSound() {
        playSound("loginSound");
    }

    function playLoginSoundIfApplicable() {
        if (SettingsData.soundsEnabled && SettingsData.soundLogin && !notificationsAudioMuted) {
            // plays login sound on session start, but only if a specific file doesn't exist,
            // to prevent it from playing on every DMS restart during the session
            const runtimeDir = Quickshell.env("XDG_RUNTIME_DIR");
            const sessionId = Quickshell.env("XDG_SESSION_ID") || "0";

            if (!runtimeDir)
                return;

            const loginFile = `${runtimeDir}/dms.login-${sessionId}`;
            const legacyLoginFile = `${runtimeDir}/danklinux.login-${sessionId}`;

            // if file doesn't exist, touch it (0)
            // If it exists, do nothing (1)
            loginSoundChecker.command = ["sh", "-c", `[ ! -f ${loginFile} ] && [ ! -f ${legacyLoginFile} ] && touch ${loginFile}`];
            loginSoundChecker.running = true;
        }
    }

    function playVolumeChangeSoundIfEnabled() {
        if (SettingsData.soundsEnabled && SettingsData.soundVolumeChanged && !notificationsAudioMuted) {
            playVolumeChangeSound();
        }
    }

    readonly property string sinkVolumeIconName: {
        if (isSilent(sink))
            return volumeIconName(sink);
        const bluetoothDevice = BluetoothService.deviceForNodeName(sink?.name);
        if (bluetoothDevice?.connected && /headset|headphone/.test((bluetoothDevice.icon || "").toLowerCase()))
            return "headphones";
        return volumeIconName(sink);
    }
    readonly property bool sinkSilent: isSilent(sink)

    function isSilent(node) {
        const audio = node?.audio;
        if (!audio)
            return false;
        return audio.muted || audio.volume === 0;
    }

    function volumeIcon(volume, muted) {
        if (muted)
            return "volume_off";
        if (volume === 0)
            return "volume_mute";
        return volume <= 0.33 ? "volume_down" : "volume_up";
    }

    function volumeIconName(node, noDeviceIcon = "volume_off") {
        const audio = node?.audio;
        if (!audio)
            return noDeviceIcon;
        if (audio.muted)
            return "volume_off";
        if (audio.volume === 0)
            return "volume_mute";
        return audio.volume <= 0.33 ? "volume_down" : "volume_up";
    }

    function sinkIcon(node) {
        if (!node)
            return "speaker";

        const props = node.properties || {};
        const formFactor = (props["device.form-factor"] || "").toLowerCase();

        switch (formFactor) {
        case "headphone":
        case "headset":
        case "hands-free":
        case "handset":
            return "headset";
        case "tv":
        case "monitor":
            return "tv";
        case "speaker":
        case "computer":
        case "hifi":
        case "portable":
        case "car":
            return "speaker";
        }

        const bus = (props["device.bus"] || "").toLowerCase();
        if (bus === "bluetooth")
            return "headset";

        const name = (node.name || "").toLowerCase();
        if (name.includes("hdmi"))
            return "tv";
        if (name.includes("iec958") || name.includes("spdif"))
            return "speaker";

        if (bus === "usb")
            return "headset";

        return "speaker";
    }

    // QtMultimedia's pipewire stream carries no application.* props, only node.name set to the app name.
    function isOwnStream(node) {
        return !!node?.isStream && node.name === "quickshell";
    }

    function displayName(node) {
        if (!node) {
            return "";
        }

        if (node.name && deviceAliases[node.name]) {
            return deviceAliases[node.name];
        }

        if (node.properties && node.properties["node.description"]) {
            const desc = node.properties["node.description"];
            if (desc !== node.name) {
                return desc;
            }
        }

        if (node.description && node.description !== node.name) {
            return node.description;
        }

        if (node.properties && node.properties["device.description"]) {
            return node.properties["device.description"];
        }

        if (node.nickname && node.nickname !== node.name) {
            return node.nickname;
        }

        if (node.name.includes("analog-stereo")) {
            return "Built-in Audio Analog Stereo";
        }
        if (node.name.includes("bluez")) {
            return "Bluetooth Audio";
        }
        if (node.name.includes("usb")) {
            return "USB Audio";
        }
        if (node.name.includes("hdmi")) {
            return "HDMI Audio";
        }

        return node.name;
    }

    function originalName(node) {
        if (!node) {
            return "";
        }

        if (node.name.includes("analog-stereo")) {
            return "Built-in Audio Analog Stereo";
        }
        if (node.name.includes("bluez")) {
            return "Bluetooth Audio";
        }
        if (node.name.includes("usb")) {
            return "USB Audio";
        }
        if (node.name.includes("hdmi")) {
            return "HDMI Audio";
        }
        if (node.name.includes("raop_sink")) {
            const match = node.name.match(/raop_sink\.([^.]+)/);
            if (match) {
                return match[1].replace(/-/g, " ");
            }
        }

        if (node.properties && node.properties["device.description"]) {
            return node.properties["device.description"];
        }

        if (node.nickname && node.nickname !== node.name) {
            return node.nickname;
        }

        return node.name;
    }

    function subtitle(name) {
        if (!name) {
            return "";
        }

        if (name.includes('usb-')) {
            if (name.includes('SteelSeries')) {
                return "USB Gaming Headset";
            }
            if (name.includes('Generic')) {
                return "USB Audio Device";
            }
            return "USB Audio";
        }

        if (name.includes('pci-')) {
            if (name.includes('01_00.1') || name.includes('01:00.1')) {
                return "NVIDIA GPU Audio";
            }
            return "PCI Audio";
        }

        if (name.includes('bluez')) {
            return "Bluetooth Audio";
        }
        if (name.includes('analog')) {
            return "Built-in Audio";
        }
        if (name.includes('hdmi')) {
            return "HDMI Audio";
        }

        return "";
    }

    function detectAudioBackend() {
        Proc.runCommand("audio-detect-os", ["uname", "-s"], (output, exitCode) => {
            const osName = exitCode === 0 ? (output || "").trim() : "";
            root.freebsdAudio = osName === "FreeBSD";
            root.audioBackendDetected = true;

            if (root.freebsdAudio) {
                Proc.runCommand("audio-detect-freebsd-mixer", ["sh", "-c", "command -v mixer >/dev/null 2>&1"], (mixerOutput, mixerExitCode) => {
                    if (mixerExitCode === 0)
                        root.refreshFreeBsdDevices();
                    else
                        log.error("FreeBSD detected, but mixer(8) is unavailable");
                }, 0);
            } else {
                Qt.callLater(root.rebuildTypedNodeLists);
            }
        }, 0);
    }

    function parseFreeBsdMixerDevices(output) {
        const result = [];
        const lines = (output || "").split("\n");
        let current = null;

        function finishCurrent() {
            if (current)
                result.push(current);
        }

        for (const raw of lines) {
            const header = raw.match(/^pcm(\d+):mixer:\s*<(.+)>\s+on\s+(\S+)\s+\(([^)]+)\)(?:\s+\(default\))?\s*$/);
            if (header) {
                finishCurrent();
                current = {
                    pcmUnit: parseInt(header[1]),
                    pcmName: "pcm" + header[1],
                    mixerDevice: "/dev/mixer" + header[1],
                    description: header[2],
                    driver: header[3],
                    modes: header[4].split("/"),
                    isDefault: raw.includes("(default)"),
                    controls: ({})
                };
                continue;
            }
            if (!current)
                continue;
            const control = raw.match(/^\s*([A-Za-z0-9_]+)\s*=\s*([0-9.]+)(?::([0-9.]+))?\s*(.*)$/);
            if (!control)
                continue;
            const left = parseFloat(control[2]);
            const right = control[3] ? parseFloat(control[3]) : left;
            current.controls[control[1]] = {
                volume: (left + right) / 2,
                flags: control[4] || ""
            };
        }
        finishCurrent();
        return result;
    }

    function freeBsdInputControl(entry) {
        const preferred = ["mic", "rec", "igain", "line"];
        for (const name of preferred) {
            if (entry.controls[name])
                return name;
        }
        return "";
    }

    function syncFreeBsdNode(existingNodes, entry, isSink, control) {
        const suffix = isSink ? "output" : "input";
        const name = "freebsd-" + entry.pcmName + "-" + suffix;
        let node = existingNodes.find(item => item?.name === name);
        if (!node) {
            node = freeBsdNodeComponent.createObject(root, {
                service: root,
                name: name,
                description: entry.description,
                mixerDevice: entry.mixerDevice,
                pcmName: entry.pcmName,
                pcmUnit: entry.pcmUnit,
                mixerControl: control,
                isSink: isSink
            });
        } else {
            node.description = entry.description;
            node.mixerControl = control;
        }
        const state = entry.controls[control];
        if (state && !root.hasPendingFreeBsdWrite(node))
            node.audio.volume = Math.max(0, Math.min(1, state.volume));
        return node;
    }

    function applyFreeBsdDeviceList(output) {
        const entries = parseFreeBsdMixerDevices(output);
        const oldSinks = nativeSinks;
        const oldSources = nativeSources;
        const nextSinks = [];
        const nextSources = [];
        let defaultEntry = null;

        nativeAudioSyncing = true;
        for (const entry of entries) {
            if (entry.isDefault)
                defaultEntry = entry;
            if (entry.modes.includes("play") && entry.controls.vol)
                nextSinks.push(syncFreeBsdNode(oldSinks, entry, true, "vol"));
            if (entry.modes.includes("rec")) {
                const inputControl = freeBsdInputControl(entry);
                if (inputControl)
                    nextSources.push(syncFreeBsdNode(oldSources, entry, false, inputControl));
            }
        }
        nativeAudioSyncing = false;

        nativeSinks = nextSinks;
        nativeSources = nextSources;
        if (defaultEntry) {
            nativeSink = nextSinks.find(n => n.pcmUnit === defaultEntry.pcmUnit) ?? nextSinks[0] ?? null;
            nativeSource = nextSources.find(n => n.pcmUnit === defaultEntry.pcmUnit) ?? nextSources[0] ?? null;
        } else {
            nativeSink = nextSinks[0] ?? null;
            nativeSource = nextSources[0] ?? null;
        }
        rebuildTypedNodeLists();
        deviceRevision++;
    }

    function refreshFreeBsdDevices() {
        if (!freebsdAudio)
            return;
        if (Date.now() - lastFreeBsdLocalChangeMs < 800)
            return;
        Proc.runCommand("audio-freebsd-devices", ["nice", "-n", "10", "env", "LC_ALL=C", "mixer", "-a"], (output, exitCode) => {
            if (exitCode === 0)
                root.applyFreeBsdDeviceList(output);
            else
                log.error("Unable to enumerate FreeBSD audio devices:", output);
        }, 0);
    }

    function hasPendingFreeBsdWrite(node) {
        if (!node)
            return false;
        const key = node.mixerDevice + "|" + node.mixerControl;
        return pendingFreeBsdVolumeWrites[key] !== undefined;
    }

    function queueFreeBsdMixerVolume(node, volume) {
        if (!node)
            return;
        const percent = Math.max(0, Math.min(100, Math.round(volume * 100)));
        const key = node.mixerDevice + "|" + node.mixerControl;
        const writes = Object.assign({}, pendingFreeBsdVolumeWrites);
        writes[key] = {
            node: node,
            percent: percent
        };
        pendingFreeBsdVolumeWrites = writes;
        lastFreeBsdLocalChangeMs = Date.now();
        freeBsdVolumeWriteTimer.restart();
    }

    function flushFreeBsdVolumeWrites() {
        const writes = pendingFreeBsdVolumeWrites;
        pendingFreeBsdVolumeWrites = ({});
        for (const key of Object.keys(writes)) {
            const entry = writes[key];
            const node = entry.node;
            Proc.runCommand("audio-freebsd-volume-" + node.pcmName + "-" + node.mixerControl, ["mixer", "-f", node.mixerDevice, node.mixerControl + ".volume=" + entry.percent + "%"], (output, exitCode) => {
                if (exitCode !== 0)
                    log.error("FreeBSD mixer volume update failed:", output);
            }, 0);
        }
    }

    function setFreeBsdMixerMute(node, muted) {
        if (!node)
            return;
        lastFreeBsdLocalChangeMs = Date.now();
        Proc.runCommand("audio-freebsd-mute-" + node.pcmName + "-" + node.mixerControl, ["mixer", "-f", node.mixerDevice, node.mixerControl + ".mute=" + (muted ? "1" : "0")], (output, exitCode) => {
            if (exitCode !== 0)
                log.error("FreeBSD mixer mute update failed:", output);
        }, 0);
    }

    function setFreeBsdDefaultDevice(node) {
        if (!node || node.pcmUnit < 0)
            return false;
        lastFreeBsdLocalChangeMs = Date.now();
        if (node.isSink)
            nativeSink = node;
        else
            nativeSource = node;
        // sound(4) has one default PCM unit. Keep both directions in sync when
        // the selected card supports them.
        const matchingSink = nativeSinks.find(n => n.pcmUnit === node.pcmUnit);
        const matchingSource = nativeSources.find(n => n.pcmUnit === node.pcmUnit);
        if (matchingSink)
            nativeSink = matchingSink;
        if (matchingSource)
            nativeSource = matchingSource;
        deviceRevision++;
        Proc.runCommand("audio-freebsd-default-device", ["mixer", "-d", node.pcmName], (output, exitCode) => {
            if (exitCode !== 0) {
                log.error("Unable to set FreeBSD default audio device:", output);
                root.refreshFreeBsdDevices();
            }
        }, 0);
        return true;
    }

    Timer {
        id: freeBsdVolumeWriteTimer
        interval: 35
        repeat: false
        onTriggered: root.flushFreeBsdVolumeWrites()
    }

    function setVolume(percentage) {
        if (!root.sink?.audio)
            return "No audio sink available";
        if (isNaN(percentage))
            return "Invalid percentage";

        const maxVol = root.sinkMaxVolume;
        const clampedVolume = Math.max(0, Math.min(maxVol, percentage));
        root.sinkVolumeWrites = [];
        root.sink.audio.volume = clampedVolume / 100;
        return `Volume set to ${clampedVolume}%`;
    }

    function outputVolumeStep(step) {
        const parsed = parseInt(step || "5");
        return isNaN(parsed) ? 5 : Math.max(0, parsed);
    }

    // Steps still awaiting PipeWire's echo; an older echo overwrites audio.volume, so stepping from it drops detents.
    property var sinkVolumeWrites: []
    property bool writingSinkVolume: false

    onSinkChanged: sinkVolumeWrites = []

    Connections {
        target: root.sink?.audio ?? null

        function onVolumeChanged() {
            if (root.writingSinkVolume || root.sinkVolumeWrites.length === 0)
                return;
            const idx = root.sinkVolumeWrites.indexOf(Math.round(root.sink.audio.volume * 100));
            root.sinkVolumeWrites = idx < 0 ? [] : root.sinkVolumeWrites.slice(idx + 1);
        }
    }

    function adjustDefaultSinkVolume(step, direction) {
        const audio = root.sink.audio;
        const maxVol = root.sinkMaxVolume;
        const stepValue = outputVolumeStep(step);
        const pending = root.sinkVolumeWrites;
        const currentVolume = pending.length > 0 ? pending[pending.length - 1] : Math.round(audio.volume * 100);
        const newVolume = Math.max(0, Math.min(maxVol, currentVolume + direction * stepValue));

        if (audio.muted)
            audio.muted = false;

        if (newVolume === currentVolume)
            return newVolume;

        root.writingSinkVolume = true;
        audio.volume = newVolume / 100;
        root.writingSinkVolume = false;
        root.sinkVolumeWrites = pending.concat([newVolume]).slice(-8);
        return newVolume;
    }

    function toggleMute() {
        if (!root.sink?.audio) {
            return "No audio sink available";
        }

        root.sink.audio.muted = !root.sink.audio.muted;
        return root.sink.audio.muted ? "Audio muted" : "Audio unmuted";
    }

    // Mono audio toggle
    property bool _monoQueryInProgress: false

    function queryMonoSetting(callback) {
        if (root._monoQueryInProgress) {
            return;
        }
        root._monoQueryInProgress = true;
        // Try pactl first (PipeWire ≥1.4.10 /1.6.0)
        Proc.runCommand("audio-query-mono", ["env", "LC_ALL=C", "pactl", "send-message", "/core", "pipewire-pulse:force-mono-output", ""], (output, exitCode) => {
            if (exitCode === 0 && output) {
                const trimmed = output.trim();
                if (trimmed === "true" || trimmed === "false") {
                    root.monoSettingSupported = true;
                    root.monoSettingBackend = "pactl";
                    root._monoQueryInProgress = false;
                    callback(true, trimmed === "true");
                    return;
                }
            }
            // Fallback to wpctl settings
            Proc.runCommand("audio-query-mono-wpctl", ["env", "LC_ALL=C", "wpctl", "settings", "node.features.audio.mono"], (output2, exitCode2) => {
                if (exitCode2 === 0 && output2) {
                    const m = output2.match(/\b(true|false)\b/);
                    if (m) {
                        root.monoSettingSupported = true;
                        root.monoSettingBackend = "wpctl";
                        root._monoQueryInProgress = false;
                        callback(true, m[1] === "true");
                        return;
                    }
                }
                root.monoSettingSupported = false;
                root.monoSettingBackend = "";
                root._monoQueryInProgress = false;
                callback(false, false);
            });
        }, 0);
    }

    // Re-apply the saved preference: the live PipeWire value is runtime-only and resets on restart
    function applyMonoStartupPreference() {
        if (!SettingsData._hasLoaded || !SettingsData.audioMono)
            return;
        queryMonoSetting((supported, currentValue) => {
            if (supported && currentValue !== SettingsData.audioMono)
                root.setMonoSetting(SettingsData.audioMono);
        });
    }

    function setMonoSetting(enabled, callback) {
        const boolStr = enabled ? "true" : "false";
        const backend = root.monoSettingBackend;
        if (backend === "pactl") {
            Proc.runCommand("audio-set-mono", ["env", "LC_ALL=C", "pactl", "send-message", "/core", "pipewire-pulse:force-mono-output", boolStr], (output, exitCode) => {
                const ok = exitCode === 0;
                if (callback) {
                    callback(ok, ok ? "Mono audio enabled" : (output || "Failed to set mono audio"));
                }
            }, 0);
        } else if (backend === "wpctl") {
            Proc.runCommand("audio-set-mono-wpctl", ["env", "LC_ALL=C", "wpctl", "settings", "node.features.audio.mono", boolStr], (output, exitCode) => {
                const ok = exitCode === 0;
                if (callback) {
                    callback(ok, ok ? "Mono audio enabled" : (output || "Failed to set mono audio"));
                }
            }, 0);
        } else if (callback) {
            callback(false, "Mono audio not supported");
        }
    }

    function setMicVolume(percentage) {
        if (!root.source?.audio) {
            return "No audio source available";
        }

        const clampedVolume = Math.max(0, Math.min(100, percentage));
        root.source.audio.volume = clampedVolume / 100;
        micVolumeChanged();
        return `Microphone volume set to ${clampedVolume}%`;
    }

    function toggleMicMute() {
        if (!root.source?.audio) {
            return "No audio source available";
        }

        root.source.audio.muted = !root.source.audio.muted;
        return root.source.audio.muted ? "Microphone muted" : "Microphone unmuted";
    }

    function incrementMicVolume(step) {
        if (!root.source?.audio)
            return "No audio source available";

        if (root.source.audio.muted)
            root.source.audio.muted = false;

        const currentVolume = Math.round(root.source.audio.volume * 100);
        const stepValue = parseInt(step || "5");
        const newVolume = Math.max(0, Math.min(100, currentVolume + stepValue));

        root.source.audio.volume = newVolume / 100;
        micVolumeChanged();
        return `Microphone volume increased to ${newVolume}%`;
    }

    function decrementMicVolume(step) {
        if (!root.source?.audio)
            return "No audio source available";

        if (root.source.audio.muted)
            root.source.audio.muted = false;

        const currentVolume = Math.round(root.source.audio.volume * 100);
        const stepValue = parseInt(step || "5");
        const newVolume = Math.max(0, Math.min(100, currentVolume - stepValue));

        root.source.audio.volume = newVolume / 100;
        micVolumeChanged();
        return `Microphone volume decreased to ${newVolume}%`;
    }

    onRefCountChanged: {
        if (root.refCount !== 1)
            return;
        root.rebuildTypedNodeLists();
        root.deviceRevision++;
        root.refreshFreeBsdDevices();
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.freebsdAudio && root.refCount > 0
        onTriggered: root.refreshFreeBsdDevices()
    }

    IpcHandler {
        target: "audio"

        function setvolume(percentage: string): string {
            return root.setVolume(parseInt(percentage));
        }

        function increment(step: string): string {
            if (!root.sink?.audio)
                return "No audio sink available";

            const newVolume = root.adjustDefaultSinkVolume(step, 1);
            return `Volume increased to ${newVolume}%`;
        }

        function decrement(step: string): string {
            if (!root.sink?.audio)
                return "No audio sink available";

            const newVolume = root.adjustDefaultSinkVolume(step, -1);
            return `Volume decreased to ${newVolume}%`;
        }

        function mute(): string {
            return root.toggleMute();
        }

        function setmic(percentage: string): string {
            return root.setMicVolume(parseInt(percentage));
        }

        function micmute(): string {
            return root.toggleMicMute();
        }

        function setmono(status: string): string {
            const enabled = status === "true";
            if (!root.monoSettingSupported) {
                return "Mono audio not supported";
            }
            // Async: persist setting only on success
            root.setMonoSetting(enabled, (ok, message) => {
                if (ok) {
                    SettingsData.set("audioMono", enabled);
                }
            });
            return "Mono audio toggle sent";
        }

        function getmono(): string {
            if (!root.monoSettingSupported) {
                return "Mono audio not supported";
            }
            return `Mono Audio: ${root.monoSettingBackend} ${SettingsData.audioMono ? "enabled" : "disabled"}`;
        }

        function status(): string {
            let result = "Audio Status:\n";

            if (root.sink?.audio) {
                const volume = Math.round(root.sink.audio.volume * 100);
                const muteStatus = root.sink.audio.muted ? " (muted)" : "";
                const maxVol = root.sinkMaxVolume;
                result += `Output: ${volume}%${muteStatus} (max: ${maxVol}%)\n`;
            } else {
                result += "Output: No sink available\n";
            }

            if (root.source?.audio) {
                const micVolume = Math.round(root.source.audio.volume * 100);
                const muteStatus = root.source.audio.muted ? " (muted)" : "";
                result += `Input: ${micVolume}%${muteStatus}`;
            } else {
                result += "Input: No source available";
            }

            return result;
        }

        function getmaxvolume(): string {
            return `${root.sinkMaxVolume}`;
        }

        function setmaxvolume(percent: string): string {
            if (!root.sink?.name)
                return "No audio sink available";
            const val = parseInt(percent);
            if (isNaN(val))
                return "Invalid percentage";
            SessionData.setDeviceMaxVolume(root.sink.name, val);
            return `Max volume set to ${SessionData.getDeviceMaxVolume(root.sink.name)}%`;
        }

        function getmaxvolumefor(nodeName: string): string {
            if (!nodeName)
                return "No node name specified";
            return `${SessionData.getDeviceMaxVolume(nodeName)}`;
        }

        function setmaxvolumefor(nodeName: string, percent: string): string {
            if (!nodeName)
                return "No node name specified";
            const val = parseInt(percent);
            if (isNaN(val))
                return "Invalid percentage";
            SessionData.setDeviceMaxVolume(nodeName, val);
            return `Max volume for ${nodeName} set to ${SessionData.getDeviceMaxVolume(nodeName)}%`;
        }

        function cycleoutput(): string {
            const result = root.cycleAudioOutput();
            if (!result)
                return "Only one audio output available";
            return `Switched to: ${result}`;
        }
    }
    Connections {
        target: SettingsData
        function onUseSystemSoundThemeChanged() {
            reloadSounds();
        }
    }

    onSoundsAvailableChanged: {
        if (!soundsAvailable)
            return;
        checkSoundThemeSupport();
    }

    readonly property bool settingsLoaded: SettingsData._hasLoaded
    onSettingsLoadedChanged: {
        if (settingsLoaded)
            root.applyMonoStartupPreference();
    }

    Component.onCompleted: {
        detectAudioBackend();
        rebuildTypedNodeLists();
        loadDeviceAliases();
        if (SettingsData.soundsEnabled && SettingsData.useSystemSoundTheme)
            getCurrentSoundTheme();
        root.applyMonoStartupPreference();
    }
}
