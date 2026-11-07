import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

PanelWindow {
    id: root

    WlrLayershell.namespace: "dms:tooltip"

    property string text: ""
    property real targetX: 0
    property real targetY: 0
    property var targetScreen: null
    property bool alignLeft: false
    property bool alignRight: false
    property bool persistent: false
    property bool shown: false

    function show(text, x, y, screen, leftAlign, rightAlign) {
        root.text = text;
        targetScreen = screen ?? null;
        targetX = x;
        targetY = y;
        alignLeft = leftAlign ?? false;
        alignRight = rightAlign ?? false;
        shown = true;
    }

    function hide() {
        shown = false;
    }

    screen: targetScreen
    implicitWidth: Math.min(Theme.tooltipMaxWidth, textContent.implicitWidth) + Theme.spacingM * 2
    implicitHeight: textContent.implicitHeight + Theme.spacingS * 2
    color: "transparent"
    mask: Region {}
    visible: persistent || shown
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1

    anchors {
        top: true
        left: true
    }

    margins {
        left: {
            const screenWidth = targetScreen?.width ?? Screen.width;
            if (alignLeft) {
                return Math.round(Math.max(Theme.spacingS, Math.min(screenWidth - implicitWidth - Theme.spacingS, targetX)));
            } else if (alignRight) {
                return Math.round(Math.max(Theme.spacingS, Math.min(screenWidth - implicitWidth - Theme.spacingS, targetX - implicitWidth)));
            } else {
                return Math.round(Math.max(Theme.spacingS, Math.min(screenWidth - implicitWidth - Theme.spacingS, targetX - implicitWidth / 2)));
            }
        }
        top: {
            const screenHeight = targetScreen?.height ?? Screen.height;
            if (alignLeft || alignRight) {
                return Math.round(Math.max(Theme.spacingS, Math.min(screenHeight - implicitHeight - Theme.spacingS, targetY - implicitHeight / 2)));
            } else {
                return Math.round(Math.max(Theme.spacingS, Math.min(screenHeight - implicitHeight - Theme.spacingS, targetY)));
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.shown
        color: Theme.tooltipSurface
        radius: Theme.cornerRadiusXS

        StyledText {
            id: textContent

            anchors.centerIn: parent
            text: root.text
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.tooltipText
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            elide: Text.ElideRight
            width: Math.min(implicitWidth, Theme.tooltipMaxWidth)
        }
    }
}
