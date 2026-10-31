pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "SystemInfo.js" as SystemInfo
import "Drives.js" as Drives
import "../../Services/SysmonDevices.js" as Devices

Item {
    id: root

    // The page's actions sit in a FAB bar, like Settings pages; SettingsFabBar finds this property.
    property var fabBar: null

    Ref {
        service: DgopService
        modules: ["system", "cpu", "memory", "memory-modules", "sensors", "diskmounts"]
        active: root.visible
    }

    Ref {
        service: TailscaleService
        active: root.visible
    }

    SystemFacts {
        id: facts
    }

    // visible starts true when the tab is already current, so the bound handler alone would miss the first show.
    Component.onCompleted: {
        if (visible)
            facts.refresh();
    }
    onVisibleChanged: {
        if (visible && !facts.loaded)
            facts.refresh();
    }

    readonly property var f: facts.facts
    readonly property var cpuInfo: DgopService.cpuInfo
    readonly property var gpus: DgopService.availableGpus ?? []
    readonly property string mesa: SystemInfo.mesaVersion(f)
    readonly property string compositorVersion: {
        const raw = f["wm." + CompositorService.compositor];
        return raw ? SystemInfo.version(raw) : "";
    }
    readonly property string compositorText: [CompositorService.displayName, compositorVersion].filter(x => x).join(" ")
    readonly property string memoryText: DgopService.totalMemoryKB > 0 ? DgopService.formatSystemMemory(DgopService.totalMemoryKB) : ""
    readonly property string kernelText: DgopService.kernelVersion ? DgopService.kernelVersion + (DgopService.architecture ? " (" + DgopService.architecture + ")" : "") : ""
    readonly property string graphicsDriver: [[...new Set(gpus.map(g => g.driver).filter(d => d))].join(", "), mesa ? "Mesa " + mesa : ""].filter(x => x).join(", ")
    readonly property string doctorText: {
        const s = facts.doctor?.summary;
        if (!s)
            return "";
        return I18n.tr("%1 errors, %2 warnings", "system check summary").arg(s.errors ?? 0).arg(s.warnings ?? 0);
    }
    readonly property var doctorIssues: (facts.doctor?.results ?? []).filter(r => r.status === "error" || r.status === "warn" || r.status === "warning")

    readonly property var displays: {
        const outputs = (WlrOutputService.outputs ?? []).filter(o => o.enabled && o.currentMode);
        if (outputs.length > 0)
            return outputs.map(o => ({
                        "name": [o.make, o.model].filter(x => x).join(" ") || o.name || "",
                        "value": [SystemInfo.modeText(o.currentMode), o.scale && o.scale !== 1 ? o.scale + "×" : "", o.adaptiveSync ? "VRR" : ""].filter(x => x).join(", ")
                    }));
        return Quickshell.screens.map(s => ({
                    "name": s.name,
                    "value": SystemInfo.modeText({
                        "width": Math.round(s.width * s.devicePixelRatio),
                        "height": Math.round(s.height * s.devicePixelRatio)
                    })
                }));
    }

    readonly property string themeText: {
        const name = Theme.currentThemeName ?? "";
        const base = name === "dynamic" ? I18n.tr("Dynamic", "theme generated from the wallpaper") + (SettingsData.matugenScheme ? ", " + SettingsData.matugenScheme.replace(/^scheme-/, "") : "") : name;
        return [base, SessionData.isLightMode ? I18n.tr("Light") : I18n.tr("Dark")].filter(x => x).join(", ");
    }

    readonly property string powerProfileText: {
        if (!PowerProfileWatcher.available)
            return "";
        switch (PowerProfiles.profile) {
        case PowerProfile.PowerSaver:
            return I18n.tr("Power Saver");
        case PowerProfile.Performance:
            return I18n.tr("Performance");
        }
        return I18n.tr("Balanced");
    }

    readonly property string chassisText: {
        switch (SystemInfo.chassisKind(f["dmi.chassis_type"])) {
        case "desktop":
            return I18n.tr("Desktop", "computer chassis type");
        case "laptop":
            return I18n.tr("Laptop", "computer chassis type");
        case "server":
            return I18n.tr("Server", "computer chassis type");
        case "tablet":
            return I18n.tr("Tablet", "computer chassis type");
        case "convertible":
            return I18n.tr("Convertible", "computer chassis type: laptop that turns into a tablet");
        case "mini":
            return I18n.tr("Mini PC", "computer chassis type");
        }
        return "";
    }

    readonly property var rootPartition: {
        for (const d of DriveService.drives ?? []) {
            const p = (d.partitions ?? []).find(x => x.mountPoint === "/");
            if (p)
                return p;
        }
        return null;
    }
    readonly property string rootText: {
        if (!rootPartition)
            return "";
        const mount = (DgopService.diskMounts ?? []).find(m => m.mount === "/");
        return [[rootPartition.fsType, rootPartition.encryption ? I18n.tr("on %1", "filesystem on an encrypted container, e.g. on LUKS2").arg(rootPartition.encryption) : ""].filter(x => x).join(" "), mount?.percent ? I18n.tr("%1 used", "share of a filesystem in use, e.g. 61% used").arg(mount.percent) : ""].filter(x => x).join(", ");
    }

    readonly property string connectionText: {
        if (NetworkService.ethernetConnected) {
            const dev = (NetworkService.ethernetDevices ?? []).find(d => d.name === NetworkService.ethernetInterface);
            const speed = dev?.speed > 0 ? (dev.speed >= 1000 ? dev.speed / 1000 + " Gbit/s" : dev.speed + " Mbit/s") : "";
            return [I18n.tr("Ethernet"), speed].filter(s => s).join(", ");
        }
        if (NetworkService.wifiConnected)
            return I18n.tr("Wi-Fi");
        return NetworkService.networkAvailable ? I18n.tr("Disconnected") : "";
    }

    // An empty row keeps its place with a spinner while it can still be filled: until the facts script is read, or
    // `waiting` for rows from elsewhere. Afterwards empty rows are dropped.
    function row(label, value, tooltip, isPrivate, waiting) {
        const text = value === null || value === undefined ? "" : String(value);
        return {
            "label": label,
            "value": text,
            "tooltip": tooltip ?? "",
            "private": isPrivate === true,
            "loading": text === "" && (waiting ?? !facts.loaded)
        };
    }

    readonly property var aboutRows: [row("DMS", ShellVersionService.shellVersion), row("Quickshell", SystemInfo.version(f.qs)), row(I18n.tr("Compositor"), compositorText), row(I18n.tr("Distribution", "system info label"), DgopService.distribution), row(I18n.tr("Kernel", "system info label"), DgopService.kernelVersion), row(I18n.tr("CPU"), DgopService.cpuModel), row(I18n.tr("Memory"), memoryText), row(I18n.tr("GPU"), gpus.map(g => g.displayName).join(", ")), row(I18n.tr("Graphics driver", "GPU kernel driver and Mesa version"), graphicsDriver), row(I18n.tr("Display"), displays.map(d => d.value).join("; "))]

    readonly property var dmsRows: [row(I18n.tr("Shell"), ShellVersionService.shellVersion), row(I18n.tr("Codename", "DMS release codename"), ShellVersionService.shellCodename), row(I18n.tr("Backend", "noun, settings label for the backend service in use"), DMSService.cliVersion), row(I18n.tr("API", "about page card title, application programming interface version"), DMSService.apiVersion > 0 ? DMSService.apiVersion : ""), row(I18n.tr("Capabilities"), (DMSService.capabilities ?? []).join(", "), (DMSService.capabilities ?? []).join("\n")), row(I18n.tr("Settings version", "version number of the settings file format"), SettingsData.settingsConfigVersion), row(I18n.tr("Plugins"), Object.keys(PluginService.loadedPlugins ?? {}).length || "", Object.keys(PluginService.loadedPlugins ?? {}).join("\n")), row(I18n.tr("System check"), doctorText, doctorIssues.map(r => r.name + ": " + r.message).join("\n"), false, facts.doctorRunning)]

    readonly property var osRows: [row(I18n.tr("Distribution", "system info label"), DgopService.distribution), row(I18n.tr("Kernel", "system info label"), kernelText), row(I18n.tr("Init", "init system, e.g. systemd"), f.init ? f.init.replace(/\s*\(.*\)$/, "") : (DgopService.initSystem ?? "")), row(I18n.tr("Boot", "boot loader and firmware mode"), [f["boot.loader"], f["boot.uefi"] ? "UEFI" : (Object.keys(f).length > 0 ? "BIOS" : "")].filter(x => x).join(", ")), row(I18n.tr("Secure Boot", "UEFI Secure Boot state"), f["boot.secure"] === "1" ? I18n.tr("On") : f["boot.secure"] === "0" ? I18n.tr("Off") : ""), row(I18n.tr("Packages", "installed package counts per package manager"), SystemInfo.packagesText(f)), row(I18n.tr("Uptime"), DgopService.uptime ? DgopService.uptime.slice(3) : "", "", true), row(I18n.tr("Hostname"), DgopService.hostname, "", true), row(I18n.tr("User"), UserInfoService.username, "", true)]

    readonly property var hardwareRows: {
        const rows = [row(I18n.tr("Model", "computer vendor and model"), SystemInfo.dmiModel(f)), row(I18n.tr("Chassis", "computer chassis type"), chassisText), row(I18n.tr("Board", "motherboard model"), [f["dmi.board_vendor"], f["dmi.board_name"]].filter(x => x).join(" ") || (DgopService.bios?.motherboard ?? "")), row(I18n.tr("BIOS", "firmware version and date"), [f["dmi.bios_version"] || DgopService.bios?.version, f["dmi.bios_date"] || DgopService.bios?.date].filter(x => x).join(", ")), row(I18n.tr("CPU"), DgopService.cpuModel), row(I18n.tr("Cores", "CPU core and thread count"), cpuInfo?.physicalCores > 0 ? I18n.tr("%1 cores, %2 threads", "CPU core and thread count").arg(cpuInfo.physicalCores).arg(cpuInfo.count) : ""), row(I18n.tr("Memory"), Devices.memoryModulesSummary(DgopService.memoryModules?.modules) || memoryText)];
        for (const g of gpus)
            rows.push(row(I18n.tr("GPU"), g.fullName || g.displayName, g.driver));
        return rows.concat([row(I18n.tr("Graphics driver", "GPU kernel driver and Mesa version"), graphicsDriver), row("Vulkan", [f["vk.api"], f["vk.driver"]].filter(x => x).join(", ")), row(I18n.tr("Audio"), f.pipewire ? "PipeWire " + f.pipewire : ""), row(I18n.tr("Audio Output", "default audio output device"), AudioService.sink ? AudioService.displayName(AudioService.sink) : ""), row(I18n.tr("Power profile"), powerProfileText), row(I18n.tr("Battery"), BatteryService.batteryAvailable ? Math.round(BatteryService.batteryLevel) + "%" : "")]);
    }

    readonly property var desktopRows: [row(I18n.tr("Compositor"), compositorText), row(I18n.tr("Session"), [f.session === "wayland" ? "Wayland" : f.session, f.uwsm ? "uwsm" : ""].filter(x => x).join(", ")), row(I18n.tr("Theme"), themeText), row(I18n.tr("GTK theme", "system info label"), f["gs.gtk-theme"]), row(I18n.tr("Qt theme", "Qt platform theme plugin, e.g. qtengine"), f.qpa), row(I18n.tr("Icons", "icon theme"), f["gs.icon-theme"]), row(I18n.tr("Cursor", "cursor theme and size"), [f["gs.cursor-theme"], f["gs.cursor-size"] ? f["gs.cursor-size"] + " px" : ""].filter(x => x).join(", ")), row(I18n.tr("Font"), Theme.fontFamily), row(I18n.tr("Monospace font", "system info label, font name"), Theme.monoFontFamily), row(I18n.tr("Terminal"), SessionData.resolveTerminal ? SessionData.resolveTerminal() : ""), row(I18n.tr("Shell", "command line shell, e.g. zsh"), [f.shell, SystemInfo.version(f.shellver)].filter(x => x).join(" ")), row(I18n.tr("Locale"), f.lang || Qt.locale().name)]

    readonly property var displayRows: displays.map(d => row(d.name || I18n.tr("Display"), d.value))

    readonly property var storageRows: (DriveService.drives ?? []).map(d => row(d.model || d.name, Drives.driveSubtitle(d))).concat([row(I18n.tr("Root Filesystem", "the filesystem mounted at /"), rootText)])

    readonly property var networkRows: [row(I18n.tr("Connection", "system info label: network connection type"), connectionText), row(I18n.tr("Wi-Fi network", "name of the connected Wi-Fi network"), NetworkService.wifiConnected ? NetworkService.currentWifiSSID : "", "", true), row("VPN", (NetworkService.vpnActive ?? []).length > 0 ? I18n.tr("%1 active", "number of active VPN connections").arg(NetworkService.vpnActive.length) : "", (NetworkService.vpnActive ?? []).map(v => v.name ?? v).join("\n")), row("Tailscale", TailscaleService.connected ? I18n.tr("Connected") : "")]

    readonly property var sensorNames: ({
            "cpu": I18n.tr("CPU"),
            "gpu": I18n.tr("GPU"),
            "memory": I18n.tr("Memory")
        })
    readonly property var sensorRows: SystemInfo.sensorRows(DgopService.sensors, DriveService.drives, DgopService.availableGpus, sensorNames)
    readonly property int sensorSplit: Math.ceil(sensorRows.length / 2)

    readonly property var sections: [
        {
            "title": "Dux Shell",
            "icon": "deployed_code",
            "rows": dmsRows
        },
        {
            "title": I18n.tr("Operating system", "system info label"),
            "icon": "terminal",
            "rows": osRows
        },
        {
            "title": I18n.tr("Hardware", "system info section"),
            "icon": "memory",
            "rows": hardwareRows
        },
        {
            "title": I18n.tr("Desktop", "system info section: compositor, themes, fonts"),
            "icon": "palette",
            "rows": desktopRows
        },
        {
            "title": I18n.tr("Displays"),
            "icon": "desktop_windows",
            "rows": displayRows
        },
        {
            "title": I18n.tr("Storage", "system monitor device group: disks"),
            "icon": "hard_drive",
            "rows": storageRows
        },
        {
            "title": I18n.tr("Network"),
            "icon": "lan",
            "rows": networkRows
        }
    ]

    function copy(text) {
        Quickshell.execDetached([Proc.dmsBin, "cl", "copy", "--", text]);
        ToastService.showInfo(I18n.tr("Copied to clipboard"));
    }

    // Everything on the page except personal rows (hostname, user, network names), plus system check findings.
    function reportText() {
        const issues = doctorIssues.map(r => row("[" + r.status + "] " + r.name, r.message));
        return SystemInfo.report(I18n.tr("System report", "title of the copied system information"), sections.concat(issues.length ? [
            {
                "title": I18n.tr("System check"),
                "rows": issues
            }
        ] : []));
    }

    function summaryText() {
        return SystemInfo.summary([["DMS " + ShellVersionService.shellVersion, f.qs ? "Quickshell " + SystemInfo.version(f.qs) : "", compositorText].filter(x => x.trim() !== "" && x !== "DMS ").join(" · "), [DgopService.distribution, kernelText ? "Linux " + kernelText : "", f.session === "wayland" ? "Wayland" + (f.uwsm ? " (uwsm)" : "") : ""].filter(x => x).join(" · "), [DgopService.cpuModel, memoryText].filter(x => x).join(" · "), gpus.map(g => g.displayName).join(", ") + (graphicsDriver ? " (" + graphicsDriver + ")" : ""), displays.map(d => d.value).join("; "), doctorText && !facts.doctorRunning ? I18n.tr("System check") + ": " + doctorText : ""]);
    }

    DFlickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + (root.fabBar?.reservedHeight ?? 0)

        ColumnLayout {
            id: column
            width: scroll.width
            spacing: Theme.spacingXL

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: DgopService.hostname
                    font.pixelSize: Theme.fontSizeXXLarge
                    color: Theme.surfaceText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: [DgopService.distribution, DgopService.kernelVersion ? "Linux " + DgopService.kernelVersion : ""].filter(x => x).join(", ")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: DgopService.uptime ? I18n.tr("Up %1", "system uptime, %1 is a duration").arg(DgopService.uptime.slice(3)) : ""
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: aboutColumn.implicitHeight + Theme.spacingL * 2
                radius: Theme.cornerRadiusL
                color: Theme.withAlpha(Theme.primaryContainer, 0.45)

                ColumnLayout {
                    id: aboutColumn
                    x: Theme.spacingL
                    y: Theme.spacingL
                    width: parent.width - Theme.spacingL * 2
                    spacing: Theme.spacingM

                    SectionTitle {
                        text: I18n.tr("About")
                        iconName: "info"
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= SettingsMetrics.compactBreakpoint ? 2 : 1
                        columnSpacing: Theme.spacingL
                        rowSpacing: Theme.spacingL

                        Rows {
                            rows: root.aboutRows.slice(0, 5)
                            slotColor: Theme.surfaceContainer
                        }

                        Rows {
                            rows: root.aboutRows.slice(5)
                            slotColor: Theme.surfaceContainer
                        }
                    }
                }
            }

            GridLayout {
                id: sectionGrid
                Layout.fillWidth: true
                columns: width >= SettingsMetrics.compactBreakpoint ? 2 : 1
                columnSpacing: Theme.spacingL
                rowSpacing: Theme.spacingXL

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: Theme.spacingXL

                    Repeater {
                        model: sectionGrid.columns === 2 ? [0, 3, 4, 6] : [0, 1, 2, 3, 4, 5, 6]

                        Section {
                            required property int modelData
                            readonly property var section: root.sections[modelData]
                            title: section.title
                            iconName: section.icon
                            rows: section.rows
                        }
                    }
                }

                ColumnLayout {
                    visible: sectionGrid.columns === 2
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: Theme.spacingXL

                    Repeater {
                        model: sectionGrid.columns === 2 ? [1, 2, 5] : []

                        Section {
                            required property int modelData
                            readonly property var section: root.sections[modelData]
                            title: section.title
                            iconName: section.icon
                            rows: section.rows
                        }
                    }
                }
            }

            ColumnLayout {
                visible: root.sensorRows.length > 0
                Layout.fillWidth: true
                spacing: Theme.spacingM

                SectionTitle {
                    text: I18n.tr("Sensors", "hardware sensors section")
                    iconName: "thermostat"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingL

                    SensorGroup {
                        rows: root.sensorRows.slice(0, root.sensorSplit)
                    }

                    SensorGroup {
                        rows: root.sensorRows.slice(root.sensorSplit)
                    }
                }
            }
        }
    }

    component SectionTitle: RowLayout {
        id: sectionTitle

        property string text: ""
        property string iconName: ""

        spacing: Theme.spacingS

        DIcon {
            name: sectionTitle.iconName
            size: Theme.iconSizeSmall + 2
            color: Theme.primary
        }

        StyledText {
            text: sectionTitle.text
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.primary
        }
    }

    component Rows: SettingsGroup {
        id: rowsGroup

        property var rows: []
        readonly property var shown: rows.filter(r => r && (r.value !== "" || r.loading))

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        visible: shown.length > 0
        customPaddingV: 0
        customPaddingH: Theme.spacingL

        Repeater {
            model: rowsGroup.shown.length

            StatRow {
                required property int index
                readonly property var row: rowsGroup.shown[index] ?? ({})
                label: row.label ?? ""
                value: row.value ?? ""
                loading: row.loading === true
                tooltip: row.tooltip ?? ""
            }
        }
    }

    component Section: ColumnLayout {
        id: section

        property string title: ""
        property string iconName: ""
        property var rows: []

        Layout.fillWidth: true
        visible: rows.some(r => r && (r.value !== "" || r.loading))
        spacing: Theme.spacingM

        SectionTitle {
            text: section.title
            iconName: section.iconName
        }

        Rows {
            rows: section.rows
        }
    }

    component SensorGroup: SettingsGroup {
        id: group

        property var rows: []

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        customPaddingV: 0
        customPaddingH: Theme.spacingL

        Repeater {
            model: group.rows.length

            Item {
                id: sensor

                required property int index
                readonly property var modelData: group.rows[index] ?? ({})

                height: Theme.iconButtonSize

                StyledText {
                    anchors.left: parent.left
                    anchors.right: bar.left
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: sensor.modelData.name ?? ""
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: bar
                    anchors.right: valueText.left
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(Theme.fontSizeSmall * 10, sensor.width / 4)
                    height: Theme.spacingS
                    radius: height / 2
                    color: Theme.surfaceContainerHighest
                    opacity: sensor.modelData.ratio == null ? 0 : 1

                    Rectangle {
                        width: parent.width * (sensor.modelData.ratio ?? 0)
                        height: parent.height
                        radius: height / 2
                        color: (sensor.modelData.ratio ?? 0) >= 0.9 ? Theme.error : Theme.primary
                    }
                }

                NumericText {
                    id: valueText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.iconButtonSize * 2
                    text: sensor.modelData.value ?? ""
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }

    SettingsFabBar {
        DFab {
            text: I18n.tr("Copy summary", "button, copies a short system overview for bug reports")
            iconName: "short_text"
            colorRole: "secondaryContainer"
            onClicked: root.copy(root.summaryText())
        }

        DFab {
            text: I18n.tr("Copy report", "button, copies the full system report without personal details")
            iconName: "content_copy"
            onClicked: root.copy(root.reportText())
        }
    }
}
