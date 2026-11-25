pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash
import qs.Modules.ControlCenter.Widgets
import "Wellbeing.js" as Wellbeing

DCard {
    id: root

    property var day: null

    readonly property var apps: day ? Wellbeing.topApps([day], WellbeingMetrics.listedApps) : []

    signal limitRequested(string appId)

    restRadius: DashMetrics.cardRadius
    pad: Theme.spacingL

    StyledText {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        text: I18n.tr("Most used apps", "screen time card title, apps ranked by time")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: root.contentColor
        elide: Text.ElideRight
    }

    StyledText {
        anchors.centerIn: list
        width: list.width - Theme.spacingL * 2
        visible: root.apps.length === 0
        text: I18n.tr("Nothing tracked yet", "empty state of the screen time app list")
        font.pixelSize: Theme.fontSizeMedium
        color: root.mutedColor
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    DListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: Theme.spacingM
        anchors.bottom: parent.bottom
        clip: true
        spacing: Theme.groupedListGap
        showScrollBar: false
        model: root.apps

        delegate: DListItem {
            id: row

            required property var modelData
            required property int index

            readonly property string appId: modelData.appId
            readonly property int limitMinutes: WellbeingService.appLimitMinutes(appId)
            readonly property bool overLimit: limitMinutes > 0 && modelData.seconds >= limitMinutes * 60

            width: ListView.view.width
            height: WellbeingMetrics.appRowHeight
            surfaceColor: root.chipColor
            firstInGroup: index === 0
            lastInGroup: index === root.apps.length - 1
            Accessible.name: WellbeingService.appName(appId)
            onClicked: root.limitRequested(appId)

            CcAppIcon {
                id: icon
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                appId: row.appId
                iconSize: Theme.iconSizeLarge
            }

            StyledText {
                anchors.left: icon.right
                anchors.leftMargin: Theme.spacingM
                anchors.right: duration.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                text: WellbeingService.appName(row.appId)
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: row.contentColor
                elide: Text.ElideRight
            }

            NumericText {
                id: duration
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: WellbeingService.formatDuration(row.modelData.seconds)
                font.pixelSize: Theme.fontSizeMedium
                color: row.overLimit ? Theme.error : row.supportingContentColor
            }
        }
    }
}
