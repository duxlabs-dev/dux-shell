pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import "../../../../../Common/niri/sections/rules.js" as Rules

NiriCard {
    id: root

    property var picked: null
    property bool useAppId: true
    property bool useTitle: false
    property string workspace: ""
    property bool floating: false
    property bool blockOut: true
    readonly property var criteria: picked ? Rules.criteria(picked, useAppId, useTitle) : ({})
    readonly property int matchCount: picked ? Rules.matchCount(NiriService.windows, criteria) : 0
    readonly property var workspaceNames: NiriService.allWorkspaces.map(ws => ws.name || "").filter((name, i, all) => name !== "" && all.indexOf(name) === i)

    function startPick() {
        picked = null;
        pickProc.running = true;
    }

    function fill(win) {
        if (!win)
            return;
        useAppId = win.appId !== "";
        useTitle = win.appId === "";
        workspace = "";
        floating = false;
        blockOut = true;
        picked = win;
    }

    function save() {
        rulesList.addRule(Rules.buildRule(picked, {
            useAppId: useAppId,
            useTitle: useTitle,
            workspace: workspace,
            floating: floating,
            blockOut: blockOut
        }));
        picked = null;
    }

    icon: "rule"
    title: I18n.tr("Window rules", "niri page card")
    aside: rulesList.rules.length === 1 ? I18n.tr("1 rule", "niri page window rules count") : I18n.tr("%1 rules", "niri page window rules count").arg(rulesList.rules.length)

    // Lives only while the user is picking: niri answers once a window is clicked or Escape is pressed.
    Process {
        id: pickProc
        command: ["niri", "msg", "--json", "pick-window"]
        stdout: StdioCollector {
            onStreamFinished: root.fill(Rules.parsePicked(text))
        }
    }

    NiriRow {
        icon: "ads_click"
        title: I18n.tr("Rule from a window")
        tip: I18n.tr("Click any open window, DMS fills in its app-id and title")
        kdlKey: "niri msg pick-window"

        DButton {
            text: I18n.tr("Pick a window")
            iconName: "ads_click"
            enabled: !pickProc.running
            backgroundColor: Theme.primary
            textColor: Theme.onPrimary
            onClicked: root.startPick()
        }
    }

    // No Cancel button: while niri picks, every click goes to the pick, Escape is the only way out.
    RulesNote {
        visible: pickProc.running
        icon: "ads_click"
        text: I18n.tr("Click a window, or press Esc to cancel")
        border.width: Theme.outlineWidthFocused
        border.color: Theme.primary
    }

    Column {
        width: parent.width
        visible: root.picked !== null
        spacing: Theme.spacingXXS

        RulesNote {
            icon: "select_window"
            text: root.picked ? root.picked.appId + "  ·  " + root.picked.title : ""
            mono: true
        }

        NiriRow {
            icon: "apps"
            title: I18n.tr("App ID")
            tip: root.criteria.appId || ""
            kdlKey: "match app-id"

            DToggle {
                checked: root.useAppId
                enabled: root.picked?.appId !== ""
                Accessible.name: I18n.tr("App ID")
                onToggled: checked => root.useAppId = checked
            }
        }

        NiriRow {
            icon: "title"
            title: I18n.tr("Title", "noun, window title match field, also name field label")
            tip: root.criteria.title || ""
            kdlKey: "match title"

            DToggle {
                checked: root.useTitle
                Accessible.name: I18n.tr("Title", "noun, window title match field, also name field label")
                onToggled: checked => root.useTitle = checked
            }
        }

        NiriRow {
            icon: "space_dashboard"
            title: I18n.tr("Open on")
            tip: I18n.tr("Only named workspaces can be chosen")
            kdlKey: "open-on-workspace"

            DDropdown {
                readonly property string anyText: I18n.tr("Any workspace")
                dropdownWidth: Theme.iconButtonSize * 5
                compactMode: true
                options: [anyText].concat(root.workspaceNames)
                currentValue: root.workspace || anyText
                onValueChanged: value => root.workspace = value === anyText ? "" : value
            }
        }

        NiriRow {
            icon: "picture_in_picture"
            title: I18n.tr("Floating")
            kdlKey: "open-floating"

            DToggle {
                checked: root.floating
                Accessible.name: I18n.tr("Open floating")
                onToggled: checked => root.floating = checked
            }
        }

        NiriRow {
            icon: "visibility_off"
            title: I18n.tr("Hide when sharing")
            tip: I18n.tr("Shown as a black box in screencasts")
            kdlKey: "block-out-from \"screencast\""

            DToggle {
                checked: root.blockOut
                Accessible.name: I18n.tr("Hide while sharing the screen")
                onToggled: checked => root.blockOut = checked
            }
        }

        RulesNote {
            icon: root.matchCount < 0 ? "warning" : "check_circle"
            tone: root.matchCount < 0 ? "warn" : "ok"
            text: root.matchCount < 0 ? I18n.tr("No match: every window would get it.") : root.matchCount === 1 ? I18n.tr("Matches 1 open window", "niri page window rule tester") : I18n.tr("Matches %1 open windows", "niri page window rule tester, %1 is a count").arg(root.matchCount)
        }

        Flow {
            width: parent.width
            topPadding: Theme.spacingS
            spacing: Theme.spacingS

            DButton {
                text: I18n.tr("Create rule")
                enabled: root.matchCount >= 0
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                onClicked: root.save()
            }

            DButton {
                text: I18n.tr("More options")
                backgroundColor: "transparent"
                textColor: Theme.surfaceText
                iconName: "tune"
                onClicked: {
                    rulesList.openEditor("new", root.picked);
                    root.picked = null;
                }
            }

            DButton {
                text: I18n.tr("Cancel")
                backgroundColor: "transparent"
                textColor: Theme.surfaceText
                onClicked: root.picked = null
            }
        }
    }

    NiriRow {
        visible: NiriPageService.expert
        icon: "web_asset"
        title: I18n.tr("Open floating")
        tip: I18n.tr("Adds a compositor window rule so DMS windows such as Settings open floating", "theme floating windows section, open floating toggle description")
        kdlKey: "window-rule open-floating"

        DToggle {
            checked: CompositorService.dmsWindowFloatingActive
            Accessible.name: I18n.tr("Open floating")
            onToggled: checked => CompositorService.setDmsWindowFloatingRule(checked, () => rulesList.reload())
        }
    }

    RulesList {
        id: rulesList
        topPadding: Theme.spacingS
    }
}
