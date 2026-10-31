import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

// A Scope, not a PluginComponent: the service parents daemons to itself, and an Item there is never placed in a scene.
Scope {
    id: root

    property string pluginId: ""
    property var pluginService: null
    property string token: ""

    // notifyApp: the app name of this request's notifications; empty keeps the manifest's island.notifyApp.
    function show(kind, notifyApp) {
        root.token = IslandActivityService.request(root.pluginId, {
            "kind": kind,
            "notifyApp": notifyApp ?? "",
            "data": {
                "label": kind === "alert" ? "Pasta" : kind === "live" ? "Tea" : "Connected"
            }
        });
        return root.token || "REFUSED";
    }

    Connections {
        target: IslandActivityService

        function onDropped(token, reason) {
            if (token === root.token)
                root.token = "";
        }
    }

    IpcHandler {
        target: "islandActivityExample"

        function request(kind: string): string {
            return root.show(kind);
        }

        function requestNotifying(kind: string, notifyApp: string): string {
            return root.show(kind, notifyApp);
        }

        function release(): string {
            return IslandActivityService.release(root.token) ? "RELEASED" : "NONE";
        }

        // A permanent bubble: "left", "right" or "off"; "drag on|off" stands in for a file dragged over the bar.
        function permanent(side: string): string {
            return IslandActivityService.setPermanent(root.pluginId, side === "off" ? null : {
                "side": side === "left" ? "left" : "right",
                "label": "Send to Example",
                "image": Qt.resolvedUrl("jellyfish.svg")
            }) ? "PERMANENT: " + side : "REFUSED";
        }

        function drag(on: string): string {
            const p = IslandActivityService.permanent[root.pluginId];
            if (!p)
                return "NONE";
            return IslandActivityService.setPermanent(root.pluginId, Object.assign({}, p, {
                "receiving": on === "on"
            })) ? "DRAG: " + on : "REFUSED";
        }

        function state(): string {
            return IslandActivityService.state(root.token) || "NONE";
        }
    }
}
