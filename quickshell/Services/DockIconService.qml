pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Modals.FileBrowser
import "../Common/DockIconRules.js" as Rules

Singleton {
    id: root

    // Icons picked for single windows. They last until the window closes.
    property var windowIcons: []
    property string pendingAppId: ""
    property var pendingToplevel: null

    FileBrowserModal {
        id: imageBrowser

        browserTitle: I18n.tr("Select Dock Icon", "file browser title when picking an image for a dock icon")
        bucket: "dock-icon"
        filters: ["*.png", "*.svg", "*.jpg", "*.jpeg", "*.webp"]
        onAccepted: paths => {
            if (paths.length > 0 && ToplevelManager.toplevels.values.includes(root.pendingToplevel))
                root.setIcon(root.pendingAppId, root.pendingToplevel, paths[0]);
            root.pendingToplevel = null;
        }
        onRejected: root.pendingToplevel = null
    }

    function chooseImage(appId, toplevel) {
        if (!toplevel)
            return;
        pendingAppId = appId;
        pendingToplevel = toplevel;
        imageBrowser.open();
    }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() {
            root.pruneClosed();
        }
    }

    function pruneClosed() {
        const open = ToplevelManager.toplevels.values;
        const kept = windowIcons.filter(entry => open.includes(entry.toplevel));
        if (kept.length !== windowIcons.length)
            windowIcons = kept;
    }

    function titleKey(title) {
        return Rules.titleKey(title);
    }

    function windowIcon(toplevel) {
        return windowIcons.find(entry => entry.toplevel === toplevel)?.icon ?? "";
    }

    function iconFor(appId, toplevel) {
        if (!toplevel)
            return "";
        return windowIcon(toplevel) || (Rules.findRule(SessionData.dockIconRules, appId, toplevel.title)?.icon ?? "");
    }

    function isRemembered(appId, toplevel) {
        return Rules.findRule(SessionData.dockIconRules, appId, toplevel?.title) !== null;
    }

    function setIcon(appId, toplevel, icon) {
        if (!toplevel || !icon)
            return;
        windowIcons = windowIcons.filter(entry => entry.toplevel !== toplevel).concat([
            {
                "toplevel": toplevel,
                "icon": icon
            }
        ]);
        if (isRemembered(appId, toplevel))
            SessionData.setDockIconRule(appId, titleKey(toplevel.title), icon);
    }

    function setRemembered(appId, toplevel, remember) {
        const key = titleKey(toplevel?.title);
        if (!appId || !key)
            return;
        if (!remember) {
            SessionData.removeDockIconRule(appId, key);
            return;
        }
        const icon = iconFor(appId, toplevel);
        if (icon)
            SessionData.setDockIconRule(appId, key, icon);
    }

    function reset(appId, toplevel) {
        windowIcons = windowIcons.filter(entry => entry.toplevel !== toplevel);
        const key = titleKey(toplevel?.title);
        if (appId && key)
            SessionData.removeDockIconRule(appId, key);
    }
}
