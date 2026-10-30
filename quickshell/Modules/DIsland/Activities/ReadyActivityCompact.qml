import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../../../Common/IslandKit.js" as Kit

// A plugin's ready-made face, compact: ring, title and value centered as one group, the same margin on both sides.
Item {
    id: root

    required property var face

    Accessible.role: Accessible.StaticText
    Accessible.name: root.face.name
    property bool isVertical: false

    readonly property color accent: Kit.readyTone(root.face.accent, Theme)
    // The detail beside the title takes at most this share of the pill, so the title stays readable.
    readonly property real detailShare: 1 / 3

    // Upright, the texts hide and the row keeps only the ring, centered the same way.
    Row {
        id: row

        anchors.centerIn: parent
        spacing: Theme.spacingS

        ReadyActivityRing {
            id: ring

            anchors.verticalCenter: parent.verticalCenter
            iconName: root.face.icon
            progress: root.face.progress
            accent: root.accent
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.isVertical
            width: Math.max(0, Math.min(implicitWidth, root.width - Theme.spacingM * 2 - ring.width - (detail.visible ? detail.width + row.spacing : 0) - row.spacing))
            text: root.face.title
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            maximumLineCount: 1
            elide: Text.ElideRight
        }

        StyledText {
            id: detail

            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width * root.detailShare)
            visible: !root.isVertical && text !== ""
            // A state accent is shown in words too, not by colour alone, as on the sheet.
            text: root.face.detail
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
            font.features: {
                "tnum": 1
            }
            maximumLineCount: 1
            elide: Text.ElideRight
        }
    }
}
