pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import "../../Common/Format.js" as Format
import "Drives.js" as Drives

Item {
    id: stripRow

    property var drive: null
    property var mounts: []
    readonly property var strip: Drives.partitionStrip(drive, mounts)

    function partitionTooltip(device) {
        const p = (drive?.partitions ?? []).find(x => x.device === device);
        if (!p)
            return "";
        return [p.fsType ?? "", Format.formatBytes(p.size, true)].filter(s => s !== "").join(", ");
    }

    function segmentDetail(seg) {
        if (seg.usedRatio !== null && seg.size > 0)
            return I18n.tr("%1 of %2 used", "partition space, e.g. 1.2 TB of 2 TB used").arg(Drives.formatCapacity(seg.size * seg.usedRatio)).arg(Drives.formatCapacity(seg.size));
        return seg.size > 0 ? Drives.formatCapacity(seg.size) : "";
    }

    visible: strip.length > 0
    implicitHeight: Theme.buttonHeightS

    Row {
        anchors.fill: parent
        spacing: Theme.spacingXS

        Repeater {
            model: stripRow.strip

            ClippingRectangle {
                id: seg

                required property var modelData

                width: Math.max(0, stripRow.width - Theme.spacingXS * (stripRow.strip.length - 1)) * modelData.weight
                height: stripRow.height
                radius: Theme.cornerRadiusS
                color: Theme.surfaceContainerHighest

                Rectangle {
                    visible: seg.modelData.usedRatio !== null
                    width: parent.width * (seg.modelData.usedRatio ?? 0)
                    height: parent.height
                    color: Theme.withAlpha(Theme.primary, 0.28)
                }

                StyledText {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingS + Theme.spacingXXS
                    anchors.rightMargin: Theme.spacingS + Theme.spacingXXS
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.StyledText
                    text: {
                        const name = seg.modelData.swap ? I18n.tr("Swap") : seg.modelData.label;
                        const detail = stripRow.segmentDetail(seg.modelData);
                        return "<b>" + Format.escapeHtml(name) + "</b>" + (detail ? " " + Format.escapeHtml(detail) : "");
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: segHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                DTooltipHost {
                    text: stripRow.partitionTooltip(seg.modelData.device)
                    target: seg
                    hoverArea: segHover
                }
            }
        }
    }
}
