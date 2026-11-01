pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import "SegmentRoles.js" as SegmentRoles
import "OverflowLayout.js" as OverflowLayout

Item {
    id: root

    property var barContent: null
    property var surfaceContext: barContent?.surfaceContext ?? null
    property var widgetsModel: barContent?.[section + "WidgetsModel"] ?? null
    property var components: barContent?.allComponents ?? null
    property bool noBackground: barConfig?.noBackground ?? false
    required property var axis
    property string section: "center"
    property var parentScreen: barContent?.barWindow?.screen ?? null
    property real widgetThickness: barContent?.barWindow?.widgetThickness ?? 30
    property real barThickness: barContent?.barWindow?.effectiveBarThickness ?? 48
    property real barSpacing: barConfig?.spacing ?? 4
    property var barConfig: barContent?.barConfig ?? null
    property var blurBarWindow: barContent?.blurBarWindow ?? null
    property real sectionAvailablePrimarySize: 0
    property bool overrideAxisLayout: false
    property bool forceVerticalLayout: false
    property bool edgeIsScreenEdge: true
    property real crossEdgeExtension: 0
    property string widgetStyle: BarMetrics.widgetStyle(barConfig)
    property var roles: []
    property string overflowSegmentRole: "solo"
    property var entryRepeater: null
    property int entryRevision: 0
    readonly property alias parkingHost: parkingHost
    readonly property var overflowIndices: barContent?.overflowPlan?.hidden?.[section] ?? []
    readonly property string overflowDefaultMode: barConfig?.[section + "OverflowMode"] === "bar" ? "bar" : "auto"
    readonly property int overflowPosition: Math.max(0, Math.min(entryRepeater?.count ?? 0, barConfig?.[section + "OverflowPosition"] ?? OverflowLayout.defaultPosition(section, entryRepeater?.count ?? 0)))
    readonly property var layoutEntries: {
        // Delegates incubate after count changes; entryRevision re-reads them once they land.
        root.entryRevision;
        const entries = [];
        for (let index = 0; index < (entryRepeater?.count ?? 0); index++) {
            const wrapper = entryRepeater.itemAt(index);
            entries.push({
                size: wrapper?.preferredSize ?? 0,
                min: wrapper?.minimumSize ?? 0,
                mode: wrapper?.overflowMode ?? "bar",
                priority: wrapper?.overflowPriority ?? 0
            });
        }
        return entries;
    }
    readonly property var inlineEntries: {
        root.entryRevision;
        const entries = [];
        for (let index = 0; index < (entryRepeater?.count ?? 0); index++)
            entries.push({
                size: entryRepeater.itemAt(index)?.primarySize ?? 0
            });
        return entries;
    }
    readonly property var allottedSizes: barContent?.overflowPlan?.sizes?.[section] ?? []
    readonly property var hiddenEntries: {
        root.entryRevision;
        const entries = [];
        for (let index = 0; index < (entryRepeater?.count ?? 0); index++) {
            const wrapper = entryRepeater.itemAt(index);
            if (wrapper?.available && wrapper.inOverflow)
                entries.push(wrapper);
        }
        return entries;
    }
    readonly property int overflowCount: hiddenEntries.length
    readonly property SectionOverflow overflowItem: overflowLoader.item as SectionOverflow
    readonly property var overflowButton: overflowItem?.button ?? null
    readonly property var overflowParent: overflowItem?.popupParent ?? null
    readonly property var overflowSurface: overflowItem?.popout ?? null
    readonly property bool overflowOpen: overflowItem?.open ?? false
    property real overflowButtonPosition: 0
    property bool overflowWanted: false
    readonly property real overflowTriggerSize: widgetThickness
    readonly property bool overflowBackground: {
        root.entryRevision;
        let barePills = 0;
        for (let index = 0; index < (entryRepeater?.count ?? 0); index++) {
            const wrapper = entryRepeater.itemAt(index);
            const item = wrapper?.available ? wrapper.widgetItem : null;
            if (!item || !("widgetBackground" in item))
                continue;
            if (item.widgetBackground)
                return true;
            barePills++;
        }
        return barePills === 0 && !noBackground;
    }
    readonly property var inlineOrder: {
        const layout = inlineLayout();
        return layout.indices.filter((index, position) => layout.sizes[position] !== null);
    }
    readonly property var leadingInlineItem: inlineItemAt(0)
    readonly property var trailingInlineItem: inlineItemAt(inlineOrder.length - 1)

    signal layoutRequested

    Connections {
        target: root.entryRepeater
        function onItemAdded(index, item) {
            root.entryRevision++;
        }
        function onItemRemoved(index, item) {
            root.entryRevision++;
        }
    }

    onLayoutEntriesChanged: requestOverflowLayout()
    onInlineEntriesChanged: layoutRequested()
    onOverflowIndicesChanged: layoutRequested()
    onOverflowPositionChanged: requestOverflowLayout()
    onOverflowTriggerSizeChanged: requestOverflowLayout()
    onWidgetSpacingChanged: requestOverflowLayout()

    function requestOverflowLayout() {
        layoutRequested();
        barContent?.requestOverflowLayout?.();
    }

    function inlineLayout() {
        return OverflowLayout.section(inlineEntries, hiddenEntries.map(entry => entry.occurrenceOrder), widgetSpacing, overflowTriggerSize, overflowPosition);
    }

    function inlineItemAt(position) {
        root.entryRevision;
        const index = inlineOrder[position];
        if (index === undefined)
            return null;
        if (index === -1)
            return overflowButton;
        return entryRepeater?.itemAt(index)?.widgetItem ?? null;
    }

    Item {
        id: parkingHost
        width: 0
        height: 0
        clip: true
    }

    Loader {
        id: overflowLoader
        // Unloading while the popup is open destroys its window mid-flight and leaves a stale surface.
        active: root.overflowCount > 0 || root.overflowWanted
        sourceComponent: Component {
            SectionOverflow {
                sectionContext: root
            }
        }
        onLoaded: root.layoutRequested()
    }

    readonly property bool isVertical: overrideAxisLayout ? forceVerticalLayout : (axis?.isVertical ?? false)
    readonly property bool segmented: widgetStyle === "segments" && !noBackground
    readonly property real outlineThickness: (barConfig?.widgetOutlineEnabled ?? false) ? (barConfig?.widgetOutlineThickness ?? Theme.outlineWidth) : 0
    readonly property real widgetSpacing: (segmented ? BarMetrics.segmentGap : noBackground ? BarMetrics.bareGap : BarMetrics.pillGap) + outlineThickness * 2

    function refreshBlur() {
        blurBarWindow?.refreshBlurRegion?.();
    }

    function roleAt(index) {
        if (!segmented)
            return "solo";
        return roles[index] ?? "solo";
    }

    function participation(wrapper, visible, item) {
        if (!wrapper || !visible || wrapper.width <= 0 || wrapper.height <= 0)
            return null;
        return !!item && "segmentRole" in item;
    }

    function applyRoles(entries, participating) {
        const allEntries = entries.slice();
        const allStates = participating.slice();
        if (overflowCount > 0) {
            allEntries.splice(overflowPosition, 0, {
                widgetId: "overflow"
            });
            allStates.splice(overflowPosition, 0, true);
        }
        const next = SegmentRoles.resolve(allEntries, allStates);
        const buttonRole = overflowCount > 0 ? next.splice(overflowPosition, 1)[0] : "solo";
        overflowSegmentRole = segmented ? buttonRole : "solo";
        if (next.join() !== roles.join())
            roles = next;
    }
}
