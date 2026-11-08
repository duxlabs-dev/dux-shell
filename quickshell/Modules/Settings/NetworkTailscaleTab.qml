pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets
import "../../Common/ConnectionEditor.js" as ConnectionEditor

Item {
    id: networkTailscaleTab

    property var parentModal: null

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property string statusText: TailscaleService.connected ? TailscaleService.tailnetName : I18n.tr("Not connected", "Tailscale connection switch description")
    property bool granting: false
    property string suggestedId: ""

    readonly property bool queryable: TailscaleService.canWritePrefs
    readonly property bool profilesLoaded: TailscaleService.profilesLoaded
    readonly property bool canOperate: TailscaleService.canOperate
    readonly property bool writable: queryable && canOperate && backendState !== "Unreachable"
    readonly property bool tsConnected: TailscaleService.connected
    readonly property string backendState: TailscaleService.backendState
    readonly property string prefOperator: TailscaleService.prefs.operatorUser ?? ""
    readonly property string prefHostname: TailscaleService.prefs.hostname ?? ""
    readonly property string prefRoutes: (TailscaleService.prefs.advertiseRoutes ?? []).join(", ")
    readonly property string noneLabel: I18n.tr("None", "Tailscale exit node: none selected")
    readonly property string operatorCommand: "sudo tailscale set --operator=$USER"

    readonly property var exitNodeChoices: {
        const choices = [
            {
                "label": noneLabel,
                "id": ""
            }
        ];
        for (const p of TailscaleService.exitNodeOptions) {
            choices.push({
                "label": p.id === suggestedId ? I18n.tr("%1 (recommended)", "suggested Tailscale exit node").arg(p.hostname) : p.hostname,
                "id": p.id
            });
        }
        return choices;
    }

    readonly property bool showAccounts: TailscaleService.available && backendState !== "Unreachable" && canOperate
    property string busyId: ""

    onQueryableChanged: {
        Qt.callLater(TailscaleService.loadProfiles);
        Qt.callLater(loadSuggestion);
    }
    onBackendStateChanged: Qt.callLater(TailscaleService.loadProfiles)
    onPrefOperatorChanged: Qt.callLater(TailscaleService.loadProfiles)
    onTsConnectedChanged: Qt.callLater(loadSuggestion)
    onPrefHostnameChanged: hostnameField.value = prefHostname
    onPrefRoutesChanged: routesField.value = prefRoutes
    Component.onCompleted: {
        hostnameField.value = prefHostname;
        routesField.value = prefRoutes;
        TailscaleService.loadProfiles(true);
        loadSuggestion();
    }

    function loadSuggestion() {
        if (!tsConnected) {
            suggestedId = "";
            return;
        }
        TailscaleService.suggestExitNode(response => {
            suggestedId = response?.result?.id ?? "";
        });
    }

    function grant() {
        granting = true;
        const sent = TailscaleService.grantOperator(response => {
            granting = false;
            if (response.error)
                return;
            TailscaleService.applyProfiles(response.result);
            loadSuggestion();
        });
        if (!sent)
            granting = false;
    }

    function runOn(id, action) {
        if (busyId !== "")
            return;
        busyId = id;
        const sent = action(() => {
            TailscaleService.loadProfiles();
            busyId = "";
        });
        if (!sent)
            busyId = "";
    }

    function parseRoutes(text) {
        return String(text ?? "").split(/[\s,]+/).filter(t => t.length > 0);
    }

    function routesValid(text) {
        return parseRoutes(text).every(r => ConnectionEditor.isValidCidr(r, r.includes(":") ? 6 : 4));
    }

    function copyText(text) {
        Quickshell.execDetached([Proc.dmsBin, "cl", "copy", text]);
        ToastService.showInfo(I18n.tr("Copied to clipboard"));
    }

    Ref {
        service: TailscaleService
    }

    component PeerRow: SettingsRow {
        id: peerRow

        required property var peer
        readonly property bool isSelf: (peer?.id ?? "") !== "" && peer.id === TailscaleService.selfNode?.id

        signal copyRequested(string text)

        title: peer?.hostname ?? ""
        subtitle: peer?.tailscaleIp ?? ""
        trailingBadge: isSelf ? I18n.tr("This device") : ""
        trailingBadgeColor: Theme.primary
        Accessible.description: peer?.online ? subtitle + " · " + I18n.tr("Online") : subtitle

        leading: Rectangle {
            width: Theme.spacingS
            height: Theme.spacingS
            radius: Theme.fullRadius(width, height)
            color: peerRow.peer?.online ? Theme.success : Theme.surfaceVariantText
        }

        DActionButton {
            visible: (peerRow.peer?.tailscaleIp ?? "") !== ""
            buttonSize: Theme.iconButtonSize
            iconName: "content_copy"
            iconColor: Theme.surfaceText
            tooltipText: peerRow.peer?.tailscaleIp ?? ""
            Accessible.name: I18n.tr("Copy") + " " + tooltipText
            onClicked: peerRow.copyRequested(peerRow.peer.tailscaleIp)
        }

        DActionButton {
            visible: (peerRow.peer?.dnsName ?? "") !== ""
            buttonSize: Theme.iconButtonSize
            iconName: "file_copy"
            iconColor: Theme.surfaceText
            tooltipText: peerRow.peer?.dnsName ?? ""
            Accessible.name: I18n.tr("Copy") + " " + tooltipText
            onClicked: peerRow.copyRequested(peerRow.peer.dnsName)
        }
    }

    SettingsPage {
        SettingsCard {
            title: I18n.tr("Tailscale", "Tailscale mesh VPN widget title")
            iconName: "hub"
            settingKey: "networkTailscale"
            tags: ["tailscale", "vpn", "tailnet", "exit node", "magicdns", "ssh", "subnet", "account", "login"]

            SettingsRow {
                visible: !TailscaleService.available || networkTailscaleTab.backendState === "Unreachable"
                subtitle: I18n.tr("Tailscale not available", "Warning when Tailscale service is not running")
            }

            SettingsNoteRow {
                visible: TailscaleService.available && networkTailscaleTab.profilesLoaded && !networkTailscaleTab.canOperate
                text: I18n.tr("Operator permission needed", "Tailscale settings note, followed by a grant button and a terminal command")
            }

            SettingsRow {
                visible: TailscaleService.available && networkTailscaleTab.profilesLoaded && !networkTailscaleTab.canOperate
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width - copyCommandButton.width - grantButton.width - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: networkTailscaleTab.operatorCommand
                        isMonospace: true
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        wrapMode: Text.Wrap
                    }

                    DActionButton {
                        id: copyCommandButton
                        anchors.verticalCenter: parent.verticalCenter
                        buttonSize: Theme.iconButtonSize
                        iconName: "content_copy"
                        iconColor: Theme.surfaceText
                        tooltipText: I18n.tr("Copy")
                        Accessible.name: I18n.tr("Copy")
                        onClicked: networkTailscaleTab.copyText(networkTailscaleTab.operatorCommand)
                    }

                    DButton {
                        id: grantButton
                        anchors.verticalCenter: parent.verticalCenter
                        visible: TailscaleService.grantAvailable
                        width: visible ? implicitWidth : 0
                        text: I18n.tr("Grant permission", "Tailscale: button to grant operator permission")
                        iconName: "admin_panel_settings"
                        busy: networkTailscaleTab.granting
                        enabled: !networkTailscaleTab.granting
                        onClicked: networkTailscaleTab.grant()
                    }
                }
            }

            SettingsToggleRow {
                visible: TailscaleService.available
                enabled: networkTailscaleTab.writable && networkTailscaleTab.backendState !== "NeedsLogin"
                text: I18n.tr("Status", "Tailscale connection switch title")
                description: networkTailscaleTab.statusText
                checked: TailscaleService.connected
                onToggled: checked => {
                    if (checked)
                        TailscaleService.connectTailscale(null);
                    else
                        TailscaleService.disconnectTailscale(null);
                }
            }

            PeerRow {
                visible: TailscaleService.available && (TailscaleService.selfNode?.id ?? "") !== ""
                peer: TailscaleService.selfNode
                onCopyRequested: text => networkTailscaleTab.copyText(text)
            }
        }

        SettingsCard {
            visible: networkTailscaleTab.showAccounts
            title: I18n.tr("Accounts")

            Repeater {
                model: ScriptModel {
                    objectProp: "id"
                    values: TailscaleService.profiles
                }

                SettingsRow {
                    id: accountRow

                    required property var modelData
                    readonly property string profileId: modelData.id
                    readonly property bool isCurrent: profileId === TailscaleService.currentProfile

                    title: modelData.name
                    subtitle: modelData.tailnet ?? ""
                    iconName: isCurrent ? "radio_button_checked" : "radio_button_unchecked"
                    iconColor: isCurrent ? Theme.primary : Theme.surfaceVariantText
                    clickable: true
                    enabled: networkTailscaleTab.writable
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: isCurrent
                    onClicked: {
                        if (!isCurrent)
                            networkTailscaleTab.runOn(profileId, done => TailscaleService.switchProfile(profileId, done));
                    }

                    DSpinner {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: networkTailscaleTab.busyId === accountRow.profileId
                        size: Theme.iconSizeMedium
                        strokeWidth: 2
                    }

                    DActionButton {
                        visible: accountRow.isCurrent && networkTailscaleTab.backendState !== "NeedsLogin"
                        buttonSize: Theme.iconButtonSize
                        iconName: "logout"
                        iconColor: Theme.surfaceText
                        tooltipText: I18n.tr("Log out")
                        Accessible.name: tooltipText
                        onClicked: networkTailscaleTab.runOn(accountRow.profileId, done => TailscaleService.logout(done))
                    }

                    SettingsDeleteButton {
                        visible: !accountRow.isCurrent
                        buttonSize: Theme.iconButtonSize
                        iconName: confirming ? "warning" : "person_remove"
                        tooltipText: confirming ? I18n.tr("Confirm") : I18n.tr("Remove")
                        Accessible.name: tooltipText
                        onDeleteRequested: networkTailscaleTab.runOn(accountRow.profileId, done => TailscaleService.removeProfile(accountRow.profileId, done))
                    }
                }
            }

            SettingsNavRow {
                iconName: "person_add"
                title: I18n.tr("Add account", "Tailscale: add another account")
                enabled: networkTailscaleTab.writable && networkTailscaleTab.busyId === ""
                onClicked: keyboard => networkTailscaleTab.parentModal?.navigateTo("network_tailscale_add", keyboard)
            }
        }

        SettingsCard {
            visible: TailscaleService.available
            title: I18n.tr("Exit node")

            SettingsDropdownRow {
                id: exitNodeRow
                enabled: networkTailscaleTab.writable
                text: I18n.tr("Exit node")
                options: networkTailscaleTab.exitNodeChoices.map(c => c.label)
                currentValue: {
                    const current = TailscaleService.currentExitNode;
                    if (!current)
                        return networkTailscaleTab.noneLabel;
                    return networkTailscaleTab.exitNodeChoices.find(c => c.id === current.id)?.label ?? current.hostname;
                }
                onValueChanged: value => {
                    const choice = networkTailscaleTab.exitNodeChoices.find(c => c.label === value);
                    if (!choice)
                        return;
                    const resyncOnError = response => {
                        if (response.error)
                            exitNodeRow.resync();
                    };
                    if (choice.id === "")
                        TailscaleService.clearExitNode(resyncOnError);
                    else
                        TailscaleService.setExitNode(choice.id, resyncOnError);
                }
            }

            SettingsToggleRow {
                enabled: networkTailscaleTab.writable
                text: I18n.tr("Allow LAN access")
                description: I18n.tr("Reach local network devices while using an exit node")
                checked: TailscaleService.exitNodeAllowLanAccess
                onToggled: value => TailscaleService.setAllowLanAccess(value, null)
            }

            SettingsToggleRow {
                enabled: networkTailscaleTab.writable
                text: I18n.tr("Run as exit node", "Tailscale setting")
                checked: TailscaleService.prefs.advertiseExitNode === true
                onToggled: value => TailscaleService.setPrefs({
                        "advertiseExitNode": value
                    })
            }
        }

        SettingsCard {
            visible: TailscaleService.available
            title: I18n.tr("Settings")

            SettingsToggleRow {
                enabled: networkTailscaleTab.writable
                text: I18n.tr("Use Tailscale subnets", "Tailscale setting")
                checked: TailscaleService.prefs.acceptRoutes === true
                onToggled: value => TailscaleService.setPrefs({
                        "acceptRoutes": value
                    })
            }

            SettingsToggleRow {
                enabled: networkTailscaleTab.writable
                text: I18n.tr("Use Tailscale DNS settings", "Tailscale setting")
                checked: TailscaleService.prefs.acceptDns === true
                onToggled: value => TailscaleService.setPrefs({
                        "acceptDns": value
                    })
            }

            SettingsToggleRow {
                enabled: networkTailscaleTab.writable
                text: I18n.tr("Allow incoming connections", "Tailscale setting")
                checked: TailscaleService.prefs.shieldsUp !== true
                onToggled: value => TailscaleService.setPrefs({
                        "shieldsUp": !value
                    })
            }

            SettingsToggleRow {
                enabled: networkTailscaleTab.writable
                text: I18n.tr("Run Tailscale SSH server", "Tailscale setting")
                checked: TailscaleService.prefs.runSsh === true
                onToggled: value => TailscaleService.setPrefs({
                        "runSsh": value
                    })
            }

            SettingsTextFieldRow {
                id: hostnameField
                enabled: networkTailscaleTab.writable
                text: I18n.tr("Hostname")
                onEditingFinished: value => {
                    const hostname = value.trim();
                    if (hostname !== networkTailscaleTab.prefHostname)
                        TailscaleService.setPrefs({
                            "hostname": hostname
                        });
                }
            }

            SettingsTextFieldRow {
                id: routesField
                enabled: networkTailscaleTab.writable
                text: I18n.tr("Subnet routes", "routes this device advertises to the tailnet")
                placeholderText: "192.168.1.0/24, fd00::/64"
                isError: !networkTailscaleTab.routesValid(value)
                onEditingFinished: value => {
                    if (!networkTailscaleTab.routesValid(value))
                        return;
                    const routes = networkTailscaleTab.parseRoutes(value);
                    if (routes.join(", ") !== networkTailscaleTab.prefRoutes)
                        TailscaleService.setPrefs({
                            "advertiseRoutes": routes
                        });
                }
            }
        }

        SettingsCard {
            visible: TailscaleService.available
            title: I18n.tr("Devices")

            SettingsRow {
                visible: TailscaleService.allPeersList.length === 0
                subtitle: I18n.tr("No peers found")
            }

            Repeater {
                model: TailscaleService.allPeersList

                PeerRow {
                    required property var modelData

                    peer: modelData
                    onCopyRequested: text => networkTailscaleTab.copyText(text)
                }
            }
        }

        SettingsFabBar {
            shown: loginFab.visible

            DFab {
                id: loginFab
                visible: networkTailscaleTab.showAccounts && networkTailscaleTab.backendState === "NeedsLogin" && TailscaleService.currentProfile !== ""
                text: I18n.tr("Log in", "Tailscale: start login button")
                iconName: "login"
                enabled: networkTailscaleTab.writable
                onClicked: TailscaleService.login()
            }
        }
    }
}
