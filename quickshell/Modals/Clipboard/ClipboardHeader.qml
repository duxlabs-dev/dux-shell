import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: header

    required property var modal
    readonly property bool savedTab: modal.activeTab === "saved"

    implicitHeight: actions.implicitHeight

    ClipboardActions {
        id: actions
        anchors.fill: parent
        modal: header.modal
    }

    StyledText {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 2 * (actions.sideWidth + Theme.spacingM))
        text: (header.savedTab ? I18n.tr("Clipboard Saved") : I18n.tr("Clipboard History")) + ` (${header.savedTab ? header.modal.pinnedEntries.length : header.modal.unpinnedEntries.length})`
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
}
