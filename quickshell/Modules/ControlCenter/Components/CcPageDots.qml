pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.ControlCenter

Item {
    id: root

    property int count: 0
    property int currentIndex: 0
    // Only the bottom padding, so its taps never reach the tiles above.
    property real targetHeight: CcMetrics.sheetPadding

    signal pageRequested(int index)

    function request(index: int) {
        const page = Math.max(0, Math.min(count - 1, index));
        if (page !== currentIndex)
            pageRequested(page);
    }

    visible: count > 1
    implicitWidth: dots.implicitWidth
    implicitHeight: count > 1 ? targetHeight : 0
    activeFocusOnTab: count > 1
    Accessible.role: Accessible.PageTabList

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Left:
            request(currentIndex + (I18n.isRtl ? 1 : -1));
            break;
        case Qt.Key_Right:
            request(currentIndex + (I18n.isRtl ? -1 : 1));
            break;
        case Qt.Key_Home:
            request(0);
            break;
        case Qt.Key_End:
            request(count - 1);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    Row {
        id: dots

        anchors.centerIn: parent
        layoutDirection: I18n.isRtl ? Qt.RightToLeft : Qt.LeftToRight
        // The direction is already the reading order; an inherited mirror would flip it back.
        LayoutMirroring.enabled: false

        Repeater {
            model: root.count

            Item {
                id: dot

                required property int index
                readonly property bool current: index === root.currentIndex

                width: pip.width + CcMetrics.pageDotSize
                height: root.targetHeight
                Accessible.role: Accessible.PageTab
                Accessible.name: I18n.tr("Page %1 of %2", "control center page indicator, %1 is the page number, %2 the page count").arg(index + 1).arg(root.count)
                Accessible.selected: current
                Accessible.onPressAction: root.request(index)

                Rectangle {
                    id: pip

                    anchors.centerIn: parent
                    width: dot.current ? CcMetrics.pageDotActiveWidth : CcMetrics.pageDotSize
                    height: CcMetrics.pageDotSize
                    radius: Theme.fullRadius(width, height)
                    color: dot.current ? Theme.primary : CcMetrics.pageDotColor

                    Behavior on width {
                        enabled: CcMetrics.animationsEnabled
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                        }
                    }

                    Behavior on color {
                        enabled: CcMetrics.animationsEnabled
                        ColorAnimation {
                            duration: Theme.expressiveDurations.expressiveEffects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }

                    FocusRing {
                        visible: dot.current && root.activeFocus
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.request(dot.index)
                }
            }
        }
    }
}
