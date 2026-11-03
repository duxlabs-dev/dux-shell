import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Rectangle {
    id: root

    required property string outputName
    required property var outputData
    required property real canvasScaleFactor
    required property point canvasOffset

    property bool isConnected: outputData?.connected ?? false
    property bool isDragging: false
    property point originalLogical: Qt.point(0, 0)
    property point snappedLogical: Qt.point(0, 0)
    property bool isValidPosition: true

    property var physSize: DisplayConfigState.getPhysicalSize(outputData)
    property var logicalSize: DisplayConfigState.getLogicalSize(outputData)

    x: isDragging ? x : (outputData?.logical?.x ?? 0) * canvasScaleFactor + canvasOffset.x
    y: isDragging ? y : (outputData?.logical?.y ?? 0) * canvasScaleFactor + canvasOffset.y
    width: logicalSize.w * canvasScaleFactor
    height: logicalSize.h * canvasScaleFactor
    radius: Theme.cornerRadius
    opacity: isConnected ? 1.0 : 0.5

    color: {
        if (!isConnected)
            return SettingsMetrics.controlColor;
        if (!isValidPosition)
            return Theme.withAlpha(Theme.error, 0.3);
        if (isDragging)
            return Theme.withAlpha(Theme.primary, 0.4);
        if (dragArea.containsMouse)
            return Theme.withAlpha(Theme.primary, 0.2);
        return SettingsMetrics.controlColor;
    }

    border.color: {
        if (!isConnected)
            return Theme.outline;
        if (!isValidPosition)
            return Theme.error;
        if (isDragging)
            return Theme.primary;
        if (CompositorService.getFocusedScreen()?.name === outputName)
            return Theme.primary;
        return Theme.outline;
    }
    border.width: isDragging ? 3 : Theme.outlineWidthFocused
    z: isDragging ? 100 : (isConnected ? 1 : 0)

    Rectangle {
        id: snapPreview
        visible: root.isDragging && root.isValidPosition && SettingsData.displaySnapToEdge
        x: root.snappedLogical.x * root.canvasScaleFactor + root.canvasOffset.x - root.x
        y: root.snappedLogical.y * root.canvasScaleFactor + root.canvasOffset.y - root.y
        width: parent.width
        height: parent.height
        radius: Theme.cornerRadius
        color: "transparent"
        border.color: Theme.primary
        border.width: Theme.outlineWidthFocused
        opacity: 0.6
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingXXS

        DIcon {
            name: root.isConnected ? "desktop_windows" : "desktop_access_disabled"
            size: Math.min(24, Math.min(root.width * 0.3, root.height * 0.25))
            color: root.isConnected ? (root.isValidPosition ? Theme.primary : Theme.error) : Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: DisplayConfigState.getOutputDisplayName(root.outputData, root.outputName)
            font.pixelSize: Math.max(10, Math.min(14, root.width * 0.12))
            font.weight: Theme.fontWeightMedium
            color: root.isConnected ? Theme.surfaceText : Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            elide: Text.ElideMiddle
            width: Math.min(implicitWidth, root.width - 8)
        }

        StyledText {
            text: root.isConnected ? (root.physSize.w + "x" + root.physSize.h) : I18n.tr("Disconnected")
            font.pixelSize: Math.max(8, Math.min(11, root.width * 0.09))
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.isConnected
        cursorShape: !root.isConnected ? Qt.ArrowCursor : (root.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
        drag.target: root.isConnected ? root : null
        drag.axis: Drag.XAndYAxis
        drag.threshold: 0

        onPressed: mouse => {
            if (!root.isConnected)
                return;
            root.isDragging = true;
            root.originalLogical = Qt.point(root.outputData?.logical?.x ?? 0, root.outputData?.logical?.y ?? 0);
            root.snappedLogical = root.originalLogical;
            root.isValidPosition = true;
        }

        onPositionChanged: mouse => {
            if (!root.isDragging || !root.isConnected)
                return;
            let posX = Math.round((root.x - root.canvasOffset.x) / root.canvasScaleFactor);
            let posY = Math.round((root.y - root.canvasOffset.y) / root.canvasScaleFactor);

            const size = DisplayConfigState.getLogicalSize(root.outputData);

            const snapped = SettingsData.displaySnapToEdge ? DisplayConfigState.snapToEdges(root.outputName, posX, posY, size.w, size.h) : Qt.point(posX, posY);
            root.snappedLogical = snapped;
            root.isValidPosition = SettingsData.displaySnapToEdge ? !DisplayConfigState.checkOverlap(root.outputName, snapped.x, snapped.y, size.w, size.h) : true;
        }

        onReleased: {
            if (!root.isDragging || !root.isConnected)
                return;
            root.isDragging = false;

            const size = DisplayConfigState.getLogicalSize(root.outputData);
            const finalX = root.snappedLogical.x;
            const finalY = root.snappedLogical.y;

            if (SettingsData.displaySnapToEdge && DisplayConfigState.checkOverlap(root.outputName, finalX, finalY, size.w, size.h)) {
                root.isValidPosition = true;
                return;
            }

            if (finalX === root.originalLogical.x && finalY === root.originalLogical.y)
                return;

            DisplayConfigState.initOriginalOutputs();
            DisplayConfigState.backendUpdateOutputPosition(root.outputName, finalX, finalY);
            DisplayConfigState.setPendingChange(root.outputName, "position", {
                "x": finalX,
                "y": finalY
            });
        }
    }

    Drag.active: dragArea.drag.active && root.isConnected
}
