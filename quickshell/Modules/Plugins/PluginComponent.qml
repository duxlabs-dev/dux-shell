import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root

    property string layerNamespacePlugin: "plugin"

    property var surfaceContext: null
    property var hostContext: null
    property string widgetInstanceId: ""
    readonly property string popoutTriggerId: widgetInstanceId || pluginId
    property Component attachedContent: null
    readonly property bool usesAttachedExpansion: !!attachedContent && ((surfaceContext?.inlineExpansion ?? false) || !hasPopout)
    readonly property bool surfaceLive: (surfaceContext?.live ?? true) && effectiveVisible
    readonly property bool attachedActive: surfaceContext?.host?.expansionOwner === root
    readonly property bool interactionActive: attachedActive || pluginPopout.shouldBeVisible
    property var axis: null
    property string section: "center"
    property var parentScreen: null
    property real widgetThickness: 30
    property real barThickness: 48
    property real barSpacing: 4
    property var barConfig: null
    property var blurBarWindow: null
    property string pluginId: ""
    property var pluginService: null
    property bool isFirst: false
    property bool isLast: false
    property bool isLeftBarEdge: false
    property bool isRightBarEdge: false
    property bool isTopBarEdge: false
    property bool isBottomBarEdge: false
    property real sectionSpacing: 0
    property string segmentRole: "solo"
    property real crossEdgeExtension: 0

    property string visibilityCommand: ""
    property int visibilityInterval: 0
    property bool conditionVisible: true
    property bool _visibilityOverride: false
    property bool _visibilityOverrideValue: true
    readonly property bool _barRevealed: surfaceContext?.live ?? blurBarWindow?.barRevealed ?? true

    readonly property bool effectiveVisible: {
        if (_visibilityOverride)
            return _visibilityOverrideValue;
        if (!visibilityCommand)
            return true;
        return conditionVisible;
    }

    property Component horizontalBarPill: null
    property Component verticalBarPill: null
    property Component popoutContent: null
    property real popoutWidth: 400
    property real popoutHeight: 0
    property var pillClickAction: null
    property var pillRightClickAction: null

    property Component controlCenterWidget: null
    property string ccWidgetIcon: ""
    property string ccWidgetPrimaryText: ""
    property string ccWidgetSecondaryText: ""
    property bool ccWidgetIsActive: false
    property bool ccWidgetIsToggle: true
    property Component ccExpandedContent: null
    // Unused; kept so older plugins still load.
    property Component ccFooterContent: null
    property real ccExpandedMinimumHeight: Theme.listItemHeight
    property Component ccDetailContent: null
    property real ccDetailHeight: 250

    signal ccWidgetToggled
    signal ccWidgetExpanded

    property var pluginData: ({})
    property var variants: []

    readonly property bool isVertical: axis?.isVertical ?? false
    readonly property bool hasHorizontalPill: horizontalBarPill !== null
    readonly property bool hasVerticalPill: verticalBarPill !== null
    readonly property bool hasPopout: popoutContent !== null

    readonly property int iconSize: Theme.barIconSize(barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
    readonly property int iconSizeLarge: Theme.barIconSize(barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
    readonly property int textSize: Theme.barTextSize(barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)

    Component.onCompleted: {
        loadPluginData();
        if (visibilityCommand)
            Qt.callLater(checkVisibility);
    }

    onPluginServiceChanged: {
        loadPluginData();
    }

    onPluginIdChanged: {
        loadPluginData();
    }

    Connections {
        target: pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === pluginId) {
                loadPluginData();
            }
        }
    }

    function loadPluginData() {
        if (!pluginService || !pluginId) {
            pluginData = {};
            variants = [];
            return;
        }
        pluginData = SettingsData.getPluginSettingsForPlugin(pluginId);
        variants = pluginService.getPluginVariants(pluginId);
    }

    function checkVisibility() {
        if (!visibilityCommand) {
            conditionVisible = true;
            return;
        }
        visibilityProcess.running = true;
    }

    function setVisibilityOverride(visible) {
        _visibilityOverride = true;
        _visibilityOverrideValue = visible;
    }

    function clearVisibilityOverride() {
        _visibilityOverride = false;
        if (visibilityCommand)
            checkVisibility();
    }

    onVisibilityCommandChanged: {
        if (visibilityCommand)
            Qt.callLater(checkVisibility);
        else
            conditionVisible = true;
    }

    on_BarRevealedChanged: {
        if (_barRevealed && visibilityCommand && !_visibilityOverride)
            checkVisibility();
    }

    onVisibilityIntervalChanged: {
        if (visibilityInterval > 0 && visibilityCommand) {
            visibilityTimer.restart();
        } else {
            visibilityTimer.stop();
        }
    }

    Timer {
        id: visibilityTimer
        interval: root.visibilityInterval * 1000
        repeat: true
        running: root.visibilityInterval > 0 && root.visibilityCommand !== "" && root._barRevealed && !root._visibilityOverride
        onTriggered: root.checkVisibility()
    }

    Process {
        id: visibilityProcess
        command: ["sh", "-c", root.visibilityCommand]
        running: false
        onExited: (exitCode, exitStatus) => {
            root.conditionVisible = (exitCode === 0);
        }
    }

    function createVariant(variantName, variantConfig) {
        if (!pluginService || !pluginId) {
            return null;
        }
        return pluginService.createPluginVariant(pluginId, variantName, variantConfig);
    }

    function removeVariant(variantId) {
        if (!pluginService || !pluginId) {
            return;
        }
        pluginService.removePluginVariant(pluginId, variantId);
    }

    function updateVariant(variantId, variantConfig) {
        if (!pluginService || !pluginId) {
            return;
        }
        pluginService.updatePluginVariant(pluginId, variantId, variantConfig);
    }

    width: isVertical ? (hasVerticalPill ? verticalPill.width : 0) : (hasHorizontalPill ? horizontalPill.width : 0)
    height: isVertical ? (hasVerticalPill ? verticalPill.height : 0) : (hasHorizontalPill ? horizontalPill.height : 0)

    BasePill {
        id: horizontalPill
        visible: !isVertical && hasHorizontalPill
        opacity: root.effectiveVisible ? 1 : 0
        axis: root.axis
        section: root.section
        popoutTarget: hasPopout ? pluginPopout : null
        parentScreen: root.parentScreen
        widgetThickness: root.widgetThickness
        barThickness: root.barThickness
        barSpacing: root.barSpacing
        barConfig: root.barConfig
        blurBarWindow: root.blurBarWindow
        content: root.horizontalBarPill
        isFirst: root.isFirst
        isLast: root.isLast
        segmentRole: root.segmentRole
        isLeftBarEdge: root.isLeftBarEdge
        isRightBarEdge: root.isRightBarEdge
        isTopBarEdge: root.isTopBarEdge
        isBottomBarEdge: root.isBottomBarEdge
        sectionSpacing: root.sectionSpacing
        crossEdgeExtension: root.crossEdgeExtension

        states: State {
            name: "hidden"
            when: !root.effectiveVisible
            PropertyChanges {
                target: horizontalPill
                width: 0
            }
        }

        transitions: Transition {
            enabled: !SettingsData.reduceMotion
            NumberAnimation {
                properties: "width,opacity"
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        onClicked: root.triggerPopout()
        onRightClicked: root.runPillAction(root.pillRightClickAction)
    }

    BasePill {
        id: verticalPill
        visible: isVertical && hasVerticalPill
        opacity: root.effectiveVisible ? 1 : 0
        axis: root.axis
        section: root.section
        popoutTarget: hasPopout ? pluginPopout : null
        parentScreen: root.parentScreen
        widgetThickness: root.widgetThickness
        barThickness: root.barThickness
        barSpacing: root.barSpacing
        barConfig: root.barConfig
        blurBarWindow: root.blurBarWindow
        content: root.verticalBarPill
        isVerticalOrientation: true
        isFirst: root.isFirst
        isLast: root.isLast
        segmentRole: root.segmentRole
        isLeftBarEdge: root.isLeftBarEdge
        isRightBarEdge: root.isRightBarEdge
        isTopBarEdge: root.isTopBarEdge
        isBottomBarEdge: root.isBottomBarEdge
        sectionSpacing: root.sectionSpacing
        crossEdgeExtension: root.crossEdgeExtension

        states: State {
            name: "hidden"
            when: !root.effectiveVisible
            PropertyChanges {
                target: verticalPill
                height: 0
            }
        }

        transitions: Transition {
            enabled: !SettingsData.reduceMotion
            NumberAnimation {
                properties: "height,opacity"
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        onClicked: root.triggerPopout()
        onRightClicked: root.runPillAction(root.pillRightClickAction)
    }

    Component.onDestruction: {
        if (attachedActive)
            surfaceContext.dismissExpansion();
    }

    function closePopout() {
        if (attachedActive)
            surfaceContext.dismissExpansion();
        if (pluginPopout) {
            pluginPopout.close();
        }
    }

    function pillAnchor() {
        const pill = isVertical ? verticalPill : horizontalPill;
        if (surfaceContext?.popupAnchor)
            return surfaceContext.popupAnchor(pill, section);
        const screen = parentScreen || Screen;
        const position = barConfig?.position ?? (isVertical ? 2 : 0);
        return {
            trigger: SettingsData.getPopupTriggerPosition(pill.visualContent.mapToItem(null, 0, 0), screen, barThickness, pill.visualWidth, barSpacing, position, barConfig),
            screen,
            section,
            position,
            thickness: barThickness,
            spacing: barSpacing,
            config: barConfig
        };
    }

    function runPillAction(action) {
        if (!action)
            return;
        if (action.length === 0) {
            action();
            return;
        }
        const anchor = pillAnchor();
        if (anchor)
            action(anchor.trigger.x, anchor.trigger.y, anchor.trigger.width, section, anchor.screen);
    }

    function positionPopout() {
        const anchor = pillAnchor();
        if (!anchor)
            return false;
        pluginPopout.setTriggerPosition(anchor.trigger.x, anchor.trigger.y, anchor.trigger.width, section, anchor.screen, anchor.position, anchor.thickness, anchor.spacing, anchor.config, root);
        return true;
    }

    function triggerPopout() {
        surfaceContext?.ensureVisible(root);
        if (pillClickAction) {
            runPillAction(pillClickAction);
            return;
        }
        if (usesAttachedExpansion && surfaceContext?.requestExpansion(root))
            return;
        if (hasPopout && positionPopout())
            PopoutManager.requestPopout(pluginPopout, undefined, popoutTriggerId);
    }

    function triggerHoverPopout() {
        if (pillClickAction) {
            triggerPopout();
            return;
        }
        if (!hasPopout || !positionPopout())
            return;
        PopoutManager.requestHoverPopout(pluginPopout, undefined, popoutTriggerId);
    }

    PluginPopout {
        id: pluginPopout
        pluginId: root.pluginId
        contentWidth: root.popoutWidth
        contentHeight: root.popoutHeight
        pluginContent: root.popoutContent
    }
}
