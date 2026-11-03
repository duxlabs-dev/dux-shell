import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

StyledRect {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    width: parent.width
    height: messageContent.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadius
    color: SettingsMetrics.rowColor
    border.color: Theme.outlineMedium
    border.width: Theme.layerOutlineWidth

    Column {
        id: messageContent
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        Row {
            width: parent.width
            spacing: Theme.spacingM

            DIcon {
                name: "monitor"
                size: Theme.iconSize
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                width: parent.width - Theme.iconSize - Theme.spacingM
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: I18n.tr("Arrangement")
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                    width: parent.width
                    horizontalAlignment: Text.AlignLeft
                }

                StyledText {
                    text: I18n.tr("Display configuration is not available. WLR output management protocol not supported.")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                    horizontalAlignment: Text.AlignLeft
                }
            }
        }
    }
}
