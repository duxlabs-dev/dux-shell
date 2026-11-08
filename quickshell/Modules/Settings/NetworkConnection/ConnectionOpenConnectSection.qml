pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets
import "../../../Common/ConnectionEditor.js" as CE

SettingsCard {
    id: root

    required property var editor
    readonly property bool valid: gatewayText.trim() !== ""

    readonly property int revision: editor.revision
    readonly property var vpnData: {
        revision;
        return editor.draft?.vpn?.data ?? {};
    }
    readonly property bool locked: editor.readOnly

    readonly property string protocolKey: vpnData.protocol ?? "anyconnect"
    readonly property var protocols: [["Cisco AnyConnect", "anyconnect"], ["Juniper Network Connect", "nc"], ["GlobalProtect", "gp"], ["Pulse Connect Secure", "pulse"], ["F5", "f5"], ["Fortinet", "fortinet"], ["Array Networks", "array"]].map(p => ({
                "label": p[0],
                "value": p[1]
            }))

    readonly property string gatewayText: vpnData.gateway ?? ""

    title: "OpenConnect"

    function setData(key, value) {
        editor.setValue("vpn", "data", CE.withDataEntry(vpnData, key, value));
    }

    ConnectionCertBrowser {
        id: certBrowser
        onPicked: (key, path) => root.setData(key, path)
    }

    component DataRow: ConnectionSyncedRow {
        id: dataRow
        required property string dataKey

        enabled: !root.locked
        stored: root.vpnData[dataKey] ?? ""
        commit: t => root.setData(dataRow.dataKey, t)
    }

    DataRow {
        dataKey: "gateway"
        text: I18n.tr("Gateway", "network IP setting label")
        isError: root.gatewayText.trim() === ""
    }

    ConnectionChoiceRow {
        text: I18n.tr("Protocol")
        enabled: !root.locked
        choices: root.protocols
        stored: root.protocolKey
        onPicked: value => root.setData("protocol", value)
    }

    Repeater {
        model: [
            {
                "key": "cacert",
                "label": I18n.tr("CA certificate", "network authentication certificate file field")
            },
            {
                "key": "usercert",
                "label": I18n.tr("Client certificate", "network authentication certificate file field")
            },
            {
                "key": "userkey",
                "label": I18n.tr("Private key", "network authentication key file field")
            }
        ]

        ConnectionPathRow {
            id: pathRow

            required property var modelData

            enabled: !root.locked
            browser: certBrowser
            target: modelData.key
            text: modelData.label
            stored: root.vpnData[modelData.key] ?? ""
            commit: t => root.setData(pathRow.modelData.key, t)
        }
    }

    DataRow {
        dataKey: "proxy"
        text: I18n.tr("Proxy", "VPN proxy server field")
    }
}
