pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/settings/ConfigProfiles.js" as Profiles
import "../DCommon/Common/settings/SpecUtil.js" as SpecUtil

Singleton {
    id: root
    readonly property var log: Log.scoped("ConfigProfileService")

    readonly property string profilesDir: Paths.strip(Paths.config) + "/profiles"

    property var profiles: []
    // Folder name -> { state: "ok" | "broken" | "missing", profile, text }
    property var _entries: ({})
    property var _views: ({})
    property var _folderIds: []
    property bool _folderReady: false
    property bool _scanned: false
    property bool _started: false
    property var _creating: ({})
    property var _deleting: ({})
    property bool _applying: false
    property bool _wantsDefault: false
    property string capturingId: ""
    property string screenshotTargetId: ""
    property var draft: null
    property string _pendingImport: ""
    readonly property var imageExtensions: ["jpg", "jpeg", "png", "bmp", "gif", "webp", "jxl", "avif", "heif", "exr", "svg"]
    readonly property var _groupLabels: ({
            "colors": I18n.tr("Theme"),
            "wallpaper": I18n.tr("Wallpaper"),
            "dark_mode": I18n.tr("Dark mode"),
            "app_theming": I18n.tr("App theming"),
            "interface_style": I18n.tr("Interface style"),
            "shadows": I18n.tr("Shadows"),
            "bar": I18n.tr("Bar"),
            "frame": I18n.tr("Frame"),
            "dock": I18n.tr("Dock"),
            "desktop_widgets": I18n.tr("Desktop widgets"),
            "control_center": I18n.tr("Control Center"),
            "dashboard": I18n.tr("Dashboard"),
            "displays": I18n.tr("Display assignment"),
            "fonts_motion": I18n.tr("Fonts & motion"),
            "icons": I18n.tr("Icons"),
            "cursor": I18n.tr("Cursor"),
            "time_weather": I18n.tr("Time & weather"),
            "lock_screen": I18n.tr("Lock screen"),
            "launcher": I18n.tr("Launcher"),
            "notifications": I18n.tr("Notifications"),
            "osd": I18n.tr("On-screen displays"),
            "sound_media": I18n.tr("Sound & media"),
            "plugins": I18n.tr("Plugins"),
            "general": I18n.tr("General")
        })
    readonly property var _categoryLabels: ({
            "theme": I18n.tr("Theme & colors"),
            "layout": I18n.tr("Layout"),
            "appearance": I18n.tr("Appearance"),
            "other": I18n.tr("Other")
        })

    readonly property bool ready: _scanned && SettingsData._hasLoaded && SessionData._hasLoaded && !SettingsData._parseError && !SessionData._parseError && !SettingsData._pluginParseError
    readonly property string activeProfileId: profiles.some(p => p.id === SessionData.activeConfigProfile) ? SessionData.activeConfigProfile : ""
    readonly property var activeProfile: find(activeProfileId)
    readonly property bool screenshotPending: screenshotTargetId !== "" && capturingId === ""
    // Users who never opened profiles have no pointer; the folder is only scanned once one is set or requested.
    readonly property bool _wanted: SessionData.activeConfigProfile !== "" || _wantsDefault

    signal liveChanged
    signal profileImported(string id)

    on_WantedChanged: _start()
    Component.onCompleted: _start()

    onReadyChanged: {
        if (ready && _wantsDefault)
            ensureDefault();
    }

    // The folder must exist before the model is pointed at it, or it never becomes Ready.
    function _start() {
        if (_started || !_wanted)
            return;
        _started = true;
        Proc.runCommand(null, ["mkdir", "-p", "--", profilesDir], (output, exitCode) => {
            if (exitCode !== 0) {
                root.log.warn("Failed to create", root.profilesDir, output);
                ToastService.showError(I18n.tr("Failed to save profile"), root.profilesDir);
                return;
            }
            folderModel.folder = Paths.toFileUrl(root.profilesDir);
        });
    }

    FolderListModel {
        id: folderModel
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        showHidden: false
        onCountChanged: root._scanFolder()
        onStatusChanged: root._scanFolder()
    }

    Component {
        id: profileView

        FileView {
            required property string profileId

            blockLoading: true
            blockWrites: true
            atomicWrites: true
            watchChanges: true
            printErrors: false
            onLoaded: root._loaded(profileId, text())
            onLoadFailed: error => root._loadFailed(profileId, error === FileViewError.FileNotFound, error)
            onFileChanged: reload()
            onSaveFailed: error => {
                root.log.warn("Failed to save", path, error);
                ToastService.showError(I18n.tr("Failed to save profile"), FileViewError.toString(error));
            }
        }
    }

    Connections {
        target: SettingsData
        function onSettingsSaved() {
            root.liveChanged();
            root._scheduleSync();
        }
    }

    Connections {
        target: SessionData
        function onSaved() {
            root.liveChanged();
            root._scheduleSync();
        }
    }

    Timer {
        id: syncTimer
        interval: 1000
        onTriggered: root._sync()
    }

    Timer {
        id: captureTimer
        interval: 250
        onTriggered: root._runCapture()
    }

    function _scanFolder() {
        if (folderModel.status !== FolderListModel.Ready)
            return;
        const names = [];
        for (let i = 0; i < folderModel.count; i++)
            names.push(folderModel.get(i, "fileName"));
        _setFolders(names);
    }

    // Ids end up in paths that are removed with rm -rf.
    function _validId(id) {
        return typeof id === "string" && /^[\w-]+$/.test(id);
    }

    // Registered before the path is set: a blocking load can already write (normalization) through it.
    function _createView(id) {
        const view = profileView.createObject(root, {
            "profileId": id
        });
        _views[id] = view;
        view.path = profilesDir + "/" + id + "/profile.json";
        return view;
    }

    function _removeView(id) {
        _views[id]?.destroy();
        delete _views[id];
        delete _entries[id];
    }

    function _setFolders(names) {
        for (const name of _folderIds) {
            if (!names.includes(name))
                _removeView(name);
        }
        for (const name of names) {
            if (!_views[name] && !_deleting[name])
                _createView(name);
        }
        _folderIds = names;
        _folderReady = true;
        _refresh();
    }

    function _refresh() {
        profiles = Object.values(_entries).filter(e => e.state === "ok").map(e => e.profile).sort((a, b) => (a.created || 0) - (b.created || 0) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
        _scanned = _folderReady && _folderIds.every(name => _entries[name] || _deleting[name]);
        if (_pendingImport && find(_pendingImport)) {
            const id = _pendingImport;
            _pendingImport = "";
            profileImported(id);
        }
    }

    function _parseProfile(id, text) {
        if (!_validId(id))
            throw new Error("invalid profile id");
        const data = JSON.parse(text);
        if (!data || typeof data !== "object" || Array.isArray(data))
            throw new Error("not a JSON object");
        if (data.version > 1)
            throw new Error("written by a newer shell (version " + data.version + ")");
        if (typeof data.name !== "string" || !data.name.trim())
            throw new Error("missing name");
        if (!Array.isArray(data.groups))
            throw new Error("missing groups");
        data.id = id;
        return data;
    }

    function _markBroken(id, text, message) {
        const prev = _entries[id];
        _entries[id] = {
            "state": "broken",
            "text": text
        };
        if (prev?.state === "broken" && prev.text === text)
            return;
        log.warn(id + "/profile.json is unreadable and stays untouched:", message);
        Qt.callLater(() => ToastService.showError(I18n.tr("Failed to parse %1").arg(id + "/profile.json"), message));
    }

    function _loaded(id, text) {
        let loaded;
        try {
            loaded = _parseProfile(id, text);
        } catch (e) {
            _markBroken(id, text, e.message || String(e));
            _refresh();
            return;
        }
        const prev = _entries[id];
        if (prev?.state === "ok" && SpecUtil.stableStringify(_fileForm(prev.profile)) === SpecUtil.stableStringify(_fileForm(loaded)))
            return;
        _entries[id] = {
            "state": "ok",
            "profile": loaded
        };
        _refresh();
        const migrated = Profiles.migrate(loaded, SettingsData.settingsConfigVersion, SessionData.sessionConfigVersion);
        if (migrated)
            _write(migrated);
    }

    function _loadFailed(id, notFound, error) {
        if (_creating[id])
            return;
        if (notFound)
            _entries[id] = {
                "state": "missing"
            };
        else
            _markBroken(id, null, FileViewError.toString(error));
        _refresh();
    }

    function _fileForm(profile) {
        const out = Object.assign({
            "version": 1
        }, profile);
        delete out.id;
        return out;
    }

    function _write(profile) {
        const id = profile?.id;
        if (!_validId(id) || _entries[id]?.state === "broken") {
            ToastService.showError(I18n.tr("Failed to save profile"));
            return false;
        }
        _entries[id] = {
            "state": "ok",
            "profile": profile
        };
        _refresh();
        if (_views[id]) {
            _views[id].setText(JSON.stringify(_fileForm(profile), null, 2));
            return true;
        }
        if (_creating[id])
            return true;
        _creating[id] = true;
        Proc.runCommand(null, ["mkdir", "-p", "--", profilesDir + "/" + id], (output, exitCode) => {
            const latest = root._entries[id]?.state === "ok" ? root._entries[id].profile : null;
            if (exitCode !== 0 || !latest) {
                delete root._creating[id];
                if (exitCode !== 0) {
                    root.log.warn("Failed to create profile folder:", id, output);
                    ToastService.showError(I18n.tr("Failed to save profile"), String(output || "").trim());
                }
                return;
            }
            if (!root._views[id])
                root._createView(id);
            delete root._creating[id];
            root._views[id].setText(JSON.stringify(root._fileForm(latest), null, 2));
        });
        return true;
    }

    function find(id) {
        return profiles.find(p => p.id === id) ?? null;
    }

    function _isNewer(profile) {
        return Profiles.isNewer(profile, SettingsData.settingsConfigVersion, SessionData.sessionConfigVersion);
    }

    function _current() {
        return {
            "settings": SettingsData.profileSettingsSnapshot(),
            "session": SessionData.profileValues(Profiles.sessionKeys(Profiles.GROUPS)),
            "pluginSettings": SettingsData.pluginSettings
        };
    }

    function _captureInto(profile, groups, current) {
        const data = Profiles.capture(groups, current.settings, current.session, current.pluginSettings);
        if (!data)
            return null;
        const out = {
            "id": profile.id,
            "name": profile.name,
            "groups": data.groups,
            "sync": !!profile.sync,
            "configVersion": SettingsData.settingsConfigVersion,
            "sessionConfigVersion": SessionData.sessionConfigVersion,
            "settings": data.settings,
            "session": data.session,
            "thumbnail": profile.thumbnail || "",
            "thumbnailUpdated": profile.thumbnailUpdated || 0,
            "created": profile.created || Date.now(),
            "updated": Date.now()
        };
        if (data.pluginSettings)
            out.pluginSettings = data.pluginSettings;
        return out;
    }

    function _sameData(a, b) {
        const data = p => SpecUtil.stableStringify([p.groups, p.configVersion, p.sessionConfigVersion, p.settings, p.session, p.pluginSettings ?? null]);
        return data(a) === data(b);
    }

    function _scheduleSync() {
        if (_applying || !ready || !activeProfile?.sync || _isNewer(activeProfile))
            return;
        syncTimer.restart();
    }

    function _sync() {
        if (!_applying && ready)
            _syncProfile(activeProfile);
    }

    function _syncProfile(profile) {
        if (!profile?.sync || _isNewer(profile))
            return;
        const next = _captureInto(profile, profile.groups, _current());
        if (next && !_sameData(profile, next))
            _write(next);
    }

    function ensureDefault() {
        if (!ready) {
            _wantsDefault = true;
            return;
        }
        _wantsDefault = false;
        if (Object.values(_entries).some(e => e.state !== "missing"))
            return;
        const created = _captureInto({
            "id": _generateId(),
            "name": I18n.tr("Default", "name of the first config profile"),
            "sync": true
        }, Profiles.GROUPS, _current());
        if (_write(created))
            SessionData.set("activeConfigProfile", created.id);
    }

    function groupLabel(id) {
        if (id === "compositor")
            return CompositorService.displayName;
        return _groupLabels[id] ?? id;
    }

    function categoryLabel(id) {
        return _categoryLabels[id] ?? id;
    }

    function _generateId() {
        return "profile_" + Date.now() + "_" + Math.random().toString(36).slice(2, 9);
    }

    function createProfile(name, groups, sync) {
        const trimmed = (name || "").trim();
        if (!ready || !trimmed)
            return "";
        const created = _captureInto({
            "id": draft?.id || _generateId(),
            "name": trimmed,
            "sync": sync ?? true,
            "thumbnail": draft?.thumbnail,
            "thumbnailUpdated": draft?.thumbnailUpdated
        }, groups, _current());
        if (!created || !_write(created))
            return "";
        draft = null;
        return created.id;
    }

    function updateProfile(id, name, groups, sync) {
        const profile = find(id);
        const trimmed = (name || "").trim();
        if (!ready || !profile || !trimmed)
            return false;
        let next;
        if (_isNewer(profile)) {
            const sameScope = SpecUtil.stableStringify(Profiles.normalize(groups)) === SpecUtil.stableStringify(Profiles.normalize(profile.groups));
            if (!sameScope || !!sync !== !!profile.sync)
                return false;
            next = Object.assign({}, profile, {
                "name": trimmed
            });
        } else {
            next = Profiles.rescope(profile, groups, _current(), SettingsData.settingsConfigVersion, SessionData.sessionConfigVersion);
            if (!next)
                return false;
            next.name = trimmed;
            next.sync = !!sync;
        }
        if (!_write(next))
            return false;
        if (next.sync && !profile.sync && id === activeProfileId)
            _syncProfile(next);
        return true;
    }

    function updateFromCurrent(id) {
        const profile = find(id);
        if (!ready || !profile || _isNewer(profile))
            return false;
        const next = _captureInto(profile, profile.groups, _current());
        return !!next && _write(next);
    }

    function deleteProfile(id) {
        if (!ready || !find(id) || id === activeProfileId)
            return false;
        if (screenshotTargetId === id)
            cancelScreenshot();
        _removeView(id);
        _deleting[id] = true;
        _refresh();
        Proc.runCommand(null, ["rm", "-rf", "--", profilesDir + "/" + id], (output, exitCode) => {
            delete root._deleting[id];
            if (exitCode !== 0) {
                root.log.warn("Failed to remove profile folder:", id, output);
                ToastService.showError(I18n.tr("Failed to delete profile", "toast title, config profile"));
                root._scanFolder();
                return;
            }
            ToastService.showInfo(I18n.tr("Profile deleted"));
        });
        return true;
    }

    function _isImageName(name) {
        return new RegExp("^preview\\.(" + imageExtensions.join("|") + ")$", "i").test(name || "");
    }

    function _removeImage(id, name) {
        if (!_validId(id) || !_isImageName(name) || _entries[id]?.state === "broken")
            return;
        if (find(id)?.thumbnail === name || (draft?.id === id && draft.thumbnail === name))
            return;
        Proc.runCommand(null, ["rm", "-f", "--", profilesDir + "/" + id + "/" + name], () => {});
    }

    function startDraft() {
        discardDraft();
        const id = _generateId();
        draft = {
            "id": id,
            "thumbnail": "",
            "thumbnailUpdated": 0
        };
        Proc.runCommand(null, ["mkdir", "-p", "--", profilesDir + "/" + id], (output, exitCode) => {
            if (exitCode !== 0)
                root.log.warn("Failed to create profile folder:", id, output);
        });
        _sweep();
        return id;
    }

    function discardDraft() {
        const old = draft;
        if (!old)
            return;
        if (screenshotTargetId === old.id)
            cancelScreenshot();
        draft = null;
        if (_validId(old.id) && (_entries[old.id]?.state ?? "missing") === "missing" && !_creating[old.id])
            Proc.runCommand(null, ["rm", "-rf", "--", profilesDir + "/" + old.id], () => {});
    }

    function _sweep() {
        if (!ready)
            return;
        Proc.runCommand(null, ["find", profilesDir, "-mindepth", "1", "-maxdepth", "1", "-type", "d", "!", "-exec", "test", "-e", "{}/profile.json", "-o", "-L", "{}/profile.json", ";", "-printf", "%f\\n"], (output, exitCode) => {
            if (exitCode !== 0 || !root.ready)
                return;
            const stale = output.split("\n").filter(name => root._validId(name) && root.draft?.id !== name && !root._creating[name] && !root._deleting[name] && (root._entries[name]?.state ?? "missing") === "missing");
            if (stale.length)
                Proc.runCommand(null, ["rm", "-rf", "--"].concat(stale.map(name => root.profilesDir + "/" + name)), () => {});
        });
    }

    function _hasTarget(id) {
        return !!id && (!!find(id) || draft?.id === id);
    }

    function _imageFailed(id, name, output) {
        log.warn("Failed to save profile image:", id, output);
        _removeImage(id, name);
        if (_hasTarget(id))
            ToastService.showError(I18n.tr("Failed to save profile"));
    }

    function _applyImage(id, name) {
        const fields = {
            "thumbnail": name,
            "thumbnailUpdated": Date.now()
        };
        const profile = find(id);
        let old = "";
        if (profile) {
            old = profile.thumbnail;
            if (!_write(Object.assign({}, profile, fields)))
                return false;
        } else if (draft?.id === id) {
            old = draft.thumbnail;
            draft = Object.assign({}, draft, fields);
        } else {
            _removeImage(id, name);
            return false;
        }
        if (old !== name)
            _removeImage(id, old);
        return true;
    }

    function setImageFromFile(id, path) {
        const ext = (String(path || "").match(/\.([^./]+)$/)?.[1] ?? "").toLowerCase();
        if (!ready || !_hasTarget(id) || !imageExtensions.includes(ext))
            return false;
        const name = "preview." + ext;
        Proc.runCommand(null, ["cp", "--remove-destination", "-T", "--", path, profilesDir + "/" + id + "/" + name], (output, exitCode) => {
            if (exitCode !== 0)
                root._imageFailed(id, name, output);
            else
                root._applyImage(id, name);
        });
        return true;
    }

    function startScreenshot(id) {
        if (!ready || screenshotTargetId || capturingId || !_hasTarget(id))
            return false;
        screenshotTargetId = id;
        return true;
    }

    function cancelScreenshot() {
        if (!capturingId)
            screenshotTargetId = "";
    }

    function captureScreenshot() {
        if (!screenshotTargetId || capturingId)
            return;
        capturingId = screenshotTargetId;
        captureTimer.restart();
    }

    function activate(id) {
        const target = find(id);
        if (!ready || _applying || !target || id === activeProfileId)
            return false;
        _applying = true;
        try {
            syncTimer.stop();
            _syncProfile(activeProfile);
            if (!_apply(target))
                return false;
            SessionData.set("activeConfigProfile", id);
        } finally {
            _applying = false;
            syncTimer.stop();
        }
        ToastService.showInfo(I18n.tr("Profile activated: %1").arg(target.name));
        return true;
    }

    function applyGroups(id, groups) {
        const target = find(id);
        if (!ready || _applying || !target || !Profiles.normalize(groups).some(g => target.groups.includes(g)))
            return false;
        _applying = true;
        let ok = false;
        try {
            ok = _apply(target, groups);
        } finally {
            _applying = false;
        }
        if (ok)
            _scheduleSync();
        return ok;
    }

    // Callers hold _applying.
    function _apply(target, groups) {
        const scoped = Profiles.scoped(target, groups);
        if (!SettingsData.applyProfileSettings(scoped.settings, scoped.settingsKeys)) {
            ToastService.showError(I18n.tr("Failed to apply profile"));
            return false;
        }
        if (Object.keys(scoped.session).length)
            SessionData.applyProfileValues(scoped.session);
        if (scoped.pluginSettings)
            _applyPluginSettings(scoped.pluginSettings);
        return true;
    }

    function compare(id) {
        const profile = find(id);
        return profile ? Profiles.diff(profile, _current()) : null;
    }

    // Plugins the profile doesn't know (installed after it was captured) keep their current settings.
    function _applyPluginSettings(stored) {
        const before = SettingsData.pluginSettings || {};
        SettingsData.pluginSettings = Object.assign(SpecUtil.cloneDef(before), SpecUtil.cloneDef(stored));
        SettingsData.savePluginSettings();
        for (const pluginId of Object.keys(stored)) {
            const wasEnabled = !!before[pluginId]?.enabled;
            if (!!stored[pluginId]?.enabled !== wasEnabled) {
                if (wasEnabled)
                    PluginService.disablePlugin(pluginId);
                else
                    PluginService.enablePlugin(pluginId);
            } else if (SpecUtil.stableStringify(before[pluginId]) !== SpecUtil.stableStringify(stored[pluginId])) {
                PluginService.pluginDataChanged(pluginId);
            }
        }
    }

    function exportProfile(id, path) {
        if (!ready || !find(id) || !path)
            return false;
        if (id === activeProfileId)
            _sync();
        Proc.runCommand(null, [Proc.dmsBin, "profile", "export", id, path], (output, exitCode) => {
            const out = String(output || "").trim();
            const saved = I18n.tr("Profile saved: %1").arg(path);
            if (exitCode !== 0)
                ToastService.showError(I18n.tr("Failed to export profile", "toast title, config profile archive"), out);
            else if (out)
                ToastService.showWarning(saved, out);
            else
                ToastService.showInfo(saved);
        }, 0, Proc.noTimeout);
        return true;
    }

    function importProfile(path) {
        if (!ready || !path)
            return false;
        _pendingImport = "";
        Proc.runCommand(null, [Proc.dmsBin, "profile", "import", path], (output, exitCode) => {
            const out = String(output || "").trim();
            if (exitCode !== 0 || !root._validId(out)) {
                ToastService.showError(I18n.tr("Failed to import profile", "toast title, config profile archive"), exitCode !== 0 ? out : "");
                return;
            }
            root._pendingImport = out;
            root._scanFolder();
        }, 0, Proc.noTimeout);
        return true;
    }

    function thumbnailSource(profile) {
        if (!_validId(profile?.id) || !_isImageName(profile.thumbnail))
            return "";
        return Paths.toFileUrl(profilesDir + "/" + profile.id + "/" + profile.thumbnail) + "?v=" + (profile.thumbnailUpdated || 0);
    }

    function _runCapture() {
        const id = capturingId;
        Proc.runCommand(null, [Proc.dmsBin, "screenshot", "full", "--no-clipboard", "--no-notify", "--cursor", "off", "-f", "jpg", "-q", "92", "-d", profilesDir + "/" + id, "--filename", "preview.jpg"], (output, exitCode) => root._finishCapture(id, exitCode === 0, output));
    }

    function _finishCapture(id, ok, output) {
        if (ok)
            _applyImage(id, "preview.jpg");
        else
            _imageFailed(id, "preview.jpg", output);
        capturingId = "";
        screenshotTargetId = "";
    }
}
