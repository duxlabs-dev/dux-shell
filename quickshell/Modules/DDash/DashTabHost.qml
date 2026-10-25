pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

FocusScope {
    id: root

    required property var entry
    required property var dashHost
    property bool isCurrent: false
    property int rowBudget: DashMetrics.minimumTabRows
    property real contentPadding: 0
    property Item keyForwardTarget: null
    property Item contentViewport: null
    property bool animatingOut: false

    readonly property bool presented: dashHost.dashVisible || dashHost.isClosing
    readonly property var item: loader.item
    readonly property bool loading: loader.active && loader.status === Loader.Loading
    readonly property bool failed: loader.active && (loader.status === Loader.Error || loader.sourceComponent === null)
    readonly property Item focusTarget: loader.item?.focusTarget ?? loader.item ?? null

    implicitHeight: loader.item?.implicitHeight ?? DashMetrics.tabMinHeight
    visible: isCurrent || animatingOut
    enabled: isCurrent
    z: isCurrent ? 1 : 0
    opacity: 0
    clip: true

    onIsCurrentChanged: {
        if (isCurrent) {
            animatingOut = false;
            exitAnim.stop();
            if (loader.item)
                enter();
            return;
        }
        enterAnim.stop();
        if (!loader.item || !DashMetrics.animationsEnabled) {
            opacity = 0;
            return;
        }
        animatingOut = true;
        exitAnim.restart();
    }

    function enter() {
        if (!DashMetrics.animationsEnabled || !root.dashHost.shouldBeVisible) {
            snap();
            return;
        }
        enterAnim.restart();
    }

    function snap() {
        enterAnim.stop();
        opacity = 1;
    }

    function inject(target) {
        if (!target)
            return;
        if ("entryId" in target)
            target.entryId = root.entry?.id ?? "";
        if ("live" in target)
            target.live = Qt.binding(() => (root.isCurrent || root.animatingOut) && root.presented);
        if ("active" in target)
            target.active = Qt.binding(() => (root.isCurrent || root.animatingOut) && root.presented);
        if ("keyForwardTarget" in target)
            target.keyForwardTarget = root.keyForwardTarget;
        if ("contentViewport" in target)
            target.contentViewport = root.contentViewport;
        if ("parentPopout" in target)
            target.parentPopout = root.dashHost;
        if ("dashHost" in target)
            target.dashHost = root.dashHost;
        if ("transientSurfaceTracker" in target)
            target.transientSurfaceTracker = root.dashHost.transientSurfaceTracker;
        if ("targetScreen" in target)
            target.targetScreen = Qt.binding(() => root.dashHost.screen);
        if ("preferredFocusId" in target)
            target.preferredFocusId = Qt.binding(() => root.dashHost.overviewFocusId);
        if ("editMode" in target)
            target.editMode = Qt.binding(() => root.dashHost.editMode);
        if ("rowBudget" in target)
            target.rowBudget = Qt.binding(() => root.rowBudget);
        if ("columnCap" in target)
            target.columnCap = Qt.binding(() => root.dashHost.columnCap);
        if (root.entry?.isPlugin !== true)
            return;
        if ("pluginId" in target)
            target.pluginId = root.entry.pluginId;
        if ("pluginService" in target)
            target.pluginService = PluginService;
        if ("popoutService" in target)
            target.popoutService = PopoutService;
    }

    NumberAnimation {
        id: enterAnim
        target: root
        property: "opacity"
        from: 0
        to: 1
        duration: DashMetrics.fadeDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
    }

    NumberAnimation {
        id: exitAnim
        target: root
        property: "opacity"
        to: 0
        duration: DashMetrics.fadeDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        onFinished: root.animatingOut = false
    }

    Loader {
        id: loader

        anchors.fill: parent
        anchors.margins: root.contentPadding
        focus: true
        active: root.isCurrent || root.animatingOut
        asynchronous: root.entry?.tab?.async === true
        sourceComponent: DashRegistry.tabComponentFor(root.entry?.id ?? "")

        onLoaded: {
            root.inject(item);
            if (root.isCurrent)
                root.enter();
        }
    }

    Connections {
        target: loader.item
        ignoreUnknownSignals: true

        function onCardFocusChanged(id) {
            root.dashHost.overviewFocusId = id;
        }

        function onNavFocusRequested(backwards) {
            root.dashHost.focusContent(backwards);
        }

        function onTabRequested(id) {
            root.dashHost.requestTab(id);
        }
    }

    DSpinner {
        anchors.centerIn: parent
        size: DashMetrics.spinnerSize
        visible: root.isCurrent && root.loading
    }
}
