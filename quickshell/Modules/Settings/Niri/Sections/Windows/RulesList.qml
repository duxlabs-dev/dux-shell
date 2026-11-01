pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Common
import "../../../../../Common/WindowRuleSize.js" as WindowRuleSize
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

// The rows of the old Window rules tab, written through the same `dms config windowrules` provider.
Column {
    id: root

    property var rules: []
    property var externalRules: []
    property bool savingOrder: false
    readonly property var editorLoader: PopoutService.windowRuleModalLoader

    readonly property var labels: ({
            "opacity": I18n.tr("Opacity"),
            "openFloating": I18n.tr("Float"),
            "openMaximized": I18n.tr("Maximize"),
            "openMaximizedToEdges": I18n.tr("Max edges", "window rule action, open maximized to screen edges"),
            "openFullscreen": I18n.tr("Fullscreen"),
            "openFocused": I18n.tr("Focus"),
            "openOnOutput": I18n.tr("Output"),
            "openOnWorkspace": I18n.tr("Workspace"),
            "defaultColumnWidth": I18n.tr("Width"),
            "defaultWindowHeight": I18n.tr("Height"),
            "variableRefreshRate": I18n.tr("VRR", "window rule action, variable refresh rate"),
            "blockOutFrom": I18n.tr("Block out"),
            "defaultColumnDisplay": I18n.tr("Display"),
            "scrollFactor": I18n.tr("Scroll"),
            "cornerRadius": I18n.tr("Radius"),
            "clipToGeometry": I18n.tr("Clip", "verb, short window rule property label for clip to geometry"),
            "tiledState": I18n.tr("Tiled", "adjective, short window rule property label for tiled state"),
            "minWidth": I18n.tr("Min W"),
            "maxWidth": I18n.tr("Max W"),
            "minHeight": I18n.tr("Min H"),
            "maxHeight": I18n.tr("Max H"),
            "drawBorderWithBackground": I18n.tr("Border w/ bg"),
            "backgroundBlur": I18n.tr("Blur"),
            "backgroundXray": I18n.tr("X-Ray"),
            "backgroundNoise": I18n.tr("Noise"),
            "backgroundSaturation": I18n.tr("Saturation"),
            "defaultFloatingX": I18n.tr("Float X"),
            "defaultFloatingY": I18n.tr("Float Y"),
            "defaultFloatingRelativeTo": I18n.tr("Float anchor"),
            "borderColor": I18n.tr("Border color"),
            "focusRingColor": I18n.tr("Focus ring color"),
            "focusRingOff": I18n.tr("Focus ring off"),
            "borderOff": I18n.tr("Border off"),
            "appId": I18n.tr("App ID"),
            "title": I18n.tr("Title", "noun, window title match field, also name field label"),
            "isFloating": I18n.tr("Floating"),
            "isActive": I18n.tr("Active", "active state label"),
            "isFocused": I18n.tr("Focused"),
            "isActiveInColumn": I18n.tr("Active in column"),
            "isWindowCastTarget": I18n.tr("Cast target"),
            "isUrgent": I18n.tr("Urgent"),
            "atStartup": I18n.tr("At startup")
        })

    function chips(obj) {
        const a = obj || {};
        return Object.keys(a).filter(k => a[k] !== undefined && a[k] !== null && a[k] !== "").map(k => {
            const label = labels[k] || k;
            if (typeof a[k] === "boolean")
                return a[k] ? label : label + ": " + I18n.tr("Off");
            if (k === "defaultColumnWidth" || k === "defaultWindowHeight")
                return label + ": " + WindowRuleSize.label(a[k]);
            return label + ": " + a[k];
        });
    }

    function matchesOf(rule) {
        return rule.matches?.length > 0 ? rule.matches : [rule.matchCriteria || {}];
    }

    function subtitleOf(rule) {
        const c = rule.matchCriteria || {};
        const parts = [];
        if (c.appId)
            parts.push(c.appId);
        if (c.title)
            parts.push(I18n.tr("title: %1", "window rule match on the window title").arg(c.title));
        const base = parts.length > 0 ? parts.join(" · ") : I18n.tr("No match criteria");
        const more = matchesOf(rule).length - 1;
        return more > 0 ? I18n.tr("%1 (+%2 more)").arg(base).arg(more) : base;
    }

    function reload() {
        include.checking = true;
        Proc.runCommand("niri-page-windowrules", [Proc.dmsBin, "config", "windowrules", "list", "niri"], (output, exitCode) => {
            include.checking = false;
            if (exitCode !== 0) {
                rules = [];
                externalRules = [];
                return;
            }
            try {
                const result = JSON.parse(output.trim());
                const all = result.rules || [];
                CompositorService.syncDmsWindowFloatingRule(all);
                rules = all.filter(r => (r.source || "").includes("dms/windowrules") && r.id !== CompositorService.dmsOpaqueRuleId);
                externalRules = all.filter(r => !(r.source || "").includes("dms/windowrules"));
                include.applyStatus(result.dmsStatus);
            } catch (e) {
                rules = [];
                externalRules = [];
            }
        });
    }

    function afterWrite(exitCode) {
        if (exitCode !== 0)
            return;
        CompositorService.reloadAfterWindowRuleWrite();
        reload();
    }

    function addRule(rule) {
        Proc.runCommand("niri-page-add-windowrule", [Proc.dmsBin, "config", "windowrules", "add", "niri", JSON.stringify(rule)], (output, exitCode) => {
            if (exitCode !== 0)
                ToastService.showError(I18n.tr("Could not save the rule"), output);
            root.afterWrite(exitCode);
        });
    }

    function remove(id) {
        Proc.runCommand("niri-page-remove-windowrule", [Proc.dmsBin, "config", "windowrules", "remove", "niri", id], (output, exitCode) => root.afterWrite(exitCode));
    }

    function reorder(indices) {
        if (savingOrder)
            return;
        const previous = rules;
        const reordered = indices.map(i => previous[i]);
        savingOrder = true;
        rules = reordered;
        Proc.runCommand("niri-page-reorder-windowrules", [Proc.dmsBin, "config", "windowrules", "reorder", "niri", JSON.stringify(reordered.map(r => r.id))], (output, exitCode) => {
            root.savingOrder = false;
            if (exitCode !== 0) {
                root.rules = previous;
                return;
            }
            root.afterWrite(exitCode);
        });
    }

    // mode: "new" (payload: {appId, title} or null), "edit" or "copy" (payload: a rule)
    function openEditor(mode, payload) {
        if (!editorLoader)
            return;
        editorLoader.active = true;
        const present = () => {
            const editor = editorLoader.item;
            if (!editor)
                return;
            if (mode === "edit")
                editor.showEdit(payload);
            else if (mode === "copy")
                editor.showCopy(payload);
            else
                editor.show(payload);
        };
        if (editorLoader.item)
            present();
        else
            Qt.callLater(present);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingS

    Component.onCompleted: reload()

    ConfigInclude {
        id: include
        includeKind: "windowrules"
        autoCheck: false
        onFixed: root.reload()
    }

    // Every writer reloads the list through this file: the rule editor, the mini desktop menu, and niri does not reload a file it does not include.
    // No Connections on the editor: it belongs to a shell LazyLoader, and this page is built asynchronously.
    FileView {
        path: include.configDir() + "/niri/dms/windowrules.kdl"
        watchChanges: true
        printErrors: false
        onFileChanged: root.reload()
    }

    IncludeSetupBanner {
        include: include
    }

    StyledText {
        width: parent.width
        visible: root.rules.length === 0
        text: I18n.tr("No window rules configured")
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    SettingsReorderList {
        id: list

        model: root.rules
        visible: count > 0
        enabled: !root.savingOrder
        onReordered: indices => root.reorder(indices)

        delegate: SettingsReorderRow {
            id: row

            required property var modelData

            reorderList: list
            title: modelData.name || modelData.matchCriteria?.appId || modelData.matchCriteria?.title || I18n.tr("Unnamed rule")
            subtitle: root.subtitleOf(modelData)

            DActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "edit"
                Accessible.name: I18n.tr("Edit rule")
                onClicked: root.openEditor("edit", row.modelData)
            }

            DActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "delete"
                iconColor: Theme.error
                Accessible.name: I18n.tr("Delete rule")
                onClicked: root.remove(row.modelData.id)
            }

            body: Flow {
                width: parent.width
                spacing: Theme.spacingXS
                visible: chipRepeater.count > 0

                Repeater {
                    id: chipRepeater
                    model: root.chips(row.modelData.actions)

                    delegate: DBadge {
                        required property string modelData
                        maximumWidth: parent?.width ?? 0
                        text: modelData
                        color: Theme.primaryContainer
                        textColor: Theme.onPrimaryContainer
                        tooltipText: truncated ? modelData : null
                    }
                }
            }
        }
    }

    RulesExternal {
        list: root
    }
}
