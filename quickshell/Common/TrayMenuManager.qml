pragma Singleton

import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import qs.Common
import "../Services/IconThemeIndex.js" as IconIndex

Singleton {
    id: root

    property var activeTrayMenus: ({})
    property var _pendingMenuRequest: null
    property var _trayKeyByItem: new Map()
    property var _iconFallbacks: ({})
    property var _iconFallbackWaiters: ({})

    readonly property var envHiddenTrayIds: {
        const envValue = Quickshell.env("DMS_HIDE_TRAYIDS") || "";
        return envValue ? envValue.split(",").map(id => id.trim().toLowerCase()) : [];
    }

    function isEnvHidden(itemId) {
        if (!itemId || !envHiddenTrayIds.length)
            return false;
        return envHiddenTrayIds.includes(itemId.toLowerCase());
    }

    function filterEnvHidden(items) {
        if (!items)
            return [];
        if (!envHiddenTrayIds.length)
            return items;
        return items.filter(item => !isEnvHidden(item?.id));
    }

    Connections {
        target: SystemTray
        function onItemUnregistered(item) {
            root._trayKeyByItem.delete(item);
        }
    }

    function getTrayItemKey(item, allItems) {
        const id = item?.id || "";
        if (!id)
            return "";
        if (_trayKeyByItem.has(item))
            return _trayKeyByItem.get(item);
        const pool = allItems || SystemTray.items.values;
        const taken = new Set();
        for (const live of pool) {
            if (live !== item && (live?.id || "") === id && _trayKeyByItem.has(live))
                taken.add(_trayKeyByItem.get(live));
        }
        let key = id;
        for (let n = 1; taken.has(key); n++)
            key = `${id}::${n}`;
        _trayKeyByItem.set(item, key);
        return key;
    }

    function resolveOrderIndex(key, orderMap) {
        if (orderMap.has(key))
            return orderMap.get(key);
        return -1;
    }

    function sortByPreferredOrder(items, savedOrder) {
        if (!items)
            return [];
        const order = savedOrder || [];
        const orderMap = new Map();
        order.forEach((key, idx) => orderMap.set(key, idx));

        return [...items].sort((a, b) => {
            const keyA = getTrayItemKey(a, items);
            const keyB = getTrayItemKey(b, items);
            const orderA = resolveOrderIndex(keyA, orderMap);
            const orderB = resolveOrderIndex(keyB, orderMap);
            const posA = orderA >= 0 ? orderA : 10000 + items.indexOf(a);
            const posB = orderB >= 0 ? orderB : 10000 + items.indexOf(b);
            return posA - posB;
        });
    }

    function dragShiftOffset(index, draggedIndex, dropTargetIndex, shiftAmount) {
        if (draggedIndex < 0 || index === draggedIndex || dropTargetIndex < 0)
            return 0;
        if (draggedIndex < dropTargetIndex && index > draggedIndex && index <= dropTargetIndex)
            return -shiftAmount;
        if (draggedIndex > dropTargetIndex && index >= dropTargetIndex && index < draggedIndex)
            return shiftAmount;
        return 0;
    }

    function reorderItemKeys(allKeys, fromKey, toKey) {
        if (!allKeys || !fromKey || !toKey)
            return null;
        const fullOrder = [...allKeys];
        const fromIdx = fullOrder.indexOf(fromKey);
        const toIdx = fullOrder.indexOf(toKey);
        if (fromIdx < 0 || toIdx < 0 || fromIdx === toIdx)
            return null;
        const moved = fullOrder.splice(fromIdx, 1)[0];
        fullOrder.splice(toIdx, 0, moved);
        return fullOrder;
    }

    signal openTrayMenuRequested

    function requestOpenMenu(itemId, screenName) {
        _pendingMenuRequest = {
            "itemId": itemId,
            "screenName": screenName
        };
        openTrayMenuRequested();
    }

    // Every SystemTrayBar instance receives the signal; the claim ensures
    // exactly one opens the menu, preferring the requested screen
    function claimMenuRequest(instanceScreenName) {
        if (!_pendingMenuRequest)
            return null;
        if (_pendingMenuRequest.screenName && _pendingMenuRequest.screenName !== instanceScreenName)
            return null;
        const request = _pendingMenuRequest;
        _pendingMenuRequest = null;
        return request;
    }

    function findTrayItem(itemId: string): var {
        if (!itemId)
            return null;

        return SystemTray.items.values.find(item => {
            const id = item?.id || "";
            const title = item?.tooltipTitle || "";
            const fullKey = title ? `${id}::${title}` : id;
            return fullKey === itemId || id === itemId;
        });
    }

    function registerMenu(screenName, menu) {
        if (!screenName || !menu)
            return;
        const newMenus = Object.assign({}, activeTrayMenus);
        newMenus[screenName] = menu;
        activeTrayMenus = newMenus;
    }

    function unregisterMenu(screenName) {
        if (!screenName)
            return;
        const newMenus = Object.assign({}, activeTrayMenus);
        delete newMenus[screenName];
        activeTrayMenus = newMenus;
    }

    function closeHoverMenus() {
        for (const screenName in activeTrayMenus) {
            const menu = activeTrayMenus[screenName];
            if (!menu || menu.openedByHover !== true)
                continue;
            if (typeof menu.close === "function") {
                menu.close();
            } else if (menu.showMenu !== undefined) {
                menu.showMenu = false;
            }
        }
    }

    function closeAllMenus() {
        for (const screenName in activeTrayMenus) {
            const menu = activeTrayMenus[screenName];
            if (!menu)
                continue;
            if (typeof menu.close === "function") {
                menu.close();
            } else if (menu.showMenu !== undefined) {
                menu.showMenu = false;
            }
        }
    }

    function iconRequest(icon) {
        if (typeof icon !== "string" || !icon.includes("?path="))
            return null;
        const split = icon.split("?path=");
        if (split.length !== 2)
            return null;
        const name = split[0].substring(split[0].lastIndexOf("/") + 1);
        return {
            name: name,
            dir: split[1]
        };
    }

    function iconSourceFor(trayItem) {
        const icon = trayItem && trayItem.icon;
        if (typeof icon !== "string" || icon === "")
            return "";
        const request = iconRequest(icon);
        if (request)
            return `file://${request.dir}/${request.name}`;
        if (icon.startsWith("/"))
            return `file://${icon}`;
        return icon;
    }

    function resolveIconFallback(icon, callback) {
        const request = iconRequest(icon);
        if (!request || !/^[\w.+-]+$/.test(request.name)) {
            callback("");
            return;
        }
        const cached = _iconFallbacks[icon];
        if (cached) {
            callback(cached);
            return;
        }
        const waiters = _iconFallbackWaiters[icon];
        if (waiters) {
            waiters.push(callback);
            return;
        }
        _iconFallbackWaiters[icon] = [callback];
        Proc.runCommand(null, ["find", "-L", request.dir, "-maxdepth", "4", "-type", "f", "-name", `${request.name}.*`], out => {
            const index = IconIndex.create();
            for (const path of (out || "").split("\n")) {
                if (path)
                    IconIndex.add(index, path, [request.dir], [request.dir]);
            }
            const found = index.paths[request.name];
            const url = found ? Paths.toFileUrl(found) : Paths.themedIconPath(request.name);
            if (url)
                _iconFallbacks[icon] = url;
            const pending = _iconFallbackWaiters[icon] || [];
            delete _iconFallbackWaiters[icon];
            for (const waiter of pending)
                waiter(url);
        }, 0);
    }

    function callContextMenuFallback(trayItemId, globalX, globalY) {
        const script = ['ITEMS=$(dbus-send --session --print-reply --dest=org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.freedesktop.DBus.Properties.Get string:org.kde.StatusNotifierWatcher string:RegisteredStatusNotifierItems 2>/dev/null)', 'while IFS= read -r line; do', '  line="${line#*\\\"}"', '  line="${line%\\\"*}"', '  [ -z "$line" ] && continue', '  BUS="${line%%/*}"', '  OBJ="/${line#*/}"', '  ID=$(dbus-send --session --print-reply --dest="$BUS" "$OBJ" org.freedesktop.DBus.Properties.Get string:org.kde.StatusNotifierItem string:Id 2>/dev/null | grep -oP "(?<=\\\")(.*?)(?=\\\")" | tail -1)', '  if [ "$ID" = "$1" ]; then', '    dbus-send --session --type=method_call --dest="$BUS" "$OBJ" org.kde.StatusNotifierItem.ContextMenu int32:"$2" int32:"$3"', '    exit 0', '  fi', 'done <<< "$ITEMS"',].join("\n");
        Quickshell.execDetached(["bash", "-c", script, "_", trayItemId, String(Math.round(globalX)), String(Math.round(globalY))]);
    }
}
