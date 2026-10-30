import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const catalog = loadScript(new URL("../Common/ActionCatalog.js", import.meta.url));
const root = new URL("../", import.meta.url);

function build(input) {
    return catalog.buildDefs(Object.assign({
        themes: [{ name: "blue", label: "Blue" }],
        bluetoothDevices: [{ address: "aa:bb:cc:dd:ee:ff", name: "WH-1000XM5", icon: "headset" }],
        vpnProfiles: [{ uuid: "uuid-1", name: "Office" }]
    }, input));
}

function byId(defs, id) {
    const def = defs.find(d => d.id === id);
    assert.ok(def, "missing action " + id);
    return def;
}

// Fake services record what the action calls; overrides replace whole services.
function makeCtx(overrides = {}) {
    const calls = [];
    const rec = name => (...args) => {
        calls.push([name, ...args]);
        return true;
    };
    const ctx = {
        tr: term => term,
        theme: { isLightMode: false, currentTheme: "blue", matugenAvailable: true, dynamic: "dynamic", setLightMode: rec("setLightMode"), switchTheme: rec("switchTheme") },
        night: { nightModeEnabled: false, gammaControlAvailable: true, enableNightMode: rec("enableNight"), disableNightMode: rec("disableNight") },
        sessionData: { doNotDisturb: false, setDoNotDisturb: rec("setDnd") },
        audio: {
            sink: { audio: { muted: false } }, source: { audio: { muted: false } }, sinkVolumePercent: 30, sourceVolumePercent: 60,
            setVolume: rec("setVolume"), adjustDefaultSinkVolume: rec("adjustVolume"), toggleMute: rec("toggleMute"), setMicVolume: rec("setMicVolume"), toggleMicMute: rec("toggleMicMute")
        },
        mpris: { activePlayer: { isPlaying: true }, playPause: rec("playPause"), play: rec("play"), pause: rec("pause"), next: rec("next"), previousOrRewind: rec("previous") },
        brightness: {
            brightnessAvailable: true,
            devices: [{ id: "backlight:intel", name: "intel", class: "backlight" }, { id: "leds:tpacpi::kbd_backlight", name: "tpacpi::kbd_backlight", class: "leds" }],
            levels: { "backlight:intel": 50, "leds:tpacpi::kbd_backlight": 0 },
            getPreferredDevices() { return ["backlight:intel"]; },
            getCurrentDeviceInfoByName(id) { return this.devices.find(d => d.id === id) || null; },
            getDeviceBrightness(id) { return this.levels[id]; },
            brightnessMinimum: info => info && info.class === "backlight" ? 1 : 0,
            brightnessMaximum: () => 100,
            setGroupBrightness: rec("setGroupBrightness"), setBrightness: rec("setBrightness")
        },
        network: { networkAvailable: true, wifiAvailable: true, wifiEnabled: true, wifiToggling: false, cellularAvailable: false, cellularEnabled: false, cellularToggling: false, toggleWifiRadio: rec("toggleWifi"), toggleCellularRadio: rec("toggleCellular") },
        bluetooth: {
            available: true, enabled: true, setBluetoothEnabled: rec("setBluetooth"), connectDeviceWithTrust: rec("connectBluetooth"),
            pairedDevices: [{ address: "AA:BB:CC:DD:EE:FF", connected: false, disconnect: rec("disconnectBluetooth") }]
        },
        vpn: {
            vpnAvailable: true, vpnProfiles: [{ uuid: "uuid-1" }], vpnConnected: false, vpnIsBusy: false, activeUuids: [],
            isActiveVpnUuid(uuid) { return this.activeUuids.includes(uuid); },
            connectVpn: rec("connectVpn"), disconnectVpn: rec("disconnectVpn"), disconnectAllVpns: rec("disconnectAllVpns"), toggleVpn: rec("toggleVpn")
        },
        power: {
            available: true, availableProfiles: [0, 1, 2], currentProfile: 1,
            parseProfileSlug: slug => ({ "power-saver": 0, balanced: 1, performance: 2 })[slug] ?? -1,
            profileSlug: profile => ["power-saver", "balanced", "performance"][profile] ?? "unknown",
            applyProfile: rec("applyProfile")
        },
        sessionService: { executePowerAction: rec("powerAction"), isPowerActionSupported: () => true, inhibitorAvailable: true, idleInhibited: false, enableIdleInhibit: rec("inhibit"), disableIdleInhibit: rec("uninhibit") },
        idle: { lockRequested: rec("lock") },
        popout: { openPowerMenu: rec("openPowerMenu") },
        settings: { powerActionConfirm: false },
        compositor: {
            compositorDetected: true, isHyprland: false, isNiri: false, isMango: false, isSway: false, isScroll: false, isMiracle: false,
            powerOffMonitors: rec("monitorsOff"), getFocusedScreenName: () => "DP-1"
        },
        hyprlandService: { luaConfigActive: true, luaString: v => JSON.stringify(v), luaValue: v => typeof v === "number" ? String(v) : JSON.stringify(v) },
        hyprland: { dispatch: rec("hyprland") },
        niri: { send: rec("niri") },
        mango: { available: true, dispatch: rec("mango") },
        i3: { dispatch: rec("i3") },
        screenNames: () => ["DP-1", "HDMI-A-1"],
        exec: rec("exec")
    };
    for (const [key, value] of Object.entries(overrides))
        ctx[key] = Object.assign({}, ctx[key], value);
    ctx.calls = calls;
    return ctx;
}

const plain = value => JSON.parse(JSON.stringify(value));

test("every action has a unique id, an English description and keywords", () => {
    const defs = build();
    const ids = new Set(defs.map(d => d.id));
    assert.equal(ids.size, defs.length);
    for (const def of defs) {
        assert.match(def.text, /^[\x20-\x7e]{60,}$/, def.id + " description must be rich English text");
        assert.ok(def.keywords.length >= 3, def.id + " needs keywords");
        assert.ok(def.icon && def.category, def.id);
    }
});

test("items carry the contract fields and param units", () => {
    const defs = build();
    const item = plain(catalog.toItem(byId(defs, "audio.volume.set"), t => t));
    assert.deepEqual(Object.keys(item).sort(), ["category", "icon", "id", "keywords", "params", "text", "title"]);
    assert.deepEqual(item.params, [{ name: "percent", type: "percent", min: 0, max: 100, unit: "%" }]);
    const timer = plain(catalog.toItem(byId(defs, "notifications.dnd"), t => t));
    assert.equal(timer.params[0].unit, "minutes");
    assert.deepEqual(plain(catalog.toIndexItem(item)), { id: item.id, title: item.title, text: item.text, keywords: item.keywords, payload: { category: "audio" } });
});

test("dynamic families come from real device data and titles use the translation", () => {
    const defs = build();
    const tr = term => term === "Blue" ? "Mavi" : term === "Color scheme: %1" ? "Renk şeması: %1" : term;
    assert.equal(catalog.toItem(byId(defs, "theme.scheme.blue"), tr).title, "Renk şeması: Mavi");
    assert.equal(catalog.toItem(byId(defs, "bluetooth.device:AA:BB:CC:DD:EE:FF"), tr).title, "Bluetooth: WH-1000XM5");
    assert.match(byId(defs, "bluetooth.device:AA:BB:CC:DD:EE:FF").text, /headphones/);
    assert.equal(catalog.toItem(byId(defs, "network.vpn:uuid-1"), tr).title, "VPN: Office");
    assert.equal(build({ bluetoothDevices: [], vpnProfiles: [] }).some(d => /^(bluetooth\.device|network\.vpn):/.test(d.id)), false);
});

test("dark mode follows the typed intent instead of always flipping", () => {
    const def = byId(build(), "theme.dark");
    let ctx = makeCtx();
    assert.equal(catalog.stateText(def, ctx), "On");
    assert.equal(catalog.run(def, ctx, "karanlık tema kapat").ok, true);
    assert.deepEqual(ctx.calls, [["setLightMode", true, true, true]]);

    ctx = makeCtx();
    catalog.run(def, ctx, "dark mode");
    assert.deepEqual(ctx.calls, [["setLightMode", true, true, true]], "no intent flips the current state");

    ctx = makeCtx();
    const result = plain(catalog.run(def, ctx, "karanlık tema aç"));
    assert.deepEqual(ctx.calls, [], "already dark, asked for dark: nothing to do");
    assert.deepEqual(result, { ok: true, message: "Dark mode: On" });

    ctx = makeCtx({ theme: { isLightMode: true } });
    assert.equal(catalog.stateText(def, ctx), "Off");
    catalog.run(def, ctx, "dark");
    assert.deepEqual(ctx.calls, [["setLightMode", false, true, true]]);
});

test("a switch named for its other side is set, not flipped", () => {
    const def = byId(build(), "theme.dark");
    const cases = [
        [false, "aydınlık tema", [["setLightMode", true, true, true]]],
        [true, "aydınlık tema", []],
        [false, "light mode", [["setLightMode", true, true, true]]],
        [false, "aydınlık tema aç", [["setLightMode", true, true, true]]],
        [true, "aydınlık tema kapat", [["setLightMode", false, true, true]]],
        [true, "karanlık tema", [["setLightMode", false, true, true]]]
    ];
    for (const [lightNow, query, expected] of cases) {
        const ctx = makeCtx({ theme: { isLightMode: lightNow } });
        catalog.run(def, ctx, query);
        assert.deepEqual(plain(ctx.calls), expected, query + " while " + (lightNow ? "light" : "dark"));
    }
});

test("notification verbs describe the notifications, not the switch", () => {
    const def = byId(build(), "notifications.dnd");
    const cases = [
        [false, "bildirimleri kapat", [["setDnd", true, 0]]],
        [true, "bildirimleri aç", [["setDnd", false, 0]]],
        [false, "rahatsız etme aç", [["setDnd", true, 0]]],
        [true, "rahatsız etme kapat", [["setDnd", false, 0]]],
        [false, "disable notifications", [["setDnd", true, 0]]],
        [true, "do not disturb off", [["setDnd", false, 0]]]
    ];
    for (const [on, query, expected] of cases) {
        const ctx = makeCtx({ sessionData: { doNotDisturb: on } });
        catalog.run(def, ctx, query);
        assert.deepEqual(plain(ctx.calls), expected, query);
    }
});

test("mute switches read 'sesi aç' as unmuting", () => {
    const def = byId(build(), "audio.mute");
    let ctx = makeCtx({ audio: { sink: { audio: { muted: true } } } });
    assert.equal(catalog.stateText(def, ctx), "Muted");
    catalog.run(def, ctx, "sesi aç");
    assert.deepEqual(ctx.calls, [["toggleMute"]]);
    ctx = makeCtx();
    catalog.run(def, ctx, "sesi aç");
    assert.deepEqual(ctx.calls, [], "already audible");
    catalog.run(def, ctx, "sesi kapat");
    assert.deepEqual(ctx.calls, [["toggleMute"]]);
    ctx = makeCtx();
    catalog.run(byId(build(), "audio.mic.mute"), ctx, "mikrofonu sustur");
    assert.deepEqual(ctx.calls, [["toggleMicMute"]]);
});

test("volume with and without a value", () => {
    const defs = build();
    const set = byId(defs, "audio.volume.set");
    let ctx = makeCtx();
    assert.deepEqual(plain(catalog.run(set, ctx, "sesi 80'e çıkar")), { ok: true, message: "" });
    assert.deepEqual(ctx.calls, [["setVolume", 80]]);
    ctx = makeCtx();
    const missing = plain(catalog.run(set, ctx, "sesi ayarla"));
    assert.equal(missing.ok, false);
    assert.equal(missing.reason, "missing");
    assert.equal(missing.param.example, "40%");
    assert.deepEqual(ctx.calls, []);
    ctx = makeCtx();
    catalog.run(byId(defs, "audio.volume.up"), ctx, "sesi 10 arttır");
    catalog.run(byId(defs, "audio.volume.down"), ctx, "sesi kıs");
    assert.deepEqual(ctx.calls, [["adjustVolume", 10, 1], ["adjustVolume", 5, -1]]);
    assert.equal(catalog.stateText(set, makeCtx({ audio: { sink: { audio: { muted: true } } } })), "Muted");
    assert.equal(catalog.stateText(set, makeCtx()), "30%");
    ctx = makeCtx({ audio: { sink: null } });
    assert.equal(catalog.isAvailable(set, ctx), false);
    assert.equal(catalog.run(set, ctx, "40").reason, "unavailable");
});

test("display brightness uses the preferred display and never a keyboard LED", () => {
    const defs = build();
    const set = byId(defs, "display.brightness.set");
    let ctx = makeCtx();
    catalog.run(set, ctx, "parlaklığı %0 yap");
    assert.deepEqual(ctx.calls, [["setGroupBrightness", 1, ["backlight:intel"], false]], "a backlight never goes fully dark");
    ctx = makeCtx();
    catalog.run(byId(defs, "display.brightness.up"), ctx, "daha parlak");
    catalog.run(byId(defs, "display.brightness.down"), ctx, "parlaklığı 20 azalt");
    assert.deepEqual(ctx.calls, [["setGroupBrightness", 60, ["backlight:intel"], false], ["setGroupBrightness", 30, ["backlight:intel"], false]]);
    assert.equal(catalog.stateText(set, makeCtx()), "50%");
    ctx = makeCtx({ brightness: { getPreferredDevices: () => ["leds:tpacpi::kbd_backlight"] } });
    assert.equal(catalog.isAvailable(set, ctx), false);
    ctx = makeCtx({ brightness: { brightnessAvailable: false } });
    assert.equal(catalog.isAvailable(set, ctx), false);
});

test("keyboard backlight and flashlight exist only where the device does", () => {
    const defs = build();
    const keyboard = byId(defs, "keyboard.backlight");
    const flashlight = byId(defs, "light.flashlight");
    let ctx = makeCtx();
    assert.equal(catalog.isAvailable(keyboard, ctx), true);
    assert.equal(catalog.isAvailable(flashlight, ctx), false, "a keyboard LED is not a flashlight");
    catalog.run(keyboard, ctx, "klavye ışığı");
    catalog.run(keyboard, ctx, "klavye ışığını %40 yap");
    assert.deepEqual(ctx.calls, [["setBrightness", 100, "leds:tpacpi::kbd_backlight", false], ["setBrightness", 40, "leds:tpacpi::kbd_backlight", false]]);
    ctx = makeCtx({ brightness: { devices: [{ id: "leds:white:torch", name: "white:torch", class: "leds" }], levels: { "leds:white:torch": 100 } } });
    assert.equal(catalog.isAvailable(flashlight, ctx), true);
    assert.equal(catalog.isAvailable(keyboard, ctx), false);
    assert.equal(catalog.stateText(flashlight, ctx), "On");
    catalog.run(flashlight, ctx, "feneri kapat");
    assert.deepEqual(ctx.calls, [["setBrightness", 0, "leds:white:torch", false]]);
});

test("do not disturb and keep awake take a duration", () => {
    const defs = build();
    let ctx = makeCtx();
    catalog.run(byId(defs, "notifications.dnd"), ctx, "rahatsız etme 30 dakika");
    catalog.run(byId(defs, "notifications.dnd"), ctx, "dnd");
    assert.deepEqual(ctx.calls, [["setDnd", true, 30], ["setDnd", true, 0]]);
    ctx = makeCtx({ sessionData: { doNotDisturb: true } });
    catalog.run(byId(defs, "notifications.dnd"), ctx, "rahatsız etme kapat");
    assert.deepEqual(ctx.calls, [["setDnd", false, 0]]);
    ctx = makeCtx();
    catalog.run(byId(defs, "session.keepawake"), ctx, "ekran kapanmasın 1 saat");
    assert.deepEqual(ctx.calls, [["inhibit", 60]]);
    ctx = makeCtx({ sessionService: { idleInhibited: true } });
    catalog.run(byId(defs, "session.keepawake"), ctx, "uyanık tut");
    assert.deepEqual(ctx.calls, [["uninhibit"]]);
});

test("night mode is unavailable until gamma control is", () => {
    const def = byId(build(), "display.nightlight");
    assert.equal(catalog.isAvailable(def, makeCtx({ night: { gammaControlAvailable: false } })), false);
    const ctx = makeCtx();
    catalog.run(def, ctx, "gece ışığı aç");
    assert.deepEqual(ctx.calls, [["enableNight"]]);
});

test("radios: wifi, bluetooth, airplane mode", () => {
    const defs = build();
    let ctx = makeCtx();
    catalog.run(byId(defs, "network.wifi"), ctx, "internet kapat");
    catalog.run(byId(defs, "network.wifi"), ctx, "wifi aç");
    assert.deepEqual(ctx.calls, [["toggleWifi"]], "wifi is on, so only the off request acts");
    assert.equal(plain(catalog.run(byId(defs, "network.wifi"), makeCtx({ network: { wifiToggling: true } }), "wifi kapat")).reason, "busy");

    ctx = makeCtx();
    catalog.run(byId(defs, "bluetooth.power"), ctx, "bluetooth kapat");
    assert.deepEqual(ctx.calls, [["setBluetooth", false]]);

    const airplane = byId(defs, "network.airplane");
    ctx = makeCtx();
    assert.equal(catalog.stateText(airplane, ctx), "Off");
    catalog.run(airplane, ctx, "uçak modu");
    assert.deepEqual(ctx.calls, [["toggleWifi"], ["setBluetooth", false]]);
    ctx = makeCtx({ network: { wifiEnabled: false }, bluetooth: { enabled: false } });
    assert.equal(catalog.stateText(airplane, ctx), "On");
    catalog.run(airplane, ctx, "uçak modu");
    assert.deepEqual(ctx.calls, [["toggleWifi"], ["setBluetooth", true]], "leaving airplane mode restores every radio");
    ctx = makeCtx({ network: { networkAvailable: false }, bluetooth: { available: false } });
    assert.equal(catalog.isAvailable(airplane, ctx), false);
});

test("bluetooth devices and vpn connections toggle individually", () => {
    const defs = build();
    const device = byId(defs, "bluetooth.device:AA:BB:CC:DD:EE:FF");
    let ctx = makeCtx();
    assert.equal(catalog.stateText(device, ctx), "Disconnected");
    catalog.run(device, ctx, "kulaklığa bağlan");
    assert.equal(ctx.calls[0][0], "connectBluetooth");
    assert.equal(ctx.calls[0][1].address, "AA:BB:CC:DD:EE:FF");
    assert.equal(catalog.isAvailable(device, makeCtx({ bluetooth: { enabled: false } })), false);
    assert.equal(catalog.isAvailable(device, makeCtx({ bluetooth: { pairedDevices: [] } })), false);

    const vpn = byId(defs, "network.vpn:uuid-1");
    ctx = makeCtx({ vpn: { activeUuids: ["uuid-1"] } });
    assert.equal(catalog.stateText(vpn, ctx), "Connected");
    catalog.run(vpn, ctx, "vpn");
    assert.deepEqual(ctx.calls, [["disconnectVpn", "uuid-1"]]);
    ctx = makeCtx();
    catalog.run(vpn, ctx, "vpn");
    assert.deepEqual(ctx.calls, [["connectVpn", "uuid-1"]]);
    ctx = makeCtx({ vpn: { vpnConnected: true } });
    catalog.run(byId(defs, "network.vpn"), ctx, "vpn kapat");
    assert.deepEqual(ctx.calls, [["disconnectAllVpns"]]);
    assert.equal(plain(catalog.run(vpn, makeCtx({ vpn: { vpnIsBusy: true } }), "vpn")).reason, "busy");
    assert.equal(catalog.isAvailable(byId(defs, "network.vpn"), makeCtx({ vpn: { vpnProfiles: [] } })), false);
});

test("power profiles apply the matching profile and show the active one", () => {
    const defs = build();
    const saver = byId(defs, "power.profile.power-saver");
    const balanced = byId(defs, "power.profile.balanced");
    const ctx = makeCtx();
    catalog.run(saver, ctx, "pil tasarrufu");
    assert.deepEqual(ctx.calls, [["applyProfile", 0]]);
    assert.equal(catalog.stateText(balanced, ctx), "Active");
    assert.equal(catalog.stateText(saver, ctx), "");
    const noPerformance = makeCtx({ power: { availableProfiles: [0, 1] } });
    assert.equal(catalog.isAvailable(byId(defs, "power.profile.performance"), noPerformance), false);
    assert.equal(catalog.isAvailable(saver, makeCtx({ power: { available: false } })), false);
});

test("destructive session actions defer to the held-to-confirm power menu", () => {
    const defs = build();
    let ctx = makeCtx();
    for (const [id, action] of [["session.reboot", "reboot"], ["session.poweroff", "poweroff"], ["session.logout", "logout"], ["session.suspend", "suspend"], ["session.hibernate", "hibernate"]])
        catalog.run(byId(defs, id), ctx, "");
    assert.deepEqual(ctx.calls.map(c => c[1]), ["reboot", "poweroff", "logout", "suspend", "hibernate"]);
    ctx = makeCtx({ settings: { powerActionConfirm: true } });
    catalog.run(byId(defs, "session.poweroff"), ctx, "bilgisayarı kapat");
    assert.deepEqual(ctx.calls, [["openPowerMenu"]]);
    ctx = makeCtx({ sessionService: { isPowerActionSupported: action => action !== "hibernate" } });
    assert.equal(catalog.isAvailable(byId(defs, "session.hibernate"), ctx), false);
    ctx = makeCtx();
    catalog.run(byId(defs, "session.lock"), ctx, "kilitle");
    catalog.run(byId(defs, "display.off"), ctx, "ekranı kapat");
    assert.deepEqual(ctx.calls, [["lock"], ["monitorsOff"]]);
});

test("media actions need a player", () => {
    const defs = build();
    const ctx = makeCtx();
    for (const id of ["media.playpause", "media.play", "media.pause", "media.next", "media.previous"])
        catalog.run(byId(defs, id), ctx, "");
    assert.deepEqual(ctx.calls.map(c => c[0]), ["playPause", "play", "pause", "next", "previous"]);
    assert.equal(catalog.stateText(byId(defs, "media.playpause"), ctx), "Playing");
    assert.equal(catalog.stateText(byId(defs, "media.playpause"), makeCtx({ mpris: { activePlayer: { isPlaying: false } } })), "Paused");
    const none = makeCtx({ mpris: { activePlayer: null } });
    assert.equal(catalog.isAvailable(byId(defs, "media.next"), none), false);
});

test("screenshots run the dms command", () => {
    const defs = build();
    const ctx = makeCtx();
    for (const mode of ["region", "full", "window", "all", "scroll"])
        catalog.run(byId(defs, "screenshot." + mode), ctx, "");
    assert.deepEqual(plain(ctx.calls), ["region", "full", "window", "all", "scroll"].map(mode => ["exec", ["dms", "screenshot", mode]]));
});

test("color schemes switch the stock theme or the wallpaper palette", () => {
    const defs = build();
    const ctx = makeCtx();
    catalog.run(byId(defs, "theme.scheme.blue"), ctx, "");
    catalog.run(byId(defs, "theme.scheme.dynamic"), ctx, "");
    assert.deepEqual(ctx.calls, [["switchTheme", "blue"], ["switchTheme", "dynamic"]]);
    assert.equal(catalog.stateText(byId(defs, "theme.scheme.blue"), ctx), "Active");
    assert.equal(catalog.isAvailable(byId(defs, "theme.scheme.dynamic"), makeCtx({ theme: { matugenAvailable: false } })), false);
});

const WINDOW_IDS = ["window.close", "window.fullscreen", "window.float", "window.move-workspace", "window.move-screen"];

function windowCalls(ctxOverrides, query = "") {
    const defs = build();
    const ctx = makeCtx(ctxOverrides);
    for (const id of WINDOW_IDS)
        catalog.run(byId(defs, id), ctx, query);
    return plain(ctx.calls);
}

test("window actions speak each compositor's own protocol", () => {
    assert.deepEqual(windowCalls({ compositor: { isHyprland: true } }), [
        ["hyprland", "hl.dsp.window.close()"],
        ["hyprland", "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })"],
        ["hyprland", "hl.dsp.window.float({ action = \"toggle\" })"],
        ["hyprland", "hl.dsp.window.move({ workspace = \"+1\", follow = true })"],
        ["hyprland", "hl.dsp.window.move({ monitor = \"HDMI-A-1\", follow = true })"]
    ]);
    assert.deepEqual(windowCalls({ compositor: { isNiri: true } }), [
        ["niri", { Action: { CloseWindow: { id: null } } }],
        ["niri", { Action: { FullscreenWindow: { id: null } } }],
        ["niri", { Action: { ToggleWindowFloating: { id: null } } }],
        ["niri", { Action: { MoveWindowToWorkspaceDown: { focus: true } } }],
        ["niri", { Action: { MoveWindowToMonitor: { id: null, output: "HDMI-A-1" } } }]
    ]);
    assert.deepEqual(windowCalls({ compositor: { isMango: true } }), [
        ["mango", "killclient"], ["mango", "togglefullscreen"], ["mango", "togglefloating"], ["mango", "tagtoright"]
    ]);
    assert.deepEqual(windowCalls({ compositor: { isSway: true } }), [
        ["i3", "kill"], ["i3", "fullscreen toggle"], ["i3", "floating toggle"], ["i3", "move container to workspace next"], ["i3", "move container to output \"HDMI-A-1\""]
    ]);
});

test("a workspace number in the query picks that workspace", () => {
    const defs = build();
    const move = byId(defs, "window.move-workspace");
    const cases = [
        [{ isHyprland: true }, "hyprland", "hl.dsp.window.move({ workspace = 3, follow = true })"],
        [{ isNiri: true }, "niri", { Action: { MoveWindowToWorkspace: { window_id: null, reference: { Index: 3 }, focus: true } } }],
        [{ isMango: true }, "mango", "tag,3"],
        [{ isScroll: true }, "i3", "move container to workspace number 3"]
    ];
    for (const [flags, target, expected] of cases) {
        const ctx = makeCtx({ compositor: flags });
        catalog.run(move, ctx, "pencereyi 3. çalışma alanına taşı");
        assert.deepEqual(plain(ctx.calls), [[target, expected]]);
    }
});

test("window actions are unavailable where no backend can run them", () => {
    const defs = build();
    const close = byId(defs, "window.close");
    assert.equal(catalog.isAvailable(close, makeCtx()), false, "unknown compositor");
    assert.equal(catalog.isAvailable(close, makeCtx({ compositor: { isHyprland: true }, hyprlandService: { luaConfigActive: false } })), false, "Hyprland without Lua config");
    assert.equal(catalog.isAvailable(close, makeCtx({ compositor: { isMango: true }, mango: { available: false } })), false);
    assert.equal(catalog.run(close, makeCtx(), "").reason, "unavailable");
    const screen = byId(defs, "window.move-screen");
    assert.equal(catalog.isAvailable(screen, makeCtx({ compositor: { isHyprland: true } })), true);
    const single = makeCtx({ compositor: { isHyprland: true } });
    single.screenNames = () => ["DP-1"];
    assert.equal(catalog.isAvailable(screen, single), false, "one display has nowhere to move to");
    assert.equal(catalog.isAvailable(screen, makeCtx({ compositor: { isMango: true } })), false, "mango has no named-output move");
});

test("a failing niri send is reported as a failure", () => {
    const ctx = makeCtx({ compositor: { isNiri: true }, niri: { send: () => false } });
    assert.equal(plain(catalog.run(byId(build(), "window.close"), ctx, "")).reason, "failed");
});

test("plugin actions are validated and namespaced", () => {
    const run = () => {};
    const good = { id: "lamp.on", title: "Lamp on", text: "Turn on the living room lamp; light, bulb, smart home.", keywords: ["lamp", "lamba"], params: [{ name: "percent", type: "percent", min: 0, max: 100 }], run };
    const built = catalog.pluginDefs("duxHome", [
        good,
        { id: "bad id", title: "x", text: "y", run },
        { id: "no-run", title: "x", text: "y" },
        { id: "bad-param", title: "x", text: "y", run, params: [{ name: "n", type: "color" }] },
        { id: "lamp.on", title: "Duplicate", text: "again", run },
        { id: "bad-range", title: "x", text: "y", run, params: [{ name: "n", type: "int", min: "1" }] }
    ]);
    assert.deepEqual(plain(built.defs.map(d => d.id)), ["plugin:duxHome:lamp.on"]);
    assert.equal(built.errors.length, 5);
    const item = plain(catalog.toItem(built.defs[0], t => "translated:" + t));
    assert.equal(item.title, "Lamp on", "plugin titles are the plugin's own text");
    assert.equal(item.category, "plugin");
    assert.equal(item.icon, "extension");
    assert.equal(catalog.pluginDefs("bad/id", [good]).defs.length, 0);
});

test("a plugin action receives the parsed values and its own state hooks", () => {
    const seen = [];
    let reachable = true;
    const built = catalog.pluginDefs("duxHome", [{
        id: "lamp", title: "Lamp", text: "Turn the lamp on and set its brightness.", params: [{ name: "percent", type: "percent", min: 0, max: 100 }],
        available: () => reachable, state: () => "Living room",
        run: (values, query) => seen.push([plain(values), query])
    }, {
        id: "boom", title: "Boom", text: "Always throws.", run: () => false
    }, {
        id: "hook-throws", title: "Hook", text: "Availability hook throws.", available: () => { throw new Error("x"); }, run: () => {}
    }]);
    const [lamp, boom, hook] = built.defs;
    const ctx = makeCtx();
    assert.deepEqual(plain(catalog.run(lamp, ctx, "oda ışığı %30")), { ok: true, message: "Lamp" });
    assert.deepEqual(seen, [[{ percent: 30 }, "oda ışığı %30"]]);
    assert.equal(catalog.stateText(lamp, ctx), "Living room");
    reachable = false;
    assert.equal(catalog.run(lamp, ctx, "x").reason, "unavailable");
    assert.equal(catalog.run(boom, ctx, "").reason, "failed", "run returning false is a failure");
    assert.equal(catalog.isAvailable(hook, ctx), true, "a throwing availability hook falls back to available");
});

test("every ctx.<service>.<member> the catalog uses is declared and exists in the service source", () => {
    const source = readFileSync(new URL("../Common/ActionCatalog.js", import.meta.url), "utf8");
    const declared = loadScript(new URL("../Common/ActionCatalog.js", import.meta.url)).serviceMembers();
    const used = {};
    for (const [, key, member] of source.matchAll(/\bctx\.([a-zA-Z0-9]+)\.([a-zA-Z0-9]+)/g))
        (used[key] ??= new Set()).add(member);
    for (const [key, members] of Object.entries(used)) {
        assert.ok(declared[key], "ctx." + key + " is not declared in SERVICE_MEMBERS");
        for (const member of members)
            assert.ok(declared[key].members.includes(member), "ctx." + key + "." + member + " is used but not declared");
    }
    for (const [key, entry] of Object.entries(declared)) {
        for (const member of entry.members)
            assert.ok(used[key]?.has(member), "ctx." + key + "." + member + " is declared but never used");
        if (entry.file === "")
            continue;
        const service = readFileSync(new URL(entry.file, root), "utf8");
        for (const member of entry.members) {
            const defined = new RegExp("(function\\s+" + member + "\\s*\\(|property\\s+[\\w.<>]+\\s+" + member + "\\b|signal\\s+" + member + "\\b)").test(service);
            assert.ok(defined, entry.file + " has no " + member);
        }
    }
});

function argCount(text, open) {
    let depth = 0;
    let count = 0;
    let sawToken = false;
    for (let i = open; i < text.length; i++) {
        const c = text[i];
        if (c === "(" || c === "[" || c === "{") {
            depth++;
            if (depth > 1)
                sawToken = true;
        } else if (c === ")" || c === "]" || c === "}") {
            depth--;
            if (depth === 0)
                return sawToken ? count + 1 : 0;
        } else if (c === "," && depth === 1) {
            count++;
        } else if (depth >= 1 && !/\s/.test(c)) {
            sawToken = true;
        }
    }
    return -1;
}

test("service calls pass no more arguments than the service function declares", () => {
    const source = readFileSync(new URL("../Common/ActionCatalog.js", import.meta.url), "utf8");
    const declared = loadScript(new URL("../Common/ActionCatalog.js", import.meta.url)).serviceMembers();
    let checked = 0;
    for (const match of source.matchAll(/\bctx\.([a-zA-Z0-9]+)\.([a-zA-Z0-9]+)\(/g)) {
        const entry = declared[match[1]];
        if (!entry || entry.file === "")
            continue;
        const service = readFileSync(new URL(entry.file, root), "utf8");
        const signature = new RegExp("(?:function|signal)\\s+" + match[2] + "\\s*\\(([^)]*)\\)").exec(service) || new RegExp("signal\\s+" + match[2] + "\\s*\\n").exec(service);
        if (!signature)
            continue;
        const declaredArgs = signature[1] === undefined || signature[1].trim() === "" ? 0 : signature[1].split(",").length;
        const passed = argCount(source, match.index + match[0].length - 1);
        assert.ok(passed <= declaredArgs, "ctx." + match[1] + "." + match[2] + " is called with " + passed + " arguments, the service takes " + declaredArgs);
        checked++;
    }
    assert.ok(checked > 20, "the check must actually inspect calls");
});

test("every English term the catalog uses is a literal in the service, so translation extraction sees it", () => {
    const service = readFileSync(new URL("../Services/ActionCatalogService.qml", import.meta.url), "utf8");
    const terms = catalog.termsOf(build());
    for (const term of terms) {
        // The term may be followed by a translator context argument.
        const literal = "I18n.tr(" + JSON.stringify(term);
        const at = service.indexOf(literal);
        assert.ok(at >= 0 && /[,)]/.test(service[at + literal.length]), "missing I18n.tr literal for " + term);
    }
});
