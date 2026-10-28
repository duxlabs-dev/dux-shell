pragma Singleton

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root

    readonly property int sampleSize: 128
    property var decodedSamples: ({})
    property var layouts: ({})
    property var scrollSamplers: ({})

    function setScrollSampler(screenName, present) {
        const next = Object.assign({}, scrollSamplers);
        if (present)
            next[screenName] = true;
        else
            delete next[screenName];
        scrollSamplers = next;
    }

    function usesScrollAtlas(screenName) {
        if (!scrollSamplers[screenName] || SettingsData.lockScreenWallpaperPath !== "")
            return false;
        const source = SessionData.getMonitorWallpaper(screenName);
        return !!source && !source.startsWith("#") && (SettingsData.lockScreenWallpaperFillMode || SessionData.getMonitorWallpaperFillMode(screenName)) === "Scrolling";
    }

    function neededFor(screen) {
        return SettingsData.lockScreenWidgetInstances.some(instance => {
            if (instance.widgetType !== "desktopClock" || instance.enabled === false || instance.config?.autoPosition === false || !DesktopWidgetRegistry.showsOnScreen(instance.config?.displayPreferences, screen))
                return false;
            const positionKey = instance.config?.syncPositionAcrossScreens ? "_synced" : SettingsData.getScreenDisplayName(screen);
            return SessionData.desktopWidgetInstancePositions[instance.id]?.[positionKey]?.x === undefined;
        });
    }

    function backgroundKey(screenName, width, height) {
        const custom = SettingsData.lockScreenWallpaperPath !== "";
        const source = custom ? SettingsData.lockScreenWallpaperPath : SessionData.getMonitorWallpaper(screenName);
        const backdrop = !source || source.startsWith("#");
        const fill = SettingsData.lockScreenWallpaperFillMode || (custom ? "Fill" : SessionData.getMonitorWallpaperFillMode(screenName));
        return JSON.stringify([1, source, width, height, fill, fill === "Scrolling" ? SessionData.getMonitorScrollPosition(screenName) : null, backdrop ? SessionData.getMonitorMaterialWallpaper(screenName) : null, backdrop ? Theme.wallpaperPalette() : null, Theme.lockScreenBlur, Theme.lockScreenBlurMax, Theme.lockScreenScrimAlpha, Theme.screenOffColor.toString(), SettingsData.effectiveWallpaperBackgroundColor.toString()]);
    }

    function sampleFor(screenName, key) {
        const sample = CacheData.lockScreenPlacementSamples[screenName];
        if (!sample || sample.key !== key || typeof sample.key !== "string" || !Number.isInteger(sample.width) || !Number.isInteger(sample.height) || sample.width < 1 || sample.height < 1 || sample.width > 128 || sample.height > 128 || typeof sample.pixels !== "string" || sample.pixels.length !== sample.width * sample.height * 2)
            return null;
        return sample;
    }

    function hasSample(screenName, key) {
        return sampleFor(screenName, key) !== null;
    }

    function storeSample(screenName, key, luminances, width, height) {
        const pixels = luminances.map(value => Math.round(Math.max(0, Math.min(1, value)) * 255).toString(16).padStart(2, "0")).join("");
        delete decodedSamples[screenName];
        delete layouts[screenName];
        CacheData.set("lockScreenPlacementSamples", Object.assign({}, CacheData.lockScreenPlacementSamples, {
            [screenName]: {
                key,
                pixels,
                width,
                height
            }
        }));
    }

    function layoutFor(screenName, sample, key, calculate) {
        if (!sample)
            return {};
        const cached = layouts[screenName];
        if (cached?.sampleKey === sample.key && cached.key === key)
            return cached.positions;
        let decoded = decodedSamples[screenName];
        if (decoded?.key !== sample.key) {
            const luminances = [];
            for (let i = 0; i < sample.pixels.length; i += 2) {
                const value = parseInt(sample.pixels.slice(i, i + 2), 16);
                if (!Number.isFinite(value))
                    return {};
                luminances.push(value / 255);
            }
            decoded = {
                key: sample.key,
                luminances
            };
            decodedSamples[screenName] = decoded;
        }
        const positions = calculate(decoded.luminances, sample.width, sample.height);
        layouts[screenName] = {
            sampleKey: sample.key,
            key,
            positions
        };
        return positions;
    }
}
