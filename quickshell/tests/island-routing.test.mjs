import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

function functions(source, indent, context) {
    const pattern = new RegExp(`^${indent}function (\\w+)\\(([^)]*)\\)(?:: \\w+)? \\{([\\s\\S]*?)^${indent}\\}`, "gm");
    for (const [, name, parameters, body] of source.matchAll(pattern)) {
        const args = parameters.replace(/:\s*\w+/g, "");
        vm.runInContext(`function ${name}(${args}) {${body}}`, context);
    }
    return context;
}

const settingsSource = readFileSync(new URL("../Common/SettingsData.qml", import.meta.url), "utf8");
const widgetDefaults = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/settings/BarWidgetDefaults.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), widgetDefaults);
const plain = value => JSON.parse(JSON.stringify(value));
const islandDashActivities = ["home", "media", "weather", "wallpaper"];

test("shared shortcuts follow the last eligible surface independently on each screen", () => {
    const screens = [{ name: "internal" }, { name: "external" }];
    const dot = { id: "dot", dot: true, islandSharedRouting: "last-used" };
    const island = { id: "island", island: true };
    const configs = { internal: [dot, island], external: [dot, island] };
    const settings = functions(settingsSource, "    ", vm.createContext({ lastUsedBarByScreen: {}, islandDashActivities }));
    settings.activeIslandConfigsForScreen = screen => configs[screen.name];
    settings.getActiveBarEdgesForScreen = () => ["top"];
    settings.islandSetting = (config, key) => config[key];

    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), null);
    settings.recordBarInteraction(screens[0], "dot");
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), dot);
    assert.equal(settings.sharedTriggerIslandConfig(screens[1]), null);
    settings.recordBarInteraction(screens[1], "island");
    assert.equal(settings.sharedTriggerIslandConfig(screens[1]), island);
    settings.recordBarInteraction(screens[0], "standard");
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), null);
    assert.equal(settings.sharedTriggerIslandConfig(screens[1]), island);

    settings.recordBarInteraction(screens[0], "dot");
    configs.internal = [island];
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), null, "disabled/removed dots cannot retain routing");
    configs.internal = [dot, island];
    dot.islandSharedRouting = "always";
    settings.recordBarInteraction(screens[0], "standard");
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), dot, "fixed routing still wins");
    dot.islandSharedRouting = "normal";
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), null);
    settings.getActiveBarEdgesForScreen = () => [];
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), island, "sole-island fallback is preserved");
    configs.internal = [dot];
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), dot, "a dot alone on the screen takes the shortcuts");
    configs.internal = [dot, island];
    settings.getActiveBarEdgesForScreen = () => ["top"];
    island.islandSharedRouting = "last-used";
    settings.recordBarInteraction(screens[0], "dot");
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), dot, "a free island can enable last-used routing for all surfaces");
    island.islandSharedRouting = "always";
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), island, "always-here also supports islands");
    dot.islandSharedRouting = "last-used";
    settings.recordBarInteraction(screens[0], "standard");
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), null, "last-used takes precedence over a fixed instance");
});

test("a satellite hosting the activity's widget counts as a standard destination under normal routing", () => {
    const screen = { name: "internal" };
    const island = { id: "island", island: true, islandSatellitesEnabled: true, rightWidgets: ["controlCenterButton"] };
    const dot = { id: "dot", dot: true, rightWidgets: ["controlCenterButton"] };
    const configs = [island];
    const settings = functions(settingsSource, "    ", vm.createContext({ lastUsedBarByScreen: {}, islandDashActivities }));
    settings.activeIslandConfigsForScreen = () => configs;
    settings.getActiveBarEdgesForScreen = () => [];
    settings.islandSetting = (config, key) => config[key];

    assert.equal(settings.sharedTriggerIslandConfig(screen, "controlcenter"), null, "the satellite popout takes the shortcut");
    assert.equal(settings.sharedTriggerIslandConfig(screen, "launcher"), island, "other activities keep the sole-island fallback");
    island.islandRouteControlCenter = "island";
    assert.equal(settings.sharedTriggerIslandConfig(screen, "controlcenter"), island, "a pin still outranks the satellite");
    delete island.islandRouteControlCenter;
    island.rightWidgets = [{ id: "controlCenterButton", enabled: false }];
    assert.equal(settings.sharedTriggerIslandConfig(screen, "controlcenter"), island, "a disabled satellite is no destination");
    island.rightWidgets = ["controlCenterButton"];
    island.islandSatellitesEnabled = false;
    assert.equal(settings.sharedTriggerIslandConfig(screen, "controlcenter"), island, "hidden satellites are no destination");
    configs.splice(0, 1, dot);
    assert.equal(settings.sharedTriggerIslandConfig(screen, "controlcenter"), dot, "a dot's inherited widget list never counts");
});

test("the island launcher face takes any island on the screen that has not opted out", () => {
    const screen = { name: "internal" };
    const island = { id: "island", island: true };
    const hosted = { id: "bar", rightWidgets: ["island"] };
    const dot = { id: "dot", dot: true };
    let configs = [hosted, dot];
    const settings = functions(settingsSource, "    ", vm.createContext({ lastUsedBarByScreen: {}, islandDashActivities, launcherStyle: "island" }));
    settings.activeIslandConfigsForScreen = () => configs;
    settings.getActiveBarEdgesForScreen = () => ["top"];
    settings.islandSetting = (config, key) => config[key];

    assert.equal(settings.sharedTriggerIslandConfig(screen, "launcher"), null, "normal routing keeps standard destinations");
    assert.equal(settings.islandLauncherHostConfig(screen), hosted, "the face still lands on the screen's island");
    hosted.islandRouteLauncher = "bar";
    assert.equal(settings.islandLauncherHostConfig(screen), dot, "an opted-out island passes to the next one");
    dot.islandRouteLauncher = "island";
    assert.equal(settings.islandLauncherHostConfig(screen), dot, "a pin keeps choosing the host");
    delete dot.islandRouteLauncher;
    configs = [hosted];
    assert.equal(settings.islandLauncherHostConfig(screen), null, "no willing island means the modal");
    configs = [island];
    settings.launcherStyle = "spotlight";
    assert.equal(settings.islandLauncherHostConfig(screen), null, "other faces never borrow an island");
});

test("always-here is exclusive among islands and dots sharing a screen", () => {
    const screens = [{ name: "internal" }, { name: "external" }];
    const covers = { dot: ["internal", "external"], island: ["internal"], remote: ["external"] };
    const settings = functions(settingsSource, "    ", vm.createContext({
        Quickshell: { screens },
        islandDefaults: { islandSharedRouting: "normal" },
        barConfigs: [{ id: "dot", dot: true, islandSharedRouting: "always" }, { id: "island", island: true }, { id: "remote", island: true, islandSharedRouting: "always" }]
    }));
    settings.updateBarConfigs = () => {};
    settings._applyConnectedFrameBarStyles = configs => ({ configs });
    settings.barConfigCoversScreen = (cfg, screen) => covers[cfg.id].includes(screen.name);
    settings.setIslandSharedRouting("island", "always");
    assert.deepEqual([...settings.barConfigs].map(cfg => cfg.islandSharedRouting), [undefined, "always", "always"], "same-screen always is reset, other-screen always is kept");
    settings.setIslandSharedRouting("island", "last-used");
    assert.deepEqual([...settings.barConfigs].map(cfg => cfg.islandSharedRouting), [undefined, "last-used", "always"]);
});

const islandWidget = values => ({ id: "island", enabled: true, ...values });

function hostedSettings(barConfigs, extra = {}) {
    const settings = functions(settingsSource, "    ", vm.createContext({
        Quickshell: { screens: [{ name: "internal" }] },
        lastUsedBarByScreen: {},
        islandDashActivities,
        islandDefaults: widgetDefaults.ISLAND_DEFAULTS,
        islandWidgetDefaults: widgetDefaults.DEFAULTS.island,
        _islandHomeGroupIds: ["media", "clock"],
        _islandHomeLayoutDefault: [{ id: "media", enabled: true }, { id: "clock", enabled: true }],
        barConfigs,
        barIpcRevealStates: {},
        notificationPopupsInvalidated: () => {},
        ...extra
    }));
    settings.updateBarConfigs = () => {};
    settings.barConfigCoversScreen = () => true;
    settings.getBarConfig = id => settings.barConfigs.find(cfg => cfg.id === id);
    settings._applyConnectedFrameBarStyles = configs => ({ configs });
    return settings;
}

test("per-activity overrides pin one activity without moving the shared rule", () => {
    const screen = { name: "internal" };
    const island = { id: "island", island: true, islandSharedRouting: "always" };
    const hosted = { id: "bar", rightWidgets: [islandWidget({ islandSharedRouting: "normal" })] };
    const settings = hostedSettings([island, hosted]);
    settings.activeIslandConfigsForScreen = () => [hosted];
    settings.getActiveBarEdgesForScreen = () => ["top"];

    assert.equal(settings.sharedTriggerIslandConfig(screen, "controlcenter"), null, "bar popouts by default");
    settings.islandWidgetEntry(hosted).islandRouteControlCenter = "island";
    assert.equal(settings.sharedTriggerIslandConfig(screen, "controlcenter"), hosted, "control center pinned to the island");
    assert.equal(settings.sharedTriggerIslandConfig(screen, "launcher"), null, "other activities keep the rule");
    assert.equal(settings.sharedShortcutsOverridden(screen, "controlcenter"), true);
    assert.equal(settings.sharedShortcutsOverridden(screen, "launcher"), false);
    settings.islandWidgetEntry(hosted).islandRouteDash = "island";
    assert.equal(settings.sharedTriggerIslandConfig(screen, "weather"), hosted, "the legacy dash route covers weather until it gets its own value");

    settings.activeIslandConfigsForScreen = () => [island];
    assert.equal(settings.sharedTriggerIslandConfig(screen, "launcher"), island);
    island.islandRouteLauncher = "bar";
    assert.equal(settings.sharedTriggerIslandConfig(screen, "launcher"), null, "an always island can still hand one activity to the bar");
    assert.equal(settings.sharedTriggerIslandConfig(screen, "controlcenter"), island);
    settings.getActiveBarEdgesForScreen = () => [];
    assert.equal(settings.sharedTriggerIslandConfig(screen, "launcher"), null, "bar keeps the island out even as the sole surface");
    assert.equal(settings.sharedTriggerIslandConfig(screen, "volume"), island, "activities without an override follow the rule");
});

test("dashboard, media, weather and wallpaper have independent route keys with legacy fallback", () => {
    const settings = hostedSettings([
        { id: "standalone", island: true, islandRouteDash: "island" },
        { id: "hosted", rightWidgets: [islandWidget({ islandRouteDash: "bar" })] }
    ]);
    const standalone = settings.barConfigs[0];
    const hosted = settings.barConfigs[1];
    const entry = settings.islandWidgetEntry(hosted);
    assert.deepEqual(["home", "media", "weather", "wallpaper"].map(activity => settings.islandRouteKey(activity)),
        ["islandRouteDash", "islandRouteMedia", "islandRouteWeather", "islandRouteWallpaper"]);
    for (const activity of ["media", "weather", "wallpaper"]) {
        assert.equal(settings.islandActivityRoutingMode(standalone, activity), "always", `${activity} inherits the old standalone dash route`);
        assert.equal(settings.islandActivityRoutingMode(hosted, activity), "never", `${activity} inherits the old hosted dash route`);
    }
    standalone.islandRouteMedia = "bar";
    entry.islandRouteWeather = "island";
    assert.equal(settings.islandActivityRoutingMode(standalone, "media"), "never");
    assert.equal(settings.islandActivityRoutingMode(standalone, "weather"), "always");
    assert.equal(settings.islandActivityRoutingMode(hosted, "weather"), "always");
    assert.equal(settings.islandActivityRoutingMode(hosted, "media"), "never");
    assert.equal(settings.islandActivityRoutingMode(hosted, "home"), "never");
});

test("editing dashboard snapshots legacy routes before changing its fallback", () => {
    const settings = hostedSettings([
        { id: "standalone", island: true, islandRouteDash: "island", islandRouteWeather: "bar" },
        { id: "hosted", rightWidgets: [islandWidget({ islandRouteDash: "bar", islandRouteMedia: "island" })] }
    ]);
    assert.equal(settings.getBarConfig("standalone").islandRouteMedia, undefined, "legacy routes remain unset until edited");
    assert.equal(settings.islandWidgetEntry(settings.getBarConfig("hosted")).islandRouteWallpaper, undefined);
    settings.updateBarConfig = (id, patch) => Object.assign(settings.getBarConfig(id), patch);
    settings.updateBarWidget = (id, section, index, patch) => Object.assign(settings.getBarConfig(id)[`${section}Widgets`][index], patch);

    settings.setIslandSettings("standalone", { islandRouteDash: "bar" });
    const standalone = settings.getBarConfig("standalone");
    assert.equal(settings.islandActivityRoutingMode(standalone, "home"), "never");
    assert.deepEqual(["media", "weather", "wallpaper"].map(activity => settings.islandActivityRoutingMode(standalone, activity)),
        ["always", "never", "always"], "standalone media, weather and wallpaper retain their old destinations");
    assert.deepEqual([standalone.islandRouteMedia, standalone.islandRouteWeather, standalone.islandRouteWallpaper],
        ["island", "bar", "island"], "the snapshot is persisted as independent keys");

    settings.setIslandSettings("hosted", { islandRouteDash: "island" });
    const hosted = settings.getBarConfig("hosted");
    const entry = settings.islandWidgetEntry(hosted);
    assert.equal(settings.islandActivityRoutingMode(hosted, "home"), "always");
    assert.deepEqual(["media", "weather", "wallpaper"].map(activity => settings.islandActivityRoutingMode(hosted, activity)),
        ["always", "never", "never"], "hosted media, weather and wallpaper retain their old destinations");
    assert.deepEqual([entry.islandRouteMedia, entry.islandRouteWeather, entry.islandRouteWallpaper],
        ["island", "bar", "bar"]);
});

test("an explicit media pin wins over inherited last-used routing", () => {
    const screen = { name: "internal" };
    const settings = hostedSettings([
        { id: "last", dot: true, islandSharedRouting: "last-used" },
        { id: "always", island: true, islandSharedRouting: "always" },
        { id: "pinned", rightWidgets: [islandWidget({ islandRouteMedia: "island" })] }
    ]);
    settings.activeIslandConfigsForScreen = () => settings.barConfigs;
    settings.getActiveBarEdgesForScreen = () => ["top"];
    settings.recordBarInteraction(screen, "last");
    assert.equal(settings.sharedTriggerIslandConfig(screen, "media"), settings.getBarConfig("pinned"));
    assert.equal(settings.sharedTriggerIslandConfig(screen, "weather"), settings.getBarConfig("last"),
        "last-used still precedes an inherited always route");
});

test("an explicit follow route disables the legacy dashboard fallback", () => {
    const settings = hostedSettings([
        { id: "standalone", island: true, islandRouteDash: "island" },
        { id: "hosted", rightWidgets: [islandWidget({ islandRouteDash: "island" })] }
    ]);
    const standalone = settings.getBarConfig("standalone");
    const hosted = settings.getBarConfig("hosted");
    settings.updateBarConfig = (id, patch) => Object.assign(settings.getBarConfig(id), patch);
    settings.updateBarWidget = (id, section, index, patch) => Object.assign(settings.getBarConfig(id)[`${section}Widgets`][index], patch);
    settings.setIslandSettings("standalone", { islandRouteMedia: "follow" });
    settings.setIslandSettings("hosted", { islandRouteMedia: "follow" });
    assert.equal(settings.islandActivityRoutingMode(standalone, "media"), "normal");
    assert.equal(settings.islandActivityRoutingMode(hosted, "media"), "normal");
    assert.equal(settings.islandActivityRoutingMode(standalone, "weather"), "always");
    assert.equal(settings.islandActivityRoutingMode(hosted, "weather"), "always");
});

test("a hosted island routes and competes through its widget entry, not the island-mode keys", () => {
    const screens = [{ name: "internal" }];
    // Flat keys are what the bar used as an island; the hosted island must neither read nor write them.
    const settings = hostedSettings([{ id: "bar", islandSharedRouting: "last-used", islandPalette: "dim", islandOuterGap: 9, rightWidgets: ["clock", islandWidget({ islandSharedRouting: "always" })] }, { id: "dot", dot: true }]);
    const bar = () => settings.barConfigs.find(cfg => cfg.id === "bar");
    const entry = () => settings.islandWidgetEntry(bar());
    assert.equal(settings.hostsIsland(bar()), true);
    assert.equal(settings.islandSharedRoutingMode(bar()), "always");
    assert.equal(settings.islandSetting(bar(), "islandPalette"), "default", "island-mode palette does not reach the hosted island");
    assert.equal(settings.islandSetting(bar(), "islandNotificationPopups"), true, "hosted defaults keep popups standard");
    assert.equal(settings.islandSetting(settings.barConfigs[1], "islandNotificationPopups"), false, "dots keep the island defaults");
    settings.setIslandSharedRouting("dot", "always");
    assert.equal(entry().islandSharedRouting, undefined, "always on a dot resets the hosted island");
    assert.equal(bar().islandSharedRouting, "last-used", "the island-mode key is left alone");
    settings.setIslandSharedRouting("bar", "always");
    assert.deepEqual([entry().islandSharedRouting, bar().islandSharedRouting, settings.barConfigs[1].islandSharedRouting], ["always", "last-used", undefined]);
    settings.setIslandSharedRouting("bar", "last-used");
    assert.equal(settings.islandSharedRoutingMode(bar()), "normal", "last-used degenerates to normal on a hosted island");
    assert.equal(settings.islandSharedRoutingMode({ id: "island", island: true, islandSharedRouting: "last-used" }), "last-used");
    settings.setIslandSharedRouting("dot", "always");
    settings.barConfigs.push({ id: "plain" });
    settings.setIslandSharedRouting("plain", "always");
    assert.equal(settings.barConfigs[1].islandSharedRouting, "always", "a bar without an island cannot clear a dot's always");

    const hosted = { id: "bar", islandSharedRouting: "always", centerWidgets: ["island"] };
    settings.activeIslandConfigsForScreen = () => [hosted];
    settings.getActiveBarEdgesForScreen = () => ["top"];
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), null, "a flat always from island mode does not route into the hosted island");
    hosted.centerWidgets = [islandWidget({ islandSharedRouting: "always" })];
    assert.equal(settings.sharedTriggerIslandConfig(screens[0]), hosted);
});

test("island settings write to the config for islands and to the widget entry for a hosted island", () => {
    const settings = hostedSettings([{ id: "island", island: true }, { id: "bar", islandOuterGap: 9, islandHomeLayout: [{ id: "clock", enabled: true }, { id: "media", enabled: false }], leftWidgets: ["island"] }]);
    const configs = new Proxy([], { get: (_, key) => settings.barConfigs[key] });
    settings.setIslandSettings("island", { islandOuterGap: 7 });
    settings.setIslandSettings("bar", { islandOuterGap: 6 });
    assert.equal(configs[0].islandOuterGap, 7);
    assert.deepEqual(plain(configs[1].leftWidgets), [{ id: "island", enabled: true, islandOuterGap: 6 }], "a bare string entry is upgraded in place");
    assert.equal(configs[1].islandOuterGap, 9, "island-mode value survives");
    assert.equal(settings.islandSetting(configs[1], "islandOuterGap"), 6);
    assert.equal(settings.islandHomeGroupEnabled(configs[1], "media"), true, "island-mode home layout does not reach the hosted island");
    settings.setIslandHomeGroupEnabled("bar", "media", false);
    assert.equal(settings.islandHomeGroupEnabled(configs[1], "media"), false);
    assert.equal(configs[1].islandHomeLayout[1].enabled, false, "island-mode layout untouched");
    assert.deepEqual(plain(configs[1].leftWidgets[0].islandHomeLayout.map(g => g.enabled)), [false, true]);
    settings.setIslandSettings("missing", { islandOuterGap: 1 });
    settings.barConfigs.push({ id: "plain" });
    settings.setIslandSettings("plain", { islandOuterGap: 1 });
    assert.deepEqual(plain(configs[2]), { id: "plain" }, "a bar without the widget takes no island settings");
});

test("adding the island widget is exclusive per screen and refused across an island-layout bar", () => {
    const covers = { a: ["internal"], b: ["internal", "external"], c: ["external"], island: ["internal"], other: ["other"] };
    const settings = hostedSettings([{ id: "a", centerWidgets: ["clock"] }, { id: "b", leftWidgets: ["island"] }, { id: "c", rightWidgets: [islandWidget({ islandOuterGap: 2 })] }, { id: "island", island: true, enabled: true }, { id: "other" }], {
        Quickshell: { screens: [{ name: "internal" }, { name: "external" }, { name: "other" }] }
    });
    settings.barConfigCoversScreen = (cfg, screen) => covers[cfg.id].includes(screen.name);
    const byId = id => settings.barConfigs.find(cfg => cfg.id === id);
    assert.equal(settings.islandWidgetBlocked(byId("a")), true, "an island-layout bar covers this screen");
    assert.equal(settings.addBarWidget("a", "center", "island"), -1);
    assert.deepEqual(plain(byId("a").centerWidgets), ["clock"]);
    assert.equal(settings.addBarWidget("island", "center", "island"), -1, "island-layout bars never take the widget");
    assert.equal(settings.islandWidgetBlocked(byId("other")), false);
    assert.equal(settings.addBarWidget("other", "right", "island"), 0);
    assert.deepEqual(plain(byId("other").rightWidgets), [{ id: "island", enabled: true }]);
    assert.equal(settings.addBarWidget("other", "left", "island"), -1, "one island per bar");
    settings.barConfigs[3].island = false;
    assert.equal(settings.addBarWidget("a", "center", "island"), 1);
    assert.deepEqual(plain(byId("a").centerWidgets), ["clock", { id: "island", enabled: true }]);
    assert.deepEqual([byId("b").leftWidgets, byId("c").rightWidgets, byId("other").rightWidgets].map(plain), [[], [{ id: "island", enabled: true, islandOuterGap: 2 }], [{ id: "island", enabled: true }]], "same-screen hosts are evicted, other screens keep theirs");
    assert.deepEqual(plain(byId("b").islandWidgetStash), { entry: "island", sectionId: "left", index: 0 }, "an evicted bar keeps its placement");
    settings.updateBarConfig("a", { enabled: false });
    assert.deepEqual(plain(byId("b").leftWidgets), [], "the other host still holds a screen the evicted bar spans");
    settings.updateBarConfig("c", { enabled: false });
    assert.deepEqual([plain(byId("a").centerWidgets), plain(byId("b").leftWidgets)], [["clock", { id: "island", enabled: true }], ["island"]], "disabling the owners gives the island back");
    assert.equal(byId("b").islandWidgetStash, undefined);
    settings.updateBarConfig("a", { enabled: true });
    assert.deepEqual(plain(byId("b").leftWidgets), [], "re-enabling an owner evicts again");
    settings.updateBarWidget("a", "center", 1, { enabled: false });
    assert.deepEqual(plain(byId("b").leftWidgets), ["island"], "a disabled entry owns no screen");
    settings.updateBarWidget("a", "center", 1, { enabled: true });
    assert.deepEqual(plain(byId("b").leftWidgets), []);
    settings.updateBarConfig("c", { enabled: true });

    settings.setBarIsland("c", true, true);
    assert.deepEqual([plain(byId("c").rightWidgets), plain(byId("a").centerWidgets)], [[], ["clock", { id: "island", enabled: true }]], "a dot drops its own widget and evicts nothing");
    settings.setBarIsland("c", false);
    assert.deepEqual(plain(byId("c").rightWidgets), [{ id: "island", enabled: true, islandOuterGap: 2 }], "back to standard restores the widget with its settings");
    assert.equal(byId("c").islandWidgetStash, undefined);
    settings.setBarIsland("c", true);
    assert.equal(byId("c").island, true);
    settings.setBarIsland("b", true);
    assert.deepEqual(plain(byId("a").centerWidgets), ["clock"], "island layout evicts hosted islands on its screens");
    assert.equal(settings.hostsIsland(byId("a")), false);
    assert.equal(settings.hostsIsland(byId("b")), true);
    assert.equal(settings.hostsIsland({ id: "x", centerWidgets: [{ id: "island", enabled: false }] }), false);
    settings.setBarIsland("c", false);
    assert.deepEqual(plain(byId("c").rightWidgets), [], "a restore never evicts: the island bar on the same screen keeps it");
    assert.equal(byId("c").islandWidgetStash?.entry.islandOuterGap, 2, "the refused restore waits with its settings");

    // A disabled island-layout bar is not on screen: it neither blocks the widget nor loses its own on eviction.
    byId("b").enabled = false;
    assert.equal(settings.islandWidgetBlocked(byId("a")), false, "a disabled island-layout bar blocks nothing");
    settings.setBarIsland("b", false);
    assert.deepEqual([plain(byId("a").centerWidgets), plain(byId("c").rightWidgets)], [["clock", { id: "island", enabled: true }], [{ id: "island", enabled: true, islandOuterGap: 2 }]], "the freed screens restore the waiting widgets");
    byId("b").leftWidgets = [islandWidget({ islandOuterGap: 5 })];
    settings.updateBarConfig("a", { enabled: true });
    assert.deepEqual(plain(byId("b").leftWidgets), [{ id: "island", enabled: true, islandOuterGap: 5 }], "a disabled bar keeps its island and settings");
    byId("b").leftWidgets = [];
    assert.equal(settings.addBarWidget("b", "left", "island"), 0);
    assert.deepEqual(plain(byId("c").rightWidgets), [{ id: "island", enabled: true, islandOuterGap: 2 }], "a disabled bar taking the widget evicts nobody");

    // Switching a hidden bar to Island must clear the hide, or the island draws but never routes.
    byId("a").visible = false;
    settings.setBarIsland("a", true);
    assert.equal(byId("a").visible, true, "island layout clears a stale hide");
});

test("hidden bars drop out of routing and hosted defaults keep popups and OSDs standard", () => {
    const screen = { name: "internal" };
    const settings = hostedSettings([{ id: "a", visible: false, centerWidgets: [islandWidget({ islandSystemOsd: true, islandNotificationPopups: false })] }, { id: "island", island: true }]);
    const byId = id => settings.barConfigs.find(cfg => cfg.id === id);
    const routed = ["a"];
    settings.ShellLayout = { islandConfigs: () => routed.map(byId) };
    assert.deepEqual(settings.activeIslandConfigsForScreen(screen), [], "a hidden host swallows nothing");
    byId("a").visible = true;
    assert.deepEqual(settings.activeIslandConfigsForScreen(screen), [byId("a")]);
    assert.equal(settings.dankIslandHandlesSystemOsd(screen), true);
    assert.equal(settings.dankIslandHandlesNotifications(screen), true);
    byId("a").islandSystemOsd = false;
    assert.equal(settings.dankIslandHandlesSystemOsd(screen), true, "a flat island-mode key does not move the OSD");
    settings.setIslandSettings("a", { islandSystemOsd: settings.islandDefaultsFor(byId("a")).islandSystemOsd, islandNotificationPopups: settings.islandDefaultsFor(byId("a")).islandNotificationPopups });
    assert.equal(settings.dankIslandHandlesSystemOsd(screen), false, "hosted defaults keep OSDs standard");
    assert.equal(settings.dankIslandHandlesNotifications(screen), false);
    routed[0] = "island";
    assert.equal(settings.dankIslandHandlesSystemOsd(screen), true, "islands keep their OSDs by default");
    byId("island").visible = false;
    assert.deepEqual(settings.activeIslandConfigsForScreen(screen), [], "a hidden island-layout bar swallows nothing either");
});

test("shared launcher entry points bypass a previously loaded launcher and forward query/mode", () => {
    const calls = [];
    let fallbacks = 0;
    let overridden = true;
    const screen = { name: "external" };
    const source = readFileSync(new URL("../Services/PopoutService.qml", import.meta.url), "utf8");
    const service = functions(source, "    ", vm.createContext({
        CompositorService: { getFocusedScreen: () => screen },
        SettingsData: { sharedShortcutsOverridden: () => overridden },
        dankIslandRouter: {
            openLauncher: (...args) => { calls.push(["open", ...args]); return true; },
            toggleLauncher: (...args) => { calls.push(["toggle", ...args]); return true; }
        },
        dankLauncherV2Modal: { show: () => fallbacks++, hide() {}, toggle: () => fallbacks++ }
    }));
    service._sharedTriggerIsland = () => ({ screen, barId: "clicked-dot" });
    service._setDankLauncherV2TriggerUsesOverlayLayer = () => {};
    service._setDankLauncherV2EdgeHoverManaged = () => {};
    for (const [method, argument, action, query, mode] of [
        ["openDankLauncherV2", undefined, "open", "", ""],
        ["toggleDankLauncherV2", undefined, "toggle", "", ""],
        ["openDankLauncherV2WithQuery", "firefox", "open", "firefox", ""],
        ["toggleDankLauncherV2WithQuery", "firefox", "toggle", "firefox", ""],
        ["openDankLauncherV2WithMode", "files", "open", "", "files"],
        ["toggleDankLauncherV2WithMode", "files", "toggle", "", "files"]
    ]) {
        service[method](argument);
        assert.deepEqual(calls.at(-1), [action, query, mode, screen, "clicked-dot"]);
    }
    assert.equal(fallbacks, 0);
    overridden = false;
    service.openDankLauncherV2();
    assert.equal(fallbacks, 1, "normal routing preserves the configured launcher");
});

test("an IPC close takes down every surface showing the activity", () => {
    const source = readFileSync(new URL("../Services/PopoutService.qml", import.meta.url), "utf8");
    let islandShowing = {};
    const closed = [];
    const service = functions(source, "    ", vm.createContext({
        dankIslandRouter: {
            closeActivity: activity => {
                if (!islandShowing[activity])
                    return false;
                closed.push("island:" + activity);
                islandShowing[activity] = false;
                return true;
            }
        },
        controlCenterPopout: { close: () => closed.push("popout:controlcenter") },
        notificationCenterPopout: null,
        dankLauncherV2Modal: { hide: () => closed.push("modal:launcher") }
    }));
    islandShowing = { controlcenter: true, launcher: true };
    service.closeControlCenter();
    service.closeDankLauncherV2();
    assert.deepEqual(closed.splice(0), ["island:controlcenter", "popout:controlcenter", "island:launcher", "modal:launcher"], "island face and bar surface both close");
    service.closeDankLauncherV2();
    assert.deepEqual(closed.splice(0), ["modal:launcher"], "a quiet island is skipped, the modal still hides");
});

test("control-center IPC hide and status agree on both surfaces", () => {
    const ipcSource = readFileSync(new URL("../DMSShellIPC.qml", import.meta.url), "utf8");
    const block = ipcSource.split('target: "control-center"')[0].split("IpcHandler {").pop();
    const calls = [];
    const popout = { shouldBeVisible: false, close: () => calls.push("popout:close") };
    const state = { islandOpen: false, routed: false };
    const bar = { triggerControlCenter: () => calls.push("bar:trigger") };
    const handler = functions(block, "        ", vm.createContext({
        root: { controlCenterLoaderRef: { item: popout }, getPreferredBar: () => bar },
        PopoutService: {
            get islandControlCenterOpen() {
                return state.islandOpen;
            },
            closeIslandActivity: () => {
                if (!state.islandOpen)
                    return false;
                calls.push("island:close");
                state.islandOpen = false;
                return true;
            },
            routeToIsland: () => {
                if (!state.routed)
                    return false;
                calls.push("island:toggle");
                return true;
            }
        }
    }));
    assert.equal(handler.status(), "hidden");
    assert.equal(handler.hide(), "CONTROL_CENTER_HIDE_FAILED");
    state.islandOpen = true;
    assert.equal(handler.status(), "visible", "an island face counts");
    popout.shouldBeVisible = true;
    assert.equal(handler.hide(), "CONTROL_CENTER_HIDE_SUCCESS");
    assert.deepEqual(calls.splice(0), ["island:close", "popout:close"], "hide closes both");
    popout.shouldBeVisible = false;
    assert.equal(handler.status(), "hidden");
    assert.equal(handler.toggle(), "CONTROL_CENTER_TOGGLE_SUCCESS");
    assert.deepEqual(calls.splice(0), ["bar:trigger"], "toggle opens the policy surface");
    state.routed = true;
    assert.equal(handler.toggle(), "CONTROL_CENTER_TOGGLE_SUCCESS");
    assert.deepEqual(calls.splice(0), ["island:toggle"]);
});

test("the privacy slot is a known home layout entry appended after stored ones", () => {
    const groupIds = JSON.parse(settingsSource.match(/_islandHomeGroupIds: (\[.*\])/)[1]);
    const layoutDefault = JSON.parse(settingsSource.match(/_islandHomeLayoutDefault: (\[[\s\S]*?\n    \])/)[1]);
    const settings = functions(settingsSource, "    ", vm.createContext({ _islandHomeGroupIds: groupIds, _islandHomeLayoutDefault: layoutDefault }));
    settings.islandSetting = (config, key) => config[key];
    settings.islandSettings = config => config;
    const legacy = { islandHomeLayout: [{ id: "clock" }, { id: "media", enabled: false }] };
    const ids = settings.getIslandHomeLayout(legacy).map(entry => entry.id);
    assert.ok(ids.includes("privacy"), "a stored layout gains the privacy slot");
    assert.ok(ids.includes("tray"), "a stored layout gains the tray slot");
    assert.equal(ids.indexOf("tray"), ids.length - 1, "new slots append after the stored order");
});

test("power menu shortcuts open in the island before the modal", () => {
    const popoutSource = readFileSync(new URL("../Services/PopoutService.qml", import.meta.url), "utf8");
    const ipcSource = readFileSync(new URL("../DMSShellIPC.qml", import.meta.url), "utf8");
    const block = ipcSource.split('target: "powermenu"')[0].split("IpcHandler {").pop();
    const calls = [];
    const state = { routed: false };
    const modal = { shouldBeVisible: false, openCentered: () => { modal.shouldBeVisible = true; calls.push("modal:open"); }, close: () => { modal.shouldBeVisible = false; calls.push("modal:close"); } };
    const loader = { active: false, item: null };
    Object.defineProperty(loader, "active", { get: () => loader.item !== null, set: on => { if (on) loader.item = modal; } });
    const context = vm.createContext({
        powerMenuModalLoader: loader,
        powerMenuModal: null,
        dankIslandRouter: {
            closeActivity: id => { calls.push("island:close:" + id); return true; }
        }
    });
    const service = functions(popoutSource, "    ", context);
    service.routeToIsland = (id, screen, toggle) => {
        if (!state.routed)
            return false;
        calls.push(`island:${toggle ? "toggle" : "open"}:${id}`);
        return true;
    };
    const handler = functions(block, "        ", vm.createContext({ root: {}, PopoutService: service }));

    state.routed = true;
    assert.equal(handler.toggle(), "POWERMENU_TOGGLE_SUCCESS");
    assert.equal(handler.open(), "POWERMENU_OPEN_SUCCESS");
    assert.deepEqual(calls.splice(0), ["island:toggle:powermenu", "island:open:powermenu"], "routed shortcuts leave the modal alone");
    assert.equal(loader.item, null, "the modal loader stays inactive");

    state.routed = false;
    assert.equal(handler.toggle(), "POWERMENU_TOGGLE_SUCCESS");
    assert.deepEqual(calls.splice(0), ["modal:open"], "no island means the centered modal");
    handler.toggle();
    assert.deepEqual(calls.splice(0), ["modal:close"], "a visible modal closes without asking the router");
    assert.equal(handler.open(), "POWERMENU_OPEN_SUCCESS");
    assert.deepEqual(calls.splice(0), ["modal:open"]);

    assert.equal(handler.close(), "POWERMENU_CLOSE_SUCCESS");
    assert.deepEqual(calls.splice(0), ["island:close:powermenu", "modal:close"], "close takes down both surfaces");
});

test("a right-click face swap holds hover-open until the pointer leaves", () => {
    const source = readFileSync(new URL("../Modules/DIsland/IslandController.qml", import.meta.url), "utf8");
    const requested = [];
    const timer = { stop() {}, restart() {} };
    const controller = functions(source, "    ", vm.createContext({
        activeActivity: "home",
        mediaFaceToggleAvailable: true,
        hoverHeld: false,
        inputSuspended: false,
        hoverExpandEnabled: true,
        slotHovered: false,
        notificationActive: false,
        hoverExpanded: false,
        expanded: false,
        hoverOpenTimer: timer,
        hoverCloseTimer: timer
    }));
    controller.requestActivity = id => requested.push(id) > 0;
    controller.requestExpand = () => true;
    controller.syncNotificationTimeout = () => {};
    controller.syncTransientTimeout = () => {};

    assert.equal(controller.toggleMediaFace(), true);
    assert.deepEqual(requested, ["media"]);
    assert.equal(controller.requestHoverExpand(), false, "the resized face must not hover-open under the pointer");
    controller.updatePointerInside(false);
    controller.updatePointerInside(true);
    assert.equal(controller.requestHoverExpand(), true, "leaving the island releases the hold");

    controller.mediaFaceToggleAvailable = false;
    assert.equal(controller.toggleMediaFace(), false);
    assert.equal(vm.runInContext("hoverHeld", controller), false);
});
