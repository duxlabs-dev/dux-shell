import QtQuick
import qs.Common
import qs.DCommon.Common as DCommon
import qs.DCommon.Widgets
import qs.Modules.DBar
import qs.Modules.Plugins
import qs.Modules.SurfaceWidgets
import qs.Modules.Sysmon
import qs.Services
import "../../../Common/Format.js" as Format
import "../../../Services/Drives.js" as Drives
import "../../../Services/SysmonCatalog.js" as SysmonCatalog

BasePill {
    id: root

    property var widgetData: null

    readonly property string style: pick("style", SysmonCatalog.barChoices.style)
    readonly property string labelMode: pick("label", SysmonCatalog.barChoices.label)
    readonly property string colorMode: pick("colorMode", ["default", "primary", "secondary", "custom"])
    readonly property string separator: pick("separator", SysmonCatalog.barChoices.separator)
    readonly property string popoutStyle: pick("popout", SysmonCatalog.barChoices.popout)

    // A string, so the per-sample reassignment of diskMounts doesn't rebuild the entries.
    readonly property string mountPaths: (DgopService.diskMounts ?? []).map(e => e.mount).join("\n")
    // A mount that isn't mounted falls back to "/", then to the first mount.
    readonly property var shownMetrics: SysmonService.widgetMetrics(widgetData).filter(m => m.on).map(m => {
        const saved = m.mount ?? "";
        const mounts = mountPaths ? mountPaths.split("\n") : [];
        if (!saved || mounts.length === 0 || mounts.indexOf(saved) >= 0)
            return m;
        return Object.assign({}, m, {
            mount: mounts.indexOf("/") >= 0 ? "/" : mounts[0]
        });
    })
    readonly property var rows: source.rows
    readonly property bool hasNet: shownMetrics.some(m => SysmonCatalog.typeOf(m.device) === "net")
    // Rebuilt once per sample, not by a binding: its inputs are DgopService properties a sample assigns one by one.
    property var groups: []
    readonly property string idleText: I18n.tr("Idle", "device state")
    readonly property bool hiddenByIdle: groups.length === 0
    readonly property bool splitActive: separator === "separate" && !noBackground && groups.length > 1
    // Centers of the gaps between groups, along the bar in visualContent coordinates.
    property var bounds: []

    readonly property real iconSize: Theme.barIconSize(barThickness, undefined, barConfig?.maximizeWidgetIcons, barConfig?.iconScale)
    readonly property real textSize: Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)
    // One size for every number in a vertical pill, shrunk until the widest possible one fits across it.
    readonly property real numberSize: {
        if (!isVerticalOrientation)
            return textSize;
        const font = sizeProbe.font;
        const digit = DCommon.Fonts.widestDigit(font);
        let widest = 0;
        for (const m of shownMetrics) {
            for (const id of m.vals ?? [])
                widest = Math.max(widest, DCommon.Fonts.textWidth(font, reserveText(m, id, true).replace(/\d/g, digit)));
        }
        return widest > widgetThickness ? Math.max(Theme.fontSizeSmall / 2, Math.floor(textSize * widgetThickness / widest)) : textSize;
    }
    // The asleep word is wider than any number in some languages, so only that item shrinks to fit.
    readonly property real idleSize: {
        const width = DCommon.Fonts.textWidth(sizeProbe.font, idleText);
        return width > widgetThickness ? Math.max(Theme.fontSizeSmall / 2, Math.floor(textSize * widgetThickness / width)) : textSize;
    }
    readonly property color accent: colorMode === "custom" ? Theme.safeColor(option("customColor"), Theme.widgetIconColor) : colorMode === "default" ? Theme.widgetIconColor : Theme.roleColor(colorMode)

    // The devices of every System Monitor widget on this bar or dock, this one included, one per line.
    readonly property string hostDevices: {
        const c = barConfig ?? {};
        const lists = [[widgetData], SysmonCatalog.listOf(c.widgets) ?? []];
        for (const section of ["left", "center", "right", "island"])
            lists.push(SysmonCatalog.listOf(SettingsData.barSectionWidgets(c, section)) ?? []);
        const keys = [];
        for (const list of lists) {
            for (const e of list) {
                const entry = typeof e === "string" ? {
                    id: e
                } : e;
                if (!entry || typeof entry !== "object" || (entry.widgetId ?? entry.id) !== "sysmon" || entry.enabled === false)
                    continue;
                for (const m of SysmonService.widgetMetrics(entry)) {
                    if (m.on)
                        keys.push(deviceIdentity(m.device));
                }
            }
        }
        return keys.join("\n");
    }
    readonly property int hoveredGroup: {
        if (!hover.hovered)
            return 0;
        return groupAt(hover.point.position.x, hover.point.position.y);
    }
    readonly property string tooltipText: groups[hoveredGroup]?.tooltip ?? ""
    property bool tooltipShown: false
    // Set by the host; tells two pills of the same section apart.
    property string widgetInstanceId: widgetData?.id ?? ""
    // The host applies overflow and liveness after the widget is created, so data waits a turn.
    property bool settled: false

    signal activated(int row)

    // One group per shown row that isn't hidden by Hide when idle; a widget without rows shows a placeholder.
    function rebuildGroups() {
        if (shownMetrics.length === 0) {
            const dash = "—";
            groups = [{
                    index: 0,
                    items: [{
                            main: true,
                            plain: true,
                            icon: "monitoring",
                            text: dash,
                            vtext: dash
                        }],
                    name: "",
                    tooltip: I18n.tr("System Monitor", "sysmon bar widget without entries")
                }];
            return;
        }
        const out = [];
        shownMetrics.forEach((m, i) => {
            if (idleHidden(m))
                return;
            const r = rows[i] ?? null;
            out.push({
                index: i,
                items: buildItems(m, r),
                name: showName(m) ? nameText(m) : "",
                tooltip: rowTooltip(m, r)
            });
        });
        groups = out;
    }

    // A migrated "gpu:<pciId>" and a picked "gpu:<busId>" can name the same card.
    function deviceIdentity(key) {
        if (SysmonCatalog.typeOf(key) !== "gpu")
            return key;
        const g = SysmonService.gpuFor(SysmonService.parseKey(key).id);
        return g ? SysmonService.gpuEntry(g).key : key;
    }

    // One popout trigger per pill and row, the key the factory opens with and the hover controller compares.
    function triggerKey(row) {
        return "sysmon-" + (barConfig?.id ?? "default") + "-" + section + "-" + widgetInstanceId + "-" + row;
    }

    function option(key) {
        return SettingsData.widgetOption("sysmon", widgetData, key);
    }

    function pick(key, allowed) {
        const v = option(key);
        return allowed.indexOf(v) >= 0 ? v : SettingsData.widgetDefaults("sysmon")[key];
    }

    function typeOf(m) {
        return SysmonCatalog.typeOf(m.device);
    }

    function idleHidden(m) {
        return m.hideIdle === true && typeOf(m) === "net" && widgetData?.enabled !== false && Math.max(SysmonService.read(m.device, "down") ?? 0, SysmonService.read(m.device, "up") ?? 0) < 1024;
    }

    function hasTwin(m) {
        const key = deviceIdentity(m.device);
        const type = typeOf(m);
        return hostDevices.split("\n").some(k => k !== key && SysmonCatalog.typeOf(k) === type);
    }

    function showName(m) {
        return labelMode === "name" || labelMode === "both" || (labelMode === "icon" && hasTwin(m));
    }

    function nameText(m) {
        return m.mount || (hasTwin(m) ? SysmonService.displayName(m.device) : SysmonService.typeName(typeOf(m)));
    }

    function rowTooltip(m, r) {
        const name = m.mount || (r && !r.missing ? SysmonService.device(m.device)?.name : "") || SysmonService.typeName(typeOf(m));
        if (r?.asleep)
            return name + " · " + idleText;
        return [name].concat((r?.values ?? []).map(v => v.label + " " + wideText(m, v))).join(" · ");
    }

    function showsSize(m, id) {
        const type = typeOf(m);
        return m.percent === false && ((type === "memory" && id === "used") || (type === "gpu" && id === "vram"));
    }

    function sizeText(m, v) {
        if (!showsSize(m, v.id))
            return "";
        const type = typeOf(m);
        if (type === "memory")
            return Format.formatBytes(DgopService.usedMemoryKB * 1024, true);
        const kb = SysmonService.activeGpu(SysmonService.parseKey(m.device).id)?.memoryUsed;
        return kb != null ? Format.formatBytes(kb * 1024, true) : "";
    }

    function narrowSize(t) {
        return t.replace(/\s+/g, "").replace(/i?B$/, "");
    }

    function diskSizes(m) {
        if (m.mount) {
            const mt = (DgopService.diskMounts ?? []).find(e => e.mount === m.mount);
            return mt ? {
                avail: mt.avail || "—",
                size: mt.size || "—"
            } : null;
        }
        const s = Drives.usedSpace(DriveService.drives, DgopService.diskMounts, SysmonService.parseKey(m.device).id, "");
        return s?.total > 0 && s.used != null ? {
            avail: Drives.formatCapacity(s.total - s.used),
            size: Drives.formatCapacity(s.total)
        } : null;
    }

    function diskText(m, narrow) {
        const s = diskSizes(m);
        if (!s)
            return "";
        const shorten = t => narrow ? narrowSize(t) : t;
        switch (m.diskMode ?? 0) {
        case 1:
            return shorten(s.size);
        case 3:
            return narrow ? shorten(s.avail) : s.avail + " / " + s.size;
        }
        return shorten(s.avail);
    }

    function wideText(m, v) {
        if (v.value === null)
            return "—";
        if (v.kind === "rate") {
            if (m.compact === true)
                return Format.formatRateCompact(v.value, false);
            return v.value > 0 ? Format.formatRate(v.value, 1) : "0 B/s";
        }
        const size = sizeText(m, v);
        if (size)
            return size;
        if (typeOf(m) === "disk" && v.id === "space" && m.diskMode > 0)
            return diskText(m, false) || v.text;
        return v.text;
    }

    function narrowText(m, v) {
        if (v.value === null)
            return "—";
        switch (v.kind) {
        case "pct":
            if (typeOf(m) === "disk" && v.id === "space" && m.diskMode > 0)
                return diskText(m, true) || String(Math.round(v.value));
            return narrowSize(sizeText(m, v)) || String(Math.round(v.value));
        case "power":
            return Math.round(v.value) + "W";
        }
        return v.shortText;
    }

    // The widest text a value formats to, so the pill keeps its width as numbers change. The narrow form is the vertical text.
    function reserveText(m, id, narrow) {
        const kind = SysmonCatalog.valueDef(typeOf(m), id)?.kind ?? "";
        const samples = MonitorMetrics.sizeSamples;
        if (showsSize(m, id))
            return narrow ? narrowSize(samples.bytes) : samples.bytes;
        if (kind === "rate")
            return narrow || m.compact !== true ? MonitorMetrics.reserveFor("rate", narrow) : samples.compactRate;
        if (typeOf(m) === "disk" && id === "space" && m.diskMode > 0) {
            const one = m.mount ? samples.mount : samples.drive;
            return narrow ? narrowSize(one) : m.diskMode === 3 ? one + " / " + one : one;
        }
        const sample = MonitorMetrics.reserveFor(kind, narrow);
        if (!narrow)
            return sample;
        return kind === "pct" ? sample.replace("%", "") : kind === "power" ? sample.replace(/\s+/g, "") : sample;
    }

    function buildItems(m, r) {
        const idle = idleText;
        if (r?.asleep)
            return [{
                    main: true,
                    plain: true,
                    muted: true,
                    icon: "bedtime",
                    text: idle,
                    vtext: idle,
                    vsize: Math.min(numberSize, idleSize),
                    reserve: reserveText(m, m.vals?.[0], false)
                }];
        if (!r || r.missing)
            return [{
                    main: true,
                    plain: true,
                    icon: r?.icon ?? SysmonService.valueIcon(typeOf(m), ""),
                    text: "—",
                    vtext: "—",
                    reserve: reserveText(m, m.vals?.[0], false)
                }];
        const showIcon = labelMode === "icon" || labelMode === "both";
        const out = [];
        r.values.forEach((v, i) => {
            if (i > 0 && v.value === null)
                return;
            const rate = v.kind === "rate";
            out.push({
                main: i === 0,
                plain: style === "graph" && !!m.mount && v.id === "space",
                muted: false,
                icon: i === 0 ? (showIcon ? (v.kind === "temp" ? v.icon : r.icon) : "") : (rate ? "" : v.icon),
                dir: rate ? (v.id === "down" || v.id === "read" ? "down" : "up") : "",
                text: wideText(m, v),
                vtext: narrowText(m, v),
                reserve: reserveText(m, v.id, false),
                fraction: v.fraction,
                level: v.level,
                history: v.history,
                maximum: v.maximum
            });
        });
        return out;
    }

    // Position of the group under a point in pill coordinates; gaps belong to the nearer group.
    function groupAt(x, y) {
        const pos = mapToItem(visualContent, x, y);
        const along = isVerticalOrientation ? pos.y : pos.x;
        let i = 0;
        for (const b of bounds) {
            if (along >= b)
                i++;
        }
        return mirrored ? groups.length - 1 - i : i;
    }

    // Index into rows of the entry under a point in pill coordinates.
    function entryAt(x, y) {
        return groups[groupAt(x, y)]?.index ?? 0;
    }

    function showTooltip() {
        if (!parentScreen || barConfig?.hoverPopouts || popoutTarget?.shouldBeVisible)
            return;
        tooltipShown = true;
        tooltip.show(tooltipText, clickArea);
    }

    function hideTooltip() {
        tooltipShown = false;
        tooltip.hide();
    }

    Component.onCompleted: {
        rebuildGroups();
        Qt.callLater(() => root.settled = true);
        // A migrated GPU entry resolves its card from the GPU list.
        if (!SysmonCatalog.listOf(widgetData?.metrics) && Number.isInteger(widgetData?.selectedGpuIndex))
            DgopService.ensureMeta();
    }
    onRowsChanged: Qt.callLater(rebuildGroups)
    onShownMetricsChanged: Qt.callLater(rebuildGroups)
    onLabelModeChanged: Qt.callLater(rebuildGroups)
    onStyleChanged: Qt.callLater(rebuildGroups)
    onHostDevicesChanged: Qt.callLater(rebuildGroups)

    onIdleTextChanged: Qt.callLater(rebuildGroups)
    onIsMouseHoveredChanged: isMouseHovered ? showTooltip() : hideTooltip()
    onTooltipTextChanged: if (tooltipShown)
        tooltip.show(tooltipText, clickArea)

    splitOffsets: splitActive ? bounds : []
    splitJoined: BarMetrics.widgetStyle(barConfig) === "segments"
    splitGap: splitJoined ? BarMetrics.segmentGap : BarMetrics.pillGap
    splitBlurPerSegment: true

    width: hiddenByIdle ? 0 : (isVerticalOrientation ? barThickness : visualWidth)
    height: hiddenByIdle ? 0 : (isVerticalOrientation ? visualHeight : barThickness)
    opacity: hiddenByIdle ? 0 : 1
    visible: !hiddenByIdle || opacity > 0

    Accessible.role: Accessible.Button
    Accessible.name: groups.map(g => g.tooltip).join(", ")
    Accessible.onPressAction: root.activated(groups[0]?.index ?? 0)

    Behavior on width {
        enabled: root.hasNet
        DCommon.DAnim {}
    }

    Behavior on height {
        enabled: root.hasNet
        DCommon.DAnim {}
    }

    Behavior on opacity {
        enabled: root.hasNet
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
        }
    }

    SysmonSource {
        id: source
        metrics: root.shownMetrics
        charts: root.style === "graph" ? "all" : "none"
        rangeSeconds: 60
        active: root.settled && root.surfaceLive && (root.hiddenByIdle || root.visible) && (root.Window.window?.visible ?? false)
    }

    content: Component {
        Item {
            id: contentRoot

            // itemAt() is not observable, so the bounds binding re-runs when delegates come or go.
            property int itemsRevision: 0

            implicitWidth: root.isVerticalOrientation ? root.contentThickness : layout.implicitWidth
            implicitHeight: root.isVerticalOrientation ? layout.implicitHeight : root.contentThickness

            Binding {
                target: root
                property: "bounds"
                value: {
                    const count = contentRoot.itemsRevision > 0 ? groupRepeater.count : 0;
                    const items = [];
                    for (let i = 0; i < count; i++)
                        items.push(groupRepeater.itemAt(i));
                    return root.gapCenters(items, layout);
                }
            }

            Grid {
                id: layout
                anchors.centerIn: parent
                columns: root.isVerticalOrientation ? 1 : Math.max(1, groupRepeater.count)
                spacing: root.splitActive ? 2 * root.horizontalPadding + root.splitGap : BarMetrics.pillEntryGap
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter

                Repeater {
                    id: groupRepeater
                    model: root.groups.length
                    onItemAdded: contentRoot.itemsRevision++
                    onItemRemoved: contentRoot.itemsRevision++

                    Grid {
                        id: group

                        required property int index
                        readonly property var entry: root.groups[index] ?? null
                        readonly property var items: entry?.items ?? []
                        readonly property bool showSeparator: index > 0 && (root.separator === "line" || root.separator === "dot")

                        columns: root.isVerticalOrientation ? 1 : (showSeparator ? 2 : 1)
                        spacing: BarMetrics.pillEntryGap
                        horizontalItemAlignment: Grid.AlignHCenter
                        verticalItemAlignment: Grid.AlignVCenter

                        PillEntrySeparator {
                            visible: group.showSeparator
                            dot: root.separator === "dot"
                            vertical: root.isVerticalOrientation
                        }

                        Grid {
                            columns: root.isVerticalOrientation ? 1 : Math.max(1, group.items.length)
                            spacing: root.isVerticalOrientation ? Theme.spacingXS : Theme.spacingS
                            horizontalItemAlignment: Grid.AlignHCenter
                            verticalItemAlignment: Grid.AlignVCenter

                            Repeater {
                                model: group.items.length

                                SysmonBarItem {
                                    required property int index

                                    value: group.items[index] ?? ({})
                                    style: root.style
                                    vertical: root.isVerticalOrientation
                                    labelText: index === 0 ? (group.entry?.name ?? "") : ""
                                    iconSize: root.iconSize
                                    textSize: root.textSize
                                    numberSize: root.numberSize
                                    thickness: root.widgetThickness
                                    dpr: root.dpr
                                    color: root.accent
                                    textColor: root.contentColor
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    StyledText {
        id: sizeProbe
        visible: false
        font.pixelSize: root.textSize
    }

    // On the pill rather than the click area, so the pill's hover tint still sees the pointer.
    HoverHandler {
        id: hover
        margin: Math.max(root.leftMargin, root.topMargin, root.rightMargin, root.bottomMargin)
    }

    PillTooltip {
        id: tooltip
        pill: root
    }

    MouseArea {
        id: clickArea
        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton

        onPressed: mouse => {
            root.hideTooltip();
            root.triggerRipple(this, mouse.x, mouse.y);
            const p = mapToItem(root, mouse.x, mouse.y);
            root.activated(root.entryAt(p.x, p.y));
        }
    }
}
