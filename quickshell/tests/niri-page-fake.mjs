import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

// The singleton imports qs.*, which qmltestrunner cannot resolve, so its functions run here against fakes.
const source = readFileSync(new URL("../Services/NiriPageService.qml", import.meta.url), "utf8");
const Assemble = loadScript(new URL("../Common/niri/assemble.js", import.meta.url));
const Page = loadScript(new URL("../Common/niri/pagestate.js", import.meta.url));
export const include = "include optional=true \"niri-custom.kdl\"\n";
const Look = loadScript(new URL("../Common/niri/sections/look.js", import.meta.url));
export const look = { id: "windows", defaults: Look.defaults, toKdl: Look.toKdl, stored: Look.stored };
export const ring = hex => "layout {\n    focus-ring {\n        active-color \"" + hex + "\"\n    }\n}\n" + include;

export const section = {
    id: "t",
    defaults: { "t.width": 4 },
    stored: { "t.width": "page", "t.gaps": "SettingsData:niriLayoutGapsOverride" },
    toKdl: state => [{ block: "layout", lines: Object.keys(state).map(key => key.slice(2) + " " + state[key]) }]
};

function timer() {
    return { running: false, restarts: 0, restart() { this.running = true; this.restarts++; }, stop() { this.running = false; } };
}

function dms(replies) {
    const requests = [];
    let version = 0;
    const defaults = {
        "niri.config.read": () => ({ result: { content: "", hash: "h0" } }),
        "niri.config.apply": () => ({ result: { version: ++version, hash: "h" + version } }),
        "niri.config.restore": params => ({ result: { version: ++version, hash: "r" + params.version } }),
        "niri.config.history": () => ({ result: [] })
    };
    const DMSService = {
        sendRequest(method, params, callback) {
            requests.push({ method, params: { ...params } });
            const queued = replies[method]?.shift();
            callback(queued ?? defaults[method](params));
        }
    };
    return { requests, DMSService };
}

// QML bindings: state is rebuilt only when niriPage changes, themeColors stands for the live Theme.
function bind(context, settings) {
    context.builds = 0;
    context.Page.pageState = (sections, page) => {
        context.builds++;
        return Page.pageState(sections, page);
    };
    let cache = null;
    Object.defineProperty(context, "state", {
        get: () => (cache?.page === settings.niriPage ? cache : (cache = { page: settings.niriPage, state: context.Page.pageState(context.Registry.sections, settings.niriPage) })).state
    });
    context.themeColors = { secondary: "#112233", tertiary: "#445566" };
}

export function service(replies = {}) {
    const events = [];
    const warnings = [];
    const { requests, DMSService } = dms(replies);
    const settings = {
        niriPage: {},
        niriLayoutGapsOverride: -1,
        set(key, value) { this[key] = value; },
        specDefault: key => ({ niriLayoutGapsOverride: -1 })[key]
    };
    const context = vm.createContext({
        JSON, Object, Assemble, DMSService,
        Page: Object.assign({}, Page),
        I18n: { tr: text => text },
        Registry: { sections: [section] },
        SettingsData: settings,
        CompositorService: { isNiri: true },
        applyTimer: timer(),
        log: { warn: (...args) => warnings.push(args.join(" ")) },
        applied: v => events.push(["applied", v]),
        refused: m => events.push(["refused", m])
    });
    context.root = context;
    for (const match of source.matchAll(/^    function \w+\([^\n]*\)(?:: \w+)? \{\n[\s\S]*?^    \}/gm))
        vm.runInContext(match[0], context);
    for (const match of source.matchAll(/^    property (?:var|string|bool|int) (_\w+): (.+)$/gm))
        vm.runInContext(`var ${match[1]} = ${match[2]};`, context);
    bind(context, settings);
    const fire = () => {
        assert.ok(context.applyTimer.running);
        context.applyTimer.running = false;
        context.applyNow();
    };
    return { s: context, settings, requests, events, warnings, fire, methods: () => requests.map(r => r.method) };
}
