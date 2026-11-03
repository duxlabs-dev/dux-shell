import QtQuick
import qs.Common
import qs.DCommon.Widgets

DActionButton {
    id: root

    property bool confirming: false

    signal deleteRequested

    iconName: confirming ? "warning" : "delete"
    iconColor: confirming ? Theme.error : Theme.surfaceVariantText
    tooltipText: confirming ? I18n.tr("Confirm Delete") : I18n.tr("Delete")

    onActiveFocusChanged: {
        if (!activeFocus)
            confirming = false;
    }
    onClicked: {
        if (!confirming) {
            confirming = true;
            return;
        }
        confirming = false;
        deleteRequested();
    }
}
