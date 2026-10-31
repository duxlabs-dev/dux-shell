pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Common as DCommon

Singleton {
    id: root
    readonly property var log: Log.scoped("DMSService")

    readonly property bool dmsAvailable: isConnected
    property var capabilities: []
    property int apiVersion: 0
    property string cliVersion: ""
    readonly property int expectedApiVersion: 1
    property var availablePlugins: []
    property var installedPlugins: []
    property bool checkingPluginUpdates: false
    property string pluginUpdateCheckError: ""
    property double pluginUpdatesCheckedAt: 0
    readonly property int pluginUpdatesCacheAge: 5 * 60 * 1000
    property int pluginInventoryRevision: 0
    property var pluginUpdateCallbacks: []
    property var registries: []
    property var availableThemes: []
    property var installedThemes: []
    property bool installedThemesLoaded: false
    property bool isConnected: false
    readonly property bool isConnecting: requestSocket.connected && !requestSocket.linkUp
    property bool subscribeConnected: false
    property string mprisCommandLease: ""
    property bool matugenSmartSupported: false

    readonly property string socketPath: Quickshell.env("DMS_SOCKET")

    property var pendingRequests: ({})
    property var requestTimeouts: ({})
    property var clipboardRequestIds: ({})
    property int requestIdCounter: 0
    property bool shownOutdatedError: false

    signal pluginsListReceived(var plugins)
    signal installedPluginsReceived(var plugins)
    signal searchResultsReceived(var plugins)
    signal themesListReceived(var themes)
    signal installedThemesReceived(var themes)
    signal themeSearchResultsReceived(var themes)
    signal operationSuccess(string message)
    signal operationError(string error)
    signal connectionStateChanged

    signal networkStateUpdate(var data)
    signal cupsStateUpdate(var data)
    signal loginctlStateUpdate(var data)
    signal capabilitiesReceived
    signal credentialsRequest(var data)
    signal bluetoothPairingRequest(var data)
    signal mprisCommandReceived(string command)
    signal brightnessStateUpdate(var data)
    signal brightnessDeviceUpdate(var device)
    signal wlrOutputStateUpdate(var data)
    signal evdevStateUpdate(var data)
    signal gammaStateUpdate(var data)
    signal themeAutoStateUpdate(var data)
    signal wallpaperCycleUpdate(var data)
    signal openUrlRequested(string url)
    signal appPickerRequested(var data)
    signal screensaverStateUpdate(var data)
    signal freedesktopStateUpdate(var data)
    signal clipboardStateUpdate(var data)
    signal locationStateUpdate(var data)
    signal sysupdateStateUpdate(var data)
    signal tailscaleStateUpdate(var data)
    signal wellbeingStateUpdate(var data)
    signal filesEvent(var data)

    property bool capsLockState: false
    property bool numLockState: false
    property bool evdevStateInitialized: false
    property bool screensaverInhibited: false
    property var screensaverInhibitors: []

    property var activeSubscriptions: ["network", "network.credentials", "loginctl", "freedesktop", "freedesktop.screensaver", "gamma", "wallpaper", "bluetooth", "bluetooth.pairing", "brightness", "wlroutput", "evdev", "browser", "dbus"]
    property var connectionCapabilities: null

    Component.onCompleted: {
        if (!socketPath || socketPath.length === 0)
            return;
        requestSocket.connected = true;
    }

    DCommon.DSocket {
        id: requestSocket
        path: root.socketPath
        connected: false

        onConnectionStateChanged: {
            if (linkUp) {
                root.isConnected = true;
                root.connectionStateChanged();
                subscribeSocket.connected = true;
                root.refreshMatugenStatus();
                return;
            }
            root.isConnected = false;
            root.apiVersion = 0;
            root.capabilities = [];
            root.failPendingRequests();
            root.connectionStateChanged();
        }

        parser: SplitParser {
            onRead: line => {
                if (!line || line.length === 0)
                    return;

                let response;
                try {
                    response = JSON.parse(line);
                } catch (e) {
                    log.warn("Failed to parse request response:", line.substring(0, 100));
                    return;
                }
                const isClipboard = clipboardRequestIds[response.id];
                if (isClipboard)
                    delete clipboardRequestIds[response.id];
                else
                    log.debug("Request socket <<", line);
                handleResponse(response);
            }
        }
    }

    DCommon.DSocket {
        id: subscribeSocket
        path: root.socketPath
        connected: false

        onConnectionStateChanged: {
            root.subscribeConnected = linkUp;
            root.mprisCommandLease = "";
            if (!linkUp) {
                root.connectionCapabilities = null;
                return;
            }
            sendSubscribeRequest();
        }

        parser: SplitParser {
            onRead: line => {
                if (!line || line.length === 0)
                    return;

                let response;
                try {
                    response = JSON.parse(line);
                } catch (e) {
                    log.warn("Failed to parse subscription event:", line.substring(0, 100));
                    return;
                }
                if (!line.includes("clipboard"))
                    log.debug("Subscribe socket <<", line);
                handleSubscriptionEvent(response);
            }
        }
    }

    function refreshMatugenStatus() {
        sendRequest("matugen.status", null, response => {
            if (!response.error && response.result)
                matugenSmartSupported = response.result.smartSupported === true;
        });
    }

    function sendSubscribeRequest() {
        const request = {
            "method": "subscribe",
            "params": {
                "clientId": dbusClientId
            }
        };

        if (activeSubscriptions.length > 0) {
            request.params.services = activeSubscriptions;
            log.debug("Subscribing to services:", JSON.stringify(activeSubscriptions));
        } else {
            log.debug("Subscribing to all services");
        }

        subscribeSocket.send(request);
    }

    property bool _resubscribePending: false

    // Deferred so the socket is not torn down inside its own parser callback.
    // Qt.callLater collapses a same-tick capability burst into one re-dial.
    function _resubscribeNow() {
        if (!_resubscribePending)
            return;
        _resubscribePending = false;
        subscribe(activeSubscriptions);
    }

    function _capabilityNeeded(capability) {
        return activeSubscriptions.includes("all") || activeSubscriptions.includes(capability);
    }

    // Only a capability that was missing when this connection was made can be worth re-dialing for.
    function _hasNewNeededCapability(newCapabilities) {
        if (!connectionCapabilities)
            return false;
        return newCapabilities.some(c => !connectionCapabilities.includes(c) && _capabilityNeeded(c));
    }

    function subscribe(services) {
        if (!Array.isArray(services)) {
            services = [services];
        }

        _resubscribePending = false;
        activeSubscriptions = services;

        if (subscribeConnected) {
            subscribeSocket.connected = false;
            Qt.callLater(() => {
                subscribeSocket.connected = true;
            });
        }
    }

    function addSubscription(service) {
        if (activeSubscriptions.includes(service))
            return;
        if (activeSubscriptions.includes("all") && service !== "mpris.command")
            return;
        subscribe([...activeSubscriptions, service]);
    }

    function removeSubscription(service) {
        if (activeSubscriptions.includes("all") && service !== "mpris.command") {
            const allServices = ["network", "loginctl", "freedesktop", "gamma", "bluetooth", "brightness", "browser", "location"];
            const filtered = allServices.filter(s => s !== service);
            subscribe(filtered);
        } else {
            const filtered = activeSubscriptions.filter(s => s !== service);
            if (filtered.length === 0) {
                log.warn("Cannot remove last subscription");
                return;
            }
            subscribe(filtered);
        }
    }

    function handleSubscriptionEvent(response) {
        if (response.error) {
            if (response.error.includes("unknown method") && response.error.includes("subscribe")) {
                if (!shownOutdatedError) {
                    log.error("Server does not support subscribe method");
                    ToastService.showError(I18n.tr("DMS out of date"), I18n.tr("Update the dms package with your package manager, then restart the shell.", "shown when the running shell is older than the installed dms binary"));
                    shownOutdatedError = true;
                }
            }
            return;
        }

        if (!response.result) {
            return;
        }

        const service = response.result.service;
        const data = response.result.data;

        if (service === "server") {
            apiVersion = data.apiVersion || 0;
            cliVersion = data.cliVersion || "";
            capabilities = data.capabilities || [];

            log.info("Connected (API v" + apiVersion + ", CLI " + cliVersion + ") -", JSON.stringify(capabilities));

            if (apiVersion < expectedApiVersion) {
                ToastService.showError(I18n.tr("DMS server is outdated (API v%1, expected v%2)", "error toast, %1 is current api version, %2 is required version").arg(apiVersion).arg(expectedApiVersion));
            }

            capabilitiesReceived();

            const needsResubscribe = _hasNewNeededCapability(capabilities);
            if (!connectionCapabilities)
                connectionCapabilities = capabilities;
            if (needsResubscribe && !_resubscribePending) {
                log.info("Subscribed capability appeared, resubscribing");
                _resubscribePending = true;
                Qt.callLater(root._resubscribeNow);
            }
        } else if (service === "network") {
            networkStateUpdate(data);
        } else if (service === "network.credentials") {
            credentialsRequest(data);
        } else if (service === "loginctl") {
            loginctlStateUpdate(data);
        } else if (service === "bluetooth.pairing") {
            bluetoothPairingRequest(data);
        } else if (service === "mpris.command") {
            if (data && typeof data.lease === "string")
                mprisCommandLease = data.lease;
            else if (data && typeof data.command === "string")
                mprisCommandReceived(data.command);
        } else if (service === "cups") {
            cupsStateUpdate(data);
        } else if (service === "brightness") {
            brightnessStateUpdate(data);
        } else if (service === "brightness.update") {
            if (data.device) {
                brightnessDeviceUpdate(data.device);
            }
        } else if (service === "wlroutput") {
            wlrOutputStateUpdate(data);
        } else if (service === "evdev") {
            if (data.capsLock !== undefined) {
                capsLockState = data.capsLock;
            }
            if (data.numLock !== undefined) {
                numLockState = data.numLock;
            }
            evdevStateInitialized = true;
            evdevStateUpdate(data);
        } else if (service === "gamma") {
            gammaStateUpdate(data);
        } else if (service === "theme.auto") {
            themeAutoStateUpdate(data);
        } else if (service === "wallpaper") {
            wallpaperCycleUpdate(data);
        } else if (service === "browser.open_requested") {
            if (data.target) {
                if (data.requestType === "url" || !data.requestType) {
                    openUrlRequested(data.target);
                } else {
                    appPickerRequested(data);
                }
            } else if (data.url) {
                openUrlRequested(data.url);
            }
        } else if (service === "freedesktop.screensaver") {
            screensaverInhibited = data.inhibited || false;
            screensaverInhibitors = data.inhibitors || [];
            screensaverStateUpdate(data);
        } else if (service === "freedesktop") {
            freedesktopStateUpdate(data);
        } else if (service === "dbus") {
            dbusSignalReceived(data.subscriptionId || "", data);
        } else if (service === "clipboard") {
            clipboardStateUpdate(data);
        } else if (service === "location") {
            locationStateUpdate(data);
        } else if (service === "sysupdate") {
            sysupdateStateUpdate(data);
        } else if (service === "tailscale") {
            tailscaleStateUpdate(data);
        } else if (service === "wellbeing") {
            wellbeingStateUpdate(data);
        } else if (service === "files") {
            filesEvent(data);
        }
    }

    Component {
        id: requestTimeoutComponent
        Timer {
            property var requestId
            repeat: false
            onTriggered: root.handleResponse({
                id: requestId,
                error: "Request timed out; operation completion is uncertain"
            })
        }
    }

    function sendRequest(method, params, callback, timeoutMs) {
        if (!isConnected) {
            log.warn("DMSService.sendRequest: Not connected, method:", method);
            if (callback) {
                callback({
                    "error": "not connected to DMS socket"
                });
            }
            return;
        }

        requestIdCounter++;
        const id = Date.now() + requestIdCounter;
        const request = {
            "id": id,
            "method": method
        };

        if (params) {
            request.params = params;
        }

        if (callback) {
            pendingRequests[id] = callback;
            if (timeoutMs > 0) {
                const timeout = requestTimeoutComponent.createObject(root, {
                    requestId: id,
                    interval: timeoutMs
                });
                requestTimeouts[id] = timeout;
                timeout.start();
            }
        }

        if (method.startsWith("clipboard")) {
            clipboardRequestIds[id] = true;
        } else {
            log.debug("DMSService.sendRequest: Sending request id=" + id + " method=" + method);
        }
        requestSocket.send(request);
        return id;
    }

    function cancelRequest(id) {
        const timeout = requestTimeouts[id];
        if (timeout) {
            timeout.stop();
            timeout.destroy();
            delete requestTimeouts[id];
        }
        delete pendingRequests[id];
    }

    function handleResponse(response) {
        const callback = pendingRequests[response.id];
        if (!callback)
            return;
        cancelRequest(response.id);
        callback(response);
    }

    function failPendingRequests() {
        const pending = pendingRequests;
        pendingRequests = {};
        clipboardRequestIds = {};
        for (const id in pending) {
            cancelRequest(id);
            pending[id]({
                "error": "not connected to DMS socket"
            });
        }
    }

    function listPlugins(callback) {
        sendRequest("plugins.list", null, response => {
            if (response.result) {
                availablePlugins = response.result;
                pluginsListReceived(response.result);
            }
            if (callback) {
                callback(response);
            }
        });
    }

    function listInstalled(callback, force = false) {
        if (callback)
            pluginUpdateCallbacks.push(callback);
        if (checkingPluginUpdates)
            return;
        if (!force && pluginUpdatesCheckedAt > 0 && Date.now() - pluginUpdatesCheckedAt < pluginUpdatesCacheAge) {
            finishPluginUpdateCheck({
                result: installedPlugins
            });
            return;
        }
        checkingPluginUpdates = true;
        pluginUpdateCheckError = "";
        const revision = pluginInventoryRevision;
        sendRequest("plugins.listInstalled", null, response => {
            checkingPluginUpdates = false;
            if (revision !== pluginInventoryRevision && dmsAvailable) {
                listInstalled(undefined, true);
                return;
            }
            if (response.error) {
                pluginUpdateCheckError = response.error;
                finishPluginUpdateCheck(response);
                return;
            }
            const previous = new Map(installedPlugins.map(plugin => [plugin.id, plugin]));
            installedPlugins = (response.result || []).map(plugin => {
                const known = previous.get(plugin.id);
                if (!plugin.updateError || !known)
                    return plugin;
                return Object.assign({}, plugin, {
                    hasUpdate: known.hasUpdate,
                    diffUrl: known.diffUrl
                });
            });
            pluginUpdatesCheckedAt = Date.now();
            installedPluginsReceived(installedPlugins);
            finishPluginUpdateCheck({
                result: installedPlugins
            });
        }, 120000);
    }

    function finishPluginUpdateCheck(response) {
        const callbacks = pluginUpdateCallbacks;
        pluginUpdateCallbacks = [];
        for (const callback of callbacks)
            callback(response);
    }

    function pluginOperationFinished(pluginName, removed) {
        pluginInventoryRevision++;
        pluginUpdatesCheckedAt = 0;
        if (removed) {
            installedPlugins = installedPlugins.filter(plugin => plugin.id !== pluginName);
        } else {
            const known = installedPlugins.find(plugin => plugin.id === pluginName) || availablePlugins.find(plugin => plugin.id === pluginName);
            if (known)
                installedPlugins = installedPlugins.filter(plugin => plugin.id !== pluginName).concat([Object.assign({}, known, {
                        hasUpdate: false,
                        updateError: ""
                    })]);
        }
        installedPluginsReceived(installedPlugins);
    }

    function install(pluginName, callback) {
        sendRequest("plugins.install", {
            "name": pluginName
        }, response => {
            if (!response.error)
                pluginOperationFinished(pluginName, false);
            if (callback)
                callback(response);
            if (!response.error)
                listInstalled();
        });
    }

    function uninstall(pluginName, callback) {
        sendRequest("plugins.uninstall", {
            "name": pluginName
        }, response => {
            if (!response.error)
                pluginOperationFinished(pluginName, true);
            if (callback)
                callback(response);
            if (!response.error)
                listInstalled();
        });
    }

    function update(pluginName, callback) {
        sendRequest("plugins.update", {
            "name": pluginName
        }, response => {
            if (!response.error)
                pluginOperationFinished(pluginName, false);
            if (callback)
                callback(response);
            if (!response.error)
                listInstalled();
        });
    }

    function listRegistries(callback) {
        sendRequest("registries.list", null, response => {
            if (response.result) {
                registries = response.result;
            }
            if (callback) {
                callback(response);
            }
        });
    }

    function addRegistry(name, url, callback) {
        sendRequest("registries.add", {
            "name": name,
            "url": url
        }, response => {
            if (callback) {
                callback(response);
            }
            if (!response.error) {
                listRegistries();
            }
        });
    }

    function removeRegistry(name, callback) {
        sendRequest("registries.remove", {
            "name": name
        }, response => {
            if (callback) {
                callback(response);
            }
            if (!response.error) {
                listRegistries();
            }
        });
    }

    function listThemes(callback) {
        sendRequest("themes.list", null, response => {
            if (response.result) {
                availableThemes = response.result;
                themesListReceived(response.result);
            }
            if (callback) {
                callback(response);
            }
        });
    }

    function listInstalledThemes(callback) {
        sendRequest("themes.listInstalled", null, response => {
            if (response.result) {
                installedThemes = response.result;
                installedThemesLoaded = true;
                installedThemesReceived(response.result);
            }
            if (callback) {
                callback(response);
            }
        });
    }

    function installTheme(themeName, callback) {
        sendRequest("themes.install", {
            "name": themeName
        }, response => {
            if (callback) {
                callback(response);
            }
            if (!response.error) {
                listInstalledThemes();
            }
        });
    }

    function uninstallTheme(themeName, callback) {
        sendRequest("themes.uninstall", {
            "name": themeName
        }, response => {
            if (callback) {
                callback(response);
            }
            if (!response.error) {
                listInstalledThemes();
            }
        });
    }

    function lockSession(callback) {
        sendRequest("loginctl.lock", null, callback);
    }

    function unlockSession(callback) {
        sendRequest("loginctl.unlock", null, callback);
    }

    function setLockedHint(locked, callback) {
        sendRequest("loginctl.setLockedHint", {
            "locked": locked
        }, callback);
    }

    function bluetoothPair(devicePath, callback) {
        sendRequest("bluetooth.pair", {
            "device": devicePath
        }, callback);
    }

    function bluetoothRemove(devicePath, callback) {
        sendRequest("bluetooth.remove", {
            "device": devicePath
        }, callback);
    }

    function bluetoothSubmitPairing(token, secrets, accept, callback) {
        sendRequest("bluetooth.pairing.submit", {
            "token": token,
            "secrets": secrets,
            "accept": accept
        }, callback);
    }

    function bluetoothCancelPairing(token, callback) {
        sendRequest("bluetooth.pairing.cancel", {
            "token": token
        }, callback);
    }

    signal dbusSignalReceived(string subscriptionId, var data)

    readonly property string dbusClientId: "dms-qml-" + Date.now() + "-" + Math.floor(Math.random() * 0xffffffff)
    property var dbusSubscriptions: ({})

    function dbusCall(bus, dest, path, iface, method, args, callback) {
        sendRequest("dbus.call", {
            "bus": bus,
            "dest": dest,
            "path": path,
            "interface": iface,
            "method": method,
            "args": args || []
        }, callback);
    }

    function dbusGetProperty(bus, dest, path, iface, property, callback) {
        sendRequest("dbus.getProperty", {
            "bus": bus,
            "dest": dest,
            "path": path,
            "interface": iface,
            "property": property
        }, callback);
    }

    function dbusSetProperty(bus, dest, path, iface, property, value, callback) {
        sendRequest("dbus.setProperty", {
            "bus": bus,
            "dest": dest,
            "path": path,
            "interface": iface,
            "property": property,
            "value": value
        }, callback);
    }

    function dbusGetAllProperties(bus, dest, path, iface, callback) {
        sendRequest("dbus.getAllProperties", {
            "bus": bus,
            "dest": dest,
            "path": path,
            "interface": iface
        }, callback);
    }

    function dbusIntrospect(bus, dest, path, callback) {
        sendRequest("dbus.introspect", {
            "bus": bus,
            "dest": dest,
            "path": path || "/"
        }, callback);
    }

    function dbusListNames(bus, callback) {
        sendRequest("dbus.listNames", {
            "bus": bus
        }, callback);
    }

    function dbusSubscribe(bus, sender, path, iface, member, callback) {
        sendRequest("dbus.subscribe", {
            "bus": bus,
            "sender": sender || "",
            "path": path || "",
            "interface": iface || "",
            "member": member || "",
            "clientId": dbusClientId
        }, response => {
            if (!response.error && response.result?.subscriptionId) {
                dbusSubscriptions[response.result.subscriptionId] = true;
            }
            if (callback)
                callback(response);
        });
    }

    function dbusUnsubscribe(subscriptionId, callback) {
        sendRequest("dbus.unsubscribe", {
            "subscriptionId": subscriptionId
        }, response => {
            if (!response.error) {
                delete dbusSubscriptions[subscriptionId];
            }
            if (callback)
                callback(response);
        });
    }

    function sysupdateGetState(callback) {
        sendRequest("sysupdate.getState", null, callback);
    }

    function sysupdateRefresh(force, callback, background) {
        sendRequest("sysupdate.refresh", {
            "force": force === true,
            "background": background === true
        }, callback);
    }

    function sysupdateUpgrade(opts, callback) {
        const params = opts || {};
        sendRequest("sysupdate.upgrade", params, callback);
    }

    function sysupdateCancel(callback) {
        sendRequest("sysupdate.cancel", null, callback);
    }

    function sysupdateSetInterval(seconds, callback) {
        sendRequest("sysupdate.setInterval", {
            "seconds": seconds
        }, callback);
    }

    function sysupdateAcquire(callback) {
        sendRequest("sysupdate.acquire", null, callback);
    }

    function sysupdateRelease(callback) {
        sendRequest("sysupdate.release", null, callback);
    }

    function notifySend(params, callback) {
        sendRequest("notify.send", params, callback);
    }

    function sysupdateReleases(force, callback) {
        sendRequest("sysupdate.releases", {
            "force": force === true
        }, callback);
    }

    function sysupdateRepoStatus(callback) {
        sendRequest("sysupdate.repoStatus", null, callback);
    }
}
