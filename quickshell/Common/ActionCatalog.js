.pragma library
.import "ActionParams.js" as ActionParams

// Pure catalog of the shell's directly runnable actions. Nothing here reaches
// a service by name: every call goes through the `ctx` object that
// ActionCatalogService builds from the real singletons, so the same code runs
// against fakes in tests. Titles and state words are English terms that the
// service translates through `ctx.tr`.
//
// `text` is what the embedding model reads. Keep every entry in the one shape
// the retrieval measurements rely on: name, what it does, synonyms, the
// situation a user is in ("tired eyes"). `keywords` feed the lexical side and
// mix English and Turkish.

const TOGGLE_STATE = { on: "On", off: "Off" };

// ctx.<key>.<member> uses below, checked against the service sources by a
// test. file "" marks a type that lives in Quickshell itself.
const SERVICE_MEMBERS = {
    theme: { file: "Common/Theme.qml", members: ["isLightMode", "setLightMode", "switchTheme", "currentTheme", "matugenAvailable", "dynamic"] },
    night: { file: "Services/NightModeService.qml", members: ["nightModeEnabled", "gammaControlAvailable", "enableNightMode", "disableNightMode"] },
    sessionData: { file: "Common/SessionData.qml", members: ["doNotDisturb", "setDoNotDisturb"] },
    audio: { file: "Services/AudioService.qml", members: ["sink", "source", "sinkVolumePercent", "sourceVolumePercent", "setVolume", "adjustDefaultSinkVolume", "toggleMute", "setMicVolume", "toggleMicMute"] },
    mpris: { file: "Services/MprisController.qml", members: ["activePlayer", "playPause", "play", "pause", "next", "previousOrRewind"] },
    brightness: { file: "Services/BrightnessService.qml", members: ["brightnessAvailable", "devices", "getPreferredDevices", "getCurrentDeviceInfoByName", "getDeviceBrightness", "brightnessMinimum", "brightnessMaximum", "setGroupBrightness", "setBrightness"] },
    network: { file: "Services/NetworkService.qml", members: ["networkAvailable", "wifiAvailable", "wifiEnabled", "wifiToggling", "toggleWifiRadio", "cellularAvailable", "cellularEnabled", "cellularToggling", "toggleCellularRadio"] },
    bluetooth: { file: "Services/BluetoothService.qml", members: ["available", "enabled", "setBluetoothEnabled", "pairedDevices", "connectDeviceWithTrust"] },
    vpn: { file: "Services/DMSNetworkService.qml", members: ["vpnAvailable", "vpnProfiles", "vpnConnected", "vpnIsBusy", "isActiveVpnUuid", "connectVpn", "disconnectVpn", "disconnectAllVpns", "toggleVpn"] },
    power: { file: "Services/PowerProfileWatcher.qml", members: ["available", "availableProfiles", "currentProfile", "parseProfileSlug", "profileSlug", "applyProfile"] },
    sessionService: { file: "Services/SessionService.qml", members: ["executePowerAction", "isPowerActionSupported", "inhibitorAvailable", "idleInhibited", "enableIdleInhibit", "disableIdleInhibit"] },
    idle: { file: "Services/IdleService.qml", members: ["lockRequested"] },
    popout: { file: "Services/PopoutService.qml", members: ["openPowerMenu"] },
    settings: { file: "Common/SettingsData.qml", members: ["powerActionConfirm"] },
    compositor: { file: "Services/CompositorService.qml", members: ["compositorDetected", "isHyprland", "isNiri", "isMango", "isSway", "isScroll", "isMiracle", "powerOffMonitors", "getFocusedScreenName"] },
    hyprlandService: { file: "Services/HyprlandService.qml", members: ["luaConfigActive", "luaString", "luaValue"] },
    hyprland: { file: "", members: ["dispatch"] },
    niri: { file: "Services/NiriService.qml", members: ["send"] },
    mango: { file: "Services/MangoService.qml", members: ["available", "dispatch"] },
    i3: { file: "", members: ["dispatch"] }
};

function serviceMembers() {
    return SERVICE_MEMBERS;
}

function formatTerm(term, arg) {
    return arg === undefined || arg === null ? term : String(term).replace("%1", arg);
}

function toggle(spec) {
    return Object.assign({
        kind: "toggle",
        params: [],
        keywords: [],
        stateOn: TOGGLE_STATE.on,
        stateOff: TOGGLE_STATE.off,
        invert: false,
        invertWhen: [],
        opposite: [],
        valueImpliesOn: false,
        feedback: "toast",
        available: () => true
    }, spec);
}

function command(spec) {
    return Object.assign({
        kind: "command",
        params: [],
        keywords: [],
        feedback: "toast",
        available: () => true
    }, spec);
}

const OK = { ok: true, message: "" };

function fail(reason, extra) {
    return Object.assign({ ok: false, message: "", reason: reason }, extra || {});
}

function stateOf(ctx, on, spec) {
    return ctx.tr(on ? spec.stateOn : spec.stateOff);
}

// ---- audio -----------------------------------------------------------------

function sinkAudio(ctx) {
    return ctx.audio.sink ? ctx.audio.sink.audio : null;
}

function sourceAudio(ctx) {
    return ctx.audio.source ? ctx.audio.source.audio : null;
}

function percentText(value) {
    return Math.round(value) + "%";
}

// ---- brightness ------------------------------------------------------------

function displayTargets(ctx) {
    if (!ctx.brightness.brightnessAvailable)
        return [];
    return (ctx.brightness.getPreferredDevices() || []).filter(id => {
        const info = id ? ctx.brightness.getCurrentDeviceInfoByName(id) : null;
        return info && info.class !== "leds";
    });
}

function displayMinimum(ctx, id) {
    const info = ctx.brightness.getCurrentDeviceInfoByName(id);
    return info && (info.class === "backlight" || info.class === "ddc") ? 1 : 0;
}

function setDisplayBrightness(ctx, percent) {
    const targets = displayTargets(ctx);
    if (targets.length === 0)
        return fail("unavailable");
    const value = Math.max(displayMinimum(ctx, targets[0]), Math.min(100, percent));
    ctx.brightness.setGroupBrightness(value, targets, false);
    return OK;
}

function stepDisplayBrightness(ctx, step, direction) {
    const targets = displayTargets(ctx);
    if (targets.length === 0)
        return fail("unavailable");
    const info = ctx.brightness.getCurrentDeviceInfoByName(targets[0]);
    const current = ctx.brightness.getDeviceBrightness(targets[0]);
    const next = current + direction * step;
    const low = ctx.brightness.brightnessMinimum(info);
    const high = ctx.brightness.brightnessMaximum(info);
    ctx.brightness.setGroupBrightness(Math.max(low, Math.min(high, next)), targets, false);
    return OK;
}

function ledDevice(ctx, pattern) {
    if (!ctx.brightness.brightnessAvailable)
        return null;
    return (ctx.brightness.devices || []).find(d => d.class === "leds" && pattern.test(String(d.name || "") + " " + String(d.id || ""))) || null;
}

const KEYBOARD_LED = /kbd|keyboard/i;
const FLASH_LED = /flash|torch/i;

function ledToggle(spec, pattern) {
    return toggle(Object.assign({
        valueImpliesOn: true,
        available: ctx => ledDevice(ctx, pattern) !== null,
        get: ctx => {
            const device = ledDevice(ctx, pattern);
            return device !== null && ctx.brightness.getDeviceBrightness(device.id) > 0;
        },
        set: (ctx, on, values) => {
            const device = ledDevice(ctx, pattern);
            if (!device)
                return fail("unavailable");
            ctx.brightness.setBrightness(on ? (values.percent === undefined ? 100 : values.percent) : 0, device.id, false);
            return OK;
        }
    }, spec));
}

// ---- radios ----------------------------------------------------------------

function radios(ctx) {
    const list = [];
    if (ctx.network.networkAvailable && ctx.network.wifiAvailable)
        list.push({
            enabled: () => ctx.network.wifiEnabled,
            toggle: () => ctx.network.toggleWifiRadio(),
            busy: () => ctx.network.wifiToggling
        });
    if (ctx.network.networkAvailable && ctx.network.cellularAvailable)
        list.push({
            enabled: () => ctx.network.cellularEnabled,
            toggle: () => ctx.network.toggleCellularRadio(),
            busy: () => ctx.network.cellularToggling
        });
    if (ctx.bluetooth.available)
        list.push({
            enabled: () => ctx.bluetooth.enabled,
            toggle: () => ctx.bluetooth.setBluetoothEnabled(!ctx.bluetooth.enabled),
            busy: () => false
        });
    return list;
}

// ---- power -----------------------------------------------------------------

function powerAction(ctx, action) {
    // A held-to-confirm power menu is the user's own guard against a stray Enter.
    if (ctx.settings.powerActionConfirm) {
        ctx.popout.openPowerMenu();
        return OK;
    }
    return ctx.sessionService.executePowerAction(action) ? OK : fail("failed");
}

function powerProfile(slug, title, text, keywords, icon) {
    return command({
        id: "power.profile." + slug,
        title: title,
        text: text,
        keywords: keywords,
        icon: icon,
        category: "power",
        feedback: "osd",
        available: ctx => ctx.power.available && ctx.power.availableProfiles.indexOf(ctx.power.parseProfileSlug(slug)) !== -1,
        state: ctx => ctx.power.profileSlug(ctx.power.currentProfile) === slug ? ctx.tr("Active") : "",
        run: ctx => ctx.power.applyProfile(ctx.power.parseProfileSlug(slug)) ? OK : fail("failed")
    });
}

// ---- windows ---------------------------------------------------------------

function windowBackend(ctx) {
    if (ctx.compositor.isHyprland)
        return ctx.hyprlandService.luaConfigActive ? "hyprland" : "";
    if (ctx.compositor.isNiri)
        return "niri";
    if (ctx.compositor.isMango)
        return ctx.mango.available ? "mango" : "";
    if (ctx.compositor.isSway || ctx.compositor.isScroll || ctx.compositor.isMiracle)
        return "i3";
    return "";
}

function otherScreen(ctx) {
    const names = ctx.screenNames();
    if (names.length < 2)
        return "";
    const index = names.indexOf(ctx.compositor.getFocusedScreenName());
    return names[(index + 1) % names.length];
}

function windowAction(spec, perBackend) {
    return command(Object.assign({
        category: "window",
        available: ctx => perBackend[windowBackend(ctx)] !== undefined,
        run: (ctx, values) => {
            const backend = windowBackend(ctx);
            const send = perBackend[backend];
            if (!send)
                return fail("unavailable");
            return send(ctx, values) === false ? fail("failed") : OK;
        }
    }, spec));
}

const NIRI_ACTION = (name, args) => ctx => ctx.niri.send({ Action: { [name]: args } });

const WINDOW_BACKENDS = {
    close: {
        hyprland: ctx => ctx.hyprland.dispatch("hl.dsp.window.close()"),
        niri: NIRI_ACTION("CloseWindow", { id: null }),
        mango: ctx => ctx.mango.dispatch("killclient"),
        i3: ctx => ctx.i3.dispatch("kill")
    },
    fullscreen: {
        hyprland: ctx => ctx.hyprland.dispatch("hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })"),
        niri: NIRI_ACTION("FullscreenWindow", { id: null }),
        mango: ctx => ctx.mango.dispatch("togglefullscreen"),
        i3: ctx => ctx.i3.dispatch("fullscreen toggle")
    },
    float: {
        hyprland: ctx => ctx.hyprland.dispatch("hl.dsp.window.float({ action = \"toggle\" })"),
        niri: NIRI_ACTION("ToggleWindowFloating", { id: null }),
        mango: ctx => ctx.mango.dispatch("togglefloating"),
        i3: ctx => ctx.i3.dispatch("floating toggle")
    },
    workspace: {
        hyprland: (ctx, values) => ctx.hyprland.dispatch("hl.dsp.window.move({ workspace = " + (values.workspace === undefined ? "\"+1\"" : ctx.hyprlandService.luaValue(values.workspace)) + ", follow = true })"),
        niri: (ctx, values) => values.workspace === undefined ? ctx.niri.send({ Action: { MoveWindowToWorkspaceDown: { focus: true } } }) : ctx.niri.send({ Action: { MoveWindowToWorkspace: { window_id: null, reference: { Index: values.workspace }, focus: true } } }),
        mango: (ctx, values) => ctx.mango.dispatch(values.workspace === undefined ? "tagtoright" : "tag," + values.workspace),
        i3: (ctx, values) => ctx.i3.dispatch(values.workspace === undefined ? "move container to workspace next" : "move container to workspace number " + values.workspace)
    },
    screen: {
        hyprland: ctx => {
            const target = otherScreen(ctx);
            return target === "" ? false : ctx.hyprland.dispatch("hl.dsp.window.move({ monitor = " + ctx.hyprlandService.luaString(target) + ", follow = true })");
        },
        niri: ctx => {
            const target = otherScreen(ctx);
            return target === "" ? false : ctx.niri.send({ Action: { MoveWindowToMonitor: { id: null, output: target } } });
        },
        i3: ctx => {
            const target = otherScreen(ctx);
            return target === "" ? false : ctx.i3.dispatch("move container to output \"" + target.replace(/["\\]/g, "\\$&") + "\"");
        }
    }
};

function screenshot(mode, title, text, keywords, icon) {
    return command({
        id: "screenshot." + mode,
        title: title,
        text: text,
        keywords: keywords,
        icon: icon,
        category: "screenshot",
        feedback: "osd",
        run: ctx => {
            ctx.exec(["dms", "screenshot", mode]);
            return OK;
        }
    });
}

function mediaCommand(id, title, text, keywords, icon, act) {
    return command({
        id: "media." + id,
        title: title,
        text: text,
        keywords: keywords,
        icon: icon,
        category: "media",
        feedback: "osd",
        available: ctx => !!ctx.mpris.activePlayer,
        run: ctx => {
            act(ctx);
            return OK;
        }
    });
}

// ---- the static catalog ----------------------------------------------------

function staticDefs() {
    return [
        toggle({
            id: "theme.dark",
            title: "Dark mode",
            text: "Dark mode. Switch the desktop between the dark theme and the light theme; night theme, black interface, light interface, bright or dim colors, easier on the eyes in the dark.",
            keywords: ["dark", "dark mode", "light mode", "theme", "night theme", "karanlık", "koyu", "aydınlık", "açık tema", "tema"],
            icon: "dark_mode",
            category: "appearance",
            opposite: ["aydinlik", "light"],
            get: ctx => !ctx.theme.isLightMode,
            set: (ctx, on) => {
                ctx.theme.setLightMode(!on, true, true);
                return OK;
            }
        }),
        toggle({
            id: "display.nightlight",
            title: "Night mode",
            text: "Night light. Reduce blue light with warm, yellowish screen colors that lessen eye strain; tired eyes, my eyes hurt, reading at night, sleep better, eye comfort, sunset mode.",
            keywords: ["night light", "night mode", "blue light", "warm", "eye strain", "gece ışığı", "gece modu", "mavi ışık", "göz yorgunluğu", "gözlerim yoruldu"],
            icon: "nightlight",
            category: "display",
            available: ctx => ctx.night.gammaControlAvailable,
            get: ctx => ctx.night.nightModeEnabled,
            set: (ctx, on) => {
                if (on)
                    ctx.night.enableNightMode();
                else
                    ctx.night.disableNightMode();
                return OK;
            }
        }),
        toggle({
            id: "notifications.dnd",
            title: "Do not disturb",
            text: "Do not disturb. Silence and hide notification popups and alerts, optionally for a set time; focus mode, quiet mode, I am in a meeting, presenting, concentrating, stop interruptions. Say a duration such as 30 minutes.",
            keywords: ["do not disturb", "dnd", "notifications", "silence", "focus", "rahatsız etme", "rahatsız etmeyin", "bildirim", "bildirimleri sustur", "odak"],
            icon: "notifications_off",
            category: "notifications",
            invertWhen: ["bildirim", "notif"],
            valueImpliesOn: true,
            params: [{ name: "duration", type: "duration", unit: "minutes", min: 1, max: 10080 }],
            get: ctx => ctx.sessionData.doNotDisturb,
            set: (ctx, on, values) => {
                ctx.sessionData.setDoNotDisturb(on, values.duration || 0);
                return OK;
            }
        }),

        command({
            id: "audio.volume.set",
            title: "Volume",
            text: "Set volume. Set the speaker sound level to an exact value or percentage; volume 50 percent, audio level, make the sound exactly this loud.",
            keywords: ["volume", "sound", "speaker", "audio", "ses", "ses seviyesi", "sesi ayarla", "sesi yap"],
            icon: "volume_up",
            category: "audio",
            feedback: "osd",
            params: [{ name: "percent", type: "percent", min: 0, max: 100, required: true, example: "40%" }],
            available: ctx => !!sinkAudio(ctx),
            state: ctx => sinkAudio(ctx) ? (sinkAudio(ctx).muted ? ctx.tr("Muted") : percentText(ctx.audio.sinkVolumePercent)) : "",
            run: (ctx, values) => {
                ctx.audio.setVolume(values.percent);
                return OK;
            }
        }),
        command({
            id: "audio.volume.up",
            title: "Volume up",
            text: "Volume up. Make the speaker louder; raise or increase the sound, too quiet, cannot hear it.",
            keywords: ["volume up", "louder", "increase volume", "raise volume", "sesi aç", "sesi arttır", "sesi artır", "yükselt", "daha yüksek"],
            icon: "volume_up",
            category: "audio",
            feedback: "osd",
            params: [{ name: "step", type: "int", min: 1, max: 100 }],
            available: ctx => !!sinkAudio(ctx),
            state: ctx => sinkAudio(ctx) ? percentText(ctx.audio.sinkVolumePercent) : "",
            run: (ctx, values) => {
                ctx.audio.adjustDefaultSinkVolume(values.step === undefined ? 5 : values.step, 1);
                return OK;
            }
        }),
        command({
            id: "audio.volume.down",
            title: "Volume down",
            text: "Volume down. Turn the volume down and make the speaker quieter; lower, reduce or decrease the sound, quiet down, it is too loud, hurts the ears.",
            keywords: ["volume down", "quieter", "decrease volume", "lower volume", "sesi kıs", "sesi azalt", "alçalt", "daha düşük"],
            icon: "volume_down",
            category: "audio",
            feedback: "osd",
            params: [{ name: "step", type: "int", min: 1, max: 100 }],
            available: ctx => !!sinkAudio(ctx),
            state: ctx => sinkAudio(ctx) ? percentText(ctx.audio.sinkVolumePercent) : "",
            run: (ctx, values) => {
                ctx.audio.adjustDefaultSinkVolume(values.step === undefined ? 5 : values.step, -1);
                return OK;
            }
        }),
        toggle({
            id: "audio.mute",
            title: "Mute",
            text: "Mute sound. Put the speaker output on silent or bring the sound back; mute audio, silent mode, sound off, no sound at all, unmute.",
            keywords: ["mute", "unmute", "silence", "sound off", "sessiz", "sustur", "sesi kapat", "sesi sustur"],
            icon: "volume_off",
            category: "audio",
            invert: true,
            stateOn: "Muted",
            stateOff: "Unmuted",
            feedback: "osd",
            available: ctx => !!sinkAudio(ctx),
            get: ctx => !!(sinkAudio(ctx) && sinkAudio(ctx).muted),
            set: ctx => {
                ctx.audio.toggleMute();
                return OK;
            }
        }),
        toggle({
            id: "audio.mic.mute",
            title: "Microphone mute",
            text: "Microphone mute. Mute or unmute the microphone input during a call; nobody can hear me, mic off, mic on, stop others hearing me.",
            keywords: ["microphone", "mic", "mute mic", "mikrofon", "mikrofonu kapat", "mikrofonu sustur", "mikrofonu aç"],
            icon: "mic_off",
            category: "audio",
            invert: true,
            stateOn: "Muted",
            stateOff: "Unmuted",
            feedback: "osd",
            available: ctx => !!sourceAudio(ctx),
            get: ctx => !!(sourceAudio(ctx) && sourceAudio(ctx).muted),
            set: ctx => {
                ctx.audio.toggleMicMute();
                return OK;
            }
        }),
        command({
            id: "audio.mic.volume",
            title: "Microphone volume",
            text: "Microphone volume. Set the microphone input level to a percentage; mic too quiet or too loud, input gain, recording level.",
            keywords: ["microphone volume", "mic level", "input volume", "mikrofon sesi", "mikrofon seviyesi"],
            icon: "mic",
            category: "audio",
            feedback: "osd",
            params: [{ name: "percent", type: "percent", min: 0, max: 100, required: true, example: "60%" }],
            available: ctx => !!sourceAudio(ctx),
            state: ctx => sourceAudio(ctx) ? percentText(ctx.audio.sourceVolumePercent) : "",
            run: (ctx, values) => {
                ctx.audio.setMicVolume(values.percent);
                return OK;
            }
        }),

        command({
            id: "media.playpause",
            title: "Play/Pause",
            text: "Play or pause media. Start or stop the music or video that is playing; resume, toggle playback, continue the song, play pause.",
            keywords: ["play", "pause", "music", "media", "song", "çal", "oynat", "duraklat", "müzik", "devam"],
            icon: "play_pause",
            category: "media",
            feedback: "osd",
            available: ctx => !!ctx.mpris.activePlayer,
            state: ctx => ctx.mpris.activePlayer ? ctx.tr(ctx.mpris.activePlayer.isPlaying ? "Playing" : "Paused") : "",
            run: ctx => {
                ctx.mpris.playPause();
                return OK;
            }
        }),
        mediaCommand("play", "Play", "Play. Start or resume the music or video player; continue the song, press play, unpause.", ["play", "resume", "continue", "çal", "oynat", "devam et"], "play_arrow", ctx => ctx.mpris.play()),
        mediaCommand("pause", "Pause", "Pause. Pause the music or video that is playing; stop the song for now, hold playback, silence the player.", ["pause", "hold", "duraklat", "beklet", "müziği durdur"], "pause", ctx => ctx.mpris.pause()),
        mediaCommand("next", "Next", "Next track. Skip to the next song, episode or video; skip this one, play something else, forward.", ["next", "skip", "next song", "sonraki", "sonraki şarkı", "geç", "atla"], "skip_next", ctx => ctx.mpris.next()),
        mediaCommand("previous", "Previous", "Previous track. Go back to the previous song or restart the current one; play the last song again, rewind, back.", ["previous", "back", "last song", "önceki", "önceki şarkı", "geri"], "skip_previous", ctx => ctx.mpris.previousOrRewind()),

        command({
            id: "display.brightness.set",
            title: "Brightness",
            text: "Display brightness level. Set the screen backlight to an exact value or percentage such as 40 percent.",
            keywords: ["brightness", "screen", "backlight", "parlaklık", "ekran parlaklığı", "parlaklığı ayarla"],
            icon: "brightness_6",
            category: "display",
            feedback: "osd",
            params: [{ name: "percent", type: "percent", min: 0, max: 100, required: true, example: "40%" }],
            available: ctx => displayTargets(ctx).length > 0,
            state: ctx => {
                const targets = displayTargets(ctx);
                return targets.length > 0 ? percentText(ctx.brightness.getDeviceBrightness(targets[0])) : "";
            },
            run: (ctx, values) => setDisplayBrightness(ctx, values.percent)
        }),
        command({
            id: "display.brightness.up",
            title: "Brightness up",
            text: "Brightness up. Increase the screen brightness so the display is brighter; the screen is too dark or dim, hard to see, raise the backlight.",
            keywords: ["brighter", "increase brightness", "brightness up", "parlaklığı arttır", "parlaklığı artır", "daha parlak", "ekran karanlık"],
            icon: "brightness_high",
            category: "display",
            feedback: "osd",
            params: [{ name: "step", type: "int", min: 1, max: 100 }],
            available: ctx => displayTargets(ctx).length > 0,
            run: (ctx, values) => stepDisplayBrightness(ctx, values.step === undefined ? 10 : values.step, 1)
        }),
        command({
            id: "display.brightness.down",
            title: "Brightness down",
            text: "Brightness down. Decrease the screen brightness so the display is dimmer; the screen is too bright, glare, dazzling in a dark room, lower the backlight.",
            keywords: ["dimmer", "decrease brightness", "brightness down", "parlaklığı azalt", "parlaklığı kıs", "daha loş", "ekran çok parlak"],
            icon: "brightness_low",
            category: "display",
            feedback: "osd",
            params: [{ name: "step", type: "int", min: 1, max: 100 }],
            available: ctx => displayTargets(ctx).length > 0,
            run: (ctx, values) => stepDisplayBrightness(ctx, values.step === undefined ? 10 : values.step, -1)
        }),
        ledToggle({
            id: "keyboard.backlight",
            title: "Keyboard backlight",
            text: "Keyboard backlight. Turn the keyboard illumination on or off or set its level; backlit keys, typing in the dark, key lights.",
            keywords: ["keyboard light", "keyboard backlight", "backlit", "klavye ışığı", "klavye aydınlatması", "klavye"],
            icon: "keyboard",
            category: "display",
            feedback: "osd",
            params: [{ name: "percent", type: "percent", min: 0, max: 100 }]
        }, KEYBOARD_LED),
        ledToggle({
            id: "light.flashlight",
            title: "Flashlight",
            text: "Flashlight. Turn the device flashlight or torch LED on or off; flash light, torch, lamp, light up the dark.",
            keywords: ["flashlight", "torch", "lamp", "flash", "fener", "el feneri", "ışık", "lamba"],
            icon: "flashlight_on",
            category: "light"
        }, FLASH_LED),

        toggle({
            id: "network.wifi",
            title: "Wi-Fi",
            text: "Wi-Fi. Turn the wireless network adapter on or off; wifi, wireless internet, turn the internet off, go offline, no internet connection, connect to the network.",
            keywords: ["wifi", "wi-fi", "wireless", "internet", "network", "kablosuz", "ağ", "internet kapat", "wifi aç"],
            icon: "wifi",
            category: "network",
            feedback: "service",
            available: ctx => ctx.network.networkAvailable && ctx.network.wifiAvailable,
            get: ctx => ctx.network.wifiEnabled,
            set: ctx => {
                if (ctx.network.wifiToggling)
                    return fail("busy");
                ctx.network.toggleWifiRadio();
                return OK;
            }
        }),
        toggle({
            id: "bluetooth.power",
            title: "Bluetooth",
            text: "Bluetooth. Turn the Bluetooth radio on or off; wireless devices, pairing, wireless headphones, earbuds, speakers, mouse, keyboard.",
            keywords: ["bluetooth", "wireless headphones", "pairing", "kablosuz kulaklık", "mavi diş", "eşleştir"],
            icon: "bluetooth",
            category: "network",
            available: ctx => ctx.bluetooth.available,
            get: ctx => ctx.bluetooth.enabled,
            set: (ctx, on) => {
                ctx.bluetooth.setBluetoothEnabled(on);
                return OK;
            }
        }),
        toggle({
            id: "network.airplane",
            title: "Airplane mode",
            text: "Airplane mode. Disable all wireless radios at once or bring them back; flight mode, offline, no radio, Wi-Fi and Bluetooth off, on a plane.",
            keywords: ["airplane", "flight mode", "offline", "radio", "uçak modu", "uçak", "çevrimdışı"],
            icon: "airplanemode_active",
            category: "network",
            feedback: "toast",
            available: ctx => radios(ctx).length > 0,
            get: ctx => {
                const list = radios(ctx);
                return list.length > 0 && list.every(radio => !radio.enabled());
            },
            set: (ctx, on) => {
                const list = radios(ctx);
                if (list.some(radio => radio.busy()))
                    return fail("busy");
                for (const radio of list) {
                    if (radio.enabled() === on)
                        radio.toggle();
                }
                return OK;
            }
        }),
        toggle({
            id: "network.vpn",
            title: "VPN",
            text: "VPN. Connect or disconnect the virtual private network; secure tunnel, private connection, hide my IP address, privacy, reach the work network.",
            keywords: ["vpn", "tunnel", "private network", "privacy", "sanal özel ağ", "vpn bağlan", "vpn kapat"],
            icon: "vpn_lock",
            category: "network",
            available: ctx => ctx.vpn.vpnAvailable && ((ctx.vpn.vpnProfiles || []).length > 0 || ctx.vpn.vpnConnected),
            get: ctx => ctx.vpn.vpnConnected,
            set: (ctx, on) => {
                if (ctx.vpn.vpnIsBusy)
                    return fail("busy");
                if (on)
                    ctx.vpn.toggleVpn("");
                else
                    ctx.vpn.disconnectAllVpns();
                return OK;
            }
        }),

        powerProfile("power-saver", "Power Saver", "Power saver profile. Reduce performance to extend the battery life; save battery, the battery is low or running out, low power, battery saving mode, cooler and quieter.", ["power saver", "battery saver", "save battery", "pil tasarrufu", "güç tasarrufu", "pil"], "battery_saver"),
        powerProfile("balanced", "Balanced", "Balanced power profile. Balance performance and energy use; default, normal, everyday use, back to standard power mode.", ["balanced", "default power", "normal", "dengeli", "güç profili"], "balance"),
        powerProfile("performance", "Performance", "Performance power profile. Run the processor and graphics at full speed; maximum power, fast, gaming, heavy work, boost the computer.", ["performance", "fast", "gaming", "boost", "performans", "yüksek performans", "hızlı"], "speed"),

        command({
            id: "session.lock",
            title: "Lock screen",
            text: "Lock screen. Lock the session so a password is needed to continue; secure the computer, step away, leaving the desk, privacy.",
            keywords: ["lock", "lock screen", "secure", "kilitle", "ekranı kilitle", "kilit"],
            icon: "lock",
            category: "session",
            feedback: "osd",
            run: ctx => {
                ctx.idle.lockRequested();
                return OK;
            }
        }),
        command({
            id: "session.suspend",
            title: "Suspend",
            text: "Suspend. Put the computer to sleep to save power and wake it later; sleep the computer, put it to sleep, sleep mode, standby, like closing the laptop lid.",
            keywords: ["suspend", "sleep", "standby", "uyut", "uyku", "bilgisayarı uyut", "uyku modu"],
            icon: "bedtime",
            category: "session",
            feedback: "osd",
            available: ctx => ctx.sessionService.isPowerActionSupported("suspend"),
            run: ctx => powerAction(ctx, "suspend")
        }),
        command({
            id: "session.hibernate",
            title: "Hibernate",
            text: "Hibernate. Save the session to disk and power off completely; deep sleep, resume later, suspend to disk, keep my work and turn off.",
            keywords: ["hibernate", "deep sleep", "hazırda beklet", "hazırda bekletme"],
            icon: "mode_standby",
            category: "session",
            feedback: "osd",
            available: ctx => ctx.sessionService.isPowerActionSupported("hibernate"),
            run: ctx => powerAction(ctx, "hibernate")
        }),
        command({
            id: "session.reboot",
            title: "Reboot",
            text: "Restart computer. Reboot the machine; restart the system, the computer is stuck or slow, apply updates, start fresh.",
            keywords: ["restart", "reboot", "yeniden başlat", "bilgisayarı yeniden başlat", "reset"],
            icon: "restart_alt",
            category: "session",
            feedback: "osd",
            available: ctx => ctx.sessionService.isPowerActionSupported("reboot"),
            run: ctx => powerAction(ctx, "reboot")
        }),
        command({
            id: "session.poweroff",
            title: "Power off",
            text: "Shut down computer. Turn the computer off completely; power off, switch off, finish for the day, go to bed.",
            keywords: ["shutdown", "shut down", "power off", "turn off computer", "kapat", "bilgisayarı kapat", "kapanış"],
            icon: "power_settings_new",
            category: "session",
            feedback: "osd",
            available: ctx => ctx.sessionService.isPowerActionSupported("poweroff"),
            run: ctx => powerAction(ctx, "poweroff")
        }),
        command({
            id: "session.logout",
            title: "Log out",
            text: "Log out. Close your user session and return to the login screen; sign out of the account, end the session, switch user, exit the desktop.",
            keywords: ["log out", "logout", "sign out", "oturumu kapat", "çıkış", "çıkış yap"],
            icon: "logout",
            category: "session",
            feedback: "osd",
            available: ctx => ctx.sessionService.isPowerActionSupported("logout"),
            run: ctx => powerAction(ctx, "logout")
        }),
        command({
            id: "display.off",
            title: "Turn off displays",
            text: "Turn off displays. Switch the monitors off while the session keeps running; screen off, black screen, display sleep, monitor off, save power.",
            keywords: ["screen off", "monitor off", "display off", "ekranı kapat", "ekranı söndür", "monitör"],
            icon: "desktop_access_disabled",
            category: "display",
            feedback: "osd",
            available: ctx => ctx.compositor.compositorDetected,
            run: ctx => {
                ctx.compositor.powerOffMonitors();
                return OK;
            }
        }),
        toggle({
            id: "session.keepawake",
            title: "Keep Awake",
            text: "Keep awake. Prevent the screen from dimming or locking and the computer from going idle, optionally for a set time; caffeine mode, stay on, I am watching a movie, giving a presentation.",
            keywords: ["keep awake", "caffeine", "prevent sleep", "stay awake", "idle inhibit", "uyanık tut", "uyku engelle", "ekran kapanmasın"],
            icon: "coffee",
            category: "session",
            valueImpliesOn: true,
            params: [{ name: "duration", type: "duration", unit: "minutes", min: 1, max: 10080 }],
            available: ctx => ctx.sessionService.inhibitorAvailable,
            get: ctx => ctx.sessionService.idleInhibited,
            set: (ctx, on, values) => {
                if (on)
                    ctx.sessionService.enableIdleInhibit(values.duration || 0);
                else
                    ctx.sessionService.disableIdleInhibit();
                return OK;
            }
        }),

        windowAction({
            id: "window.close",
            title: "Close Window",
            text: "Close window. Close the focused application window; quit this app window, shut the window, get rid of it.",
            keywords: ["close window", "close", "quit", "kill window", "pencereyi kapat", "pencere kapat", "kapat"],
            icon: "close",
            feedback: "osd"
        }, WINDOW_BACKENDS.close),
        windowAction({
            id: "window.fullscreen",
            title: "Fullscreen",
            text: "Fullscreen. Make the focused window fill the whole screen or leave fullscreen; maximize, full screen toggle, cover the screen, video in full screen.",
            keywords: ["fullscreen", "full screen", "maximize", "tam ekran", "pencereyi tam ekran yap", "büyüt"],
            icon: "fullscreen",
            feedback: "osd"
        }, WINDOW_BACKENDS.fullscreen),
        windowAction({
            id: "window.float",
            title: "Floating",
            text: "Floating window. Make the focused window float above the tiled layout or tile it again; unsnap, free-moving window, pop out, detach from tiling.",
            keywords: ["floating", "float", "tile", "untile", "yüzen pencere", "yüzer", "yüzen"],
            icon: "picture_in_picture_alt",
            feedback: "osd"
        }, WINDOW_BACKENDS.float),
        windowAction({
            id: "window.move-workspace",
            title: "Move window to workspace",
            text: "Move window to workspace. Send the focused window to another workspace, optionally a numbered one; move to desktop 2, send to the next workspace, relocate the window.",
            keywords: ["move window", "send to workspace", "workspace", "çalışma alanı", "pencereyi taşı", "başka çalışma alanına taşı", "masaüstü"],
            icon: "drive_file_move",
            feedback: "osd",
            params: [{ name: "workspace", type: "int", min: 1, max: 99, example: "2" }]
        }, WINDOW_BACKENDS.workspace),
        windowAction({
            id: "window.move-screen",
            title: "Move window to monitor",
            text: "Move window to another monitor. Send the focused application window to the next screen; second display, other screen, external monitor, multi-monitor setup.",
            keywords: ["move to monitor", "other screen", "second display", "external monitor", "başka ekrana taşı", "yan ekrana taşı", "ikinci ekran", "monitör"],
            icon: "monitor",
            feedback: "osd",
            available: ctx => ctx.screenNames().length > 1 && windowBackend(ctx) !== "" && WINDOW_BACKENDS.screen[windowBackend(ctx)] !== undefined
        }, WINDOW_BACKENDS.screen),

        screenshot("region", "Screenshot: Region", "Screenshot of a region. Select an area of the screen and capture it as an image; snip, crop a screenshot, capture part of the screen, screen grab.", ["screenshot", "region", "snip", "crop", "ekran görüntüsü", "bölge", "alan seç"], "screenshot_region"),
        screenshot("full", "Screenshot: Screen", "Screenshot of the screen. Capture the focused monitor as an image; take a picture of the whole screen, print screen, save what is on the display.", ["screenshot", "full screen", "print screen", "ekran görüntüsü al", "tam ekran görüntüsü"], "screenshot_monitor"),
        screenshot("window", "Screenshot: Window", "Screenshot of a window. Capture only the focused window as an image; window capture, save this app as a picture.", ["screenshot window", "window capture", "pencere görüntüsü", "pencerenin ekran görüntüsü"], "screenshot"),
        screenshot("all", "Screenshot: All screens", "Screenshot of all screens. Capture every monitor combined into one image; all displays, multi-monitor screenshot.", ["screenshot all", "all monitors", "tüm ekranlar", "tüm ekranların görüntüsü"], "devices"),
        screenshot("scroll", "Screenshot: Scrolling", "Scrolling screenshot. Capture a scrolling region stitched into one tall image; long screenshot, whole web page, scroll capture, chat history.", ["scrolling screenshot", "long screenshot", "scroll capture", "kaydırmalı ekran görüntüsü", "uzun ekran görüntüsü"], "swap_vert")
    ];
}

// ---- dynamic families ------------------------------------------------------

const BLUETOOTH_ICON_WORDS = {
    headset: "headphones, headset, earbuds, wireless audio",
    headphones: "headphones, headset, earbuds, wireless audio",
    speaker: "speaker, wireless audio, music",
    mouse: "mouse, pointer",
    keyboard: "keyboard, typing",
    gamepad: "game controller, gamepad, joystick",
    phone: "phone, smartphone",
    smartphone: "phone, smartphone",
    watch: "smart watch",
    tv: "television, screen",
    print: "printer"
};

function themeDefs(themes) {
    return (themes || []).map(theme => command({
        id: "theme.scheme." + theme.name,
        title: "Color scheme: %1",
        titleArg: theme.label,
        titleArgTranslated: true,
        text: "Color scheme " + theme.label + ". Change the accent color palette of the whole desktop to " + theme.label + "; theme color, accent color, palette, tint, make the interface " + String(theme.label).toLowerCase() + ".",
        keywords: [String(theme.label).toLowerCase(), "color scheme", "accent color", "theme color", "palette", "renk", "renk şeması", "tema rengi"],
        icon: "palette",
        category: "appearance",
        feedback: "toast",
        state: ctx => ctx.theme.currentTheme === theme.name ? ctx.tr("Active") : "",
        run: ctx => {
            ctx.theme.switchTheme(theme.name);
            return OK;
        }
    })).concat([command({
            id: "theme.scheme.dynamic",
            title: "Color scheme: %1",
            titleArg: "Dynamic",
            titleArgTranslated: true,
            text: "Dynamic colors. Generate the desktop colors from the current wallpaper; wallpaper colors, material you, matugen, automatic palette that follows the background picture.",
            keywords: ["dynamic colors", "wallpaper colors", "material you", "matugen", "dinamik", "duvar kağıdı renkleri", "renk şeması"],
            icon: "wallpaper",
            category: "appearance",
            feedback: "toast",
            available: ctx => ctx.theme.matugenAvailable,
            state: ctx => ctx.theme.currentTheme === ctx.theme.dynamic ? ctx.tr("Active") : "",
            run: ctx => {
                ctx.theme.switchTheme(ctx.theme.dynamic);
                return OK;
            }
        })]);
}

function findBluetoothDevice(ctx, address) {
    return (ctx.bluetooth.pairedDevices || []).find(d => String(d.address || "").toUpperCase() === address) || null;
}

function bluetoothDefs(devices) {
    return (devices || []).filter(d => d && d.address).map(device => {
        const address = String(device.address).toUpperCase();
        const kind = BLUETOOTH_ICON_WORDS[device.icon] || "wireless device";
        return toggle({
            id: "bluetooth.device:" + address,
            title: "Bluetooth: %1",
            titleArg: device.name || address,
            text: "Connect " + (device.name || address) + ". Connect to or disconnect from the paired Bluetooth device " + (device.name || address) + " (" + kind + "); wireless connection, pair again, use my " + (device.name || "device") + ".",
            keywords: [String(device.name || address).toLowerCase(), "bluetooth", "connect", "kulaklık", "bağlan", "bağla"],
            icon: device.icon || "bluetooth_connected",
            category: "bluetooth",
            stateOn: "Connected",
            stateOff: "Disconnected",
            available: ctx => ctx.bluetooth.available && ctx.bluetooth.enabled && findBluetoothDevice(ctx, address) !== null,
            get: ctx => {
                const found = findBluetoothDevice(ctx, address);
                return found !== null && found.connected === true;
            },
            set: (ctx, on) => {
                const found = findBluetoothDevice(ctx, address);
                if (!found)
                    return fail("unavailable");
                if (on)
                    ctx.bluetooth.connectDeviceWithTrust(found);
                else
                    found.disconnect();
                return OK;
            }
        });
    });
}

function vpnDefs(profiles) {
    return (profiles || []).filter(p => p && p.uuid && !p.transient).map(profile => toggle({
        id: "network.vpn:" + profile.uuid,
        title: "VPN: %1",
        titleArg: profile.name || profile.uuid,
        text: "VPN connection " + (profile.name || profile.uuid) + ". Connect or disconnect the VPN connection named " + (profile.name || profile.uuid) + "; secure tunnel, private connection, hide my IP address, reach that network.",
        keywords: [String(profile.name || profile.uuid).toLowerCase(), "vpn", "tunnel", "bağlan", "sanal özel ağ"],
        icon: "vpn_key",
        category: "network",
        stateOn: "Connected",
        stateOff: "Disconnected",
        available: ctx => ctx.vpn.vpnAvailable,
        get: ctx => ctx.vpn.isActiveVpnUuid(profile.uuid),
        set: (ctx, on) => {
            if (ctx.vpn.vpnIsBusy)
                return fail("busy");
            if (on)
                ctx.vpn.connectVpn(profile.uuid);
            else
                ctx.vpn.disconnectVpn(profile.uuid);
            return OK;
        }
    }));
}

// ---- plugin actions --------------------------------------------------------

const PLUGIN_PARAM_TYPES = { percent: true, int: true, duration: true };
const PLUGIN_ID = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;

function validateParams(params) {
    if (params === undefined || params === null)
        return "";
    if (!Array.isArray(params))
        return "params must be an array";
    for (const spec of params) {
        if (!spec || typeof spec.name !== "string" || spec.name === "")
            return "every param needs a name";
        if (!PLUGIN_PARAM_TYPES[spec.type])
            return "param " + spec.name + ": type must be percent, int or duration";
        for (const bound of ["min", "max"]) {
            if (spec[bound] !== undefined && typeof spec[bound] !== "number")
                return "param " + spec.name + ": " + bound + " must be a number";
        }
        if (spec.type === "duration" && spec.unit !== undefined && !(spec.unit === "seconds" || spec.unit === "minutes" || spec.unit === "hours"))
            return "param " + spec.name + ": unit must be seconds, minutes or hours";
    }
    return "";
}

// Returns an error string, or "" when the plugin action is well formed.
function validatePluginAction(action) {
    if (!action || typeof action !== "object")
        return "action must be an object";
    if (typeof action.id !== "string" || !PLUGIN_ID.test(action.id))
        return "id must be a non-empty string of letters, digits, '.', '_' or '-'";
    if (typeof action.title !== "string" || action.title.trim() === "")
        return "title is required";
    if (typeof action.text !== "string" || action.text.trim() === "")
        return "text is required";
    if (typeof action.run !== "function")
        return "run must be a function";
    if (action.keywords !== undefined && !Array.isArray(action.keywords))
        return "keywords must be an array of strings";
    return validateParams(action.params);
}

// Builds the defs of one plugin. Invalid actions are reported, not thrown, so
// one bad entry does not take the plugin's other actions down.
function pluginDefs(pluginId, actions) {
    const defs = [];
    const errors = [];
    const seen = {};
    if (!PLUGIN_ID.test(String(pluginId)))
        return { defs: defs, errors: ["plugin id is not valid: " + pluginId] };
    for (const action of actions || []) {
        const problem = validatePluginAction(action);
        if (problem !== "") {
            errors.push((action && action.id ? action.id : "?") + ": " + problem);
            continue;
        }
        if (seen[action.id]) {
            errors.push(action.id + ": duplicate id");
            continue;
        }
        seen[action.id] = true;
        const call = (value, ctx, fallback) => {
            try {
                return typeof value === "function" ? value(ctx) : (value === undefined ? fallback : value);
            } catch (error) {
                return fallback;
            }
        };
        defs.push(command({
            id: "plugin:" + pluginId + ":" + action.id,
            pluginId: pluginId,
            title: action.title.trim(),
            literalTitle: true,
            text: action.text.trim(),
            keywords: (action.keywords || []).filter(k => typeof k === "string" && k !== ""),
            icon: typeof action.icon === "string" && action.icon !== "" ? action.icon : "extension",
            category: "plugin",
            params: (action.params || []).map(spec => Object.assign({}, spec)),
            available: ctx => call(action.available, ctx, true) !== false,
            state: ctx => String(call(action.state, ctx, "") || ""),
            run: (ctx, values, query) => {
                const result = action.run(values, query);
                return result === false ? fail("failed") : OK;
            }
        }));
    }
    return { defs: defs, errors: errors };
}

// ---- assembling and running ------------------------------------------------

function buildDefs(input) {
    const source = input || {};
    return staticDefs().concat(themeDefs(source.themes), bluetoothDefs(source.bluetoothDevices), vpnDefs(source.vpnProfiles), source.pluginDefs || []);
}

function titleOf(def, tr) {
    if (def.literalTitle)
        return def.title;
    const arg = def.titleArg === undefined ? undefined : (def.titleArgTranslated ? tr(def.titleArg) : def.titleArg);
    return formatTerm(tr(def.title), arg);
}

function toItem(def, tr) {
    return {
        id: def.id,
        title: titleOf(def, tr),
        text: def.text,
        keywords: def.keywords.slice(),
        icon: def.icon,
        category: def.category,
        params: def.params.map(spec => ({ name: spec.name, type: spec.type, min: spec.min, max: spec.max, unit: spec.unit || (spec.type === "percent" ? "%" : spec.type === "duration" ? "minutes" : "") }))
    };
}

function toIndexItem(item) {
    return { id: item.id, title: item.title, text: item.text, keywords: item.keywords.slice(), payload: { category: item.category } };
}

function isAvailable(def, ctx) {
    try {
        return def.available(ctx) === true;
    } catch (error) {
        return false;
    }
}

function stateText(def, ctx) {
    try {
        if (def.kind === "toggle")
            return def.available(ctx) ? stateOf(ctx, def.get(ctx), def) : "";
        return def.state ? def.state(ctx) : "";
    } catch (error) {
        return "";
    }
}

// Terms every translation table must offer: titles, state words, plus the
// fixed vocabulary of the states above.
const FIXED_TERMS = ["On", "Off", "Active", "Muted", "Unmuted", "Playing", "Paused", "Connected", "Disconnected", "Dynamic"];

function termsOf(defs) {
    const terms = {};
    for (const term of FIXED_TERMS)
        terms[term] = true;
    for (const def of defs) {
        if (!def.literalTitle)
            terms[def.title] = true;
        if (def.kind === "toggle") {
            terms[def.stateOn] = true;
            terms[def.stateOff] = true;
        }
    }
    return Object.keys(terms);
}

function wordsOf(query) {
    return ActionParams.fold(query).match(/[a-z]+/g) || [];
}

// A switch whose verbs describe the thing it controls rather than the switch:
// "sesi kapat" mutes (switch on), "bildirimleri kapat" turns Do Not Disturb on.
function mutesSound(def, query) {
    if (def.invert)
        return true;
    return def.invertWhen.length > 0 && wordsOf(query).some(word => def.invertWhen.some(prefix => word.indexOf(prefix) === 0));
}

function desiredState(def, query, wanted, current) {
    // "aydınlık tema" names the other side of the switch; the bare name toggles.
    if (def.opposite.length > 0 && wordsOf(query).some(word => def.opposite.indexOf(word) !== -1))
        return wanted === "off";
    return wanted === "" ? !current : wanted === "on";
}

// Executes `def` for the text the user typed. Returns {ok, message, reason}:
// message is the confirmation to show when the shell has no OSD of its own.
function run(def, ctx, query) {
    if (!isAvailable(def, ctx))
        return fail("unavailable");
    const values = ActionParams.parse(query, def.params);
    for (const spec of def.params) {
        if (spec.required && values[spec.name] === undefined)
            return fail("missing", { param: spec });
    }
    let outcome;
    if (def.kind === "toggle") {
        const current = !!def.get(ctx);
        const wanted = ActionParams.intent(query, mutesSound(def, query));
        const valued = def.valueImpliesOn && Object.keys(values).length > 0 && wanted !== "off";
        const target = valued ? true : desiredState(def, query, wanted, current);
        if (target === current && !valued)
            return { ok: true, message: def.feedback === "toast" ? titleOf(def, ctx.tr) + ": " + stateOf(ctx, current, def) : "" };
        outcome = def.set(ctx, target, values);
        if (outcome.ok)
            outcome = { ok: true, message: def.feedback === "toast" ? titleOf(def, ctx.tr) + ": " + stateOf(ctx, target, def) : "" };
        return outcome;
    }
    outcome = def.run(ctx, values, query);
    if (outcome.ok && def.feedback === "toast" && outcome.message === "")
        outcome = { ok: true, message: titleOf(def, ctx.tr) };
    return outcome;
}
