import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import "ControllerUtils.js" as Utils

DContextMenu {
    id: root

    property var item: null
    property var controller: null
    property var searchField: null
    property var parentHandler: null
    property string pinDockId: ""

    readonly property bool isCoreApp: item?.type === "app" && !!item?.isCore
    readonly property var coreAppData: isCoreApp ? item?.data ?? null : null
    readonly property var desktopEntry: !isCoreApp ? (item?.data ?? null) : null
    readonly property string appId: {
        if (isCoreApp)
            return item?.id || coreAppData?.builtInPluginId || "";
        return desktopEntry?.id || desktopEntry?.execString || "";
    }
    readonly property bool isPinned: !!appId && SessionData.getDockPins(pinDockId).includes(appId)
    readonly property bool isRegularApp: item?.type === "app" && !item.isCore && desktopEntry
    readonly property bool isFlatpakApp: isRegularApp && (item?.source === "flatpak" || !!item?.flatpakId || Utils.classifyAppSource(desktopEntry) === "flatpak")
    readonly property string flatpakAppId: item?.flatpakId || (isFlatpakApp ? Utils.extractFlatpakAppId(desktopEntry) : "")
    readonly property bool isPluginItem: item?.type === "plugin"

    signal editAppRequested(var app)

    layerNamespace: "dms:launcher-context-menu"
    keyboardNavigable: true

    menuItems: {
        if (isPluginItem)
            return getPluginContextMenuActions().map(act => ({
                        type: "item",
                        icon: act.icon || "play_arrow",
                        text: act.text || act.name || "",
                        action: () => executePluginAction(act)
                    }));

        if (item?.type !== "app" && item?.actions?.length > 0)
            return item.actions.map(act => ({
                        type: "item",
                        icon: act.icon || "play_arrow",
                        text: act.name || "",
                        action: () => executeLauncherAction(act)
                    }));

        const items = [];
        if (item?.type === "app" && pinDockId)
            items.push({
                type: "item",
                icon: isPinned ? "keep_off" : "push_pin",
                text: isPinned ? I18n.tr("Unpin from Dock") : I18n.tr("Pin to Dock"),
                action: togglePin
            });
        if (isRegularApp) {
            items.push({
                type: "item",
                icon: "visibility_off",
                text: I18n.tr("Hide App"),
                action: hideCurrentApp
            });
            items.push({
                type: "item",
                icon: "edit",
                text: I18n.tr("Edit App"),
                action: editCurrentApp
            });
        }
        if (item?.actions?.length > 0) {
            items.push({
                type: "separator"
            });
            for (const act of item.actions)
                items.push({
                    type: "item",
                    icon: act.icon || "play_arrow",
                    text: act.name || "",
                    action: () => executeDesktopAction(act)
                });
        }
        items.push({
            type: "separator"
        });
        if (isRegularApp && SessionService.nvidiaCommand)
            items.push({
                type: "item",
                icon: "memory",
                text: I18n.tr("Launch on dGPU"),
                action: launchWithNvidia
            });
        items.push({
            type: "item",
            icon: "launch",
            text: I18n.tr("Launch", "verb, start an application"),
            action: launchApp
        });
        if (isFlatpakApp && flatpakAppId)
            items.push({
                type: "separator"
            }, {
                type: "item",
                icon: "delete",
                text: I18n.tr("Uninstall", "context menu action to uninstall app") + "…",
                isDestructive: true,
                action: uninstallCurrentApp
            });
        return items;
    }

    onRenderActiveChanged: {
        if (renderActive)
            return;
        if (parentHandler)
            parentHandler.enabled = true;
        if (searchField?.visible)
            Qt.callLater(() => searchField.forceActiveFocus());
    }

    function hasContextMenuActions(spotlightItem) {
        if (!spotlightItem)
            return false;
        if (spotlightItem.type === "app")
            return true;
        if (spotlightItem.type === "plugin" && spotlightItem.pluginId) {
            const instance = PluginService.pluginInstances[spotlightItem.pluginId];
            if (typeof instance?.getContextMenuActions !== "function")
                return false;
            const actions = instance.getContextMenuActions(spotlightItem.data);
            return Array.isArray(actions) && actions.length > 0;
        }
        return spotlightItem.actions?.length > 0;
    }

    function getPluginContextMenuActions() {
        if (!isPluginItem || !item?.pluginId)
            return [];
        const instance = PluginService.pluginInstances[item.pluginId];
        if (typeof instance?.getContextMenuActions !== "function")
            return [];
        const actions = instance.getContextMenuActions(item.data);
        return Array.isArray(actions) ? actions : [];
    }

    function show(x, y, spotlightItem, fromKeyboard) {
        if (!spotlightItem?.data)
            return;
        item = spotlightItem;

        const modal = parentHandler?.parentModal ?? null;
        const screenRef = modal?.effectiveScreen ?? parentHandler?.Window?.window?.screen ?? searchField?.Window?.window?.screen ?? null;
        const screenX = screenRef?.x || 0;
        const screenY = screenRef?.y || 0;
        const screenRelativeX = modal ? ((modal.alignedX ?? 0) + x) : ((parentHandler ? parentHandler.mapToGlobal(x, y).x : x) - screenX);
        const screenRelativeY = modal ? ((modal.alignedY ?? 0) + y) : ((parentHandler ? parentHandler.mapToGlobal(x, y).y : y) - screenY);

        pinDockId = SettingsData.dockConfigForAction(screenRef)?.id ?? "";
        if (parentHandler)
            parentHandler.enabled = false;
        open(screenRef, screenRelativeX + Theme.spacingXS, screenRelativeY + Theme.spacingXS, fromKeyboard);
    }

    function executePluginAction(actionOrObj) {
        const actionFunc = typeof actionOrObj === "function" ? actionOrObj : actionOrObj?.action;
        const closeLauncher = typeof actionOrObj === "object" && actionOrObj?.closeLauncher;
        if (typeof actionFunc === "function")
            actionFunc();
        if (closeLauncher)
            controller?.itemExecuted();
        else
            controller?.performSearch();
        hide();
    }

    function executeLauncherAction(actionData) {
        if (!controller || !item || !actionData)
            return;
        controller.executeAction(item, actionData);
        hide();
    }

    function togglePin() {
        if (!appId || !SettingsData.getDockConfig(pinDockId))
            return;
        const pins = SessionData.getDockPins(pinDockId);
        if (!isPinned)
            SettingsData.ensureDockApps(pinDockId);
        SessionData.setDockPins(pinDockId, isPinned ? pins.filter(id => id !== appId) : pins.concat([appId]));
        hide();
    }

    function hideCurrentApp() {
        if (!appId)
            return;
        SessionData.hideApp(appId);
        controller?.performSearch();
        hide();
    }

    function editCurrentApp() {
        if (!desktopEntry)
            return;
        editAppRequested(desktopEntry);
        hide();
    }

    function uninstallCurrentApp() {
        if (!isFlatpakApp || !flatpakAppId)
            return;
        const targetFlatpakId = flatpakAppId;
        const appName = item?.name || desktopEntry?.name || flatpakAppId;
        const currentAppId = appId;
        hide();
        controller?.itemExecuted();
        AppSearchService.requestUninstallFlatpak(currentAppId, appName, targetFlatpakId);
    }

    function launchApp() {
        if (isCoreApp) {
            if (!coreAppData)
                return;
            AppSearchService.executeCoreApp(coreAppData);
            controller?.itemExecuted();
            hide();
            return;
        }
        if (!desktopEntry)
            return;
        SessionService.launchDesktopEntry(desktopEntry);
        AppUsageHistoryData.addAppUsage(desktopEntry);
        controller?.itemExecuted();
        hide();
    }

    function launchWithNvidia() {
        if (!desktopEntry)
            return;
        SessionService.launchDesktopEntry(desktopEntry, true);
        AppUsageHistoryData.addAppUsage(desktopEntry);
        controller?.itemExecuted();
        hide();
    }

    function executeDesktopAction(actionData) {
        if (!desktopEntry || !actionData)
            return;
        SessionService.launchDesktopAction(desktopEntry, actionData.actionData || actionData);
        AppUsageHistoryData.addAppUsage(desktopEntry);
        controller?.itemExecuted();
        hide();
    }
}
