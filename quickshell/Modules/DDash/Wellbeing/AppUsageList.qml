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

    property var days: []
    property int firstDayOfWeek: 1
    property date anchor: new Date()
    property date today: anchor
    property string period: "week"
    property bool showTitle: true
    property bool fillHeight: true

    readonly property var periods: [
        {
            "value": "day",
            "text": I18n.tr("Day", "screen time range filter")
        },
        {
            "value": "week",
            "text": I18n.tr("Week", "screen time range filter")
        },
        {
            "value": "month",
            "text": I18n.tr("Month", "screen time range filter")
        }
    ]
    readonly property var apps: Wellbeing.topApps(Wellbeing.periodDays(days, anchor, firstDayOfWeek, period, today), WellbeingMetrics.listedApps)
    readonly property real longest: apps.length > 0 ? apps[0].seconds : 0
    readonly property real listHeight: Math.max(1, apps.length) * WellbeingMetrics.appRowHeight + Math.max(0, apps.length - 1) * Theme.groupedListGap

    signal limitRequested(string appId)

    restRadius: DashMetrics.cardRadius
    pad: Theme.spacingL
    implicitHeight: pad * 2 + header.height + Theme.spacingM + listHeight

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Theme.buttonHeightXS

        StyledText {
            anchors.left: parent.left
            anchors.right: periodGroup.left
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showTitle
            text: I18n.tr("Most used apps", "screen time card title, apps ranked by time")
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightMedium
            color: root.contentColor
            elide: Text.ElideRight
        }

        DButtonGroup {
            id: periodGroup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            size: "small"
            checkEnabled: false
            model: root.periods.map(p => p.text)
            currentIndex: root.periods.findIndex(p => p.value === root.period)
            onSelectionChanged: (index, selected) => {
                if (selected)
                    root.period = root.periods[index].value;
            }
        }
    }

    StyledText {
        anchors.centerIn: listHost
        width: listHost.width - Theme.spacingL * 2
        visible: root.apps.length === 0
        text: I18n.tr("Nothing tracked yet", "empty state of the screen time app list")
        font.pixelSize: Theme.fontSizeMedium
        color: root.mutedColor
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    Loader {
        id: listHost
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: Theme.spacingM
        height: root.fillHeight ? parent.height - y : root.listHeight
        sourceComponent: root.fillHeight ? scrolling : stacked
    }

    // a nested list view would take the wheel from the settings page
    Component {
        id: stacked

        Column {
            spacing: Theme.groupedListGap

            Repeater {
                model: root.apps

                AppRow {
                    width: parent.width
                }
            }
        }
    }

    Component {
        id: scrolling

        DListView {
            clip: true
            spacing: Theme.groupedListGap
            showScrollBar: false
            model: root.apps

            delegate: AppRow {
                width: ListView.view.width
            }
        }
    }

    component AppRow: DListItem {
        id: row

        required property var modelData
        required property int index

        readonly property string appId: modelData.appId
        readonly property int limitMinutes: WellbeingService.appLimitMinutes(appId)
        readonly property bool overLimit: limitMinutes > 0 && modelData.seconds >= limitMinutes * 60

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
            id: name
            anchors.left: icon.right
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            width: WellbeingMetrics.appNameWidth
            text: WellbeingService.appName(row.appId)
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: row.contentColor
            elide: Text.ElideRight
        }

        Rectangle {
            anchors.left: name.right
            anchors.right: duration.left
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            height: DashMetrics.meterBarThickness
            radius: Theme.fullRadius(width, height)
            color: Theme.withAlpha(row.contentColor, Theme.stateLayerFocus)

            Rectangle {
                width: root.longest > 0 ? parent.width * row.modelData.seconds / root.longest : 0
                height: parent.height
                radius: parent.radius
                color: row.overLimit ? Theme.error : Theme.primary

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
            id: duration
            anchors.right: limitButton.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            reserveText: WellbeingService.formatDuration(10 * Wellbeing.secondsPerHour)
            text: WellbeingService.formatDuration(row.modelData.seconds)
            font.pixelSize: Theme.fontSizeMedium
            color: row.overLimit ? Theme.error : row.contentColor
        }

        DActionButton {
            id: limitButton
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: Theme.buttonHeightXS
            iconName: row.limitMinutes > 0 ? "timer" : "timer_off"
            iconColor: row.limitMinutes > 0 ? Theme.primary : row.supportingContentColor
            tooltipText: row.limitMinutes > 0 ? I18n.tr("%1 min").arg(row.limitMinutes) : I18n.tr("Set limit", "button that opens the per-app screen time limit editor")
            onClicked: root.limitRequested(row.appId)
        }
    }
}
