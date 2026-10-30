pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import "../../Common/ConfigIncludeResolve.js" as ConfigIncludeResolve
import "../../Common/WindowRuleSize.js" as WindowRuleSize
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var parentModal: null
    property bool pageActive: true
    property bool componentReady: false
    readonly property bool readOnly: windowRulesInclude.readOnly
    property bool savingRuleOrder: false
    property var windowRules: []
    property var externalRules: []
    property var activeWindows: getActiveWindows()
    property string expandedExternalId: ""
    readonly property string dmsRulesFileName: "dms/" + (ConfigIncludeResolve.includeSpec("windowrules", CompositorService.compositor)?.fragmentNames[0] ?? "windowrules.lua")

    Component.onDestruction: SettingsSearchService.unregisterCard("windowRules")

    ConfigInclude {
        id: windowRulesInclude
        includeKind: "windowrules"
        autoCheck: false
        onFixed: {
            if (CompositorService.isMango)
                MangoService.reloadConfig();
            root.loadWindowRules();
        }
    }

    onPageActiveChanged: {
        if (componentReady && pageActive)
            loadWindowRules();
    }

    readonly property var matchLabels: ({
            "appId": I18n.tr("App ID"),
            "title": I18n.tr("Title", "noun, window title match field, also name field label"),
            "isFloating": I18n.tr("Floating"),
            "isActive": I18n.tr("Active", "active state label"),
            "isFocused": I18n.tr("Focused"),
            "isActiveInColumn": I18n.tr("Active in column"),
            "isWindowCastTarget": I18n.tr("Cast target"),
            "isUrgent": I18n.tr("Urgent"),
            "atStartup": I18n.tr("At startup"),
            "xwayland": "XWayland",
            "fullscreen": I18n.tr("Fullscreen"),
            "pinned": I18n.tr("Pinned"),
            "initialised": I18n.tr("Initialised"),
            "initialClass": I18n.tr("Initial class"),
            "initialTitle": I18n.tr("Initial title"),
            "tag": I18n.tr("Tag"),
            "xdgTag": I18n.tr("XDG tag"),
            "workspace": I18n.tr("Workspace"),
            "content": I18n.tr("Content"),
            "group": I18n.tr("Group"),
            "modal": I18n.tr("Modal"),
            "fullscreenStateInternal": I18n.tr("Fullscreen state"),
            "fullscreenStateClient": I18n.tr("Client fullscreen state")
        })

    function matchesOf(rule) {
        const m = rule.matches;
        if (m && m.length > 0)
            return m;
        return [rule.matchCriteria || {}];
    }

    function actionChips(actions) {
        const a = actions || {};
        return Object.keys(a).filter(k => a[k] !== undefined && a[k] !== null && a[k] !== "").map(k => {
            const label = root.actionLabels[k] || k;
            if (typeof a[k] === "boolean")
                return a[k] ? label : label + ": " + I18n.tr("Off");
            if (k === "defaultColumnWidth" || k === "defaultWindowHeight")
                return label + ": " + WindowRuleSize.label(a[k]);
            return label + ": " + a[k];
        });
    }

    function formatCriteria(obj, labels) {
        let out = [];
        const keys = Object.keys(obj || {});
        for (let i = 0; i < keys.length; i++) {
            const k = keys[i];
            const v = obj[k];
            if (v === undefined || v === null || v === "")
                continue;
            const label = labels[k] || k;
            if (typeof v === "boolean")
                out.push(label + ": " + (v ? I18n.tr("Yes") : I18n.tr("No")));
            else
                out.push(label + ": " + v);
        }
        return out;
    }

    function matchSummary(rule) {
        const matches = matchesOf(rule);
        const first = matches[0] || {};
        const label = first.appId || first.title || I18n.tr("Any window");
        if (matches.length > 1)
            return I18n.tr("%1 (+%2 more)", "window rule summary, %1 is first match, %2 is remaining count").arg(label).arg(matches.length - 1);
        return label;
    }

    readonly property var actionLabels: ({
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
            "variableRefreshRate": "VRR",
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
            "tile": I18n.tr("Tile"),
            "nofocus": I18n.tr("No focus"),
            "noborder": I18n.tr("No border"),
            "noshadow": I18n.tr("No shadow"),
            "nodim": I18n.tr("No dim"),
            "noblur": I18n.tr("No blur"),
            "noanim": I18n.tr("No anim"),
            "norounding": I18n.tr("No round"),
            "pin": I18n.tr("Pin", "verb, keep an item pinned in place"),
            "opaque": I18n.tr("Opaque"),
            "sizeWidth": I18n.tr("W"),
            "sizeHeight": I18n.tr("H"),
            "moveX": "X",
            "moveY": "Y",
            "monitor": I18n.tr("Monitor"),
            "workspace": I18n.tr("Workspace"),
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
            "forcergbx": I18n.tr("Force RGBX"),
            "idleinhibit": I18n.tr("Idle inhibitor", "feature that keeps the session from going idle"),
            "noInitialFocus": I18n.tr("No initial focus"),
            "focusOnActivate": I18n.tr("Focus on activate"),
            "stayFocused": I18n.tr("Stay focused"),
            "confinePointer": I18n.tr("Confine pointer"),
            "noXdgDrags": I18n.tr("No XDG drags"),
            "noAutoHdr": I18n.tr("No auto HDR"),
            "noGlow": I18n.tr("No glow"),
            "noWobble": I18n.tr("No wobble"),
            "scrollingWidth": I18n.tr("Column Width"),
            "tonemap": I18n.tr("Tone mapping"),
            "suppressEvent": I18n.tr("Suppress events")
        })

    signal rulesChanged

    function getActiveWindows() {
        const toplevels = ToplevelManager.toplevels?.values || [];
        return toplevels.map(t => ({
                    appId: t.appId || "",
                    title: t.title || ""
                }));
    }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() {
            root.activeWindows = root.getActiveWindows();
        }
    }

    function loadWindowRules() {
        const compositor = CompositorService.compositor;
        if (compositor !== "niri" && compositor !== "hyprland" && compositor !== "mango") {
            windowRulesInclude.checking = false;
            windowRules = [];
            externalRules = [];
            return;
        }

        windowRulesInclude.checking = true;
        Proc.runCommand("load-windowrules", [Proc.dmsBin, "config", "windowrules", "list", compositor], (output, exitCode) => {
            windowRulesInclude.checking = false;
            if (exitCode !== 0) {
                windowRules = [];
                externalRules = [];
                return;
            }
            try {
                const result = JSON.parse(output.trim());
                const allRules = result.rules || [];
                CompositorService.syncDmsWindowFloatingRule(allRules);
                windowRules = allRules.filter(r => (r.source || "").includes("dms/windowrules") && r.id !== CompositorService.dmsOpaqueRuleId);
                externalRules = allRules.filter(r => !(r.source || "").includes("dms/windowrules"));
                windowRulesInclude.applyStatus(result.dmsStatus);
            } catch (e) {
                windowRules = [];
                externalRules = [];
            }
        });
    }

    function removeRule(ruleId) {
        if (readOnly) {
            windowRulesInclude.showReadOnlyWarning();
            return;
        }
        const compositor = CompositorService.compositor;
        if (compositor !== "niri" && compositor !== "hyprland" && compositor !== "mango")
            return;

        Proc.runCommand("remove-windowrule", [Proc.dmsBin, "config", "windowrules", "remove", compositor, ruleId], (output, exitCode) => {
            if (exitCode === 0) {
                CompositorService.reloadAfterWindowRuleWrite();
                loadWindowRules();
                rulesChanged();
            }
        });
    }

    function reorderRules(indices) {
        if (savingRuleOrder)
            return;
        if (readOnly) {
            windowRulesInclude.showReadOnlyWarning();
            return;
        }
        const compositor = CompositorService.compositor;
        if (compositor !== "niri" && compositor !== "hyprland" && compositor !== "mango")
            return;
        const previous = windowRules;
        const reordered = indices.map(index => previous[index]);
        const ids = reordered.map(rule => rule.id);
        savingRuleOrder = true;
        windowRules = reordered;

        Proc.runCommand("reorder-windowrules", [Proc.dmsBin, "config", "windowrules", "reorder", compositor, JSON.stringify(ids)], (output, exitCode) => {
            savingRuleOrder = false;
            if (exitCode !== 0) {
                windowRules = previous;
                return;
            }
            CompositorService.reloadAfterWindowRuleWrite();
            loadWindowRules();
            rulesChanged();
        });
    }

    property bool editorOpen: false
    property bool editorMounted: false
    property var editorRequest: null

    function openRuleModal(window) {
        openEditor("new", window || null);
    }

    function editRule(rule) {
        openEditor("edit", rule);
    }

    function copyRuleToDms(rule) {
        openEditor("copy", rule);
    }

    function openEditor(mode, payload) {
        if (readOnly) {
            windowRulesInclude.showReadOnlyWarning();
            return;
        }
        if (editorOpen)
            return;
        editorRequest = {
            mode,
            payload
        };
        editorOpen = true;
        editorMounted = true;
        if (editorLoader.item)
            presentEditor();
    }

    function presentEditor() {
        const request = editorRequest;
        if (!request)
            return;
        switch (request.mode) {
        case "edit":
            editorLoader.item.showEdit(request.payload);
            return;
        case "copy":
            editorLoader.item.showCopy(request.payload);
            return;
        default:
            editorLoader.item.show(request.payload);
        }
    }

    function closeEditor() {
        if (!editorOpen)
            return;
        editorOpen = false;
        editorRequest = null;
        if (editorLoader.item)
            editorLoader.item.opened = false;
    }

    Component.onCompleted: {
        componentReady = true;
        Qt.callLater(() => {
            SettingsSearchService.registerCard("windowRules", headerSection, flickable);
            if (CompositorService.supportsWindowRules)
                loadWindowRules();
        });
    }

    SettingsPage {
        id: flickable

        SettingsCard {
            id: headerSection
            width: parent.width
            iconName: "select_window"

            SettingsRow {
                subtitle: I18n.tr("Define rules for window behavior. Saves to %1", "window rules settings description, %1 is a config file name").arg(root.dmsRulesFileName)
            }

            SettingsRow {
                id: createRuleRow
                visible: root.activeWindows.length > 0
                title: I18n.tr("Create rule for:")

                DDropdown {
                    id: windowSelector
                    downKeyOpens: false
                    backgroundColor: SettingsMetrics.controlSurface
                    anchors.verticalCenter: parent.verticalCenter
                    dropdownWidth: Math.min(400, createRuleRow.width - SettingsMetrics.rowPaddingH * 2)
                    compactMode: true
                    emptyText: I18n.tr("Select a window...")
                    options: root.activeWindows.map(w => {
                        const label = w.appId + (w.title ? " - " + w.title : "");
                        return label.length > 60 ? label.substring(0, 57) + "..." : label;
                    })
                    onValueChanged: value => {
                        if (!value)
                            return;
                        const index = options.indexOf(value);
                        if (index < 0 || index >= root.activeWindows.length)
                            return;
                        const window = root.activeWindows[index];
                        root.openRuleModal(window);
                        currentValue = "";
                    }
                }
            }
        }

        IncludeSetupBanner {
            include: windowRulesInclude
            visibleCondition: windowRulesInclude.compositorSupported
        }

        SettingsCard {
            width: parent.width
            iconName: "list"
            title: I18n.tr("Rules (%1)", "window rules settings card title, %1 is a count").arg(root.windowRules?.length ?? 0)

            SettingsRow {
                visible: !root.windowRules || root.windowRules.length === 0
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    DIcon {
                        name: "select_window"
                        size: Theme.iconSizeLarge
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: I18n.tr("No window rules configured")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            SettingsReorderList {
                id: rulesListColumn

                model: root.windowRules || []
                visible: count > 0
                enabled: !root.savingRuleOrder
                onReordered: indices => root.reorderRules(indices)

                delegate: SettingsReorderRow {
                    id: ruleRow

                    required property var modelData

                    reorderList: rulesListColumn
                    reorderEnabled: !root.readOnly
                    readonly property string ruleIdRef: modelData.id
                    readonly property var liveRuleData: (root.windowRules || []).find(rule => rule.id === ruleIdRef) ?? modelData

                    title: liveRuleData.name || liveRuleData.matchCriteria?.appId || liveRuleData.matchCriteria?.title || I18n.tr("Unnamed rule")
                    subtitle: {
                        const criteria = liveRuleData.matchCriteria || {};
                        const parts = [];
                        if (criteria.appId)
                            parts.push(criteria.appId);
                        if (criteria.title)
                            parts.push("title: " + criteria.title);
                        return parts.length > 0 ? parts.join(" · ") : I18n.tr("No match criteria");
                    }

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "edit"
                        enabled: !root.readOnly
                        Accessible.name: I18n.tr("Edit rule")
                        onClicked: root.editRule(ruleRow.liveRuleData)
                    }

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "delete"
                        iconColor: Theme.error
                        enabled: !root.readOnly
                        Accessible.name: I18n.tr("Delete rule")
                        onClicked: root.removeRule(ruleRow.ruleIdRef)
                    }

                    body: Flow {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: actionRepeater.count > 0

                        Repeater {
                            id: actionRepeater
                            model: root.actionChips(ruleRow.liveRuleData.actions)

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
        }

        SettingsCard {
            width: parent.width
            iconName: "description"
            title: I18n.tr("User window rules (%1)", "card title for read-only compositor config rules, %1 is a count").arg(root.externalRules?.length ?? 0)
            visible: root.externalRules && root.externalRules.length > 0

            SettingsRow {
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Rules found in your compositor config. These are read-only here, use Convert to DMS to make an editable copy.")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            Repeater {
                model: ScriptModel {
                    objectProp: "id"
                    values: root.externalRules || []
                }

                delegate: SettingsRow {
                    id: externalCard
                    required property var modelData

                    readonly property string displayName: {
                        const name = externalCard.modelData.name || "";
                        if (name)
                            return name;
                        return root.matchSummary(externalCard.modelData);
                    }
                    readonly property string sourceFile: (externalCard.modelData.source || "").split("/").pop()
                    readonly property bool expanded: root.expandedExternalId === externalCard.modelData.id
                    readonly property bool hasActions: {
                        const a = externalCard.modelData.actions || {};
                        return Object.keys(a).some(k => a[k] !== undefined && a[k] !== null && a[k] !== "");
                    }

                    title: externalCard.displayName
                    subtitle: {
                        const m = externalCard.modelData.matchCriteria || {};
                        let parts = [];
                        if (m.appId)
                            parts.push(m.appId);
                        if (m.title)
                            parts.push("title: " + m.title);
                        const base = parts.length > 0 ? parts.join(" · ") : I18n.tr("No match criteria");
                        const count = root.matchesOf(externalCard.modelData).length;
                        return count > 1 ? I18n.tr("%1 (+%2 more)").arg(base).arg(count - 1) : base;
                    }
                    clickable: true
                    onClicked: root.expandedExternalId = externalCard.expanded ? "" : externalCard.modelData.id

                    DBadge {
                        visible: externalCard.sourceFile.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: externalCard.sourceFile
                        color: SettingsMetrics.controlColor
                        textColor: Theme.surfaceVariantText
                    }

                    DIcon {
                        name: externalCard.expanded ? "expand_less" : "expand_more"
                        size: Theme.iconSize
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DActionButton {
                        iconName: "content_copy"
                        iconColor: Theme.surfaceVariantText
                        enabled: !root.readOnly
                        anchors.verticalCenter: parent.verticalCenter
                        tooltipText: I18n.tr("Convert to DMS")
                        tooltipSide: "left"
                        onClicked: root.copyRuleToDms(externalCard.modelData)
                    }

                    body: Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: externalCard.hasActions || externalCard.expanded

                        Flow {
                            width: parent.width
                            spacing: Theme.spacingXS
                            visible: externalCard.hasActions

                            Repeater {
                                model: root.actionChips(externalCard.modelData.actions)

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

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS
                            visible: externalCard.expanded

                            SettingsDivider {}

                            StyledText {
                                text: I18n.tr("Match (%1)", "noun, window rule match criteria heading, %1 is a count").arg(root.matchesOf(externalCard.modelData).length)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Theme.fontWeightMedium
                                color: Theme.surfaceText
                            }

                            Repeater {
                                model: root.matchesOf(externalCard.modelData)

                                delegate: StyledText {
                                    required property var modelData
                                    width: parent.width
                                    text: {
                                        const c = root.formatCriteria(modelData, root.matchLabels);
                                        return "• " + (c.length > 0 ? c.join("   ·   ") : I18n.tr("Any window"));
                                    }
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                }
                            }

                            StyledText {
                                text: I18n.tr("Actions")
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Theme.fontWeightMedium
                                color: Theme.surfaceText
                                topPadding: Theme.spacingXS
                            }

                            StyledText {
                                width: parent.width
                                text: {
                                    const a = root.formatCriteria(externalCard.modelData.actions, root.actionLabels);
                                    return a.length > 0 ? a.join("   ·   ") : I18n.tr("None");
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }

                            StyledText {
                                width: parent.width
                                text: I18n.tr("Source: %1", "window rule detail, %1 is the config file path").arg(externalCard.modelData.source || "")
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                elide: Text.ElideMiddle
                                topPadding: Theme.spacingXS
                            }
                        }
                    }
                }
            }
        }

        SettingsFabBar {
            shown: !root.readOnly

            DFab {
                text: I18n.tr("Add window rule")
                iconName: "add"
                onClicked: root.openRuleModal()
            }
        }
    }

    Loader {
        id: editorLoader
        parent: root.parentModal?.modalFocusScope ?? root
        anchors.fill: parent
        z: 100
        active: root.editorMounted
        onLoaded: root.presentEditor()

        sourceComponent: WindowRuleEditorDialog {
            supportingText: I18n.tr("Changes save to %1", "hint under the keybind and window rule editors, %1 is the config file the changes are written to").arg(root.dmsRulesFileName)
            onRejected: root.closeEditor()
            onRuleSubmitted: {
                root.loadWindowRules();
                root.closeEditor();
            }
            onActiveChanged: {
                if (!active && !root.editorOpen)
                    root.editorMounted = false;
            }
        }
    }
}
