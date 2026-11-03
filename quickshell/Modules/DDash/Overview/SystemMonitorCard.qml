import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash

Card {
    id: root

    property bool live: Window.window?.visible ?? false
    property bool dgopRefHeld: false

    readonly property bool horizontal: width > height
    readonly property bool showTemperature: options.temperature !== false
    readonly property var meters: showTemperature ? ["cpu", "temp", "memory"] : ["cpu", "memory"]

    function meterIcon(key) {
        switch (key) {
        case "temp":
            return "device_thermostat";
        case "memory":
            return "developer_board";
        }
        return "memory";
    }

    function meterLabel(key) {
        switch (key) {
        case "temp":
            return I18n.tr("CPU temperature");
        case "memory":
            return I18n.tr("Memory usage");
        }
        return I18n.tr("CPU usage");
    }

    function meterValue(key) {
        switch (key) {
        case "temp":
            return DgopService.cpuTemperature || 0;
        case "memory":
            return DgopService.memoryUsage || 0;
        }
        return DgopService.cpuUsage || 0;
    }

    function meterText(key) {
        const value = Math.round(meterValue(key));
        return key === "temp" ? value + "°" : value + "%";
    }

    function levelColor(key) {
        const value = meterValue(key);
        let warn = DashMetrics.cpuWarnPercent;
        let critical = DashMetrics.cpuCriticalPercent;
        switch (key) {
        case "temp":
            warn = DashMetrics.tempWarnDegrees;
            critical = DashMetrics.tempCriticalDegrees;
            break;
        case "memory":
            warn = DashMetrics.memoryWarnPercent;
            critical = DashMetrics.memoryCriticalPercent;
            break;
        }
        if (value > critical)
            return Theme.error;
        if (value > warn)
            return Theme.warning;
        return root.accentColor;
    }

    entryId: "sysmon"
    tone: options.tone ?? ""

    function syncDgopRef(wanted) {
        if (wanted === dgopRefHeld)
            return;
        dgopRefHeld = wanted;
        if (wanted) {
            DgopService.addRef(["cpu", "memory", "system"]);
            return;
        }
        DgopService.removeRef(["cpu", "memory", "system"]);
    }

    onLiveChanged: syncDgopRef(live)
    Component.onCompleted: syncDgopRef(live)
    Component.onDestruction: syncDgopRef(false)

    DTooltipHost {
        id: meterTooltip
        text: target ? root.meterLabel(target.meter) : ""
        side: root.horizontal ? "bottom" : "top"
    }

    component MeterIcon: DIcon {
        id: icon

        property string meter: ""

        name: root.meterIcon(meter)
        size: Theme.iconSizeSmall

        MouseArea {
            anchors.fill: parent
            anchors.margins: -Theme.spacingXS
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                meterTooltip.target = icon;
                meterTooltip.schedule();
            }
            onExited: meterTooltip.dismiss()
        }
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spacingXS
        visible: root.horizontal

        Repeater {
            model: root.meters

            Item {
                id: meterRow

                required property var modelData

                readonly property color levelColor: root.levelColor(modelData)
                readonly property real value: root.meterValue(modelData)

                width: parent.width
                height: (parent.height - parent.spacing * (root.meters.length - 1)) / root.meters.length
                Accessible.role: Accessible.StaticText
                Accessible.name: root.meterLabel(modelData) + " " + root.meterText(modelData)

                MeterIcon {
                    id: meterIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    meter: meterRow.modelData
                    color: meterRow.levelColor
                }

                Rectangle {
                    anchors.left: meterIcon.right
                    anchors.right: meterValue.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    height: DashMetrics.meterBarThickness
                    radius: Theme.fullRadius(width, height)
                    color: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)

                    Rectangle {
                        anchors.left: parent.left
                        width: parent.width * Math.min(Math.max(meterRow.value / 100, 0), 1)
                        height: parent.height
                        radius: parent.radius
                        color: meterRow.levelColor

                        Behavior on width {
                            enabled: DashMetrics.animationsEnabled
                            NumberAnimation {
                                duration: DashMetrics.meterDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.standard
                            }
                        }
                    }
                }

                NumericText {
                    id: meterValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.meterText(meterRow.modelData)
                    reserveText: "100%"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: root.contentColor
                }
            }
        }
    }

    Row {
        anchors.fill: parent
        spacing: Theme.spacingM
        visible: !root.horizontal

        Repeater {
            model: root.meters

            Column {
                id: meterColumn

                required property var modelData

                readonly property color levelColor: root.levelColor(modelData)
                readonly property real value: root.meterValue(modelData)

                width: (parent.width - parent.spacing * (root.meters.length - 1)) / root.meters.length
                height: parent.height
                spacing: Theme.spacingS
                Accessible.role: Accessible.StaticText
                Accessible.name: root.meterLabel(modelData) + " " + root.meterText(modelData)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: DashMetrics.meterBarThickness
                    height: parent.height - Theme.iconSizeSmall - parent.spacing
                    radius: Theme.fullRadius(width, height)
                    color: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.height * Math.min(Math.max(meterColumn.value / 100, 0), 1)
                        radius: parent.radius
                        color: meterColumn.levelColor

                        Behavior on height {
                            enabled: DashMetrics.animationsEnabled
                            NumberAnimation {
                                duration: DashMetrics.meterDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.standard
                            }
                        }
                    }
                }

                MeterIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    meter: meterColumn.modelData
                    color: meterColumn.levelColor
                }
            }
        }
    }
}
