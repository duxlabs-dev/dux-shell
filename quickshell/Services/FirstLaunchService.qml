pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("FirstLaunchService")

    readonly property string configDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation)) + "/dms"
    readonly property string settingsPath: configDir + "/settings.json"
    readonly property string firstLaunchMarkerPath: configDir + "/.firstlaunch"

    property bool isFirstLaunch: false
    property bool checkComplete: false
    property bool greeterDismissed: false
    property int requestedStartPage: 0

    readonly property bool shouldShowGreeter: checkComplete && isFirstLaunch && !greeterDismissed

    signal greeterRequested
    signal greeterCompleted

    function showGreeter(startPage) {
        requestedStartPage = startPage || 0;
        greeterRequested();
    }

    function showWelcome() {
        showGreeter(0);
    }

    function showDoctor() {
        showGreeter(1);
    }

    Component.onCompleted: {
        checkFirstLaunch();
    }

    function checkFirstLaunch() {
        markerProbe.path = root.firstLaunchMarkerPath;
    }

    function _finishCheck(firstLaunch) {
        isFirstLaunch = firstLaunch;
        checkComplete = true;
        if (!firstLaunch)
            return;
        log.info("First launch detected, greeter will be shown");
        greeterRequested();
    }

    function markFirstLaunchComplete() {
        greeterDismissed = true;
        touchMarkerProcess.running = true;
        greeterCompleted();
    }

    function dismissGreeter() {
        greeterDismissed = true;
    }

    FileView {
        id: markerProbe
        path: ""
        printErrors: false
        onLoaded: root._finishCheck(false)
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                root._finishCheck(false);
                return;
            }
            settingsProbe.path = root.settingsPath;
        }
    }

    FileView {
        id: settingsProbe
        path: ""
        printErrors: false
        onLoaded: {
            log.info("Existing user detected, silently creating marker");
            touchMarkerProcess.running = true;
            root._finishCheck(false);
        }
        onLoadFailed: error => root._finishCheck(error === FileViewError.FileNotFound)
    }

    Process {
        id: touchMarkerProcess

        command: ["sh", "-c", "mkdir -p '" + configDir + "' && touch '" + firstLaunchMarkerPath + "'"]
        running: false

        onExited: exitCode => {
            if (exitCode === 0) {
                log.info("First launch marker created");
            } else {
                log.warn("Failed to create first launch marker");
            }
        }
    }
}
