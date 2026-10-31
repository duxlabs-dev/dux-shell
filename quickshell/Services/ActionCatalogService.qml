pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.I3
import qs.Common
import qs.Services
import "../Common/ActionCatalog.js" as ActionCatalog
import "../Common/StockThemes.js" as StockThemes

// Directly runnable actions for the launcher and its semantic search. The
// catalog data and logic live in Common/ActionCatalog.js; this singleton hands
// that code the real services and keeps the list in step with the system.
Singleton {
    id: root

    readonly property var log: Log.scoped("ActionCatalogService")

    // [{id, title, text, keywords, icon, category, params:[{name, type, min, max, unit}]}]
    property var items: []
    // Bumps whenever the list, or which actions can run, changes.
    property int revision: 0

    property var _pluginDefs: ({})
    property string _appliedKey: ""

    // English terms must appear here as literals so translation extraction
    // sees them; ActionCatalog.js refers to them by their English text.
    readonly property var _terms: ({
        "On": I18n.tr("On"),
        "Off": I18n.tr("Off"),
        "Active": I18n.tr("Active"),
        "Muted": I18n.tr("Muted"),
        "Unmuted": I18n.tr("Unmuted", "launcher action state of the speaker or microphone"),
        "Playing": I18n.tr("Playing"),
        "Paused": I18n.tr("Paused"),
        "Connected": I18n.tr("Connected"),
        "Disconnected": I18n.tr("Disconnected"),
        "Dynamic": I18n.tr("Dynamic"),
        "Dark mode": I18n.tr("Dark mode"),
        "Night mode": I18n.tr("Night mode"),
        "Do not disturb": I18n.tr("Do not disturb"),
        "Volume": I18n.tr("Volume"),
        "Volume up": I18n.tr("Volume up", "launcher action name"),
        "Volume down": I18n.tr("Volume down", "launcher action name"),
        "Mute": I18n.tr("Mute"),
        "Microphone mute": I18n.tr("Microphone mute"),
        "Microphone volume": I18n.tr("Microphone volume"),
        "Play/Pause": I18n.tr("Play/Pause", "launcher action name (media)"),
        "Play": I18n.tr("Play"),
        "Pause": I18n.tr("Pause"),
        "Next": I18n.tr("Next"),
        "Previous": I18n.tr("Previous"),
        "Brightness": I18n.tr("Brightness"),
        "Brightness up": I18n.tr("Brightness up", "launcher action name"),
        "Brightness down": I18n.tr("Brightness down", "launcher action name"),
        "Keyboard backlight": I18n.tr("Keyboard backlight", "launcher action name"),
        "Flashlight": I18n.tr("Flashlight", "launcher action name"),
        "Wi-Fi": I18n.tr("Wi-Fi"),
        "Bluetooth": I18n.tr("Bluetooth"),
        "Airplane mode": I18n.tr("Airplane mode", "launcher action name"),
        "VPN": I18n.tr("VPN"),
        "Power Saver": I18n.tr("Power Saver"),
        "Balanced": I18n.tr("Balanced"),
        "Performance": I18n.tr("Performance"),
        "Lock screen": I18n.tr("Lock screen"),
        "Suspend": I18n.tr("Suspend"),
        "Hibernate": I18n.tr("Hibernate"),
        "Reboot": I18n.tr("Reboot"),
        "Power off": I18n.tr("Power off"),
        "Log out": I18n.tr("Log out"),
        "Turn off displays": I18n.tr("Turn off displays", "launcher action name"),
        "Keep Awake": I18n.tr("Keep Awake"),
        "Close Window": I18n.tr("Close Window"),
        "Fullscreen": I18n.tr("Fullscreen"),
        "Floating": I18n.tr("Floating"),
        "Move window to workspace": I18n.tr("Move window to workspace", "launcher action name"),
        "Move window to monitor": I18n.tr("Move window to monitor", "launcher action name"),
        "Screenshot: Region": I18n.tr("Screenshot: Region", "launcher action name: screenshot of a selected area"),
        "Screenshot: Screen": I18n.tr("Screenshot: Screen", "launcher action name: screenshot of the current monitor"),
        "Screenshot: Window": I18n.tr("Screenshot: Window", "launcher action name: screenshot of the focused window"),
        "Screenshot: All screens": I18n.tr("Screenshot: All screens", "launcher action name: screenshot of every monitor"),
        "Screenshot: Scrolling": I18n.tr("Screenshot: Scrolling", "launcher action name: screenshot of a scrolling page"),
        "Color scheme: %1": I18n.tr("Color scheme: %1", "launcher action name; %1 is a color scheme name"),
        "Bluetooth: %1": I18n.tr("Bluetooth: %1", "launcher action name; %1 is On or Off"),
        "VPN: %1": I18n.tr("VPN: %1", "launcher action name; %1 is On or Off")
    })

    // Every service the actions call, handed to ActionCatalog.js by name.
    readonly property var _ctxObject: ({
            "tr": root._translate,
            "theme": Theme,
            "night": NightModeService,
            "sessionData": SessionData,
            "audio": AudioService,
            "mpris": MprisController,
            "brightness": BrightnessService,
            "network": NetworkService,
            "bluetooth": BluetoothService,
            "vpn": DMSNetworkService,
            "power": PowerProfileWatcher,
            "sessionService": SessionService,
            "idle": IdleService,
            "popout": PopoutService,
            "settings": SettingsData,
            "compositor": CompositorService,
            "hyprlandService": HyprlandService,
            "hyprland": Hyprland,
            "niri": NiriService,
            "mango": MangoService,
            "i3": I3,
            "screenNames": () => Quickshell.screens.map(screen => screen.name),
            "exec": argv => Quickshell.execDetached(argv)
        })

    readonly property var _themeEntries: StockThemes.getAllThemeNames().map(name => ({
                "name": name,
                "label": StockThemes.getThemeByName(name, false).name
            }))

    readonly property var _bluetoothEntries: (BluetoothService.pairedDevices || []).map(device => ({
                "address": device.address,
                "name": device.name || device.deviceName || "",
                "icon": BluetoothService.getDeviceIcon(device)
            }))

    readonly property var _pluginDefList: Object.keys(_pluginDefs).reduce((all, id) => all.concat(_pluginDefs[id]), [])

    readonly property var _defs: ActionCatalog.buildDefs({
        "themes": _themeEntries,
        "bluetoothDevices": _bluetoothEntries,
        "vpnProfiles": DMSNetworkService.vpnProfiles,
        "pluginDefs": _pluginDefList
    })

    readonly property var _defById: {
        const index = {};
        for (const def of _defs)
            index[def.id] = def;
        return index;
    }

    readonly property var _itemList: _defs.map(def => ActionCatalog.toItem(def, _translate))

    // The key changes only when the visible catalog or what can run changes, so
    // a rebuilt array with the same content does not trigger a re-embedding.
    readonly property string _catalogKey: JSON.stringify(_itemList) + "|" + _defs.filter(def => ActionCatalog.isAvailable(def, _ctx())).map(def => def.id).join(",")

    on_CatalogKeyChanged: _sync()
    Component.onCompleted: _sync()

    function _sync() {
        if (_catalogKey === _appliedKey)
            return;
        _appliedKey = _catalogKey;
        items = _itemList;
        revision++;
    }

    function _translate(term) {
        return root._terms[term] ?? I18n.tr(term);
    }

    function _ctx() {
        return _ctxObject;
    }

    function itemById(id) {
        return items.find(item => item.id === id) ?? null;
    }

    function available(id) {
        const def = _defById[id];
        return def ? ActionCatalog.isAvailable(def, _ctx()) : false;
    }

    // "" when the action has no state to show.
    function stateText(id) {
        const def = _defById[id];
        return def ? ActionCatalog.stateText(def, _ctx()) : "";
    }

    // The items dsearch embeds: only actions that can run right now.
    function indexItems() {
        return items.filter(item => available(item.id)).map(ActionCatalog.toIndexItem);
    }

    // Runs the action with the numbers found in `query` ("volume 40%").
    function execute(id, query) {
        const def = _defById[id];
        if (!def)
            return false;
        let result;
        try {
            result = ActionCatalog.run(def, _ctx(), String(query ?? ""));
        } catch (error) {
            log.error("Action failed:", id, error);
            result = {
                "ok": false,
                "reason": "failed"
            };
        }
        _report(id, result);
        return result.ok;
    }

    function _report(id, result) {
        if (result.ok) {
            if (result.message)
                ToastService.showInfo(result.message);
            return;
        }
        const item = itemById(id);
        const title = item ? item.title : id;
        ToastService.showError(title, _failureText(result));
    }

    function _failureText(result) {
        switch (result.reason) {
        case "unavailable":
            return I18n.tr("Not available");
        case "busy":
            return I18n.tr("Busy, try again in a moment", "launcher action result while the same action is still running");
        case "missing":
            return I18n.tr("Add a value, for example %1", "launcher action needs a value typed after its name; %1 is an example value").arg(result.param?.example ?? "");
        default:
            return result.message || I18n.tr("Action failed", "launcher action result when running an action failed without a message");
        }
    }

    // Plugin API. `actions` replaces everything `pluginId` registered before:
    // [{id, title, text, keywords?, icon?, params?, available?, state?, run(values, query)}].
    // Returns {registered, errors}; a malformed entry is skipped and reported.
    function registerPluginActions(pluginId, actions) {
        const built = ActionCatalog.pluginDefs(pluginId, actions);
        for (const error of built.errors)
            log.warn("Plugin action rejected:", pluginId, error);
        const next = Object.assign({}, _pluginDefs);
        if (built.defs.length > 0)
            next[pluginId] = built.defs;
        else
            delete next[pluginId];
        _pluginDefs = next;
        return {
            "registered": built.defs.length,
            "errors": built.errors
        };
    }

    function unregisterPluginActions(pluginId) {
        if (!(pluginId in _pluginDefs))
            return;
        const next = Object.assign({}, _pluginDefs);
        delete next[pluginId];
        _pluginDefs = next;
    }

    Connections {
        target: PluginService

        function onPluginUnloaded(pluginId) {
            root.unregisterPluginActions(pluginId);
        }
    }
}
