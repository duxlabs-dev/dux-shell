import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Rectangle {
    id: root

    property string draggingOutput: ""
    readonly property bool identifyActive: draggingOutput !== "" || identifyButton.pressed

    property var filteredOutputs: {
        void (DisplayConfigState.pendingHyprlandChanges);
        void (DisplayConfigState.pendingNiriChanges);
        const all = DisplayConfigState.allOutputs || {};
        const keys = Object.keys(all);
        return keys.filter(k => {
            const od = all[k];
            const isConnected = od?.connected ?? false;
            if (!isConnected)
                return SettingsData.displayShowDisconnected;
            if (CompositorService.isHyprland && DisplayConfigState.getHyprlandSetting(od, k, "disabled", false))
                return false;
            if (CompositorService.isNiri && DisplayConfigState.getNiriSetting(od, k, "disabled", false))
                return false;
            return true;
        });
    }

    property var filteredBounds: {
        const all = DisplayConfigState.allOutputs || {};
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const name of filteredOutputs) {
            const output = all[name];
            if (!output?.logical)
                continue;
            const x = output.logical.x;
            const y = output.logical.y;
            const size = DisplayConfigState.getLogicalSize(output);
            const w = size.w || 1920;
            const h = size.h || 1080;
            minX = Math.min(minX, x);
            minY = Math.min(minY, y);
            maxX = Math.max(maxX, x + w);
            maxY = Math.max(maxY, y + h);
        }
        if (minX === Infinity)
            return {
                minX: 0,
                minY: 0,
                width: 1920,
                height: 1080
            };
        return {
            minX: minX,
            minY: minY,
            width: maxX - minX,
            height: maxY - minY
        };
    }

    width: parent.width
    height: 280
    radius: Theme.cornerRadius
    color: SettingsMetrics.rowColor
    border.color: Theme.outlineMedium
    border.width: Theme.layerOutlineWidth

    Item {
        id: canvas
        anchors.fill: parent
        anchors.margins: Theme.spacingL

        property var bounds: root.filteredBounds
        property real scaleFactor: {
            if (bounds.width === 0 || bounds.height === 0)
                return 0.1;
            const padding = Theme.spacingL * 2;
            const scaleX = (width - padding) / bounds.width;
            const scaleY = (height - padding) / bounds.height;
            return Math.min(scaleX, scaleY);
        }
        property point offset: Qt.point((width - bounds.width * scaleFactor) / 2 - bounds.minX * scaleFactor, (height - bounds.height * scaleFactor) / 2 - bounds.minY * scaleFactor)

        Repeater {
            model: root.filteredOutputs

            delegate: MonitorRect {
                required property string modelData
                outputName: modelData
                outputData: DisplayConfigState.allOutputs[modelData]
                canvasScaleFactor: canvas.scaleFactor
                canvasOffset: canvas.offset
                onIsDraggingChanged: {
                    if (isDragging) {
                        root.draggingOutput = outputName;
                        return;
                    }
                    if (root.draggingOutput === outputName)
                        root.draggingOutput = "";
                }
            }
        }
    }

    DActionButton {
        id: identifyButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingS
        iconName: "badge"
        iconColor: pressed ? Theme.primary : Theme.surfaceVariantText
        tooltipText: I18n.tr("Identify", "button for identifying monitor positions")
        z: 200
    }
}
