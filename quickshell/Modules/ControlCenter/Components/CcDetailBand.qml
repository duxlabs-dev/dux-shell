pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Details
import qs.DCommon.Widgets
import "../utils/sections.js" as Sections

FocusScope {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string section: ""
    property var model: null
    property string screenName: ""
    property string screenModel: ""
    property var transientSurfaceTracker: null
    property real maximumHeight: 0
    property real coverage: 0
    property var runningToplevels: []

    signal dismissed
    signal backRequested
    signal collapseRequested
    signal closeRequested
    signal codecSelectorRequested(var device)
    signal portSelectorRequested(var node)
    signal screenshotRequested(string mode, bool keepOpen)

    property string shownSection: ""
    property real _heldHeight: 0
    readonly property var pageItem: pageLoader.item
    readonly property bool pluginPage: shownSection.startsWith("plugin_") || shownSection.startsWith("builtin_")
    // A page measures itself a tick after it loads; waiting for that keeps the first target the final one.
    readonly property real pageHeight: {
        const own = pageItem?.implicitHeight ?? 0;
        if (own > 0)
            return own;
        if (!pluginPage)
            return 0;
        const preferred = pageItem?.preferredHeight ?? 0;
        return preferred > 0 ? preferred : CcMetrics.detailHeightDefault;
    }
    // The band's extent includes the gap above and below its card, so they grow and shrink with it.
    readonly property real chromeHeight: CcMetrics.gridGap * 2 + CcMetrics.detailHeaderHeight + CcMetrics.detailDialogPadding * 2
    readonly property real contentCap: Math.max(CcMetrics.detailHeightFloor(shownSection, pageItem?.preferredHeight ?? 0), maximumHeight - chromeHeight)
    readonly property real _measuredHeight: section === "" || pageHeight <= 0 ? 0 : chromeHeight + Math.min(pageHeight, contentCap)
    // Hold the previous band height across section switches until the new page measures itself, so switching tiles animates only the delta.
    readonly property real targetHeight: section === "" ? 0 : (_measuredHeight > 0 ? _measuredHeight : _heldHeight)
    on_MeasuredHeightChanged: {
        if (section !== "" && _measuredHeight > 0)
            _heldHeight = _measuredHeight;
    }
    readonly property bool transitioning: heightMotion.running
    onTargetHeightChanged: heightMotion.retarget(targetHeight)
    // Only IPC can ask for a plugin section whose tile is not placed, so there is nothing to show.
    readonly property bool pageEmpty: pageItem?.empty === true
    readonly property string title: {
        const own = pageItem?.title ?? "";
        if (own)
            return own;
        const parsed = Sections.parse(shownSection);
        return model?.getWidgetForId(parsed.base)?.text ?? "";
    }

    height: Math.round(heightMotion.value)
    visible: shownSection !== ""
    clip: true
    Accessible.role: Accessible.Grouping
    Accessible.name: title

    // Same spring as the popout's own resize, so the surface and the content move as one.
    SpringMotion {
        id: heightMotion

        readonly property var spring: Theme.springPreset("standardDefaultSpatial")

        enabled: CcMetrics.animationsEnabled
        stiffness: spring.stiffness
        damping: spring.damping
        positionEpsilon: 0.25
        velocityEpsilon: positionEpsilon * damping / (2 * mass)
    }

    function _collapseIfEmpty() {
        if (pageEmpty && section !== "")
            collapseRequested();
    }

    onPageEmptyChanged: {
        if (pageEmpty && section !== "")
            Qt.callLater(_collapseIfEmpty);
    }

    function finishClose() {
        if (section !== "" || shownSection === "")
            return;
        pageLoader.sourceComponent = null;
        shownSection = "";
        _heldHeight = 0;
        dismissed();
    }

    function dismissTransient() {
        const item = pageItem;
        if (!item || typeof item.dismissTransient !== "function")
            return false;
        return item.dismissTransient() === true;
    }

    function _componentFor(sectionId) {
        const parsed = Sections.parse(sectionId);
        switch (parsed.base) {
        case "network":
        case "wifi":
            return networkComponent;
        case "bluetooth":
            return bluetoothComponent;
        case "audioOutput":
            return audioOutputComponent;
        case "audioInput":
            return audioInputComponent;
        case "battery":
            return batteryComponent;
        case "doNotDisturb":
            return dndComponent;
        case "idleInhibitor":
            return idleInhibitComponent;
        case "diskUsage":
            return diskUsageComponent;
        case "brightnessSlider":
            return brightnessComponent;
        case "runningApps":
            return runningAppsComponent;
        case "screenshot":
            return screenshotComponent;
        }
        if (sectionId.startsWith("builtin_") || sectionId.startsWith("plugin_"))
            return pluginComponent;
        return null;
    }

    onSectionChanged: {
        if (section === "") {
            if (!CcMetrics.animationsEnabled)
                finishClose();
            return;
        }
        pageLoader.sourceComponent = null;
        shownSection = section;
        pageLoader.sourceComponent = _componentFor(section);
        (pageItem ?? root).forceActiveFocus();
    }

    onHeightChanged: {
        if (section === "" && height <= 0.5)
            finishClose();
    }

    Rectangle {
        y: CcMetrics.gridGap
        width: parent.width
        height: Math.max(0, parent.height - CcMetrics.gridGap * 2)
        radius: CcMetrics.detailBandRadius
        color: CcMetrics.dialogColor
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium

        Item {
            id: panel

            anchors.fill: parent
            anchors.margins: CcMetrics.detailDialogPadding
            opacity: root.section !== "" ? (CcMetrics.hideCoveredContent ? 1 - root.coverage : 1) : 0

            Behavior on opacity {
                enabled: CcMetrics.animationsEnabled
                NumberAnimation {
                    duration: CcMetrics.fadeDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                }
            }

            Item {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: CcMetrics.detailHeaderHeight

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: CcMetrics.rowPaddingH
                    anchors.right: headerSlot.left
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    font.pixelSize: CcMetrics.detailTitleSize
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }

                Item {
                    id: headerSlot
                    anchors.right: closeButton.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    width: childrenRect.width
                    height: childrenRect.height
                }

                DActionButton {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.rightMargin: CcMetrics.headerEdgeInset
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: CcMetrics.headerActionSize
                    iconName: "close"
                    iconSize: CcMetrics.headerActionIconSize
                    iconColor: Theme.surfaceText
                    Accessible.name: I18n.tr("Close")
                    onClicked: root.backRequested()
                }
            }

            ClippingRectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: header.bottom
                anchors.bottom: parent.bottom
                radius: Theme.groupedListOuterRadius
                color: "transparent"

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    active: root.shownSection !== ""
                    onLoaded: {
                        const actions = item.headerActions ?? null;
                        if (actions)
                            actions.parent = headerSlot;
                    }
                }
            }
        }
    }

    Connections {
        target: root.pageItem
        ignoreUnknownSignals: true

        function onMountPathChanged(newMountPath) {
            Sections.updateWidgetForSection(root.shownSection, {
                "mountPath": newMountPath
            });
            root.collapseRequested();
        }

        function onDeviceNameChanged(newDeviceName) {
            Sections.updateWidgetForSection(root.shownSection, {
                "deviceName": newDeviceName
            });
        }

        function onShowCodecSelector(device) {
            root.codecSelectorRequested(device);
        }

        function onShowPortSelector(node) {
            root.portSelectorRequested(node);
        }

        function onDismissRequested() {
            root.backRequested();
        }

        function onCloseRequested() {
            root.closeRequested();
        }

        function onScreenshotRequested(mode, keepOpen) {
            root.screenshotRequested(mode, keepOpen);
        }
    }

    Component {
        id: networkComponent
        NetworkDetail {
            transientSurfaceTracker: root.transientSurfaceTracker
            transitioning: root.transitioning
        }
    }

    Component {
        id: bluetoothComponent
        BluetoothDetail {
            transientSurfaceTracker: root.transientSurfaceTracker
        }
    }

    Component {
        id: audioOutputComponent
        AudioOutputDetail {}
    }

    Component {
        id: audioInputComponent
        AudioInputDetail {}
    }

    Component {
        id: batteryComponent
        BatteryDetail {}
    }

    Component {
        id: dndComponent
        DoNotDisturbDetail {}
    }

    Component {
        id: idleInhibitComponent
        IdleInhibitorDetail {}
    }

    Component {
        id: diskUsageComponent
        DiskUsageDetail {
            readonly property var widgetEntry: Sections.widgetForSection(root.shownSection)
            currentMountPath: widgetEntry?.mountPath || "/"
        }
    }

    Component {
        id: brightnessComponent
        BrightnessDetail {
            readonly property var widgetEntry: Sections.widgetForSection(root.shownSection)
            initialDeviceName: widgetEntry?.deviceName || ""
            instanceId: widgetEntry?.instanceId || ""
            screenName: root.screenName
            screenModel: root.screenModel
        }
    }

    Component {
        id: runningAppsComponent
        RunningAppsDetail {
            toplevels: root.runningToplevels
        }
    }

    Component {
        id: screenshotComponent
        ScreenshotDetail {}
    }

    Component {
        id: pluginComponent
        PluginDetailShell {
            pluginId: root.shownSection.startsWith("plugin_") ? root.shownSection.replace("plugin_", "") : ""
            builtinInstance: root.shownSection.startsWith("builtin_") ? (root.model?.builtinInstances[root.shownSection] ?? null) : null
        }
    }
}
