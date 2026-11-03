import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property string text: ""
    property string description: ""
    property alias value: field.text
    property alias labelText: field.labelText
    property alias leftIconName: field.leftIconName
    property alias isError: field.isError
    property alias supportingText: field.supportingText
    property alias placeholderText: field.placeholderText
    property alias validator: field.validator
    property alias maximumLength: field.maximumLength
    property alias actions: actionRow.data

    signal valueEdited(string value)
    signal editingFinished(string value)
    signal accepted(string value)

    title: ""
    subtitle: ""
    resetInHeader: false
    resetByKeys: false
    onResetRequested: {
        resetStore.resetToDefault(resetKeys);
        if (resetStore !== SettingsData || resetKeys.length !== 1)
            return;
        field.text = String(SettingsData[resetKeys[0]] ?? "");
    }

    body: Row {
        width: parent.width
        spacing: Theme.spacingS

        DTextField {
            id: field
            outlined: true
            labelText: root.text
            supportingText: root.description
            width: parent.width - (actionRow.visible ? actionRow.width + parent.spacing : 0)
            rightAccessoryWidth: resetButton.visible ? resetButton.width + Theme.spacingXS : 0
            Accessible.name: root.text || root.placeholderText
            Accessible.description: root.description
            onTextEdited: root.valueEdited(text)
            onEditingFinished: root.editingFinished(text)
            onAccepted: root.accepted(text)

            DActionButton {
                id: resetButton
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingXS
                y: field.containerTop + (field.containerHeight - height) / 2
                buttonSize: field.accessorySize
                iconName: "restart_alt"
                iconSize: Theme.iconSize
                iconColor: Theme.surfaceVariantText
                tooltipText: I18n.tr("Reset to default")
                Accessible.name: I18n.tr("Reset to default")
                visible: root.modified
                enabled: root.enabled
                onClicked: root.resetRequested()
            }
        }

        Row {
            id: actionRow
            y: field.containerTop + (field.containerHeight - height) / 2
            spacing: Theme.spacingS
            visible: children.length > 0
        }
    }
}
