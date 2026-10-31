pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Physical drives from the core's drives.list, polled only while something holds a Ref.
Singleton {
    id: root
    readonly property var log: Log.scoped("DriveService")

    property int refCount: 0

    property var drives: []
    property string smartctlPath: ""
    property string installCommand: ""
    property bool loaded: false

    readonly property bool polling: refCount > 0 && DMSService.isConnected && DMSService.capabilities.includes("drives")

    property bool _errorLogged: false

    function refresh() {
        DMSService.sendRequest("drives.list", null, response => {
            // The last reply may arrive after the final Ref went away
            if (!root.polling)
                return;
            if (response.error || !response.result) {
                if (!root._errorLogged)
                    root.log.warn("drives.list failed:", response.error || "empty result");
                root._errorLogged = true;
                return;
            }
            root._errorLogged = false;
            const drives = response.result.drives || [];
            if (JSON.stringify(drives) !== JSON.stringify(root.drives))
                root.drives = drives;
            root.smartctlPath = response.result.smartctl || "";
            root.installCommand = response.result.installCommand || "";
            root.loaded = true;
        });
    }

    // Runs the install command in the configured terminal and waits for Enter
    function install() {
        if (!installCommand)
            return;
        Quickshell.execDetached([SessionData.resolveTerminal() || "xterm", "-e", "sh", "-c", installCommand + "; read -r _"]);
    }

    onPollingChanged: {
        if (polling)
            return;
        drives = [];
        smartctlPath = "";
        installCommand = "";
        loaded = false;
        _errorLogged = false;
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.polling
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
