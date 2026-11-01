import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Common
import qs.Services

Scope {
    id: overviewScope

    property bool overviewOpen: false

    Binding {
        target: HyprlandService
        property: "inOverview"
        value: overviewScope.overviewOpen
    }

    Loader {
        id: hyprlandLoader
        active: overviewScope.overviewOpen
        asynchronous: false

        sourceComponent: Variants {
            id: overviewVariants
            model: Quickshell.screens

            PanelWindow {
                id: root
                required property var modelData
                readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
                property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
                property bool grabArmed: false

                function rearmGrab() {
                    grabArmed = false;
                    grabArmed = true;
                }

                screen: modelData
                visible: overviewScope.overviewOpen
                color: "transparent"

                WlrLayershell.namespace: "dms:workspace-overview"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: {
                    if (PopoutManager.screenshotActive)
                        return WlrKeyboardFocus.None;
                    if (!overviewScope.overviewOpen)
                        return WlrKeyboardFocus.None;
                    if (CompositorService.useHyprlandFocusGrab)
                        return WlrKeyboardFocus.OnDemand;
                    return WlrKeyboardFocus.Exclusive;
                }

                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                HyprlandFocusGrab {
                    id: grab
                    windows: overviewLoader.item?.windowMenuWindow ? [root, overviewLoader.item.windowMenuWindow] : [root]
                    active: root.grabArmed && root.monitorIsFocused && !PopoutManager.screenshotActive
                    onCleared: overviewScope.overviewOpen = false
                }

                Component.onCompleted: {
                    if (CompositorService.useHyprlandFocusGrab)
                        delayedGrabTimer.start();
                }

                Timer {
                    id: delayedGrabTimer
                    interval: 150
                    repeat: false
                    onTriggered: root.grabArmed = true
                }

                Timer {
                    id: closeTimer
                    interval: Math.max(Theme.expressiveDurations.expressiveDefaultSpatial + 120, Math.round(morph.settleDurationMs) + 120)
                    onTriggered: {
                        root.visible = false;
                    }
                }

                Rectangle {
                    id: background
                    anchors.fill: parent
                    color: Theme.backdropColor
                    opacity: overviewScope.overviewOpen ? 0.5 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.variantDuration(Theme.expressiveDurations.expressiveDefaultSpatial, overviewScope.overviewOpen)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: overviewScope.overviewOpen ? Theme.variantModalEnterCurve : Theme.variantModalExitCurve
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: mouse => {
                            const localPos = mapToItem(contentAnchor, mouse.x, mouse.y);
                            if (localPos.x < 0 || localPos.x > contentAnchor.width || localPos.y < 0 || localPos.y > contentAnchor.height) {
                                overviewScope.overviewOpen = false;
                                closeTimer.restart();
                            }
                        }
                    }
                }

                Item {
                    id: contentAnchor
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 100
                    width: contentContainer.width
                    height: contentContainer.height

                    Item {
                        id: contentContainer
                        width: childrenRect.width
                        height: childrenRect.height
                        transformOrigin: Item.Center

                        readonly property var morphSpringParams: Theme.springPreset("expressive", Theme.variantDuration(Theme.expressiveDurations.expressiveDefaultSpatial, overviewScope.overviewOpen))
                        readonly property real collapsedX: {
                            if (Theme.isDepthEffect)
                                return Theme.effectAnimOffset * 0.25;
                            return 0;
                        }
                        readonly property real collapsedY: {
                            if (Theme.isDirectionalEffect)
                                return -Math.max(contentContainer.height * 0.8, Theme.effectAnimOffset * 1.1);
                            if (Theme.isDepthEffect)
                                return Math.max(Theme.effectAnimOffset * 0.85, 28);
                            return Theme.effectAnimOffset;
                        }

                        SpringMotion {
                            id: morph
                            reducedMotion: Theme.springMotionDisabled
                            positionEpsilon: 0.001
                            velocityEpsilon: 0.001
                            stiffness: contentContainer.morphSpringParams.stiffness
                            damping: contentContainer.morphSpringParams.damping
                            value: overviewScope.overviewOpen ? 1 : 0

                            Component.onCompleted: snapTo(overviewScope.overviewOpen ? 1 : 0)
                        }

                        Connections {
                            target: overviewScope
                            function onOverviewOpenChanged() {
                                morph.retarget(overviewScope.overviewOpen ? 1 : 0);
                            }
                        }

                        opacity: overviewScope.overviewOpen ? 1 : 0
                        scale: Theme.effectScaleCollapsed + (1.0 - Theme.effectScaleCollapsed) * morph.value
                        x: collapsedX * (1 - morph.value)
                        y: collapsedY * (1 - morph.value)

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.variantDuration(Theme.expressiveDurations.expressiveDefaultSpatial, overviewScope.overviewOpen)
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: overviewScope.overviewOpen ? Theme.variantModalEnterCurve : Theme.variantModalExitCurve
                            }
                        }

                        Loader {
                            id: overviewLoader
                            active: overviewScope.overviewOpen
                            asynchronous: false

                            sourceComponent: OverviewWidget {
                                panelWindow: root
                                overviewOpen: overviewScope.overviewOpen
                            }
                        }
                    }
                }

                FocusScope {
                    id: focusScope
                    anchors.fill: parent
                    visible: overviewScope.overviewOpen
                    focus: overviewScope.overviewOpen && root.monitorIsFocused

                    Keys.onEscapePressed: event => {
                        if (!root.monitorIsFocused)
                            return;
                        overviewScope.overviewOpen = false;
                        closeTimer.restart();
                        event.accepted = true;
                    }

                    Keys.onPressed: event => {
                        if (!root.monitorIsFocused)
                            return;
                        if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                            if (!overviewLoader.item)
                                return;
                            const thisMonitorWorkspaceIds = overviewLoader.item.thisMonitorWorkspaceIds;
                            if (thisMonitorWorkspaceIds.length === 0)
                                return;
                            const currentId = root.monitor.activeWorkspace?.id ?? thisMonitorWorkspaceIds[0];
                            const currentIndex = thisMonitorWorkspaceIds.indexOf(currentId);

                            let targetIndex;
                            if (event.key === Qt.Key_Left) {
                                targetIndex = currentIndex - 1;
                                if (targetIndex < 0)
                                    targetIndex = thisMonitorWorkspaceIds.length - 1;
                            } else {
                                targetIndex = currentIndex + 1;
                                if (targetIndex >= thisMonitorWorkspaceIds.length)
                                    targetIndex = 0;
                            }

                            const targetId = thisMonitorWorkspaceIds[targetIndex];

                            HyprlandService.focusWorkspace(targetId);
                            event.accepted = true;
                        }
                    }

                    onVisibleChanged: {
                        if (visible && overviewScope.overviewOpen && root.monitorIsFocused) {
                            Qt.callLater(() => focusScope.forceActiveFocus());
                        }
                    }

                    readonly property bool rootMonitorIsFocused: root.monitorIsFocused

                    onRootMonitorIsFocusedChanged: {
                        if (rootMonitorIsFocused && overviewScope.overviewOpen) {
                            Qt.callLater(() => focusScope.forceActiveFocus());
                        }
                    }

                    readonly property bool windowActive: Window.active

                    // Hyprland nulls keyboard focus when the workspace has no window to focus, without ending the grab
                    onWindowActiveChanged: {
                        if (windowActive || !grab.active || !overviewScope.overviewOpen)
                            return;
                        root.rearmGrab();
                    }
                }

                onVisibleChanged: {
                    if (visible && overviewScope.overviewOpen) {
                        Qt.callLater(() => focusScope.forceActiveFocus());
                    } else if (!visible) {
                        root.grabArmed = false;
                    }
                }

                Connections {
                    target: overviewScope
                    function onOverviewOpenChanged() {
                        if (overviewScope.overviewOpen) {
                            closeTimer.stop();
                            root.visible = true;
                            Qt.callLater(() => focusScope.forceActiveFocus());
                        } else {
                            closeTimer.restart();
                            root.grabArmed = false;
                        }
                    }
                }
            }
        }
    }
}
