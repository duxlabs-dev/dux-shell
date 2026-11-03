.import qs.Common as Common
.import qs.Services as Services
.import qs.Modules.ControlCenter as ControlCenter
.import "../../../Common/GridLayout.js" as GridLayout
.import "../../../Common/settings/SettingsSpec.js" as Spec

var OPTION_IDS = ["diskUsage", "brightnessSlider", "idleInhibitor", "user", "battery", "quickTiles"];
var GROUP_ID = "quickTiles";
var BATTERY_STYLES = ["icon", "solid", "outline", "ring", "duo"];
var ACTION_IDS = ["settings", "lock", "power"];
var EDIT_ID = "edit";
var BUTTON_IDS = ACTION_IDS.concat([EDIT_ID]);
var USER_SHAPES = ["circle", "cookie4", "cookie7", "cookie12", "clover4", "clover8", "sunny", "pentagon", "arch", "slanted", "gem", "square"];

function isSliderWidget(id) {
    return id === "volumeSlider" || id === "brightnessSlider" || id === "inputVolumeSlider";
}

function canShrink(id) {
    return id !== "user";
}

function isSmall(widget, rows) {
    return widget?.small === true && rows === 1 && canShrink(widget.id);
}

function canGroup(widget) {
    return canShrink(widget?.id) && !isSliderWidget(widget?.id) && widget?.id !== GROUP_ID;
}

// Members of a group that no longer exists fall back to the grid.
function groupIds(widgets) {
    return widgets.filter(widget => widget?.id === GROUP_ID).map(widget => widget.instanceId);
}

function inGroup(widget, ids) {
    return !!widget?.group && ids.includes(widget.group);
}

function groupMembers(widgets, groupId) {
    return widgets.reduce((members, widget, index) => widget?.group === groupId && isShown(widget) ? members.concat([
            {
                "index": index,
                "widget": widget
            }
        ]) : members, []);
}

function isRemovable(widget) {
    return widget?.id !== EDIT_ID;
}

// A saved list without the pencil gets it back whatever state the migration left it in.
function ensureEditButton() {
    const widgets = Common.SettingsData.controlCenterWidgets;
    if (!Array.isArray(widgets) || widgets.some(widget => widget?.id === EDIT_ID))
        return;
    const fallback = Spec.SPEC.controlCenterWidgets.def.find(widget => widget.id === EDIT_ID);
    Common.SettingsData.set("controlCenterWidgets", widgets.concat([Object.assign({}, fallback)]));
}

function isShown(widget) {
    switch (widget?.id) {
    case "battery":
        return Services.BatteryService.batteryAvailable || Services.PowerProfileWatcher.available;
    case "diskUsage":
        return Services.DgopService.dgopAvailable;
    default:
        return true;
    }
}

function isUnplaced(widget) {
    return !Number.isFinite(widget?.col) || !Number.isFinite(widget?.row);
}

function hasOptions(id) {
    return OPTION_IDS.includes(id) || String(id ?? "").startsWith("plugin_");
}

function filterWidgets(widgets, query) {
    const needle = query.trim().toLowerCase();
    if (!needle)
        return widgets;
    return widgets.filter(widget => [widget.text, widget.description, widget.id].some(value => (value || "").toLowerCase().includes(needle)));
}

function nextUserShape(shape) {
    return USER_SHAPES[(USER_SHAPES.indexOf(shape) + 1) % USER_SHAPES.length];
}

function defaultWidget(id, columns) {
    return Object.assign({
        "id": id,
        "enabled": true
    }, clampSize({
        "id": id
    }, columns));
}

function sizeSpec(widget, columns, rows = Infinity) {
    const spec = {
        "w": 4,
        "h": 1,
        "minW": 1,
        "maxW": columns,
        "minH": 1,
        "maxH": rows,
        "step": ControlCenter.CcMetrics.gridStep
    };
    if (widget?.id === "user")
        spec.w = (Number.isFinite(columns) ? columns : ControlCenter.CcMetrics.defaultColumns) - ACTION_IDS.length;
    if (BUTTON_IDS.includes(widget?.id))
        spec.w = 1;
    return spec;
}

function clampSize(widget, columns, rows = Infinity) {
    const spec = sizeSpec(widget, columns, rows);
    const size = {
        "w": GridLayout.dimension(widget.w, spec.minW, spec.maxW, spec.w, spec.step),
        "h": GridLayout.dimension(widget.h, spec.minH, spec.maxH, spec.h, spec.step)
    };
    if (!isSliderWidget(widget.id) || size.w >= 2 || size.h >= 2)
        return size;
    if (rows > 1)
        return {
            "w": 1,
            "h": 2
        };
    return {
        "w": Math.min(2, columns),
        "h": 1
    };
}

function addWidget(widgetId, columns) {
    const widgets = Common.SettingsData.controlCenterWidgets.slice();
    const widget = defaultWidget(widgetId, columns);
    if (BUTTON_IDS.includes(widgetId) || isSliderWidget(widgetId))
        widget.small = true;

    if (widgetId === "diskUsage") {
        widget.instanceId = generateUniqueId();
        widget.mountPath = "/";
        widget.showMountPath = true;
    }

    if (widgetId === GROUP_ID)
        widget.instanceId = generateUniqueId();

    if (widgetId === "brightnessSlider") {
        widget.instanceId = generateUniqueId();
        widget.deviceName = "";
    }

    widgets.push(widget);
    Common.SettingsData.set("controlCenterWidgets", widgets);
}

function generateUniqueId() {
    return Date.now().toString(36) + Math.random().toString(36).substr(2);
}

function removeWidget(index) {
    const widgets = Common.SettingsData.controlCenterWidgets.slice();
    if (index < 0 || index >= widgets.length || !isRemovable(widgets[index]))
        return;
    const [removed] = widgets.splice(index, 1);
    Common.SettingsData.set("controlCenterWidgets", removed.id === GROUP_ID ? ungroup(widgets, removed.instanceId) : widgets);
}

function ungroup(widgets, groupId) {
    return widgets.map(widget => {
        if (widget?.group !== groupId)
            return widget;
        const freed = Object.assign({}, widget);
        delete freed.group;
        return freed;
    });
}

// Lands just before `beforeIndex`, or after the group's last member.
function moveToGroup(index, groupId, beforeIndex) {
    const widgets = Common.SettingsData.controlCenterWidgets.slice();
    const widget = widgets[index];
    if (!widget || !canGroup(widget))
        return;
    const before = beforeIndex === index ? null : widgets[beforeIndex] ?? null;
    widgets.splice(index, 1);
    const lastMember = widgets.reduce((last, other, i) => other?.group === groupId ? i : last, -1);
    const at = before ? widgets.indexOf(before) : lastMember >= 0 ? lastMember + 1 : widgets.length;
    const moved = Object.assign({}, widget, {
        "group": groupId
    });
    delete moved.col;
    delete moved.row;
    widgets.splice(at, 0, moved);
    Common.SettingsData.set("controlCenterWidgets", widgets);
}

function placeFromGroup(widgets, index, col, row) {
    const tile = Object.assign({}, widgets[index], {
        "col": col,
        "row": row
    });
    delete tile.group;
    const placed = widgets.slice();
    placed[index] = tile;
    return placed;
}

function setOption(index, key, value) {
    const widgets = Common.SettingsData.controlCenterWidgets.slice();
    if (index < 0 || index >= widgets.length)
        return;
    widgets[index] = Object.assign({}, widgets[index], {
        [key]: value
    });
    Common.SettingsData.set("controlCenterWidgets", widgets);
}

function setLayout(widgets) {
    Common.SettingsData.set("controlCenterWidgets", widgets);
}

function resetToDefault() {
    Common.SettingsData.resetToDefault(["controlCenterWidgets", "controlCenterColumns"]);
}

function clearAll() {
    Common.SettingsData.set("controlCenterWidgets", Common.SettingsData.controlCenterWidgets.filter(widget => !isRemovable(widget)));
}
