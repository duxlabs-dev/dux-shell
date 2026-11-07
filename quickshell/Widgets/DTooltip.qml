import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property string text: ""
    property real targetX: 0
    property real targetY: 0
    property var screen: null
    property var targetScreen: screen
    property bool alignLeft: false
    property bool alignRight: false
    property bool persistent: false
    property bool shown: false

    readonly property var surface: IdleSurfaces.surfaceFor("tooltip", targetScreen?.name ?? "")
    readonly property bool attached: shown && !!surface
    readonly property real tooltipWidth: Math.min(Theme.tooltipMaxWidth, textContent.implicitWidth) + Theme.spacingM * 2
    readonly property real tooltipHeight: textContent.implicitHeight + Theme.spacingS * 2

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

    Rectangle {
        id: body

        readonly property var host: root
        parent: root.attached ? root.surface.hostItem : root
        visible: root.attached
        width: root.tooltipWidth
        height: root.tooltipHeight
        x: {
            const screenWidth = root.targetScreen?.width ?? 0;
            if (root.alignLeft)
                return Math.round(Math.max(Theme.spacingS, Math.min(screenWidth - width - Theme.spacingS, root.targetX)));
            if (root.alignRight)
                return Math.round(Math.max(Theme.spacingS, Math.min(screenWidth - width - Theme.spacingS, root.targetX - width)));
            return Math.round(Math.max(Theme.spacingS, Math.min(screenWidth - width - Theme.spacingS, root.targetX - width / 2)));
        }
        y: {
            const screenHeight = root.targetScreen?.height ?? 0;
            if (root.alignLeft || root.alignRight)
                return Math.round(Math.max(Theme.spacingS, Math.min(screenHeight - height - Theme.spacingS, root.targetY - height / 2)));
            return Math.round(Math.max(Theme.spacingS, Math.min(screenHeight - height - Theme.spacingS, root.targetY)));
        }
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
