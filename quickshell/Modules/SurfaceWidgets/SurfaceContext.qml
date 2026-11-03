import QtQuick
import qs.Common
import qs.Services

QtObject {
    required property var host
    required property var config
    property string kind: "bar"
    property var centerSection: null
    readonly property string configId: config?.id ?? ""
    property var screen: host?.screen ?? null
    readonly property var hostWindow: host?.hostWindow ?? null
    property var axis: host?.axis ?? null
    readonly property bool isVertical: axis?.isVertical ?? false
    property real thickness: host?.effectiveBarThickness ?? config?.thickness ?? 48
    property real widgetThickness: host?.widgetThickness ?? thickness
    readonly property var hyprlandOverviewLoader: host.hyprlandOverviewLoader ?? null
    readonly property int notificationCount: host.notificationCount ?? 0
    readonly property bool revealed: host.reveal ?? host.isBarVisible ?? true
    readonly property bool live: revealed && !(IdleService.monitorsOff ?? false)
    readonly property bool editMode: host.editMode ?? false
    property real availableSize: isVertical ? (host?.height ?? 0) : (host?.width ?? 0)
    function screenPoint(item, x, y) {
        const window = item?.Window.window;
        if (!window || !screen)
            return null;
        const point = item.mapToItem(window.contentItem, x, y);
        const anchors = hostWindow?.anchors ?? {
            left: axis?.edge !== "right",
            right: axis?.edge !== "left",
            top: axis?.edge !== "bottom",
            bottom: axis?.edge !== "top"
        };
        const origin = ShellLayout.surfaceOrigin(screen, window.width, window.height, anchors, hostWindow?.margins);
        return Qt.point(point.x + origin.x, point.y + origin.y);
    }

    function popupAnchor(item, section, visual, width, record = true) {
        const owner = BarWidgetService.registrationForItem(item)?.context?.owner;
        if (owner?.overflowAnchor) {
            const anchor = popupAnchor(owner.overflowAnchor, section, null, undefined, record);
            const overflow = owner.overflowSurface;
            if (!anchor || !overflow?.shouldBeVisible)
                return anchor;
            const gap = Math.max(Theme.spacingXS, config?.spacing ?? Theme.spacingXS);
            switch (axis?.edge) {
            case "bottom":
                anchor.trigger.y = overflow.renderedAlignedY - gap;
                break;
            case "left":
                anchor.trigger.x = overflow.renderedAlignedX + overflow.renderedAlignedWidth + gap;
                break;
            case "right":
                anchor.trigger.x = overflow.renderedAlignedX - gap;
                break;
            default:
                anchor.trigger.y = overflow.renderedAlignedY + overflow.renderedAlignedHeight + gap;
                break;
            }
            return anchor;
        }
        const point = screenPoint(visual || item.visualContent || item, 0, visual && isVertical ? visual.height / 2 : 0);
        if (!point)
            return null;
        // Every bar widget popout anchors here, so this is where last-used routing learns which bar was clicked.
        if (kind === "bar" && record)
            SettingsData.recordBarInteraction(screen, config?.id);
        const position = config?.position ?? 0;
        const spacing = config?.spacing ?? 4;
        const triggerWidth = width ?? (visual ? (isVertical ? visual.height : visual.width) : item.visualWidth ?? item.width);
        return {
            trigger: SettingsData.getPopupTriggerPosition(point, screen, thickness, triggerWidth, spacing, position, config),
            screen,
            section: section || item.section || "center",
            position,
            thickness,
            spacing,
            config
        };
    }

    function positionPopout(popout, item, section, visual, width, record = true) {
        const anchor = popupAnchor(item, section, visual, width, record);
        if (!anchor || !popout?.setTriggerPosition)
            return false;
        const trigger = anchor.trigger;
        popout.setTriggerPosition(trigger.x, trigger.y, trigger.width, anchor.section, screen, anchor.position, thickness, anchor.spacing, config, item);
        return true;
    }

    function ensureVisible(item) {
        if (host && typeof host.revealWidgetItem === "function")
            host.revealWidgetItem(item);
    }
    readonly property bool inlineExpansion: kind === "dock" && config?.widgetExpansion === "inline"
    function requestExpansion(item) {
        if (kind !== "dock" || !host.openExpansion)
            return false;
        return host.openExpansion(item);
    }
    function dismissExpansion() {
        if (kind === "dock" && host.closeExpansion)
            host.closeExpansion();
    }
}
