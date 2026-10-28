pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash
import qs.Modules.DDash.Wellbeing
import qs.Modules.ControlCenter.Widgets
import "../Wellbeing/Wellbeing.js" as Wellbeing

Card {
    id: root

    property bool live: Window.window?.visible ?? false

    readonly property bool wide: width >= DashMetrics.gridRowUnit * 2
    readonly property bool tall: height >= DashMetrics.gridRowUnit * 2
    readonly property var today: WellbeingService.today
    readonly property real appRowHeight: Theme.iconSizeMedium + Theme.spacingXS
    readonly property int appRows: tall ? Math.min(WellbeingMetrics.cardApps, Math.floor((height - pad * 2 - header.height - value.height - Theme.spacingS * 2) / (appRowHeight + Theme.spacingXS))) : 0
    readonly property var apps: appRows > 0 ? Wellbeing.topApps([today], appRows) : []
    readonly property real limitSeconds: SettingsData.wellbeingDailyLimit * 60
    readonly property bool overLimit: limitSeconds > 0 && today.active >= limitSeconds

    entryId: "wellbeing"
    clickable: true
    clipContent: true
    pad: Theme.spacingM
    Accessible.name: I18n.tr("Screen time", "dashboard card and settings card title, time spent in apps")

    Row {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.spacingS

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "digital_wellbeing"
            size: Theme.iconSizeMedium
            color: root.accentColor
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.iconSizeMedium - parent.spacing
            text: I18n.tr("Screen time", "dashboard card and settings card title, time spent in apps")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: root.contentColor
            elide: Text.ElideRight
        }
    }

    StyledText {
        id: value
        anchors.left: parent.left
        anchors.right: parent.right
        y: root.apps.length > 0 ? header.height + Theme.spacingXS : parent.height - height
        text: WellbeingService.formatDuration(root.today.active)
        font.pixelSize: root.wide ? Theme.fontSizeXXLarge : DashMetrics.tileValueSizeCompact
        font.weight: Theme.fontWeightMedium
        font.features: ({
                "tnum": 1
            })
        color: root.overLimit ? Theme.error : root.contentColor
        elide: Text.ElideRight
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: value.bottom
        anchors.topMargin: Theme.spacingS
        spacing: Theme.spacingXS
        visible: root.apps.length > 0

        Repeater {
            model: root.apps

            Item {
                id: appRow
                required property var modelData
                width: parent.width
                height: root.appRowHeight

                CcAppIcon {
                    id: icon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    appId: appRow.modelData.appId
                    iconSize: Theme.iconSizeMedium
                }

                StyledText {
                    anchors.left: icon.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: time.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: WellbeingService.appName(appRow.modelData.appId)
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.contentColor
                    elide: Text.ElideRight
                }

                StyledText {
                    id: time
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: WellbeingService.formatDuration(appRow.modelData.seconds)
                    font.pixelSize: Theme.fontSizeSmall
                    font.features: ({
                            "tnum": 1
                        })
                    color: root.mutedColor
                }
            }
        }
    }
}
