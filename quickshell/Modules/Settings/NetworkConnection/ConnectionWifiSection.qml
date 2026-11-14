pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

SettingsCard {
    id: root

    required property var editor

    readonly property string section: "802-11-wireless"
    readonly property int rev: editor.revision
    readonly property var wifi: {
        rev;
        return editor.draft ? (editor.draft[section] ?? {}) : {};
    }

    readonly property bool ssidDecodable: editor.isNew || editor.original?.[section]?.ssid !== undefined
    readonly property string ssid: String(wifi.ssid ?? "")
    readonly property string mode: wifi.mode ?? "infrastructure"
    readonly property int powersave: wifi.powersave ?? 0

    readonly property bool valid: (!ssidDecodable || ssid !== "") && bssidRow.ok && macRow.ok && clonedRows.ok

    readonly property var modeChoices: [
        {
            "label": I18n.tr("Infrastructure", "Wi-Fi mode: client of an access point"),
            "value": "infrastructure"
        },
        {
            "label": I18n.tr("Ad-hoc", "Wi-Fi mode"),
            "value": "adhoc"
        },
        {
            "label": I18n.tr("Hotspot"),
            "value": "ap"
        }
    ]
    readonly property var bandChoices: [
        {
            "label": I18n.tr("Auto"),
            "value": ""
        },
        {
            "label": I18n.tr("2.4 GHz"),
            "value": "bg"
        },
        {
            "label": I18n.tr("5 GHz"),
            "value": "a"
        },
        {
            "label": I18n.tr("6 GHz", "WiFi band option"),
            "value": "6GHz"
        }
    ]
    readonly property var powersaveChoices: [
        {
            "label": I18n.tr("Default"),
            "value": 0
        },
        {
            "label": I18n.tr("Enabled"),
            "value": 3
        },
        {
            "label": I18n.tr("Disabled"),
            "value": 2
        },
        {
            "label": I18n.tr("Ignore", "leave as the driver or system configured it"),
            "value": 1
        }
    ]

    title: I18n.tr("Wi-Fi")
    enabled: !editor.readOnly

    SettingsTextFieldRow {
        visible: root.ssidDecodable
        text: I18n.tr("Network Name (SSID)")
        value: root.ssid
        isError: root.editor.showErrors && root.ssid === ""
        onValueEdited: value => root.editor.setValue(root.section, "ssid", value)
    }

    SettingsRow {
        visible: !root.ssidDecodable
        title: I18n.tr("Network Name (SSID)")
        subtitle: I18n.tr("Unknown")
    }

    ConnectionChoiceRow {
        text: I18n.tr("Mode")
        choices: root.modeChoices
        stored: root.mode
        onPicked: value => root.editor.setValue(root.section, "mode", value)
    }

    SettingsToggleRow {
        text: I18n.tr("Hidden")
        checked: root.wifi.hidden === true
        onToggled: checked => root.editor.setValue(root.section, "hidden", checked)
    }

    ConnectionChoiceRow {
        text: I18n.tr("Band")
        choices: root.bandChoices
        stored: root.wifi.band ?? ""
        onPicked: value => root.editor.setValue(root.section, "band", value === "" ? undefined : value)
    }

    ConnectionNumberRow {
        visible: root.mode !== "infrastructure"
        text: I18n.tr("Channel")
        editor: root.editor
        section: root.section
        key: "channel"
        max: 4294967295
        zeroUnset: true
        placeholderText: I18n.tr("Auto")
    }

    ConnectionMacRow {
        id: bssidRow
        text: "BSSID"
        editor: root.editor
        section: root.section
        key: "bssid"
    }

    ConnectionMacRow {
        id: macRow
        text: I18n.tr("MAC address", "network hardware setting")
        editor: root.editor
        section: root.section
        key: "mac-address"
    }

    ConnectionClonedMacRows {
        id: clonedRows
        editor: root.editor
        section: root.section
    }

    ConnectionNumberRow {
        text: "MTU"
        editor: root.editor
        section: root.section
        key: "mtu"
        max: 4294967295
        zeroUnset: true
        placeholderText: I18n.tr("Auto")
    }

    ConnectionChoiceRow {
        text: I18n.tr("Power saving", "WiFi setting")
        choices: root.powersaveChoices
        stored: root.powersave
        onPicked: value => root.editor.setValue(root.section, "powersave", value === 0 ? undefined : value)
    }
}
