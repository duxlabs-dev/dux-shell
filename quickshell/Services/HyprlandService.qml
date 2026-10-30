pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Common
import qs.Services
import "../Common/OutputModel.js" as OutputModel
import "../Common/BlurStrength.js" as BlurStrength
import "../Common/WorkspaceModel.js" as WorkspaceModel // qmllint disable unused-imports

Singleton {
    id: root
    readonly property var log: Log.scoped("HyprlandService")

    readonly property string configDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation))
    readonly property string hyprDmsDir: configDir + "/hypr/dms"
    readonly property string outputsPath: hyprDmsDir + "/outputs.lua"
    readonly property string layoutPath: hyprDmsDir + "/layout.lua"
    readonly property string cursorPath: hyprDmsDir + "/cursor.lua"
    readonly property string inputPath: hyprDmsDir + "/input.lua"
    readonly property string windowrulesPath: hyprDmsDir + "/windowrules.lua"
    readonly property bool luaConfigActive: CompositorService.isHyprland && (Hyprland.usingLua === true || luaConfigDetected)

    property bool inOverview: false

    property int _lastGapValue: -1
    property string _monitorLayoutSignature: ""
    signal monitorLayoutChanged
    property bool luaConfigDetected: false
    property bool luaConfigStatusReady: false
    property bool luaConfigStatusLoading: false
    property bool layoutGenerationPending: false
    property bool layoutGenerationRunning: false
    // Effect options come and go between Hyprland releases; an unknown key is a config error, so writers and rows both gate on this
    property var hyprOptionNames: ({})
    property bool hyprOptionsReady: false
    property bool hyprOptionsLoading: false
    property bool inputGenerationPending: false
    property bool inputGenerationRunning: false
    property bool cursorGenerationPending: false
    property int followMouseMode: -1
    // Hyprland only has per-device touchpad speed; probed once per compositor, a hotplugged touchpad waits for the next shell start
    property var hyprTouchpadNames: []
    property bool hyprDevicesReady: false
    property bool hyprDevicesLoading: false
    property int _layoutRequestRevision: 0
    property int _layoutAppliedRevision: 0
    property int _frameTransitionRevision: 0
    readonly property bool frameLayoutReady: _layoutAppliedRevision >= _frameTransitionRevision

    // dms/layout.lua is the source of truth for xray; parsed once before the first regeneration
    property bool layoutXrayEnabled: false
    property bool layoutBarXrayEnabled: true
    property bool _layoutXrayLoaded: false
    property bool _layoutXrayLoading: false

    DeferredAction {
        id: layoutGenerationAction
        onTriggered: root.doGenerateLayoutConfig()
    }

    DeferredAction {
        id: inputGenerationAction
        onTriggered: root.doGenerateInputConfig()
    }

    onLuaConfigStatusLoadingChanged: {
        if (luaConfigStatusLoading)
            return;
        if (layoutGenerationPending)
            layoutGenerationAction.schedule();
        if (inputGenerationPending)
            inputGenerationAction.schedule();
    }

    onLuaConfigActiveChanged: {
        if (luaConfigActive)
            ensureDmsLuaConfigs();
    }

    // workspaceString + monitor pairs from `hyprctl workspacerules`, refreshed on configreloaded
    property var workspaceRules: []
    // Proc keeps one callback per id, so a second reload would drop the first caller's.
    property var _reloadCallbacks: []

    function refreshWorkspaceRules() {
        if (!CompositorService.isHyprland)
            return;
        Proc.runCommand("hyprctl-workspacerules", ["hyprctl", "-j", "workspacerules"], (output, exitCode) => {
            if (exitCode !== 0)
                return;
            try {
                const rules = JSON.parse(output);
                workspaceRules = Array.isArray(rules) ? rules.filter(rule => rule.monitor).map(rule => ({
                            "workspaceString": rule.workspaceString,
                            "monitor": rule.monitor
                        })) : [];
            } catch (error) {
                log.warn("workspacerules parse failed:", error);
            }
        });
    }

    Component.onCompleted: {
        if (CompositorService.isHyprland) {
            refreshFollowMouse();
            refreshWorkspaceRules();
            refreshLuaConfigStatus();
            if (luaConfigActive)
                ensureDmsLuaConfigs();
        }
    }

    function ensureDmsLuaConfigs() {
        Qt.callLater(generateLayoutConfig);
        Qt.callLater(generateInputConfig);
        Qt.callLater(ensureWindowrulesConfig);
    }

    function ensureWindowrulesConfig() {
        if (!canWriteLuaConfig("windowrules"))
            return;
        Proc.runCommand("hypr-ensure-windowrules", ["sh", "-c", `mkdir -p "${hyprDmsDir}" && [ ! -f "${windowrulesPath}" ] && touch "${windowrulesPath}" || true`], (output, exitCode) => {
            if (exitCode !== 0)
                log.warn("Failed to ensure windowrules.lua:", output);
        });
    }

    Connections {
        target: SettingsData
        enabled: CompositorService.isHyprland
        function onBarConfigsChanged() {
            const newGaps = Math.max(4, (SettingsData.getPrimaryBarConfig()?.spacing ?? 4));
            if (newGaps === root._lastGapValue)
                return;
            root._lastGapValue = newGaps;
            generateLayoutConfig();
        }
    }

    Connections {
        target: CompositorService
        function onIsHyprlandChanged() {
            if (CompositorService.isHyprland) {
                refreshFollowMouse();
                refreshLuaConfigStatus();
                if (luaConfigActive)
                    ensureDmsLuaConfigs();
                generateLayoutConfig();
                return;
            }
            followMouseMode = -1;
            luaConfigDetected = false;
            luaConfigStatusReady = false;
            luaConfigStatusLoading = false;
            hyprOptionNames = {};
            hyprOptionsReady = false;
            hyprTouchpadNames = [];
            hyprDevicesReady = false;
        }
    }

    function getOutputIdentifier(output, outputName) {
        if (output.explicitIdentifier)
            return outputName;
        return OutputModel.hyprlandIdentifier(output, outputName, SettingsData.displayNameMode);
    }

    function luaQuoted(str) {
        return JSON.stringify(String(str ?? ""));
    }

    // Hyprland prefers hyprland.lua whenever it exists, so the file probe covers old Quickshell builds and a lost j/status reply
    function refreshLuaConfigStatus() {
        if (!CompositorService.isHyprland) {
            luaConfigDetected = false;
            luaConfigStatusReady = false;
            luaConfigStatusLoading = false;
            return;
        }
        if (luaConfigStatusReady || luaConfigStatusLoading)
            return;
        // usingLua starts false until the async j/status reply lands, so only true is a decision
        if (Hyprland.usingLua === true) {
            luaConfigStatusReady = true;
            return;
        }

        luaConfigStatusLoading = true;
        Proc.runCommand("hypr-lua-config-status", ["test", "-f", configDir + "/hypr/hyprland.lua"], (output, exitCode) => {
            luaConfigDetected = exitCode === 0;
            luaConfigStatusReady = true;
            luaConfigStatusLoading = false;
        });
    }

    function canWriteLuaConfig(name) {
        if (luaConfigActive)
            return true;
        if (CompositorService.isHyprland && !luaConfigStatusReady && !luaConfigStatusLoading)
            refreshLuaConfigStatus();
        if (CompositorService.isHyprland && (luaConfigStatusLoading || !luaConfigStatusReady)) {
            log.debug("Deferring Hyprland", name || "config", "Lua write until config format is known");
            return false;
        }
        log.info("Skipping Hyprland", name || "config", "Lua write because the active Hyprland config is not Lua");
        return false;
    }

    function hyprSupports(name) {
        return hyprOptionNames[name] === true;
    }

    // hyprctl descriptions only gives us names, so a 0.57-only option marks the release where these bools became modes
    function hyprIntModes() {
        return hyprSupports("input:swallow_focus_click");
    }

    function hyprMode(value) {
        return hyprIntModes() ? value : value !== 0;
    }

    function refreshFollowMouse() {
        if (!CompositorService.isHyprland)
            return;
        Proc.runCommand("hypr-follow-mouse", ["hyprctl", "-j", "getoption", "input:follow_mouse"], (output, exitCode) => {
            if (exitCode !== 0 || !CompositorService.isHyprland)
                return;
            try {
                const mode = JSON.parse(output).int;
                if (Number.isInteger(mode) && mode >= 0 && mode <= 3)
                    followMouseMode = mode;
            } catch (error) {
                log.warn("hyprctl follow_mouse parse failed:", error);
            }
        });
    }

    function loadHyprOptionNames() {
        if (!CompositorService.isHyprland || hyprOptionsReady || hyprOptionsLoading)
            return;
        hyprOptionsLoading = true;
        Proc.runCommand("hypr-option-names", ["hyprctl", "-j", "descriptions"], (output, exitCode) => {
            hyprOptionsLoading = false;
            hyprOptionsReady = true;
            if (exitCode !== 0)
                return;
            try {
                const names = {};
                for (const option of JSON.parse(output))
                    names[option.name] = true;
                hyprOptionNames = names;
            } catch (error) {
                log.warn("hyprctl descriptions parse failed:", error);
            }
            if (layoutGenerationPending)
                layoutGenerationAction.schedule();
            if (inputGenerationPending)
                inputGenerationAction.schedule();
            if (cursorGenerationPending)
                generateCursorConfig();
        });
    }

    function loadHyprTouchpads() {
        if (!CompositorService.isHyprland || hyprDevicesReady || hyprDevicesLoading)
            return;
        hyprDevicesLoading = true;
        Proc.runCommand("hypr-devices", ["hyprctl", "-j", "devices"], (output, exitCode) => {
            hyprDevicesLoading = false;
            hyprDevicesReady = true;
            if (exitCode === 0) {
                try {
                    hyprTouchpadNames = touchpadNames(JSON.parse(output));
                } catch (error) {
                    log.warn("hyprctl devices parse failed:", error);
                }
            }
            if (inputGenerationPending)
                inputGenerationAction.schedule();
        });
    }

    function forceFlagValue(value) {
        if (value === true)
            return 1;
        if (value === false)
            return -1;
        return Number(value);
    }

    function generateOutputsConfig(outputsData, hyprlandSettings, callback, skipReload) {
        if (!canWriteLuaConfig("outputs")) {
            if (callback)
                callback(false);
            return;
        }
        if (!outputsData || Object.keys(outputsData).length === 0) {
            if (callback)
                callback(false);
            return;
        }

        const settings = hyprlandSettings || SessionData.hyprlandOutputSettings;
        Proc.runCommand("hypr-read-outputs", ["cat", outputsPath], (existing, readExitCode) => {
            const saved = readExitCode === 0 ? OutputModel.parseHyprlandOutputs(existing) : {};
            writeOutputsConfig(buildOutputsLua(outputsData, settings, saved), callback, skipReload);
        });
    }

    function buildOutputsLua(outputsData, settings, saved) {
        let lines = ["-- Auto-generated by DMS — do not edit manually", ""];

        const liveIdentifiers = {};
        for (const outputName in outputsData) {
            const output = outputsData[outputName];
            if (output?.make && output?.model)
                liveIdentifiers[getOutputIdentifier(output, outputName).trim()] = true;
        }

        for (const outputName in outputsData) {
            const output = outputsData[outputName];
            if (!output)
                continue;

            const identifier = getOutputIdentifier(output, outputName);
            if (!identifier.trim())
                continue;
            if (!(output.make && output.model) && liveIdentifiers[identifier.trim()])
                continue;

            const outputSettings = settings[identifier] || {};

            if (outputSettings.disabled) {
                lines.push(`hl.monitor({ output = ${luaQuoted(identifier)}, disabled = true })`);
                continue;
            }

            let resolution = output.configured_mode || "preferred";
            if (!output.configured_mode && output.modes && output.current_mode !== undefined) {
                const mode = output.modes[output.current_mode];
                if (mode)
                    resolution = mode.width + "x" + mode.height + "@" + (mode.refresh_rate / 1000).toFixed(3);
            }

            const geometry = OutputModel.hyprlandLuaGeometry(output, saved[identifier], liveMonitor(outputName));
            const scale = geometry.scale === "auto" ? luaQuoted("auto") : geometry.scale;
            const parts = [`output = ${luaQuoted(identifier)}`, `mode = ${luaQuoted(resolution)}`, `position = ${luaQuoted(geometry.position)}`, `scale = ${scale}`];

            const transform = OutputModel.transformIndex(output.logical?.transform ?? "Normal");
            if (transform !== 0)
                parts.push(`transform = ${transform}`);

            const vrrMode = OutputModel.hyprlandVrrMode(outputSettings, saved[identifier]);
            if (vrrMode !== undefined)
                parts.push(`vrr = ${vrrMode}`);

            if (output.mirror && output.mirror.length > 0)
                parts.push(`mirror = ${luaQuoted(output.mirror)}`);

            if (outputSettings.bitdepth && outputSettings.bitdepth !== 8)
                parts.push(`bitdepth = ${Number(outputSettings.bitdepth)}`);

            if (outputSettings.colorManagement && outputSettings.colorManagement !== "auto")
                parts.push(`cm = ${luaQuoted(outputSettings.colorManagement)}`);

            if (outputSettings.sdrEotf)
                parts.push(`sdr_eotf = ${luaQuoted(outputSettings.sdrEotf)}`);

            if (outputSettings.icc)
                parts.push(`icc = ${luaQuoted(outputSettings.icc)}`);

            if (outputSettings.sdrBrightness !== undefined && outputSettings.sdrBrightness !== 1.0)
                parts.push(`sdrbrightness = ${Number(outputSettings.sdrBrightness)}`);

            if (outputSettings.sdrSaturation !== undefined && outputSettings.sdrSaturation !== 1.0)
                parts.push(`sdrsaturation = ${Number(outputSettings.sdrSaturation)}`);

            if (outputSettings.supportsWideColor !== undefined)
                parts.push(`supports_wide_color = ${forceFlagValue(outputSettings.supportsWideColor)}`);

            if (outputSettings.supportsHdr !== undefined)
                parts.push(`supports_hdr = ${forceFlagValue(outputSettings.supportsHdr)}`);

            if (outputSettings.sdrMinLuminance !== undefined)
                parts.push(`sdr_min_luminance = ${Number(outputSettings.sdrMinLuminance)}`);

            if (outputSettings.sdrMaxLuminance !== undefined)
                parts.push(`sdr_max_luminance = ${Number(outputSettings.sdrMaxLuminance)}`);

            if (outputSettings.minLuminance !== undefined)
                parts.push(`min_luminance = ${Number(outputSettings.minLuminance)}`);

            if (outputSettings.maxLuminance !== undefined)
                parts.push(`max_luminance = ${Number(outputSettings.maxLuminance)}`);

            if (outputSettings.maxAvgLuminance !== undefined)
                parts.push(`max_avg_luminance = ${Number(outputSettings.maxAvgLuminance)}`);

            lines.push("hl.monitor({ " + parts.join(", ") + " })");
        }

        lines.push('hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })');
        lines.push("");
        return lines.join("\n");
    }

    function writeOutputsConfig(content, callback, skipReload) {
        Proc.runCommand("hypr-write-outputs", ["sh", "-c", `mkdir -p "${hyprDmsDir}" && cat > "${outputsPath}" << 'EOF'\n${content}EOF`], (output, exitCode) => {
            if (exitCode !== 0) {
                log.warn("Failed to write outputs config:", output);
                if (callback)
                    callback(false);
                return;
            }
            log.info("Generated outputs config at", outputsPath);
            if (CompositorService.isHyprland && !skipReload)
                reloadConfig();
            if (callback)
                callback(true);
        });
    }

    function reloadConfig(callback) {
        if (callback)
            _reloadCallbacks.push(callback);
        Proc.runCommand("hyprctl-reload", ["hyprctl", "reload"], (output, exitCode) => {
            if (exitCode !== 0)
                log.warn("hyprctl reload failed:", output);
            else
                Hyprland.refreshMonitors();
            const callbacks = _reloadCallbacks;
            _reloadCallbacks = [];
            callbacks.forEach(cb => cb(exitCode === 0));
        });
    }

    function liveMonitor(name) {
        if (!CompositorService.isHyprland)
            return null;
        return Hyprland.monitors.values.find(m => m.name === name) ?? null;
    }

    function _syncMonitorLayout() {
        const signature = Hyprland.monitors.values.map(m => `${m.name}:${m.x},${m.y},${m.scale},${m.lastIpcObject?.transform ?? 0}`).join("|");
        if (signature === _monitorLayoutSignature)
            return;
        _monitorLayoutSignature = signature;
        monitorLayoutChanged();
    }

    Instantiator {
        model: CompositorService.isHyprland ? Hyprland.monitors : null
        delegate: QtObject {
            required property HyprlandMonitor modelData
            readonly property var monitorLastIpcObject: modelData.lastIpcObject
            onMonitorLastIpcObjectChanged: root._syncMonitorLayout()
        }
    }

    function setLayoutXray(enabled) {
        layoutXrayEnabled = enabled;
        _layoutXrayLoaded = true;
        generateLayoutConfig();
    }

    function setLayoutBarXray(enabled) {
        layoutBarXrayEnabled = enabled;
        _layoutXrayLoaded = true;
        generateLayoutConfig();
    }

    function loadLayoutXrayState() {
        if (_layoutXrayLoading)
            return;
        _layoutXrayLoading = true;
        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        Proc.runCommand("hypr-read-layout-xray", ["cat", configDir + "/hypr/dms/layout.lua"], (output, exitCode) => {
            _layoutXrayLoading = false;
            if (!_layoutXrayLoaded) {
                const content = exitCode === 0 ? output : "";
                layoutXrayEnabled = content.includes('"^dms:.*$"');
                layoutBarXrayEnabled = !content.includes("-- bar-xray off");
                _layoutXrayLoaded = true;
            }
            if (layoutGenerationPending)
                layoutGenerationAction.schedule();
        });
    }

    function generateLayoutConfig(frameTransition) {
        if (!CompositorService.isHyprland)
            return;
        _layoutRequestRevision++;
        if (frameTransition === true)
            _frameTransitionRevision = _layoutRequestRevision;
        layoutGenerationPending = true;
        layoutGenerationAction.schedule();
    }

    function doGenerateLayoutConfig() {
        if (layoutGenerationRunning)
            return;
        if (!_layoutXrayLoaded) {
            loadLayoutXrayState();
            return;
        }
        layoutGenerationPending = false;
        const requestRevision = _layoutRequestRevision;
        if (!canWriteLuaConfig("layout")) {
            if (luaConfigStatusLoading || !luaConfigStatusReady) {
                layoutGenerationPending = true;
                return;
            }
            _layoutAppliedRevision = Math.max(_layoutAppliedRevision, requestRevision);
            return;
        }
        if (!hyprOptionsReady) {
            layoutGenerationPending = true;
            loadHyprOptionNames();
            return;
        }
        layoutGenerationRunning = true;

        const defaultGaps = typeof SettingsData !== "undefined" ? Math.max(4, (SettingsData.getPrimaryBarConfig()?.spacing ?? 4)) : 4;
        const defaultBorderSize = 2;

        const cornerRadius = Theme.windowRadius;
        const gapsOverride = typeof SettingsData !== "undefined" ? SettingsData.hyprlandLayoutGapsOverride : -1;
        const manageGaps = gapsOverride !== -2;
        const gapsIn = gapsOverride >= 0 ? gapsOverride : defaultGaps;
        const gapsOut = (gapsOverride >= 0 && SettingsData.hyprlandLayoutGapsOutOverride >= 0) ? SettingsData.hyprlandLayoutGapsOutOverride : gapsIn;
        const borderSize = (typeof SettingsData !== "undefined" && SettingsData.hyprlandLayoutBorderSize >= 0) ? SettingsData.hyprlandLayoutBorderSize : defaultBorderSize;
        const resizeOnBorder = (typeof SettingsData !== "undefined" && SettingsData.hyprlandResizeOnBorder) ? true : false;
        const frameEnabled = typeof SettingsData !== "undefined" && SettingsData.frameEnabled;
        // Hyprland `xray = false` is still early-development; unset already samples real content, so only force xray=true
        // dms:frame only in separate mode — connected-mode frame blur overlaps windows via popouts/arcs
        const xrayNamespaces = ["dms:bar"];
        if (typeof SettingsData !== "undefined" && SettingsData.dankIslandEnabled)
            xrayNamespaces.push("dms:dankisland");
        if (frameEnabled && SettingsData.frameMode !== "connected")
            xrayNamespaces.push("dms:frame");

        const tilingLayout = typeof SettingsData !== "undefined" ? SettingsData.hyprlandTilingLayout : "";

        const generalLines = [];
        if (manageGaps)
            generalLines.push(`gaps_in = ${gapsIn},`, `gaps_out = ${gapsOut},`);
        generalLines.push(`border_size = ${borderSize},`, `resize_on_border = ${resizeOnBorder},`);
        if (resizeOnBorder && SettingsData.hyprlandBorderGrabArea !== 15)
            generalLines.push(`extend_border_grab_area = ${SettingsData.hyprlandBorderGrabArea},`);
        if (tilingLayout)
            generalLines.push(`layout = ${luaString(tilingLayout)},`);

        const luaSection = (name, lines) => `\t${name} = {\n${lines.map(l => "\t\t" + l).join("\n")}\n\t},`;
        const sections = [luaSection("general", generalLines)];
        const tilingLines = tilingLayoutLines(tilingLayout);
        if (tilingLines.length)
            sections.push(luaSection(tilingLayout, tilingLines));
        sections.push(luaSection("decoration", decorationLines(SettingsData, cornerRadius)));
        const groupLines = luaTable("groupbar", groupbarLines(SettingsData));
        if (groupLines.length)
            sections.push(luaSection("group", groupLines));
        const binds = bindsLines(SettingsData);
        if (binds.length)
            sections.push(luaSection("binds", binds));
        const misc = miscLines(SettingsData);
        if (misc.length)
            sections.push(luaSection("misc", misc));

        let content = `-- Auto-generated by DMS — do not edit manually

hl.config({
${sections.join("\n")}
})
`;

        if (layoutXrayEnabled) {
            content += `
hl.layer_rule({
	match = { namespace = "^dms:.*$" },
	xray = true,
})
`;
        }
        if (layoutBarXrayEnabled) {
            for (const ns of xrayNamespaces) {
                content += `
hl.layer_rule({
	match = { namespace = "^${ns}$" },
	xray = true,
})
`;
            }
        }
        // Marker persists the preference even while the rule has no target
        if (!layoutBarXrayEnabled) {
            content += `
-- bar-xray off
`;
        }

        Proc.runCommand("hypr-write-layout", ["sh", "-c", `mkdir -p "${hyprDmsDir}" && cat > "${layoutPath}" << 'EOF'\n${content}EOF`], (output, exitCode) => {
            if (exitCode !== 0) {
                log.warn("Failed to write layout config:", output);
                // Best-effort ack so a failed write can't wedge frame transitions
                _layoutAppliedRevision = Math.max(_layoutAppliedRevision, requestRevision);
                layoutGenerationRunning = false;
                if (layoutGenerationPending)
                    layoutGenerationAction.schedule();
                return;
            }
            log.info("Generated layout config at", layoutPath);
            reloadConfig(success => {
                // Advance even on failure — proceed degraded rather than wedge the transition
                _layoutAppliedRevision = Math.max(_layoutAppliedRevision, requestRevision);
                layoutGenerationRunning = false;
                if (layoutGenerationPending)
                    layoutGenerationAction.schedule();
            });
        });
    }

    function tilingLayoutLines(layout) {
        switch (layout) {
        case "dwindle":
            return [`preserve_split = ${SettingsData.hyprlandDwindlePreserveSplit},`, `smart_split = ${SettingsData.hyprlandDwindleSmartSplit},`, `force_split = ${SettingsData.hyprlandDwindleForceSplit},`];
        case "master":
            return [`orientation = ${luaString(SettingsData.hyprlandMasterOrientation)},`, `new_status = ${luaString(SettingsData.hyprlandMasterNewStatus)},`, `new_on_top = ${SettingsData.hyprlandMasterNewOnTop},`, `mfact = ${SettingsData.hyprlandMasterSize / 100},`];
        case "scrolling":
            return [`direction = ${luaString(SettingsData.hyprlandScrollingDirection)},`, `column_width = ${SettingsData.hyprlandScrollingColumnWidth / 100},`, `fullscreen_on_one_column = ${SettingsData.hyprlandScrollingFullscreenOneColumn},`, `follow_focus = ${hyprMode(SettingsData.hyprlandScrollingFollowFocus)},`];
        default:
            return [];
        }
    }

    function luaTable(name, lines) {
        return lines.length ? [`${name} = {`, ...lines.map(l => "\t" + l), "},"] : [];
    }

    function blurLines(s) {
        const blur = BlurStrength.hyprlandBlur(s.blurStrength || BlurStrength.HYPRLAND_DEFAULT);
        const lines = [];
        if (blur.size !== 8)
            lines.push(`size = ${blur.size},`);
        if (blur.passes !== 1)
            lines.push(`passes = ${blur.passes},`);
        if (s.hyprlandBlurProportional && hyprSupports("decoration:blur:proportional"))
            lines.push("proportional = true,");
        const variant = s.hyprlandBlurVariant;
        if (!variant || variant === "kawase" || !hyprSupports("decoration:blur:variant"))
            return lines;
        // A user config with blur disabled would otherwise hide the chosen variant
        lines.push("enabled = true,", `variant = ${luaString(variant)},`);
        switch (variant) {
        case "ripple":
            return lines.concat(luaTable("ripple", [`strength = ${s.hyprlandBlurRippleStrength},`]));
        case "water":
            return lines.concat(luaTable("water", [`strength = ${s.hyprlandBlurWaterStrength},`]));
        case "drops":
            if (s.hyprlandBlurDropsSpeed === 3 || !hyprSupports("decoration:blur:drops:speed"))
                return lines;
            return lines.concat(luaTable("drops", [`speed = ${s.hyprlandBlurDropsSpeed},`]));
        case "heat_shimmer":
            if (s.hyprlandBlurHeatShimmerSpeed === 1 || !hyprSupports("decoration:blur:heat_shimmer:speed"))
                return lines;
            return lines.concat(luaTable("heat_shimmer", [`speed = ${s.hyprlandBlurHeatShimmerSpeed},`]));
        case "acrylic":
            return lines.concat(luaTable("acrylic", [`clarity = ${s.hyprlandBlurAcrylicClarity / 100},`]));
        case "aurora":
            return lines.concat(luaTable("aurora", [`intensity = ${s.hyprlandBlurAuroraIntensity / 100},`, `speed = ${s.hyprlandBlurAuroraSpeed},`]));
        case "haze":
            return lines.concat(luaTable("haze", [`intensity = ${s.hyprlandBlurHazeIntensity / 100},`, `iridescence = ${s.hyprlandBlurHazeIridescence / 100},`]));
        default:
            return lines;
        }
    }

    function decorationLines(s, rounding) {
        const lines = [`rounding = ${rounding},`];
        if (s.hyprlandWindowOpacity < 100) {
            const opacity = (s.hyprlandWindowOpacity / 100).toFixed(2);
            lines.push(`active_opacity = ${opacity},`, `inactive_opacity = ${opacity},`);
        }
        lines.push(...luaTable("blur", blurLines(s)));
        if (s.hyprlandGlowEnabled && hyprSupports("decoration:glow:enabled"))
            lines.push(...luaTable("glow", ["enabled = true,", `range = ${s.hyprlandGlowRange},`, `render_power = ${s.hyprlandGlowRenderPower},`]));
        if (s.hyprlandWobbleEnabled && hyprSupports("decoration:wobble:enabled"))
            lines.push(...luaTable("wobble", ["enabled = true,", `intensity = ${s.hyprlandWobbleIntensity / 100},`, `stiffness = ${s.hyprlandWobbleStiffness},`]));
        if (s.hyprlandMotionBlurEnabled && hyprSupports("decoration:motion_blur:enabled"))
            lines.push(...luaTable("motion_blur", ["enabled = true,", `samples = ${s.hyprlandMotionBlurSamples},`]));
        return lines;
    }

    function groupbarLines(s) {
        const lines = [];
        if (s.hyprlandGroupbarBlur && hyprSupports("group:groupbar:blur"))
            lines.push("blur = true,");
        if (s.hyprlandGroupbarTextPadding > 0 && hyprSupports("group:groupbar:text_padding"))
            lines.push(`text_padding = ${s.hyprlandGroupbarTextPadding},`);
        if (!s.hyprlandGroupbarMiddleClickClose && hyprSupports("group:groupbar:middle_click_close"))
            lines.push("middle_click_close = false,");
        if (s.hyprlandGroupbarDisableWhenOnly && hyprSupports("group:groupbar:disable_when_only"))
            lines.push("disable_when_only = true,");
        return lines;
    }

    function bindsLines(s) {
        const lines = [];
        if (!s.hyprlandDragCenterWindow && hyprSupports("binds:drag_center_window"))
            lines.push("drag_center_window = false,");
        if (s.hyprlandWorkspaceBackAndForth > 0 && hyprSupports("binds:workspace_back_and_forth"))
            lines.push(`workspace_back_and_forth = ${hyprMode(s.hyprlandWorkspaceBackAndForth)},`);
        return lines;
    }

    function miscLines(s) {
        const lines = [];
        if (s.hyprlandExitWindowRetainsFullscreen > 0 && hyprSupports("misc:exit_window_retains_fullscreen"))
            lines.push(`exit_window_retains_fullscreen = ${hyprMode(s.hyprlandExitWindowRetainsFullscreen)},`);
        if (s.hyprlandBellSound !== "default" && hyprSupports("misc:bell_sound"))
            lines.push(`bell_sound = ${luaString(s.hyprlandBellSound)},`);
        return lines;
    }

    function generateCursorConfig() {
        if (!CompositorService.isHyprland)
            return;
        if (!canWriteLuaConfig("cursor"))
            return;
        cursorGenerationPending = false;

        const settings = typeof SettingsData !== "undefined" ? SettingsData.cursorSettings : null;
        if (!settings) {
            Proc.runCommand("hypr-write-cursor", ["sh", "-c", `mkdir -p "${hyprDmsDir}" && printf '%s\\n' "-- Auto-generated by DMS — do not edit manually" "" > "${cursorPath}"`], (output, exitCode) => {
                if (exitCode !== 0)
                    log.warn("Failed to write cursor config:", output);
            });
            return;
        }

        const themeName = settings.theme === "System Default" ? (SettingsData.systemDefaultCursorTheme || "") : settings.theme;
        const size = settings.size || 24;
        const hideOnKeyPress = settings.hyprland?.hideOnKeyPress || false;
        const hideOnTouch = settings.hyprland?.hideOnTouch || false;
        const inactiveTimeout = settings.hyprland?.inactiveTimeout || 0;
        const warpOnMonitorChange = settings.hyprland?.warpOnMonitorChange ?? -1;
        if (warpOnMonitorChange !== -1 && !hyprOptionsReady) {
            cursorGenerationPending = true;
            loadHyprOptionNames();
            return;
        }
        const writeWarp = warpOnMonitorChange !== -1 && hyprSupports("cursor:warp_on_monitor_change");

        const hasTheme = themeName && themeName.length > 0;
        const hasNonDefaultSize = size !== 24;
        const hasCursorSettings = hideOnKeyPress || hideOnTouch || inactiveTimeout > 0 || writeWarp;

        if (!hasTheme && !hasNonDefaultSize && !hasCursorSettings) {
            Proc.runCommand("hypr-write-cursor", ["sh", "-c", `mkdir -p "${hyprDmsDir}" && printf '%s\\n' "-- Auto-generated by DMS — do not edit manually" "" > "${cursorPath}"`], (output, exitCode) => {
                if (exitCode !== 0)
                    log.warn("Failed to write cursor config:", output);
            });
            return;
        }

        let lines = ["-- Auto-generated by DMS — do not edit manually", ""];

        if (hasTheme) {
            lines.push(`hl.env("HYPRCURSOR_THEME", ${luaQuoted(themeName)})`);
            lines.push(`hl.env("XCURSOR_THEME", ${luaQuoted(themeName)})`);
        }
        lines.push(`hl.env("HYPRCURSOR_SIZE", ${luaQuoted(String(size))})`);
        lines.push(`hl.env("XCURSOR_SIZE", ${luaQuoted(String(size))})`);

        if (hasCursorSettings) {
            lines.push("");
            lines.push("hl.config({");
            lines.push("\tcursor = {");
            if (hideOnKeyPress)
                lines.push("\t\thide_on_key_press = true,");
            if (hideOnTouch)
                lines.push("\t\thide_on_touch = true,");
            if (inactiveTimeout > 0)
                lines.push(`\t\tinactive_timeout = ${inactiveTimeout},`);
            if (writeWarp)
                lines.push(`\t\twarp_on_monitor_change = ${warpOnMonitorChange},`);
            lines.push("\t},");
            lines.push("})");
        }

        lines.push("");
        const content = lines.join("\n");

        Proc.runCommand("hypr-write-cursor", ["sh", "-c", `mkdir -p "${hyprDmsDir}" && cat > "${cursorPath}" << 'EOF'\n${content}EOF`], (output, exitCode) => {
            if (exitCode !== 0) {
                log.warn("Failed to write cursor config:", output);
                return;
            }
            if (hasTheme)
                Proc.runCommand("hyprctl-setcursor", ["hyprctl", "setcursor", themeName, String(size)], () => {});
            reloadConfig();
        });
    }

    function generateInputConfig() {
        if (!CompositorService.isHyprland)
            return;
        inputGenerationPending = true;
        inputGenerationAction.schedule();
    }

    function doGenerateInputConfig() {
        if (inputGenerationRunning)
            return;
        inputGenerationPending = false;
        if (!canWriteLuaConfig("input")) {
            if (luaConfigStatusLoading || !luaConfigStatusReady)
                inputGenerationPending = true;
            return;
        }
        if (!hyprOptionsReady || !hyprDevicesReady) {
            inputGenerationPending = true;
            loadHyprOptionNames();
            loadHyprTouchpads();
            return;
        }
        inputGenerationRunning = true;

        let content = "-- Auto-generated by DMS — do not edit manually\n";
        const lines = inputLines(SettingsData);
        if (lines.length)
            content += `\nhl.config({\n\tinput = {\n${lines.map(l => "\t\t" + l).join("\n")}\n\t},\n})\n`;
        const devices = touchpadDeviceLines(SettingsData, hyprTouchpadNames);
        if (devices.length)
            content += "\n" + devices.join("\n") + "\n";

        // Exit 3 = unchanged, so a shell start does not reload Hyprland for nothing
        const script = `mkdir -p "${hyprDmsDir}" && cat > "${inputPath}.tmp" << 'EOF'\n${content}EOF\nif cmp -s "${inputPath}.tmp" "${inputPath}"; then rm -f "${inputPath}.tmp"; exit 3; fi\nmv -f "${inputPath}.tmp" "${inputPath}"`;
        Proc.runCommand("hypr-write-input", ["sh", "-c", script], (output, exitCode) => {
            const finish = () => {
                inputGenerationRunning = false;
                if (inputGenerationPending)
                    inputGenerationAction.schedule();
            };
            if (exitCode === 3) {
                finish();
                return;
            }
            if (exitCode !== 0) {
                log.warn("Failed to write input config:", output);
                finish();
                return;
            }
            reloadConfig(finish);
        });
    }

    function hyprScrollMethod(method) {
        switch (method) {
        case "no-scroll":
            return "no_scroll";
        case "two-finger":
            return "2fg";
        case "edge":
            return "edge";
        case "on-button-down":
            return "on_button_down";
        default:
            return "";
        }
    }

    function touchpadNames(devices) {
        return (devices?.mice ?? []).map(mouse => mouse.name).filter(name => /touchpad|trackpad|synaptics|elan/i.test(name ?? ""));
    }

    // Keys the setup template sets are always written, everything else only when it differs from Hyprland's default
    function inputLines(s) {
        const lines = [];
        const add = (option, line) => {
            if (hyprSupports(option))
                lines.push(line);
        };
        // -1 leaves existing follow_mouse modes untouched until the user operates the toggle.
        if (s.focusFollowsMouse === 0 || s.focusFollowsMouse === 1)
            add("input:follow_mouse", `follow_mouse = ${s.focusFollowsMouse},`);
        if (s.mouseAccelSpeed !== 0)
            add("input:sensitivity", `sensitivity = ${s.mouseAccelSpeed.toFixed(2)},`);
        if (s.mouseAccelProfile !== "default")
            add("input:accel_profile", `accel_profile = ${luaString(s.mouseAccelProfile)},`);
        if (s.mouseNaturalScroll)
            add("input:natural_scroll", "natural_scroll = true,");
        if (s.mouseLeftHanded)
            add("input:left_handed", "left_handed = true,");
        if (s.hyprlandSwallowFocusClick)
            add("input:swallow_focus_click", "swallow_focus_click = true,");
        if (s.mouseScrollFactor !== 1)
            add("input:scroll_factor", `scroll_factor = ${s.mouseScrollFactor.toFixed(2)},`);
        const scrollMethod = hyprScrollMethod(s.mouseScrollMethod);
        if (scrollMethod)
            add("input:scroll_method", `scroll_method = ${luaString(scrollMethod)},`);
        // Mouse middle emulation has no global key; Hyprland reads input:touchpad:middle_button_emulation for every pointer

        const touchpad = [];
        const addTouchpad = (option, line) => {
            if (hyprSupports("input:touchpad:" + option))
                touchpad.push(line);
        };
        addTouchpad("natural_scroll", `natural_scroll = ${s.touchpadNaturalScroll},`);
        addTouchpad("tap-to-click", `tap_to_click = ${s.touchpadTapToClick},`);
        if (!s.touchpadTapAndDrag)
            addTouchpad("tap-and-drag", "tap_and_drag = false,");
        if (s.touchpadDragLock)
            addTouchpad("drag_lock", "drag_lock = 1,");
        if (!s.touchpadDisableWhileTyping)
            addTouchpad("disable_while_typing", "disable_while_typing = false,");
        if (s.touchpadMiddleEmulation)
            addTouchpad("middle_button_emulation", "middle_button_emulation = true,");
        if (s.touchpadScrollFactor !== 1)
            addTouchpad("scroll_factor", `scroll_factor = ${s.touchpadScrollFactor.toFixed(2)},`);
        if (s.touchpadClickMethod !== "default")
            addTouchpad("clickfinger_behavior", `clickfinger_behavior = ${s.touchpadClickMethod === "clickfinger"},`);
        lines.push(...luaTable("touchpad", touchpad));
        if (!s.hyprlandTabletEnabled && hyprSupports("input:tablet:enabled"))
            lines.push(...luaTable("tablet", ["enabled = false,"]));

        // Unconfigured keyboard keeps the user's own kb_* keys and XKB_DEFAULT_LAYOUT
        const keyboardConfigured = s.keyboardKeymapFile || s.keyboardLayouts || s.keyboardVariants || s.keyboardModel || s.keyboardOptions || s.keyboardRepeatDelay > 0 || s.keyboardRepeatRate > 0 || s.keyboardNumlock;
        if (!keyboardConfigured)
            return lines;
        if (s.keyboardKeymapFile) {
            add("input:kb_file", `kb_file = ${luaString(s.keyboardKeymapFile)},`);
        } else {
            if (s.keyboardLayouts)
                add("input:kb_layout", `kb_layout = ${luaString(s.keyboardLayouts)},`);
            if (s.keyboardVariants)
                add("input:kb_variant", `kb_variant = ${luaString(s.keyboardVariants)},`);
            if (s.keyboardModel)
                add("input:kb_model", `kb_model = ${luaString(s.keyboardModel)},`);
            if (s.keyboardOptions)
                add("input:kb_options", `kb_options = ${luaString(s.keyboardOptions)},`);
        }
        if (s.keyboardRepeatDelay > 0)
            add("input:repeat_delay", `repeat_delay = ${s.keyboardRepeatDelay},`);
        if (s.keyboardRepeatRate > 0)
            add("input:repeat_rate", `repeat_rate = ${s.keyboardRepeatRate},`);
        add("input:numlock_by_default", `numlock_by_default = ${!!s.keyboardNumlock},`);
        return lines;
    }

    // Global sensitivity, accel_profile, scroll_method and left_handed also reach touchpads, so pin the touchpad's own values per device
    function touchpadDeviceLines(s, names) {
        const fields = [];
        if ((s.touchpadAccelSpeed !== 0 || s.mouseAccelSpeed !== 0) && hyprSupports("input:sensitivity"))
            fields.push(`sensitivity = ${s.touchpadAccelSpeed.toFixed(2)}`);
        if ((s.touchpadAccelProfile !== "default" || s.mouseAccelProfile !== "default") && hyprSupports("input:accel_profile"))
            fields.push(`accel_profile = ${luaString(s.touchpadAccelProfile === "default" ? "" : s.touchpadAccelProfile)}`);
        const scrollMethod = hyprScrollMethod(s.touchpadScrollMethod);
        if ((scrollMethod || hyprScrollMethod(s.mouseScrollMethod)) && hyprSupports("input:scroll_method"))
            fields.push(`scroll_method = ${luaString(scrollMethod)}`);
        if (s.mouseLeftHanded && hyprSupports("input:left_handed"))
            fields.push("left_handed = false");
        if (!fields.length)
            return [];
        return names.map(name => `hl.device({ name = ${luaString(name)}, ${fields.join(", ")} })`);
    }

    // renameWorkspace stores "<id> <name>"; hand back only the part the user typed.
    function focusedWorkspaceName() {
        const ws = Hyprland.focusedWorkspace;
        if (!ws?.id)
            return "";
        const prefix = ws.id + " ";
        if (ws.name.startsWith(prefix))
            return ws.name.slice(prefix.length);
        return ws.name === String(ws.id) ? "" : ws.name;
    }

    function renameWorkspace(newName) {
        if (!luaConfigActive)
            return;
        const ws = Hyprland.focusedWorkspace;
        if (!ws)
            return;
        const name = ws.id > 0 ? ws.id + " " + newName : newName;
        Hyprland.dispatch(`hl.dsp.workspace.rename({ workspace = ${luaValue(WorkspaceModel.hyprlandSelector(ws))}, name = ${luaString(name)} })`);
    }

    function focusWorkspace(workspace) {
        if (!luaConfigActive)
            return;
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${luaValue(workspace)} })`);
    }

    function luaString(value) {
        return `"${String(value ?? "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
    }

    function luaValue(value) {
        const text = String(value ?? "");
        // Signed selectors are relative ("+0", "-1") and Lua has no unary plus, so only plain ids stay bare
        return /^\d+$/.test(text) ? text : luaString(text);
    }

    function windowSelector(windowAddress) {
        if (!windowAddress)
            return "";

        const text = String(windowAddress);
        if (text.startsWith("address:"))
            return text;

        return `address:${text.startsWith("0x") ? text : "0x" + text}`;
    }

    function focusWindow(windowAddress) {
        if (!luaConfigActive)
            return;
        const selector = windowSelector(windowAddress);
        if (!selector)
            return;
        Hyprland.dispatch(`hl.dsp.focus({ window = ${luaString(selector)} })`);
    }

    function closeWindow(windowAddress) {
        if (!luaConfigActive)
            return;
        const selector = windowSelector(windowAddress);
        if (!selector)
            return;
        Hyprland.dispatch(`hl.dsp.window.close({ window = ${luaString(selector)} })`);
    }

    function moveToWorkspace(workspace, windowAddress, follow = true) {
        if (!luaConfigActive)
            return;
        const selector = windowSelector(windowAddress);
        if (!selector)
            return;
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${luaValue(workspace)}, window = ${luaString(selector)}, follow = ${follow ? "true" : "false"} })`);
    }

    function cycleWindow(forward) {
        if (!luaConfigActive)
            return;
        Hyprland.dispatch(`hl.dsp.window.cycle_next({ next = ${forward ? "true" : "false"} })`);
    }

    function focusMonitor(monitor) {
        if (!luaConfigActive)
            return;
        Hyprland.dispatch(`hl.dsp.focus({ monitor = ${luaString(monitor)} })`);
    }

    function toggleSpecial(specialName) {
        if (!luaConfigActive)
            return;
        Hyprland.dispatch(specialName ? `hl.dsp.workspace.toggle_special(${luaString(specialName)})` : "hl.dsp.workspace.toggle_special()");
    }

    function exit() {
        if (!luaConfigActive)
            return;
        Hyprland.dispatch("hl.dsp.exit()");
    }

    function dpmsOff() {
        if (!luaConfigActive)
            return;
        Hyprland.dispatch(`hl.dsp.dpms({ action = "disable" })`);
    }

    function dpmsOn() {
        if (!luaConfigActive)
            return;
        Hyprland.dispatch(`hl.dsp.dpms({ action = "enable" })`);
    }
}
