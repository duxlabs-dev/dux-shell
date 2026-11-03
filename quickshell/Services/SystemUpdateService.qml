pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "RepoMoveNotice.js" as RepoMoveNotice

Singleton {
    id: root

    property int refCount: 0
    // `Ref { modules: ["releases"] }` also holds the feed document; a plain Ref only keeps the daemon polling.
    property int releasesRefCount: 0
    readonly property bool pollWanted: refCount > 0 || SettingsData.updaterNotify

    function addRef(modules) {
        refCount++;
        if (modules.includes("releases"))
            releasesRefCount++;
    }

    function removeRef(modules) {
        refCount = Math.max(0, refCount - 1);
        if (modules.includes("releases"))
            releasesRefCount = Math.max(0, releasesRefCount - 1);
    }

    property bool sysupdateAvailable: false

    property var availableUpdates: []
    property var _rawUpdates: []
    property bool isChecking: false
    property bool isUpgrading: false
    property bool hasError: false
    property string errorMessage: ""
    property string errorHint: ""
    property string errorCode: ""
    property var backends: []
    property string distribution: ""
    property string distributionPretty: ""
    property string pkgManager: ""
    property bool distributionSupported: false
    property var recentLog: []
    property int intervalSeconds: 86400
    property int lastCheckUnix: 0
    property int nextCheckUnix: 0

    property string shellInstallMethod: "unknown"
    property string shellPackageName: ""
    property string shellChannel: "unknown"
    property string shellRunning: ""
    property string shellInstalled: ""
    property int shellGitBuild: 0
    property bool restartPending: false
    property bool rebootRecommended: false
    property var rebootPackages: []
    property var _rawShellUpdate: null
    // From the filtered list, so an AUR-off/ignored dms package doesn't advertise.
    readonly property var shellUpdate: _rawShellUpdate ? (availableUpdates.find(p => p.name === _rawShellUpdate.name) ?? null) : null
    // -1 while unknown (stable channel or no feed yet)
    property int commitsBehind: -1
    property var releases: null
    // Repo files, not URLs: what `dms migrate dux` would move.
    property var legacyRepos: []
    property string migrateCommand: "dms migrate dux"

    readonly property int updateCount: availableUpdates.length
    readonly property var systemUpdates: availableUpdates.filter(p => !shellUpdate || p.name !== shellUpdate.name)
    // The feed never flips this: DMS only updates through the package manager.
    readonly property bool shellUpdateAvailable: shellUpdate !== null
    readonly property string shellUpdateVersion: shellUpdate?.toVersion || ""
    // Notes follow the version the repo offers (or the running one), never the feed's newest tag.
    readonly property string notesVersion: (shellUpdateVersion || shellRunning).replace(/^v/, "")
    readonly property var notesRelease: {
        const list = releases?.releases ?? [];
        const mm = notesVersion.match(/^\d+\.\d+/)?.[0] ?? "";
        const match = list.find(r => r.version === notesVersion) ?? list.find(r => mm !== "" && (r.version === mm || r.version.startsWith(mm + "."))) ?? null;
        if (match || shellChannel === "stable")
            return match;
        // Git builds may carry no semver (Fedora: 0.0.git.N.sha) or run past the newest tag
        return list.find(r => !r.prerelease) ?? null;
    }
    readonly property bool shellManagedExternally: shellInstallMethod === "nix"
    readonly property bool helperAvailable: sysupdateAvailable && backends.length > 0
    readonly property bool useCustomCommand: SettingsData.updaterUseCustomCommand && (SettingsData.updaterCustomCommand || "").trim().length > 0

    // Arch repository packages must upgrade together.
    readonly property bool systemHoldsAllowed: !["pacman", "paru", "yay", "shelly"].includes(pkgManager)

    function canIgnorePackage(pkg) {
        if (!pkg)
            return false;
        if (pkgManager === "shelly")
            return pkg.repo === "flatpak";
        return systemHoldsAllowed || pkg.repo !== "system";
    }

    function isValidIgnoredName(name) {
        return /^[A-Za-z0-9@._+:\/-]+$/.test(name);
    }

    Connections {
        target: DMSService
        function onCapabilitiesReceived() {
            root.checkCapabilities();
        }
        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                root.checkCapabilities();
            } else {
                root.sysupdateAvailable = false;
                root._startupCheckDone = false;
            }
            Qt.callLater(() => root._maybeStartupCheck());
        }
        function onSysupdateStateUpdate(data) {
            root._applyState(data);
        }
    }

    Connections {
        target: SessionData
        function onLoaded() {
            root._maybeNotifyRepoMove();
        }
    }

    Connections {
        target: ShellVersionService
        function onSemverVersionChanged() {
            root._maybeNotifyRepoMove();
        }
    }

    Connections {
        target: SettingsData
        function onUpdaterCheckOnStartChanged() {
            Qt.callLater(() => root._maybeStartupCheck());
        }
        function onUpdaterAllowAURChanged() {
            root._refilter();
        }
        function onUpdaterIncludeFlatpakChanged() {
            root._refilter();
        }
        function onUpdaterIgnoredPackagesChanged() {
            root._refilter();
        }
        function on_HasLoadedChanged() {
            Qt.callLater(() => root._maybeStartupCheck());
        }
    }

    Component.onCompleted: {
        if (DMSService.dmsAvailable) {
            checkCapabilities();
        }
        Qt.callLater(() => root._maybeStartupCheck());
    }

    function checkCapabilities() {
        if (!DMSService.capabilities || !Array.isArray(DMSService.capabilities)) {
            sysupdateAvailable = false;
            Qt.callLater(() => root._maybeStartupCheck());
            return;
        }
        const has = DMSService.capabilities.includes("sysupdate");
        if (has && !sysupdateAvailable) {
            sysupdateAvailable = true;
            requestRepoStatus();
            if (pollWanted) {
                requestState();
                // The daemon persists its last check but not the interval; re-apply it on every fresh connection.
                setInterval(SettingsData.updaterIntervalSeconds);
            }
        } else if (!has) {
            sysupdateAvailable = false;
        }
        Qt.callLater(() => root._maybeStartupCheck());
    }

    function requestState() {
        if (!DMSService.isConnected || !sysupdateAvailable) {
            return;
        }
        DMSService.sysupdateGetState(resp => {
            if (resp && resp.result) {
                _applyState(resp.result);
            }
        });
    }

    function requestRepoStatus() {
        DMSService.sysupdateRepoStatus(resp => {
            const result = resp?.result;
            if (!result)
                return;
            root.legacyRepos = result.legacy || [];
            root.migrateCommand = result.command || "dms migrate dux";
            root._maybeNotifyRepoMove();
        });
    }

    function _maybeNotifyRepoMove() {
        if (_repoNoticeInFlight || !SessionData._hasLoaded)
            return;
        const current = ShellVersionService.semverVersion;
        if (!RepoMoveNotice.repoNoticeDue(legacyRepos, SessionData.repoMoveNoticeVersion, current))
            return;
        _repoNoticeInFlight = true;
        DMSService.notifySend({
            "summary": I18n.tr("Package repositories moved", "notification title, the DMS package repositories moved to a new owner"),
            "body": I18n.tr("Run %1 in a terminal.", "%1 is a shell command").arg(migrateCommand),
            "actionLabel": I18n.tr("Settings"),
            "actionArgs": ["ipc", "call", "settings", "openWith", "updater"]
        }, resp => {
            root._repoNoticeInFlight = false;
            if (!resp || resp.error)
                return;
            SessionData.set("repoMoveNoticeVersion", current);
        });
    }

    property bool _repoNoticeInFlight: false

    function _applyState(data) {
        if (!data) {
            return;
        }
        backends = data.backends || [];
        const systemBackend = backends.find(b => b.repo === "system" || b.repo === "ostree");
        pkgManager = systemBackend ? systemBackend.id : (backends.length > 0 ? backends[0].id : "");
        _rawUpdates = data.packages || [];
        availableUpdates = _filterUpdates(_rawUpdates);
        distribution = data.distro || "";
        distributionPretty = data.distroPretty || "";
        distributionSupported = (backends.length > 0);
        recentLog = data.recentLog || [];
        intervalSeconds = data.intervalSeconds ?? 86400;
        const checked = data.lastCheckUnix || 0;
        const freshCheck = _stateSeeded && checked > lastCheckUnix;
        _stateSeeded = true;
        lastCheckUnix = checked;
        nextCheckUnix = data.nextCheckUnix || 0;

        const shell = data.shell || {};
        shellInstallMethod = shell.installMethod || "unknown";
        shellPackageName = shell.packageName || "";
        shellChannel = shell.channel || "unknown";
        shellRunning = shell.running || "";
        shellInstalled = shell.installed || "";
        shellGitBuild = shell.gitBuild || 0;
        restartPending = shell.restartPending === true;
        const reboot = data.reboot || {};
        rebootRecommended = reboot.recommended === true;
        rebootPackages = reboot.packages || [];
        _rawShellUpdate = shell.updatePackage || null;
        commitsBehind = typeof shell.commitsBehind === "number" ? shell.commitsBehind : -1;

        const phase = data.phase || "idle";
        switch (phase) {
        case "refreshing":
            isChecking = true;
            isUpgrading = false;
            break;
        case "upgrading":
            isChecking = false;
            isUpgrading = true;
            break;
        default:
            isChecking = false;
            isUpgrading = false;
        }

        if (data.error) {
            hasError = true;
            errorMessage = data.error.message || "";
            errorCode = data.error.code || "";
            errorHint = data.error.hint || "";
        } else {
            hasError = false;
            errorMessage = "";
            errorCode = "";
            errorHint = "";
        }
        if (freshCheck)
            _maybeNotify();
    }

    function _packageMatchesIgnore(pkgName, ignored) {
        const split = s => {
            if (!s)
                return [s || "", ""];
            const idx = s.indexOf(":");
            if (idx === -1)
                return [s, ""];
            return [s.substring(0, idx), s.substring(idx + 1)];
        };
        const [pkgBase, pkgSlot] = split(pkgName);
        const [ignBase, ignSlot] = split(ignored);
        if (pkgSlot && ignSlot) {
            if (pkgBase === ignBase && pkgSlot === ignSlot)
                return true;
            return false;
        }
        if (ignSlot && !pkgSlot) {
            if (pkgBase === ignBase && ignSlot === "0")
                return true;
            return false;
        }
        if (pkgBase === ignBase)
            return true;
        return false;
    }

    function _isIgnored(pkg) {
        if (!pkg || !pkg.name)
            return false;
        const ignored = SettingsData.updaterIgnoredPackages || [];
        for (let i = 0; i < ignored.length; i++) {
            if (_packageMatchesIgnore(pkg.name, ignored[i]))
                return true;
        }
        return false;
    }

    function _filterUpdates(pkgs) {
        return (pkgs || []).filter(p => {
            if (!SettingsData.updaterAllowAUR && p.repo === "aur")
                return false;
            if (!SettingsData.updaterIncludeFlatpak && p.repo === "flatpak")
                return false;
            if (!canIgnorePackage(p))
                return true;
            return !_isIgnored(p);
        });
    }

    function _refilter() {
        availableUpdates = _filterUpdates(_rawUpdates);
    }

    // Only when the count grows past the last announcement.
    function _maybeNotify() {
        if (!SettingsData.updaterNotify || isChecking || isUpgrading)
            return;
        if (updateCount === 0) {
            if (SessionData.updaterNotifiedCount !== 0)
                SessionData.set("updaterNotifiedCount", 0);
            return;
        }
        if (updateCount <= SessionData.updaterNotifiedCount)
            return;
        const now = Math.floor(Date.now() / 1000);
        if (now - SessionData.updaterNotifiedUnix < SettingsData.updaterNotifyMinSeconds)
            return;
        if (_notifyInFlight)
            return;
        _notifyInFlight = true;
        const count = updateCount;
        DMSService.notifySend({
            "summary": count === 1 ? I18n.tr("%1 update", "singular, %1 is 1, available system update count").arg(count) : I18n.tr("%1 updates", "plural, %1 is a count of available system updates").arg(count),
            "body": I18n.tr("Software updates are ready to install.", "notification body when system updates are available"),
            "actionLabel": I18n.tr("Settings"),
            "actionArgs": ["ipc", "call", "settings", "openWith", "updater"]
        }, resp => {
            root._notifyInFlight = false;
            if (!resp || resp.error)
                return;
            SessionData.set("updaterNotifiedUnix", Math.floor(Date.now() / 1000));
            SessionData.set("updaterNotifiedCount", count);
        });
    }

    property bool _notifyInFlight: false
    // The first state after a connect is the persisted list, not a check that just ran.
    property bool _stateSeeded: false

    function ignorePackage(name) {
        if (!name)
            return false;
        if (pkgManager === "shelly" && !_rawUpdates.some(p => p.name === name && canIgnorePackage(p)))
            return false;
        const list = (SettingsData.updaterIgnoredPackages || []).slice();
        if (list.indexOf(name) !== -1)
            return true;
        list.push(name);
        SettingsData.set("updaterIgnoredPackages", list);
        return true;
    }

    function unignorePackage(name) {
        if (!name)
            return;
        const list = (SettingsData.updaterIgnoredPackages || []).filter(p => p !== name);
        SettingsData.set("updaterIgnoredPackages", list);
    }

    function checkForUpdates() {
        DMSService.sysupdateRefresh(false, null);
        if (releasesRefCount > 0)
            loadReleases(true);
    }

    function loadReleases(force) {
        if (!DMSService.isConnected || !sysupdateAvailable)
            return;
        DMSService.sysupdateReleases(force, resp => {
            // A late reply must not repopulate a feed the last Ref already dropped.
            if (root.releasesRefCount > 0 && resp && resp.result)
                root.releases = resp.result;
        });
    }

    function restartShell() {
        Quickshell.execDetached(["dms", "restart"]);
    }

    function runUpdates(opts) {
        const params = opts || {};
        params.ignored = SettingsData.updaterIgnoredPackages || [];
        if (useCustomCommand) {
            params.customCommand = SettingsData.updaterCustomCommand.trim();
            const termArgs = (SettingsData.updaterTerminalAdditionalParams || "").trim();
            if (termArgs.length > 0) {
                params.terminalArgs = termArgs.split(/\s+/);
            }
        }
        DMSService.sysupdateUpgrade(params, null);
    }

    function cancelUpdates() {
        DMSService.sysupdateCancel(null);
    }

    function setInterval(seconds) {
        DMSService.sysupdateSetInterval(seconds, null);
    }

    property bool _startupCheckDone: false

    function _maybeStartupCheck() {
        if (!pollWanted) {
            _startupCheckDone = false;
            return;
        }
        if (!SettingsData.updaterCheckOnStart)
            return;
        if (_startupCheckDone)
            return;
        if (!DMSService.isConnected || !sysupdateAvailable)
            return;
        _startupCheckDone = true;
        Qt.callLater(() => DMSService.sysupdateRefresh(false, null, true));
    }

    onPollWantedChanged: {
        if (!pollWanted)
            _startupCheckDone = false;
        _syncSubscription();
        Qt.callLater(() => root._syncAcquire());
        Qt.callLater(() => root._maybeStartupCheck());
    }
    onReleasesRefCountChanged: {
        if (releasesRefCount <= 0)
            releases = null;
        else if (releases === null)
            loadReleases(false);
    }
    onSysupdateAvailableChanged: {
        _syncAcquire();
        if (sysupdateAvailable && releasesRefCount > 0 && releases === null)
            loadReleases(false);
    }

    function _syncSubscription() {
        if (!pollWanted) {
            if (DMSService.activeSubscriptions.includes("sysupdate"))
                DMSService.removeSubscription("sysupdate");
            return;
        }
        DMSService.addSubscription("sysupdate");
        if (!sysupdateAvailable)
            return;
        requestState();
        setInterval(SettingsData.updaterIntervalSeconds);
    }

    property bool _acquired: false
    // Releasing the ref parks the daemon scheduler; its deadline is kept, so checks resume on AC.
    readonly property bool pausedOnBattery: SettingsData.updaterPauseOnBattery && BatteryService.batteryAvailable && !BatteryService.isPluggedIn
    onPausedOnBatteryChanged: _syncAcquire()

    function _syncAcquire() {
        const want = pollWanted && sysupdateAvailable && !pausedOnBattery;
        if (want === _acquired) {
            return;
        }
        _acquired = want;
        if (want) {
            DMSService.sysupdateAcquire(null);
            return;
        }
        DMSService.sysupdateRelease(null);
    }
}
