pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import "../Common/InstanceRegistry.js" as Registry

Singleton {
    id: root

    property var widgetRegistry: ({})
    property var onDemandWidgetIds: []
    property var dankBarRepeater: null

    property var frameHostedBars: ({})

    signal dockEditRequested(string dockId)

    property var dockContextMenu: null
    property var dockTrashContextMenu: null

    function registerFrameBar(screenName, barId, body) {
        if (!screenName || !barId || !body)
            return;
        const next = Object.assign({}, frameHostedBars);
        const bars = Object.assign({}, next[screenName] ?? {});
        bars[barId] = body;
        next[screenName] = bars;
        frameHostedBars = next;
    }

    function unregisterFrameBar(screenName, barId, body) {
        if (!screenName || !barId || frameHostedBars[screenName]?.[barId] !== body)
            return;
        const next = Object.assign({}, frameHostedBars);
        const bars = Object.assign({}, next[screenName]);
        delete bars[barId];
        if (Object.keys(bars).length === 0)
            delete next[screenName];
        else
            next[screenName] = bars;
        frameHostedBars = next;
    }

    function frameBarsForScreen(screenName) {
        const bars = frameHostedBars[screenName] ?? {};
        const order = SettingsData.barConfigs.map(cfg => cfg.id);
        const vertical = barId => {
            const position = SettingsData.getBarConfig(barId)?.position ?? SettingsData.Position.Top;
            return (position === SettingsData.Position.Left || position === SettingsData.Position.Right) ? 1 : 0;
        };
        return Object.keys(bars).sort((a, b) => (vertical(a) - vertical(b)) || (order.indexOf(a) - order.indexOf(b))).map(barId => bars[barId]);
    }

    property var dankBarItems: ({})

    function registerDankBarItem(barId, item) {
        if (!barId || !item)
            return;
        const next = Object.assign({}, dankBarItems);
        next[barId] = item;
        dankBarItems = next;
    }

    function unregisterDankBarItem(barId, item) {
        if (!barId || dankBarItems[barId] !== item)
            return;
        const next = Object.assign({}, dankBarItems);
        delete next[barId];
        dankBarItems = next;
    }

    signal widgetRegistered(string widgetId, string screenName)
    signal widgetUnregistered(string widgetId, string screenName)

    property int _legacySerial: 0

    function registerWidget(widgetId, screenName, widgetRef, instanceId, context) {
        if (!widgetId || !screenName || !widgetRef)
            return null;
        const previous = Object.values(widgetRegistry).find(entry => entry.item === widgetRef && entry.widgetId === widgetId && entry.screenName === screenName);
        const identity = instanceId || previous?.instanceId || "legacy:" + (++_legacySerial);
        const registration = {
            key: Registry.key(screenName, identity),
            widgetId,
            screenName,
            instanceId: identity,
            item: widgetRef,
            context: context ?? null
        };
        widgetRegistry = Object.assign({}, widgetRegistry, {
            [registration.key]: registration
        });
        widgetRegistered(widgetId, screenName);
        return registration;
    }

    function releaseWidget(registration) {
        const next = Registry.release(widgetRegistry, registration);
        if (next === widgetRegistry)
            return;
        widgetRegistry = next;
        widgetUnregistered(registration.widgetId, registration.screenName);
    }

    function unregisterWidget(widgetId, screenName, widgetRef, instanceId) {
        if (!widgetRef)
            return;
        const registration = Object.values(widgetRegistry).find(entry => entry.widgetId === widgetId && entry.screenName === screenName && entry.item === widgetRef && (!instanceId || entry.instanceId === instanceId));
        releaseWidget(registration);
    }

    function registrationForItem(sourceItem) {
        const entries = Object.values(widgetRegistry);
        for (let item = sourceItem; item; item = item.parent) {
            const entry = entries.find(entry => entry.item === item || entry.context?.owner === item);
            if (entry)
                return entry;
        }
        return null;
    }

    function registrationActive(entry, includeHidden = false) {
        return registrationLive(entry, includeHidden) && entry.item.effectiveVisible !== false;
    }

    function registrationShown(entry) {
        return registrationActive(entry) && entry.context?.owner?.widgetEnabled !== false;
    }

    function registrationLive(entry, includeHidden = false) {
        if (!entry?.item || widgetRegistry[entry.key] !== entry)
            return false;
        const context = entry.context;
        if (!context?.surface?.screen)
            return true;
        if (!context.owner?.active || context.surface.config.enabled === false)
            return false;
        if (!includeHidden && context.surface.config.visible === false && !(context.surface.host?.barRevealed ?? context.surface.revealed))
            return false;
        if (context.kind === "dock")
            return SettingsData.dockConfigsForScreen(context.surface.screen).some(config => config.id === context.barId);
        return ShellLayout.forScreen(entry.screenName)?.instances.some(instance => instance.barId === context.barId) === true;
    }

    // IPC passes includeHidden: a hidden bar's widget still opens, anchored where the bar sits.
    function resolveWidget(widgetId, target, includeHidden = false) {
        const configs = SettingsData.barConfigs.concat(SettingsData.dockConfigs ?? []).map(config => config.id);
        const screens = Quickshell.screens.map(screen => screen.name);
        const select = eligible => Registry.select(widgetRegistry, widgetId, target, configs, screens, eligible);
        return select(registrationShown) ?? select(registrationLive) ?? (includeHidden ? select(entry => registrationLive(entry, true)) : null);
    }

    // Matches getPreferredBar in DMSShellIPC: focused screen, then visible before hidden, then the last used bar.
    function resolveIpcWidget(widgetId) {
        const configs = SettingsData.barConfigs.concat(SettingsData.dockConfigs ?? []).map(config => config.id);
        const screens = Quickshell.screens.map(screen => screen.name);
        const screenName = getFocusedScreenName();
        const lastBarId = screenName ? SettingsData.lastUsedBarByScreen[screenName] : "";
        const tiers = [registrationShown, registrationLive, entry => registrationLive(entry, true)];
        const focusedTargets = screenName ? [
            {
                screenName,
                barId: lastBarId
            },
            {
                screenName
            }
        ] : [];
        for (const targets of [focusedTargets, [{}]]) {
            for (const eligible of tiers) {
                for (const target of targets) {
                    const hit = Registry.select(widgetRegistry, widgetId, target, configs, screens, eligible);
                    if (hit)
                        return hit;
                }
            }
        }
        return null;
    }

    function getWidget(widgetId, screenName, instanceId) {
        return resolveWidget(widgetId, {
            screenName,
            instanceId
        })?.item ?? null;
    }

    function getWidgetInstance(widgetId, target) {
        if (!target?.screenName || !target.barId || !target.section || !target.occurrenceId)
            return null;
        return resolveWidget(widgetId, target)?.item ?? null;
    }

    function naturalPopoutAnchor(screen, sourceItem, section) {
        const source = registrationForItem(sourceItem);
        if (source?.context?.kind !== "dock" && source?.context?.surface?.popupAnchor)
            return source.context.surface.popupAnchor(source.item, section);
        const widget = source ? resolveWidget(source.widgetId, {
            screenName: screen?.name,
            kind: "bar"
        })?.item : null;
        const context = registrationForItem(widget)?.context?.surface;
        if (context?.popupAnchor)
            return context.popupAnchor(widget, widget.section || section);
        const bar = getBarWindowForScreen(screen?.name);
        const config = widget?.barConfig ?? bar?.barConfig ?? null;
        const position = config?.position ?? SettingsData.Position.Top;
        const thickness = widget?.barThickness ?? bar?.effectiveBarThickness ?? Theme.barHeight;
        const spacing = widget?.barSpacing ?? config?.spacing ?? Theme.spacingXS;
        const targetSection = widget?.section ?? section ?? "center";
        const vertical = position === SettingsData.Position.Left || position === SettingsData.Position.Right;
        const fraction = targetSection === "left" ? 0 : targetSection === "right" ? 1 : 0.5;
        const visual = widget?.visualContent ?? widget;
        const point = visual ? visual.mapToItem(null, 0, 0) : Qt.point(vertical ? (position === SettingsData.Position.Left ? 0 : screen.width - thickness) : screen.width * fraction, vertical ? screen.height * fraction : (position === SettingsData.Position.Top ? 0 : screen.height - thickness));
        const width = widget?.visualWidth ?? widget?.width ?? 0;
        const trigger = SettingsData.getPopupTriggerPosition(point, screen, thickness, width, spacing, position, config);
        return {
            trigger,
            section: targetSection,
            position,
            thickness,
            spacing,
            config
        };
    }

    function getWidgetOnFocusedScreen(widgetId) {
        return resolveIpcWidget(widgetId)?.item ?? null;
    }

    readonly property bool focusedScreenDetectionSupported: (CompositorService.isAqueous && AqueousService.available) || CompositorService.isHyprland || CompositorService.isNiri || CompositorService.isMango || CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle || CompositorService.isUmbriel

    function getFocusedScreenName() {
        return CompositorService.getFocusedScreenName();
    }

    function getRegisteredWidgetIds() {
        if (typeof widgetRegistry !== "object" || widgetRegistry === null)
            return [];
        return [...new Set(Object.values(widgetRegistry).map(entry => entry.widgetId))];
    }

    function hasWidget(widgetId) {
        return resolveIpcWidget(widgetId) !== null;
    }

    function ensureWidget(widgetId) {
        if (!hasWidget(widgetId) && !onDemandWidgetIds.includes(widgetId))
            onDemandWidgetIds = [...onDemandWidgetIds, widgetId];
        return hasWidget(widgetId);
    }

    function triggerWidgetPopout(widgetId, target) {
        const widget = target ? resolveWidget(widgetId, target, true)?.item : getWidgetOnFocusedScreen(widgetId);
        if (!widget)
            return false;

        const registration = registrationForItem(widget);
        registration?.context?.surface?.ensureVisible(widget);
        if (typeof widget.triggerPopout === "function") {
            widget.triggerPopout();
            return true;
        }

        const signalMap = {
            "battery": "toggleBatteryPopup",
            "vpn": "toggleVpnPopup",
            "layout": "toggleLayoutPopup",
            "clock": "clockClicked",
            "cpuUsage": "cpuClicked",
            "memUsage": "ramClicked",
            "cpuTemp": "cpuTempClicked",
            "gpuTemp": "gpuTempClicked"
        };

        const signalName = signalMap[widgetId];
        if (signalName && typeof widget[signalName] === "function") {
            widget[signalName]();
            return true;
        }

        if (typeof widget.clicked === "function") {
            widget.clicked();
            return true;
        }

        if (widget.popoutTarget?.toggle) {
            widget.popoutTarget.toggle();
            return true;
        }

        return false;
    }

    function barsForScreen(screenName, barId) {
        const bars = [];
        for (const config of SettingsData.barConfigs) {
            if (barId && config.id !== barId)
                continue;
            const instance = ShellLayout.forScreen(screenName)?.instances.find(instance => instance.barId === config.id);
            if (!instance || instance.kind === "island")
                continue;
            const item = instance.kind === "frame" ? frameHostedBars[screenName]?.[config.id] : dankBarItems[config.id]?.barVariants?.instances.find(bar => bar.modelData?.name === screenName);
            if (item)
                bars.push(item);
        }
        return bars.sort((a, b) => Number(a.isVertical) - Number(b.isVertical));
    }

    function getBarWindowForScreen(screenName, barId) {
        return barsForScreen(screenName, barId)[0] ?? null;
    }

    function getBarWindowOnFocusedScreen() {
        return getBarWindowForScreen(getFocusedScreenName()) || getFirstBarWindow();
    }

    function getFirstBarWindow() {
        for (const screen of Quickshell.screens) {
            const bar = getBarWindowForScreen(screen.name);
            if (bar)
                return bar;
        }
        return null;
    }
}
