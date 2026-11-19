pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../../../Common/BatteryDevices.js" as BatteryDevices

SettingsReorderList {
    id: root

    property var saved: null
    property var devices: []
    // Rows shown under the system battery while it is on, supplied by the host so they stay in its search index
    property Component systemDetails: null

    readonly property var rows: BatteryDevices.editorRows(saved, devices)
    readonly property var emptyRow: ({
            "id": "",
            "kind": "device",
            "name": "",
            "iconName": "",
            "present": false,
            "on": false,
            "icon": true,
            "percent": true,
            "lowOnly": false
        })
    readonly property var partKeys: ["icon", "percent", "lowOnly"]
    readonly property var partLabels: [I18n.tr("Icon", "battery bar widget: show the device glyph"), I18n.tr("Percentage", "battery bar widget: show the charge number"), I18n.tr("Only when low", "battery bar widget: show the entry only at or below the low threshold")]

    signal entriesEdited(var entries)

    function saveRows(next) {
        entriesEdited(next.map(row => BatteryDevices.entryForRow(row)));
    }

    function patchRow(index, patch) {
        saveRows(rows.map((row, i) => i === index ? Object.assign({}, row, patch) : row));
    }

    function removeRow(index) {
        saveRows(rows.filter((row, i) => i !== index));
    }

    // The rows follow the list by position, so a drag or a reading change never rebuilds them mid-use
    model: rows.length
    onReordered: indices => saveRows(indices.map(i => rows[i]))

    delegate: SettingsReorderRow {
        id: row

        readonly property var entry: root.rows[index] ?? root.emptyRow
        readonly property bool system: entry.kind === "system"
        readonly property bool detailed: entry.on && (system ? BatteryService.batteryAvailable : entry.present)

        reorderList: root
        clickable: true
        title: system ? (BatteryService.batteryAvailable ? I18n.tr("Battery", "battery bar widget: the laptop battery entry") : I18n.tr("Power", "battery bar widget: power icon entry on a desktop without battery")) : entry.name || I18n.tr("Device", "battery bar widget: peripheral without a name")
        subtitle: entry.present ? "" : I18n.tr("Not connected", "battery bar widget: saved device that is not connected")
        iconName: system ? (BatteryService.batteryAvailable ? BatteryService.getBatteryIcon() : "power") : (entry.iconName || "devices_other")
        iconColor: entry.present ? Theme.primary : Theme.onSurfaceVariant
        titleColor: entry.present ? contentColor : supportingContentColor
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: entry.on
        Accessible.onToggleAction: row.clicked(true)
        onClicked: root.patchRow(index, {
            "on": !entry.on
        })

        DActionButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.system && !row.entry.present
            iconName: "close"
            tooltipText: I18n.tr("Remove", "battery bar widget: forget a saved device")
            onClicked: root.removeRow(row.index)
        }

        DToggle {
            anchors.verticalCenter: parent.verticalCenter
            hideText: true
            text: row.title
            activeFocusOnTab: false
            Accessible.ignored: true
            checked: row.entry.on
            onToggled: value => root.patchRow(row.index, {
                    "on": value
                })
        }

        body: Loader {
            width: parent.width
            active: row.detailed
            sourceComponent: row.system ? systemBody : deviceBody

            Component {
                id: deviceBody

                Item {
                    implicitHeight: parts.height

                    DButtonGroup {
                        id: parts

                        anchors.left: parent.left
                        size: "small"
                        selectionMode: "multi"
                        arrowKeysSelect: false
                        maximumWidth: parent.width
                        model: root.partLabels
                        onSelectionChanged: (index, selected) => root.patchRow(row.index, {
                                [root.partKeys[index]]: selected
                            })
                    }

                    // The group assigns its own selection on a pick, which would drop a plain binding
                    Binding {
                        target: parts
                        property: "currentSelection"
                        value: root.partKeys.filter(key => row.entry[key]).map(key => root.partLabels[root.partKeys.indexOf(key)])
                    }
                }
            }

            Component {
                id: systemBody

                Column {
                    spacing: Theme.spacingXS

                    SettingsToggleRow {
                        width: parent.width
                        paintBackground: false
                        text: root.partLabels[2]
                        checked: row.entry.lowOnly
                        onToggled: checked => root.patchRow(row.index, {
                                "lowOnly": checked
                            })
                    }

                    Loader {
                        width: parent.width
                        sourceComponent: root.systemDetails
                    }
                }
            }
        }
    }
}
