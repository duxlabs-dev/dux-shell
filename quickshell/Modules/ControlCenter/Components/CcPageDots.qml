pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.ControlCenter

Item {
    id: root

    property int count: 0
    property int currentIndex: 0
    property real position: currentIndex
    // Overscroll past either end must not dim the lit dot.
    readonly property real settledPosition: Math.max(0, Math.min(count - 1, position))
    // Only the footer, so its taps never reach the tiles above.
    property real targetHeight: CcMetrics.pageFooterHeight

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

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        layoutDirection: I18n.isRtl ? Qt.RightToLeft : Qt.LeftToRight
        // The direction is already the reading order; an inherited mirror would flip it back.
        LayoutMirroring.enabled: false

        Repeater {
            model: root.count > 1 ? root.count : 0

            Item {
                id: dot

                required property int index
                readonly property bool current: index === root.currentIndex
                readonly property real lit: Math.max(0, 1 - Math.abs(index - root.settledPosition))

                width: pip.width + Theme.spacingXS
                height: root.targetHeight
                Accessible.role: Accessible.PageTab
                Accessible.name: I18n.tr("Page %1 of %2", "control center page indicator, %1 is the page number, %2 the page count").arg(index + 1).arg(root.count)
                Accessible.selected: current
                Accessible.onPressAction: root.request(index)

                Rectangle {
                    id: pip

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: CcMetrics.pageDotVerticalPadding
                    width: dot.current ? CcMetrics.pageDotActiveWidth : CcMetrics.pageDotSize
                    height: CcMetrics.pageDotSize
                    radius: Theme.fullRadius(width, height)
                    // No color Behavior: a tween would lag the finger.
                    color: Theme.blend(CcMetrics.pageDotColor, Theme.primary, dot.lit)

                    Behavior on width {
                        enabled: CcMetrics.animationsEnabled
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
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
