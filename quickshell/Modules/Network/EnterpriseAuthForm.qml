pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.NetworkConnection
import qs.Modules.Settings.Widgets
import "../../Common/ConnectionEditor.js" as CE

Column {
    id: root

    property string usernameSuffix: ""
    property bool usernameSuffixRequired: false
    property string caDisplayName: ""
    property string defaultCa: "system"
    property bool advancedOpen: false
    property bool showIcons: true
    property bool markInvalid: false
    property bool surfaceBrowser: false
    // Files NM already holds as blobs (keys ca, clientCert, privateKey): they count as present while their path is empty.
    property var storedFiles: ({})
    property var original: ({})
    readonly property bool valid: CE.enterpriseConfigValid(toConfig(), {
        usernameSuffix: usernameSuffix,
        usernameSuffixRequired: usernameSuffixRequired,
        storedFiles: storedFiles
    })

    signal submitRequested

    readonly property var methodChoices: [{"label": "PEAP", "value": "peap"}, {"label": "TTLS", "value": "ttls"}, {"label": "TLS", "value": "tls"}, {"label": "PWD", "value": "pwd"}]
    readonly property var innerChoices: ({
            "peap": [{"label": "MSCHAPv2", "value": "mschapv2"}, {"label": "GTC", "value": "gtc"}, {"label": "MD5", "value": "md5"}],
            "ttls": [{"label": "PAP", "value": "pap"}, {"label": "MSCHAP", "value": "mschap"}, {"label": "MSCHAPv2", "value": "mschapv2"}, {"label": "CHAP", "value": "chap"}, {"label": "EAP-MSCHAPv2", "value": "eap-mschapv2"}]
        })
    readonly property var caChoices: [{"label": I18n.tr("File"), "value": "file"}, {"label": I18n.tr("Use system certificates", "802.1X CA certificate source option"), "value": "system"}, {"label": I18n.tr("None"), "value": "none"}]
    readonly property var matchChoices: [{"label": I18n.tr("Exact"), "value": false}, {"label": I18n.tr("Suffix", "server name match type"), "value": true}]
    readonly property var peapVersionChoices: [{"label": I18n.tr("Auto"), "value": ""}, {"label": "0", "value": "0"}, {"label": "1", "value": "1"}]

    readonly property bool usesInner: draft.eap === "peap" || draft.eap === "ttls"
    readonly property bool usesCa: draft.eap !== "pwd"
    readonly property bool isTls: draft.eap === "tls"
    readonly property bool usesTlsOptions: draft.eap !== "pwd"

    function defaultInner(eap) {
        return eap === "ttls" ? "pap" : "mschapv2";
    }

    function reset(cfg) {
        const c = cfg || {};
        advancedOpen = false;
        const eap = methodChoices.some(m => m.value === c.eap) ? c.eap : "peap";
        const inner = innerChoices[eap] || [];
        draft.eap = eap;
        draft.phase2 = inner.some(i => i.value === c.phase2) ? c.phase2 : defaultInner(eap);
        draft.identity = c.identity || "";
        draft.password = c.password || "";
        draft.savePassword = !c.askPassword;
        draft.anonymousIdentity = c.anonymousIdentity || "";
        draft.ca = caChoices.some(a => a.value === c.ca) ? c.ca : defaultCa;
        draft.caCertPath = c.caCertPath || "";
        draft.caCertPem = c.caCertPem || "";
        draft.serverDomain = c.serverDomain || "";
        draft.serverDomainSuffix = !!c.serverDomainSuffix;
        draft.clientCertPath = c.clientCertPath || "";
        draft.privateKeyPath = c.privateKeyPath || "";
        draft.privateKeyPassword = c.privateKeyPassword || "";
        draft.peapVersion = c.peapVersion === "0" || c.peapVersion === "1" ? c.peapVersion : "";
        draft.authFlags = c.authFlags || 0;
        draft.opensslCiphers = c.opensslCiphers || "";
        original = {
            "ca": {"path": draft.caCertPath, "pem": draft.caCertPem, "stored": !!storedFiles.ca},
            "clientCert": {"path": draft.clientCertPath, "pem": "", "stored": !!storedFiles.clientCert},
            "privateKey": {"path": draft.privateKeyPath, "pem": "", "stored": !!storedFiles.privateKey}
        };
    }

    function focusIdentity() {
        identityField.forceActiveFocus();
    }

    function storedLabel(target, path) {
        return path || (storedFiles[target] ? I18n.tr("Saved") : "");
    }

    // An empty path puts back what the form was reset with, so a stray edit never drops a stored file.
    function setPath(target, path) {
        const o = path === "" ? original[target] : {
            "path": path,
            "pem": "",
            "stored": false
        };
        if (!!storedFiles[target] !== o.stored)
            storedFiles = Object.assign({}, storedFiles, {
                [target]: o.stored
            });
        if (target === "ca")
            draft.caCertPem = o.pem;
        switch (target) {
        case "ca":
            draft.caCertPath = o.path;
            break;
        case "clientCert":
            draft.clientCertPath = o.path;
            break;
        case "privateKey":
            draft.privateKeyPath = o.path;
            break;
        }
    }

    function toConfig() {
        return CE.enterpriseConfig({
            "eap": draft.eap,
            "phase2": draft.phase2,
            "identity": draft.identity,
            "password": draft.password,
            "savePassword": draft.savePassword,
            "anonymousIdentity": draft.anonymousIdentity,
            "ca": draft.ca,
            "caCertPath": draft.caCertPath,
            "caCertPem": draft.caCertPem,
            "serverDomain": draft.serverDomain,
            "serverDomainSuffix": draft.serverDomainSuffix,
            "clientCertPath": draft.clientCertPath,
            "privateKeyPath": draft.privateKeyPath,
            "privateKeyPassword": draft.privateKeyPassword,
            "peapVersion": draft.peapVersion,
            "authFlags": draft.authFlags,
            "opensslCiphers": draft.opensslCiphers,
            "usernameSuffix": root.usernameSuffix
        });
    }

    width: parent?.width ?? 0
    spacing: SettingsMetrics.groupGap
    // Don't overwrite a reset the host already made while being created.
    Component.onCompleted: if (draft.eap === "") reset()

    QtObject {
        id: draft

        property string eap
        property string phase2
        property string identity
        property string password
        property bool savePassword
        property string anonymousIdentity
        property string ca
        property string caCertPath
        property string caCertPem
        property string serverDomain
        property bool serverDomainSuffix
        property string clientCertPath
        property string privateKeyPath
        property string privateKeyPassword
        property string peapVersion
        property int authFlags
        property string opensslCiphers
    }

    component FormField: DTextField {
        width: parent.width
        outlined: true
    }

    component PathRow: ConnectionPathRow {
        id: pathRow

        property bool mandatory: false
        property string path: ""
        property string label: ""

        browser: certBrowser
        stored: path
        supportingText: value ? "" : label
        isError: root.markInvalid && mandatory && !value && !label
        onAccepted: root.submitRequested()
        commit: t => root.setPath(pathRow.target, t)
    }

    ConnectionChoiceRow {
        text: I18n.tr("Authentication")
        choices: root.methodChoices
        stored: draft.eap
        onPicked: eap => {
            draft.eap = eap;
            draft.phase2 = root.defaultInner(eap);
        }
    }

    ConnectionChoiceRow {
        visible: root.usesInner
        text: I18n.tr("Inner authentication", "802.1X phase 2 authentication method")
        choices: root.innerChoices[draft.eap] || []
        stored: draft.phase2
        onPicked: value => draft.phase2 = value
    }

    SettingsRow {
        body: FormField {
            id: identityField
            leftIconName: root.showIcons ? "person" : ""
            labelText: I18n.tr("Username", "text field label for network, vpn and account forms")
            supportingText: root.usernameSuffix ? "@" + root.usernameSuffix : ""
            isError: (root.markInvalid && !text.trim()) || (root.usernameSuffixRequired && !CE.identityMatchesSuffix(text.trim(), root.usernameSuffix))
            text: draft.identity
            onTextEdited: draft.identity = text
            onAccepted: passwordField.visible ? passwordField.forceActiveFocus() : root.submitRequested()
        }
    }

    SettingsRow {
        visible: draft.savePassword
        body: FormField {
            id: passwordField
            leftIconName: root.showIcons ? "lock" : ""
            showPasswordToggle: true
            echoMode: passwordVisible ? TextInput.Normal : TextInput.Password
            labelText: root.isTls ? I18n.tr("Private Key Password") : I18n.tr("Password")
            isError: root.markInvalid && !root.isTls && !text
            text: root.isTls ? draft.privateKeyPassword : draft.password
            onTextEdited: {
                if (root.isTls)
                    draft.privateKeyPassword = text;
                else
                    draft.password = text;
            }
            onAccepted: anonField.visible ? anonField.forceActiveFocus() : root.submitRequested()
        }
    }

    SettingsToggleRow {
        text: I18n.tr("Save password")
        checked: draft.savePassword
        onToggled: checked => draft.savePassword = checked
    }

    SettingsRow {
        visible: root.usesInner
        body: FormField {
            id: anonField
            leftIconName: root.showIcons ? "person_off" : ""
            labelText: I18n.tr("Anonymous Identity (optional)")
            text: draft.anonymousIdentity
            onTextEdited: draft.anonymousIdentity = text
            onAccepted: root.submitRequested()
        }
    }

    ConnectionChoiceRow {
        visible: root.usesCa
        text: I18n.tr("CA certificate", "network authentication certificate file field")
        choices: root.caChoices
        stored: draft.ca
        onPicked: value => draft.ca = value
    }

    PathRow {
        visible: root.usesCa && draft.ca === "file"
        target: "ca"
        mandatory: true
        leftIconName: root.showIcons ? "verified_user" : ""
        text: I18n.tr("File")
        path: draft.caCertPem ? "" : draft.caCertPath
        label: draft.caCertPem ? root.caDisplayName : root.storedLabel("ca", draft.caCertPath)
    }

    SettingsNoteRow {
        visible: root.usesCa && draft.ca === "none"
        text: I18n.tr("Server is not verified without a CA certificate", "802.1X warning when no CA certificate is set")
        tint: Theme.warning
        tintBackground: Theme.warningHover
    }

    SettingsRow {
        visible: root.usesCa
        body: FormField {
            leftIconName: root.showIcons ? "domain" : ""
            labelText: I18n.tr("Server")
            isError: root.markInvalid && draft.ca === "system" && !text.trim()
            text: draft.serverDomain
            onTextEdited: draft.serverDomain = text
        }
    }

    ConnectionChoiceRow {
        visible: root.usesCa
        text: I18n.tr("Match type", "802.1X server name match, exact or suffix")
        choices: root.matchChoices
        stored: draft.serverDomainSuffix
        onPicked: value => draft.serverDomainSuffix = value
    }

    PathRow {
        visible: root.isTls
        target: "clientCert"
        mandatory: true
        leftIconName: root.showIcons ? "badge" : ""
        text: I18n.tr("Client certificate", "network authentication certificate file field")
        path: draft.clientCertPath
        label: root.storedLabel("clientCert", draft.clientCertPath)
    }

    PathRow {
        visible: root.isTls
        target: "privateKey"
        leftIconName: root.showIcons ? "key" : ""
        text: I18n.tr("Private key", "network authentication key file field")
        path: draft.privateKeyPath
        label: root.storedLabel("privateKey", draft.privateKeyPath)
    }

    SettingsFoldRow {
        visible: root.usesTlsOptions
        title: I18n.tr("Advanced")
        open: root.advancedOpen
        onToggled: root.advancedOpen = !root.advancedOpen
    }

    ConnectionChoiceRow {
        visible: root.advancedOpen && draft.eap === "peap"
        text: I18n.tr("PEAP version", "802.1X advanced option")
        choices: root.peapVersionChoices
        stored: draft.peapVersion
        onPicked: value => draft.peapVersion = value
    }

    // phase1-auth-flags: tls-1-0-enable 0x20, tls-1-1-enable 0x40, tls-1-3-disable 0x10
    SettingsToggleRow {
        visible: root.advancedOpen && root.usesTlsOptions
        text: I18n.tr("Allow TLS 1.0 and 1.1", "802.1X advanced option")
        checked: (draft.authFlags & 0x60) === 0x60
        onToggled: checked => draft.authFlags = CE.withFlags(draft.authFlags, 0x60, checked)
    }

    SettingsToggleRow {
        visible: root.advancedOpen && root.usesTlsOptions
        text: I18n.tr("Disable TLS 1.3", "802.1X advanced option")
        checked: (draft.authFlags & 0x10) !== 0
        onToggled: checked => draft.authFlags = CE.withFlags(draft.authFlags, 0x10, checked)
    }

    SettingsRow {
        visible: root.advancedOpen && root.usesTlsOptions
        body: FormField {
            leftIconName: root.showIcons ? "tune" : ""
            labelText: I18n.tr("OpenSSL ciphers", "802.1X advanced option")
            text: draft.opensslCiphers
            onTextEdited: draft.opensslCiphers = text
        }
    }

    ConnectionCertBrowser {
        id: certBrowser
        surface: root.surfaceBrowser
        onPicked: (key, path) => root.setPath(key, path)
    }
}
