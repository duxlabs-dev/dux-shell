import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    required property string entryId
    property bool editable: entryId !== ""
    readonly property Item focusTarget: titleIcon

    signal editRequested

    implicitHeight: Theme.buttonHeightS
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    StyledButton {
        id: titleIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.buttonHeightS
        height: Theme.buttonHeightS
        radius: Theme.fullRadius(width, height)
        color: Theme.secondaryContainer
        Accessible.name: root.editable ? I18n.tr("Edit") : I18n.tr("Dashboard")
        enabled: root.editable
        onClicked: root.editRequested()

        DIcon {
            anchors.centerIn: parent
            name: root.editable && titleIcon.hovered ? "edit" : DashRegistry.entry(root.entryId)?.icon ?? "dashboard"
            size: Theme.iconSize
            color: Theme.onSecondaryContainer
        }

        StateLayer {
            control: titleIcon
            disabled: !root.editable
            stateColor: Theme.onSecondaryContainer
        }
    }

    StyledText {
        anchors.left: titleIcon.right
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        text: DashRegistry.entry(root.entryId)?.text ?? I18n.tr("Dashboard")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
    }
}
