pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "Drives.js" as Drives
import "../../Common/Format.js" as Format
import "../../Services/SysmonDevices.js" as Devices

Rectangle {
    id: root

    property var drive: null
    property var mounts: []

    signal installRequested

    readonly property string level: Drives.healthLevel(drive)

    DriveHealth {
        id: health
        level: root.level
    }

    readonly property bool asleep: drive?.asleep ?? false
    readonly property var rates: (DgopService.diskRates ?? []).find(d => d.device === drive?.name) ?? null
    readonly property var history: DgopService.deviceHistory[Devices.deviceKey("disk", drive?.name ?? "")] ?? ({})
    readonly property real axisMax: Devices.rateAxisMax(history.a, history.b, 1024 * 1024)
    readonly property var allRows: Drives.summaryRows(drive)
    readonly property var powerOn: allRows.find(r => r.id === "powerOnTime") ?? null
    readonly property var smartRows: allRows.filter(r => r.id !== "wear" && r.id !== "powerOnTime" && r.id !== "dataWritten")
    readonly property var wear: drive?.nvme?.percentUsed ?? null
    readonly property color healthTint: level === "failing" ? Theme.error : level === "warning" ? Theme.warning : Theme.success
    readonly property real pad: Theme.spacingL
    property bool expanded: false
    readonly property var filesystems: Drives.partitionStrip(drive, mounts)
    readonly property var statRows: {
        const rows = [];
        const add = (label, value, tooltip) => rows.push({
                "label": label,
                "value": value,
                "tooltip": tooltip ?? ""
            });
        if (!asleep && rates?.busy != null)
            add(I18n.tr("Busy", "share of time a disk is busy"), Math.round(rates.busy) + "%");
        if (!asleep && rates?.responseTime != null)
            add(I18n.tr("Response time", "average time a disk takes per request"), rates.responseTime.toFixed(2) + " ms");
        if (wear !== null)
            add(I18n.tr("Wear", "SSD wear level, percent of rated endurance used"), wear + "%");
        if (powerOn !== null)
            add(I18n.tr("Power-on time", "total time a drive has been powered on"), rowValue(powerOn));
        if (drive?.nvme?.dataWritten != null)
            add(I18n.tr("Written total", "total data written"), Format.formatBytes(drive.nvme.dataWritten, true));
        if (drive?.firmware)
            add(I18n.tr("Firmware", "drive firmware revision"), drive.firmware);
        for (const r of smartRows)
            add(rowLabel(r.id), String(rowValue(r)));
        for (const r of deviceRows)
            add(r.label, r.value);
        return rows;
    }

    implicitHeight: body.implicitHeight + pad * 2
    radius: Theme.cornerRadiusL
    color: Theme.surfaceContainerLow

    function rowLabel(id) {
        switch (id) {
        case "criticalWarning":
            return I18n.tr("Critical warning", "SSD health: critical warning flags");
        case "spare":
            return I18n.tr("Spare blocks left", "SSD health: share of spare blocks still available");
        case "mediaErrors":
            return I18n.tr("Media errors", "SSD health: unrecovered data integrity errors");
        case "dataRead":
            return I18n.tr("Read total", "total data read");
        case "dataWritten":
            return I18n.tr("Written total", "total data written");
        case "unsafeShutdowns":
            return I18n.tr("Unsafe shutdowns", "SSD health: power losses without a clean shutdown");
        case "powerOnTime":
            return I18n.tr("Power-on time", "total time a drive has been powered on");
        case "selftest":
            return I18n.tr("Last self-test", "drive health: result of the last self-test");
        case "reallocated":
            return I18n.tr("Reallocated sectors", "HDD health: sectors remapped after errors");
        case "pending":
            return I18n.tr("Current pending sectors", "HDD health: sectors waiting to be remapped");
        case "uncorrectable":
            return I18n.tr("Offline uncorrectable", "HDD health: sectors that could not be read or fixed");
        case "crc":
            return I18n.tr("Cable errors", "drive health: data cable CRC errors");
        case "startStop":
            return I18n.tr("Start/stop count", "HDD health: spindle start and stop count");
        case "loadCycles":
            return I18n.tr("Head load cycles", "HDD health: read head load/unload count");
        case "spinUp":
            return I18n.tr("Spin-up time", "HDD health: time to spin the platters up");
        }
        return id;
    }

    function rowValue(r) {
        if (!r)
            return "";
        if (r.id === "powerOnTime") {
            const text = r.unit === "hours" ? I18n.tr("%1 hours") : r.unit === "days" ? I18n.tr("%1 days") : I18n.tr("%1 years", "duration in years, %1 is a number");
            return text.arg(r.value);
        }
        if (r.id === "criticalWarning" && r.value === "none")
            return I18n.tr("None");
        if (r.id === "selftest")
            return r.value === "ok" ? I18n.tr("OK") : r.value === "running" ? I18n.tr("Running") : I18n.tr("Error");
        return r.value;
    }

    function spaceText(fs) {
        if (fs.usedRatio !== null && fs.size > 0)
            return I18n.tr("%1 of %2 used", "partition space, e.g. 1.2 TB of 2 TB used").arg(Drives.formatCapacity(fs.size * fs.usedRatio)).arg(Drives.formatCapacity(fs.size));
        return fs.size > 0 ? Drives.formatCapacity(fs.size) : "";
    }

    readonly property var deviceRows: {
        const q = drive?.queue ?? null;
        const yes = I18n.tr("Yes");
        const sector = q?.logicalBlock > 0 ? (q.physicalBlock > q.logicalBlock ? q.logicalBlock + " B / " + Format.formatBytes(q.physicalBlock, true) : q.logicalBlock + " B") : "";
        const bus = drive?.connectionBus ? drive.connectionBus.toUpperCase() : "";
        const rows = [[I18n.tr("Serial number", "drive serial number"), drive?.serial ?? ""], [I18n.tr("WWN", "drive world wide name, a unique id"), drive?.wwn ?? ""], [I18n.tr("Interface"), [bus, drive?.link ?? ""].filter(s => s).join(", ")], [I18n.tr("Partition table"), drive?.tableType === "gpt" ? "GPT" : drive?.tableType === "dos" ? "MBR" : ""], [I18n.tr("Sector size", "logical and physical disk sector size"), sector], [I18n.tr("I/O scheduler", "Linux block I/O scheduler"), q?.scheduler ?? ""], [I18n.tr("Write cache", "disk write cache mode"), q?.writeCache ?? ""], [I18n.tr("TRIM", "SSD discard support"), q ? (q.trim ? yes : I18n.tr("No")) : ""], [I18n.tr("Queue depth", "block device request queue depth"), q?.depth > 0 ? String(q.depth) : ""], [I18n.tr("Removable"), drive?.removable ? yes : ""]];
        return rows.filter(r => r[1] !== "").map(r => ({
                    "label": r[0],
                    "value": r[1]
                }));
    }

    readonly property var reliabilityRows: smartRows.map(r => ({
                "label": rowLabel(r.id),
                "value": String(rowValue(r))
            }))

    // A titled grouped list; count models so a 30 s drive poll rebinds rows instead of rebuilding them.
    component DetailGroup: ColumnLayout {
        id: group

        property string title: ""
        property var rows: []

        visible: rows.length > 0
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        spacing: 0

        SettingsSectionLabel {
            Layout.fillWidth: true
            topGap: 0
            text: group.title
        }

        SettingsGroup {
            Layout.fillWidth: true
            customPaddingV: 0
            customPaddingH: Theme.spacingL

            Repeater {
                model: group.rows.length

                StatRow {
                    required property int index
                    readonly property var row: group.rows[index] ?? ({})
                    height: Theme.buttonHeightXS
                    label: row.label ?? ""
                    value: row.value ?? ""
                }
            }
        }
    }

    function cardText() {
        const lines = [drive?.model || drive?.name || "", Drives.driveSubtitle(drive), drive?.device ?? ""];
        if (drive?.temperature != null)
            lines.push(I18n.tr("Temperature") + ": " + Devices.formatTemp(drive.temperature));
        if (level !== "")
            lines.push(I18n.tr("Health") + ": " + health.text);
        for (const r of statRows)
            lines.push(r.label + ": " + r.value);
        for (const fs of filesystems)
            lines.push([fs.swap ? I18n.tr("Swap") : fs.label, fs.fsType, spaceText(fs)].filter(x => x).join(", "));
        const report = smartReport.reportText();
        return lines.filter(l => l !== "").join("\n") + (report ? "\n\n" + report : "");
    }

    function warnTooltip() {
        return Drives.warnRows(drive).map(r => rowLabel(r.id) + ": " + rowValue(r)).join("\n");
    }

    ColumnLayout {
        id: body
        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        spacing: Theme.spacingL

        Item {
            Layout.fillWidth: true
            implicitHeight: header.implicitHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: -Theme.spacingS
                radius: Theme.cornerRadiusM
                color: "transparent"

                StateLayer {
                    onClicked: root.expanded = !root.expanded
                }
            }

            RowLayout {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.spacingL

                Rectangle {
                    Layout.preferredWidth: Theme.iconButtonSize
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: Theme.cornerRadiusM
                    color: Theme.secondaryContainer

                    DeviceIcon {
                        anchors.centerIn: parent
                        name: Drives.driveIcon(root.drive)
                        size: Theme.iconSize
                        color: Theme.onSecondaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.drive?.model || root.drive?.name || ""
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.surfaceText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: Drives.driveSubtitle(root.drive)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                }

                MetricChart {
                    visible: !root.expanded
                    Layout.preferredWidth: Theme.iconButtonSize * 2
                    Layout.preferredHeight: Theme.buttonHeightXXS
                    compact: true
                    values: root.history.a ?? []
                    secondaryValues: root.history.b ?? []
                    maximum: root.axisMax
                    historyLength: DgopService.historySize
                }

                NumericText {
                    visible: root.drive?.temperature != null
                    text: Devices.formatTemp(root.drive?.temperature ?? null)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                Pill {
                    visible: root.asleep
                    text: I18n.tr("Asleep", "drive is in standby and was not woken")
                    dotColor: Theme.surfaceVariantText
                    tooltip: (root.drive?.smartUpdated ?? 0) > 0 ? Qt.formatDateTime(new Date(root.drive.smartUpdated * 1000), Locale.ShortFormat) : ""
                }

                Pill {
                    visible: root.level !== ""
                    text: health.text
                    dotColor: root.healthTint
                    textColor: root.level === "healthy" ? Theme.surfaceText : root.healthTint
                    tooltip: root.warnTooltip()
                }

                DActionButton {
                    iconName: "content_copy"
                    iconColor: Theme.surfaceText
                    tooltipText: I18n.tr("Copy")
                    onClicked: Quickshell.execDetached(["dms", "cl", "copy", "--", root.cardText()])
                }

                DActionButton {
                    iconName: "expand_more"
                    rotation: root.expanded ? 180 : 0
                    tooltipText: root.expanded ? I18n.tr("Collapse") : I18n.tr("Expand")
                    onClicked: root.expanded = !root.expanded
                }
            }
        }

        RowLayout {
            visible: root.expanded
            Layout.fillWidth: true
            spacing: Theme.spacingL

            ChartCard {
                Layout.fillWidth: true
                Layout.horizontalStretchFactor: 3
                Layout.alignment: Qt.AlignTop
                cardColor: Theme.surfaceContainer
                chartHeight: Math.max(Theme.listItemHeight * 1.5, stats.height - Theme.spacingL * 2 - Theme.spacingS * 2 - Theme.fontSizeSmall * 3)
                label: I18n.tr("Disk read", "disk read rate")
                valueText: root.rates?.readRate != null ? Format.formatRate(root.rates.readRate, 1) : "—"
                secondaryLabel: I18n.tr("Disk write", "disk write rate")
                secondaryValueText: root.rates?.writeRate != null ? Format.formatRate(root.rates.writeRate, 1) : "—"
                values: root.history.a ?? []
                secondaryValues: root.history.b ?? []
                maximum: root.axisMax
                maximumText: Format.formatRate(root.axisMax, 1)
                historyLength: DgopService.historySize
            }

            SettingsGroup {
                id: stats
                Layout.fillWidth: true
                Layout.horizontalStretchFactor: 2
                Layout.alignment: Qt.AlignTop
                customPaddingV: 0
                customPaddingH: Theme.spacingL

                Repeater {
                    model: root.statRows.length

                    StatRow {
                        required property int index
                        readonly property var row: root.statRows[index] ?? ({})
                        height: Theme.buttonHeightXS
                        label: row.label ?? ""
                        value: row.value ?? ""
                        tooltip: row.tooltip ?? ""
                    }
                }
            }
        }

        SettingsGroup {
            visible: root.expanded && root.filesystems.length > 0
            Layout.fillWidth: true
            customPaddingV: 0
            customPaddingH: Theme.spacingL

            Repeater {
                model: root.filesystems.length

                RowLayout {
                    id: fsRow

                    required property int index
                    readonly property var modelData: root.filesystems[index] ?? ({})

                    width: parent?.width ?? 0
                    height: Theme.buttonHeightS
                    spacing: Theme.spacingL

                    DIcon {
                        name: fsRow.modelData.swap ? "swap_horiz" : fsRow.modelData.encrypted ? "lock" : "folder"
                        size: Theme.iconSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: fsRow.modelData.swap ? I18n.tr("Swap") : fsRow.modelData.label ?? ""
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideMiddle
                    }

                    StyledText {
                        Layout.preferredWidth: Theme.fontSizeMedium * 7
                        text: fsRow.modelData.fsType ?? ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        Layout.preferredWidth: Theme.fontSizeMedium * 10
                        Layout.preferredHeight: Theme.spacingS
                        radius: height / 2
                        color: Theme.surfaceContainerHighest
                        opacity: fsRow.modelData.usedRatio != null ? 1 : 0

                        Rectangle {
                            width: parent.width * Math.min(1, fsRow.modelData.usedRatio ?? 0)
                            height: parent.height
                            radius: height / 2
                            color: Theme.primary
                        }
                    }

                    NumericText {
                        Layout.preferredWidth: Theme.fontSizeMedium * 12
                        horizontalAlignment: Text.AlignRight
                        text: root.spaceText(fsRow.modelData)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }
                }
            }
        }

        RowLayout {
            visible: root.expanded
            Layout.fillWidth: true
            spacing: Theme.spacingL

            DetailGroup {
                title: I18n.tr("Device")
                rows: root.deviceRows
            }

            DetailGroup {
                title: I18n.tr("Reliability", "drive health counters section")
                rows: root.reliabilityRows
            }
        }

        RowLayout {
            visible: root.expanded
            Layout.fillWidth: true
            spacing: Theme.spacingL

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                visible: DriveService.smartctlPath === "" && DriveService.installCommand === ""
                text: I18n.tr("Requires %1", "missing program", true).arg("smartctl")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            DButton {
                visible: DriveService.smartctlPath === "" && DriveService.installCommand !== ""
                text: I18n.tr("Install smartmontools", "button, installs the smartmontools package")
                iconName: "download"
                backgroundColor: Theme.secondaryContainer
                textColor: Theme.onSecondaryContainer
                onClicked: root.installRequested()
            }

            DButton {
                visible: DriveService.smartctlPath !== "" && !DgopService.unlocked
                text: I18n.tr("Full SMART report", "drive health report from smartctl")
                iconName: "lock_open"
                backgroundColor: Theme.secondaryContainer
                textColor: Theme.onSecondaryContainer
                tooltipText: I18n.tr("Authentication Required")
                enabled: !DgopService.unlocking
                onClicked: DgopService.unlock()
            }
        }

        SmartReport {
            id: smartReport
            Layout.fillWidth: true
            drive: root.drive
            wanted: root.expanded
            visible: root.expanded && state_ !== "idle"
        }
    }

    component Pill: Rectangle {
        id: pill

        property string text: ""
        property color dotColor: Theme.success
        property color textColor: Theme.surfaceText
        property string tooltip: ""

        implicitWidth: pillRow.implicitWidth + Theme.spacingM * 2
        implicitHeight: Theme.buttonHeightXS
        radius: height / 2
        color: Theme.surfaceContainerHighest

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: Theme.spacingS

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.spacingS
                height: width
                radius: width / 2
                color: pill.dotColor
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                font.pixelSize: Theme.fontSizeSmall
                color: pill.textColor
            }
        }

        MouseArea {
            id: pillHover
            anchors.fill: parent
            hoverEnabled: pill.tooltip !== ""
            acceptedButtons: Qt.NoButton
        }

        DTooltipHost {
            text: pill.tooltip
            target: pill
            hoverArea: pillHover
        }
    }
}
