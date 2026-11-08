import QtQuick
import qs.DCommon.Widgets

ConnectionSyncedRow {
    id: root

    property var browser: null
    property string target: ""

    actions: DActionButton {
        iconName: "folder_open"
        tooltipText: I18n.tr("Select File")
        Accessible.name: root.labelText + ": " + tooltipText
        onClicked: root.browser.open(root.target)
    }
}
