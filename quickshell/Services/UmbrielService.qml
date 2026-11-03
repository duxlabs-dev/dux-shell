pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Common as DCommon

Singleton {
    id: root
    readonly property var log: Log.scoped("UmbrielService")

    readonly property string socketPath: Quickshell.env("UMBRIEL_SOCKET")

    property bool active: false
    property var workspaces: []
    property var windows: []
    readonly property string focusedOutput: workspaces.find(ws => ws.focused)?.output ?? ""

    DCommon.DSocket {
        path: root.socketPath
        connected: root.active && root.socketPath !== ""

        onConnectionStateChanged: {
            if (linkUp)
                send({
                    "cmd": "subscribe",
                    "events": ["workspaces", "windows"]
                });
        }

        parser: SplitParser {
            onRead: line => root._handleEvent(line)
        }
    }

    function _handleEvent(line) {
        let message;
        try {
            message = JSON.parse(line);
        } catch (e) {
            log.warn("Failed to parse event:", e);
            return;
        }
        switch (message.event) {
        case "workspaces":
            workspaces = message.data;
            return;
        case "windows":
            windows = message.data;
            return;
        }
    }

    function action(name) {
        Proc.runCommand(null, ["umbriel", "msg", name], (output, exitCode) => {
            if (exitCode !== 0)
                log.warn("umbriel msg", name, "exited with", exitCode);
        }, 0);
    }
}
