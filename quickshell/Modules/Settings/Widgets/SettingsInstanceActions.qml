import QtQuick
import qs.Common
import qs.DCommon.Widgets

Row {
    id: root

    property bool fixed: false
    readonly property alias confirming: deleteButton.confirming
    default property alias extra: extraSlot.data

    signal duplicateRequested
    signal deleteRequested

    spacing: Theme.spacingS

    DIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: "chevron_right"
        size: Theme.iconSize
        color: Theme.onSurfaceVariant
        rotation: I18n.isRtl ? 180 : 0
    }

    SettingsDivider {
        vertical: true
    }

    Row {
        id: extraSlot
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS
        visible: !root.fixed && children.length > 0
    }

    DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.fixed
        iconName: "content_copy"
        tooltipText: I18n.tr("Duplicate", "verb, desktop widget menu action")
        onClicked: root.duplicateRequested()
    }

    SettingsDeleteButton {
        id: deleteButton
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.fixed
        onDeleteRequested: root.deleteRequested()
    }
}
