pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.DDash.Overview
import "utils/options.js" as Options

Singleton {
    id: root

    readonly property string pluginPrefix: "plugin_"
    readonly property string overviewId: "overview"
    readonly property string defaultTabId: visibleTabIds[0] ?? ""
    readonly property string widgetsKey: "widgets"

    readonly property var toneChoices: [
        {
            "value": "",
            "text": I18n.tr("Surface")
        },
        {
            "value": "primary",
            "text": I18n.tr("Primary")
        },
        {
            "value": "secondary",
            "text": I18n.tr("Secondary")
        },
        {
            "value": "tertiary",
            "text": I18n.tr("Tertiary")
        }
    ]

    function toggle(key, text, def, description) {
        return {
            "key": key,
            "text": text,
            "type": "toggle",
            "def": def,
            "description": description ?? ""
        };
    }

    function choice(key, text, def, choices) {
        return {
            "key": key,
            "text": text,
            "type": "choice",
            "def": def,
            "choices": choices
        };
    }

    function number(key, text, def, min, max, step, unit) {
        return {
            "key": key,
            "text": text,
            "type": "number",
            "def": def,
            "min": min,
            "max": max,
            "step": step ?? 1,
            "unit": unit ?? ""
        };
    }

    function slider(key, text, def, min, max, step, minimumLabel) {
        return Object.assign(number(key, text, def, min, max, step), {
            "type": "slider",
            "minimumLabel": minimumLabel ?? ""
        });
    }

    function toneOption(def = "") {
        return choice("tone", I18n.tr("Tone", "noun, dashboard widget color tone option label"), def, toneChoices);
    }

    function cardOnly(spec) {
        return Object.assign(spec, {
            "cardOnly": true
        });
    }

    function panelOptions(tab) {
        return [Object.assign(number("panelColumns", I18n.tr("Panel width (columns)"), DashMetrics.defaultGridColumns, DashMetrics.minimumGridColumns, DashMetrics.maximumGridColumns), {
                "settingsOnly": true
            }), Object.assign(number("panelRows", I18n.tr("Panel height (rows)"), DashMetrics.defaultRowsForTab(tab), DashMetrics.minimumTabRows, DashMetrics.maximumGridRows), {
                "settingsOnly": true
            })];
    }

    readonly property var builtins: [
        {
            "id": "overview",
            "text": I18n.tr("Overview", "dashboard tab name"),
            "icon": "dashboard",
            "description": I18n.tr("Clock, calendar, system info and profile"),
            "tab": {
                "component": overviewTab
            }
        },
        {
            "id": "media",
            "text": I18n.tr("Media", "dashboard media player tab name"),
            "icon": "music_note",
            "description": I18n.tr("Now playing and media controls"),
            "tab": {
                "component": mediaTab,
                "async": true,
                "sizeToContent": true
            },
            "card": {
                "component": mediaCard,
                "w": 2,
                "h": 1,
                "minW": 1,
                "minH": 1
            },
            "options": [choice("playerStyle", I18n.tr("Player style"), MediaOptions.defaultPlayerStyle, MediaOptions.playerStyles), choice("artStyle", I18n.tr("Artwork"), "rounded", [
                    {
                        "value": "rounded",
                        "text": I18n.tr("Rounded")
                    },
                    {
                        "value": "circle",
                        "text": I18n.tr("Circle")
                    },
                    {
                        "value": "square",
                        "text": I18n.tr("Soft square", "Album artwork shape")
                    },
                    {
                        "value": "slanted",
                        "text": I18n.tr("Slanted", "Album artwork shape")
                    },
                    {
                        "value": "cookie",
                        "text": I18n.tr("Rotating Cookie", "Album artwork shape")
                    }
                ]), choice("titleFont", I18n.tr("Title font"), MediaOptions.defaultTitleFont, Theme.fontChoices), toggle("deviceName", I18n.tr("Show device name", "Media player option that puts the audio output device name on its button"), MediaOptions.defaults.deviceName), toggle("seekbar", I18n.tr("Show seekbar"), MediaOptions.defaults.seekbar), toggle("waveProgress", I18n.tr("Wave progress bars"), MediaOptions.defaults.waveProgress), toggle("albumArtBackdrop", I18n.tr("Album art backdrop"), MediaOptions.defaults.albumArtBackdrop), toggle("albumArtAccent", I18n.tr("Use album art accent"), MediaOptions.defaults.albumArtAccent), toggle("animatedArt", I18n.tr("Apple Music animated covers"), MediaOptions.defaults.animatedArt, I18n.tr("Sends the playing artist and album name to Apple")), toggle("lyrics", I18n.tr("Lyrics", "Media player lyrics button"), MediaOptions.defaults.lyrics, I18n.tr("Sends the playing track, artist and album name to enabled lyrics providers")), toggle("smoothLyrics", I18n.tr("Smooth lyrics highlight", "Media player option that fills each sung word gradually instead of highlighting it at once"), MediaOptions.defaults.smoothLyrics)]
        },
        {
            "id": "wallpaper",
            "text": I18n.tr("Wallpapers", "dashboard tab name"),
            "icon": "wallpaper",
            "description": I18n.tr("Browse and set wallpapers"),
            "tab": {
                "component": wallpaperTab,
                "async": true,
                "sizeToContent": true
            },
            "options": [choice("layout", I18n.tr("Layout"), "grid", [
                    {
                        "value": "grid",
                        "text": I18n.tr("Grid")
                    },
                    {
                        "value": "carousel",
                        "text": I18n.tr("Carousel", "wallpaper tab layout option")
                    }
                ]), number("columns", I18n.tr("Columns", "number of columns in the wallpaper grid option"), 4, DashMetrics.wallpaperColumnsMin, DashMetrics.wallpaperColumnsMax), number("rows", I18n.tr("Rows", "number of rows in the wallpaper grid option"), 4, DashMetrics.wallpaperRowsMin, DashMetrics.wallpaperRowsMax), toggle("filename", I18n.tr("Show filename"), true)]
        },
        {
            "id": "weather",
            "text": I18n.tr("Weather"),
            "icon": "wb_sunny",
            "description": SettingsData.weatherEnabled ? I18n.tr("Forecast and conditions") : I18n.tr("Hidden until weather is enabled"),
            "available": SettingsData.weatherEnabled,
            "tab": {
                "component": weatherTab,
                "async": true,
                "sizeToContent": true
            },
            "card": {
                "component": weatherCard,
                "w": 1,
                "h": 2,
                "minW": 1,
                "minH": 1
            },
            "options": [cardOnly(toggle("city", I18n.tr("Show city"), false)), cardOnly(toggle("readings", I18n.tr("Show readings"), true)), cardOnly(toneOption())]
        },
        {
            "id": "wellbeing",
            "text": I18n.tr("Digital wellbeing", "settings page and dashboard tab title, screen time tracking"),
            "icon": "digital_wellbeing",
            "description": SettingsData.wellbeingEnabled ? I18n.tr("Screen time and app limits", "settings sidebar hint and dashboard tab description for digital wellbeing") : I18n.tr("Hidden until screen time tracking is enabled", "dashboard tab description while digital wellbeing is off"),
            "available": SettingsData.wellbeingEnabled,
            "tab": {
                "component": wellbeingTab,
                "async": true,
                "sizeToContent": true
            },
            "card": {
                "component": wellbeingCard,
                "w": 2,
                "h": 1,
                "minW": 1,
                "minH": 1,
                "maxH": 3
            }
        },
        {
            "id": "notifications",
            "text": I18n.tr("Notifications"),
            "icon": "notifications",
            "tab": {
                "component": notificationsTab
            },
            "card": {
                "component": notificationsCard,
                "w": 3,
                "h": 5,
                "minW": 3,
                "minH": 2
            }
        },
        {
            "id": "clock",
            "text": I18n.tr("Clock"),
            "icon": "schedule",
            "card": {
                "component": clockCard,
                "w": 2,
                "h": 2,
                "minW": 1,
                "minH": 1
            },
            "options": [choice("style", I18n.tr("Style", "noun, visual style option label for a widget or the dock"), "digital", [
                    {
                        "value": "digital",
                        "text": I18n.tr("Digital", "clock style option")
                    },
                    {
                        "value": "analog",
                        "text": I18n.tr("Analog", "clock style option")
                    }
                ]), slider("weight", I18n.tr("Weight"), 0, 0, Font.Black, 100, I18n.tr("Default")), toggle("seconds", I18n.tr("Show seconds"), false), toggle("date", I18n.tr("Show date"), false), toggle("numbers", I18n.tr("Show hour numbers"), false), choice("tone", I18n.tr("Tone"), "primary", toneChoices)]
        },
        {
            "id": "calendar",
            "text": I18n.tr("Calendar"),
            "icon": "calendar_month",
            "card": {
                "component": calendarCard,
                "w": 3,
                "h": 3,
                "minW": 3,
                "minH": 3,
                "async": true
            },
            "options": [toggle("weekends", I18n.tr("Highlight weekends"), false)]
        },
        {
            "id": "user",
            "text": I18n.tr("User"),
            "icon": "person",
            "card": {
                "component": userCard,
                "w": 3,
                "h": 1,
                "minW": 1,
                "minH": 1,
                "maxH": 3
            },
            "options": [toggle("hostname", I18n.tr("Show hostname"), true), toggle("compositor", I18n.tr("Show compositor"), true), toggle("uptime", I18n.tr("Show uptime"), true), toggle("badge", I18n.tr("Distro badge"), true)]
        },
        {
            "id": "sysmon",
            "text": I18n.tr("System Monitor"),
            "icon": "monitoring",
            "card": {
                "component": sysmonCard,
                "w": 2,
                "h": 1,
                "minW": 1,
                "minH": 1
            },
            "options": [toggle("temperature", I18n.tr("Show temperature"), true), toneOption()]
        },
        {
            "id": "cpu",
            "text": I18n.tr("CPU"),
            "icon": "memory",
            "card": {
                "component": cpuCard,
                "w": 1,
                "h": 1,
                "minW": 1,
                "minH": 1,
                "maxH": 3
            },
            "options": [toggle("trend", I18n.tr("Show trend"), true), toggle("temperature", I18n.tr("Show temperature"), true), toneOption()]
        },
        {
            "id": "memory",
            "text": I18n.tr("Memory"),
            "icon": "developer_board",
            "card": {
                "component": memoryCard,
                "w": 1,
                "h": 1,
                "minW": 1,
                "minH": 1,
                "maxH": 3
            },
            "options": [toggle("trend", I18n.tr("Show trend"), true), toggle("swap", I18n.tr("Show swap"), false), toneOption()]
        },
        {
            "id": "network",
            "text": I18n.tr("Network"),
            "icon": "swap_vert",
            "card": {
                "component": networkCard,
                "w": 2,
                "h": 1,
                "minW": 1,
                "minH": 1,
                "maxH": 3
            },
            "options": [toggle("trend", I18n.tr("Show trend"), true), toneOption()]
        },
        {
            "id": "disk",
            "text": I18n.tr("Disk"),
            "icon": "hard_drive",
            "card": {
                "component": diskCard,
                "w": 1,
                "h": 1,
                "minW": 1,
                "minH": 1,
                "maxH": 3
            },
            "options": [toggle("trend", I18n.tr("Show trend"), true), toggle("io", I18n.tr("Show I/O"), false), toneOption()]
        },
        {
            "id": "battery",
            "text": I18n.tr("Battery"),
            "icon": "battery_full",
            "description": BatteryService.batteryAvailable ? "" : I18n.tr("No battery", "battery status"),
            "available": BatteryService.batteryAvailable,
            "card": {
                "component": batteryCard,
                "w": 1,
                "h": 1,
                "minW": 1,
                "minH": 1,
                "maxH": 3
            },
            "options": [choice("style", I18n.tr("Style"), "solid", [
                    {
                        "value": "solid",
                        "text": I18n.tr("Solid")
                    },
                    {
                        "value": "outline",
                        "text": I18n.tr("Outline")
                    },
                    {
                        "value": "ring",
                        "text": I18n.tr("Ring", "noun, battery widget ring gauge style option")
                    }
                ]), choice("color", I18n.tr("Color"), "level", [
                    {
                        "value": "level",
                        "text": I18n.tr("Level", "battery settings: charge level indicator colors")
                    },
                    {
                        "value": "theme",
                        "text": I18n.tr("Theme", "battery settings: theme accent indicator colors")
                    }
                ]), toggle("health", I18n.tr("Show health"), false), toneOption()]
        }
    ]

    readonly property var pluginEntries: {
        const loaded = PluginService.loadedPlugins;
        const list = [];
        for (const pluginId in loaded) {
            const info = loaded[pluginId];
            const surfaces = info.surfaces ?? [];
            const hasTab = surfaces.includes("dash");
            const hasCard = surfaces.includes("dashCard");
            if (!hasTab && !hasCard)
                continue;
            const dash = info.dash ?? {};
            const card = dash.card ?? {};
            const options = Array.isArray(dash.options) ? dash.options.map(o => pluginOption(pluginId, o)).filter(o => o !== null) : [];
            const text = I18n.trFor(pluginId, dash.title ?? info.name ?? pluginId);
            const icon = dash.icon ?? info.icon ?? "extension";
            list.push({
                "id": pluginPrefix + pluginId,
                "pluginId": pluginId,
                "isPlugin": true,
                "text": text,
                "icon": icon,
                "description": info.description ?? I18n.tr("Plugin"),
                "options": options,
                "tab": hasTab ? {
                    "async": true
                } : null,
                "card": hasCard ? {
                    "text": card.title ? I18n.trFor(pluginId, card.title) : text,
                    "icon": card.icon ?? icon,
                    "w": clampCell(card.w, DashMetrics.gridColumns, 1),
                    "h": clampCell(card.h, DashMetrics.maximumCardRows, 1),
                    "minW": clampCell(card.minW, DashMetrics.gridColumns, 1),
                    "minH": clampCell(card.minH, DashMetrics.maximumCardRows, 1),
                    "maxW": clampCell(card.maxW, DashMetrics.gridColumns, DashMetrics.gridColumns),
                    "maxH": clampCell(card.maxH, DashMetrics.maximumCardRows, DashMetrics.maximumCardRows),
                    "async": true
                } : null
            });
        }
        list.sort((a, b) => a.text.localeCompare(b.text));
        return list;
    }

    readonly property var entries: {
        return builtins.map(e => e.card ? Object.assign({}, e, {
                "card": Object.assign({
                    "text": e.text,
                    "icon": e.icon,
                    "minW": 1,
                    "minH": 1,
                    "maxW": DashMetrics.gridColumns,
                    "maxH": DashMetrics.maximumCardRows
                }, e.card)
            }) : e).concat(pluginEntries).map(e => e.tab ? Object.assign({}, e, {
                "options": (e.options ?? []).concat(panelOptions(e.tab))
            }) : e);
    }

    readonly property var tabEntries: {
        const known = entries.filter(e => e.tab);
        const result = [];
        const seen = {};
        for (const tab of SettingsData.getDashTabs()) {
            const def = known.find(k => k.id === tab.id);
            if (!def || seen[tab.id])
                continue;
            seen[tab.id] = true;
            result.push(Object.assign({
                "enabled": tab.enabled
            }, def));
        }
        for (const def of known) {
            if (seen[def.id])
                continue;
            result.push(Object.assign({
                "enabled": true
            }, def));
        }
        return result;
    }
    readonly property var tabIds: tabEntries.filter(e => e.available !== false).map(e => e.id)
    readonly property int widestPanelColumns: Math.max(DashMetrics.defaultGridColumns, ...tabIds.map(id => DashMetrics.panelColumnsFor(id)))
    readonly property var visibleTabIds: tabEntries.filter(e => e.available !== false && e.enabled).map(e => e.id)
    readonly property var tabBarModel: visibleTabIds.map(id => {
        const e = entry(id);
        return {
            "icon": e.icon,
            "text": e.text
        };
    })

    readonly property var cardEntries: entries.filter(e => e.card)
    readonly property var placed: Array.isArray(SettingsData.dashCards) ? SettingsData.dashCards : []
    readonly property var unplaced: cardEntries.filter(e => e.available !== false && !placed.some(c => c.id === e.id))

    function pluginOption(pluginId, raw) {
        if (!raw || typeof raw.key !== "string" || raw.key === "" || raw.key === widgetsKey)
            return null;
        const spec = pluginOptionSpec(pluginId, raw);
        if (spec && raw.cardOnly === true)
            return cardOnly(spec);
        return spec;
    }

    function pluginOptionSpec(pluginId, raw) {
        const text = I18n.trFor(pluginId, raw.text ?? raw.key);
        switch (raw.type) {
        case "toggle":
            return toggle(raw.key, text, raw.def === true, typeof raw.description === "string" ? I18n.trFor(pluginId, raw.description) : "");
        case "choice":
            {
                const choices = (Array.isArray(raw.choices) ? raw.choices : []).filter(c => c && typeof c.value === "string").map(c => ({
                            "value": c.value,
                            "text": I18n.trFor(pluginId, c.text ?? c.value)
                        }));
                if (choices.length === 0)
                    return null;
                const def = choices.some(c => c.value === raw.def) ? raw.def : choices[0].value;
                return choice(raw.key, text, def, choices);
            }
        case "number":
            {
                const min = Number.isFinite(raw.min) ? raw.min : 0;
                const max = Math.max(min, Number.isFinite(raw.max) ? raw.max : 100);
                const def = Number.isFinite(raw.def) ? Math.max(min, Math.min(max, raw.def)) : min;
                return number(raw.key, text, def, min, max, Number.isFinite(raw.step) && raw.step > 0 ? raw.step : 1, typeof raw.unit === "string" ? raw.unit : "");
            }
        }
        return null;
    }

    function optionSpecs(id) {
        return entry(id)?.options ?? [];
    }

    function sheetOptionSpecs(id, tabScope = false) {
        return optionSpecs(id).filter(spec => spec.settingsOnly !== true && !(tabScope && spec.cardOnly === true));
    }

    function hasOptions(id, tabScope = false) {
        return sheetOptionSpecs(id, tabScope).length > 0;
    }

    function storedOptions(id) {
        const all = SettingsData.dashOptions;
        if (!all || typeof all !== "object")
            return {};
        const mine = all[id];
        return mine && typeof mine === "object" ? mine : {};
    }

    function hasStoredOptions(id) {
        const stored = storedOptions(id);
        return optionSpecs(id).some(spec => spec.key in stored);
    }

    function resolvedOptions(id, stored = storedOptions(id)) {
        const out = {};
        for (const spec of optionSpecs(id))
            out[spec.key] = optionValue(spec, stored[spec.key]);
        return out;
    }

    function optionValue(spec, value) {
        return Options.value(spec, value);
    }

    function option(id, key) {
        return resolvedOptions(id)[key];
    }

    function setOption(id, key, value) {
        setOptions(id, {
            [key]: value
        });
    }

    function setOptions(id, values) {
        const specs = optionSpecs(id);
        const all = Object.assign({}, SettingsData.dashOptions ?? {});
        const mine = Object.assign({}, storedOptions(id));
        let changed = false;
        for (const key in values) {
            const spec = specs.find(s => s.key === key);
            if (!spec)
                continue;
            const value = optionValue(spec, values[key]);
            if (value === (key in mine ? mine[key] : spec.def))
                continue;
            if (value === spec.def)
                delete mine[key];
            else
                mine[key] = value;
            changed = true;
        }
        if (!changed)
            return;
        if (Object.keys(mine).length === 0)
            delete all[id];
        else
            all[id] = mine;
        SettingsData.set("dashOptions", all);
    }

    function setPanelSize(id, columns, rows) {
        setOptions(id, {
            "panelColumns": columns,
            "panelRows": rows
        });
    }

    function resetPanelSize(id) {
        const stored = storedOptions(id);
        if (!("panelColumns" in stored) && !("panelRows" in stored))
            return;
        setPanelSize(id, DashMetrics.defaultGridColumns, DashMetrics.defaultRowsFor(id));
    }

    function resetOptions(id) {
        if (!hasStoredOptions(id))
            return;
        const all = Object.assign({}, SettingsData.dashOptions ?? {});
        const mine = Object.assign({}, storedOptions(id));
        for (const spec of optionSpecs(id))
            delete mine[spec.key];
        if (Object.keys(mine).length === 0)
            delete all[id];
        else
            all[id] = mine;
        SettingsData.set("dashOptions", all);
    }

    function widgetLayout(id) {
        const value = storedOptions(id)[widgetsKey];
        return Array.isArray(value) ? value : null;
    }

    function setWidgetLayout(id, widgets) {
        if (!entry(id))
            return;
        const all = Object.assign({}, SettingsData.dashOptions ?? {});
        const mine = Object.assign({}, storedOptions(id));
        if (widgets === null)
            delete mine[widgetsKey];
        else
            mine[widgetsKey] = widgets;
        if (Object.keys(mine).length === 0)
            delete all[id];
        else
            all[id] = mine;
        SettingsData.set("dashOptions", all);
    }

    function clampCell(value, max, fallback) {
        const n = Number(value);
        if (!Number.isInteger(n))
            return fallback;
        return Math.max(1, Math.min(max, n));
    }

    function entry(id) {
        return entries.find(e => e.id === id) ?? null;
    }

    function hasTab(id) {
        return tabIds.includes(id);
    }

    function isSelectable(id) {
        return visibleTabIds.includes(id);
    }

    function tabComponentFor(id) {
        const e = entry(id);
        if (!e?.tab)
            return null;
        if (!e.isPlugin)
            return e.tab.component;
        return PluginService.pluginDashComponents[e.pluginId] ?? null;
    }

    function indexId(index) {
        return visibleTabIds[index] ?? defaultTabId;
    }

    function resolveId(tab) {
        if (typeof tab === "number")
            return indexId(tab);
        const raw = String(tab ?? "").trim();
        if (raw === "")
            return defaultTabId;
        if (/^\d+$/.test(raw))
            return indexId(parseInt(raw));
        if (hasTab(raw))
            return raw;
        const lower = raw.toLowerCase();
        return tabIds.find(id => id.toLowerCase() === lower) ?? defaultTabId;
    }

    function indexOf(id) {
        return visibleTabIds.indexOf(id);
    }

    function isCardAvailable(id) {
        const e = entry(id);
        return !!e?.card && e.available !== false;
    }

    function cardComponentFor(id) {
        const e = entry(id);
        if (!e?.card)
            return null;
        if (!e.isPlugin)
            return e.card.component;
        return PluginService.pluginDashCardComponents[e.pluginId] ?? null;
    }

    function clampSize(id, w, h) {
        const card = entry(id)?.card;
        if (!card)
            return {
                "w": w,
                "h": h
            };
        return {
            "w": Math.min(DashMetrics.gridColumns, Math.max(card.minW, Math.min(card.maxW, w))),
            "h": Math.max(card.minH, Math.min(card.maxH, h))
        };
    }

    function minSize(id) {
        const card = entry(id)?.card;
        return {
            "w": card?.minW ?? 1,
            "h": card?.minH ?? 1
        };
    }

    function defaultSize(id) {
        const card = entry(id)?.card;
        return card ? {
            "w": Math.min(DashMetrics.gridColumns, card.w),
            "h": card.h
        } : {
            "w": 1,
            "h": 1
        };
    }

    Component {
        id: overviewTab
        OverviewTab {}
    }

    Component {
        id: mediaTab
        MediaPlayerTab {}
    }

    Component {
        id: wallpaperTab
        WallpaperTab {}
    }

    Component {
        id: weatherTab
        WeatherTab {}
    }

    Component {
        id: notificationsTab
        NotificationsTab {}
    }

    Component {
        id: notificationsCard
        NotificationsOverviewCard {}
    }

    Component {
        id: wellbeingTab
        WellbeingTab {}
    }

    Component {
        id: wellbeingCard
        WellbeingOverviewCard {}
    }

    Component {
        id: clockCard
        ClockCard {}
    }

    Component {
        id: weatherCard
        WeatherOverviewCard {}
    }

    Component {
        id: userCard
        UserInfoCard {}
    }

    Component {
        id: calendarCard
        CalendarOverviewCard {}
    }

    Component {
        id: mediaCard
        MediaOverviewCard {}
    }

    Component {
        id: sysmonCard
        SystemMonitorCard {}
    }

    Component {
        id: cpuCard
        CpuCard {}
    }

    Component {
        id: memoryCard
        MemoryCard {}
    }

    Component {
        id: networkCard
        NetworkCard {}
    }

    Component {
        id: diskCard
        DiskCard {}
    }

    Component {
        id: batteryCard
        BatteryCard {}
    }
}
