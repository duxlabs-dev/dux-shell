import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/fcitx5Schema.js" as Fcitx5Schema

SettingsRow {
    id: root

    required property var fields
    required property var item

    signal fieldEdited(var fieldPath, var value)
    signal removed

    leading: Row {
        spacing: Theme.spacingS

        Repeater {
            model: root.fields

            delegate: Item {
                id: cell

                required property var modelData
                required property int index
                readonly property var fieldValue: Fcitx5Schema.getPath(root.item, modelData.path)

                anchors.verticalCenter: parent.verticalCenter
                width: modelData.kind === "bool" ? toggle.width : field.width
                height: Math.max(toggle.height, field.height)

                DToggle {
                    id: toggle
                    anchors.verticalCenter: parent.verticalCenter
                    visible: cell.modelData.kind === "bool"
                    hideText: true
                    text: cell.modelData.label
                    activeFocusOnTab: false
                    Accessible.name: cell.modelData.label
                    checked: Fcitx5Schema.boolValue(cell.fieldValue)
                    onToggled: value => root.fieldEdited(cell.modelData.path, Fcitx5Schema.boolString(value))
                }

                DTextField {
                    id: field
                    anchors.verticalCenter: parent.verticalCenter
                    visible: cell.modelData.kind !== "bool"
                    width: cell.modelData.kind === "strings" ? SettingsMetrics.fieldWidthXL : (cell.index === root.fields.length - 1 ? SettingsMetrics.fieldWidthM : SettingsMetrics.fieldWidthS)
                    placeholderText: cell.modelData.label
                    text: cell.modelData.kind === "strings" ? Fcitx5Schema.joinList(cell.fieldValue) : String(cell.fieldValue ?? "")
                    Accessible.name: cell.modelData.label
                    onEditingFinished: {
                        const strings = cell.modelData.kind === "strings";
                        if (text === (strings ? Fcitx5Schema.joinList(cell.fieldValue) : String(cell.fieldValue ?? "")))
                            return;
                        root.fieldEdited(cell.modelData.path, strings ? Fcitx5Schema.splitList(text) : text);
                    }
                }
            }
        }
    }

    DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        iconName: "delete"
        tooltipText: I18n.tr("Delete")
        onClicked: root.removed()
    }
}
