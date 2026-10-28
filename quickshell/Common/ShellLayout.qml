pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Services
import "LayoutResolver.js" as Resolver

Singleton {
    id: root

    readonly property var screens: Quickshell.screens.map(screen => ({
                name: screen.name,
                model: screen.model,
                x: screen.x,
                y: screen.y,
                width: screen.width,
                height: screen.height,
                scale: CompositorService.getScreenScale(screen)
            }))
    readonly property var primaryBar: SettingsData.getPrimaryBarConfig()
    property string maximizedScreens: ""
    readonly property var layouts: screens.map(screen => {
        const maximized = !!screen.name && root.maximizedScreens.split("\n").includes(screen.name);
        return Resolver.resolveScreen(SettingsData.barConfigs.map(config => {
            const flattened = maximized && (config.maximizeDetection ?? true);
            return {
                config,
                flattened,
                barThickness: Theme.barThickness(config.innerPadding ?? SettingsData.barInnerPaddingDefault, screen.scale),
                wingSize: config.gothCornersEnabled && !flattened && root.barSpansEdge(config) ? Math.max(0, config.gothCornerRadiusOverride ? config.gothCornerRadiusValue ?? 12 : Theme.windowRadius) : 0,
                popupThickness: Theme.barThickness(Resolver.option(config, "innerPadding", root.primaryBar, SettingsData.barInnerPaddingDefault), screen.scale),
                islandThickness: Resolver.islandThickness(SettingsData.islandSettings(config), SettingsData.islandDefaultsFor(config)),
                islandReserve: Resolver.islandReserve(SettingsData.islandSettings(config), SettingsData.islandDefaultsFor(config)),
                islandFloating: SettingsData.islandSetting(config, "islandFloating"),
                islandPlacement: SettingsData.islandFreePlacement(config) ? "free" : "edge",
                islandSatellites: SettingsData.islandSetting(config, "islandSatellitesEnabled")
            };
        }), screen, {
            screens: root.screens,
            displayNameMode: SettingsData.displayNameMode,
            framePreferences: SettingsData.frameScreenPreferences,
            effectiveFrameEnabled: FrameTransitionState.effectiveFrameEnabled,
            effectiveConnected: FrameTransitionState.effectiveConnectedFrameModeActive,
            frameThickness: SettingsData.frameThickness,
            frameBarSize: SettingsData.frameBarSize
        });
    })
    readonly property var islandKeys: layouts.reduce((keys, layout) => keys.concat(layout.instances.filter(instance => instance.hostsIsland && !instance.free).map(instance => instance.key)), [])
    readonly property var freeIslandKeys: layouts.reduce((keys, layout) => keys.concat(layout.instances.filter(instance => instance.free).map(instance => instance.key)), [])

    onScreensChanged: updateMaximizedScreens()
    Component.onCompleted: updateMaximizedScreens()

    Connections {
        target: CompositorService
        function onToplevelsChanged() {
            root.updateMaximizedScreens();
        }
        function onWorkspaceStateChanged() {
            root.updateMaximizedScreens();
        }
    }

    function updateMaximizedScreens() {
        maximizedScreens = Quickshell.screens.filter(screen => CompositorService.maximizedWindowOnScreen(screen.name)).map(screen => screen.name).join("\n");
    }

    function barSpansEdge(config) {
        return (config?.barLengthMode ?? "full") === "full" && (config?.barLengthPadding ?? 0) <= 0;
    }

    function forScreen(screen) {
        const name = typeof screen === "string" ? screen : screen?.name;
        return layouts.find(layout => layout.screen.name === name) ?? null;
    }

    function screenForName(name) {
        return Quickshell.screens.find(screen => screen.name === name) ?? null;
    }

    function instance(key) {
        const [screenName, barId] = JSON.parse(key);
        return forScreen(screenName)?.instances.find(instance => instance.barId === barId) ?? null;
    }

    function forConfig(screen, barId) {
        return forScreen(screen)?.instances.find(instance => instance.barId === barId) ?? null;
    }

    function edge(screen, side) {
        return forScreen(screen)?.edges[side] ?? null;
    }

    function assignedScreens(config) {
        return Quickshell.screens.filter(screen => coversScreen(config, screen));
    }

    function coversScreen(config, screen) {
        return Resolver.coversScreen(config, screen, screens, SettingsData.displayNameMode);
    }

    function standaloneScreens(barId) {
        return Quickshell.screens.filter(screen => forScreen(screen)?.instances.some(instance => instance.barId === barId && instance.kind === "bar"));
    }

    function hostedScreens(barId) {
        return Quickshell.screens.filter(screen => forScreen(screen)?.instances.some(instance => instance.barId === barId && Resolver.hostsBarWindow(instance)));
    }

    function frameKeys(screen) {
        const instances = forScreen(screen)?.instances ?? [];
        const order = ["left", "right", "top", "bottom"];
        return instances.filter(instance => instance.kind === "frame").sort((a, b) => order.indexOf(a.edge) - order.indexOf(b.edge)).map(instance => instance.key);
    }

    function barEdges(screen, overlayOnly) {
        return Resolver.edges.filter(side => edge(screen, side)?.bars.some(config => !overlayOnly || config.useOverlayLayer));
    }

    function islandConfigs(screen) {
        return forScreen(screen)?.islands.map(input => input.config) ?? [];
    }

    function frameReservation(screen, side) {
        const band = edge(screen, side);
        if (SettingsData.frameShowOnOverview && CompositorService.overviewActiveOnScreen(screen))
            return band?.overviewFrameReservation ?? 0;
        return band?.frameReservation ?? 0;
    }

    function frameContentInset(screen, barId, side) {
        const layout = forScreen(screen);
        const band = layout?.edges[side];
        if (!band?.occupancy)
            return null;
        const instance = forConfig(screen, barId);
        return Math.max(0, band.occupancy - (instance?.kind === "frame" ? 0 : instance?.margins[side] ?? 0));
    }

    function adjacentBar(screen, side, config) {
        return Resolver.adjacentBar(forScreen(screen), side, config);
    }

    function dockAdjacentThickness(screen, side) {
        const layout = forScreen(screen);
        return (layout?.instances ?? []).filter(instance => instance.edge === side).reduce((sum, instance) => sum + instance.reservation, 0);
    }

    // non-manual layouts let the compositor stack exclusive zones, so the bar that was mapped later is the tucked one
    function adjacentCover(screen, side, config, length) {
        const layout = forScreen(screen);
        const neighbour = adjacentBar(screen, side, config);
        if (!layout || !neighbour)
            return null;
        const opposite = {
            top: "bottom",
            bottom: "top",
            left: "right",
            right: "left"
        }[side];
        const near = layout.edges[side].reservation;
        const far = adjacentBar(screen, opposite, config) ? layout.edges[opposite].reservation : 0;
        const deficit = (side === "top" || side === "bottom" ? layout.screen.height : layout.screen.width) - length;
        const order = id => layout.instances.find(instance => instance.barId === id)?.configOrder ?? 0;
        let tucked;
        if (deficit >= near + far - 1)
            tucked = true;
        else if (deficit < near - 1)
            tucked = false;
        else if (Math.abs(near - far) > 1)
            tucked = Math.abs(deficit - near) <= 1;
        else
            tucked = order(neighbour.config.id) < order(config?.id);
        return {
            reach: dockAdjacentThickness(screen, side),
            wing: neighbour.wingSize ?? 0,
            tucked
        };
    }

    function adjacentInfo(screen, config, includeAutoHide) {
        return Resolver.adjacentInfo(forScreen(screen), config, primaryBar, includeAutoHide);
    }

    function barBounds(screen, thickness, position, config) {
        const appearance = config ?? primaryBar;
        const radius = (appearance?.gothCornerRadiusOverride ?? false) ? (appearance?.gothCornerRadiusValue ?? 12) : Theme.windowRadius;
        const wing = (appearance?.gothCornersEnabled ?? false) && barSpansEdge(appearance) ? Math.max(0, radius) : 0;
        const edge = position === undefined ? (primaryBar?.position ?? 0) : position;
        return Resolver.barBounds(forScreen(screen), thickness, edge, config, primaryBar, SettingsData.connectedFrameModeActive, wing);
    }

    function surfaceOrigin(screen, width, height, anchors, margins) {
        return Resolver.surfaceOrigin(forScreen(screen) ?? {
            screen
        }, width, height, anchors, margins);
    }

    function popupTrigger(pos, screen, thickness, width, spacing, position, config) {
        const edge = position === undefined ? (primaryBar?.position ?? 0) : position;
        const gap = spacing === undefined ? (primaryBar?.spacing ?? 4) : spacing;
        const trigger = Resolver.popupTrigger(pos, screen, thickness, width, gap, edge, config, primaryBar, SettingsData.connectedFrameModeActive);
        const offset = forScreen(screen)?.instances.find(instance => instance.barId === config?.id)?.rowOffset ?? 0;
        switch (edge) {
        case 0:
            trigger.y += offset;
            break;
        case 1:
            trigger.y -= offset;
            break;
        case 2:
            trigger.x += offset;
            break;
        case 3:
            trigger.x -= offset;
            break;
        }
        return trigger;
    }

    function positionChoices(config) {
        return Resolver.availablePositions(layouts.filter(layout => coversScreen(config, layout.screen)), config);
    }
}
