pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/niri/assemble.js" as Assemble
import "../Common/niri/news.js" as News
import "../Common/niri/registry.js" as Registry
import "../Common/niri/pagestate.js" as Page
import "../Common/settings/SessionSpec.js" as SessionSpec

Singleton {
    id: root

    readonly property var log: Log.scoped("NiriPageService")

    readonly property var state: Page.pageState(Registry.sections, SettingsData.niriPage)
    readonly property bool expert: SettingsData.niriPageExpert
    readonly property bool busy: _busy
    readonly property string lastError: _lastError
    readonly property var history: _history
    // "primary" is left out: DMS colors.kdl already writes it.
    readonly property var themeColors: ({
            "secondary": String(Theme.secondary),
            "tertiary": String(Theme.tertiary)
        })

    signal applied(var version)
    signal refused(string message)

    // "New" pills: the running niri version and the keys that arrived after the last seen one.
    // NiriService keeps no version, so it is read once from the niri binary itself.
    readonly property string niriVersion: _niriVersion
    readonly property string seenVersion: SettingsData.niriPage["custom.news-seen"] ?? ""
    // Frozen at startup: the pills hold for the session once the version is seen and persisted.
    readonly property var newKeys: _newKeys
    property string _niriVersion: ""
    property var _newKeys: []

    function isNew(key) {
        return root._newKeys.indexOf(key) >= 0;
    }

    // Called when a pill is on screen. Stored with the page's own metadata, never as config,
    // so writing it does not assemble or reload anything.
    function noteSeenVersion() {
        if (root._niriVersion === "" || root.seenVersion === root._niriVersion)
            return;
        const page = Object.assign({}, SettingsData.niriPage);
        page["custom.news-seen"] = root._niriVersion;
        SettingsData.set("niriPage", page);
    }

    onThemeColorsChanged: followTheme()

    property bool _busy: false
    property var _sentMain: null
    property string _lastError: ""
    property var _history: []
    property var _hash: null
    property var _confirmed: null
    property var _undoState: null
    property bool _again: false

    Timer {
        id: applyTimer
        interval: 300
        onTriggered: root.applyNow()
    }

    Process {
        id: versionProbe
        running: CompositorService.isNiri
        command: ["niri", "--version"]
        stdout: StdioCollector {
            onStreamFinished: {
                versionProbe.running = false;
                const match = text.match(/niri (\d+\.\d+)/);
                if (!match)
                    return;
                root._niriVersion = match[1];
                root._newKeys = News.newKeys(root.seenVersion, match[1]);
            }
        }
    }

    // Whatever triggered the apply, theme roles are resolved here.
    function kdlState(page) {
        return Page.withColors(Page.pageState(Registry.sections, page), root.themeColors);
    }

    // Nothing sent yet this session: compare with niri.kdl as it is on disk.
    function followTheme() {
        if (!CompositorService.isNiri)
            return;
        if (root._sentMain === null) {
            // Only log: refuse() would reset an apply in flight.
            readHash(() => followTheme(), error => log.warn("niri theme follow: read failed:", Page.refusal(error)));
            return;
        }
        const main = Assemble.fragments(Registry.sections, kdlState(SettingsData.niriPage), {}).main;
        if (main !== root._sentMain)
            applyTimer.restart();
    }

    function get(key) {
        const [store, prop] = Page.storeOf(Registry.sections, key);
        if (store === "SettingsData")
            return SettingsData[prop];
        if (store === "SessionData")
            return SessionData[prop];
        if (store === "NiriService")
            return NiriService[prop];
        return root.state[key];
    }

    function defaultOf(key) {
        const [store, prop] = Page.storeOf(Registry.sections, key);
        if (store === "SettingsData")
            return SettingsData.specDefault(prop);
        if (store === "SessionData")
            return SessionSpec.SPEC[prop]?.def;
        const section = Registry.sections.find(s => key in s.defaults);
        return section ? section.defaults[key] : undefined;
    }

    function isModified(key) {
        return JSON.stringify(get(key)) !== JSON.stringify(defaultOf(key));
    }

    function set(key, value) {
        const [store, prop, setter] = Page.storeOf(Registry.sections, key);
        if (store === "SettingsData") {
            SettingsData.set(prop, value);
            return;
        }
        if (store === "SessionData") {
            SessionData.set(prop, value);
            return;
        }
        if (store === "NiriService") {
            NiriService[setter](value);
            return;
        }
        writePage(key, value);
    }

    function reset(key) {
        const [store, prop] = Page.storeOf(Registry.sections, key);
        if (store === "SettingsData") {
            SettingsData.resetToDefault([prop]);
            return;
        }
        if (store === "SessionData") {
            SessionData.resetToDefault([prop]);
            return;
        }
        if (store === "NiriService") {
            set(key, defaultOf(key));
            return;
        }
        writePage(key, undefined);
    }

    function setCustom(id, text) {
        writePage("custom." + id, text?.trim() ? text : undefined);
    }

    function writePage(key, value) {
        const page = Object.assign({}, SettingsData.niriPage);
        if (value === undefined)
            delete page[key];
        else
            page[key] = value;
        // A key with no KDL (columns.cycleWidth) leaves niri.kdl as sent: confirmed at once, no apply.
        const same = !root._busy && !applyTimer.running && !key.startsWith("custom.") && Assemble.fragments(Registry.sections, kdlState(page), {}).main === root._sentMain;
        if (root._confirmed === null || same)
            root._confirmed = same ? page : SettingsData.niriPage;
        SettingsData.set("niriPage", page);
        if (!same)
            applyTimer.restart();
    }

    function sectionKdl(id) {
        return Assemble.assemble(Registry.sections.filter(s => s.id === id), kdlState(SettingsData.niriPage));
    }

    function request(method, params, callback) {
        DMSService.sendRequest(method, Object.assign({
            "fragment": "niri.kdl"
        }, params), callback);
    }

    function applyNow() {
        if (root._busy) {
            root._again = true;
            return;
        }
        root._busy = true;
        const sent = SettingsData.niriPage;
        const out = Assemble.fragments(Registry.sections, kdlState(sent), Page.customOf(Registry.sections, sent));
        if (root._hash !== null) {
            sendApply(sent, out, true);
            return;
        }
        readHash(() => sendApply(sent, out, true));
    }

    function readHash(next, fail) {
        request("niri.config.read", {}, response => {
            if (response.error) {
                if (fail)
                    fail(response.error);
                else
                    refuse(response.error);
                return;
            }
            root._hash = response.result.hash;
            root._sentMain = response.result.content ?? "";
            next();
        });
    }

    function sendApply(sent, out, mayRetry) {
        request("niri.config.apply", {
            "content": out.main,
            "baseHash": root._hash,
            "extra": {
                [Assemble.customFragment]: out.custom
            }
        }, response => {
            if (response.error === "changed" && mayRetry) {
                readHash(() => sendApply(sent, out, false));
                return;
            }
            if (response.error) {
                refuse(response.error);
                return;
            }
            // A theme change applies the same page again: it must not become an undo step.
            if (sent !== root._confirmed) {
                root._undoState = root._confirmed;
                root._confirmed = sent;
            }
            root._sentMain = out.main;
            root._hash = response.result.hash;
            root._lastError = "";
            root._busy = false;
            root.applied(response.result.version);
            if (!root._again)
                return;
            root._again = false;
            applyNow();
        });
    }

    function refuse(error) {
        const message = Page.refusal(error);
        applyTimer.stop();
        root._hash = null;
        root._again = false;
        root._busy = false;
        root._lastError = message;
        if (root._confirmed !== null)
            SettingsData.set("niriPage", root._confirmed);
        log.warn("niri config refused:", message);
        root.refused(message);
    }

    function refreshHistory() {
        request("niri.config.history", {}, response => root._history = response.result ?? []);
    }

    function report(message) {
        root._lastError = message;
        root.refused(message);
    }

    // Applying the previous page, not restoring niri.kdl, also brings back its custom text.
    function undo() {
        const page = root._undoState;
        if (page === null) {
            report(I18n.tr("Nothing to undo"));
            return;
        }
        root._undoState = null;
        applyTimer.stop();
        SettingsData.set("niriPage", page);
        applyNow();
    }

    // shortcut: without the page that produced version n, only the file goes back and the next set overwrites it; keep a page per version if restore from history needs it.
    function restore(n, page) {
        if (root._busy) {
            report(I18n.tr("Please wait..."));
            return;
        }
        applyTimer.stop();
        root._busy = true;
        request("niri.config.restore", {
            "version": n
        }, response => {
            root._busy = false;
            if (response.error) {
                report(response.error);
                return;
            }
            root._hash = response.result.hash;
            root._sentMain = null;
            root._lastError = "";
            if (page) {
                root._confirmed = page;
                SettingsData.set("niriPage", page);
            }
            root.applied(response.result.version);
        });
    }
}
