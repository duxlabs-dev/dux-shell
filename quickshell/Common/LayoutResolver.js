.pragma library

const edges = ["top", "bottom", "left", "right"];

function edgeName(position) {
    return typeof position === "number" ? (edges[position] ?? "") : "";
}

function option(config, key, defaults, fallback) {
    return config?.[key] === undefined ? (defaults?.[key] ?? fallback) : config[key];
}

function screenModelIndex(screen, screens) {
    if (!screen?.model)
        return -1;
    const matches = screens.filter(candidate => candidate.model === screen.model).slice().sort((a, b) => a.x - b.x || a.y - b.y);
    return matches.length > 1 ? matches.findIndex(candidate => candidate.name === screen.name) : -1;
}

function screenMatches(screen, preferences, screens, displayNameMode) {
    if (!screen)
        return false;
    const modelIndex = screenModelIndex(screen, screens);
    const displayName = displayNameMode === "model" && screen.model ? screen.model + (modelIndex >= 0 ? "-" + modelIndex : "") : screen.name;
    return preferences.some(pref => {
        if (typeof pref === "string")
            return pref === "all" || pref === screen.name || pref === (displayNameMode === "model" ? displayName : screen.model);
        if (displayNameMode !== "model")
            return pref.name === screen.name;
        return !!pref.model && !!screen.model && pref.model === screen.model && (pref.modelIndex === undefined || pref.modelIndex === modelIndex);
    });
}

function coversScreen(config, screen, screens, displayNameMode) {
    if ((config?.hideOnLastDisplay ?? false) && screens.length === 1)
        return false;
    const preferences = config?.screenPreferences || ["all"];
    return preferences.includes("all") || screenMatches(screen, preferences, screens, displayNameMode) || ((config?.showOnLastDisplay ?? false) && screens.length === 1);
}

function islandMetrics(config, defaults) {
    const value = key => config?.[key] ?? defaults[key];
    const strip = Math.max(24, Math.min(128, value("islandReserveThickness")));
    const compact = Math.max(24, Math.min(72, value("islandCompactThickness")));
    const gap = value("islandNotch") ? 0 : Math.max(0, Math.min(48, value("islandOuterGap")));
    const thickness = Math.max(strip, gap + compact);
    // The default reservation follows the pill itself, so windows stop right under it at any pill size;
    // the default strip only pads the painted band. Any other value is reserved as set.
    return {
        reserve: value("islandReserveThickness") === defaults.islandReserveThickness ? gap + compact : strip,
        compact,
        gap,
        thickness
    };
}

function islandThickness(config, defaults) {
    return islandMetrics(config, defaults).thickness;
}

function islandReserve(config, defaults) {
    return islandMetrics(config, defaults).reserve;
}

function isIsland(config) {
    return config.island === true || config.dot === true;
}

// First island entry across the sections, the same one SettingsData.islandWidgetEntry reads.
function hostsIslandWidget(config) {
    for (const key of ["leftWidgets", "centerWidgets", "rightWidgets"]) {
        const entry = (config?.[key] ?? []).find(entry => (typeof entry === "string" ? entry : entry?.id) === "island");
        if (entry !== undefined)
            return typeof entry === "string" || entry.enabled !== false;
    }
    return false;
}

function overviewStandInHost(input, selected) {
    const config = input.config;
    if (isIsland(config) || config.visible !== false || !config.openOnOverview)
        return null;
    return selected.find(other => !isIsland(other.config) && !other.config.openOnOverview) ?? null;
}

function resolveScreen(inputs, screen, options) {
    const assigned = inputs.filter(input => coversScreen(input.config, screen, options.screens, options.displayNameMode));
    const enabled = assigned.filter(input => input.config.enabled);
    const bars = enabled.filter(input => !isIsland(input.config));
    // One island surface per screen: an island-layout bar owns it, else the first bar hosting the island widget.
    const hostOwner = enabled.some(input => input.config.island === true) ? null : bars.find(input => hostsIslandWidget(input.config)) ?? null;
    const islands = enabled.filter(input => isIsland(input.config)).concat(hostOwner ? [hostOwner] : []);
    const frameConfigured = screenMatches(screen, options.framePreferences, options.screens, options.displayNameMode);
    const frameStyled = options.effectiveFrameEnabled && frameConfigured;
    const frameHosted = options.effectiveConnected && frameStyled;
    const bands = {};
    const instances = [];
    // Free islands and dots float anywhere on the screen, so they never join an edge band.
    const isFree = input => input.config.dot === true || (isIsland(input.config) && (input.islandPlacement ?? input.config.islandPlacement) === "free");
    for (const input of enabled.filter(isFree)) {
        const dot = input.config.dot === true;
        // A free island keeps its satellites in a bar window on its configured edge; that band never reserves or shadows.
        const satellites = !dot && (input.islandSatellites ?? input.config.islandSatellitesEnabled ?? true);
        instances.push({
            key: JSON.stringify([screen.name, input.config.id]),
            screenName: screen.name,
            barId: input.config.id,
            configOrder: inputs.indexOf(input),
            edge: "",
            kind: "island",
            free: true,
            dot,
            hostsIsland: true,
            satelliteEdge: satellites ? edgeName(input.config.position ?? 0) || "top" : "",
            row: 0,
            rowThickness: 0,
            rowOffset: 0,
            reservation: 0,
            exclusiveZone: -1,
            exclusionSize: 0,
            paintedBounds: {
                x: 0,
                y: 0,
                width: 0,
                height: 0
            },
            margins: {
                top: 0,
                bottom: 0,
                left: 0,
                right: 0
            }
        });
    }
    for (const edge of edges) {
        const selected = enabled.filter(input => !isFree(input) && (edgeName(input.config.position ?? 0) || "top") === edge);
        const active = selected.filter(input => !isIsland(input.config));
        const shown = active.filter(input => input.config.visible !== false);
        const hosted = active.filter(input => !input.config.useOverlayLayer);
        let offset = 0;
        let reservation = 0;
        const rowOffsets = new Map();
        const place = (input, rowOffset) => {
            const config = input.config;
            const kind = isIsland(config) ? "island" : frameHosted && !config.useOverlayLayer ? "frame" : "bar";
            const spacing = frameStyled || config.attachToScreenEdge || (input.flattened && !options.effectiveFrameEnabled) ? 0 : config.spacing ?? 4;
            const thickness = kind === "island" ? input.islandThickness : frameStyled ? Math.round(Math.round(options.frameBarSize * (screen.scale || 1)) / (screen.scale || 1)) : input.barThickness + spacing + (config.bottomGap ?? 0);
            const paintedThickness = thickness + (kind !== "island" && !frameStyled ? input.wingSize ?? 0 : 0);
            const reserves = kind === "island" ? !(input.islandFloating ?? config.islandFloating) : config.visible !== false && (!config.autoHide || frameStyled);
            const reserved = kind === "island" ? Math.min(thickness, input.islandReserve) : thickness;
            const contribution = reserves ? Math.max(0, rowOffset + reserved - reservation) : 0;
            instances.push({
                key: JSON.stringify([screen.name, config.id]),
                screenName: screen.name,
                barId: config.id,
                configOrder: inputs.indexOf(input),
                edge,
                kind,
                hostsIsland: kind === "island" || input === hostOwner,
                row: selected.indexOf(input),
                rowThickness: paintedThickness,
                rowOffset,
                reservation: contribution
            });
            reservation += contribution;
            rowOffsets.set(input, rowOffset);
            return paintedThickness;
        };
        const standIns = frameStyled ? [] : selected.filter(input => overviewStandInHost(input, selected));
        for (const input of selected) {
            if (standIns.includes(input))
                continue;
            offset += place(input, offset);
        }
        for (const input of standIns)
            place(input, rowOffsets.get(overviewStandInHost(input, selected)));
        const island = selected.find(input => isIsland(input.config));
        bands[edge] = {
            island: island?.config ?? null,
            islandThickness: selected.filter(input => isIsland(input.config)).reduce((sum, input) => sum + input.islandThickness, 0),
            bars: active.map(input => input.config),
            hostedBars: hosted.map(input => input.config),
            occupancy: offset,
            reservation: Math.max(frameStyled ? options.frameThickness : 0, reservation),
            frameReservation: shown.length ? Math.max(options.frameThickness, offset) : options.frameThickness,
            overviewFrameReservation: active.length ? Math.max(options.frameThickness, offset) : options.frameThickness,
            frameExclusionEnabled: frameStyled && (!shown.length || (frameHosted && !shown.some(input => input.config.useOverlayLayer)))
        };
    }
    const stacked = edges.some(edge => instances.filter(instance => instance.edge === edge).length > 1);
    const contests = instance => instance.kind !== "island" || instance.reservation > 0;
    const occupies = sides => instances.some(instance => sides.includes(instance.edge) && contests(instance));
    // compositors give a shared corner to whichever exclusive zone they arrange first, which follows map order and layer
    const sharedCorner = !frameStyled && occupies(["top", "bottom"]) && occupies(["left", "right"]);
    const manualPlacement = stacked || sharedCorner;
    if (!manualPlacement && frameStyled) {
        for (const instance of instances) {
            if (instance.kind !== "island" || instance.free)
                continue;
            const band = bands[instance.edge];
            instance.rowOffset += options.frameThickness;
            band.occupancy += options.frameThickness;
            band.reservation = options.frameThickness + instance.reservation;
        }
    }
    for (const edge of edges)
        bands[edge].tuck = stacked || frameStyled ? bands[edge].occupancy : bands[edge].reservation;
    for (const instance of instances) {
        instance.manualPlacement = stacked || (sharedCorner && instance.reservation > 0);
        if (instance.free)
            continue;
        const band = bands[instance.edge];
        instance.exclusiveZone = instance.manualPlacement || instance.kind === "frame" ? -1 : instance.reservation || -1;
        instance.exclusionSize = manualPlacement && !frameStyled && instance.row === 0 ? band.reservation : 0;
        instance.paintedBounds = rowBounds(screen, instance.edge, instance.rowOffset, instance.rowThickness, bands);
        instance.margins = {
            top: 0,
            bottom: 0,
            left: 0,
            right: 0
        };
        if (!instance.manualPlacement)
            continue;
        instance.margins[instance.edge] = instance.rowOffset;
        if (instance.edge === "left" || instance.edge === "right") {
            instance.margins.top = bands.top.tuck;
            instance.margins.bottom = bands.bottom.tuck;
        }
    }
    if (manualPlacement && frameStyled) {
        for (const edge of edges)
            bands[edge].frameExclusionEnabled = true;
    }
    instances.sort((a, b) => a.configOrder - b.configOrder);
    return {
        screen,
        assigned,
        bars,
        islands,
        instances,
        edges: bands,
        frameConfigured,
        frameStyled,
        manualPlacement
    };
}

function hostsBarWindow(instance) {
    return instance.free ? !!instance.satelliteEdge : instance.kind === "bar" || instance.kind === "island";
}

function adjacentBar(layout, edge, config) {
    if (!layout || config?.autoHide)
        return null;
    const position = edges.indexOf(edge);
    return layout.bars.find(input => input.config.id !== config?.id && !input.config.autoHide && (input.config.visible ?? true) && input.config.position === position) ?? null;
}

function adjacentInfo(layout, config, defaults, includeAutoHide) {
    const result = {
        topBar: 0,
        bottomBar: 0,
        leftBar: 0,
        rightBar: 0
    };
    if (!layout || !config || config.autoHide)
        return result;
    for (const edge of edges) {
        const rows = layout.instances.filter(instance => instance.edge === edge && instance.barId !== config.id);
        result[edge + "Bar"] = rows.reduce((sum, instance) => {
            const input = layout.assigned.find(input => input.config.id === instance.barId);
            const other = input.config;
            if (instance.kind === "island")
                return sum + instance.rowThickness;
            if (other.visible === false || (other.autoHide && !includeAutoHide))
                return sum;
            const spacing = option(other, "spacing", defaults, 4);
            const gap = option(other, "popupGapsAuto", defaults, true) ? Math.max(4, spacing) : option(other, "popupGapsManual", defaults, 4);
            return sum + input.popupThickness + spacing + gap;
        }, 0);
    }
    return result;
}

function barBounds(layout, thickness, position, config, defaults, connected, wingSize) {
    const empty = {
        x: 0,
        y: 0,
        width: 0,
        height: 0,
        wingSize: 0
    };
    if (!layout || !edgeName(position))
        return empty;
    const instance = layout.instances.find(instance => instance.barId === config?.id);
    return Object.assign(rowBounds(layout.screen, edgeName(position), instance?.rowOffset ?? 0, thickness + wingSize, layout.edges), {
        wingSize
    });
}

function rowBounds(screen, edge, offset, thickness, bands) {
    const horizontal = edge === "top" || edge === "bottom";
    const width = horizontal ? screen.width : thickness;
    const height = horizontal ? thickness : Math.max(0, screen.height - bands.top.tuck - bands.bottom.tuck);
    return {
        x: horizontal ? 0 : edge === "right" ? screen.width - width - offset : offset,
        y: horizontal ? edge === "bottom" ? screen.height - height - offset : offset : bands.top.tuck,
        width,
        height
    };
}

function surfaceOrigin(layout, width, height, anchors, margins) {
    const screen = layout.screen;
    const left = margins?.left ?? 0;
    const right = margins?.right ?? 0;
    const top = margins?.top ?? 0;
    const bottom = margins?.bottom ?? 0;
    let x = anchors.right && !anchors.left ? screen.width - width - right : left;
    let y = anchors.bottom && !anchors.top ? screen.height - height - bottom : top;
    if (anchors.left && anchors.right)
        x += Math.min(Math.max(0, screen.width - width - left - right), layout.edges?.left?.reservation ?? 0);
    if (anchors.top && anchors.bottom)
        y += Math.min(Math.max(0, screen.height - height - top - bottom), layout.edges?.top?.reservation ?? 0);
    return {
        x,
        y
    };
}

function popupTrigger(pos, screen, thickness, width, spacing, position, config, defaults, connected) {
    const bottomGap = connected ? 0 : Math.max(0, option(config, "bottomGap", defaults, 0));
    const autoGap = option(config, "popupGapsAuto", defaults, true);
    const gap = connected ? 0 : autoGap ? Math.max(4, spacing) : option(config, "popupGapsManual", defaults, 4);
    const offset = thickness + (connected ? 0 : spacing) + gap;
    switch (position) {
    case 2:
        return {
            x: offset,
            y: pos.y,
            width
        };
    case 3:
        return {
            x: (screen?.width || 0) - offset,
            y: pos.y,
            width
        };
    case 1:
        return {
            x: pos.x,
            y: (screen?.height || 0) - offset - bottomGap,
            width
        };
    default:
        return {
            x: pos.x,
            y: offset + bottomGap,
            width
        };
    }
}

function availablePositions(layouts, config) {
    return [0, 1, 2, 3];
}
