import QtQuick
import qs.Common
import qs.DCommon.Widgets

// Every island dash face wears the M3 sheet handle instead of a title row: the compact pill already names the page.
Item {
    id: root

    property bool editable: true
    readonly property Item focusTarget: handle

    signal editRequested

    implicitHeight: Theme.spacingXL

    StyledButton {
        id: handle

        anchors.centerIn: parent
        width: Theme.bottomSheetHandleWidth + Theme.spacingL * 2
        height: parent.height
        radius: Theme.fullRadius(width, height)
        color: "transparent"
        enabled: root.editable
        Accessible.name: I18n.tr("Edit")
        onClicked: root.editRequested()

        // Pointer focus lands here on open, so only hover or keyboard focus lights it; no ring, the pill is the cue.
        Rectangle {
            readonly property bool lit: handle.hovered || handle.visualFocus

            anchors.centerIn: parent
            width: lit ? parent.width - Theme.spacingL : Theme.bottomSheetHandleWidth
            height: Theme.bottomSheetHandleHeight
            radius: Theme.fullRadius(width, height)
            color: lit ? Theme.primary : Theme.onSurfaceVariant_30

            Behavior on width {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }
        }

        StateLayer {
            control: handle
            disabled: !root.editable
            stateColor: Theme.onSurfaceVariant
        }
    }
}
