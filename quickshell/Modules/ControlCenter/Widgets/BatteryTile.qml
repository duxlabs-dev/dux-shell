import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Services
import qs.Widgets

CcTile {
    id: root

    property bool live: Window.window?.visible ?? false
    property bool batteryRefHeld: false
    readonly property bool available: BatteryService.batteryAvailable
    readonly property bool profileMode: !available && PowerProfileWatcher.available
    readonly property string meterStyle: widgetData?.batteryStyle ?? "icon"
    readonly property bool levelColors: (widgetData?.batteryColorMode ?? "level") === "level"
    readonly property bool showsMeter: available && meterStyle !== "icon"
    property real meterWidth: 0

    iconName: profileMode ? Theme.getPowerProfileIcon(PowerProfileWatcher.currentProfile) : BatteryService.getBatteryIcon()
    title: {
        if (profileMode)
            return I18n.tr("Power profile");
        return available ? I18n.tr("Battery") : I18n.tr("No battery");
    }
    subtitle: {
        if (profileMode)
            return Theme.getPowerProfileLabel(PowerProfileWatcher.currentProfile);
        if (!available)
            return I18n.tr("Not available");
        if (BatteryService.isCharging)
            return `${BatteryService.displayBatteryLevelText}% • ` + I18n.tr("Charging");
        if (BatteryService.isPluggedIn)
            return `${BatteryService.displayBatteryLevelText}% • ` + I18n.tr("Plugged in");
        return `${BatteryService.displayBatteryLevelText}%`;
    }
    denseTitle: available && !showsMeter ? I18n.tr("Battery") + ` • ${BatteryService.displayBatteryLevelText}%` : ""

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

    onLiveChanged: syncBatteryRef(live)
    Component.onCompleted: syncBatteryRef(live)
    Component.onDestruction: syncBatteryRef(false)
    active: available && (BatteryService.isCharging || BatteryService.isPluggedIn) && !showsMeter
    bodyContent: showsMeter && compact ? meterPill : null
    iconContent: showsMeter && !compact ? meterIcon : null
    quickContentWidth: showsMeter ? meterWidth : 0
    opensPage: !profileMode
    showExpand: profileMode

    Component {
        id: meterIcon

        BatteryMeter {
            meterStyle: root.meterStyle
            levelColors: root.levelColors
            thickness: CcMetrics.pillMeterThickness
            scale: Math.min(1, Math.max(0, root.iconExtent - Theme.spacingXS * 2) / Math.max(1, implicitWidth, implicitHeight))
        }
    }

    Component {
        id: meterPill

        Item {
            BatteryMeter {
                id: meter

                anchors.centerIn: parent
                meterStyle: root.meterStyle
                levelColors: root.levelColors
                thickness: CcMetrics.pillMeterThickness
                scale: Math.min(1, (parent.width - Theme.spacingXS * 2) / Math.max(1, implicitWidth))
            }

            Binding {
                target: root
                property: "meterWidth"
                value: meter.implicitWidth
            }
        }
    }

    tallContent: Component {
        Item {
            BatteryMeter {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                thickness: CcMetrics.tallMeterThickness
                meterStyle: root.showsMeter ? root.meterStyle : "solid"
                levelColors: root.levelColors
                showNumber: false
                visible: root.available
            }
        }
    }

    onClicked: {
        if (!profileMode) {
            expandClicked();
            return;
        }
        PowerProfileWatcher.cycleProfile();
    }
    expandedContent: Component {
        CcTileActions {
            actions: PowerProfileWatcher.availableProfiles.map(profile => ({
                        text: Theme.getPowerProfileLabel(profile),
                        icon: Theme.getPowerProfileIcon(profile),
                        active: profile === PowerProfileWatcher.currentProfile,
                        enabled: PowerProfileWatcher.available,
                        trigger: () => {
                            if (!PowerProfileWatcher.applyProfile(profile))
                                ToastService.showError(I18n.tr("Failed to set power profile"));
                        }
                    }))
        }
    }
}
