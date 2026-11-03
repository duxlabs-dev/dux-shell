import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import "../../Common/fcitx5Schema.js" as Fcitx5Schema

Item {
    id: root

    readonly property string uri: "fcitx://config/addon/" + SettingsUiState.selectedFcitx5Addon
    property var schema: null
    property var values: ({})
    readonly property var built: schema ? Fcitx5Schema.buildRows(schema, schema.root, []) : {
        "rows": [],
        "hidden": []
    }

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

    Component.onCompleted: {
        Fcitx5Service.probeConfigtool();
        load();
    }

    SettingsPage {
        SettingsCard {
            width: parent.width
            iconName: "tune"

            Repeater {
                model: root.built.rows

                delegate: Fcitx5Row {
                    required property var modelData

                    row: modelData
                    value: Fcitx5Schema.getPath(root.values, modelData.path)
                    onValueEdited: (path, value) => root.save(path, value)
                }
            }

            SettingsNoteRow {
                visible: root.built.hidden.length > 0 && Fcitx5Service.configtoolFound
                noteIconName: "info"
                tint: Theme.primary
                tintBackground: Theme.primaryHover
                text: I18n.tr("Some options are only available in fcitx5-configtool: %1", "Displayed when not all config options are displayed in a fctix5 addon config page, followed by the option names").arg(root.built.hidden.join(", "))
            }
        }
    }
}
