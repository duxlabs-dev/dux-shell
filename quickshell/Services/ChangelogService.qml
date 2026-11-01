pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

// Welcome page, once per release line: hand-authored ChangelogContent (flip changelogEnabled
// once it's written for the line) with the feed's notes chained underneath.
Singleton {
    id: root

    // Point releases don't re-trigger it.
    readonly property string currentVersion: {
        const v = ShellVersionService.semverVersion.replace(/^v/, "");
        const m = v.match(/^\d+\.\d+/);
        return m ? m[0] : "";
    }
    readonly property bool changelogEnabled: true
    // A dotfile in the config dir, not session.json: the Nix home module can make session.json read-only
    readonly property string markerPath: currentVersion !== "" ? Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation)) + "/dms/.changelog-" + currentVersion : ""
    property bool markerChecked: false
    property bool markerSeen: false
    readonly property bool ready: FirstLaunchService.checkComplete && markerChecked

    property bool changelogDismissed: false
    property var release: null
    property bool releasePending: false

    readonly property bool shouldShowChangelog: ready && changelogEnabled && !changelogDismissed && !FirstLaunchService.isFirstLaunch && !markerSeen

    signal changelogRequested
    signal changelogCompleted

    onReadyChanged: {
        if (ready && FirstLaunchService.isFirstLaunch)
            markSeen();
    }

    onShouldShowChangelogChanged: {
        if (!shouldShowChangelog)
            return;
        changelogRequested();
        loadRelease();
    }

    // Never blocks the welcome page: the daemon may not be up yet.
    function loadRelease() {
        if (!SystemUpdateService.sysupdateAvailable) {
            releasePending = true;
            return;
        }
        releasePending = false;
        DMSService.sysupdateReleases(false, resp => {
            if (root.changelogDismissed)
                return;
            const list = resp?.result?.releases ?? [];
            root.release = list.find(r => r.version === root.currentVersion || (r.version || "").startsWith(root.currentVersion + ".")) ?? null;
        });
    }

    readonly property bool sysupdateAvailable: SystemUpdateService.sysupdateAvailable
    onSysupdateAvailableChanged: {
        if (sysupdateAvailable && releasePending)
            loadRelease();
    }

    function dismissChangelog() {
        changelogDismissed = true;
        release = null;
        releasePending = false;
        markSeen();
        changelogCompleted();
    }

    function markSeen() {
        if (markerSeen)
            return;
        markerSeen = true;
        marker.setText(currentVersion + "\n");
    }

    FileView {
        id: marker
        path: root.markerPath
        printErrors: false
        onLoaded: {
            root.markerSeen = true;
            root.markerChecked = true;
        }
        onLoadFailed: error => {
            root.markerSeen = error !== FileViewError.FileNotFound;
            root.markerChecked = true;
        }
    }
}
