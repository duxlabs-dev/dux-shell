import QtQuick
import Quickshell
import qs.Common
import qs.Modules.DBar
import qs.Modules.Plugins
import qs.Modules.SurfaceWidgets
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../../../Common/BatteryDevices.js" as BatteryDevices

BasePill {
    id: battery
    readonly property var log: Log.scoped("Battery")

    Component.onCompleted: BatteryService.addRef()
    Component.onDestruction: BatteryService.removeRef()

    property bool batteryPopupVisible: false
    property var popoutTarget: null
    property var widgetData: null
    readonly property bool showPercentOnlyOnBattery: SettingsData.widgetOption("battery", widgetData, "showBatteryPercentOnlyOnBattery")
    readonly property bool showPercent: {
        const base = SettingsData.widgetOption("battery", widgetData, "showBatteryPercent");
        return base && !(showPercentOnlyOnBattery && BatteryService.isPluggedIn);
    }
    readonly property bool showTime: SettingsData.widgetOption("battery", widgetData, "showBatteryTime")
    readonly property bool showTimeOnlyOnBattery: SettingsData.widgetOption("battery", widgetData, "showBatteryTimeOnlyOnBattery")
    readonly property string batteryStyle: SettingsData.widgetOption("battery", widgetData, "batteryStyle")
    readonly property bool pillStyle: battery.batteryStyle !== "icon"
    readonly property string colorMode: barConfig?.batteryColorMode ?? SettingsData.barConfigDefault("batteryColorMode")
    readonly property string batteryDirection: SettingsData.widgetOption("battery", widgetData, "batteryDirection")
    readonly property string batterySeparator: SettingsData.widgetOption("battery", widgetData, "batterySeparator")
    readonly property var batteryDevices: SettingsData.widgetOption("battery", widgetData, "batteryDevices")
    readonly property var entries: BatteryService.barDeviceEntries(batteryDevices)
    readonly property var renderEntries: entries.filter(item => item.kind === "system" || item.entry.icon || item.entry.percent)
    readonly property bool shouldHide: renderEntries.length === 0
    readonly property bool percentInMeter: batteryStyle === "solid" && batteryDirection === "horizontal" && !isVerticalOrientation
    // A solid meter whose long side runs across the bar is shrunk to fit the same room as the circle.
    readonly property bool meterAcross: batteryStyle === "solid" && (batteryDirection === "vertical") !== isVerticalOrientation
    readonly property bool percentVisible: showPercent && BatteryService.hasBatteryReading
    readonly property bool showPowerCharging: SettingsData.widgetOption("battery", widgetData, "showBatteryPowerCharging")
    readonly property bool showPowerDischarging: SettingsData.widgetOption("battery", widgetData, "showBatteryPowerDischarging")
    readonly property bool showPower: BatteryService.isCharging ? showPowerCharging : showPowerDischarging
    readonly property bool critical: SettingsData.batteryCriticalAnimation && BatteryService.isCriticalBattery && !BatteryService.isCharging
    property real criticalPulse: 0
    readonly property color criticalForeground: noBackground ? battery.mixColor(Theme.error, defaultContentColor, criticalPulse) : battery.mixColor(Theme.error, Theme.surface, criticalPulse)

    fillColor: critical && !noBackground ? battery.mixColor(defaultFillColor, Theme.error, criticalPulse) : defaultFillColor
    contentColor: critical ? (noBackground ? criticalForeground : battery.mixColor(defaultContentColor, Theme.surface, criticalPulse)) : defaultContentColor

    function mixColor(from, to, progress) {
        return Qt.rgba(from.r + (to.r - from.r) * progress, from.g + (to.g - from.g) * progress, from.b + (to.b - from.b) * progress, from.a + (to.a - from.a) * progress);
    }

    property int criticalTick: 0

    // Stepped on purpose: an Animation repaints the bar at the full refresh rate.
    Timer {
        interval: Timing.slowTick
        repeat: true
        running: battery.critical && battery.surfaceLive && !Theme.reduceMotion
        onRunningChanged: {
            battery.criticalTick = 0;
            battery.criticalPulse = 0;
        }
        onTriggered: {
            battery.criticalTick = (battery.criticalTick + 1) % 40;
            battery.criticalPulse = 1 - Math.abs(20 - battery.criticalTick) / 20;
        }
    }

    // Signed charge/discharge rate, e.g. "+45W" while charging, "-8.4W" while
    // draining. Empty (and therefore hidden) whenever the battery is idle.
    readonly property string batteryPowerText: showPower ? BatteryService.formatPowerRate(false) : ""
    readonly property string verticalBatteryPowerText: showPower ? BatteryService.formatPowerRate(true) : ""

    readonly property string batteryTimeText: {
        if (showTimeOnlyOnBattery && BatteryService.isPluggedIn) {
            return "";
        }
        const time = BatteryService.formatTimeRemaining();
        return time !== "Unknown" ? time : "";
    }

    readonly property string verticalBatteryTimeText: {
        if (!batteryTimeText)
            return "";

        // Parse batteryTimeText, e.g., "2h 41m" or "41m"
        let hours = 0;
        let minutes = 0;

        const hourMatch = batteryTimeText.match(/(\d+)h/);
        const minMatch = batteryTimeText.match(/(\d+)m/);

        if (hourMatch) {
            hours = parseInt(hourMatch[1], 10);
        }
        if (minMatch) {
            minutes = parseInt(minMatch[1], 10);
        }

        const hoursStr = hours < 10 ? "0" + hours : hours.toString();
        const minutesStr = minutes < 10 ? "0" + minutes : minutes.toString();

        return `${hoursStr}\n${minutesStr}`;
    }

    readonly property string horizontalDisplayText: {
        const parts = [];
        if (percentVisible) {
            parts.push(`${BatteryService.displayBatteryLevelText}%`);
        }
        if (showTime && batteryTimeText) {
            parts.push(percentVisible ? `(${batteryTimeText})` : batteryTimeText);
        }
        if (batteryPowerText) {
            parts.push(batteryPowerText);
        }
        return parts.join(" ");
    }

    // The number sits inside the solid meter when it is horizontal; otherwise it shows beside the glyph with time and wattage.
    readonly property string horizontalSideText: {
        if (!pillStyle) {
            return horizontalDisplayText;
        }
        const parts = [];
        if (percentVisible && !percentInMeter) {
            parts.push(`${BatteryService.displayBatteryLevelText}%`);
        }
        if (showTime && batteryTimeText) {
            parts.push(batteryTimeText);
        }
        if (batteryPowerText) {
            parts.push(batteryPowerText);
        }
        return parts.join(" ");
    }

    readonly property string verticalDisplayText: {
        const lines = [];
        if (percentVisible && !(pillStyle && percentInMeter)) {
            lines.push(BatteryService.displayBatteryLevelText);
        }
        if (showTime && batteryTimeText) {
            lines.push(verticalBatteryTimeText);
        }
        if (verticalBatteryPowerText) {
            lines.push(verticalBatteryPowerText);
        }
        return lines.join("\n");
    }

    readonly property real iconSize: Theme.barIconSize(barThickness, isVerticalOrientation ? undefined : -4, barConfig?.maximizeWidgetIcons, barConfig?.iconScale)
    readonly property real textSize: Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)
    readonly property bool splitActive: batterySeparator === "separate" && !noBackground && renderEntries.length > 1
    readonly property real entrySpacing: splitActive ? 2 * horizontalPadding + splitGap : BarMetrics.pillEntryGap

    // Colors follow the real level, not the charge-limit scaled one.
    function entryColor(item, neutral) {
        const percentage = item.kind === "system" ? BatteryService.batteryLevel : item.percentage;
        return BatteryService.colorFor(colorMode, percentage, item.charging, neutral);
    }

    property real touchpadAccumulator: 0

    readonly property int barPosition: {
        switch (axis?.edge) {
        case "top":
            return 0;
        case "bottom":
            return 1;
        case "left":
            return 2;
        case "right":
            return 3;
        default:
            return 0;
        }
    }

    signal toggleBatteryPopup

    width: shouldHide ? 0 : (isVerticalOrientation ? barThickness : visualWidth)
    height: shouldHide ? 0 : (isVerticalOrientation ? visualHeight : barThickness)
    visible: !shouldHide

    splitJoined: BarMetrics.widgetStyle(barConfig) === "segments"
    splitGap: splitJoined ? BarMetrics.segmentGap : BarMetrics.pillGap
    splitBlurPerSegment: true

    content: Component {
        Item {
            id: contentRoot

            // itemAt() is not observable, so the boundary binding below re-runs when delegates come or go.
            property int itemsRevision: 0

            implicitWidth: battery.isVerticalOrientation ? (battery.widgetThickness - battery.horizontalPadding * 2) : layout.implicitWidth
            implicitHeight: battery.isVerticalOrientation ? layout.implicitHeight : (battery.widgetThickness - battery.horizontalPadding * 2)

            Binding {
                target: battery
                property: "splitOffsets"
                value: {
                    contentRoot.itemsRevision;
                    if (!battery.splitActive)
                        return [];
                    const items = [];
                    for (let i = 0; i < entryRepeater.count; i++)
                        items.push(entryRepeater.itemAt(i));
                    return battery.gapCenters(items, layout);
                }
            }

            Grid {
                id: layout
                anchors.centerIn: parent
                columns: battery.isVerticalOrientation ? 1 : Math.max(1, entryRepeater.count)
                spacing: battery.entrySpacing
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter

                Repeater {
                    id: entryRepeater
                    model: ScriptModel {
                        objectProp: "id"
                        values: battery.renderEntries
                    }
                    onItemAdded: contentRoot.itemsRevision++
                    onItemRemoved: contentRoot.itemsRevision++

                    delegate: Grid {
                        id: slot

                        required property var modelData
                        required property int index
                        readonly property bool isSystem: modelData.kind === "system"
                        readonly property bool systemMeter: isSystem && battery.pillStyle && BatteryService.batteryAvailable
                        readonly property bool showSeparator: index > 0 && (battery.batterySeparator === "line" || battery.batterySeparator === "dot")
                        readonly property string systemIconName: {
                            if (!BatteryService.batteryAvailable)
                                return "power";
                            if (modelData.low && !modelData.charging)
                                return "battery_alert";
                            return BatteryService.getBatteryIcon();
                        }
                        readonly property string deviceText: {
                            if (isSystem || !modelData.entry.percent)
                                return "";
                            if (modelData.unknown)
                                return "–";
                            return battery.isVerticalOrientation ? String(modelData.percentage) : `${modelData.percentage}%`;
                        }
                        readonly property color textColor: isSystem && battery.critical ? battery.contentColor : (battery.colorMode === "lowcharging" && modelData.low ? Theme.error : battery.contentColor)
                        readonly property string shownText: {
                            if (!isSystem)
                                return deviceText;
                            if (!BatteryService.batteryAvailable)
                                return "";
                            return battery.isVerticalOrientation ? battery.verticalDisplayText : battery.horizontalSideText;
                        }

                        readonly property int partColumns: Math.max(1, (isSystem || modelData.entry.icon ? 1 : 0) + (shownText !== "" ? 1 : 0))

                        // A Grid counts spacing for every column, so columns follow what is actually shown.
                        columns: battery.isVerticalOrientation ? 1 : (showSeparator ? 2 : 1)
                        spacing: BarMetrics.pillEntryGap
                        horizontalItemAlignment: Grid.AlignHCenter
                        verticalItemAlignment: Grid.AlignVCenter

                        PillEntrySeparator {
                            visible: slot.showSeparator
                            dot: battery.batterySeparator !== "line"
                            vertical: battery.isVerticalOrientation
                        }

                        Grid {
                            columns: battery.isVerticalOrientation ? 1 : slot.partColumns
                            spacing: battery.isVerticalOrientation ? 1 : (battery.noBackground ? 1 : 2)
                            horizontalItemAlignment: Grid.AlignHCenter
                            verticalItemAlignment: Grid.AlignVCenter

                            Loader {
                                active: slot.isSystem && !slot.systemMeter
                                visible: active
                                sourceComponent: DIcon {
                                    name: slot.systemIconName
                                    rotation: BatteryService.batteryAvailable && battery.batteryDirection === "horizontal" ? 90 : 0
                                    size: battery.iconSize
                                    color: battery.critical ? battery.criticalForeground : battery.entryColor(slot.modelData, Theme.widgetIconColor)
                                }
                            }

                            Loader {
                                active: slot.systemMeter
                                visible: active
                                sourceComponent: BatteryMeter {
                                    meterStyle: battery.batteryStyle === "circle" ? "arc" : "solid"
                                    vertical: battery.batteryDirection === "vertical"
                                    singleTextColor: true
                                    showNumber: battery.percentVisible && battery.percentInMeter
                                    colorMode: battery.colorMode
                                    neutralColor: Theme.widgetIconColor
                                    colorOverride: battery.critical ? battery.criticalForeground : "transparent"
                                    maxDiameter: battery.widgetThickness - Theme.spacingXS
                                    maxLength: battery.meterAcross ? battery.widgetThickness - Theme.spacingXS : 0
                                    thickness: battery.iconSize
                                    fontSize: battery.textSize
                                }
                            }

                            Loader {
                                active: !slot.isSystem && slot.modelData.entry.icon
                                visible: active
                                sourceComponent: BatteryDeviceIcon {
                                    iconName: slot.modelData.iconName
                                    size: battery.iconSize
                                    color: battery.entryColor(slot.modelData, Theme.widgetIconColor)
                                    badgeName: BatteryDevices.badgeFor(slot.modelData)
                                    cutWidth: battery.noBackground ? 0 : Theme.outlineWidth
                                    cutColor: battery.fillColor
                                }
                            }

                            Loader {
                                active: slot.shownText !== ""
                                visible: active
                                sourceComponent: NumericText {
                                    width: battery.isVerticalOrientation ? implicitWidth : reservedWidth
                                    text: slot.shownText
                                    font.pixelSize: battery.textSize
                                    color: slot.textColor
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        x: -battery.leftMargin
        y: -battery.topMargin
        width: battery.width + battery.leftMargin + battery.rightMargin
        height: battery.height + battery.topMargin + battery.bottomMargin
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            battery.triggerRipple(this, mouse.x, mouse.y);
            if (mouse.button === Qt.LeftButton) {
                toggleBatteryPopup();
            } else if (mouse.button === Qt.RightButton) {
                if (PowerProfileWatcher.available) {
                    PowerProfileWatcher.cycleProfile();
                } else {
                    ToastService.showError(I18n.tr("power-profiles-daemon not available"));
                }
            }
        }
        onWheel: wheel => {
            var delta = wheel.angleDelta.y;
            if (delta === 0)
                return;

            // Check if this is a touchpad
            if (delta !== 120 && delta !== -120) {
                touchpadAccumulator += delta;
                if (Math.abs(touchpadAccumulator) < 500)
                    return;
                delta = touchpadAccumulator;
                touchpadAccumulator = 0;
            }

            if (!BrightnessService.brightnessAvailable) {
                return;
            }

            const step = 5;
            const change = delta > 0 ? step : -step;
            const newBrightness = Math.max(0, Math.min(100, BrightnessService.brightnessLevel + change));
            BrightnessService.setBrightness(newBrightness, "", false);
        }
    }
}
