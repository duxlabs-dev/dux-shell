pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root

    property var previews: CacheData.matugenPreviews.previews ?? ({})
    property string requestKey: ""
    property string loadedKey: CacheData.matugenPreviews.key ?? ""
    property bool failed: false
    property var seedPreviews: CacheData.matugenSeedPreviews
    property var seedQueue: []
    property string seedRequestKey: ""
    property var seedFailed: ({})
    property bool seedDirty: false
    readonly property int seedCacheLimit: 32

    readonly property string source: SettingsData.matugenSeedColor || (!Theme.rawWallpaperPath ? Theme.materialWallpaperSeed : Theme.getMatugenColor("source_color", Theme.primary).toString())
    readonly property string image: (!SettingsData.matugenSeedColor && Theme.wallpaperImagePath && !Theme.wallpaperImagePath.startsWith("#")) ? Theme.wallpaperImagePath : ""
    readonly property string keySuffix: "|" + (SettingsData.matugenContrast ?? 0) + "|" + SettingsData.matugenSpec
    readonly property string key: source + "|" + (SettingsData.matugenContrast ?? 0) + "|" + image + "|" + SettingsData.matugenSpec
    readonly property bool ready: loadedKey === key || failed || !Theme.matugenAvailable
    readonly property bool seedBusy: seedRequestKey !== "" || seedQueue.length > 0
    readonly property bool seedPreviewFailed: Object.keys(seedFailed).length > 0
    readonly property var schemeOptions: {
        const mode = SessionData.isLightMode ? "light" : "dark";
        const options = [];
        for (const option of Theme.availableMatugenSchemes) {
            if (option.value === "scheme-smart" && !DMSService.matugenSmartSupported)
                continue;
            if (SettingsData.matugenSpec !== "2021" && !option.spec2025)
                continue;
            const colors = (previews[option.value] ?? previews["scheme-tonal-spot"])?.[mode];
            // a dms binary older than the tri-color preview returns the primary hex as a plain string
            const primary = typeof colors === "string" ? colors : (colors?.primary ?? Theme.primary.toString());
            options.push({
                "value": option.value,
                "label": option.label,
                "primary": primary,
                "secondary": colors?.secondary ?? primary,
                "tertiary": colors?.tertiary ?? primary
            });
        }
        return options;
    }

    function seedKey(seed) {
        return seed.toLowerCase() + keySuffix;
    }

    function seedPalette(seed, light = SessionData.isLightMode) {
        const entry = seedPreviews[seedKey(seed)];
        if (!entry)
            return null;
        const colors = (entry[SettingsData.matugenScheme] ?? entry["scheme-tonal-spot"])?.[light ? "light" : "dark"];
        if (!colors)
            return null;
        if (typeof colors === "string")
            return {
                primary: colors,
                secondary: colors,
                tertiary: colors
            };
        return colors;
    }

    function requestSeeds(seeds) {
        if (!Theme.matugenAvailable)
            return;
        const wanted = [];
        for (const seed of seeds) {
            const key = seedKey(seed);
            if (seedPreviews[key] || seedFailed[key] || seedQueue.includes(key) || key === seedRequestKey || wanted.includes(key))
                continue;
            wanted.push(key);
        }
        if (!wanted.length)
            return;
        seedQueue = seedQueue.concat(wanted);
        pumpSeeds();
    }

    function retrySeeds(seeds) {
        seedFailed = {};
        requestSeeds(seeds);
    }

    function pumpSeeds() {
        if (seedRequestKey || !seedQueue.length)
            return;
        const key = seedQueue[0];
        seedQueue = seedQueue.slice(1);
        seedRequestKey = key;
        const [source, contrast, spec] = key.split("|");
        const args = [Proc.dmsBin, "matugen", "preview", "--source-color", source, "--contrast", contrast];
        if (spec !== "2021")
            args.push("--spec", spec);
        Proc.runCommand("", args, (output, exitCode) => {
            if (root.seedRequestKey !== key)
                return;
            root.seedRequestKey = "";
            let parsed = null;
            try {
                parsed = exitCode === 0 ? JSON.parse(output.trim()) : null;
            } catch (e) {
                parsed = null;
            }
            if (!parsed || typeof parsed !== "object") {
                root.seedFailed = Object.assign({}, root.seedFailed, {
                    [key]: true
                });
            } else {
                const next = Object.assign({}, root.seedPreviews, {
                    [key]: parsed
                });
                const keys = Object.keys(next);
                for (const stale of keys.slice(0, Math.max(0, keys.length - root.seedCacheLimit)))
                    delete next[stale];
                root.seedPreviews = next;
                CacheData.matugenSeedPreviews = next;
                root.seedDirty = true;
            }
            if (!root.seedQueue.length && root.seedDirty) {
                root.seedDirty = false;
                CacheData.saveCache();
            }
            root.pumpSeeds();
        });
    }

    function refresh() {
        if (!Theme.matugenAvailable)
            return;
        const wanted = key;
        if (wanted === loadedKey) {
            requestKey = "";
            return;
        }
        if (wanted === requestKey)
            return;
        requestKey = wanted;
        failed = false;

        const args = [Proc.dmsBin, "matugen", "preview", "--source-color", source, "--contrast", String(SettingsData.matugenContrast ?? 0)];
        if (image)
            args.push("--image", image);
        if (SettingsData.matugenSpec !== "2021")
            args.push("--spec", SettingsData.matugenSpec);
        Proc.runCommand("", args, (output, exitCode) => {
            if (wanted !== root.requestKey)
                return;
            root.requestKey = "";
            if (exitCode !== 0) {
                root.failed = true;
                return;
            }
            try {
                root.previews = JSON.parse(output.trim());
                root.loadedKey = wanted;
                CacheData.matugenPreviews = {
                    "key": wanted,
                    "previews": root.previews
                };
                CacheData.saveCache();
            } catch (e) {
                root.failed = true;
            }
        });
    }
}
