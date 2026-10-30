pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import "../../../Common/ConfigIncludeResolve.js" as ConfigIncludeResolve
import "../../../Common/OutputModel.js" as OutputModel

Singleton {
    id: root
    readonly property var log: Log.scoped("DisplayConfigState")

    readonly property bool hasOutputBackend: WlrOutputService.wlrOutputAvailable
    readonly property var wlrOutputs: WlrOutputService.outputs
    property var outputs: ({})
    property var savedOutputs: ({})
    property var savedParsedOutputs: ({})
    property var allOutputs: buildAllOutputsMap()

    readonly property ConfigInclude include: ConfigInclude {
        includeKind: "outputs"
        warningCategory: "display-config"
        onFixed: root.writeOutputsAfterIncludeFix()
    }
    readonly property var includeStatus: include.status
    readonly property bool readOnly: include.readOnly
    readonly property bool checkingInclude: include.checking
    readonly property bool fixingInclude: include.fixing

    property var pendingChanges: ({})
    property var pendingNiriChanges: ({})
    property var pendingHyprlandChanges: ({})
    property var originalNiriSettings: null
    property var originalHyprlandSettings: null
    property var originalOutputs: null
    property string originalDisplayNameMode: ""
    property bool formatChanged: originalDisplayNameMode !== "" && originalDisplayNameMode !== SettingsData.displayNameMode
    property bool hasPendingChanges: Object.keys(pendingChanges).length > 0 || Object.keys(pendingNiriChanges).length > 0 || Object.keys(pendingHyprlandChanges).length > 0 || formatChanged

    property bool validatingConfig: false
    property var _cancelOutputWrite: null
    property var aqueousPreview: null

    function outputFingerprint(outputs) {
        return OutputModel.outputFingerprint(outputs);
    }

    function outputHeads(outputs) {
        return OutputModel.outputHeads(outputs);
    }

    function outputHeadsMatch(candidate, actual, original) {
        return OutputModel.outputHeadsMatch(candidate, actual, original);
    }

    function freshAqueousOutputs(callback) {
        DMSService.sendRequest("wlroutput.getState", null, response => {
            callback(response.result?.outputs || null, response.error || "");
        }, 5000);
    }

    function aqueousDisplayError(message) {
        validatingConfig = false;
        validationError = AqueousService.errorMessage(message);
        ToastService.showError(I18n.tr("Error"), validationError, message);
    }

    function discardAqueousPreview() {
        if (validatingConfig)
            return;
        aqueousPreview = null;
        restoreDisplayNameMode();
        validationError = "";
        clearPendingChanges();
        WlrOutputService.requestState();
    }

    function previewAqueousOutputs(descriptions) {
        if (validatingConfig)
            return;
        if (!AqueousService.available) {
            aqueousDisplayError("unavailable: compositor state");
            return;
        }
        if (aqueousPreview) {
            observeAqueousPreview(aqueousPreview, descriptions, "");
            return;
        }
        const session = AqueousService.session;
        validatingConfig = true;
        AqueousConfigService.load((snapshot, error) => {
            if (!snapshot) {
                aqueousDisplayError(error);
                return;
            }
            freshAqueousOutputs((original, error) => {
                if (AqueousService.session !== session) {
                    aqueousDisplayError("conflict: compositor session changed");
                    return;
                }
                if (!original) {
                    aqueousDisplayError(error);
                    return;
                }
                const candidate = WlrOutputService.outputsConfigHeads(buildOutputsWithPendingChanges(), outputs);
                WlrOutputService.testConfiguration(candidate, (success, message) => {
                    if (AqueousService.session !== session) {
                        aqueousDisplayError("conflict: compositor session changed");
                        return;
                    }
                    if (!success) {
                        aqueousDisplayError(message);
                        return;
                    }
                    const preview = {
                        snapshot: snapshot,
                        original: original,
                        heads: candidate,
                        fingerprint: null,
                        session: session
                    };
                    aqueousPreview = preview;
                    WlrOutputService.applyConfiguration(candidate, (success, message) => {
                        observeAqueousPreview(preview, descriptions, success ? "" : message);
                    });
                });
            });
        });
    }

    function observeAqueousPreview(preview, descriptions, applyError) {
        validatingConfig = true;
        freshAqueousOutputs((actual, error) => {
            if (aqueousPreview !== preview)
                return;
            if (!actual || AqueousService.session !== preview.session || !outputHeadsMatch(preview.heads, actual, preview.original)) {
                if (actual && outputFingerprint(actual) === outputFingerprint(preview.original))
                    aqueousPreview = null;
                aqueousDisplayError(error || applyError || "conflict: display preview changed externally");
                return;
            }
            preview.fingerprint = outputFingerprint(actual);
            validatingConfig = false;
            validationError = applyError ? AqueousService.errorMessage(applyError) : "";
            changesApplied(descriptions);
        });
    }

    function finishAqueousPreview(keep) {
        if (validatingConfig || !aqueousPreview)
            return;
        const preview = aqueousPreview;
        validatingConfig = true;
        freshAqueousOutputs((actual, error) => {
            if (!actual || AqueousService.session !== preview.session || outputFingerprint(actual) !== preview.fingerprint) {
                aqueousDisplayError(error || "conflict: output configuration changed after preview");
                return;
            }
            if (keep) {
                let draft;
                try {
                    draft = AqueousConfigService.buildOutputsConfig(preview.snapshot, actual, preview.original);
                } catch (e) {
                    aqueousDisplayError(String(e));
                    return;
                }
                AqueousConfigService.apply(draft, (snapshot, message) => {
                    if (!snapshot) {
                        aqueousDisplayError(message);
                        return;
                    }
                    aqueousPreview = null;
                    if (formatChanged)
                        SettingsData.saveSettings();
                    clearPendingChanges();
                    freshAqueousOutputs((live, error) => {
                        validatingConfig = false;
                        if (!live || AqueousService.session !== preview.session || outputFingerprint(live) !== preview.fingerprint) {
                            aqueousDisplayError("conflict: configuration saved but live display state changed");
                            return;
                        }
                        changesConfirmed();
                    });
                });
                return;
            }
            WlrOutputService.applyConfiguration(outputHeads(preview.original), (success, message) => {
                if (!success) {
                    aqueousDisplayError(message);
                    return;
                }
                validatingConfig = false;
                aqueousPreview = null;
                restoreDisplayNameMode();
                clearPendingChanges();
                WlrOutputService.requestState();
                changesReverted();
            });
        });
    }
    property string validationError: ""

    property var currentOutputSet: []
    property string matchedProfile: ""
    property bool profilesLoading: false
    property var validatedProfiles: ({})
    property bool manualActivation: false
    property bool profilesReady: false
    property var monitorsCache: ({
            "version": 1,
            "configurations": []
        })
    property bool _monitorsSelfWrite: false
    // Last config entry that was applied (set by applyConfigEntry / confirmChanges).
    // Used to recover position, scale, and transform for disabled outputs that wlr
    // no longer reports a logical viewport for.
    property var lastAppliedEntry: null

    signal changesApplied(var changeDescriptions)
    signal changesConfirmed
    signal changesReverted
    signal profileActivated(string profileId, string profileName)
    signal profileSaved(string profileId, string profileName)
    signal profileDeleted(string profileId)
    signal profileError(string message)

    function buildCurrentOutputSet() {
        return OutputModel.currentOutputSet(outputs, SettingsData.displayNameMode, CompositorService.compositor);
    }

    function getOutputIdentifier(output, outputName) {
        return OutputModel.profileIdentifier(output, outputName, SettingsData.displayNameMode, CompositorService.compositor);
    }

    FileView {
        id: monitorsFile

        path: Paths.strip(Paths.config) + "/monitors.json"
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onLoaded: root._reparseMonitorsJson(monitorsFile.text())
        onLoadFailed: root._reparseMonitorsJson("")
        onFileChanged: {
            if (root._monitorsSelfWrite) {
                root._monitorsSelfWrite = false;
                return;
            }
            monitorsFile.reload();
        }
        onSaveFailed: error => {
            root._monitorsSelfWrite = false;
            log.warn("Failed to save monitors.json:", error);
        }
    }

    function _reparseMonitorsJson(text) {
        if (!text || !text.trim()) {
            monitorsCache = {
                "version": 1,
                "configurations": []
            };
        } else {
            try {
                const parsed = JSON.parse(text);
                if (!Array.isArray(parsed.configurations))
                    parsed.configurations = [];
                monitorsCache = parsed;
            } catch (e) {
                log.warn("Failed to parse monitors.json, using empty config");
                monitorsCache = {
                    "version": 1,
                    "configurations": []
                };
            }
        }
        _initializeProfiles();
    }

    function _initializeProfiles() {
        if (!profilesReady && _shouldMigrateLegacyProfiles()) {
            _migrateLegacyProfiles();
            return;
        }
        validateProfiles();
    }

    function _shouldMigrateLegacyProfiles() {
        if ((monitorsCache.configurations || []).length > 0)
            return false;
        const legacy = SettingsData.displayProfiles || {};
        for (const c in legacy) {
            if (Object.keys(legacy[c] || {}).length > 0)
                return true;
        }
        return false;
    }

    function _migrateLegacyProfiles() {
        const legacy = SettingsData.displayProfiles || {};
        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        const compositorDirs = {
            "niri": configDir + "/niri/dms/profiles",
            "hyprland": configDir + "/hypr/dms/profiles",
            "dwl": configDir + "/mango/dms/profiles",
            "mango": configDir + "/mango/dms/profiles"
        };
        const compositorExts = {
            "niri": ".kdl",
            "hyprland": ".conf",
            "dwl": ".conf",
            "mango": ".conf"
        };

        const tasks = [];
        for (const compositor in legacy) {
            const dir = compositorDirs[compositor];
            const ext = compositorExts[compositor];
            if (!dir || !ext)
                continue;
            for (const profileId in (legacy[compositor] || {})) {
                tasks.push({
                    compositor: compositor,
                    id: profileId,
                    name: legacy[compositor][profileId]?.name || "",
                    file: dir + "/" + profileId + ext
                });
            }
        }

        if (tasks.length === 0) {
            validateProfiles();
            return;
        }

        log.info("Migrating", tasks.length, "legacy display profiles to monitors.json");

        const migrated = [];
        let pending = tasks.length;
        const tryFinish = () => {
            pending--;
            if (pending > 0)
                return;
            const data = monitorsCache;
            data.configurations = (data.configurations || []).concat(migrated);
            writeMonitorsJson(data, success => {
                if (success) {
                    SettingsData.displayProfiles = {};
                    SettingsData.saveSettings();
                    log.info("Migrated", migrated.length, "of", tasks.length, "legacy profiles");
                } else {
                    log.warn("Failed to write migrated monitors.json");
                }
                validateProfiles();
            });
        };

        for (const task of tasks) {
            (function (t) {
                    Proc.runCommand("migrate-read-" + t.id, ["cat", t.file], (content, exitCode) => {
                        if (exitCode !== 0 || !content) {
                            log.warn("Skipping migration of profile", t.id, "- can't read", t.file);
                            tryFinish();
                            return;
                        }
                        let parsed;
                        switch (t.compositor) {
                        case "niri":
                            parsed = OutputModel.parseNiriOutputs(content);
                            break;
                        case "hyprland":
                            parsed = OutputModel.parseHyprlandConfProfile(content);
                            break;
                        case "dwl":
                        case "mango":
                            parsed = OutputModel.parseMangoOutputs(content);
                            break;
                        default:
                            parsed = {};
                        }
                        const niriSettings = SessionData.niriOutputSettings || {};
                        const hyprSettings = SessionData.hyprlandOutputSettings || {};
                        const profileOutputs = {};
                        for (const outputName in parsed) {
                            const od = parsed[outputName];
                            profileOutputs[outputName] = extractOutputNeutralConfig(outputName, od, niriSettings, hyprSettings);
                        }
                        if (Object.keys(profileOutputs).length > 0)
                            migrated.push({
                                "id": t.id,
                                "name": t.name,
                                "outputs": profileOutputs
                            });
                        tryFinish();
                    });
                })(task);
        }
    }

    function readMonitorsJson(callback) {
        callback(monitorsCache);
    }

    function writeMonitorsJson(data, callback) {
        monitorsCache = data;
        _monitorsSelfWrite = true;
        monitorsFile.setText(JSON.stringify(data, null, 2));
        if (callback)
            callback(true);
    }

    function publishActiveProfileModes() {
        const compositor = CompositorService.compositor;
        const profileId = SessionData.getActiveDisplayProfile(compositor);
        const profile = profileId ? validatedProfiles[profileId] : null;
        const outputs = profile?.outputs || {};
        const modes = {};

        for (const outputId in outputs) {
            const mode = outputs[outputId]?.mode;
            if (mode)
                modes[outputId] = {
                    "mode": mode
                };
        }

        SessionData.setActiveDisplayProfileModes(compositor, modes);
    }

    function generateProfileId() {
        return "profile_" + Date.now() + "_" + Math.random().toString(36).slice(2, 9);
    }

    function generateAutoProfileId(outputIdentifiers) {
        const fp = outputSetFingerprint(outputIdentifiers);
        let hash = 0;
        for (let i = 0; i < fp.length; i++) {
            hash = ((hash << 5) - hash) + fp.charCodeAt(i);
        }
        const hashStr = (hash >>> 0).toString(16);
        return "auto_" + hashStr;
    }

    function configFingerprint(configEntry) {
        return OutputModel.configFingerprint(configEntry);
    }

    function outputSetFingerprint(outputIdentifiers) {
        return OutputModel.outputSetFingerprint(outputIdentifiers);
    }

    function findConfigEntryById(data, id) {
        return OutputModel.findConfigEntryById(data, id);
    }

    function findConfigEntryByFingerprint(data, outputIdentifiers, autoOnly) {
        return OutputModel.findConfigEntryByFingerprint(data, outputIdentifiers, autoOnly);
    }

    function getProfileMonitorInclusion(profileId) {
        const profile = validatedProfiles[profileId];
        const profileOutputIds = new Set(Object.keys(profile?.outputs || {}));
        const result = {};
        for (const rawName in allOutputs) {
            const od = allOutputs[rawName];
            const id = od ? getOutputIdentifier(od, rawName) : rawName;
            result[rawName] = profileOutputIds.has(id);
        }
        return result;
    }

    function updateProfileMonitors(profileId, enabledRawNames) {
        readMonitorsJson(data => {
            const match = findConfigEntryById(data, profileId);
            if (!match) {
                profileError(I18n.tr("Profile not found"));
                return;
            }
            const profileName = match.entry.name;
            const existingOutputs = match.entry.outputs || {};
            const mergedAll = buildOutputsWithPendingChanges();
            const niriSettings = buildMergedNiriSettings();
            const hyprlandSettings = buildMergedHyprlandSettings();
            const newOutputConfigs = {};
            for (const rawName of enabledRawNames) {
                const od = mergedAll[rawName] || allOutputs[rawName];
                if (!od)
                    continue;
                const outputId = getOutputIdentifier(od, rawName);
                newOutputConfigs[outputId] = existingOutputs[outputId] || extractOutputNeutralConfig(rawName, od, niriSettings, hyprlandSettings);
            }
            data.configurations[match.index] = {
                "id": profileId,
                "name": profileName,
                "outputs": newOutputConfigs
            };
            writeMonitorsJson(data, success => {
                if (!success)
                    return;
                const updated = JSON.parse(JSON.stringify(validatedProfiles));
                updated[profileId] = {
                    id: profileId,
                    name: profileName,
                    outputs: newOutputConfigs
                };
                validatedProfiles = updated;
                matchedProfile = findMatchingProfile();
                publishActiveProfileModes();
                profileSaved(profileId, profileName);
            });
        });
    }

    function extractOutputNeutralConfig(outputName, outputData, niriSettings, hyprlandSettings) {
        return OutputModel.outputNeutralConfig(outputName, outputData, niriSettings, hyprlandSettings, SettingsData.displayNameMode, CompositorService.compositor);
    }

    function profileKeyMatchesOutput(outputId, output, name) {
        return OutputModel.profileKeyMatchesOutput(outputId, output, name, SettingsData.displayNameMode, CompositorService.compositor);
    }

    function generateOutputsDataFromConfig(configEntry) {
        return OutputModel.outputsDataFromConfigEntry(configEntry, outputs, SettingsData.displayNameMode, CompositorService.compositor);
    }

    function getNiriSettingsFromConfig(configEntry) {
        const result = {};
        for (const outputId in (configEntry.outputs || {})) {
            const cfg = configEntry.outputs[outputId];
            const settings = Object.assign({}, cfg.niri || {});
            if (cfg.disabled)
                settings.disabled = true;
            if (Object.keys(settings).length > 0)
                result[outputId] = settings;
        }
        return result;
    }

    function getHyprlandSettingsFromConfig(configEntry) {
        const result = {};
        for (const outputId in (configEntry.outputs || {})) {
            const cfg = configEntry.outputs[outputId];
            const settings = Object.assign({}, cfg.hyprland || {});
            if (cfg.disabled)
                settings.disabled = true;
            if (Object.keys(settings).length > 0)
                result[outputId] = settings;
        }
        return result;
    }

    function backendSettingsFromConfig(configEntry) {
        switch (CompositorService.compositor) {
        case "niri":
            return getNiriSettingsFromConfig(configEntry);
        case "hyprland":
            return getHyprlandSettingsFromConfig(configEntry);
        default:
            return null;
        }
    }

    function backendMergedSettings() {
        switch (CompositorService.compositor) {
        case "niri":
            return buildMergedNiriSettings();
        case "hyprland":
            return buildMergedHyprlandSettings();
        default:
            return null;
        }
    }

    function ensureEnabledOutput(configEntry) {
        return OutputModel.ensureEnabledOutput(configEntry, outputs, SettingsData.displayNameMode, CompositorService.compositor);
    }

    function profileOutputIsReal(outputId) {
        return OutputModel.profileOutputIsReal(outputId, outputs, SettingsData.displayNameMode, CompositorService.compositor);
    }

    function applyConfigEntry(configEntry, configId, profileName, isManual) {
        if (readOnly) {
            if (isManual) {
                profilesLoading = false;
                manualActivation = false;
                profileError(I18n.tr("Hyprland conf mode is read-only in Settings"));
            }
            include.showReadOnlyWarning();
            return;
        }
        const onWriteFailed = () => {
            if (isManual) {
                profilesLoading = false;
                manualActivation = false;
                profileError(I18n.tr("Failed to apply profile"));
            }
        };

        ensureEnabledOutput(configEntry);
        if (!Object.keys(configEntry.outputs || {}).some(k => profileOutputIsReal(k))) {
            log.warn("Profile", configId, "has no real outputs, not applying");
            onWriteFailed();
            return;
        }
        // Capture the entry being applied so disabled-output settings fields can read
        // scale/position/transform back even when wlr reports no logical viewport.
        root.lastAppliedEntry = JSON.parse(JSON.stringify(configEntry));
        const outputsData = generateOutputsDataFromConfig(configEntry);
        const onWriteSuccess = () => {
            SessionData.setActiveDisplayProfile(CompositorService.compositor, configId);
            publishActiveProfileModes();
            if (isManual) {
                profilesLoading = false;
                profileActivated(configId, profileName);
                manualActivationTimer.restart();
            }
            WlrOutputService.requestState();
        };

        backendWriteOutputsConfig(outputsData, backendSettingsFromConfig(configEntry), success => {
            if (success)
                onWriteSuccess();
            else
                onWriteFailed();
        });
    }

    function validateProfiles() {
        log.info("Validating profiles against current outputs...");
        readMonitorsJson(data => {
            const validated = {};
            let dirty = false;
            for (const entry of (data.configurations || [])) {
                const fp = configFingerprint(entry);
                if (!fp)
                    continue;
                if (!entry.id) {
                    entry.id = generateProfileId();
                    dirty = true;
                }
                if (ensureEnabledOutput(entry))
                    dirty = true;
                validated[entry.id] = {
                    id: entry.id,
                    name: entry?.name || "",
                    outputs: entry.outputs
                };
            }
            if (dirty)
                writeMonitorsJson(data, null);
            validatedProfiles = validated;
            matchedProfile = findMatchingProfile();
            publishActiveProfileModes();
            if (!profilesReady) {
                profilesReady = true;
                applyAutoConfig();
            }
        });
    }

    function findMatchingProfile() {
        const currentKey = currentOutputSet.join("+");
        for (const id in validatedProfiles) {
            const p = validatedProfiles[id];
            if (p.name === "")
                continue;
            if (Object.keys(p.outputs || {}).sort().join("+") === currentKey)
                return id;
        }
        return "";
    }

    function createProfile(profileName) {
        const outputConfigs = buildCurrentOutputConfigs();
        const id = generateProfileId();

        profilesLoading = true;
        readMonitorsJson(data => {
            data.configurations.push({
                "id": id,
                "name": profileName,
                "outputs": outputConfigs
            });

            writeMonitorsJson(data, success => {
                profilesLoading = false;
                if (!success) {
                    profileError(I18n.tr("Failed to save profile"));
                    return;
                }
                const updated = JSON.parse(JSON.stringify(validatedProfiles));
                updated[id] = {
                    id: id,
                    name: profileName,
                    outputs: outputConfigs
                };
                validatedProfiles = updated;
                currentOutputSet = buildCurrentOutputSet();
                matchedProfile = findMatchingProfile();
                SessionData.setActiveDisplayProfile(CompositorService.compositor, id);
                publishActiveProfileModes();
                profileSaved(id, profileName);
            });
        });
    }

    function renameProfile(profileId, newName) {
        readMonitorsJson(data => {
            const match = findConfigEntryById(data, profileId);
            if (!match) {
                profileError(I18n.tr("Profile not found"));
                return;
            }
            match.entry.name = newName;
            data.configurations[match.index] = match.entry;
            writeMonitorsJson(data, success => {
                if (!success)
                    return;
                const updated = JSON.parse(JSON.stringify(validatedProfiles));
                if (updated[profileId])
                    updated[profileId].name = newName;
                validatedProfiles = updated;
            });
        });
    }

    function deleteProfile(profileId) {
        const compositor = CompositorService.compositor;
        const isActive = SessionData.getActiveDisplayProfile(compositor) === profileId;

        profilesLoading = true;
        readMonitorsJson(data => {
            const match = findConfigEntryById(data, profileId);
            if (match)
                data.configurations.splice(match.index, 1);
            writeMonitorsJson(data, success => {
                profilesLoading = false;
                SettingsData.removeDisplayProfile(compositor, profileId);
                if (isActive) {
                    SessionData.setActiveDisplayProfile(compositor, "");
                    backendWriteOutputsConfig(allOutputs);
                }
                const updated = JSON.parse(JSON.stringify(validatedProfiles));
                delete updated[profileId];
                validatedProfiles = updated;
                matchedProfile = findMatchingProfile();
                publishActiveProfileModes();
                profileDeleted(profileId);
            });
        });
    }

    function activateProfile(profileId) {
        manualActivation = true;
        profilesLoading = true;
        readMonitorsJson(data => {
            const match = findConfigEntryById(data, profileId);
            if (!match) {
                profilesLoading = false;
                manualActivation = false;
                profileError(I18n.tr("Profile not found in %1", "display profile error, %1 is the profiles file").arg("monitors.json"));
                return;
            }
            applyConfigEntry(match.entry, profileId, match.entry.name || profileId, true);
        });
    }

    Timer {
        id: manualActivationTimer
        interval: 2000
        onTriggered: root.manualActivation = false
    }

    Timer {
        id: autoSelectDebounceTimer
        interval: 400
        onTriggered: {
            if (root.hasPendingChanges)
                return;
            root.applyAutoConfig();
        }
    }

    function configEntryMatchesLiveLayout(configEntry) {
        return OutputModel.configEntryMatchesLiveLayout(configEntry, outputs, SettingsData.displayNameMode, CompositorService.compositor);
    }

    function profileEnabledOutputsConnected(profile) {
        const connected = new Set(currentOutputSet);
        const cfg = profile.outputs || {};
        return Object.keys(cfg).every(id => cfg[id].disabled || connected.has(id));
    }

    function profileCoversConnectedOutputs(profile) {
        const cfg = profile.outputs || {};
        // Hyprland adds a make/model-less FALLBACK head once the last enabled output is gone
        return currentOutputSet.filter(id => profileOutputIsReal(id)).every(id => id in cfg);
    }

    function fallbackFromDisconnectedProfile() {
        const activeId = SessionData.getActiveDisplayProfile(CompositorService.compositor);
        const active = validatedProfiles[activeId];
        if (!active?.name || profileEnabledOutputsConnected(active))
            return;
        const fallbackId = Object.keys(validatedProfiles).find(id => {
            const p = validatedProfiles[id];
            return p.name && profileEnabledOutputsConnected(p) && profileCoversConnectedOutputs(p);
        });
        if (!fallbackId)
            return;
        log.info("Profile", activeId, "lost an output, falling back to", fallbackId);
        activateProfile(fallbackId);
    }

    function applyAutoConfig() {
        if (!profilesReady || manualActivation || !currentOutputSet.length)
            return;
        if (!SettingsData.displayProfileAutoSelect) {
            fallbackFromDisconnectedProfile();
            return;
        }

        readMonitorsJson(data => {
            const match = findConfigEntryByFingerprint(data, currentOutputSet, false);
            if (match) {
                if (configEntryMatchesLiveLayout(match.entry)) {
                    SessionData.setActiveDisplayProfile(CompositorService.compositor, match.entry.id);
                    return;
                }
                applyConfigEntry(match.entry, match.entry.id, "", false);
                return;
            }

            const outputConfigs = buildCurrentOutputConfigs();
            const id = generateAutoProfileId(currentOutputSet);
            const entry = {
                "id": id,
                "name": "",
                "outputs": outputConfigs
            };
            ensureEnabledOutput(entry);
            const existingIdx = data.configurations.findIndex(c => c.id === id);
            if (existingIdx >= 0)
                data.configurations[existingIdx] = entry;
            else
                data.configurations.push(entry);
            writeMonitorsJson(data, success => {
                if (!success)
                    return;
                const updated = JSON.parse(JSON.stringify(validatedProfiles));
                updated[id] = {
                    id: id,
                    name: "",
                    outputs: outputConfigs
                };
                validatedProfiles = updated;
                matchedProfile = "";
                const match = findConfigEntryById(data, id);
                if (match)
                    applyConfigEntry(match.entry, id, "", false);
            });
        });
    }

    function buildCurrentOutputConfigs() {
        const mergedAll = buildOutputsWithPendingChanges();
        const niriSettings = buildMergedNiriSettings();
        const hyprlandSettings = buildMergedHyprlandSettings();
        const outputConfigs = {};
        for (const name in outputs) {
            const od = mergedAll[name];
            if (od)
                outputConfigs[getOutputIdentifier(od, name)] = extractOutputNeutralConfig(name, od, niriSettings, hyprlandSettings);
        }
        return outputConfigs;
    }

    function deleteDisconnectedOutput(outputName) {
        if (outputs[outputName]?.connected)
            return;

        const updated = JSON.parse(JSON.stringify(savedOutputs));
        delete updated[outputName];
        savedOutputs = updated;

        const mergedOutputs = {};
        for (const name in outputs)
            mergedOutputs[name] = outputs[name];
        for (const name in updated)
            mergedOutputs[name] = updated[name];

        backendWriteOutputsConfig(mergedOutputs);
    }

    function buildAllOutputsMap() {
        const result = {};
        for (const name in savedOutputs) {
            result[name] = Object.assign({}, savedOutputs[name], {
                "connected": false
            });
        }
        for (const name in outputs) {
            const entry = JSON.parse(JSON.stringify(outputs[name]));
            entry.connected = true;
            // For disabled outputs wlr reports scale=0 (no logical viewport).
            // Overlay scale/position/transform from the last applied profile so
            // the settings UI can display meaningful values.
            if (!(entry.logical?.scale > 0)) {
                const profileCfg = getProfileOutputConfig(name);
                if (profileCfg) {
                    if (!entry.logical)
                        entry.logical = {};
                    entry.logical.scale = profileCfg.scale ?? 1.0;
                    entry.logical.x = profileCfg.position?.x ?? entry.logical.x ?? 0;
                    entry.logical.y = profileCfg.position?.y ?? entry.logical.y ?? 0;
                    if (profileCfg.transform)
                        entry.logical.transform = profileCfg.transform;
                } else if (entry.logical) {
                    entry.logical.scale = entry.logical.scale || 1.0;
                }
            }
            result[name] = entry;
        }
        return result;
    }

    function getProfileOutputConfig(outputName) {
        const sourceEntry = lastAppliedEntry || (matchedProfile ? validatedProfiles[matchedProfile] : null);
        if (!sourceEntry)
            return null;
        const cfgOutputs = sourceEntry.outputs || {};
        const outputId = getOutputIdentifier(outputs[outputName] || {}, outputName);
        return Object.entries(cfgOutputs).find(([key]) => key === outputId)?.[1] ?? null;
    }

    onOutputsChanged: {
        allOutputs = buildAllOutputsMap();
        const newOutputSet = buildCurrentOutputSet();
        if (JSON.stringify(newOutputSet) === JSON.stringify(currentOutputSet))
            return;
        // Physical output set changed — pending tweaks belong to the previous setup
        if (hasPendingChanges)
            clearPendingChanges();
        currentOutputSet = newOutputSet;
        autoSelectDebounceTimer.restart();
    }
    onSavedOutputsChanged: allOutputs = buildAllOutputsMap()
    onLastAppliedEntryChanged: allOutputs = buildAllOutputsMap()

    Connections {
        target: WlrOutputService
        function onStateChanged() {
            root.outputs = root.buildOutputsMap();
            root.reloadSavedOutputs();
        }
    }

    Connections {
        target: HyprlandService
        function onMonitorLayoutChanged() {
            root.outputs = root.buildOutputsMap();
        }
    }

    Connections {
        target: CompositorService
        function onCompositorChanged() {
            root.include.check();
            root.publishActiveProfileModes();
        }
    }

    Connections {
        target: SessionData
        function onActiveDisplayProfileChanged() {
            root.publishActiveProfileModes();
        }
    }

    Connections {
        target: NiriService
        enabled: CompositorService.isNiri
        function onConfigReloaded() {
            root.include.check();
        }
    }

    Component.onCompleted: {
        outputs = buildOutputsMap();
        reloadSavedOutputs();
    }

    function reloadSavedOutputs() {
        const outputsFile = outputsConfigFile();
        if (!outputsFile) {
            savedOutputs = {};
            savedParsedOutputs = {};
            return;
        }

        Proc.runCommand("load-saved-outputs", ["cat", outputsFile], (content, exitCode) => {
            if (exitCode !== 0 || !content.trim()) {
                savedOutputs = {};
                savedParsedOutputs = {};
                return;
            }
            const parsed = parseOutputsConfig(content);
            savedParsedOutputs = parsed;
            const filtered = filterDisconnectedOnly(parsed);
            savedOutputs = filtered;

            if (CompositorService.isHyprland) {
                initHyprlandSettingsFromConfig(parsed);
                syncHyprlandDisabledFromConfig(parsed);
            }
            if (CompositorService.isNiri) {
                syncNiriVrrFromConfig(parsed);
                syncNiriDisabledFromConfig(parsed);
            }
        });
    }

    function initHyprlandSettingsFromConfig(parsedOutputs) {
        const importedFields = ["colorManagement", "bitdepth", "sdrBrightness", "sdrSaturation", "supportsWideColor", "supportsHdr", "sdrEotf", "icc", "sdrMinLuminance", "sdrMaxLuminance", "minLuminance", "maxLuminance", "maxAvgLuminance"];
        const current = JSON.parse(JSON.stringify(SessionData.hyprlandOutputSettings));
        let changed = false;

        for (const outputName in parsedOutputs) {
            const settings = parsedOutputs[outputName]?.hyprlandSettings;
            if (!settings)
                continue;

            const entry = current[outputName] ?? {};
            let imported = false;
            for (const field of importedFields) {
                if (settings[field] === undefined || entry[field] !== undefined)
                    continue;
                entry[field] = settings[field];
                imported = true;
            }
            if (!imported)
                continue;

            current[outputName] = entry;
            changed = true;
        }

        if (changed) {
            SessionData.hyprlandOutputSettings = current;
            SessionData.saveSettings();
        }
    }

    function syncNiriVrrFromConfig(parsedOutputs) {
        for (const outputName in parsedOutputs) {
            const output = parsedOutputs[outputName];
            const current = SessionData.getNiriOutputSetting(outputName, "vrrOnDemand", false);
            const fromConfig = output.vrr_on_demand ?? false;
            if (current === fromConfig)
                continue;
            SessionData.setNiriOutputSetting(outputName, "vrrOnDemand", fromConfig || undefined);
        }
    }

    function syncHyprlandDisabledFromConfig(parsedOutputs) {
        const current = JSON.parse(JSON.stringify(SessionData.hyprlandOutputSettings));
        let changed = false;
        for (const outputName in parsedOutputs) {
            const settings = parsedOutputs[outputName]?.hyprlandSettings;
            const fromConfig = settings?.disabled ?? false;
            const stored = current[outputName]?.disabled ?? false;
            if (fromConfig === stored)
                continue;
            if (!current[outputName])
                current[outputName] = {};
            if (fromConfig)
                current[outputName].disabled = true;
            else
                delete current[outputName].disabled;
            changed = true;
        }
        if (changed) {
            SessionData.hyprlandOutputSettings = current;
            SessionData.saveSettings();
        }
    }

    function syncNiriDisabledFromConfig(parsedOutputs) {
        for (const outputName in parsedOutputs) {
            const output = parsedOutputs[outputName];
            const fromConfig = output.disabled ?? false;
            const current = SessionData.getNiriOutputSetting(outputName, "disabled", false);
            if (current === fromConfig)
                continue;
            SessionData.setNiriOutputSetting(outputName, "disabled", fromConfig || undefined);
        }
    }

    function filterDisconnectedOnly(parsedOutputs) {
        return OutputModel.filterDisconnectedOnly(parsedOutputs, outputs, SettingsData.displayNameMode, CompositorService.compositor);
    }

    function parseOutputsConfig(content) {
        switch (CompositorService.compositor) {
        case "niri":
            return OutputModel.parseNiriOutputs(content);
        case "hyprland":
            return OutputModel.parseHyprlandOutputs(content);
        case "mango":
            return OutputModel.parseMangoOutputs(content);
        default:
            return {};
        }
    }

    function outputsConfigFile() {
        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        const paths = ConfigIncludeResolve.includePaths("outputs", CompositorService.compositor, configDir);
        return paths ? paths.fragmentFiles[0] : "";
    }

    function fixOutputsInclude() {
        include.fix();
    }

    function writeOutputsAfterIncludeFix() {
        const liveOutputs = buildOutputsMap();
        if (Object.keys(liveOutputs).length > 0) {
            outputs = liveOutputs;
            include.fixing = true;
            backendWriteOutputsConfig(liveOutputs, backendMergedSettings(), success => {
                include.fixing = false;
                if (!success)
                    ToastService.showError(I18n.tr("Display setup failed"), I18n.tr("Failed to write outputs config."), "", "display-config");
                include.check();
                WlrOutputService.requestState();
            });
            return;
        }
        include.check();
        WlrOutputService.requestState();
    }

    function buildOutputsMap() {
        const liveMonitors = {};
        for (const output of wlrOutputs) {
            const live = HyprlandService.liveMonitor(output.name);
            if (!live)
                continue;
            liveMonitors[output.name] = {
                "x": live.x,
                "y": live.y,
                "scale": live.scale,
                "transformIndex": live.lastIpcObject?.transform ?? 0,
                "hardware": OutputModel.hyprlandHardware(live.lastIpcObject)
            };
        }
        return OutputModel.outputsFromWlr(wlrOutputs, liveMonitors);
    }

    function backendFetchOutputs() {
        WlrOutputService.requestState();
    }

    function backendWriteOutputsConfig(outputsData, settingsOrCallback, maybeCallback) {
        const settings = typeof settingsOrCallback === "function" ? null : settingsOrCallback;
        const callback = typeof settingsOrCallback === "function" ? settingsOrCallback : maybeCallback;
        const hasExplicitSettings = settings !== null && settings !== undefined;

        function finish(success) {
            if (callback)
                callback(success);
        }

        switch (CompositorService.compositor) {
        case "niri":
            {
                const niriSettings = hasExplicitSettings ? settings : buildMergedNiriSettings();
                NiriService.generateOutputsConfig(outputsData, niriSettings, success => {
                    if (!success) {
                        finish(false);
                        return;
                    }
                    reloadAndApplyNiriLiveOutputsConfig(outputsData, niriSettings, finish);
                });
                break;
            }
        case "hyprland":
            {
                if (readOnly) {
                    include.showReadOnlyWarning();
                    finish(false);
                    return;
                }
                const hyprlandSettings = hasExplicitSettings ? settings : buildMergedHyprlandSettings();
                HyprlandService.generateOutputsConfig(outputsData, hyprlandSettings, finish);
                break;
            }
        case "mango":
            MangoService.generateOutputsConfig(outputsData, finish);
            break;
        default:
            {
                if (_cancelOutputWrite)
                    _cancelOutputWrite();
                let completed = false;
                const complete = success => {
                    if (completed)
                        return;
                    completed = true;
                    root._cancelOutputWrite = null;
                    finish(success);
                };
                _cancelOutputWrite = () => complete(false);
                WlrOutputService.applyOutputsConfig(outputsData, outputs, complete);
                break;
            }
        }
    }

    function getLiveNiriOutputName(outputName, outputData) {
        if (outputs[outputName])
            return outputName;
        const targetId = getNiriOutputIdentifier(outputData, outputName);
        for (const liveName in outputs) {
            if (getNiriOutputIdentifier(outputs[liveName], liveName) === targetId)
                return liveName;
        }
        return "";
    }

    function applyNiriLiveOutputsConfig(outputsData, niriSettings, callback) {
        const names = Object.keys(outputsData || {});
        let pending = 0;
        let failed = false;

        function done(success) {
            if (callback)
                callback(success);
        }

        for (const outputName of names) {
            const output = outputsData[outputName];
            if (!output)
                continue;
            const liveName = getLiveNiriOutputName(outputName, output);
            if (!liveName)
                continue;

            const identifier = getNiriOutputIdentifier(output, outputName);
            const settings = niriSettings?.[outputName] || niriSettings?.[identifier] || {};
            const config = {};

            if (settings.disabled === true)
                config.disabled = true;
            else if (settings.disabled === false)
                config.disabled = false;

            if (!config.disabled) {
                if (output.current_mode !== undefined && output.modes && output.modes[output.current_mode]) {
                    const mode = output.modes[output.current_mode];
                    config.mode = mode.width + "x" + mode.height + "@" + (mode.refresh_rate / 1000).toFixed(3);
                }
                if (output.logical) {
                    config.scale = output.logical.scale ?? 1.0;
                    config.position = {
                        "x": output.logical.x ?? 0,
                        "y": output.logical.y ?? 0
                    };
                    config.transform = OutputModel.niriTransform(output.logical.transform);
                }
                if (settings.vrrOnDemand)
                    config.vrrOnDemand = settings.vrrOnDemand;
                else if (output.vrr_enabled !== undefined)
                    config.vrr = output.vrr_enabled;
            }

            pending++;
            NiriService.applyOutputConfig(liveName, config, success => {
                failed = failed || !success;
                pending--;
                if (pending === 0) {
                    WlrOutputService.requestState();
                    done(!failed);
                }
            });
        }

        if (pending === 0)
            done(true);
    }

    function reloadAndApplyNiriLiveOutputsConfig(outputsData, niriSettings, callback) {
        Proc.runCommand("niri-reload-output-config", ["niri", "msg", "action", "load-config-file"], () => {
            applyNiriLiveOutputsConfig(outputsData, niriSettings, callback);
        });
    }

    function normalizeOutputPositions(outputsData) {
        return OutputModel.normalizeOutputPositions(outputsData);
    }

    function findSavedParsedOutput(outputName) {
        const output = outputs[outputName];
        const candidates = [outputName];
        if (output?.make && output?.model) {
            candidates.push(output.make + " " + output.model + " " + (output.serial || "Unknown"));
            candidates.push(output.make + " " + output.model);
        }
        for (const savedName in savedParsedOutputs) {
            if (candidates.includes(savedName.trim()))
                return savedParsedOutputs[savedName];
        }
        return null;
    }

    // A disabled wlr head reports no current mode, scale 0 and position 0,0 —
    // overlay the last written config so rewrites don't discard real settings.
    function overlaySavedDisabledOutput(entry, outputName) {
        const saved = findSavedParsedOutput(outputName);
        if (!saved)
            return;

        const savedMode = saved.modes?.[saved.current_mode ?? 0];
        if (savedMode && !entry.configured_mode)
            entry.configured_mode = savedMode.width + "x" + savedMode.height + "@" + (savedMode.refresh_rate / 1000).toFixed(3);
        if (saved.vrr_enabled !== undefined)
            entry.vrr_enabled = saved.vrr_enabled;
        if (!saved.logical || !entry.logical)
            return;

        entry.logical.x = saved.logical.x;
        entry.logical.y = saved.logical.y;
        entry.logical.scale = saved.logical.scale;
        entry.logical.transform = saved.logical.transform;
    }

    function buildOutputsWithPendingChanges() {
        const result = {};

        for (const outputName in savedOutputs) {
            if (!outputs[outputName])
                result[outputName] = JSON.parse(JSON.stringify(savedOutputs[outputName]));
        }

        for (const outputName in outputs) {
            const entry = JSON.parse(JSON.stringify(outputs[outputName]));
            if (entry.enabled === false)
                overlaySavedDisabledOutput(entry, outputName);
            result[outputName] = entry;
        }

        for (const outputName in pendingChanges) {
            if (!result[outputName])
                continue;
            const changes = pendingChanges[outputName];
            if (changes.position && result[outputName].logical) {
                result[outputName].logical.x = changes.position.x;
                result[outputName].logical.y = changes.position.y;
            }
            if (changes.mode !== undefined && result[outputName].modes) {
                if (result[outputName].configured_mode)
                    result[outputName].configured_mode = changes.mode;
                for (var i = 0; i < result[outputName].modes.length; i++) {
                    if (formatMode(result[outputName].modes[i]) === changes.mode) {
                        result[outputName].current_mode = i;
                        break;
                    }
                }
            }
            if (changes.scale !== undefined && result[outputName].logical)
                result[outputName].logical.scale = changes.scale;
            if (changes.transform !== undefined && result[outputName].logical)
                result[outputName].logical.transform = changes.transform;
            if (changes.vrr !== undefined)
                result[outputName].vrr_enabled = changes.vrr;
            if (changes.mirror !== undefined)
                result[outputName].mirror = changes.mirror;
        }
        return normalizeOutputPositions(result);
    }

    function backendUpdateOutputPosition(outputName, x, y) {
        if (!outputs || !outputs[outputName])
            return;
        const updatedOutputs = {};
        for (const name in outputs) {
            const output = outputs[name];
            if (name === outputName && output.logical) {
                updatedOutputs[name] = JSON.parse(JSON.stringify(output));
                updatedOutputs[name].logical.x = x;
                updatedOutputs[name].logical.y = y;
            } else {
                updatedOutputs[name] = output;
            }
        }
        outputs = updatedOutputs;
    }

    function backendUpdateOutputScale(outputName, scale) {
        if (!outputs || !outputs[outputName])
            return;
        const updatedOutputs = {};
        for (const name in outputs) {
            const output = outputs[name];
            if (name === outputName && output.logical) {
                updatedOutputs[name] = JSON.parse(JSON.stringify(output));
                updatedOutputs[name].logical.scale = scale;
            } else {
                updatedOutputs[name] = output;
            }
        }
        outputs = updatedOutputs;
    }

    function getOutputDisplayName(output, outputName) {
        return getOutputIdentifier(output, outputName);
    }

    function getNiriOutputIdentifier(output, outputName) {
        return OutputModel.niriIdentifier(output, outputName, SettingsData.displayNameMode);
    }

    function getNiriSetting(output, outputName, key, defaultValue) {
        if (!CompositorService.isNiri)
            return defaultValue;
        const identifier = getNiriOutputIdentifier(output, outputName);
        const pending = pendingNiriChanges[identifier];
        if (pending && pending[key] !== undefined)
            return pending[key];
        return SessionData.getNiriOutputSetting(identifier, key, defaultValue);
    }

    function setNiriSetting(output, outputName, key, value) {
        if (!CompositorService.isNiri)
            return;
        initOriginalNiriSettings();
        const identifier = getNiriOutputIdentifier(output, outputName);
        const newPending = JSON.parse(JSON.stringify(pendingNiriChanges));
        if (!newPending[identifier])
            newPending[identifier] = {};
        newPending[identifier][key] = value;
        pendingNiriChanges = newPending;
    }

    function initOriginalNiriSettings() {
        if (originalNiriSettings)
            return;
        originalNiriSettings = JSON.parse(JSON.stringify(SessionData.niriOutputSettings));
    }

    function getHyprlandOutputIdentifier(output, outputName) {
        return OutputModel.hyprlandIdentifier(output, outputName, SettingsData.displayNameMode);
    }

    function getHyprlandSetting(output, outputName, key, defaultValue) {
        if (!CompositorService.isHyprland)
            return defaultValue;
        const identifier = getHyprlandOutputIdentifier(output, outputName);
        const pending = pendingHyprlandChanges[identifier];
        if (pending && (key in pending)) {
            const val = pending[key];
            return (val !== null && val !== undefined) ? val : defaultValue;
        }
        return SessionData.getHyprlandOutputSetting(identifier, key, defaultValue);
    }

    function setHyprlandSetting(output, outputName, key, value) {
        if (!CompositorService.isHyprland)
            return;
        initOriginalHyprlandSettings();
        const identifier = getHyprlandOutputIdentifier(output, outputName);
        const newPending = JSON.parse(JSON.stringify(pendingHyprlandChanges));
        if (!newPending[identifier])
            newPending[identifier] = {};
        newPending[identifier][key] = value;
        pendingHyprlandChanges = newPending;
    }

    function getHyprlandCaps(output, outputName) {
        return OutputModel.hyprlandCaps(outputs[outputName]?.hardware ?? null, {
            "supportsWideColor": getHyprlandSetting(output, outputName, "supportsWideColor", undefined),
            "supportsHdr": getHyprlandSetting(output, outputName, "supportsHdr", undefined)
        });
    }

    function hyprlandCmAllowed(cm, caps) {
        return OutputModel.hyprlandCmAllowed(cm, caps);
    }

    function getHyprlandVrrMode(output, outputName) {
        const settings = {
            "vrr": getHyprlandSetting(output, outputName, "vrr", undefined),
            "vrrFullscreenOnly": getHyprlandSetting(output, outputName, "vrrFullscreenOnly", false)
        };
        return OutputModel.hyprlandVrrMode(settings, savedParsedOutputs[getHyprlandOutputIdentifier(output, outputName)]);
    }

    function setHyprlandVrrMode(output, outputName, mode) {
        setHyprlandSetting(output, outputName, "vrr", mode);
        setHyprlandSetting(output, outputName, "vrrFullscreenOnly", null);
    }

    function initOriginalHyprlandSettings() {
        if (originalHyprlandSettings)
            return;
        originalHyprlandSettings = JSON.parse(JSON.stringify(SessionData.hyprlandOutputSettings));
    }

    function initOriginalOutputs() {
        if (!originalOutputs)
            originalOutputs = JSON.parse(JSON.stringify(outputs));
    }

    function setPendingChange(outputName, key, value) {
        initOriginalOutputs();
        const newPending = JSON.parse(JSON.stringify(pendingChanges));
        if (!newPending[outputName])
            newPending[outputName] = {};
        newPending[outputName][key] = value;
        pendingChanges = newPending;

        if (key === "scale") {
            recalculateAdjacentPositions(outputName, value);
            backendUpdateOutputScale(outputName, value);
        }
    }

    function recalculateAdjacentPositions(changedOutput, newScale) {
        const moves = OutputModel.recalculateAdjacentPositions(outputs, pendingChanges, changedOutput, newScale, CompositorService.compositor);
        for (const move of moves) {
            const newPending = JSON.parse(JSON.stringify(pendingChanges));
            if (!newPending[move.name])
                newPending[move.name] = {};
            newPending[move.name].position = {
                "x": move.x,
                "y": move.y
            };
            pendingChanges = newPending;
            backendUpdateOutputPosition(move.name, move.x, move.y);
        }
    }

    function getPendingValue(outputName, key) {
        if (!pendingChanges[outputName])
            return undefined;
        return pendingChanges[outputName][key];
    }

    function getEffectiveValue(outputName, key, originalValue) {
        const pending = getPendingValue(outputName, key);
        return pending !== undefined ? pending : originalValue;
    }

    // Prevents disabling all outputs and prevents disabling the only output
    // in a single-display configuration.
    function canDisableOutput() {
        if (!CompositorService.isNiri && !CompositorService.isHyprland)
            return false;
        const totalOutputs = Object.keys(outputs).length;
        if (totalOutputs <= 1)
            return false;
        let enabledCount = 0;
        for (const name in outputs) {
            let disabled = false;
            if (CompositorService.isNiri)
                disabled = getNiriSetting(outputs[name], name, "disabled", false);
            else if (CompositorService.isHyprland)
                disabled = getHyprlandSetting(outputs[name], name, "disabled", false);
            if (!disabled)
                enabledCount++;
        }
        return enabledCount >= 2;
    }

    function clearPendingChanges() {
        pendingChanges = {};
        pendingNiriChanges = {};
        pendingHyprlandChanges = {};
        originalOutputs = null;
        originalNiriSettings = null;
        originalHyprlandSettings = null;
        originalDisplayNameMode = "";
    }

    function restoreDisplayNameMode() {
        if (originalDisplayNameMode === "")
            return;
        SettingsData.displayNameMode = originalDisplayNameMode;
        SettingsData.saveSettings();
    }

    function discardChanges() {
        restoreDisplayNameMode();
        backendFetchOutputs();
        clearPendingChanges();
    }

    function applyChanges() {
        if (!hasPendingChanges)
            return;
        if (readOnly) {
            include.showReadOnlyWarning();
            return;
        }
        const changeDescriptions = [];

        if (formatChanged) {
            const formatLabel = SettingsData.displayNameMode === "model" ? I18n.tr("Model") : I18n.tr("Name");
            changeDescriptions.push(I18n.tr("Config Format") + " → " + formatLabel);
        }

        for (const outputName in pendingChanges) {
            const changes = pendingChanges[outputName];
            if (changes.position)
                changeDescriptions.push(outputName + ": " + I18n.tr("Position") + " → " + changes.position.x + ", " + changes.position.y);
            if (changes.mode)
                changeDescriptions.push(outputName + ": " + I18n.tr("Mode") + " → " + changes.mode);
            if (changes.scale !== undefined)
                changeDescriptions.push(outputName + ": " + I18n.tr("Scale") + " → " + changes.scale);
            if (changes.transform)
                changeDescriptions.push(outputName + ": " + I18n.tr("Transform") + " → " + getTransformLabel(changes.transform));
            if (changes.vrr !== undefined)
                changeDescriptions.push(outputName + ": " + "VRR" + " → " + (changes.vrr ? I18n.tr("Enabled") : I18n.tr("Disabled")));
        }

        for (const outputId in pendingNiriChanges) {
            const changes = pendingNiriChanges[outputId];
            if (changes.disabled !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("Disabled") + " → " + (changes.disabled ? I18n.tr("Yes") : I18n.tr("No")));
            if (changes.vrrOnDemand !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("VRR On-Demand") + " → " + (changes.vrrOnDemand ? I18n.tr("Enabled") : I18n.tr("Disabled")));
            if (changes.focusAtStartup !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("Focus at startup") + " → " + (changes.focusAtStartup ? I18n.tr("Yes") : I18n.tr("No")));
            if (changes.hotCorners !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("Hot corners") + " → " + I18n.tr("Modified"));
            if (changes.layout !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("Layout") + " → " + I18n.tr("Modified"));
        }

        for (const outputId in pendingHyprlandChanges) {
            const changes = pendingHyprlandChanges[outputId];
            if (changes.disabled !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("Disabled") + " → " + (changes.disabled ? I18n.tr("Yes") : I18n.tr("No")));
            if (changes.bitdepth !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("Bit Depth") + " → " + changes.bitdepth);
            if (changes.colorManagement !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("Color Management") + " → " + changes.colorManagement);
            if (changes.sdrBrightness !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("SDR brightness") + " → " + changes.sdrBrightness);
            if (changes.sdrSaturation !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("SDR saturation") + " → " + changes.sdrSaturation);
            if (changes.supportsHdr !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("Force HDR") + " → " + (changes.supportsHdr ? I18n.tr("Yes") : I18n.tr("No")));
            if (changes.supportsWideColor !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("Force Wide Color") + " → " + (changes.supportsWideColor ? I18n.tr("Yes") : I18n.tr("No")));
            if (changes.vrr !== undefined)
                changeDescriptions.push(outputId + ": " + "VRR" + " → " + hyprlandVrrLabel(changes.vrr));
            if (changes.sdrEotf !== undefined)
                changeDescriptions.push(outputId + ": " + I18n.tr("SDR transfer function") + " → " + (changes.sdrEotf || I18n.tr("Default")));
        }

        if (CompositorService.isNiri) {
            validateAndApplyNiriConfig(changeDescriptions);
            return;
        }

        if (CompositorService.isAqueous) {
            previewAqueousOutputs(changeDescriptions);
            return;
        }

        const mergedOutputs = buildOutputsWithPendingChanges();
        if (CompositorService.isHyprland || CompositorService.isMango) {
            changesApplied(changeDescriptions);
            if (formatChanged)
                SettingsData.saveSettings();
            if (CompositorService.isHyprland)
                commitHyprlandSettingsChanges();
            backendWriteOutputsConfig(mergedOutputs);
            return;
        }
        validatingConfig = true;
        backendWriteOutputsConfig(mergedOutputs, success => {
            validatingConfig = false;
            if (!success) {
                ToastService.showError(I18n.tr("Error"), I18n.tr("Failed to apply profile"));
                return;
            }
            if (formatChanged)
                SettingsData.saveSettings();
            changesApplied(changeDescriptions);
        });
    }

    function validateAndApplyNiriConfig(changeDescriptions) {
        validatingConfig = true;
        validationError = "";

        const mergedOutputs = buildOutputsWithPendingChanges();
        const mergedNiriSettings = buildMergedNiriSettings();
        const configContent = NiriService.buildOutputsConfig(mergedOutputs, mergedNiriSettings);

        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        const tempFile = configDir + "/niri/dms/.outputs-validate-tmp.kdl";

        Proc.runCommand("niri-validate-write-tmp", ["sh", "-c", `mkdir -p "$(dirname "${tempFile}")" && cat > "${tempFile}" << 'EOF'\n${configContent}EOF`], (output, writeExitCode) => {
            if (writeExitCode !== 0) {
                validatingConfig = false;
                validationError = I18n.tr("Failed to write temp file for validation");
                ToastService.showError(I18n.tr("Config validation failed"), validationError, "", "display-config");
                return;
            }
            Proc.runCommand("niri-validate-config", ["sh", "-c", `niri validate -c "${tempFile}" 2>&1`], (validateOutput, validateExitCode) => {
                validatingConfig = false;
                Proc.runCommand("niri-validate-cleanup", ["rm", "-f", tempFile], () => {});
                if (validateExitCode !== 0) {
                    validationError = validateOutput.trim() || I18n.tr("Invalid configuration");
                    ToastService.showError(I18n.tr("Config validation failed"), validationError, "", "display-config");
                    return;
                }
                changesApplied(changeDescriptions);
                if (formatChanged)
                    SettingsData.saveSettings();
                commitNiriSettingsChanges();
                backendWriteOutputsConfig(mergedOutputs, mergedNiriSettings);
            });
        });
    }

    function buildMergedNiriSettings() {
        const merged = JSON.parse(JSON.stringify(SessionData.niriOutputSettings));
        for (const outputId in pendingNiriChanges) {
            if (!merged[outputId])
                merged[outputId] = {};
            for (const key in pendingNiriChanges[outputId]) {
                merged[outputId][key] = pendingNiriChanges[outputId][key];
            }
        }
        // Never disable the only connected output — clear any stale flag
        if (Object.keys(outputs).length <= 1) {
            for (const id in merged)
                delete merged[id].disabled;
        }
        return merged;
    }

    function commitNiriSettingsChanges() {
        for (const outputId in pendingNiriChanges) {
            for (const key in pendingNiriChanges[outputId]) {
                SessionData.setNiriOutputSetting(outputId, key, pendingNiriChanges[outputId][key]);
            }
        }
        // Clear stale disabled from SettingsData so NiriService reads clean state
        if (Object.keys(outputs).length <= 1) {
            for (const id in SessionData.niriOutputSettings) {
                if (SessionData.niriOutputSettings[id]?.disabled)
                    SessionData.setNiriOutputSetting(id, "disabled", null);
            }
        }
    }

    function hyprlandVrrLabel(mode) {
        switch (mode) {
        case 0:
            return I18n.tr("Off");
        case 1:
            return I18n.tr("On", "adjective, enabled state");
        case 2:
        case 3:
            return I18n.tr("Fullscreen only");
        default:
            return I18n.tr("Default (Global)");
        }
    }

    function buildMergedHyprlandSettings() {
        const merged = JSON.parse(JSON.stringify(SessionData.hyprlandOutputSettings));
        for (const outputId in pendingHyprlandChanges) {
            if (!merged[outputId])
                merged[outputId] = {};
            for (const key in pendingHyprlandChanges[outputId]) {
                const val = pendingHyprlandChanges[outputId][key];
                if (val === null || val === undefined)
                    delete merged[outputId][key];
                else
                    merged[outputId][key] = val;
            }
        }
        // Never disable the only connected output — clear any stale flag
        if (Object.keys(outputs).length <= 1) {
            for (const id in merged)
                delete merged[id].disabled;
        }
        return merged;
    }

    function commitHyprlandSettingsChanges() {
        for (const outputId in pendingHyprlandChanges) {
            for (const key in pendingHyprlandChanges[outputId]) {
                const val = pendingHyprlandChanges[outputId][key];
                if (val === null || val === undefined)
                    SessionData.removeHyprlandOutputSetting(outputId, key);
                else
                    SessionData.setHyprlandOutputSetting(outputId, key, val);
            }
        }
        // Clear stale disabled from SettingsData so HyprlandService reads clean state
        if (Object.keys(outputs).length <= 1) {
            for (const id in SessionData.hyprlandOutputSettings) {
                if (SessionData.hyprlandOutputSettings[id]?.disabled)
                    SessionData.removeHyprlandOutputSetting(id, "disabled");
            }
        }
    }

    function confirmChanges(profileId) {
        if (CompositorService.isAqueous) {
            finishAqueousPreview(true);
            return;
        }
        const outputConfigs = buildCurrentOutputConfigs();
        lastAppliedEntry = {
            outputs: outputConfigs
        };

        readMonitorsJson(data => {
            const match = profileId ? findConfigEntryById(data, profileId) : findConfigEntryByFingerprint(data, currentOutputSet, true);
            if (!match)
                return;
            data.configurations[match.index] = {
                "id": match.entry.id,
                "name": match.entry.name || "",
                "outputs": outputConfigs
            };
            writeMonitorsJson(data, success => {
                if (!success || !profileId)
                    return;
                const updated = JSON.parse(JSON.stringify(validatedProfiles));
                if (updated[profileId]) {
                    updated[profileId].outputs = outputConfigs;
                    validatedProfiles = updated;
                    publishActiveProfileModes();
                }
            });
        });

        clearPendingChanges();
        changesConfirmed();
    }

    function revertChanges() {
        if (CompositorService.isAqueous && aqueousPreview) {
            finishAqueousPreview(false);
            return;
        }
        const hadFormatChange = originalDisplayNameMode !== "";
        const hadNiriChanges = originalNiriSettings !== null;
        const hadHyprlandChanges = originalHyprlandSettings !== null;

        restoreDisplayNameMode();

        if (hadNiriChanges) {
            SessionData.niriOutputSettings = JSON.parse(JSON.stringify(originalNiriSettings));
            SessionData.saveSettings();
        }

        if (hadHyprlandChanges) {
            SessionData.hyprlandOutputSettings = JSON.parse(JSON.stringify(originalHyprlandSettings));
            SessionData.saveSettings();
        }

        pendingHyprlandChanges = {};
        pendingNiriChanges = {};

        if (!originalOutputs && !hadNiriChanges && !hadHyprlandChanges) {
            if (hadFormatChange)
                backendWriteOutputsConfig(buildOutputsWithPendingChanges());
            clearPendingChanges();
            changesReverted();
            return;
        }

        const original = originalOutputs ? JSON.parse(JSON.stringify(originalOutputs)) : buildOutputsWithPendingChanges();
        for (const name in savedOutputs) {
            if (!original[name])
                original[name] = JSON.parse(JSON.stringify(savedOutputs[name]));
        }
        backendWriteOutputsConfig(original);
        clearPendingChanges();
        // clearPendingChanges() resets originalOutputs, so restore the model from the snapshot.
        outputs = original;
        changesReverted();
    }

    function getOutputBounds() {
        return OutputModel.outputBounds(allOutputs, CompositorService.compositor);
    }

    function getPhysicalSize(output) {
        return OutputModel.physicalSize(output);
    }

    function getLogicalSize(output) {
        return OutputModel.logicalSize(output, CompositorService.compositor);
    }

    function isOutputDisabled(outputName) {
        if (!outputs[outputName])
            return false;
        if (CompositorService.isHyprland)
            return getHyprlandSetting(outputs[outputName], outputName, "disabled", false);
        if (CompositorService.isNiri)
            return getNiriSetting(outputs[outputName], outputName, "disabled", false);
        return false;
    }

    function canvasLayout() {
        const disabled = {};
        for (const name in outputs) {
            if (isOutputDisabled(name))
                disabled[name] = true;
        }
        return {
            "outputs": outputs,
            "disabled": disabled,
            "compositor": CompositorService.compositor
        };
    }

    function checkOverlap(testName, testX, testY, testW, testH) {
        return OutputModel.checkOverlap(canvasLayout(), testName, testX, testY, testW, testH);
    }

    function snapToEdges(testName, posX, posY, testW, testH) {
        const snapped = OutputModel.snapToEdges(canvasLayout(), testName, posX, posY, testW, testH);
        return Qt.point(snapped.x, snapped.y);
    }

    function formatMode(mode) {
        return OutputModel.formatMode(mode);
    }

    function formatScaleLabel(scale) {
        return OutputModel.formatScaleLabel(scale);
    }

    function getScalePresetValues(outputName, outputData) {
        return OutputModel.scalePresetValues(outputData, getPendingValue(outputName, "mode"), CompositorService.compositor);
    }

    function snapScale(outputName, outputData, scale) {
        return OutputModel.snapScaleToMode(outputData, getPendingValue(outputName, "mode"), CompositorService.compositor, scale);
    }

    function formatScaleOption(outputName, outputData, scale) {
        return OutputModel.formatScaleOption(outputData, getPendingValue(outputName, "mode"), scale);
    }

    function getTransformLabel(transform) {
        switch (transform) {
        case "Normal":
            return I18n.tr("Normal", "display rotation option", true);
        case "90":
            return "90°";
        case "180":
            return "180°";
        case "270":
            return "270°";
        case "Flipped":
            return I18n.tr("Flipped");
        case "Flipped90":
            return I18n.tr("Flipped 90°");
        case "Flipped180":
            return I18n.tr("Flipped 180°");
        case "Flipped270":
            return I18n.tr("Flipped 270°");
        default:
            return I18n.tr("Normal", "display rotation option", true);
        }
    }

    function getTransformValue(label) {
        if (label === I18n.tr("Normal", "display rotation option", true))
            return "Normal";
        if (label === "90°")
            return "90";
        if (label === "180°")
            return "180";
        if (label === "270°")
            return "270";
        if (label === I18n.tr("Flipped"))
            return "Flipped";
        if (label === I18n.tr("Flipped 90°"))
            return "Flipped90";
        if (label === I18n.tr("Flipped 180°"))
            return "Flipped180";
        if (label === I18n.tr("Flipped 270°"))
            return "Flipped270";
        return "Normal";
    }

    function setOriginalDisplayNameMode(mode) {
        if (originalDisplayNameMode === "")
            originalDisplayNameMode = mode;
    }
}
