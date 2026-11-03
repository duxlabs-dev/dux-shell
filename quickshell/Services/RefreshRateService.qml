pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/OutputModel.js" as OutputModel

Singleton {
    id: root
    readonly property var log: Log.scoped("RefreshRateService")

    readonly property int batteryRefreshRateTarget: 60000
    readonly property int batteryRefreshRateTolerance: 1000

    property int _resumeRecoveryAttempt: 0
    readonly property var _resumeRecoveryIntervals: [1000, 5000, 15000, 30000]
    property var _lastAppliedTargets: ({})

    Timer {
        id: cascadeGuard
        interval: 3000
        repeat: false
        onTriggered: root._lastAppliedTargets = ({})
    }

    property string _pendingReason: ""

    Timer {
        id: syncDebounce
        interval: 300
        repeat: false
        onTriggered: root._runSync()
    }

    Timer {
        id: startupRefreshRateSync
        interval: 500
        repeat: false
        running: SettingsData.lowerDisplayRefreshRateOnBattery
        onTriggered: root.requestSync("startup")
    }

    Timer {
        id: resumeRecoveryTimer
        interval: root._resumeRecoveryIntervals[0]
        repeat: false
        onTriggered: {
            root.requestSync("resume-reconcile");
            root._resumeRecoveryAttempt++;
            if (root._resumeRecoveryAttempt < root._resumeRecoveryIntervals.length) {
                interval = root._resumeRecoveryIntervals[root._resumeRecoveryAttempt];
                restart();
                return;
            }
            root._resumeRecoveryAttempt = 0;
            interval = root._resumeRecoveryIntervals[0];
        }
    }

    Connections {
        target: SessionService
        enabled: SettingsData.lowerDisplayRefreshRateOnBattery
        function onSessionResumed() {
            root._resumeRecoveryAttempt = 0;
            resumeRecoveryTimer.interval = root._resumeRecoveryIntervals[0];
            resumeRecoveryTimer.restart();
        }
    }

    Connections {
        target: BatteryService
        enabled: SettingsData.lowerDisplayRefreshRateOnBattery
        function onIsPluggedInChanged() {
            root.requestSync("power-change");
        }
    }

    Connections {
        target: SettingsData
        function onLowerDisplayRefreshRateOnBatteryChanged() {
            resumeRecoveryTimer.stop();
            root.requestSync("setting-change");
        }
    }

    Connections {
        target: SessionData
        enabled: SettingsData.lowerDisplayRefreshRateOnBattery
        function onActiveDisplayProfileChanged() {
            root.requestSync("profile-change");
        }

        function onActiveDisplayProfileModesChanged() {
            root.requestSync("profile-change");
        }
    }

    Connections {
        target: NiriService
        enabled: SettingsData.lowerDisplayRefreshRateOnBattery
        function onOutputsChanged() {
            root.requestSync("output-change");
        }
    }

    Connections {
        target: WlrOutputService
        enabled: SettingsData.lowerDisplayRefreshRateOnBattery
        function onStateChanged() {
            root.requestSync("output-change");
        }
    }

    function syncRefreshRates(isPluggedIn, reason) {
        if (!SettingsData.lowerDisplayRefreshRateOnBattery) {
            if (reason === "setting-change")
                applyConfiguredTargets("disabled", reason);
            return;
        }

        if (!isPluggedIn) {
            applyBatteryTargets(reason);
            return;
        }

        applyConfiguredTargets("AC", reason);
    }

    function requestSync(reason) {
        _pendingReason = reason || _pendingReason;
        syncDebounce.restart();
    }

    function _runSync() {
        syncRefreshRates(BatteryService.isPluggedIn, _pendingReason || "sync");
        _pendingReason = "";
    }

    function identifierHead(output) {
        return {
            "make": output?.make || "",
            "model": output?.model || "",
            "serial": output?.serial || output?.serialNumber || ""
        };
    }

    function withIdentifiers(identifiers, candidates) {
        for (const id of candidates) {
            if (!identifiers.includes(id))
                identifiers.push(id);
        }
        return identifiers;
    }

    function outputIdentifiers(outputName, output) {
        const head = identifierHead(output);
        if (!head.make || !head.model)
            return [outputName];
        return withIdentifiers([outputName], [OutputModel.niriIdentifier(head, outputName, "model"), OutputModel.modelIdentifier(head), OutputModel.hyprlandIdentifier(head, outputName, "model")]);
    }

    function previousRefreshModes() {
        return SettingsData.displayPreviousRefreshModes?.[CompositorService.compositor] || {};
    }

    function findPreviousRefreshMode(outputName, output) {
        const modes = previousRefreshModes();
        for (const identifier of outputIdentifiers(outputName, output)) {
            const entry = modes[identifier];
            const mode = typeof entry === "string" ? entry : entry?.mode;
            if (mode)
                return mode;
        }
        return "";
    }

    function storePreviousRefreshMode(outputName, output, mode) {
        const modeString = OutputModel.formatModeString(mode);
        if (!modeString)
            return;
        const modes = JSON.parse(JSON.stringify(previousRefreshModes()));
        for (const identifier of outputIdentifiers(outputName, output)) {
            modes[identifier] = {
                "mode": modeString
            };
        }
        SettingsData.setDisplayPreviousRefreshModes(CompositorService.compositor, modes);
    }

    function clearPreviousRefreshMode(outputName, output) {
        const modes = JSON.parse(JSON.stringify(previousRefreshModes()));
        let changed = false;
        for (const identifier of outputIdentifiers(outputName, output)) {
            if (modes[identifier] === undefined)
                continue;
            delete modes[identifier];
            changed = true;
        }
        if (changed)
            SettingsData.setDisplayPreviousRefreshModes(CompositorService.compositor, modes);
    }

    function applyConfiguredTargets(context, reason) {
        if (CompositorService.isNiri) {
            const outputs = NiriService.outputs || {};
            const applied = [];
            for (const name in outputs) {
                const currentMode = OutputModel.niriCurrentMode(outputs[name]);
                const target = computeTargetMode(name, outputs[name], "niri");
                if (!target || !target.value)
                    continue;
                if (OutputModel.modeAlreadyCurrent(currentMode, target.mode, batteryRefreshRateTolerance)) {
                    if (target.source === "previous")
                        clearPreviousRefreshMode(name, outputs[name]);
                    continue;
                }
                if (root._lastAppliedTargets[name] === target.value)
                    continue;
                root._lastAppliedTargets[name] = target.value;
                cascadeGuard.restart();
                NiriService.applyOutputConfig(name, {
                    "mode": target.value
                }, success => {
                    if (success && target.source === "previous")
                        clearPreviousRefreshMode(name, outputs[name]);
                });
                applied.push(name + " " + (OutputModel.modeRefresh(target.mode) / 1000).toFixed(0) + "Hz (" + target.source + ")");
            }
            if (applied.length > 0)
                log.info("Updated display refresh rate: ", applied.join(", "), " (", context, ")");
            return;
        }

        if (!WlrOutputService.wlrOutputAvailable)
            return;

        const outputs = WlrOutputService.outputs || [];
        const modeOverrides = ({});
        const restoredOutputs = [];
        const applied = [];

        for (const output of outputs) {
            const target = computeTargetMode(output.name, output, "wlr");
            if (!target || !target.value)
                continue;
            if (OutputModel.modeAlreadyCurrent(output.currentMode, target.mode, batteryRefreshRateTolerance)) {
                if (target.source === "previous")
                    clearPreviousRefreshMode(output.name, output);
                continue;
            }
            if (root._lastAppliedTargets[output.name] === target.value)
                continue;
            root._lastAppliedTargets[output.name] = target.value;
            cascadeGuard.restart();
            modeOverrides[output.name] = target;
            if (target.source === "previous")
                restoredOutputs.push(output);
            applied.push(output.name + " " + (OutputModel.modeRefresh(target.mode) / 1000).toFixed(0) + "Hz (" + target.source + ")");
        }

        if (applied.length > 0) {
            log.info("Updated display refresh rate: ", applied.join(", "), " (", context, ")");
            applyWlrModeOverrides(modeOverrides, success => {
                if (!success)
                    return;
                for (const output of restoredOutputs)
                    clearPreviousRefreshMode(output.name, output);
            });
        }
    }

    function applyBatteryTargets(reason) {
        if (CompositorService.isNiri) {
            const outputs = NiriService.outputs || {};
            const applied = [];
            for (const name in outputs) {
                const output = outputs[name];
                const currentMode = OutputModel.niriCurrentMode(output);
                if (!currentMode)
                    continue;
                const currentRefresh = OutputModel.modeRefresh(currentMode);
                if (currentRefresh <= batteryRefreshRateTarget + batteryRefreshRateTolerance)
                    continue;
                const target = OutputModel.batteryRefreshMode(output, currentMode, "niri", batteryRefreshRateTarget, batteryRefreshRateTolerance);
                if (!target)
                    continue;
                const targetValue = OutputModel.formatNiriMode(target);
                storePreviousRefreshMode(name, output, currentMode);
                if (root._lastAppliedTargets[name] === targetValue)
                    continue;
                root._lastAppliedTargets[name] = targetValue;
                cascadeGuard.restart();
                NiriService.applyOutputConfig(name, {
                    "mode": targetValue
                });
                applied.push(name + " " + (currentRefresh / 1000).toFixed(0) + "\u2192" + (OutputModel.modeRefresh(target) / 1000).toFixed(0) + "Hz");
            }
            if (applied.length > 0)
                log.info("Updated display refresh rate: ", applied.join(", "), " (battery)");
            return;
        }

        if (!WlrOutputService.wlrOutputAvailable)
            return;

        const outputs = WlrOutputService.outputs || [];
        const modeOverrides = ({});
        const applied = [];

        for (const output of outputs) {
            const currentMode = output.currentMode;
            if (!currentMode)
                continue;
            const currentRefresh = OutputModel.modeRefresh(currentMode);
            if (currentRefresh <= batteryRefreshRateTarget + batteryRefreshRateTolerance)
                continue;
            const target = OutputModel.batteryRefreshMode(output, currentMode, "wlr", batteryRefreshRateTarget, batteryRefreshRateTolerance);
            if (!target)
                continue;
            storePreviousRefreshMode(output.name, output, currentMode);
            if (root._lastAppliedTargets[output.name] === target.id)
                continue;
            root._lastAppliedTargets[output.name] = target.id;
            cascadeGuard.restart();
            modeOverrides[output.name] = {
                "value": target.id,
                "mode": target,
                "source": "battery"
            };
            applied.push(output.name + " " + (currentRefresh / 1000).toFixed(0) + "\u2192" + (OutputModel.modeRefresh(target) / 1000).toFixed(0) + "Hz");
        }

        if (applied.length > 0) {
            log.info("Updated display refresh rate: ", applied.join(", "), " (battery)");
            applyWlrModeOverrides(modeOverrides);
        }
    }

    function buildWlrHeads(modeOverrides) {
        const outputs = WlrOutputService.outputs || [];
        const heads = [];

        for (const output of outputs) {
            const enabled = output.enabled !== false;
            const head = {
                "name": output.name,
                "enabled": enabled
            };

            if (enabled) {
                const modeId = modeOverrides[output.name] !== undefined ? modeOverrides[output.name].value : output.currentMode?.id;
                if (modeId !== undefined)
                    head.modeId = modeId;

                head.position = {
                    "x": output.x ?? 0,
                    "y": output.y ?? 0
                };
                head.scale = output.scale ?? 1.0;
                head.transform = output.transform ?? 0;

                if (output.adaptiveSyncSupported)
                    head.adaptiveSync = output.adaptiveSync ?? 0;
            }

            heads.push(head);
        }

        return heads;
    }

    function applyWlrModeOverrides(modeOverrides, callback) {
        if (CompositorService.isHyprland || CompositorService.isMango) {
            applyModeOverridesWithoutReload(modeOverrides, callback);
            return;
        }

        WlrOutputService.applyConfiguration(buildWlrHeads(modeOverrides), callback);
    }

    // apply live and persist without a compositor config reload — full reloads
    // are a suspected trigger for IME input lockups (#3073)
    function applyModeOverridesWithoutReload(modeOverrides, callback) {
        WlrOutputService.applyConfiguration(buildWlrHeads(modeOverrides), success => {
            if (!success) {
                persistOutputsConfig(modeOverrides, callback, false);
                return;
            }
            persistOutputsConfig(modeOverrides, null, true);
            if (callback)
                callback(true);
        });
    }

    function persistOutputsConfig(modeOverrides, callback, skipReload) {
        if (CompositorService.isHyprland) {
            HyprlandService.generateOutputsConfig(buildWlrOutputsData(modeOverrides), SessionData.hyprlandOutputSettings, callback, skipReload);
            return;
        }
        MangoService.generateOutputsConfig(buildWlrOutputsData(modeOverrides), callback, skipReload);
    }

    function buildWlrOutputsData(modeOverrides) {
        const outputs = WlrOutputService.outputs || [];
        const data = ({});

        for (const output of outputs) {
            const target = modeOverrides[output.name]?.mode || output.currentMode;
            const normalizedModes = (output.modes || []).map(mode => ({
                        "id": mode.id,
                        "width": OutputModel.modeWidth(mode),
                        "height": OutputModel.modeHeight(mode),
                        "refresh_rate": OutputModel.modeRefresh(mode),
                        "preferred": mode.preferred === true || mode.is_preferred === true
                    }));
            const currentMode = target ? normalizedModes.findIndex(mode => OutputModel.modeWidth(mode) === OutputModel.modeWidth(target) && OutputModel.modeHeight(mode) === OutputModel.modeHeight(target) && Math.abs(OutputModel.modeRefresh(mode) - OutputModel.modeRefresh(target)) <= batteryRefreshRateTolerance) : -1;

            // No enabled flag: a head asleep via sleep_monitor reports enabled=false, and Mango would persist that as disable:1.
            data[output.name] = {
                "name": output.name,
                "make": output.make || "",
                "model": output.model || "",
                "serial": output.serial || output.serialNumber || "",
                "modes": normalizedModes,
                "current_mode": currentMode,
                "configured_mode": target ? OutputModel.formatModeString(target) : "",
                "vrr_supported": output.adaptiveSyncSupported ?? output.vrr_supported ?? false,
                "vrr_enabled": OutputModel.outputVrrEnabled(output),
                "logical": {
                    "x": output.x ?? 0,
                    "y": output.y ?? 0,
                    "width": OutputModel.modeWidth(target || output.currentMode) || 1920,
                    "height": OutputModel.modeHeight(target || output.currentMode) || 1080,
                    "scale": output.scale ?? 1.0,
                    "transform": OutputModel.transformName(output.transform)
                }
            };
        }

        return data;
    }

    function computeTargetMode(outputName, output, backend) {
        const profileMode = findActiveProfileMode(outputName, output);
        if (profileMode) {
            const mode = OutputModel.findModeByString(output?.modes || [], profileMode, batteryRefreshRateTolerance);
            if (mode) {
                return {
                    "value": OutputModel.restoreModeValue(mode, backend),
                    "mode": mode,
                    "source": "profile"
                };
            }
        }

        const previousMode = findPreviousRefreshMode(outputName, output);
        if (previousMode) {
            const mode = OutputModel.findModeByString(output?.modes || [], previousMode, batteryRefreshRateTolerance);
            if (mode) {
                return {
                    "value": OutputModel.restoreModeValue(mode, backend),
                    "mode": mode,
                    "source": "previous"
                };
            }
        }

        return {
            "value": null,
            "mode": null,
            "source": "none"
        };
    }

    function findActiveProfileMode(outputName, output) {
        const compositor = CompositorService.compositor;
        const profileModes = SessionData.activeDisplayProfileModes?.[compositor] || {};
        if (Object.keys(profileModes).length === 0)
            return "";

        const head = identifierHead(output);
        const identifiers = head.make && head.model ? withIdentifiers([outputName], [OutputModel.niriIdentifier(head, outputName, "model"), OutputModel.modelIdentifier(head)]) : [outputName];

        for (const identifier of identifiers) {
            const mode = profileModes[identifier]?.mode;
            if (mode)
                return mode;
        }

        return "";
    }
}
