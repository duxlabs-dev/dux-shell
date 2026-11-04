pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.Niri.Components
import "../../../../../Common/niri/sections/session.js" as Session

NiriCard {
    id: root

    readonly property var apps: NiriPageService.get("session.apps") ?? []
    readonly property bool on: NiriPageService.get("session.on") === true
    readonly property var groups: Session.layout(apps, NiriService.allWorkspaces)
    readonly property var runningApps: [...new Set(NiriService.windows.map(w => w.app_id).filter(id => id && !apps.some(a => a.appId === id)))].sort()
    readonly property int columns: Math.max(1, Math.floor((width - Theme.spacingL * 2 + Theme.spacingM) / (Theme.iconButtonSize * 5 + Theme.spacingM)))

    // Desktop field codes such as %U would reach the program as literal arguments.
    function commandOf(appId) {
        const entry = DesktopEntries.heuristicLookup(Paths.moddedAppId(appId));
        const command = (entry?.command ?? []).filter(arg => !/^%[a-zA-Z]$/.test(arg));
        return command.length ? command : [appId];
    }

    function add(appId, workspace, output) {
        NiriPageService.set("session.apps", apps.concat([{
                "appId": appId,
                "command": commandOf(appId),
                "workspace": workspace,
                "output": output
            }]));
    }

    function remove(appId) {
        NiriPageService.set("session.apps", apps.filter(a => a.appId !== appId));
    }

    icon: "restore_page"
    title: I18n.tr("Session", "niri page card")
    aside: I18n.tr("Next login", "niri page: the change applies at the next login")

    NiriRow {
        settingKey: "session.on"
        icon: "restore_page"
        title: I18n.tr("Reopen programs at login", "niri page session")
        tip: I18n.tr("Each on its workspace and screen", "niri page session")
        kdlKey: "spawn-at-startup + open-on-workspace + open-on-output"
        tryValue: undefined
    }

    Flow {
        width: parent.width
        spacing: Theme.spacingM
        bottomPadding: Theme.spacingS
        opacity: root.on ? 1 : SettingsMetrics.disabledOpacity

        Repeater {
            model: root.groups

            SessionOutput {
                required property var modelData

                width: (root.width - Theme.spacingL * 2 - Theme.spacingM * (root.columns - 1)) / root.columns
                output: modelData.output
                rows: modelData.rows
                choices: root.runningApps
                onAdded: (appId, workspace) => root.add(appId, workspace, modelData.output)
                onRemoved: appId => root.remove(appId)
            }
        }
    }

    StyledText {
        visible: root.apps.length === 0
        topPadding: Theme.spacingS
        text: I18n.tr("Nothing in the session yet.", "niri page session")
        color: Theme.surfaceVariantText
    }

    // Actions on the right, like the Motion pane: the count takes the rest of the width.
    Item {
        width: parent.width
        height: Math.max(countText.height, actions.height)

        StyledText {
            id: countText
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - actions.width - Theme.spacingS
            elide: Text.ElideRight
            text: root.apps.length === 1 ? I18n.tr("1 program", "niri page session count") : I18n.tr("%1 programs", "niri page session count, %1 is a number").arg(root.apps.length)
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DButton {
                text: I18n.tr("Save open windows", "niri page session")
                iconName: "save"
                onClicked: NiriPageService.set("session.apps", Session.fromWindows(NiriService.windows, NiriService.workspaces, root.commandOf))
            }

            DButton {
                text: I18n.tr("Clear", "niri page session")
                enabled: root.apps.length > 0
                backgroundColor: "transparent"
                textColor: Theme.primary
                onClicked: NiriPageService.set("session.apps", [])
            }
        }
    }

    // Startup apps have one home, DMS Autostart: this row only points there.
    NiriRow {
        icon: "line_start"
        title: I18n.tr("Apps started at login", "niri page startup")
        tip: I18n.tr("Added and removed in Applications, Autostart apps", "niri page startup")

        DButton {
            text: I18n.tr("Autostart", "niri page startup: opens the DMS Autostart apps page")
            iconName: "open_in_new"
            onClicked: PopoutService.openSettingsWithTab("autostart")
        }
    }
}
