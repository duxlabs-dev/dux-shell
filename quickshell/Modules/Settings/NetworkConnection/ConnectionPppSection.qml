pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import "../../../Common/ConnectionEditor.js" as CE

SettingsCard {
    id: root

    required property var editor

    readonly property int rev: editor.revision
    readonly property var ppp: {
        rev;
        return editor.draft?.ppp ?? {};
    }
    readonly property bool valid: true
    readonly property bool mppe: ppp["require-mppe"] === true

    readonly property var authMethods: [
        {
            "name": "EAP",
            "key": "refuse-eap"
        },
        {
            "name": "PAP",
            "key": "refuse-pap"
        },
        {
            "name": "CHAP",
            "key": "refuse-chap"
        },
        {
            "name": "MSCHAP",
            "key": "refuse-mschap"
        },
        {
            "name": "MSCHAPv2",
            "key": "refuse-mschapv2"
        }
    ]

    // Defaults are written as an absent key, so the profile stays clean.
    function setFlag(key, on) {
        editor.setValue("ppp", key, on ? true : undefined);
        // The MPPE sub-options only apply while MPPE is required.
        if (key === "require-mppe" && !on) {
            editor.setValue("ppp", "require-mppe-128", undefined);
            editor.setValue("ppp", "mppe-stateful", undefined);
        }
    }

    function setEcho(on) {
        const out = CE.applyPppEcho(ppp, on);
        for (const k of ["lcp-echo-interval", "lcp-echo-failure"])
            editor.setValue("ppp", k, out[k]);
    }

    function setSize(key, text) {
        const n = parseInt(text, 10);
        editor.setValue("ppp", key, n > 0 ? n : undefined);
    }

    // The stored key is a "refuse"/"no" flag when inverted, so the toggle shows its opposite.
    component FlagRow: SettingsToggleRow {
        required property string flagKey
        property bool inverted: false

        checked: (root.ppp[flagKey] === true) !== inverted
        onToggled: checked => root.setFlag(flagKey, checked !== inverted)
    }

    component SizeRow: ConnectionSyncedRow {
        id: sizeRow
        required property string sizeKey

        stored: {
            const n = Number(root.ppp[sizeKey] ?? 0);
            return n > 0 ? String(n) : "";
        }
        validator: IntValidator {
            bottom: 0
        }
        commit: t => root.setSize(sizeRow.sizeKey, t)
    }

    title: "PPP"
    collapsible: true
    expanded: false
    enabled: !editor.readOnly

    SettingsSectionLabel {
        text: I18n.tr("Authentication")
    }

    Repeater {
        model: root.authMethods

        FlagRow {
            required property var modelData
            text: modelData.name
            flagKey: modelData.key
            inverted: true
        }
    }

    FlagRow {
        text: I18n.tr("Use MPPE encryption", "PPP option")
        flagKey: "require-mppe"
    }

    FlagRow {
        enabled: root.mppe
        text: I18n.tr("Require 128-bit encryption", "MPPE")
        flagKey: "require-mppe-128"
    }

    FlagRow {
        enabled: root.mppe
        text: I18n.tr("Stateful MPPE", "PPP option")
        flagKey: "mppe-stateful"
    }

    FlagRow {
        text: I18n.tr("BSD compression", "PPP option")
        flagKey: "nobsdcomp"
        inverted: true
    }

    FlagRow {
        text: I18n.tr("Deflate compression", "PPP option")
        flagKey: "nodeflate"
        inverted: true
    }

    FlagRow {
        text: I18n.tr("TCP header compression", "PPP option")
        flagKey: "no-vj-comp"
        inverted: true
    }

    SettingsToggleRow {
        text: I18n.tr("Send PPP echo packets", "PPP option")
        checked: CE.pppEcho(root.ppp)
        onToggled: checked => root.setEcho(checked)
    }

    SizeRow {
        text: "MTU"
        sizeKey: "mtu"
    }

    SizeRow {
        text: "MRU"
        sizeKey: "mru"
    }
}
