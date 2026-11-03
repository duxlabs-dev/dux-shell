import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: actions

    required property var modal
    readonly property real sideWidth: Math.max(leading.width, trailing.width)

    implicitWidth: leading.width + Theme.spacingXS + trailing.width
    implicitHeight: Theme.buttonHeightXS

    Row {
        id: leading
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        DActionButton {
            Keys.forwardTo: [actions.modal.modalFocusScope]
            iconName: "push_pin"
            iconColor: actions.modal.activeTab === "saved" ? Theme.onPrimary : Theme.onSurfaceVariant
            backgroundColor: actions.modal.activeTab === "saved" ? Theme.primary : "transparent"
            visible: actions.modal.pinnedCount > 0 || actions.modal.activeTab === "saved"
            tooltipText: actions.modal.activeTab === "saved" ? I18n.tr("Recent", "clipboard button tooltip, switches to recent entries") : I18n.tr("Saved", "clipboard button tooltip, switches to saved entries")
            onClicked: actions.modal.activeTab = actions.modal.activeTab === "saved" ? "recents" : "saved"
        }

        DActionButton {
            Keys.forwardTo: [actions.modal.modalFocusScope]
            objectName: "keyboardHints"
            iconName: "info"
            iconColor: actions.modal.showKeyboardHints ? Theme.onSecondaryContainer : Theme.onSurfaceVariant
            backgroundColor: actions.modal.showKeyboardHints ? Theme.secondaryContainer : "transparent"
            tooltipText: I18n.tr("Keyboard shortcuts")
            onClicked: actions.modal.showKeyboardHints = !actions.modal.showKeyboardHints
        }
    }

    Row {
        id: trailing
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        DActionButton {
            Keys.forwardTo: [actions.modal.modalFocusScope]
            iconName: "settings"
            tooltipText: I18n.tr("Settings")
            onClicked: actions.modal.openSettings()
        }

        DActionButton {
            Keys.forwardTo: [actions.modal.modalFocusScope]
            iconName: "delete_sweep"
            enabled: actions.modal.canClear
            iconColor: Theme.onSecondaryContainer
            backgroundColor: Theme.secondaryContainer
            tooltipText: actions.modal.clearsFilteredOnly ? I18n.tr("Clear Filtered", "clipboard modal: clear button tooltip while a search filter is active") : I18n.tr("Clear All")
            onClicked: actions.modal.confirmClearAll()
        }

        DActionButton {
            Keys.forwardTo: [actions.modal.modalFocusScope]
            visible: !actions.modal.popout
            iconName: "close"
            tooltipText: I18n.tr("Close")
            onClicked: actions.modal.hide()
        }
    }
}
