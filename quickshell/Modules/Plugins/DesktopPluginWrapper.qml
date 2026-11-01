import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

Item {
    id: root

    required property string pluginId
    required property var screen

    property string instanceId: ""
    property var instanceData: null
    property bool widgetEnabled: true

    readonly property bool showOnOverlay: instanceData?.config?.showOnOverlay ?? false
    readonly property bool showOnOverview: instanceData?.config?.showOnOverview ?? false
    readonly property bool showOnOverviewOnly: instanceData?.config?.showOnOverviewOnly ?? false
    readonly property bool overviewActive: CompositorService.isNiri && NiriService.inOverview
    readonly property bool clickThrough: instanceData?.config?.clickThrough ?? false

    // Unmapping with the widget still in the last buffer leaves a stale image in
    // Hyprland's blur cache behind transparent tiled windows (#2955), so hide the
    // content, present a transparent frame, then unmap.
    readonly property bool contentShowing: widgetEnabled && content.activeComponent !== null && (!showOnOverviewOnly || overviewActive)
    property bool surfaceLingering: false

    onContentShowingChanged: {
        if (contentShowing) {
            lingerTimer.stop();
            surfaceLingering = false;
            return;
        }
        surfaceLingering = true;
        lingerTimer.restart();
    }

    Timer {
        id: lingerTimer
        interval: 64
        onTriggered: root.surfaceLingering = false
    }

    DesktopWidgetGeometry {
        id: geometry
        instanceId: root.instanceId
        instanceData: root.instanceData
        screen: root.screen
        minWidth: content.contentMinWidth
        minHeight: content.contentMinHeight
        forceSquare: content.contentForceSquare
    }

    PanelWindow {
        id: widgetWindow
        screen: root.screen
        visible: root.contentShowing || root.surfaceLingering
        color: "transparent"

        Region {
            id: emptyMask
        }

        mask: root.clickThrough ? emptyMask : null

        WlrLayershell.namespace: "dms:desktop-widget:" + root.pluginId + (root.instanceId ? ":" + root.instanceId : "")
        WlrLayershell.layer: {
            if (root.showOnOverlay)
                return WlrLayer.Overlay;
            if (root.overviewActive && (root.showOnOverview || root.showOnOverviewOnly))
                return WlrLayer.Overlay;
            return WlrLayer.Bottom;
        }
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: {
            if (PopoutManager.screenshotActive)
                return WlrKeyboardFocus.None;
            if (content.acceptsKeyboardFocus)
                return WlrKeyboardFocus.OnDemand;
            return WlrKeyboardFocus.None;
        }

        anchors {
            left: true
            top: true
        }

        WlrLayershell.margins {
            left: geometry.widgetX
            top: geometry.widgetY
        }

        implicitWidth: geometry.widgetWidth
        implicitHeight: geometry.widgetHeight

        MouseArea {
            anchors.fill: parent
            enabled: CompositorService.desktopContextMenuEnabled
            acceptedButtons: Qt.RightButton
            onClicked: mouse => PopoutService.desktopContextMenu?.openForWidget(root.screen, geometry.widgetX + mouse.x, geometry.widgetY + mouse.y, root.instanceId)
        }

        DesktopWidgetContent {
            id: content
            anchors.fill: parent
            active: root.widgetEnabled
            visible: root.contentShowing
            pluginId: root.pluginId
            instanceId: root.instanceId
            instanceData: root.instanceData
            screen: root.screen
            geometry: geometry
        }
    }
}
