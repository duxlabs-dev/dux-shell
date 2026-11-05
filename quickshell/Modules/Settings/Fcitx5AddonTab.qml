import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Services
import "../../Common/fcitx5Schema.js" as Fcitx5Schema

Item {
    id: root

    property var parentModal: null
    // Snapshot, not a binding: the page beneath a sub page stays alive and must keep its own addon.
    property string addon: ""
    readonly property string uri: Fcitx5Schema.addonUri(addon)
    property var schema: null
    property var values: ({})
    readonly property var built: schema ? Fcitx5Schema.buildRows(schema, schema.root, []) : {
        "rows": [],
        "hidden": []
    }

    readonly property var sections: Fcitx5Schema.sections(built.rows)

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    function load() {
        Fcitx5Service.getConfig(uri, result => {
            if (!root.schema)
                root.schema = result.schema;
            root.values = result.value;
        });
    }

    function save(path, value) {
        values = Fcitx5Schema.setPath(values, path, value);
        Fcitx5Service.setConfig(uri, values, load);
    }

    function listOf(row) {
        return Fcitx5Schema.toArray(Fcitx5Schema.getPath(values, row.path));
    }

    function addItem(row) {
        const list = listOf(row);
        if (row.kind === "structs") {
            save(row.path, list.concat([Fcitx5Schema.newItem(row.fields)]));
            return;
        }
        const free = Fcitx5Schema.toArray(row.choices.values).find(v => !list.includes(v));
        if (free !== undefined)
            save(row.path, list.concat([free]));
    }

    function removeItem(row, index) {
        save(row.path, listOf(row).filter((_, i) => i !== index));
    }

    Component.onCompleted: {
        load();
    }

    SettingsPage {
        Repeater {
            model: root.sections

            delegate: Column {
                id: section

                required property var modelData

                width: parent.width
                spacing: SettingsMetrics.cardGap

                SettingsCard {
                    width: parent.width
                    title: section.modelData.title
                    iconName: "tune"

                    Repeater {
                        model: section.modelData.rows

                        delegate: Fcitx5Row {
                            required property var modelData

                            row: modelData
                            value: Fcitx5Schema.getPath(root.values, modelData.path)
                            onValueEdited: (path, value) => root.save(path, value)
                            onSubOpened: (addon, title) => {
                                SettingsUiState.selectedFcitx5SubAddon = addon;
                                SettingsUiState.selectedFcitx5SubAddonTitle = title;
                                root.parentModal?.navigateTo("fcitx5_addon_sub");
                            }
                        }
                    }

                    Repeater {
                        model: section.modelData.list?.kind === "structs" ? root.listOf(section.modelData.list).length : 0

                        delegate: Fcitx5StructItemRow {
                            required property int index

                            fields: section.modelData.list.fields
                            item: Fcitx5Schema.getPath(root.values, section.modelData.list.path.concat(index))
                            onFieldEdited: (fieldPath, value) => root.save(section.modelData.list.path.concat(index, fieldPath), value)
                            onRemoved: root.removeItem(section.modelData.list, index)
                        }
                    }

                    SettingsReorderList {
                        id: enumList

                        visible: section.modelData.list?.kind === "enums"
                        model: section.modelData.list?.kind === "enums" ? root.listOf(section.modelData.list) : []
                        onReordered: indices => root.save(section.modelData.list.path, Fcitx5Schema.applyOrder(root.listOf(section.modelData.list), indices))

                        delegate: SettingsReorderRow {
                            id: enumRow

                            required property var modelData

                            reorderList: enumList
                            title: Fcitx5Schema.enumLabel(section.modelData.list.choices, modelData)

                            DActionButton {
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "close"
                                iconColor: Theme.error
                                tooltipText: I18n.tr("Remove")
                                onClicked: root.removeItem(section.modelData.list, enumRow.index)
                            }
                        }
                    }

                    SettingsRow {
                        visible: section.modelData.list?.kind === "structs"
                        iconName: "add"
                        title: I18n.tr("Add")
                        clickable: true
                        onClicked: root.addItem(section.modelData.list)
                    }
                }

                Item {
                    width: parent.width
                    height: addButton.height
                    visible: section.modelData.list?.kind === "enums"

                    DButton {
                        id: addButton

                        anchors.right: parent.right
                        text: I18n.tr("Add")
                        iconName: "add"
                        backgroundColor: Theme.secondaryContainer
                        textColor: Theme.onSecondaryContainer
                        enabled: section.modelData.list?.kind !== "enums" || Fcitx5Schema.toArray(section.modelData.list.choices.values).some(v => !root.listOf(section.modelData.list).includes(v))
                        onClicked: root.addItem(section.modelData.list)
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            visible: root.built.hidden.length > 0
            iconName: "tune"

            SettingsNoteRow {
                noteIconName: "info"
                tint: Theme.primary
                tintBackground: Theme.primaryHover
                text: I18n.tr("Some options are only available in fcitx5-configtool: %1", "Displayed when not all config options are displayed in a fcitx5 addon config page, followed by the option names").arg(root.built.hidden.join(", "))
            }
        }
    }
}
