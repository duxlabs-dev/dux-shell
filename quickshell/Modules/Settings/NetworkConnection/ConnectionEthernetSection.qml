import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import "../../../Common/ConnectionEditor.js" as CE

SettingsCard {
    id: root

    required property var editor
    readonly property bool valid: macRow.ok && clonedRows.ok && mtuRow.ok

    readonly property string sectionKey: "802-3-ethernet"
    readonly property int revision: editor.revision
    readonly property var eth: {
        revision;
        return editor.draft?.[sectionKey] ?? {};
    }
    readonly property var devices: NetworkService.ethernetDevices
    readonly property bool locked: editor.readOnly

    readonly property string linkMode: CE.linkNegotiation(eth)
    readonly property string storedDevice: {
        revision;
        return editor.value("connection", "interface-name", "");
    }
    readonly property var deviceOptions: [
        {
            "value": "",
            "label": I18n.tr("Auto")
        }
    ].concat((devices ?? []).map(d => ({
                "value": d.name,
                "label": d.name
            })))

    readonly property string wolCurrent: CE.wolMode(eth["wake-on-lan"])
    readonly property var wolOptions: [
        {
            "value": "default",
            "label": I18n.tr("Default")
        },
        {
            "value": "disabled",
            "label": I18n.tr("Disabled")
        },
        {
            "value": "magic",
            "label": I18n.tr("Magic packet", "Wake on LAN option")
        },
        {
            "value": "ignore",
            "label": I18n.tr("Ignore", "leave as the driver or system configured it")
        }
    ]

    readonly property var linkOptions: [
        {
            "value": "ignore",
            "label": I18n.tr("Ignore", "leave as the driver or system configured it")
        },
        {
            "value": "auto",
            "label": I18n.tr("Auto")
        },
        {
            "value": "manual",
            "label": I18n.tr("Manual")
        }
    ]

    readonly property string speedCurrent: eth.speed > 0 ? String(eth.speed) : ""
    readonly property var speedOptions: [10, 100, 1000, 2500, 5000, 10000, 25000, 40000, 50000, 100000].map(s => ({
                "value": String(s),
                "label": s + " Mbps"
            }))

    readonly property string duplexCurrent: eth.duplex ?? "full"
    readonly property var duplexOptions: [
        {
            "value": "full",
            "label": I18n.tr("Full")
        },
        {
            "value": "half",
            "label": I18n.tr("Half", "half duplex")
        }
    ]

    title: I18n.tr("Ethernet")

    function setEth(obj) {
        editor.setSection(sectionKey, obj);
    }

    function setEthValue(key, value) {
        editor.setValue(sectionKey, key, value);
    }

    function applyLink(mode, speed, duplex) {
        setEth(CE.applyLinkNegotiation(eth, mode, speed, duplex));
    }

    ConnectionChoiceRow {
        text: I18n.tr("Device")
        enabled: !root.locked
        choices: root.deviceOptions
        stored: root.storedDevice
        onPicked: value => root.editor.setValue("connection", "interface-name", value === "" ? undefined : value)
    }

    ConnectionMacRow {
        id: macRow
        text: I18n.tr("MAC address", "network hardware setting")
        enabled: !root.locked
        editor: root.editor
        section: root.sectionKey
        key: "mac-address"
    }

    ConnectionClonedMacRows {
        id: clonedRows
        enabled: !root.locked
        editor: root.editor
        section: root.sectionKey
    }

    ConnectionNumberRow {
        id: mtuRow
        text: "MTU"
        enabled: !root.locked
        editor: root.editor
        section: root.sectionKey
        key: "mtu"
        max: 4294967295
        zeroUnset: true
        placeholderText: I18n.tr("Auto")
    }

    ConnectionChoiceRow {
        text: I18n.tr("Wake on LAN", "Ethernet setting")
        enabled: !root.locked
        choices: root.wolOptions
        stored: root.wolCurrent
        onPicked: value => root.setEthValue("wake-on-lan", CE.wolValue(value))
    }

    ConnectionChoiceRow {
        text: I18n.tr("Link negotiation", "Ethernet link setting")
        enabled: !root.locked
        choices: root.linkOptions
        stored: root.linkMode
        onPicked: mode => root.applyLink(mode, root.eth.speed > 0 ? root.eth.speed : 1000, root.eth.duplex ?? "full")
    }

    ConnectionChoiceRow {
        visible: root.linkMode === "manual"
        text: I18n.tr("Speed")
        enabled: !root.locked
        choices: root.speedOptions
        stored: root.speedCurrent
        onPicked: value => root.applyLink("manual", parseInt(value), root.duplexCurrent)
    }

    ConnectionChoiceRow {
        visible: root.linkMode === "manual"
        text: I18n.tr("Duplex", "Ethernet link setting")
        enabled: !root.locked
        choices: root.duplexOptions
        stored: root.duplexCurrent
        onPicked: value => root.applyLink("manual", root.eth.speed, value)
    }
}
