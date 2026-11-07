pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    implicitHeight: column.height

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string currentMountPath: "/"

    readonly property string title: I18n.tr("Disk usage")
    readonly property var mounts: DgopService.diskMounts || []

    signal mountPathChanged(string newMountPath)

    Ref {
        service: DgopService
        modules: ["diskmounts"]
        active: root.visible && (root.Window.window?.visible ?? false)
    }

    function usageOf(mount) {
        return parseFloat((mount.percent || "0").replace("%", "")) || 0;
    }

    DFlickable {
        anchors.fill: parent
        contentHeight: column.height
        clip: true

        Column {
            id: column
            width: parent.width
            spacing: CcMetrics.detailContentGap

            CcEmptyState {
                visible: !DgopService.dgopAvailable || root.mounts.length === 0
                iconName: DgopService.dgopAvailable ? "storage" : "error"
                iconColor: DgopService.dgopAvailable ? Theme.primary : Theme.error
                title: DgopService.dgopAvailable ? I18n.tr("No disk data available") : I18n.tr("%1 not available", "%1 is a tool or environment variable name").arg("dgop")
            }

            CcGroup {
                visible: root.mounts.length > 0

                Repeater {
                    model: root.mounts

                    CcListRow {
                        required property var modelData

                        readonly property real usage: root.usageOf(modelData)

                        iconName: "storage"
                        iconColor: {
                            if (usage > CcMetrics.diskCriticalPercent)
                                return Theme.error;
                            if (usage > CcMetrics.diskWarnPercent)
                                return Theme.warning;
                            return contentColor;
                        }
                        active: modelData.mount === root.currentMountPath
                        title: modelData.mount === "/" ? I18n.tr("Root Filesystem") : modelData.mount
                        subtitle: `${modelData.used || "?"} / ${modelData.size || "?"}` + (modelData.mount === "/" ? "" : " • " + modelData.mount)
                        trailingBadge: usage.toFixed(0) + "%"
                        clickable: true
                        onClicked: {
                            root.currentMountPath = modelData.mount;
                            root.mountPathChanged(modelData.mount);
                        }
                    }
                }
            }
        }
    }
}
