import QtQuick
import Quickshell
import Quickshell.WindowManager
import qs.Common
import qs.Services

LabelOSD {
    id: root

    osdKind: "workspace"
    iconName: "view_module"
    label: workspaceLabel

    property string workspaceLabel: ""
    property var lastActiveWorkspaceId: null

    readonly property var activeWorkspace: root.getActiveWorkspace()
    readonly property bool useNativeWorkspace: CompositorService.hasWorkspaceIpc
    readonly property bool useExtWorkspace: {
        if (Quickshell.env("DMS_FORCE_EXTWS") === "1")
            return (WindowManager.windowsets?.length ?? 0) > 0;
        if (!CompositorService.compositorDetected || root.useNativeWorkspace)
            return false;
        return (WindowManager.windowsets?.length ?? 0) > 0;
    }

    function inOverview() {
        return root.useNativeWorkspace && CompositorService.overviewActiveForScreen(root.screen?.name);
    }

    function getActiveWorkspace() {
        const screenName = root.screen?.name ?? "";
        if (root.useNativeWorkspace)
            return CompositorService.activeWorkspaceForScreen(screenName);
        if (!root.useExtWorkspace || !root.screen)
            return null;
        const projection = WindowManager.screenProjection(root.screen);
        const ws = projection?.windowsets?.find(w => w.active);
        if (!ws)
            return null;
        const name = (ws.name ?? "").trim();
        const id = ws.id || name;
        if (id === undefined || id === null || id === "")
            return null;
        const parsed = parseInt(name, 10);
        return {
            "id": id,
            "idx": (name !== "" && String(parsed) === name) ? parsed : null,
            "name": name,
            "output": screenName
        };
    }

    function handleWorkspaceChange() {
        if (!SettingsData.osdWorkspaceEnabled)
            return;

        const ws = root.activeWorkspace;
        if (!ws || ws.id === undefined || ws.id === null)
            return;

        if (root.lastActiveWorkspaceId === null) {
            root.lastActiveWorkspaceId = ws.id;
            return;
        }
        if (root.lastActiveWorkspaceId === ws.id)
            return;
        if (root.inOverview())
            return;

        root.lastActiveWorkspaceId = ws.id;
        root.updateWorkspaceInfo(ws);
        if (SessionData.suppressOSD)
            return;
        if (root.publishToIsland())
            return;
        root.show();
    }

    function publishToIsland() {
        const hosts = SettingsData.activeIslandConfigsForScreen(root.screen).filter(cfg => SettingsData.islandSetting(cfg, "islandWorkspaceOsd"));
        const host = hosts.find(cfg => !SettingsData.isDotBarConfig(cfg)) ?? hosts[0];
        if (!host)
            return false;
        const screenName = root.screen?.name ?? "";
        const session = IslandActivityService.sessions.find(s => s.screenName === screenName && s.barId === host.id);
        if (!session?.accepts({"source": "workspace", "screen": screenName, "barId": host.id}))
            return false;
        // announce restarts the preview so each switch in a burst gets the full duration.
        return IslandActivityService.publish("workspace", `switch-${screenName.replace(/[^a-zA-Z0-9_.:-]/g, "-")}`, {
            "title": root.workspaceLabel,
            "icon": "view_module",
            "duration": root.autoHideInterval,
            "announce": true,
            "priority": 60,
            "screen": screenName,
            "barId": host.id
        });
    }

    function updateWorkspaceInfo(ws) {
        if (!ws)
            return;
        const num = (ws.idx !== undefined && ws.idx !== null && ws.idx > 0) ? ws.idx : (typeof ws.id === "number" && ws.id > 0 ? ws.id : null);
        const name = (ws.name ?? "").trim();

        if (num !== null) {
            if (name !== "" && name !== String(num)) {
                root.workspaceLabel = I18n.tr("Workspace %1: %2", "workspace switch OSD, %1 is workspace number, %2 is workspace name").arg(num).arg(name);
            } else {
                root.workspaceLabel = I18n.tr("Workspace %1", "workspace switch OSD, %1 is workspace number").arg(num);
            }
        } else if (name !== "") {
            root.workspaceLabel = name;
        } else {
            root.workspaceLabel = I18n.tr("Workspace", "fallback label when workspace has no number or name");
        }
    }

    onActiveWorkspaceChanged: root.handleWorkspaceChange()

    Component.onCompleted: root.handleWorkspaceChange()
}
