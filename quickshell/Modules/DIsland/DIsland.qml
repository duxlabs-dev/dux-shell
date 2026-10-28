pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root

    property var hyprlandOverviewLoader: null

    readonly property var hostSlots: ShellLayout.islandKeys

    readonly property bool launcherOpen: root.activityOpen("launcher")
    readonly property bool controlCenterOpen: root.activityOpen("controlcenter")

    function hosts() {
        return (islandVariants.instances || []).concat(freeIslandVariants.instances || []);
    }

    function freeHostForScreen(screenName, kind) {
        const requested = (screenName || "").trim() || CompositorService.getFocusedScreenName();
        const instance = (ShellLayout.forScreen(requested)?.instances ?? []).find(instance => instance.free && root.matchesKind(instance, kind));
        if (!instance)
            return null;
        return hosts().find(host => host?.free && host.screen?.name === requested && host.barId === instance.barId) ?? null;
    }

    function ipcMove(x, y, screen, kind) {
        const host = root.freeHostForScreen(screen, kind);
        if (!host)
            return `${root.ipcTag(kind)}_NOT_FREE`;
        if (!isFinite(x) || !isFinite(y))
            return `${root.ipcTag(kind)}_INVALID_POSITION`;
        host.moveTo(x, y);
        return `${root.ipcTag(kind)}_MOVED: ${Math.round(host.anchorX)}\t${Math.round(host.anchorY)}\t${host.screen?.name ?? ""}`;
    }

    function ipcCenter(screen, kind) {
        const host = root.freeHostForScreen(screen, kind);
        if (!host)
            return `${root.ipcTag(kind)}_NOT_FREE`;
        return root.ipcMove(host.screenWidth / 2, host.screenHeight / 2, screen, kind);
    }

    function hostWithActivity(activityId, screenName) {
        for (const host of hosts()) {
            if (host?.islandController?.activeActivity === activityId && host.islandController.expanded && (!screenName || host.screen?.name === screenName))
                return host;
        }
        return null;
    }

    function activityOpen(activityId) {
        return root.hostWithActivity(activityId) !== null;
    }

    function hostForExactScreen(screen, barId, kind) {
        return screen ? hostForScreenName(screen.name, barId, kind) : null;
    }

    function matchesKind(instance, kind) {
        return !kind || (kind === "dot") === !!instance.dot;
    }

    function hostForScreenName(screenName, barId, kind) {
        const instances = ShellLayout.forScreen(screenName)?.instances ?? [];
        const ordered = instances.filter(instance => instance.hostsIsland && (!barId || instance.barId === barId) && root.matchesKind(instance, kind)).sort((a, b) => Number(!!a.free) - Number(!!b.free) || Number(["left", "right"].includes(a.edge)) - Number(["left", "right"].includes(b.edge)) || a.configOrder - b.configOrder);
        for (const instance of ordered) {
            const host = hosts().find(host => host?.screen?.name === screenName && host.barId === instance.barId && host.islandController);
            if (host)
                return host;
        }
        return null;
    }

    function focusedHost(kind) {
        const focused = hostForScreenName(CompositorService.getFocusedScreenName(), "", kind);
        if (focused)
            return focused;
        for (const screen of Quickshell.screens) {
            const host = hostForScreenName(screen.name, "", kind);
            if (host)
                return host;
        }
        return null;
    }

    function focusedIslandScreen() {
        return focusedHost()?.screen ?? null;
    }

    function hasHostForScreen(screen, barId) {
        return screen ? hostForExactScreen(screen, barId) !== null : focusedHost() !== null;
    }

    function hostForScreenOrFocused(screen, barId) {
        if (barId && !screen)
            return null;
        return screen ? hostForExactScreen(screen, barId) : focusedHost();
    }

    function hostForScreen(screenName, barId, kind) {
        const requested = (screenName || "").trim();
        return requested ? hostForScreenName(requested, barId, kind) : barId ? null : focusedHost(kind);
    }

    function ipcTag(kind) {
        return kind === "dot" ? "DANK_DOT" : "DANK_ISLAND";
    }

    function activityName(activity) {
        const requested = (activity || "home").trim().toLowerCase();
        switch (requested) {
        case "media":
        case "launcher":
        case "controlcenter":
        case "wallpaper":
        case "weather":
        case "wellbeing":
        case "notificationcenter":
        case "clipboard":
        case "powermenu":
            return requested;
        case "power-menu":
            return "powermenu";
        case "control-center":
        case "cc":
            return "controlcenter";
        case "notifications":
        case "notification-center":
        case "notification":
        case "nc":
            return "notificationcenter";
        }
        return "home";
    }

    function openActivityOn(host, activityId, section) {
        switch (activityId) {
        case "media":
            if (!host.islandController.mediaAvailable)
                return host.islandController.requestActivity("home", true, true);
            return host.islandController.requestActivity("media", true, true);
        case "launcher":
            return host.islandController.requestLauncher("", "", false);
        case "controlcenter":
            return host.islandController.requestControlCenter(section || "", false);
        case "wallpaper":
            return host.islandController.requestWallpaper(false);
        case "weather":
            return host.islandController.requestWeather(false);
        case "notificationcenter":
            return host.islandController.requestNotificationCenter(false);
        case "clipboard":
            return host.islandController.requestClipboard(false);
        case "powermenu":
            return host.islandController.requestPowerMenu(false);
        }
        return host.islandController.requestActivity(activityId, true, true);
    }

    function openActivity(activityId, screen, section, barId): bool {
        const host = root.hostForScreenOrFocused(screen, barId);
        return host ? root.openActivityOn(host, activityId, section) === true : false;
    }

    function toggleActivity(activityId, screen, section, barId): bool {
        const host = root.hostForScreenOrFocused(screen, barId);
        if (!host)
            return false;
        const resolved = activityId === "media" && !host.islandController.mediaAvailable ? "home" : activityId;
        const openHost = barId ? (host.islandController.activeActivity === resolved && host.islandController.expanded ? host : null) : root.hostWithActivity(resolved);
        if (openHost) {
            openHost.islandController.requestCollapse();
            return true;
        }
        return root.openActivity(activityId, screen, section, barId);
    }

    // An IPC close takes down everything that shows the activity, on every monitor.
    function closeActivity(activityId): bool {
        let closed = false;
        for (const host of hosts()) {
            if (host?.islandController?.activeActivity !== activityId || !host.islandController.expanded)
                continue;
            host.islandController.requestCollapse();
            closed = true;
        }
        return closed;
    }

    function openLauncher(query, mode, screen, barId): bool {
        const target = screen ?? CompositorService.getFocusedScreen();
        const config = barId ? null : SettingsData.islandLauncherHostConfig(target);
        const host = barId ? root.hostForExactScreen(target, barId) : config ? root.hostForExactScreen(target, config.id) : null;
        return host ? host.islandController.requestLauncher(query || "", mode || "", false) : false;
    }

    function toggleLauncher(query, mode, screen, barId): bool {
        const target = screen ?? CompositorService.getFocusedScreen();
        const host = barId ? root.hostForExactScreen(target, barId) : root.hostWithActivity("launcher", target?.name);
        if (host?.islandController.expanded && host.islandController.activeActivity === "launcher") {
            host.islandController.requestCollapse();
            return true;
        }
        return root.openLauncher(query, mode, screen, barId);
    }

    function ipcOpen(activity, screen, barId, kind) {
        const host = root.hostForScreen(screen, barId, kind);
        if (!host)
            return `${root.ipcTag(kind)}_UNAVAILABLE`;
        const requested = root.activityName(activity);
        if (!root.openActivityOn(host, requested, ""))
            return `${root.ipcTag(kind)}_ACTIVITY_UNAVAILABLE: ${requested}`;
        return `${root.ipcTag(kind)}_OPEN: ${requested}\t${host.screen?.name ?? ""}`;
    }

    function ipcToggle(activity, screen, barId, kind) {
        const host = root.hostForScreen(screen, barId, kind);
        if (!host)
            return `${root.ipcTag(kind)}_UNAVAILABLE`;
        if (host.islandController.expanded && !host.islandController.notificationActive) {
            host.islandController.requestCollapse();
            return `${root.ipcTag(kind)}_CLOSED: ${host.screen?.name ?? ""}`;
        }
        return ipcOpen(activity, screen, barId, kind);
    }

    function ipcShow(activity, screen, barId, kind) {
        const host = root.hostForScreen(screen, barId, kind);
        if (!host)
            return `${root.ipcTag(kind)}_UNAVAILABLE`;
        const requested = root.activityName(activity);
        if (!host.islandController.requestActivity(requested, false, false))
            return `${root.ipcTag(kind)}_ACTIVITY_UNAVAILABLE: ${requested}`;
        return `${root.ipcTag(kind)}_SHOW: ${requested}\t${host.screen?.name ?? ""}`;
    }

    function ipcClose(screen, barId, kind) {
        const host = root.hostForScreen(screen, barId, kind);
        if (!host)
            return `${root.ipcTag(kind)}_UNAVAILABLE`;
        host.islandController.requestCollapse();
        return `${root.ipcTag(kind)}_CLOSED: ${host.screen?.name ?? ""}`;
    }

    function ipcCycle(screen, barId, kind) {
        const host = root.hostForScreen(screen, barId, kind);
        if (!host)
            return `${root.ipcTag(kind)}_UNAVAILABLE`;
        host.islandController.cycleActivity(1, host.islandController.expanded);
        return `${root.ipcTag(kind)}_ACTIVITY: ${host.islandController.activeActivity}\t${host.screen?.name ?? ""}`;
    }

    function ipcStatus(screen, barId, kind) {
        const host = root.hostForScreen(screen, barId, kind);
        if (!host)
            return JSON.stringify({
                "available": false,
                "enabled": true,
                "launcherAvailable": false
            });
        return JSON.stringify({
            "available": true,
            "enabled": true,
            "screen": host.screen?.name ?? "",
            "activity": host.islandController.activeActivity,
            "expanded": host.islandController.expanded,
            "mediaAvailable": host.islandController.mediaAvailable,
            "launcherAvailable": true,
            "controlCenterAvailable": true,
            "wallpaperAvailable": true,
            "weatherAvailable": true,
            "notificationCenterAvailable": true,
            "clipboardAvailable": true,
            "powerMenuAvailable": true,
            "launcherInputFocused": host.islandController.launcherInputFocused,
            "launcherResultCount": host.launcherResultCount,
            "compactHeight": host.islandController.compactThickness,
            "free": !!host.free,
            "idle": host.free ? host.idle : false,
            "x": host.free ? Math.round(host.anchorX) : null,
            "y": host.free ? Math.round(host.anchorY) : null
        });
    }

    Component.onCompleted: PopoutService.dankIslandRouter = root
    Component.onDestruction: {
        if (PopoutService.dankIslandRouter === root)
            PopoutService.dankIslandRouter = null;
    }

    Variants {
        id: islandVariants

        model: root.hostSlots

        delegate: DIslandHostWindow {
            required property var modelData

            readonly property var identity: JSON.parse(modelData)
            screen: ShellLayout.screenForName(identity[0])
            barId: identity[1]
            hyprlandOverviewLoader: root.hyprlandOverviewLoader
        }
    }

    Variants {
        id: freeIslandVariants

        model: ShellLayout.freeIslandKeys

        delegate: IslandFreeHostWindow {
            required property var modelData

            readonly property var identity: JSON.parse(modelData)
            screen: ShellLayout.screenForName(identity[0])
            barId: identity[1]
        }
    }

    IpcHandler {
        target: "island"

        function open(activity: string): string {
            return root.ipcOpen(activity, "", "", "island");
        }

        function toggle(activity: string): string {
            return root.ipcToggle(activity, "", "", "island");
        }

        function show(activity: string): string {
            return root.ipcShow(activity, "", "", "island");
        }

        function close(): string {
            return root.ipcClose("", "", "island");
        }

        function cycle(): string {
            return root.ipcCycle("", "", "island");
        }

        function status(): string {
            return root.ipcStatus("", "", "island");
        }

        function openOn(activity: string, screen: string): string {
            return root.ipcOpen(activity, screen, "", "island");
        }

        function toggleOn(activity: string, screen: string): string {
            return root.ipcToggle(activity, screen, "", "island");
        }

        function showOn(activity: string, screen: string): string {
            return root.ipcShow(activity, screen, "", "island");
        }

        function closeOn(screen: string): string {
            return root.ipcClose(screen, "", "island");
        }

        function cycleOn(screen: string): string {
            return root.ipcCycle(screen, "", "island");
        }

        function statusOn(screen: string): string {
            return root.ipcStatus(screen, "", "island");
        }

        function openInstance(activity: string, screen: string, barId: string): string {
            return root.ipcOpen(activity, screen, barId);
        }

        function toggleInstance(activity: string, screen: string, barId: string): string {
            return root.ipcToggle(activity, screen, barId);
        }

        function notifications(): string {
            return root.ipcToggle("notificationcenter", "", "", "island");
        }

        function notificationsOn(screen: string): string {
            return root.ipcToggle("notificationcenter", screen, "", "island");
        }

        function move(x: string, y: string): string {
            return root.ipcMove(parseFloat(x), parseFloat(y), "", "island");
        }

        function moveOn(screen: string, x: string, y: string): string {
            return root.ipcMove(parseFloat(x), parseFloat(y), screen, "island");
        }

        function center(): string {
            return root.ipcCenter("", "island");
        }

        function centerOn(screen: string): string {
            return root.ipcCenter(screen, "island");
        }
    }

    IpcHandler {
        target: "dot"

        function open(activity: string): string {
            return root.ipcOpen(activity, "", "", "dot");
        }

        function toggle(activity: string): string {
            return root.ipcToggle(activity, "", "", "dot");
        }

        function show(activity: string): string {
            return root.ipcShow(activity, "", "", "dot");
        }

        function close(): string {
            return root.ipcClose("", "", "dot");
        }

        function cycle(): string {
            return root.ipcCycle("", "", "dot");
        }

        function status(): string {
            return root.ipcStatus("", "", "dot");
        }

        function notifications(): string {
            return root.ipcToggle("notificationcenter", "", "", "dot");
        }

        function openOn(activity: string, screen: string): string {
            return root.ipcOpen(activity, screen, "", "dot");
        }

        function toggleOn(activity: string, screen: string): string {
            return root.ipcToggle(activity, screen, "", "dot");
        }

        function showOn(activity: string, screen: string): string {
            return root.ipcShow(activity, screen, "", "dot");
        }

        function closeOn(screen: string): string {
            return root.ipcClose(screen, "", "dot");
        }

        function cycleOn(screen: string): string {
            return root.ipcCycle(screen, "", "dot");
        }

        function statusOn(screen: string): string {
            return root.ipcStatus(screen, "", "dot");
        }

        function notificationsOn(screen: string): string {
            return root.ipcToggle("notificationcenter", screen, "", "dot");
        }

        function openInstance(activity: string, screen: string, barId: string): string {
            return root.ipcOpen(activity, screen, barId, "dot");
        }

        function toggleInstance(activity: string, screen: string, barId: string): string {
            return root.ipcToggle(activity, screen, barId, "dot");
        }

        function move(x: string, y: string): string {
            return root.ipcMove(parseFloat(x), parseFloat(y), "", "dot");
        }

        function moveOn(screen: string, x: string, y: string): string {
            return root.ipcMove(parseFloat(x), parseFloat(y), screen, "dot");
        }

        function center(): string {
            return root.ipcCenter("", "dot");
        }

        function centerOn(screen: string): string {
            return root.ipcCenter(screen, "dot");
        }
    }
}
