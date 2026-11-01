import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

// The right end of a NiriRow: the Reset slot, the control and the toggle.
Item {
    id: root

    required property NiriRow row
    // Height of the row's label line: a stacked row puts Reset and the control under it, right-aligned.
    property real labelLineHeight: 0
    default property alias control: slot.data

    readonly property real slotWidth: slot.implicitWidth
    readonly property alias controlsWidth: controls.width
    readonly property alias controlsHeight: controls.height
    // The Reset slot stays reserved even when empty, so controls keep one column across rows (GNOME).
    readonly property real actionsWidth: Theme.avatarSize + Theme.spacingS + (row.toggle ? Theme.switchTrackWidth + Theme.spacingS : 0)

    // The alternate the hover preview shows for a row without its own tryValue: one obvious alternate per key.
    readonly property var afterList: ({
            "look.gaps": v => v >= 32 ? 4 : 48,
            "look.ringWidth": v => v > 6 ? 2 : 12,
            "look.borderWidth": v => v > 6 ? 2 : 12,
            "look.blurStrength": v => v > 4 ? 2 : 8,
            "columns.centerFocused": v => v === "always" ? "never" : "always",
            "columns.defaultWidth": v => v >= 0.5 ? 0.33333 : 0.66667,
            "columns.display": v => v === "tabbed" ? "normal" : "tabbed",
            "columns.overviewZoom": v => v > 0.5 ? 0.25 : 0.75,
            "columns.altTabDelay": v => v > 200 ? 0 : 400,
            "animations.slowdown": v => v >= 2 ? 1 : 2.5,
            "gestures.dndViewWidth": v => v >= 50 ? 10 : 80,
            "gestures.dndWorkspaceHeight": v => v >= 50 ? 10 : 80
        })

    function afterOf(key) {
        const after = afterList[key];
        return after ? after(row.value) : undefined;
    }

    Row {
        id: controls

        x: root.width - width
        y: root.row.stacked ? root.labelLineHeight + Theme.spacingS : (root.height - height) / 2
        spacing: Theme.spacingS

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.avatarSize
            height: Theme.avatarSize

            DActionButton {
                anchors.centerIn: parent
                visible: root.row.modified
                buttonSize: Theme.avatarSize
                iconName: "restart_alt"
                iconColor: Theme.surfaceVariantText
                tooltipText: I18n.tr("Reset to default")
                tooltipSide: "top"
                onClicked: root.row.resetValue()
            }
        }

        Row {
            id: slot
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS
        }

        DToggle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.row.toggle
            checked: root.row.isOn
            Accessible.name: root.row.title
            onToggled: checked => root.row.write(checked)
        }
    }
}
