import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.DBar.Popouts

Item {
    id: root

    readonly property color batteryStatusColor: {
        if (BatteryService.isLowBattery && !BatteryService.isCharging)
            return Theme.error;
        if (BatteryService.isCharging || BatteryService.isPluggedIn)
            return Theme.primary;
        return Theme.surfaceText;
    }

    // The sysfs names DMS can write, in the order they are tried. Hardware that
    // exposes none of them, a Lenovo IdeaPad on ideapad_laptop for instance,
    // used to run the apply script to completion without writing anything, and
    // sh exiting 0 was indistinguishable from a successful write.
    readonly property string thresholdFileList: "charge_control_limit_max charge_stop_threshold charge_control_end_threshold"
    readonly property int noThresholdExitCode: 2

    property bool chargeLimitSupported: Qt.platform.os === "linux"

    Component.onCompleted: BatteryService.addRef()
    Component.onDestruction: BatteryService.removeRef()

    Process {
        id: thresholdProbe
        running: Qt.platform.os === "linux"
        command: ["sh", "-c", "for bat in /sys/class/power_supply/BAT*; do for file in " + root.thresholdFileList + "; do [ -f \"$bat/$file\" ] && exit 0; done; done; exit 1"]
        onExited: exitCode => root.chargeLimitSupported = exitCode === 0
    }

    Process {
        id: applyLimitProcess
        command: ["pkexec", "sh", "-c", "
found=0
for bat in /sys/class/power_supply/BAT*; do
  for file in " + root.thresholdFileList + "; do
    if [ -f \"$bat/$file\" ]; then
      found=1
      echo " + SettingsData.batteryChargeLimit + " > \"$bat/$file\" || exit 1
      break
    fi
  done
done
[ \"$found\" = 1 ] || exit " + root.noThresholdExitCode + "
"]
        running: false
        onExited: exitCode => {
            if (exitCode === root.noThresholdExitCode) {
                root.chargeLimitSupported = false;
                ToastService.showError(I18n.tr("Charge limit not supported on this hardware", "battery settings: toast title when sysfs has no charge threshold"), I18n.tr("No writable charge threshold file was found under /sys/class/power_supply.", "battery settings: why the charge limit could not be applied"));
            } else if (exitCode !== 0) {
                ToastService.showError(I18n.tr("Failed to apply charge limit to system"), I18n.tr("Process exited with code %1", "charge limit error toast detail, %1 is the exit code").arg(exitCode));
            } else {
                ToastService.showInfo(I18n.tr("Charge limit applied successfully"), I18n.tr("Limit set to %1%", "charge limit toast detail, %1 is a percentage number").arg(SettingsData.batteryChargeLimit));
            }
        }
    }

    BatteryHistory {
        id: history
        readonly property var device: BatteryService.usePreferred ? BatteryService.preferredDevice : BatteryService.device
        active: root.visible && BatteryService.batteryAvailable
        nativePath: device?.nativePath ?? ""
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            width: parent.width
            title: I18n.tr("Status")
            settingKey: "batteryStatusCard"
            tags: ["battery", "status", "charge", "health"]

            SettingsRow {
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        DIcon {
                            name: BatteryService.getBatteryIcon()
                            size: Theme.iconSizeLarge
                            color: root.batteryStatusColor
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            spacing: Theme.spacingXS
                            width: parent.width - Theme.iconSizeLarge - Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter

                            Row {
                                spacing: Theme.spacingS
                                width: parent.width

                                StyledText {
                                    text: BatteryService.batteryAvailable ? `${BatteryService.displayBatteryLevelText}%` : ""
                                    font.pixelSize: Theme.fontSizeXLarge
                                    font.weight: Theme.fontWeightMedium
                                    color: root.batteryStatusColor
                                }

                                StyledText {
                                    text: BatteryService.batteryStatus
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    width: Math.max(0, parent.width - 100)
                                }
                            }

                            StyledText {
                                text: BatteryService.isPluggedIn ? I18n.tr("AC adapter (plugged in)") : I18n.tr("Battery power")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                                width: parent.width
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: Theme.spacingXS

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.fullRadius(width, height)
                            color: Theme.withAlpha(root.batteryStatusColor, Theme.tonalTintAlpha)
                        }

                        Rectangle {
                            anchors.left: parent.left
                            width: parent.width * Math.max(0, Math.min(1, BatteryService.displayBatteryLevel / 100))
                            height: parent.height
                            radius: Theme.fullRadius(width, height)
                            color: root.batteryStatusColor
                            visible: BatteryService.batteryAvailable
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        Item {
                            width: (parent.width - Theme.spacingM) / 2
                            height: timeColumn.implicitHeight

                            Column {
                                id: timeColumn
                                width: parent.width
                                spacing: Theme.spacingXXS

                                StyledText {
                                    text: I18n.tr("Estimated time")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceTextMedium
                                }

                                StyledText {
                                    text: {
                                        const remaining = BatteryService.formatTimeRemaining();
                                        const estimated = BatteryService.formatEstimatedTime();
                                        return estimated ? `${remaining} (${estimated})` : remaining;
                                    }
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                    width: parent.width
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Item {
                            width: (parent.width - Theme.spacingM) / 2
                            height: healthColumn.implicitHeight

                            Column {
                                id: healthColumn
                                width: parent.width
                                spacing: Theme.spacingXXS

                                StyledText {
                                    text: I18n.tr("Health", "noun, battery health percentage label")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceTextMedium
                                }

                                StyledText {
                                    text: BatteryService.batteryHealth
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                    width: parent.width
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "show_chart"
            title: I18n.tr("History")
            settingKey: "batteryHistory"
            tags: ["battery", "history", "graph", "charge"]
            visible: BatteryService.batteryAvailable && history.samples.filter(sample => sample[2] !== 0).length > 1

            BatteryHistoryChart {
                height: implicitHeight
                color: "transparent"
                pad: 0
                samples: history.samples
                rangeStart: history.rangeStart
                rangeEnd: history.rangeEnd
                deviceName: !BatteryService.usePreferred && BatteryService.batteries.length > 1 ? history.device?.model || history.device?.nativePath || "" : ""
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "tune"
            title: I18n.tr("Protection", "battery settings card title for charge limit")
            settingKey: "batteryProtection"
            tags: ["battery", "protection", "charge", "limit"]

            SettingsSliderRow {
                settingKey: "batteryChargeLimit"
                text: I18n.tr("Charge limit")
                value: SettingsData.batteryChargeLimit
                minimum: 50
                maximum: 100
                onSliderValueChanged: newValue => SettingsData.set("batteryChargeLimit", newValue)
            }

            SettingsToggleRow {
                settingKey: "batteryScaleToChargeLimit"
                text: I18n.tr("Scale battery level to charge limit", "battery settings: toggle to scale the displayed percentage so the charge limit represents 100%")
                description: I18n.tr("Scale the displayed battery level to the configured charge limit", "battery settings: explains that the displayed battery percentage is scaled relative to the charge limit")
                checked: SettingsData.batteryScaleToChargeLimit
                onToggled: checked => SettingsData.set("batteryScaleToChargeLimit", checked)
            }

            SettingsToggleRow {
                settingKey: "batteryScaleAlertThresholds"
                text: I18n.tr("Scale low and critical alert thresholds", "battery settings: toggle to apply low and critical alert thresholds to the charge-limit-scaled battery percentage")
                description: I18n.tr("Use the scaled battery level for alert thresholds and percentages", "battery settings: explains that low and critical alerts trigger and report percentages on the scaled battery level")
                checked: SettingsData.batteryScaleAlertThresholds
                visible: SettingsData.batteryScaleToChargeLimit
                onToggled: checked => SettingsData.set("batteryScaleAlertThresholds", checked)
            }

            SettingsRow {
                visible: Qt.platform.os === "linux" && BatteryService.batteryAvailable && !root.chargeLimitSupported
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("No writable charge threshold file was found under /sys/class/power_supply.", "battery settings: why the charge limit could not be applied")
                    wrapMode: Text.WordWrap
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                }
            }

            SettingsRow {
                visible: Qt.platform.os === "linux" && BatteryService.batteryAvailable && root.chargeLimitSupported
                body: Row {
                    // charge_control_* live in Linux sysfs; no BSD equivalent
                    width: parent.width
                    height: applyButton.height
                    layoutDirection: I18n.isRtl ? Qt.LeftToRight : Qt.RightToLeft

                    Item {
                        width: Theme.spacingM
                        height: 1
                    }

                    DButton {
                        id: applyButton
                        text: I18n.tr("Apply to hardware")
                        iconName: "lock"
                        backgroundColor: Theme.primary
                        textColor: Theme.onPrimary
                        onClicked: {
                            applyLimitProcess.running = true;
                        }
                    }
                }
            }

            SettingsToggleRow {
                settingKey: "batteryNotifyChargeLimit"
                text: I18n.tr("Notify when limit is reached")
                checked: SettingsData.batteryNotifyChargeLimit
                onToggled: checked => SettingsData.set("batteryNotifyChargeLimit", checked)
            }

            SettingsButtonGroupRow {
                settingKey: "batteryChargeLimitNotificationType"
                text: I18n.tr("Alert style")
                model: [I18n.tr("Toast", "noun, battery alert style option, small popup message"), I18n.tr("Notification")]
                visible: SettingsData.batteryNotifyChargeLimit
                currentIndex: SettingsData.batteryChargeLimitNotificationType
                onSelectionChanged: (index, selected) => {
                    if (selected) {
                        SettingsData.set("batteryChargeLimitNotificationType", index);
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "notifications"
            title: I18n.tr("Alerts", "noun, battery settings card title for low battery alerts")
            settingKey: "batteryAlerts"
            tags: ["battery", "alerts", "low", "warning"]

            SettingsSliderRow {
                settingKey: "batteryLowThreshold"
                text: I18n.tr("Low threshold")
                value: SettingsData.batteryLowThreshold
                minimum: 5
                maximum: 40
                onSliderValueChanged: newValue => SettingsData.set("batteryLowThreshold", newValue)
            }

            SettingsToggleRow {
                settingKey: "batteryNotifyLow"
                text: I18n.tr("Low notification")
                checked: SettingsData.batteryNotifyLow
                onToggled: checked => SettingsData.set("batteryNotifyLow", checked)
            }

            SettingsButtonGroupRow {
                settingKey: "batteryLowNotificationType"
                text: I18n.tr("Alert style")
                model: [I18n.tr("Toast"), I18n.tr("Notification")]
                enabled: SettingsData.batteryNotifyLow
                currentIndex: SettingsData.batteryLowNotificationType
                onSelectionChanged: (index, selected) => {
                    if (selected) {
                        SettingsData.set("batteryLowNotificationType", index);
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "battery_alert"
            title: I18n.tr("Critical", "adjective, card title for critical battery level alerts")
            settingKey: "batteryCriticalAlerts"
            tags: ["battery", "critical", "alerts"]

            SettingsSliderRow {
                settingKey: "batteryCriticalThreshold"
                text: I18n.tr("Critical threshold")
                value: SettingsData.batteryCriticalThreshold
                minimum: 1
                maximum: 30
                onSliderValueChanged: newValue => SettingsData.set("batteryCriticalThreshold", newValue)
            }

            SettingsToggleRow {
                settingKey: "batteryCriticalAnimation"
                tags: ["battery", "critical", "indicator", "animation", "pulse", "blink"]
                text: I18n.tr("Pulse animation", "critical battery indicator animation toggle")
                checked: SettingsData.batteryCriticalAnimation
                onToggled: checked => SettingsData.set("batteryCriticalAnimation", checked)
            }

            SettingsToggleRow {
                settingKey: "batteryNotifyCritical"
                text: I18n.tr("Critical notification")
                checked: SettingsData.batteryNotifyCritical
                onToggled: checked => SettingsData.set("batteryNotifyCritical", checked)
            }

            SettingsButtonGroupRow {
                settingKey: "batteryCriticalNotificationType"
                text: I18n.tr("Alert style")
                model: [I18n.tr("Toast"), I18n.tr("Notification")]
                enabled: SettingsData.batteryNotifyCritical
                currentIndex: SettingsData.batteryCriticalNotificationType
                onSelectionChanged: (index, selected) => {
                    if (selected) {
                        SettingsData.set("batteryCriticalNotificationType", index);
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "power"
            title: I18n.tr("Power profiles")
            settingKey: "powerProfilesSaving"

            SettingsToggleRow {
                settingKey: "batteryAutoPowerSaver"
                text: I18n.tr("Auto power saver")
                description: I18n.tr("Switches to power saver at the low battery threshold", "battery auto power saver toggle description")
                checked: SettingsData.batteryAutoPowerSaver
                onToggled: checked => SettingsData.set("batteryAutoPowerSaver", checked)
            }

            SettingsToggleRow {
                settingKey: "lowerDisplayRefreshRateOnBattery"
                tags: ["power", "battery", "display", "refresh", "rate", "60hz", "hz", "vrr"]
                text: I18n.tr("Lower display refresh rate on battery")
                visible: BatteryService.batteryAvailable
                checked: SettingsData.lowerDisplayRefreshRateOnBattery
                onToggled: checked => SettingsData.set("lowerDisplayRefreshRateOnBattery", checked)
            }

            SettingsDropdownRow {
                settingKey: "acProfileName"
                text: I18n.tr("Profile on AC")
                options: [I18n.tr("Don't change"), Theme.getPowerProfileLabel(0), Theme.getPowerProfileLabel(1), Theme.getPowerProfileLabel(2)]
                currentValue: {
                    const val = SettingsData.acProfileName;
                    const idx = ["", "0", "1", "2"].indexOf(val);
                    return idx >= 0 ? options[idx] : options[0];
                }
                onValueChanged: value => {
                    const idx = options.indexOf(value);
                    if (idx >= 0) {
                        SettingsData.set("acProfileName", ["", "0", "1", "2"][idx]);
                    }
                }
            }

            SettingsDropdownRow {
                settingKey: "batteryProfileName"
                text: I18n.tr("Profile on battery")
                options: [I18n.tr("Don't change"), Theme.getPowerProfileLabel(0), Theme.getPowerProfileLabel(1), Theme.getPowerProfileLabel(2)]
                currentValue: {
                    const val = SettingsData.batteryProfileName;
                    const idx = ["", "0", "1", "2"].indexOf(val);
                    return idx >= 0 ? options[idx] : options[0];
                }
                onValueChanged: value => {
                    const idx = options.indexOf(value);
                    if (idx >= 0) {
                        SettingsData.set("batteryProfileName", ["", "0", "1", "2"][idx]);
                    }
                }
            }
        }
    }
}
