import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    component Layer: Rectangle {
        id: layer

        property string label: ""
        default property alias content: body.data

        width: parent?.width ?? 0
        height: body.y + body.height + Theme.spacingM

        StyledText {
            id: caption
            x: Theme.spacingM
            y: Theme.spacingM
            text: layer.label
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }

        Column {
            id: body
            x: Theme.spacingM
            y: caption.y + caption.height + Theme.spacingS
            width: parent.width - Theme.spacingM * 2
        }
    }

    width: parent?.width ?? 0
    height: host.height

    Layer {
        id: host
        label: I18n.tr("Host")
        color: Theme.hostSurface
        radius: Theme.cornerRadiusL
        border.width: Theme.layerOutlineWidth
        border.color: Theme.withAlpha(Theme.outline, Theme.layerOutlineOpacity)

        Layer {
            label: I18n.tr("Cards")
            color: Theme.cardSurface
            border.width: Theme.layerOutlineWidth
            border.color: Theme.outlineMedium
            radius: Theme.cornerRadiusM

            Layer {
                label: I18n.tr("Chip", "surface role")
                color: Theme.chipSurface
                radius: Theme.cornerRadiusS

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Rectangle {
                        width: parent.width
                        height: nestedLabel.height + Theme.spacingM * 2
                        color: Theme.chipSurfaceNested
                        radius: Theme.cornerRadiusXS

                        StyledText {
                            id: nestedLabel
                            anchors.centerIn: parent
                            text: I18n.tr("Nested chip", "surface role")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                        }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: tooltipLabel.implicitWidth + Theme.spacingM * 2
                        height: tooltipLabel.implicitHeight + Theme.spacingS * 2
                        color: Theme.tooltipSurface
                        radius: Theme.cornerRadiusXS

                        StyledText {
                            id: tooltipLabel
                            anchors.centerIn: parent
                            text: I18n.tr("Tooltip", "surface role")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.tooltipText
                        }
                    }
                }
            }
        }
    }
}
