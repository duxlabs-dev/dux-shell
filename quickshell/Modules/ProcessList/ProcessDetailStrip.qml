import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "ProcessColumns.js" as ProcessColumns
import "Connections.js" as Remotes
import "../../Common/Format.js" as Format

Rectangle {
    id: root

    required property var process

    readonly property int pid: process?.pid ?? 0
    readonly property var live: (DgopService.allProcesses ?? []).find(p => p.pid === pid) ?? process
    readonly property string command: live?.command ?? ""
    readonly property string fullCommand: live?.fullCommand || command
    readonly property var desktopEntry: ProcessListMetrics.appEntry(live, [sandbox?.id])
    readonly property string appName: desktopEntry?.name || command
    readonly property var startTime: live?.startTime ?? null
    readonly property var started: startTime !== null ? new Date(startTime * 1000) : null
    readonly property bool startedToday: started !== null && started.toDateString() === new Date().toDateString()
    readonly property var parentProcess: (live?.ppid ?? 0) > 0 ? (DgopService.allProcesses ?? []).find(p => p.pid === live.ppid) ?? null : null

    property var detail: null
    readonly property string unit: Remotes.unescapeUnit(detail?.unit ?? "")
    readonly property string unitKind: Remotes.unitKind(unit)
    readonly property var sandbox: detail?.sandbox ?? null
    readonly property var privileges: detail?.privileges ?? null

    // Tailscale device names by address, from the peer list the Tailscale page loads.
    readonly property var tailscaleNames: {
        const names = {};
        for (const p of TailscaleService.allPeersList ?? []) {
            for (const ip of [p?.tailscaleIp, p?.tailscaleIpv6])
                if (ip)
                    names[ip] = p.hostname || p.dnsName || ip;
        }
        return names;
    }
    readonly property var connections: Remotes.group(live?.remotes ?? [], tailscaleNames)
    readonly property var listening: detail?.listening ?? []
    readonly property int connectionCount: (live?.connections ?? 0) + (live?.localConnections ?? 0)
    readonly property bool hasNetwork: connectionCount > 0 || listening.length > 0
    readonly property bool otherNetwork: connections.tailscale.length > 0 || connections.local.length > 0 || listening.length > 0

    readonly property var windows: (CompositorService.sortedToplevels ?? []).filter(t => CompositorService.windowPid(t) === pid)
    // A merged row stands for its children too; their streams are matched by the binary's name.
    readonly property var audioNodes: (AudioService.pipewireNodes ?? []).filter(n => n?.audio && n.isSink && n.isStream && (Number(n.properties?.["application.process.id"]) === pid || ((live?.childCount ?? 0) > 0 && n.properties?.["application.process.binary"] === command)))
    readonly property int audioStreams: audioNodes.length

    readonly property real groupWidth: Theme.fontSizeMedium * 16
    readonly property bool own: ProcessActions.isOwn(live)
    readonly property bool endable: ProcessActions.canEnd(live)
    readonly property string restartKind: ProcessActions.restartKind(live)
    readonly property string authTip: own ? "" : I18n.tr("Authentication Required")
    readonly property string unreadableTip: I18n.tr("Not readable without privileges", "process value that needs root access to read")

    readonly property var tabIds: ["overview", "resources"].concat(hasNetwork ? ["network"] : [], ["details"])
    readonly property string age: {
        if (!started)
            return "";
        const s = Math.max(0, (Date.now() - started.getTime()) / 1000);
        const unit = s >= 86400 ? 86400 : s >= 3600 ? 3600 : 60;
        return I18n.duration(Math.max(60, Math.floor(s / unit) * unit));
    }
    readonly property string parentChain: {
        const names = [];
        let p = parentProcess;
        while (p && names.length < 6) {
            names.push(p.command);
            const ppid = p.ppid;
            p = ppid > 0 ? (DgopService.allProcesses ?? []).find(x => x.pid === ppid) ?? null : null;
        }
        return names.join(" › ");
    }
    readonly property string currentTab: tabIds.includes(ProcessListMetrics.processTab) ? ProcessListMetrics.processTab : "overview"

    signal actionRequested(string action)

    function cell(id) {
        return ProcessColumns.formatCell(id, live ?? ({})) ?? "—";
    }

    function bytes(v) {
        return v === null || v === undefined ? "" : Format.formatBytes(v, true);
    }

    function sandboxName(kind) {
        switch (kind) {
        case "flatpak":
            return "Flatpak";
        case "snap":
            return "Snap";
        }
        return I18n.tr("Container", "process runs in its own container namespace");
    }

    function row(label, value, tooltip) {
        return {
            "label": label,
            "value": value === null || value === undefined ? null : String(value),
            "tooltip": tooltip ?? ""
        };
    }

    function known(label, value) {
        return value === null || value === undefined || value === "" ? row(label, "—", unreadableTip) : row(label, value);
    }

    function kb(v) {
        return v === null || v === undefined ? null : Format.formatBytes(v * 1024, true);
    }

    function seconds(v) {
        return v === null || v === undefined ? null : Format.formatDuration(v, true);
    }

    function count(v) {
        return v === null || v === undefined ? null : Number(v).toLocaleString(Qt.locale(), "f", 0);
    }

    function tabTitle(id) {
        switch (id) {
        case "overview":
            return I18n.tr("Overview");
        case "resources":
            return I18n.tr("Resources", "process detail tab: CPU, memory, disk and GPU use");
        case "network":
            return I18n.tr("Network");
        }
        return I18n.tr("Details", "process detail tab: less used information");
    }

    function connectionRows(list) {
        return list.slice(0, 5).map(c => ({
                    "label": c.name,
                    "value": c.service,
                    "tooltip": c.name !== c.host ? c.host : ""
                })).concat(list.length > 5 ? [
            {
                "label": I18n.tr("+ %1 more").arg(list.length - 5),
                "value": " "
            }
        ] : []);
    }

    function refreshDetail() {
        if (pid > 0)
            DgopService.fetchProcessDetail(pid, d => root.detail = d);
    }

    Component.onCompleted: refreshDetail()

    Timer {
        interval: DgopService.updateInterval
        running: root.visible && root.pid > 0
        repeat: true
        onTriggered: root.refreshDetail()
    }

    Ref {
        service: TailscaleService
        active: root.connections.tailscale.length > 0
    }

    component InfoChip: Rectangle {
        id: chip

        property string iconName: ""
        property string text: ""
        property string tip: ""
        property bool emphasis: false

        visible: text !== ""
        implicitWidth: chipRow.implicitWidth + Theme.spacingM * 2
        implicitHeight: Theme.buttonHeightXS
        radius: Theme.cornerRadiusS
        color: emphasis ? Theme.secondaryContainer : Theme.surfaceContainerHighest
        Accessible.role: Accessible.StaticText
        Accessible.name: tip ? tip + ": " + text : text

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: chip.iconName
                size: Theme.iconSizeSmall
                color: chip.emphasis ? Theme.onSecondaryContainer : Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Theme.fontSizeMedium * 18)
                text: chip.text
                font.pixelSize: Theme.fontSizeSmall
                color: chip.emphasis ? Theme.onSecondaryContainer : Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideMiddle
            }
        }

        MouseArea {
            id: chipHover
            anchors.fill: parent
            enabled: chip.tip !== ""
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        DTooltipHost {
            target: chip
            hoverArea: chipHover
            multiline: chip.tip.includes("\n")
            text: chip.tip
        }
    }

    component Section: Column {
        id: section

        property string title: ""
        property string iconName: ""
        property var rows: []
        readonly property var shown: rows.filter(r => r && r.value !== null && r.value !== undefined && r.value !== "")

        visible: shown.length > 0
        spacing: Theme.spacingXS

        Row {
            visible: section.title !== ""
            leftPadding: Theme.spacingXS
            spacing: Theme.spacingXS

            DeviceIcon {
                visible: section.iconName !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: section.iconName
                size: Theme.iconSizeSmall
                color: Theme.primary
            }

            StyledText {
                text: section.title
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primary
            }
        }

        SettingsGroup {
            width: parent.width
            customPaddingV: 0
            customPaddingH: Theme.spacingM
            slotColor: Theme.surfaceContainerHighest

            // By count, so a new sample rebinds the rows instead of rebuilding them; hidden tabs build none.
            Repeater {
                model: section.visible ? section.shown.length : 0

                StatRow {
                    required property int index
                    readonly property var entry: section.shown[index] ?? ({})
                    height: Theme.buttonHeightXS
                    label: entry.label ?? ""
                    value: String(entry.value ?? "")
                    tooltip: entry.tooltip ?? ""
                }
            }
        }
    }

    implicitHeight: body.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadiusM
    color: Theme.surfaceContainerHigh

    // Clicks between the controls stay here instead of reaching the row, which would collapse the strip.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    ColumnLayout {
        id: body
        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        spacing: Theme.spacingL

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingM

            Item {
                Layout.preferredWidth: Theme.iconButtonSize
                Layout.preferredHeight: Theme.iconButtonSize

                IconImage {
                    id: appIcon
                    anchors.fill: parent
                    source: root.command ? Paths.getAppIcon(root.desktopEntry?.id ?? root.command, root.desktopEntry) : ""
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !appIcon.visible
                    radius: Theme.cornerRadiusM
                    color: Theme.secondaryContainer

                    StyledText {
                        anchors.centerIn: parent
                        text: root.command.charAt(0).toUpperCase()
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Theme.fontWeightMedium
                        color: Theme.onSecondaryContainer
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.appName
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.surfaceText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                StyledText {
                    id: commandLine
                    Layout.fillWidth: true
                    // Commands can hold whole scripts with line breaks; one line here, the full one is under Details.
                    text: root.fullCommand.replace(/\s+/g, " ")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    textFormat: Text.PlainText
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight

                    MouseArea {
                        id: commandHover
                        anchors.fill: parent
                        enabled: commandLine.truncated
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    DTooltipHost {
                        target: commandLine
                        hoverArea: commandHover
                        multiline: true
                        text: root.fullCommand.length > 600 ? root.fullCommand.slice(0, 600) + "…" : root.fullCommand
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            InfoChip {
                iconName: "person"
                text: root.live?.username ?? ""
                tip: I18n.tr("User")
            }

            InfoChip {
                iconName: "tag"
                text: I18n.tr("PID %1", "%1 is a process id").arg(root.pid)
            }

            InfoChip {
                iconName: "stacks"
                text: (root.live?.childCount ?? 0) > 0 ? I18n.tr("%1 processes", "process count, plural, %1 is a number").arg(root.live.childCount + 1) : ""
            }

            InfoChip {
                iconName: "schedule"
                text: root.started ? (root.startedToday ? Qt.formatTime(root.started, "HH:mm") : Qt.formatDate(root.started, Locale.ShortFormat)) : ""
                tip: I18n.tr("Started", "when a process was started")
            }

            InfoChip {
                iconName: "account_tree"
                text: root.parentProcess ? root.parentProcess.command : (root.live?.ppid ?? 0) > 0 ? String(root.live.ppid) : ""
                tip: I18n.tr("Parent", "the process that started this one") + (root.parentProcess ? ", " + I18n.tr("PID %1", "%1 is a process id").arg(root.parentProcess.pid) : "")
            }

            // App launch scopes and login sessions say nothing the app name doesn't; only real services get a chip.
            InfoChip {
                iconName: "deployed_code"
                text: root.unitKind === "service" ? root.unit.replace(/\.service$/, "") : ""
                tip: I18n.tr("Service", "the systemd unit or app scope a process runs in")
            }

            InfoChip {
                iconName: "inventory_2"
                text: root.sandbox ? (root.sandbox.id || root.sandboxName(root.sandbox.kind)) : ""
                tip: root.sandbox ? root.sandboxName(root.sandbox.kind) : ""
            }

            InfoChip {
                iconName: "shield"
                emphasis: true
                text: root.privileges ? I18n.tr("Elevated", "process runs with more rights than its user") : ""
                tip: root.privileges ? (root.privileges.setuid ? I18n.tr("Setuid", "process runs with another user's rights") + "\n" : "") + (root.privileges.capabilities ?? []).join("\n") : ""
            }

            InfoChip {
                iconName: "web_asset"
                text: root.windows.length === 0 ? "" : root.windows.length === 1 ? I18n.tr("%1 window").arg(1) : I18n.tr("%1 windows").arg(root.windows.length)
                tip: root.windows.map(w => w.title ?? "").filter(t => t).join("\n")
            }

            InfoChip {
                iconName: "volume_up"
                text: root.audioStreams > 0 ? I18n.tr("Playing audio", "process has an open audio playback stream") : ""
            }
        }

        DTabBar {
            id: tabs
            Layout.fillWidth: true
            showIcons: false
            equalWidthTabs: false
            model: root.tabIds.map(id => ({
                        "text": root.tabTitle(id)
                    }))
            currentIndex: root.tabIds.indexOf(root.currentTab)
            onTabClicked: index => ProcessListMetrics.processTab = root.tabIds[index]
        }

        GridLayout {
            id: grid

            // Two columns at fixed halves, so a short column doesn't stretch the other.
            readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns

            Layout.fillWidth: true
            Layout.maximumWidth: Infinity
            columns: width >= root.groupWidth * 2 + columnSpacing ? 2 : 1
            columnSpacing: Theme.spacingL
            rowSpacing: Theme.spacingL

            Section {
                visible: root.currentTab === "overview"
                Layout.preferredWidth: grid.cellWidth
                Layout.alignment: Qt.AlignTop
                rows: [root.row(I18n.tr("CPU time", "process column: total CPU time used"), root.cell("cpuTime")), root.row(I18n.tr("Running for", "how long a process has been running"), root.age, root.started ? root.started.toLocaleString(Qt.locale(), Locale.ShortFormat) : ""), root.row(I18n.tr("Threads", "number of threads, CPU or process"), root.cell("threads")), root.known(I18n.tr("Open files", "number of files and sockets a process has open"), root.detail?.openFiles)]
            }

            Section {
                visible: root.currentTab === "overview"
                Layout.preferredWidth: grid.cellWidth
                Layout.alignment: Qt.AlignTop
                rows: [root.row(I18n.tr("Memory"), root.cell("memory")), root.known(I18n.tr("Read total", "total data read"), root.bytes(root.detail?.readTotal)), root.known(I18n.tr("Written total", "total data written"), root.bytes(root.detail?.writeTotal)), root.known(I18n.tr("Connections", "process column: number of open internet connections"), root.live?.connections == null ? null : root.connectionCount)]
            }

            Section {
                visible: root.currentTab === "resources"
                Layout.preferredWidth: grid.cellWidth
                Layout.alignment: Qt.AlignTop
                title: I18n.tr("CPU")
                iconName: "memory"
                rows: [root.row(I18n.tr("Usage", "chart legend: CPU or GPU utilization"), root.cell("cpu")), root.row(I18n.tr("User time", "CPU time spent in the program itself"), root.seconds(root.detail?.userTime)), root.row(I18n.tr("System time", "CPU time the kernel spent on behalf of the program"), root.seconds(root.detail?.systemTime)), root.row(I18n.tr("Last core", "CPU core the process last ran on"), root.detail?.lastCpu), root.row(I18n.tr("Allowed cores", "CPU affinity list"), root.detail?.affinity), root.row(I18n.tr("Scheduling", "Linux scheduling policy"), root.detail?.policy), root.row(I18n.tr("Priority", "kernel scheduling priority"), root.detail?.priority), root.row(I18n.tr("Nice", "process column: Linux nice value, scheduling priority"), root.cell("nice")), root.row(I18n.tr("I/O priority", "disk scheduling class and level"), root.detail?.ioClass ? root.detail.ioClass + (root.detail.ioLevel != null ? " " + root.detail.ioLevel : "") : null), root.row(I18n.tr("Context switches", "times the process gave up the CPU voluntarily"), root.count(root.detail?.voluntarySwitches)), root.row(I18n.tr("Preempted", "times the process was forced off the CPU"), root.count(root.detail?.involuntarySwitches))]
            }

            Section {
                visible: root.currentTab === "resources"
                Layout.preferredWidth: grid.cellWidth
                Layout.alignment: Qt.AlignTop
                title: I18n.tr("Memory")
                iconName: "developer_board"
                rows: [root.row(I18n.tr("Own share", "proportional memory: the process's share of pages it shares with others"), root.cell("memory")), root.row(I18n.tr("Resident", "memory pages currently in RAM"), root.kb(root.detail?.rssKB ?? root.live?.rssKB)), root.row(I18n.tr("Anonymous", "resident memory not backed by a file"), root.kb(root.detail?.rssAnonKB)), root.row(I18n.tr("File-backed", "resident memory mapped from files"), root.kb(root.detail?.rssFileKB)), root.row(I18n.tr("Shared", "resident shared memory (shmem)"), root.kb(root.detail?.rssShmemKB)), root.row(I18n.tr("Peak", "highest resident memory so far"), root.kb(root.detail?.peakKB)), root.row(I18n.tr("Virtual", "virtual address space size"), root.kb(root.detail?.virtualKB)), root.known(I18n.tr("Swap"), root.detail?.swapKB != null ? root.kb(root.detail.swapKB) : null), root.row(I18n.tr("Page faults", "minor page faults"), root.count(root.detail?.minorFaults)), root.row(I18n.tr("Major page faults", "page faults that needed disk reads"), root.count(root.detail?.majorFaults)), root.row(I18n.tr("Out-of-memory score", "how likely the kernel kills this process first when memory runs out"), root.detail?.oomScore, root.detail?.oomScoreAdj != null ? I18n.tr("Adjustment", "oom_score_adj") + ": " + root.detail.oomScoreAdj : "")]
            }

            Section {
                visible: root.currentTab === "resources"
                Layout.preferredWidth: grid.cellWidth
                Layout.alignment: Qt.AlignTop
                title: I18n.tr("Disk")
                iconName: "hard_drive"
                rows: [root.row(ProcessListMetrics.columnLabel("diskRead"), ProcessColumns.formatCell("diskRead", root.live ?? ({}))), root.row(ProcessListMetrics.columnLabel("diskWrite"), ProcessColumns.formatCell("diskWrite", root.live ?? ({}))), root.known(I18n.tr("Read total", "total data read"), root.bytes(root.detail?.readTotal)), root.known(I18n.tr("Written total", "total data written"), root.bytes(root.detail?.writeTotal))]
            }

            Section {
                visible: root.currentTab === "resources" && shown.length > 0
                Layout.preferredWidth: grid.cellWidth
                Layout.alignment: Qt.AlignTop
                title: I18n.tr("GPU")
                iconName: "gpu"
                rows: [root.row(I18n.tr("Usage", "chart legend: CPU or GPU utilization"), ProcessColumns.formatCell("gpu", root.live ?? ({}))), root.row(ProcessListMetrics.columnLabel("gpuVideo"), ProcessColumns.formatCell("gpuVideo", root.live ?? ({}))), root.row(I18n.tr("VRAM", "GPU video memory"), ProcessColumns.formatCell("vram", root.live ?? ({}))), root.row(I18n.tr("Shared memory", "GPU memory borrowed from system RAM (GTT)"), root.live?.gpuGttKB != null ? root.kb(root.live.gpuGttKB) : null)]
            }

            Section {
                visible: root.currentTab === "network" && shown.length > 0
                Layout.columnSpan: root.otherNetwork ? 1 : grid.columns
                Layout.preferredWidth: root.otherNetwork ? grid.cellWidth : grid.width
                Layout.alignment: Qt.AlignTop
                title: I18n.tr("Internet")
                iconName: "public"
                rows: root.connectionRows(root.connections.internet)
            }

            Column {
                visible: root.currentTab === "network" && root.otherNetwork
                Layout.columnSpan: root.connections.internet.length > 0 ? 1 : grid.columns
                Layout.preferredWidth: root.connections.internet.length > 0 ? grid.cellWidth : grid.width
                Layout.alignment: Qt.AlignTop
                spacing: Theme.spacingL

                Section {
                    width: parent.width
                    title: "Tailscale"
                    iconName: "vpn_key"
                    rows: root.connectionRows(root.connections.tailscale)
                }

                Section {
                    width: parent.width
                    title: I18n.tr("Local network", "process detail: connections to LAN, VPN or link-local addresses, not the internet")
                    iconName: "lan"
                    rows: root.connectionRows(root.connections.local)
                }

                Section {
                    width: parent.width
                    title: I18n.tr("Listening", "network ports a process accepts connections on")
                    iconName: "sensors"
                    rows: root.listening.map(l => root.row(Remotes.service(l.port, l.protocol) === String(l.port) ? String(l.port) : l.port + " (" + Remotes.service(l.port, l.protocol) + ")", l.protocol.toUpperCase(), l.address))
                }
            }

            Section {
                visible: root.currentTab === "details"
                Layout.preferredWidth: grid.cellWidth
                Layout.alignment: Qt.AlignTop
                title: I18n.tr("Process", "section title: details of one process")
                iconName: "info"
                rows: [root.row(I18n.tr("User"), root.live?.username), root.row(I18n.tr("Status"), root.live?.status ? ProcessListMetrics.statusLabel(root.live.status) : null), root.row("UID", root.detail?.uid), root.row(I18n.tr("Group"), root.detail?.group ? root.detail.group + " (" + root.detail.gid + ")" : root.detail?.gid), root.row(I18n.tr("Started", "when a process was started"), root.started ? root.started.toLocaleString(Qt.locale(), Locale.ShortFormat) : null), root.row(I18n.tr("Parents", "chain of processes that started this one"), root.parentChain), root.row(I18n.tr("Terminal"), root.detail?.tty), root.row(I18n.tr("Session", "login session id of a process"), root.detail?.session), root.row(I18n.tr("Setuid", "process runs with another user's rights"), root.privileges?.setuid ? I18n.tr("Yes") : null)]
            }

            Section {
                visible: root.currentTab === "details"
                Layout.preferredWidth: grid.cellWidth
                Layout.alignment: Qt.AlignTop
                title: I18n.tr("System")
                iconName: "settings"
                rows: [root.row(I18n.tr("Executable", "path of the program file a process runs"), root.live?.executablePath, root.live?.executablePath), root.row(I18n.tr("Working directory", "the folder a process runs in"), root.detail?.cwd, root.detail?.cwd), root.row(I18n.tr("Systemd unit", "the systemd service or scope a process runs in"), root.unit, root.unit), root.row(I18n.tr("Control group", "the cgroup path of a process"), root.detail?.cgroup, root.detail?.cgroup), root.row(root.sandbox ? root.sandboxName(root.sandbox.kind) : "", root.sandbox ? (root.sandbox.id || "—") : null), root.row(I18n.tr("Capabilities", "Linux capabilities that give a process extra rights"), (root.privileges?.capabilities ?? []).join(", "), (root.privileges?.capabilities ?? []).join("\n"))]
            }

            Section {
                visible: root.currentTab === "details" && shown.length > 0
                Layout.columnSpan: grid.columns
                Layout.fillWidth: true
                title: I18n.tr("Windows", "section title: windows a process has open")
                iconName: "web_asset"
                rows: root.windows.map(w => root.row(w.title || w.appId || "", w.appId || " ", w.title))
            }

            Section {
                visible: root.currentTab === "details" && shown.length > 0
                Layout.columnSpan: grid.columns
                Layout.fillWidth: true
                title: I18n.tr("Audio")
                iconName: "volume_up"
                rows: root.audioNodes.map(n => root.row(n.properties?.["media.name"] || n.properties?.["application.name"] || n.name, n.audio?.muted ? I18n.tr("Muted") : Math.round((n.audio?.volume ?? 0) * 100) + "%"))
            }

            Column {
                visible: root.currentTab === "details"
                Layout.columnSpan: grid.columns
                Layout.fillWidth: true
                spacing: Theme.spacingXS

                StyledText {
                    leftPadding: Theme.spacingXS
                    text: I18n.tr("Command")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(commandFull.implicitHeight + Theme.spacingS * 2, commandCopy.height + Theme.spacingXS * 2)
                    radius: Theme.cornerRadiusL
                    color: Theme.surfaceContainerHighest

                    StyledText {
                        id: commandFull
                        x: Theme.spacingM
                        y: Math.max(Theme.spacingS, (parent.height - implicitHeight) / 2)
                        width: commandCopy.x - x - Theme.spacingS
                        text: root.fullCommand
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                    }

                    DActionButton {
                        id: commandCopy
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingXS
                        y: Theme.spacingXS
                        iconName: "content_copy"
                        iconColor: Theme.surfaceText
                        tooltipText: I18n.tr("Copy Full Command")
                        onClicked: Quickshell.execDetached(["dms", "cl", "copy", "--", root.fullCommand])
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            Item {
                Layout.fillWidth: true
            }

            DButton {
                text: root.restartKind === "reload" ? I18n.tr("Reload", "process action: reload a compositor's configuration") : I18n.tr("Restart", "process action: start the process again")
                iconName: "restart_alt"
                visible: root.restartKind !== "" && !(root.restartKind === "relaunch" && (root.detail?.terminal ?? false))
                backgroundColor: Theme.secondaryContainer
                textColor: Theme.onSecondaryContainer
                tooltipText: root.authTip || null
                onClicked: root.actionRequested("restart")
            }

            DSplitButton {
                id: quitButton
                visible: root.endable
                text: I18n.tr("Quit", "process action: ask the process to exit (SIGTERM)")
                iconName: "close"
                size: "s"
                variant: "filled"
                expanded: quitMenu.menuVisible
                tooltipText: root.authTip
                menuTooltipText: I18n.tr("More")
                onClicked: root.actionRequested("quit")
                onMenuClicked: {
                    quitMenu.currentValue = "";
                    quitMenu.openDropdownMenu();
                }

                DDropdown {
                    id: quitMenu
                    showTrigger: false
                    popupAnchorItem: quitButton.trailingButton
                    focusReturnTarget: quitButton.trailingButton
                    alignPopupRight: !I18n.isRtl
                    popupWidth: Theme.fontSizeMedium * 14
                    options: [I18n.tr("Force quit", "process action: kill the process immediately (SIGKILL)"), I18n.tr("End process tree", "process action: quit the process and every process it started")]
                    optionIcons: ["dangerous", "account_tree"]
                    onValueChanged: value => root.actionRequested(value === options[0] ? "force" : "tree")
                }
            }
        }
    }
}
