import QtQuick
import Quickshell
import qs.Common
import qs.Services

Item {
    id: root

    property string selectedDockId: SettingsUiState.dockHubSelection
    onSelectedDockIdChanged: {
        if (SettingsUiState.dockHubSelection !== selectedDockId)
            SettingsUiState.dockHubSelection = selectedDockId;
    }

    Connections {
        target: SettingsUiState

        function onDockHubSelectionChanged() {
            if (root.selectedDockId !== SettingsUiState.dockHubSelection)
                root.selectedDockId = SettingsUiState.dockHubSelection;
        }
    }

    Connections {
        target: SettingsData

        function onDockConfigsChanged() {
            root.normalizeSelection();
        }
    }

    Component.onCompleted: normalizeSelection()

    function normalizeSelection() {
        if (SettingsData.getDockConfig(root.selectedDockId))
            return;
        root.selectedDockId = SettingsData.dockConfigs[0]?.id ?? "";
    }

    readonly property var config: {
        selectedDockId;
        SettingsData.dockConfigs;
        return SettingsData.getDockConfig(selectedDockId);
    }
    readonly property bool hasConfig: !!config
    readonly property bool isVertical: config?.position === SettingsData.Position.Left || config?.position === SettingsData.Position.Right

    readonly property var screenPreferences: config?.screenPreferences ?? []
    readonly property bool allDisplays: screenPreferences.includes("all")
    readonly property string displaySummary: config ? displaySummaryFor(config) : ""

    function displaySummaryFor(target) {
        const preferences = target.screenPreferences ?? [];
        if (preferences.includes("all"))
            return I18n.tr("All displays");
        const names = preferences.map(pref => typeof pref === "string" ? pref : pref.name || pref.model);
        return names.length > 0 ? names.join(", ") : I18n.tr("No displays");
    }

    function summaryFor(target) {
        SettingsData.dockConfigs;
        SettingsData.barConfigs;
        const blockedBy = target.enabled ? SettingsData.dockAssignmentConflict(target.id, target.screenPreferences, target.position) : "";
        if (blockedBy)
            return I18n.tr("%1 holds this edge, so the dock stays hidden there", "dock settings status line, %1 is a bar or dock name").arg(blockedBy);
        return positionLabel(target.position) + " • " + displaySummaryFor(target);
    }

    // Edges nothing else already holds on the displays this dock covers; its own edge always stays.
    readonly property var positionChoices: {
        selectedDockId;
        SettingsData.dockConfigs;
        SettingsData.barConfigs;
        Quickshell.screens;
        const all = [SettingsData.Position.Top, SettingsData.Position.Bottom, SettingsData.Position.Left, SettingsData.Position.Right];
        if (!config)
            return all;
        return SettingsData.dockAvailableEdges(selectedDockId, screenPreferences);
    }

    function positionLabel(position) {
        switch (position) {
        case SettingsData.Position.Bottom:
            return I18n.tr("Bottom", "screen edge position");
        case SettingsData.Position.Left:
            return I18n.tr("Left", "screen edge position");
        case SettingsData.Position.Right:
            return I18n.tr("Right", "screen edge position");
        }
        return I18n.tr("Top", "screen edge position");
    }

    readonly property bool connectedFrameModeActive: SettingsData.connectedFrameModeActive && !(config?.useOverlayLayer ?? false)
    readonly property bool connectedPersistentDock: connectedFrameModeActive && (config?.enabled ?? false) && !(config?.autoHide ?? false) && !(config?.smartAutoHide ?? false)
    // An auto-hiding dock never reserves screen space, so its exclusive zone has nothing to offset.
    readonly property bool reservesSpace: !!config && !config.autoHide && !config.smartAutoHide && (!connectedFrameModeActive || connectedPersistentDock)

    // Whatever holds this dock's edge right now, which is why it may be configured but invisible.
    readonly property string currentEdgeBlockedBy: {
        selectedDockId;
        SettingsData.dockConfigs;
        SettingsData.barConfigs;
        if (!config || !config.enabled)
            return "";
        return SettingsData.dockAssignmentConflict(selectedDockId, screenPreferences, config.position);
    }

    // The apps strip keeps its own options on its widget entry rather than on the dock.
    readonly property var appsEntry: config?.widgets.find(item => item.widgetId === "appsDock") ?? null
    readonly property var _appsDefaults: ({
            "appsDockHideIndicators": false,
            "runningAppsCurrentWorkspace": false
        })
    readonly property var apps: ({
            "get": key => root.appsValue(key),
            "set": (key, value) => root.setAppsOption(key, value),
            "isDefault": keys => keys.every(key => root.appsDefault(key) === undefined || JSON.stringify(root.appsValue(key)) === JSON.stringify(root.appsDefault(key))),
            "resetToDefault": keys => keys.filter(key => root.appsDefault(key) !== undefined).forEach(key => root.setAppsOption(key, root.appsDefault(key)))
        })

    function appsDefault(key) {
        if (key in _appsDefaults)
            return _appsDefaults[key];
        return SettingsData.widgetDefaults("appsDock")[key];
    }

    function appsValue(key) {
        if (key in _appsDefaults)
            return appsEntry?.[key] ?? _appsDefaults[key];
        return SettingsData.widgetOption("appsDock", appsEntry, key);
    }

    function setAppsOption(key, value) {
        if (!appsEntry)
            return;
        SettingsData.updateDockWidget(selectedDockId, appsEntry.id, {
            [key]: value
        });
    }

    function isDefault(keys) {
        if (!config)
            return true;
        const defaults = SettingsData.dockConfigDefaults();
        return keys.every(key => config[key] === undefined || JSON.stringify(config[key]) === JSON.stringify(defaults[key]));
    }

    function resetToDefault(keys) {
        if (!config)
            return;
        const defaults = SettingsData.dockConfigDefaults();
        const patch = {};
        for (const key of keys)
            patch[key] = defaults[key];
        SettingsData.updateDockConfig(selectedDockId, patch);
    }

    // An assignment that would stack two surfaces on one edge is rejected rather than half-applied.
    function setOption(key, value) {
        if (!config)
            return;
        const claimsEdge = (config.enabled && (key === "screenPreferences" || key === "position")) || (key === "enabled" && value === true);
        if (claimsEdge) {
            const preferences = key === "screenPreferences" ? value : screenPreferences;
            const position = key === "position" ? value : config.position;
            const conflict = SettingsData.dockAssignmentConflict(selectedDockId, preferences, position);
            if (conflict) {
                ToastService.showWarning(I18n.tr("Display assignment conflict"), I18n.tr("%1 already holds this screen edge", "dock conflict warning toast, %1 is a bar or dock name").arg(conflict));
                return;
            }
        }
        SettingsData.updateDockConfig(selectedDockId, {
            [key]: value
        });
    }

    // Turning a dock on should show it: with nothing chosen it takes every display, and an edge
    // something else already holds is swapped for a free one rather than failing silently.
    function setEnabled(enabled, preferredPosition) {
        if (!config)
            return;
        if (!enabled) {
            SettingsData.updateDockConfig(selectedDockId, {
                enabled: false
            });
            return;
        }
        const preferences = screenPreferences.length > 0 ? screenPreferences : ["all"];
        let position = preferredPosition ?? config.position;
        if (SettingsData.dockAssignmentConflict(selectedDockId, preferences, position)) {
            const free = SettingsData.firstFreeDockEdge(selectedDockId, preferences);
            if (free < 0) {
                ToastService.showWarning(I18n.tr("Display assignment conflict"), I18n.tr("Every edge of this display is already taken"));
                return;
            }
            position = free;
            ToastService.showInfo(I18n.tr("Dock moved to %1", "dock settings toast, %1 is the screen edge name").arg(positionLabel(position)));
        }
        SettingsData.updateDockConfig(selectedDockId, {
            enabled: true,
            screenPreferences: preferences,
            position
        });
    }
}
