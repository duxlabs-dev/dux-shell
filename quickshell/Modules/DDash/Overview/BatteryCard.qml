import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DDash

Card {
    id: root

    property bool live: Window.window?.visible ?? false
    property bool batteryRefHeld: false

    readonly property bool wide: width >= DashMetrics.gridRowUnit * 2
    readonly property bool tall: height >= DashMetrics.gridRowUnit * 2
    readonly property string levelText: Math.round(BatteryService.displayBatteryLevel) + "%"
    readonly property string meterStyle: options.style ?? "solid"
    readonly property bool levelColors: options.color !== "theme"
    readonly property string healthText: options.health === true && BatteryService.batteryHealth.endsWith("%") ? I18n.tr("Health %1", "battery health, %1 is a percentage").arg(BatteryService.batteryHealth) : ""

    entryId: "battery"
    tone: options.tone ?? ""

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

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingM
        visible: root.wide

        BatteryMeter {
            id: wideMeter
            anchors.verticalCenter: parent.verticalCenter
            thickness: root.tall ? DashMetrics.batteryMeterThicknessHero : DashMetrics.batteryMeterThickness
            meterStyle: root.meterStyle
            levelColors: root.levelColors
            showNumber: false
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - wideMeter.width - parent.spacing
            spacing: Theme.spacingXXS

            StyledText {
                width: parent.width
                text: root.levelText
                font.pixelSize: root.tall ? Theme.fontSizeDisplay : Theme.fontSizeXXLarge
                font.weight: Theme.fontWeightMedium
                color: root.contentColor
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: BatteryService.batteryStatus
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: root.mutedColor
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: root.healthText
                font.pixelSize: Theme.fontSizeSmall
                color: root.mutedColor
                elide: Text.ElideRight
                visible: root.tall && text !== ""
            }
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: Theme.spacingXS
        visible: !root.wide

        BatteryMeter {
            anchors.horizontalCenter: parent.horizontalCenter
            thickness: DashMetrics.batteryMeterThicknessCompact
            meterStyle: root.meterStyle
            levelColors: root.levelColors
            showNumber: false
        }

        StyledText {
            width: parent.width
            text: root.levelText
            font.pixelSize: Theme.fontSizeXLarge
            font.weight: Theme.fontWeightMedium
            color: root.contentColor
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            text: BatteryService.batteryStatus
            font.pixelSize: Theme.fontSizeSmall
            color: root.mutedColor
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: root.tall
        }
    }
}
