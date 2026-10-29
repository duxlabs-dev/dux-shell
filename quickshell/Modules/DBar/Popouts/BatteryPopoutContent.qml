pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Services.UPower
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    property bool active: false
    property bool batteryRefHeld: false
    property real contentPadding: PopoutMetrics.contentPadding
    readonly property var historyDevice: BatteryService.usePreferred ? BatteryService.preferredDevice : BatteryService.device
    readonly property bool multipleBatteries: !BatteryService.usePreferred && BatteryService.batteries.length > 1
    readonly property var stats: {
        const values = [];
        const health = parseInt(BatteryService.batteryHealth);
        if (isFinite(health) && health > 0)
            values.push({
                label: I18n.tr("Health"),
                value: root.formatPercent(health),
                icon: "ecg_heart",
                ratio: health / 100,
                color: health < 80 ? Theme.error : Theme.onSurface
            });
        if (history.temperature !== 0)
            values.push({
                label: I18n.tr("Temperature", "battery temperature"),
                value: Math.round(history.temperature) + "°C",
                icon: "device_thermostat",
                ratio: -1,
                color: Theme.onSurface
            });
        if (BatteryService.batteryCapacity > 0)
            values.push({
                label: I18n.tr("Capacity", "battery energy capacity stat label"),
                value: root.formatCapacity(BatteryService.batteryCapacity),
                icon: "battery_full",
                ratio: -1,
                color: Theme.onSurface
            });
        if (Math.abs(BatteryService.signedChangeRate) > 0.05)
            values.push({
                label: I18n.tr("Power", "battery stat label, charge or discharge rate in watts", true),
                value: (BatteryService.signedChangeRate > 0 ? "+" : "") + BatteryService.signedChangeRate.toFixed(1) + " W",
                icon: "electrical_services",
                ratio: -1,
                color: Theme.onSurface
            });
        return values;
    }
    readonly property bool levelLow: BatteryService.isLowBattery && !BatteryService.isCharging
    readonly property color levelColor: levelLow ? Theme.error : Theme.onSurface
    readonly property string timeInfo: {
        if (!BatteryService.batteryAvailable)
            return PowerProfileWatcher.available ? I18n.tr("Power profile management available") : I18n.tr("power-profiles-daemon not available");
        const time = BatteryService.formatTimeRemaining();
        if (time === "Unknown")
            return BatteryService.batteryStatus;
        const estimated = BatteryService.formatEstimatedTime();
        const value = estimated ? `${time} (${estimated})` : time;
        return `${BatteryService.batteryStatus} · ${value}`;
    }

    signal dismissRequested

    implicitHeight: contentColumn.implicitHeight + contentPadding * 2
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    function syncBatteryRef(wanted) {
        if (wanted === batteryRefHeld)
            return;
        batteryRefHeld = wanted;
        if (wanted) {
            BatteryService.addRef();
            return;
        }
        BatteryService.removeRef();
    }

    onActiveChanged: {
        syncBatteryRef(active);
        if (active)
            focusTimer.restart();
    }
    Component.onCompleted: syncBatteryRef(active)
    Component.onDestruction: syncBatteryRef(false)
    Keys.onEscapePressed: event => {
        dismissRequested();
        event.accepted = true;
    }

    function setProfile(profile) {
        if (PowerProfileWatcher.applyProfile(profile))
            return;
        const message = PowerProfileWatcher.available ? I18n.tr("Failed to set power profile") : I18n.tr("power-profiles-daemon not available");
        ToastService.showError(message);
    }

    function formatPercent(value) {
        return Math.round(value) + "%";
    }

    function formatCapacity(value) {
        return value > 0 ? value.toFixed(1) + " Wh" : I18n.tr("Unknown");
    }

    function deviceTime(device) {
        let time = 0;
        switch (device.state) {
        case UPowerDeviceState.Charging:
            time = device.timeToFull;
            break;
        case UPowerDeviceState.Discharging:
            time = device.timeToEmpty > 0 ? device.timeToEmpty : device.changeRate > 0 ? 3600 * device.energy / device.changeRate : 0;
            break;
        }
        if (!isFinite(time) || time <= 0 || time > 86400)
            return I18n.tr("Unknown");
        return BatteryService.formatDuration(time);
    }

    function deviceDetails(device) {
        const values = [];
        if (device.healthSupported && device.healthPercentage > 0)
            values.push({
                label: I18n.tr("Health"),
                value: root.formatPercent(device.healthPercentage),
                color: device.healthPercentage < 80 ? Theme.error : Theme.onSurface
            });
        if (device.energyCapacity > 0)
            values.push({
                label: I18n.tr("Capacity"),
                value: root.formatCapacity(device.energyCapacity),
                color: Theme.onSurface
            });
        const time = root.deviceTime(device);
        if (time !== I18n.tr("Unknown"))
            values.push({
                label: device.state === UPowerDeviceState.Charging ? I18n.tr("To Full") : I18n.tr("Left"),
                value: time,
                color: Theme.onSurface
            });
        return values;
    }

    Timer {
        id: focusTimer
        interval: 0
        onTriggered: root.forceActiveFocus()
    }

    BatteryHistory {
        id: history
        active: root.active && BatteryService.batteryAvailable
        nativePath: root.historyDevice?.nativePath ?? ""
        historyEnabled: false
    }

    DFlickable {
        id: flickable
        anchors.fill: parent
        clip: true
        contentHeight: root.implicitHeight
        readonly property Item focusedItem: root.Window.window?.activeFocusItem ?? null

        onFocusedItemChanged: {
            if (!focusedItem || focusedItem === root || !root.active)
                return;
            let ancestor = focusedItem.parent;
            while (ancestor && ancestor !== contentColumn)
                ancestor = ancestor.parent;
            if (!ancestor)
                return;
            const position = focusedItem.mapToItem(contentItem, 0, 0);
            revealRange(position.y - Theme.spacingS, position.y + focusedItem.height + Theme.spacingS);
        }

        Column {
            id: contentColumn
            x: root.contentPadding
            y: root.contentPadding
            width: parent.width - root.contentPadding * 2
            spacing: PopoutMetrics.contentGap

            DCard {
                width: parent.width
                height: heroRow.implicitHeight + pad * 2
                restRadius: Theme.cornerRadiusL

                Row {
                    id: heroRow
                    width: parent.width
                    spacing: Theme.spacingM

                    DRingGauge {
                        id: heroGauge
                        width: Theme.iconButtonSize + Theme.spacingM
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        value: BatteryService.hasBatteryReading ? BatteryService.displayBatteryLevel / 100 : -1
                        trackGap: Theme.spacingXXS
                        ringColor: root.levelLow ? Theme.error : Theme.primary
                        animated: root.active

                        DIcon {
                            anchors.centerIn: parent
                            name: BatteryService.isCharging ? "bolt" : BatteryService.getBatteryIcon()
                            size: Theme.iconSize
                            color: root.levelLow ? Theme.error : Theme.primary
                        }
                    }

                    Column {
                        width: parent.width - heroGauge.width - settingsButton.width - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXXS

                        StyledText {
                            width: parent.width
                            text: root.formatPercent(BatteryService.displayBatteryLevelText)
                            visible: BatteryService.hasBatteryReading
                            font.pixelSize: Theme.fontSizeXXLarge
                            color: root.levelColor
                        }

                        StyledText {
                            width: parent.width
                            text: root.timeInfo
                            visible: text !== ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.onSurfaceVariant
                            wrapMode: Text.WordWrap
                        }
                    }

                    DActionButton {
                        id: settingsButton
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "settings"
                        Accessible.name: I18n.tr("Settings")
                        onClicked: {
                            PopoutService.openSettingsWithTab("battery");
                            root.dismissRequested();
                        }
                    }
                }
            }

            Row {
                id: statsRow
                width: parent.width
                spacing: Theme.groupedListGap
                visible: BatteryService.batteryAvailable && root.stats.length > 0

                Repeater {
                    model: root.stats

                    StatTile {
                        required property var modelData
                        required property int index
                        width: (statsRow.width - statsRow.spacing * (root.stats.length - 1)) / root.stats.length
                        label: modelData.label
                        value: modelData.value
                        iconName: modelData.icon
                        ratio: modelData.ratio
                        valueColor: modelData.color
                        first: index === 0
                        last: index === root.stats.length - 1
                    }
                }
            }

            DCard {
                width: parent.width
                height: profileColumn.implicitHeight + pad * 2
                restRadius: Theme.cornerRadiusL
                visible: PowerProfileWatcher.available

                Column {
                    id: profileColumn
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width
                        text: I18n.tr("Power profile")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: Theme.primary
                    }

                    DButtonGroup {
                        id: profileGroup
                        readonly property var profiles: PowerProfileWatcher.availableProfiles

                        width: parent.width
                        fillWidth: true
                        iconOnly: true
                        checkEnabled: false
                        enabled: PowerProfileWatcher.available
                        model: profiles.map(profile => ({
                                    text: Theme.getPowerProfileLabel(profile),
                                    icon: ["eco", "speed", "bolt"][profile]
                                }))
                        currentIndex: profiles.indexOf(PowerProfileWatcher.currentProfile)
                        onSelectionChanged: (index, selected) => {
                            if (selected)
                                root.setProfile(profiles[index]);
                        }
                    }
                }
            }

            DCard {
                id: devicesCard
                readonly property int columns: Math.min(BatteryService.peripheralDevices.length, 4)
                width: parent.width
                height: devicesFlow.implicitHeight + pad * 2
                restRadius: Theme.cornerRadiusL
                visible: BatteryService.peripheralDevices.length > 0

                Flow {
                    id: devicesFlow
                    width: parent.width

                    Repeater {
                        model: ScriptModel {
                            values: BatteryService.peripheralDevices
                        }

                        DeviceGauge {
                            required property var modelData
                            required property int index
                            width: devicesFlow.width / Math.max(1, devicesCard.columns)
                            name: modelData.name
                            percentage: modelData.percentage
                            iconName: modelData.charging ? "bolt" : modelData.icon
                            accent: index % 2 === 0 ? Theme.primary : Theme.tertiary
                            animated: root.active
                        }
                    }
                }
            }

            SettingsGroup {
                visible: typeof PowerProfiles !== "undefined" && PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                slotColor: Theme.errorContainer

                SettingsRow {
                    iconName: "warning"
                    iconColor: Theme.onErrorContainer
                    titleColor: Theme.onErrorContainer
                    subtitleColor: Theme.onErrorContainer
                    title: I18n.tr("Power Profile Degradation")
                    subtitle: {
                        if (typeof PowerProfiles === "undefined")
                            return "";
                        switch (PowerProfiles.degradationReason) {
                        case PerformanceDegradationReason.LapDetected:
                            return I18n.tr("Lap detected", "reason for reduced power profile performance");
                        case PerformanceDegradationReason.HighTemperature:
                            return I18n.tr("High temperature", "reason for reduced power profile performance");
                        default:
                            return "";
                        }
                    }
                }
            }

            DCollapsibleSection {
                width: parent.width
                visible: root.multipleBatteries
                title: I18n.tr("Individual Batteries")

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: ScriptModel {
                            values: root.multipleBatteries ? BatteryService.batteries : []
                        }

                        delegate: DCard {
                            id: deviceCard
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: deviceColumn.implicitHeight + pad * 2
                            restRadius: Theme.cornerRadiusL

                            Column {
                                id: deviceColumn
                                width: parent.width
                                spacing: Theme.spacingS

                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    Column {
                                        width: parent.width - (devicePercent.visible ? devicePercent.width + parent.spacing : 0)
                                        spacing: Theme.spacingXXS

                                        StyledText {
                                            width: parent.width
                                            text: deviceCard.modelData.model || I18n.tr("Battery %1", "fallback battery device name, %1 is the battery number").arg(deviceCard.index + 1)
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Theme.fontWeightMedium
                                            color: Theme.onSurface
                                            wrapMode: Text.WordWrap
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: deviceCard.modelData.nativePath
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.onSurfaceVariant
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    StyledText {
                                        id: devicePercent
                                        text: root.formatPercent(deviceCard.modelData.percentage * 100)
                                        visible: deviceCard.modelData.ready && (deviceCard.modelData.percentage > 0 || deviceCard.modelData.state === UPowerDeviceState.Empty)
                                        font.pixelSize: Theme.fontSizeLarge
                                        font.weight: Theme.fontWeightMedium
                                        color: Theme.onSurface
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    text: BatteryService.translateBatteryState(deviceCard.modelData.state)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.primary
                                    wrapMode: Text.WordWrap
                                }

                                Row {
                                    id: deviceDetailsRow
                                    readonly property var values: root.deviceDetails(deviceCard.modelData)
                                    width: parent.width
                                    spacing: Theme.spacingS
                                    visible: values.length > 0

                                    Repeater {
                                        model: deviceDetailsRow.values

                                        DetailValue {
                                            required property var modelData
                                            width: (deviceDetailsRow.width - deviceDetailsRow.spacing * Math.max(0, deviceDetailsRow.values.length - 1)) / Math.max(1, deviceDetailsRow.values.length)
                                            label: modelData.label
                                            value: modelData.value
                                            valueColor: modelData.color
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component DeviceGauge: Item {
        id: device
        property string name: ""
        property int percentage: 0
        property string iconName: ""
        property color accent: Theme.primary
        property bool animated: true
        readonly property bool low: percentage <= SettingsData.batteryLowThreshold
        implicitHeight: deviceName.y + deviceName.implicitHeight

        DRingGauge {
            id: deviceRing
            width: Theme.iconButtonSize * 2
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            value: device.percentage / 100
            startAngle: 135
            spanAngle: 270
            strokeWidth: Theme.spacingXS + Theme.spacingXXS
            trackGap: Theme.spacingXXS
            ringColor: device.low ? Theme.error : device.accent
            animated: device.animated

            DIcon {
                anchors.centerIn: parent
                name: device.iconName
                size: Theme.iconSize
                color: device.low ? Theme.error : device.accent
            }
        }

        StyledText {
            id: deviceLevel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: deviceRing.bottom
            text: String(device.percentage)
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.onSurface
        }

        StyledText {
            id: deviceName
            y: deviceLevel.y + deviceLevel.implicitHeight + Theme.spacingXXS
            width: parent.width
            text: device.name
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.onSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }

    component StatTile: DCard {
        id: tile
        property string label: ""
        property string value: ""
        property string iconName: ""
        property real ratio: -1
        property color valueColor: Theme.onSurface
        property bool first: false
        property bool last: false
        readonly property real startRadius: first ? Theme.cornerRadiusL : Theme.groupedListInnerRadius
        readonly property real endRadius: last ? Theme.cornerRadiusL : Theme.groupedListInnerRadius

        height: tileColumn.implicitHeight + pad * 2
        restRadius: Theme.groupedListInnerRadius
        topLeftRadius: I18n.isRtl ? endRadius : startRadius
        bottomLeftRadius: topLeftRadius
        topRightRadius: I18n.isRtl ? startRadius : endRadius
        bottomRightRadius: topRightRadius

        Column {
            id: tileColumn
            width: parent.width
            spacing: Theme.spacingXS

            DRingGauge {
                width: Theme.buttonHeightXS
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                value: tile.ratio
                strokeWidth: Theme.outlineWidthFocused + Theme.dividerWidth
                trackGap: Theme.spacingXXS
                ringColor: tile.valueColor === Theme.error ? Theme.error : Theme.primary
                animated: root.active

                DIcon {
                    anchors.centerIn: parent
                    name: tile.iconName
                    size: tile.ratio >= 0 ? Theme.iconSizeSmall : Theme.iconSize
                    color: tile.valueColor === Theme.error ? Theme.error : Theme.primary
                }
            }

            StyledText {
                width: parent.width
                text: tile.value
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: tile.valueColor
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: tile.label
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    component DetailValue: Column {
        id: detail
        property string label: ""
        property string value: ""
        property color valueColor: Theme.onSurface
        spacing: Theme.spacingXXS

        StyledText {
            width: parent.width
            text: detail.value
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: detail.valueColor
            wrapMode: Text.Wrap
        }

        StyledText {
            width: parent.width
            text: detail.label
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.onSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }
}
