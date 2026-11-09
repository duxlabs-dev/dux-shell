import QtQuick
import QtQml.Models
import qs.Services
import qs.Common

Loader {
    id: root

    property var surfaceContext: null
    property var overflowAnchor: null
    property var overflowSurface: null
    property bool live: true
    property real allottedPrimarySize: 0
    property string instanceId: widgetData?.id ?? widgetId
    readonly property string registrationId: (surfaceContext?.kind ?? "bar") + ":" + (surfaceContext?.configId ?? barConfig?.id ?? "") + ":" + section + ":" + instanceId
    property int occurrenceOrder: 0
    property var registration: null
    readonly property var hostContext: context
    QtObject {
        id: context
        readonly property string kind: root.surfaceContext?.kind ?? "bar"
        readonly property string barId: root.surfaceContext?.configId ?? root.barConfig?.id ?? ""
        readonly property string screenName: root.parentScreen?.name ?? ""
        readonly property var screen: root.parentScreen
        readonly property string edge: root.axis?.edge ?? "top"
        readonly property var hostWindow: root.surfaceContext?.hostWindow ?? null
        readonly property string section: root.section
        readonly property string occurrenceId: root.instanceId
        readonly property int occurrenceOrder: root.occurrenceOrder
        readonly property var surface: root.surfaceContext
        readonly property var owner: root
        readonly property var anchorItem: root.item
    }
    property string widgetId: ""
    property var widgetData: null
    property int spacerSize: 20
    property var components: null
    property bool isInColumn: false
    property var axis: null
    property string section: "center"
    property var parentScreen: null
    property real widgetThickness: 30
    property real barThickness: 48
    property real barSpacing: 4
    property var barConfig: null
    property var blurBarWindow: null
    property real sectionAvailablePrimarySize: 0
    property bool isFirst: false
    property bool isLast: false
    property real sectionSpacing: 0
    property bool isLeftBarEdge: false
    property bool isRightBarEdge: false
    property bool isTopBarEdge: false
    property bool isBottomBarEdge: false
    property real crossEdgeExtension: 0
    property string segmentRole: "solo"

    asynchronous: false

    readonly property bool orientationMatches: (axis?.isVertical ?? false) === isInColumn

    readonly property bool widgetEnabled: widgetData?.enabled !== false
    readonly property bool loadedOnDemand: BarWidgetService.onDemandWidgetIds.includes(widgetId)
    readonly property string componentKey: widgetId === "music" && SettingsData.widgetOption("music", widgetData, "mediaStyle") === "activity" ? "music:activity" : widgetId

    active: (widgetEnabled || loadedOnDemand) && orientationMatches && getWidgetVisible(widgetId, DgopService.dgopAvailable) && (widgetId !== "music" || MprisController.activePlayer !== null)
    sourceComponent: getWidgetComponent(componentKey, components)

    signal contentItemReady(var item)

    Binding {
        target: root.item
        when: root.item && "surfaceLive" in root.item && !("effectiveVisible" in root.item)
        property: "surfaceLive"
        value: root.live && (root.surfaceContext?.live ?? true)
        restoreMode: Binding.RestoreBindingOrValue
    }

    Binding {
        target: root.item
        when: root.item && !root.widgetEnabled
        property: "visible"
        value: false
        restoreMode: Binding.RestoreBinding
    }

    Instantiator {
        model: ["parentScreen", "section", "widgetThickness", "barThickness", "barSpacing", "barConfig", "blurBarWindow", "axis", "widgetData", "isFirst", "isLast", "sectionSpacing", "sectionAvailablePrimarySize", "isLeftBarEdge", "isRightBarEdge", "isTopBarEdge", "isBottomBarEdge", "crossEdgeExtension", "segmentRole", "surfaceContext", "hostContext", "allottedPrimarySize"]
        delegate: Binding {
            required property string modelData
            target: root.item
            when: root.item && modelData in root.item
            property: modelData
            value: root[modelData]
            restoreMode: Binding.RestoreNone
        }
    }

    Binding {
        target: root.item
        when: root.item && "widgetBackground" in root.item && root.widgetData?.background !== undefined
        property: "widgetBackground"
        value: root.widgetData?.background === true
        restoreMode: Binding.RestoreBinding
    }

    Binding {
        target: root.item
        when: root.item && "widgetInstanceId" in root.item
        property: "widgetInstanceId"
        value: root.instanceId
        restoreMode: Binding.RestoreNone
    }

    onLoaded: {
        if (!item)
            return;

        contentItemReady(item);

        if (axis && "isVertical" in item) {
            try {
                item.isVertical = axis.isVertical;
            } catch (e) {}
        }

        if (item.pluginService !== undefined) {
            var parts = widgetId.split(":");
            var pluginId = parts[0];
            var variantId = parts.length > 1 ? parts[1] : null;

            if (item.pluginId !== undefined)
                item.pluginId = pluginId;
            if (item.variantId !== undefined)
                item.variantId = variantId;
            if (item.variantData !== undefined && variantId)
                item.variantData = PluginService.getPluginVariantData(pluginId, variantId);
            item.pluginService = PluginService;
        }

        if (item.popoutService !== undefined)
            item.popoutService = PopoutService;

        registerWidgetIfEligible();
    }

    Component.onDestruction: {
        unregisterWidget();
    }

    onParentScreenChanged: registerWidgetIfEligible()
    onRegistrationIdChanged: registerWidgetIfEligible()
    onSurfaceContextChanged: registerWidgetIfEligible()
    onWidgetIdChanged: registerWidgetIfEligible()
    onItemChanged: registerWidgetIfEligible()

    function registerWidgetIfEligible() {
        unregisterWidget();
        if (!active || !item || !widgetId || !parentScreen?.name)
            return;
        registration = BarWidgetService.registerWidget(widgetId, parentScreen.name, item, registrationId, hostContext);
    }

    function unregisterWidget() {
        BarWidgetService.releaseWidget(registration);
        registration = null;
    }

    function getWidgetComponent(widgetId, components) {
        return components?.[widgetId] || components?.[widgetId.split(":")[0]] || null;
    }

    function getWidgetVisible(widgetId, dgopAvailable) {
        const widgetVisibility = {
            "cpuUsage": dgopAvailable,
            "memUsage": dgopAvailable,
            "cpuTemp": dgopAvailable,
            "gpuTemp": dgopAvailable,
            "network_speed_monitor": dgopAvailable,
            "layout": CompositorService.isMango && MangoService.available
        };

        return widgetVisibility[widgetId] ?? true;
    }
}
