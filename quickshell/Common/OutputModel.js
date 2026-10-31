.pragma library

const TRANSFORM_NAMES = ["Normal", "90", "180", "270", "Flipped", "Flipped90", "Flipped180", "Flipped270"];
const WLR_SCALE_STEP = 1 / 256;
const SCALE_DENOMINATOR = 120;
const MIN_SCALE = 0.25;
const MIN_PRESET_SCALE = 0.5;
const MAX_SCALE = 4;
const GAP_FILL_MIN = 1;
const GAP_FILL_MAX = 2;
const GAP_FILL_STEP = 6;
const GAP_FILL_CLEARANCE = 4;
const LOGICAL_PIXEL_TOLERANCE = 0.01;
const FALLBACK_SCALE_PRESETS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];
const NIRI_TRANSFORMS = ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"];

function transformName(index) {
    if (!Number.isInteger(index))
        return "Normal";
    return TRANSFORM_NAMES[index] ?? "Normal";
}

function transformIndex(name) {
    const index = TRANSFORM_NAMES.indexOf(name);
    return index < 0 ? 0 : index;
}

function niriTransform(name) {
    const index = TRANSFORM_NAMES.indexOf(name);
    return index < 0 ? "normal" : NIRI_TRANSFORMS[index];
}

function isRotated(name) {
    return ["90", "270", "Flipped90", "Flipped270"].includes(name);
}

function niriIdentifier(output, name, displayNameMode) {
    if (displayNameMode !== "model" || !output?.make || !output?.model)
        return name;
    return output.make + " " + output.model + " " + (output.serial || "Unknown");
}

function hyprlandIdentifier(output, name, displayNameMode) {
    if (displayNameMode !== "model" || !output?.make || !output?.model)
        return name;
    return ("desc:" + [output.make, output.model, output.serial].filter(p => p).join(" ")).replace(/,/g, "");
}

// monitors.json keys Hyprland profiles by bare "Make Model", which hl.monitor ignores; only a connector or desc: matches
function hyprlandProfileOutputIdentifier(output, key, isConnector) {
    if (isConnector || key.startsWith("desc:") || !output?.make || !output?.model)
        return key;
    return hyprlandIdentifier(output, key, "model");
}

function modelIdentifier(output) {
    return output.make + " " + output.model;
}

function profileIdentifier(output, name, displayNameMode, compositor) {
    if (displayNameMode !== "model" || !output?.make || !output?.model)
        return name;
    switch (compositor) {
    case "niri":
        return niriIdentifier(output, name, displayNameMode);
    default:
        return modelIdentifier(output);
    }
}

function extractNiriOutputBlocks(content) {
    const blocks = [];
    const headerRegex = /output\s+"([^"]+)"\s*\{/g;
    let match;
    while ((match = headerRegex.exec(content)) !== null) {
        const start = headerRegex.lastIndex;
        let depth = 1;
        let i = start;
        while (i < content.length && depth > 0) {
            const ch = content[i];
            if (ch === '{')
                depth++;
            else if (ch === '}')
                depth--;
            i++;
        }
        blocks.push({
            "name": match[1],
            "body": content.slice(start, i - 1)
        });
        headerRegex.lastIndex = i;
    }
    return blocks;
}

function stripNestedBlocks(body) {
    let stripped = body;
    let prev;
    do {
        prev = stripped;
        stripped = stripped.replace(/[\w-]+\s*\{[^{}]*\}/g, "");
    } while (stripped !== prev)
    return stripped;
}

function hyprLuaField(line, field) {
    const re = new RegExp("\\b" + field + "\\s*=\\s*(\\\"(?:\\\\\\\\.|[^\\\"])*\\\"|'(?:\\\\\\\\.|[^'])*'|\\[\\[.*?\\]\\]|[^,}\\s]+)");
    const match = line.match(re);
    if (!match)
        return undefined;
    const raw = match[1].trim();
    if (raw.startsWith("[[") && raw.endsWith("]]"))
        return raw.slice(2, -2);
    if (raw.startsWith("\"")) {
        try {
            return JSON.parse(raw);
        } catch (e) {
            return raw.slice(1, -1);
        }
    }
    if (raw.startsWith("'") && raw.endsWith("'"))
        return raw.slice(1, -1).replace(/\\'/g, "'");
    if (raw === "true")
        return true;
    if (raw === "false")
        return false;
    const num = Number(raw);
    return isNaN(num) ? raw : num;
}

function parsedMode(width, height, refresh) {
    return {
        "width": parseInt(width),
        "height": parseInt(height),
        "refresh_rate": Math.round(parseFloat(refresh) * 1000)
    };
}

function parseNiriOutputs(content) {
    const result = {};
    for (const block of extractNiriOutputBlocks(content)) {
        const name = block.name;
        const body = block.body;

        // top-level off only, nested hot-corners { off } must not count (#2966)
        const disabled = /^\s*off\s*$/m.test(stripNestedBlocks(body));
        const modeMatch = body.match(/mode\s+"(\d+)x(\d+)@([\d.]+)"/);
        const posMatch = body.match(/position\s+x=(-?\d+)\s+y=(-?\d+)/);
        const scaleMatch = body.match(/scale\s+([\d.]+)/);
        const transformMatch = body.match(/transform\s+"([^"]+)"/);
        const vrrMatch = body.match(/variable-refresh-rate/);
        const vrrOnDemandMatch = body.match(/variable-refresh-rate\s+on-demand=true/);

        result[name] = {
            "name": name,
            "disabled": disabled,
            "logical": {
                "x": posMatch ? parseInt(posMatch[1]) : 0,
                "y": posMatch ? parseInt(posMatch[2]) : 0,
                "scale": scaleMatch ? parseFloat(scaleMatch[1]) : 1.0,
                "transform": transformMatch ? transformMatch[1] : "Normal"
            },
            "modes": modeMatch ? [parsedMode(modeMatch[1], modeMatch[2], modeMatch[3])] : [],
            "current_mode": 0,
            "vrr_enabled": !!vrrMatch,
            "vrr_on_demand": !!vrrOnDemandMatch,
            "vrr_supported": true
        };
    }
    return result;
}

function hyprLuaSettings(line, disabled, vrrMode) {
    return {
        "vrr": vrrMode,
        "disabled": disabled || undefined,
        "bitdepth": hyprLuaField(line, "bitdepth"),
        "colorManagement": hyprLuaField(line, "cm"),
        "sdrBrightness": hyprLuaField(line, "sdrbrightness"),
        "sdrSaturation": hyprLuaField(line, "sdrsaturation"),
        "supportsWideColor": hyprLuaField(line, "supports_wide_color"),
        "supportsHdr": hyprLuaField(line, "supports_hdr"),
        "sdrEotf": hyprLuaField(line, "sdr_eotf"),
        "icc": hyprLuaField(line, "icc"),
        "sdrMinLuminance": hyprLuaField(line, "sdr_min_luminance"),
        "sdrMaxLuminance": hyprLuaField(line, "sdr_max_luminance"),
        "minLuminance": hyprLuaField(line, "min_luminance"),
        "maxLuminance": hyprLuaField(line, "max_luminance"),
        "maxAvgLuminance": hyprLuaField(line, "max_avg_luminance")
    };
}

function parseHyprlandLuaMonitorLine(line) {
    if (!line.match(/^\s*hl\.monitor\s*\(/))
        return null;
    const name = hyprLuaField(line, "output");
    // output = "" is the catch-all fallback, not a monitor; the writer re-emits it verbatim.
    if (name === undefined || String(name).trim() === "")
        return null;
    const disabled = hyprLuaField(line, "disabled") === true;
    const mode = hyprLuaField(line, "mode") || "preferred";
    const position = hyprLuaField(line, "position") || "0x0";
    const scaleValue = hyprLuaField(line, "scale");
    const transform = Number(hyprLuaField(line, "transform") ?? 0);
    const vrrField = hyprLuaField(line, "vrr");
    const vrrMode = vrrField === undefined || isNaN(Number(vrrField)) ? undefined : Number(vrrField);
    const posMatch = String(position).match(/^(-?\d+)x(-?\d+)$/);
    const modeMatch = String(mode).match(/^(\d+)x(\d+)@([\d.]+)/);
    return {
        "name": String(name),
        "logical": {
            "x": posMatch ? parseInt(posMatch[1]) : 0,
            "y": posMatch ? parseInt(posMatch[2]) : 0,
            "scale": typeof scaleValue === "number" ? scaleValue : 1.0,
            "transform": transformName(transform)
        },
        "modes": modeMatch ? [parsedMode(modeMatch[1], modeMatch[2], modeMatch[3])] : [],
        "current_mode": modeMatch ? 0 : -1,
        "vrr_enabled": vrrMode >= 1,
        "vrr_supported": vrrMode > 0,
        "hyprlandSettings": hyprLuaSettings(line, disabled, vrrMode),
        "mirror": hyprLuaField(line, "mirror") || "",
        "autoPosition": posMatch ? undefined : String(position),
        "autoScale": scaleValue === "auto" ? true : undefined
    };
}

// Keeps Hyprland's "auto" words while the written value still equals what Hyprland resolved them to.
function hyprlandLuaGeometry(output, saved, live) {
    const x = output?.logical?.x ?? 0;
    const y = output?.logical?.y ?? 0;
    const scale = Number(output?.logical?.scale ?? 1.0);
    const resolved = live || saved?.logical || {};
    const keepPosition = !!saved?.autoPosition && x === resolved.x && y === resolved.y;
    const keepScale = saved?.autoScale === true && Math.abs(scale - Number(resolved.scale)) <= WLR_SCALE_STEP;
    return {
        "position": keepPosition ? saved.autoPosition : x + "x" + y,
        "scale": keepScale ? "auto" : hyprlandScaleValue(scale)
    };
}

// Hyprland snaps to the nearest n/120 itself; writing that keeps a live float32 scale and the UI preset byte-identical.
function hyprlandScaleValue(scale) {
    const value = Number(scale);
    if (!isFinite(value) || value <= 0)
        return 1;
    const numerator = Math.round(value * SCALE_DENOMINATOR);
    if (Math.abs(numerator / SCALE_DENOMINATOR - value) <= WLR_SCALE_STEP)
        return scaleFromNumerator(numerator);
    return parseFloat(value.toFixed(6));
}

// Unset per-monitor vrr inherits misc:vrr (Hyprland 0.56); -1 is the explicit "inherit" choice.
// A bare vrr = 0 in the file is what DMS used to write for every untouched monitor, so it is not a choice.
function hyprlandVrrMode(settings, saved) {
    const chosen = settings?.vrr;
    if (Number.isInteger(chosen))
        return chosen < 0 ? undefined : chosen;
    if (settings?.vrrFullscreenOnly)
        return 2;
    const fromFile = saved?.hyprlandSettings?.vrr;
    return Number.isInteger(fromFile) && fromFile > 0 ? fromFile : undefined;
}

// hardwareDetails exists from Hyprland 0.57; null means unknown and gates nothing.
function hyprlandHardware(ipcObject) {
    const details = ipcObject?.hardwareDetails;
    if (!details || typeof details !== "object")
        return null;
    return {
        "hdr": details.hdr === true,
        "chroma": details.chroma === true,
        "bt2020": details.bt2020 === true,
        "vrrCapable": details.vrrCapable === true
    };
}

function forcedFlag(value, fallback) {
    if (value === true || value === 1)
        return true;
    if (value === false || value === -1)
        return false;
    return fallback;
}

// Mirrors CMonitor::supportsWideColor/supportsHDR: a forced supports_* flag beats the EDID.
function hyprlandCaps(hardware, settings) {
    if (!hardware)
        return null;
    const wideColor = forcedFlag(settings?.supportsWideColor, hardware.bt2020);
    return {
        "vrr": hardware.vrrCapable,
        "wideColor": wideColor,
        "hdr": wideColor && forcedFlag(settings?.supportsHdr, hardware.hdr),
        "edidColor": hardware.chroma
    };
}

// Hyprland falls back to sRGB for edid without EDID primaries and for hdr/hdredid without HDR support.
function hyprlandCmAllowed(cm, caps) {
    if (!caps)
        return true;
    switch (cm) {
    case "wide":
        return caps.wideColor;
    case "edid":
        return caps.edidColor;
    case "hdr":
    case "hdredid":
        return caps.hdr;
    default:
        return true;
    }
}

function parseHyprlandDisableLine(line) {
    const disableMatch = line.match(/^\s*monitor\s*=\s*([^,]+),\s*disable\s*$/);
    if (!disableMatch)
        return null;
    return {
        "name": disableMatch[1].trim(),
        "logical": {
            "x": 0,
            "y": 0,
            "scale": 1.0,
            "transform": "Normal"
        },
        "modes": [],
        "current_mode": -1,
        "vrr_enabled": false,
        "vrr_supported": false
    };
}

function parseHyprlandMonitorLine(line) {
    const match = line.match(/^\s*monitor\s*=\s*([^,]+),\s*(\d+)x(\d+)@([\d.]+),\s*(-?\d+)x(-?\d+),\s*([\d.]+)/);
    if (!match)
        return null;
    const rest = line.substring(match[0].length);
    const transformMatch = rest.match(/,\s*transform,\s*(\d+)/);
    const vrrMatch = rest.match(/,\s*vrr,\s*(\d+)/);
    const mirrorMatch = rest.match(/,\s*mirror,\s*([^,\s]+)/);
    return {
        "name": match[1].trim(),
        "logical": {
            "x": parseInt(match[5]),
            "y": parseInt(match[6]),
            "scale": parseFloat(match[7]),
            "transform": transformName(transformMatch ? parseInt(transformMatch[1]) : 0)
        },
        "modes": [parsedMode(match[2], match[3], match[4])],
        "current_mode": 0,
        "vrr_enabled": vrrMatch ? parseInt(vrrMatch[1]) >= 1 : false,
        "vrr_supported": true,
        "mirror": mirrorMatch ? mirrorMatch[1] : ""
    };
}

function collectOutputs(content, parseLine) {
    const result = {};
    for (const line of content.split("\n")) {
        const entry = parseLine(line);
        if (!entry)
            continue;
        result[entry.name] = entry;
    }
    return result;
}

function parseHyprlandOutputs(content) {
    return collectOutputs(content, parseHyprlandLuaMonitorLine);
}

// Only for migrating DMS 1.x display profiles saved as hypr/dms/profiles/*.conf
function parseHyprlandConfProfile(content) {
    return collectOutputs(content, line => parseHyprlandDisableLine(line) || parseHyprlandMonitorLine(line));
}

function parseMangoRule(rule) {
    const params = {};
    for (const pair of rule.split(",")) {
        const colonIdx = pair.indexOf(":");
        if (colonIdx < 0)
            continue;
        params[pair.substring(0, colonIdx).trim()] = pair.substring(colonIdx + 1).trim();
    }
    const name = (params.name || "").replace(/^\^/, "").replace(/\$$/, "");
    if (!name)
        return null;
    return {
        "name": name,
        "logical": {
            "x": parseInt(params.x || "0"),
            "y": parseInt(params.y || "0"),
            "scale": parseFloat(params.scale || "1"),
            "transform": transformName(parseInt(params.rr || "0"))
        },
        "modes": [
            {
                "width": parseInt(params.width || "1920"),
                "height": parseInt(params.height || "1080"),
                "refresh_rate": parseFloat(params.refresh || "60") * 1000
            }
        ],
        "current_mode": 0,
        "vrr_enabled": parseInt(params.vrr || "0") === 1,
        "vrr_supported": true
    };
}

function parseMangoOutputs(content) {
    const result = {};
    for (const line of content.split("\n")) {
        const trimmed = line.trim();
        const match = trimmed.match(/^monitor_rule\s*=\s*(.*)$/);
        if (!match)
            continue;
        const entry = parseMangoRule(match[1]);
        if (!entry)
            continue;
        result[entry.name] = entry;
    }
    return result;
}

const mangoModeledRuleKeys = ["name", "width", "height", "refresh", "x", "y", "scale", "rr", "vrr"];

function mangoRuleFields(rule) {
    const fields = [];
    for (const pair of rule.split(",")) {
        const colonIdx = pair.indexOf(":");
        if (colonIdx > 0)
            fields.push([pair.substring(0, colonIdx).trim(), pair.substring(colonIdx + 1).trim()]);
    }
    return fields;
}

// Mango applies only the first matching monitor rule and resets hdr/icc/disable a rule omits,
// so unmodeled fields of every existing rule for an output are carried into DMS's rule, first one winning.
function mangoMonitorRuleLines(outputsData, existingText) {
    const carried = {};
    for (const line of (existingText || "").split("\n")) {
        const match = line.trim().match(/^monitor_rule\s*=\s*(.*)$/);
        if (!match)
            continue;
        const fields = mangoRuleFields(match[1]);
        const name = (fields.find(f => f[0] === "name")?.[1] || "").replace(/^\^/, "").replace(/\$$/, "");
        if (!name)
            continue;
        if (!carried[name])
            carried[name] = [];
        const kept = carried[name];
        for (const field of fields) {
            if (!mangoModeledRuleKeys.includes(field[0]) && !kept.some(k => k[0] === field[0]))
                kept.push(field);
        }
    }

    const lines = [];
    for (const outputName in outputsData) {
        const output = outputsData[outputName];
        if (!output)
            continue;
        let width = 1920;
        let height = 1080;
        let refreshRate = 60;
        const configured = (output.configured_mode || "").match(/^(\d+)x(\d+)@([\d.]+)$/);
        if (configured) {
            width = parseInt(configured[1], 10);
            height = parseInt(configured[2], 10);
            refreshRate = parseFloat(configured[3]);
        } else if (output.modes && output.current_mode !== undefined) {
            const mode = output.modes[output.current_mode];
            if (mode) {
                width = mode.width || 1920;
                height = mode.height || 1080;
                refreshRate = (mode.refresh_rate || 60000) / 1000;
            }
        }

        // Anchored: mango matches `name:` unanchored, so "DP-1" would also match "eDP-1".
        // Mango picks the nearest mode, so the refresh keeps its fraction.
        const fields = ["name:^" + outputName + "$", "width:" + width, "height:" + height, "refresh:" + Number(refreshRate.toFixed(3)), "x:" + (output.logical?.x ?? 0), "y:" + (output.logical?.y ?? 0), "scale:" + (output.logical?.scale ?? 1.0), "rr:" + transformIndex(output.logical?.transform ?? "Normal"), "vrr:" + (output.vrr_enabled ? 1 : 0)];
        for (const [key, value] of carried[outputName] || []) {
            if (key === "disable" && output.enabled !== undefined)
                continue;
            fields.push(key + ":" + value);
        }
        if (output.enabled === false)
            fields.push("disable:1");
        lines.push("monitor_rule=" + fields.join(","));
    }
    return lines;
}

function outputsFromWlr(wlrOutputs, liveMonitors) {
    const map = {};
    for (const output of wlrOutputs) {
        const normalizedModes = (output.modes || []).map(m => ({
                    "id": m.id,
                    "width": m.width,
                    "height": m.height,
                    "refresh_rate": m.refresh,
                    "preferred": m.preferred ?? false
                }));
        map[output.name] = {
            "name": output.name,
            "enabled": output.enabled ?? true,
            "make": output.make || "",
            "model": output.model || "",
            "serial": output.serialNumber || "",
            "modes": normalizedModes,
            "current_mode": normalizedModes.findIndex(m => m.id === output.currentMode?.id),
            "vrr_supported": output.adaptiveSyncSupported ?? false,
            "vrr_enabled": output.adaptiveSync === 1,
            "logical": {
                "x": output.x ?? 0,
                "y": output.y ?? 0,
                "width": output.currentMode?.width ?? 1920,
                "height": output.currentMode?.height ?? 1080,
                "scale": output.scale || 1.0,
                "transform": transformName(output.transform)
            }
        };
        const live = liveMonitors[output.name];
        if (!live)
            continue;
        if (live.hardware)
            map[output.name].hardware = live.hardware;
        map[output.name].logical.x = live.x;
        map[output.name].logical.y = live.y;
        map[output.name].logical.scale = live.scale || 1.0;
        map[output.name].logical.transform = transformName(live.transformIndex ?? 0);
    }
    return map;
}

function outputNeutralConfig(outputName, outputData, niriSettings, hyprlandSettings, displayNameMode, compositor) {
    const modeData = (outputData.modes && outputData.current_mode !== undefined) ? outputData.modes[outputData.current_mode] : null;
    const modeStr = modeData ? modeData.width + "x" + modeData.height + "@" + (modeData.refresh_rate / 1000).toFixed(3) : null;
    const cfg = {
        "mode": modeStr,
        "position": {
            "x": outputData.logical?.x ?? 0,
            "y": outputData.logical?.y ?? 0
        },
        "scale": outputData.logical?.scale || 1.0,
        "transform": outputData.logical?.transform ?? "Normal",
        "vrr": outputData.vrr_enabled ?? false,
        "disabled": false
    };
    switch (compositor) {
    case "niri":
        cfg.niri = Object.assign({}, niriSettings?.[niriIdentifier(outputData, outputName, displayNameMode)] || {});
        if (cfg.niri.disabled) {
            delete cfg.niri.disabled;
            cfg.disabled = true;
        }
        return cfg;
    case "hyprland":
        cfg.hyprland = Object.assign({}, hyprlandSettings?.[hyprlandIdentifier(outputData, outputName, displayNameMode)] || {});
        if (outputData.mirror)
            cfg.hyprland.mirror = outputData.mirror;
        if (cfg.hyprland.disabled) {
            delete cfg.hyprland.disabled;
            cfg.disabled = true;
        }
        return cfg;
    default:
        return cfg;
    }
}

function profileKeyMatchesOutput(outputId, output, name, displayNameMode, compositor) {
    if (name === outputId || profileIdentifier(output, name, displayNameMode, compositor) === outputId)
        return true;
    if (!outputId.startsWith("desc:") || !output?.make)
        return false;
    const want = outputId.slice(5).trim();
    const full = [output.make, output.model, output.serial].filter(p => p).join(" ").replace(/,/g, "");
    const noSerial = [output.make, output.model].filter(p => p).join(" ").replace(/,/g, "");
    return want === full || want === noSerial || full.startsWith(want + " ");
}

function liveOutputForKey(outputId, outputs, displayNameMode, compositor) {
    for (const name in outputs) {
        if (profileKeyMatchesOutput(outputId, outputs[name], name, displayNameMode, compositor))
            return outputs[name];
    }
    return null;
}

function outputsDataFromConfigEntry(configEntry, outputs, displayNameMode, compositor) {
    const result = {};
    const cfgOutputs = configEntry.outputs || {};
    for (const outputId in cfgOutputs) {
        const cfg = cfgOutputs[outputId];
        const liveOutput = liveOutputForKey(outputId, outputs, displayNameMode, compositor);
        const liveModes = liveOutput?.modes || [];
        const currentMode = liveModes.findIndex(m => {
            const s = m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3);
            return s === cfg.mode;
        });
        const entry = {
            "name": outputId,
            "explicitIdentifier": true,
            "configured_mode": cfg.mode || "",
            "make": liveOutput?.make || "",
            "model": liveOutput?.model || "",
            "serial": liveOutput?.serial || "",
            "modes": liveModes,
            "current_mode": currentMode,
            "vrr_supported": liveOutput?.vrr_supported ?? false,
            "vrr_enabled": cfg.vrr ?? false,
            "logical": {
                "x": cfg.position?.x ?? 0,
                "y": cfg.position?.y ?? 0,
                "scale": cfg.scale ?? 1.0,
                "transform": cfg.transform ?? "Normal"
            }
        };
        if (cfg.hyprland?.mirror)
            entry.mirror = cfg.hyprland.mirror;
        if (liveOutput?.hardware)
            entry.hardware = liveOutput.hardware;
        result[outputId] = entry;
    }
    return result;
}

function configFingerprint(configEntry) {
    return Object.keys(configEntry.outputs || {}).sort().join("+");
}

function outputSetFingerprint(outputIdentifiers) {
    return [...outputIdentifiers].sort().join("+");
}

function findConfigEntryById(data, id) {
    const configs = data.configurations || [];
    for (let i = 0; i < configs.length; i++) {
        if (configs[i].id === id)
            return {
                entry: configs[i],
                index: i
            };
    }
    return null;
}

function findConfigEntryByFingerprint(data, outputIdentifiers, autoOnly) {
    const targetKey = outputSetFingerprint(outputIdentifiers);
    const configs = data.configurations || [];
    let firstUnnamed = null;
    for (let i = 0; i < configs.length; i++) {
        if (configFingerprint(configs[i]) !== targetKey)
            continue;
        if (configs[i].name && !autoOnly)
            return {
                entry: configs[i],
                index: i
            };
        if (!configs[i].name && !firstUnnamed)
            firstUnnamed = {
                entry: configs[i],
                index: i
            };
    }
    return firstUnnamed;
}

function profileOutputIsReal(outputId, outputs, displayNameMode, compositor) {
    const live = liveOutputForKey(outputId, outputs, displayNameMode, compositor);
    if (!live)
        return true;
    return !!(live.make && live.model);
}

function ensureEnabledOutput(configEntry, outputs, displayNameMode, compositor) {
    const outputKeys = Object.keys(configEntry.outputs || {});
    if (outputKeys.length === 0)
        return false;
    const isReal = k => profileOutputIsReal(k, outputs, displayNameMode, compositor);
    const hasEnabledReal = outputKeys.some(k => !configEntry.outputs[k].disabled && isReal(k));
    if (hasEnabledReal)
        return false;
    const firstReal = outputKeys.find(isReal);
    if (!firstReal)
        return false;
    delete configEntry.outputs[firstReal].disabled;
    return true;
}

function outputFingerprint(outputs) {
    return JSON.stringify(outputs.map(o => ({
                name: o.name,
                id: o.id,
                enabled: o.enabled,
                x: o.x,
                y: o.y,
                scale: o.scale,
                transform: o.transform,
                mode: o.currentMode ? [o.currentMode.width, o.currentMode.height, o.currentMode.refresh] : null,
                adaptiveSync: o.adaptiveSync
            })).sort((a, b) => a.name.localeCompare(b.name)));
}

function outputHeads(outputs) {
    return outputs.map(o => ({
                name: o.name,
                enabled: o.enabled,
                modeId: o.currentMode?.id,
                position: {
                    x: o.x,
                    y: o.y
                },
                scale: o.scale,
                transform: o.transform,
                adaptiveSync: o.adaptiveSync
            }));
}

function outputHeadsMatch(candidate, actual, original) {
    if (candidate.length !== actual.length || original.length !== actual.length || original.some(o => !actual.some(a => a.id === o.id && a.name === o.name)))
        return false;
    return candidate.every(h => {
        const output = actual.find(o => o.name === h.name);
        if (!output || output.enabled !== h.enabled)
            return false;
        if (!h.enabled)
            return true;
        const mode = h.customMode || original.find(o => o.name === h.name)?.modes?.find(m => m.id === h.modeId);
        return output.x === h.position.x && output.y === h.position.y && Math.abs(output.scale - h.scale) < 0.0001 && output.transform === h.transform && (h.adaptiveSync === undefined || output.adaptiveSync === h.adaptiveSync) && !!mode && output.currentMode?.width === mode.width && output.currentMode?.height === mode.height && output.currentMode?.refresh === mode.refresh;
    });
}

function configEntryMatchesLiveLayout(configEntry, outputs, displayNameMode, compositor) {
    const cfgOutputs = configEntry.outputs || {};
    for (const outputId in cfgOutputs) {
        const cfg = cfgOutputs[outputId];
        const live = liveOutputForKey(outputId, outputs, displayNameMode, compositor);
        if (!live)
            return false;
        if ((cfg.disabled ?? false) !== !(live.enabled ?? true))
            return false;
        if (cfg.disabled)
            continue;
        const mode = (live.modes && live.current_mode >= 0) ? live.modes[live.current_mode] : null;
        const modeStr = mode ? mode.width + "x" + mode.height + "@" + (mode.refresh_rate / 1000).toFixed(3) : null;
        if (cfg.mode && modeStr !== cfg.mode)
            return false;
        if ((cfg.position?.x ?? 0) !== (live.logical?.x ?? 0) || (cfg.position?.y ?? 0) !== (live.logical?.y ?? 0))
            return false;
        if (Math.abs((cfg.scale ?? 1.0) - (live.logical?.scale ?? 1.0)) > WLR_SCALE_STEP)
            return false;
        if ((cfg.transform ?? "Normal") !== (live.logical?.transform ?? "Normal"))
            return false;
    }
    return true;
}

function currentOutputSet(outputs, displayNameMode, compositor) {
    const connected = [];
    for (const name in outputs)
        connected.push(profileIdentifier(outputs[name], name, displayNameMode, compositor));
    return connected.sort();
}

function liveIdentifiers(outputs, displayNameMode, compositor) {
    const identifiers = {};
    for (const name in outputs) {
        const o = outputs[name];
        identifiers[name] = true;
        if (!o?.make || !o?.model)
            continue;
        identifiers[(o.make + " " + o.model + " " + (o.serial || "Unknown")).trim()] = true;
        identifiers[(o.make + " " + o.model).trim()] = true;
        switch (compositor) {
        case "hyprland":
            identifiers[hyprlandIdentifier(o, name, displayNameMode).trim()] = true;
            break;
        }
    }
    return identifiers;
}

function filterDisconnectedOnly(parsedOutputs, outputs, displayNameMode, compositor) {
    const result = {};
    const live = liveIdentifiers(outputs, displayNameMode, compositor);
    for (const savedName in parsedOutputs) {
        if (!live[savedName.trim()])
            result[savedName] = parsedOutputs[savedName];
    }
    return result;
}

function physicalSize(output) {
    if (!output)
        return {
            "w": 1920,
            "h": 1080
        };

    let w = 1920, h = 1080;
    if (output.modes && output.current_mode !== undefined) {
        const mode = output.modes[output.current_mode];
        if (mode) {
            w = mode.width || 1920;
            h = mode.height || 1080;
        }
    } else if (output.logical) {
        const scale = output.logical.scale || 1.0;
        w = Math.round((output.logical.width || 1920) * scale);
        h = Math.round((output.logical.height || 1080) * scale);
    }

    if (output.logical && isRotated(output.logical.transform))
        return {
            "w": h,
            "h": w
        };
    return {
        "w": w,
        "h": h
    };
}

function roundLogical(value, compositor) {
    switch (compositor) {
    case "niri":
        // niri rounds the placed output, smithay's Space ceils mapped ones, only ceil never overlaps in either order (#3875)
        return Math.ceil(value);
    default:
        return Math.round(value);
    }
}

function logicalSize(output, compositor) {
    if (!output)
        return {
            "w": 1920,
            "h": 1080
        };
    const phys = physicalSize(output);
    const scale = output.logical?.scale || 1.0;
    return {
        "w": roundLogical(phys.w / scale, compositor),
        "h": roundLogical(phys.h / scale, compositor)
    };
}

function defaultBounds() {
    return {
        "minX": 0,
        "minY": 0,
        "maxX": 1920,
        "maxY": 1080,
        "width": 1920,
        "height": 1080
    };
}

function outputBounds(allOutputs, compositor) {
    if (!allOutputs || Object.keys(allOutputs).length === 0)
        return defaultBounds();

    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const name in allOutputs) {
        const output = allOutputs[name];
        if (!output.logical)
            continue;
        const size = logicalSize(output, compositor);
        minX = Math.min(minX, output.logical.x);
        minY = Math.min(minY, output.logical.y);
        maxX = Math.max(maxX, output.logical.x + size.w);
        maxY = Math.max(maxY, output.logical.y + size.h);
    }

    if (minX === Infinity)
        return defaultBounds();
    return {
        "minX": minX,
        "minY": minY,
        "maxX": maxX,
        "maxY": maxY,
        "width": maxX - minX,
        "height": maxY - minY
    };
}

function neighborNames(layout, testName) {
    return Object.keys(layout.outputs).filter(name => name !== testName && !layout.disabled[name] && layout.outputs[name].logical);
}

function checkOverlap(layout, testName, testX, testY, testW, testH) {
    for (const name of neighborNames(layout, testName)) {
        const output = layout.outputs[name];
        const x = output.logical.x;
        const y = output.logical.y;
        const size = logicalSize(output, layout.compositor);
        if (!(testX + testW <= x || testX >= x + size.w || testY + testH <= y || testY >= y + size.h))
            return true;
    }
    return false;
}

function axisSnaps(edge, extent, pos, testExtent) {
    const far = edge + extent;
    const testFar = pos + testExtent;
    return [
        {
            "val": far,
            "dist": Math.abs(pos - far)
        },
        {
            "val": edge - testExtent,
            "dist": Math.abs(testFar - edge)
        },
        {
            "val": edge,
            "dist": Math.abs(pos - edge)
        },
        {
            "val": far - testExtent,
            "dist": Math.abs(testFar - far)
        }
    ];
}

function nearestSnap(snaps, value, dist) {
    for (const snap of snaps) {
        if (snap.dist < dist) {
            dist = snap.dist;
            value = snap.val;
        }
    }
    return {
        "value": value,
        "dist": dist
    };
}

function snapToEdges(layout, testName, posX, posY, testW, testH) {
    const snapThreshold = 200;
    let snappedX = posX;
    let snappedY = posY;
    let bestXDist = snapThreshold;
    let bestYDist = snapThreshold;

    for (const name of neighborNames(layout, testName)) {
        const output = layout.outputs[name];
        const size = logicalSize(output, layout.compositor);
        const x = nearestSnap(axisSnaps(output.logical.x, size.w, posX, testW), snappedX, bestXDist);
        snappedX = x.value;
        bestXDist = x.dist;
        const y = nearestSnap(axisSnaps(output.logical.y, size.h, posY, testH), snappedY, bestYDist);
        snappedY = y.value;
        bestYDist = y.dist;
    }

    if (!checkOverlap(layout, testName, snappedX, snappedY, testW, testH))
        return {
            "x": snappedX,
            "y": snappedY
        };
    if (!checkOverlap(layout, testName, snappedX, posY, testW, testH))
        return {
            "x": snappedX,
            "y": posY
        };
    if (!checkOverlap(layout, testName, posX, snappedY, testW, testH))
        return {
            "x": posX,
            "y": snappedY
        };
    return {
        "x": posX,
        "y": posY
    };
}

function recalculateAdjacentPositions(outputs, pendingChanges, changedOutput, newScale, compositor) {
    const output = outputs[changedOutput];
    if (!output?.logical)
        return [];
    const oldPhys = physicalSize(output);
    const oldLogicalW = roundLogical(oldPhys.w / (output.logical.scale || 1.0), compositor);
    const newLogicalW = roundLogical(oldPhys.w / newScale, compositor);
    const changedX = pendingChanges[changedOutput]?.position?.x ?? output.logical.x;
    const changedY = pendingChanges[changedOutput]?.position?.y ?? output.logical.y;
    const moves = [];

    for (const name in outputs) {
        if (name === changedOutput)
            continue;
        const other = outputs[name];
        if (!other?.logical)
            continue;
        const otherX = pendingChanges[name]?.position?.x ?? other.logical.x;
        const otherY = pendingChanges[name]?.position?.y ?? other.logical.y;
        const otherRight = otherX + logicalSize(other, compositor).w;

        if (Math.abs(changedX - otherRight) < 5) {
            moves.push({
                "name": changedOutput,
                "x": otherRight,
                "y": changedY
            });
            return moves;
        }

        if (Math.abs(otherX - (changedX + oldLogicalW)) < 5)
            moves.push({
                "name": name,
                "x": changedX + newLogicalW,
                "y": otherY
            });
    }
    return moves;
}

function normalizeOutputPositions(outputsData) {
    const names = Object.keys(outputsData);
    if (names.length === 0)
        return outputsData;

    let minX = Infinity;
    let minY = Infinity;

    for (const name of names) {
        const output = outputsData[name];
        if (!output.logical)
            continue;
        minX = Math.min(minX, output.logical.x);
        minY = Math.min(minY, output.logical.y);
    }

    if (minX === Infinity || (minX === 0 && minY === 0))
        return outputsData;

    const normalized = JSON.parse(JSON.stringify(outputsData));
    for (const name of names) {
        if (!normalized[name].logical)
            continue;
        normalized[name].logical.x -= minX;
        normalized[name].logical.y -= minY;
    }

    return normalized;
}

function formatMode(mode) {
    if (!mode)
        return "";
    return mode.width + "x" + mode.height + "@" + (mode.refresh_rate / 1000).toFixed(3);
}

function formatScaleLabel(scale) {
    const value = Number(scale);
    if (!isFinite(value))
        return "1";
    return parseFloat(value.toFixed(2)).toString();
}

function scaleFromNumerator(numerator) {
    return parseFloat((numerator / SCALE_DENOMINATOR).toFixed(6));
}

function scaleNumeratorStep(compositor) {
    switch (compositor) {
    case "niri":
    case "hyprland":
        return 1;
    default:
        return SCALE_DENOMINATOR / 8;
    }
}

function cleanScaleNumerators(mode, compositor, minScale, maxScale) {
    const width = Number(mode?.width || 0) * SCALE_DENOMINATOR;
    const height = Number(mode?.height || 0) * SCALE_DENOMINATOR;
    if (width <= 0 || height <= 0)
        return [];
    const step = scaleNumeratorStep(compositor);
    const first = Math.ceil(minScale * SCALE_DENOMINATOR / step) * step;
    const last = Math.floor(maxScale * SCALE_DENOMINATOR / step) * step;
    const numerators = [];
    for (let n = first; n <= last; n += step) {
        if (width % n === 0 && height % n === 0)
            numerators.push(n);
    }
    return numerators;
}

function allowsInexactScale(compositor) {
    return compositor !== "hyprland";
}

function nearestNumerator(numerators, target) {
    let best = numerators[0];
    for (const n of numerators) {
        if (Math.abs(n - target) < Math.abs(best - target))
            best = n;
    }
    return best;
}

function gapFillNumerators(clean, compositor) {
    if (!allowsInexactScale(compositor))
        return [];
    const step = Math.max(GAP_FILL_STEP, scaleNumeratorStep(compositor));
    const fills = [];
    for (let n = GAP_FILL_MIN * SCALE_DENOMINATOR; n <= GAP_FILL_MAX * SCALE_DENOMINATOR; n += step) {
        if (clean.length === 0 || Math.abs(nearestNumerator(clean, n) - n) >= GAP_FILL_CLEARANCE)
            fills.push(n);
    }
    return fills;
}

function scalePresetValues(outputData, pendingMode, compositor) {
    const mode = modeForScalePresets(outputData, pendingMode);
    if (!mode)
        return FALLBACK_SCALE_PRESETS.slice();
    const clean = cleanScaleNumerators(mode, compositor, MIN_PRESET_SCALE, MAX_SCALE);
    return clean.concat(gapFillNumerators(clean, compositor)).sort((a, b) => a - b).map(scaleFromNumerator);
}

function snapScaleToMode(outputData, pendingMode, compositor, scale) {
    const value = Number(scale);
    if (!isFinite(value) || value < MIN_SCALE || value > MAX_SCALE)
        return NaN;
    const mode = modeForScalePresets(outputData, pendingMode);
    const clean = mode ? cleanScaleNumerators(mode, compositor, MIN_SCALE, MAX_SCALE) : [];
    if (clean.length === 0)
        return parseFloat(value.toFixed(6));
    const target = value * SCALE_DENOMINATOR;
    const nearestClean = nearestNumerator(clean, target);
    if (!allowsInexactScale(compositor) || Math.abs(nearestClean - target) < GAP_FILL_CLEARANCE)
        return scaleFromNumerator(nearestClean);
    const step = scaleNumeratorStep(compositor);
    return scaleFromNumerator(Math.round(target / step) * step);
}

function logicalSizeForScale(outputData, pendingMode, scale) {
    const mode = modeForScalePresets(outputData, pendingMode);
    if (!mode || !(scale > 0))
        return null;
    const w = mode.width / scale;
    const h = mode.height / scale;
    return {
        "w": Math.round(w),
        "h": Math.round(h),
        "exact": Math.abs(w - Math.round(w)) < LOGICAL_PIXEL_TOLERANCE && Math.abs(h - Math.round(h)) < LOGICAL_PIXEL_TOLERANCE
    };
}

function formatScaleOption(outputData, pendingMode, scale) {
    const label = parseFloat(Number(scale).toFixed(3)) + "x";
    const size = logicalSizeForScale(outputData, pendingMode, scale);
    if (!size)
        return label;
    return label + " · " + (size.exact ? "" : "~") + size.w + "x" + size.h;
}

function modeForScalePresets(outputData, pendingMode) {
    const modes = outputData?.modes || [];
    if (pendingMode) {
        for (const mode of modes) {
            if (formatMode(mode) === pendingMode)
                return mode;
        }
    }
    const currentMode = outputData?.current_mode;
    if (currentMode !== undefined && modes[currentMode])
        return modes[currentMode];
    return null;
}

function modeWidth(mode) {
    return mode?.width ?? 0;
}

function modeHeight(mode) {
    return mode?.height ?? 0;
}

function modeRefresh(mode) {
    return mode?.refresh_rate ?? mode?.refresh ?? 0;
}

function formatModeString(mode) {
    if (!mode)
        return "";
    return modeWidth(mode) + "x" + modeHeight(mode) + "@" + (modeRefresh(mode) / 1000).toFixed(3);
}

function formatNiriMode(mode) {
    return mode.width + "x" + mode.height + "@" + (modeRefresh(mode) / 1000).toFixed(3);
}

function parseModeString(modeString) {
    const match = (modeString || "").match(/^(\d+)x(\d+)@([\d.]+)$/);
    if (!match)
        return null;
    return {
        "width": parseInt(match[1]),
        "height": parseInt(match[2]),
        "refresh": Math.round(parseFloat(match[3]) * 1000)
    };
}

function findModeByString(modes, modeString, tolerance) {
    for (const mode of modes) {
        if (formatModeString(mode) === modeString)
            return mode;
    }

    const parsed = parseModeString(modeString);
    if (!parsed)
        return null;

    for (const mode of modes) {
        if (modeWidth(mode) === parsed.width && modeHeight(mode) === parsed.height && Math.abs(modeRefresh(mode) - parsed.refresh) <= tolerance)
            return mode;
    }

    return null;
}

function modeAlreadyCurrent(currentMode, targetMode, tolerance) {
    if (!currentMode || !targetMode)
        return true;
    return modeWidth(currentMode) === modeWidth(targetMode) && modeHeight(currentMode) === modeHeight(targetMode) && Math.abs(modeRefresh(currentMode) - modeRefresh(targetMode)) <= tolerance;
}

function restoreModeValue(mode, backend) {
    if (!mode)
        return null;
    if (backend === "wlr")
        return mode.id ?? null;
    return formatNiriMode(mode);
}

function outputVrrEnabled(output) {
    return output.vrr_enabled === true || output.adaptiveSync === 1;
}

function niriCurrentMode(output) {
    if (!output || !output.modes || output.current_mode === undefined)
        return null;
    return output.modes[output.current_mode] || null;
}

function batteryRefreshMode(output, currentMode, backend, target, tolerance) {
    if (!output || !currentMode || (backend === "wlr" && !output.enabled))
        return null;

    if (outputVrrEnabled(output))
        return null;

    const modes = output.modes || [];
    const sameResolutionModes = modes.filter(m => modeWidth(m) === modeWidth(currentMode) && modeHeight(m) === modeHeight(currentMode));
    const uniqueRefreshRates = [];
    for (const mode of sameResolutionModes) {
        const refresh = modeRefresh(mode);
        if (!uniqueRefreshRates.some(r => Math.abs(r - refresh) <= tolerance))
            uniqueRefreshRates.push(refresh);
    }

    if (uniqueRefreshRates.length <= 1)
        return null;

    let bestMode = null;
    let bestDiff = Infinity;
    for (const mode of sameResolutionModes) {
        const diff = Math.abs(modeRefresh(mode) - target);
        if (diff < bestDiff) {
            bestMode = mode;
            bestDiff = diff;
        }
    }

    if (!bestMode || bestDiff > tolerance)
        return null;

    return bestMode;
}
