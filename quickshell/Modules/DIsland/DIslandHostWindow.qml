pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    required property string barId
    property var screen: null
    property var hyprlandOverviewLoader: null

    readonly property var body: IslandHostRegistry.hostFor(root.screen?.name, root.barId)
    readonly property var islandController: root.body?.islandController ?? null
    readonly property int launcherResultCount: root.body?.launcherResultCount ?? 0
    readonly property int hostOriginX: root.body?.hostOriginX ?? 0
    readonly property int hostOriginY: root.body?.hostOriginY ?? 0
    readonly property int islandLayer: root.body?.hostLayer ?? WlrLayer.Top

    function requestKeyboardFocus() {
        root.body?.requestKeyboardFocus();
    }

    function containsGlobalPoint(gx, gy, padding) {
        return root.body?.containsGlobalPoint(gx, gy, padding) ?? false;
    }

    // The focus grab must include the dismiss layer, or Hyprland eats the first outside click to end the grab.
    Binding {
        target: root.body
        property: "dismissWindow"
        value: dismissWindow
        when: !!root.body
    }

    DIdleSurface {
        id: dismissWindow

        screen: root.screen
        active: !!root.islandController && root.islandController.outsideClickCollapses && !PopoutManager.screenshotActive
        renders: false

        WlrLayershell.namespace: "dms:dankisland:dismiss"
        WlrLayershell.layer: root.islandLayer
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region {
            item: dismissWindow.active ? dismissMask : null

            Region {
                item: islandHole
                intersection: Intersection.Subtract
            }

            Region {
                item: fittsStripHole
                intersection: Intersection.Subtract
            }

            Region {
                item: leadingSectionHole
                intersection: Intersection.Subtract
            }

            Region {
                item: centerSectionHole
                intersection: Intersection.Subtract
            }

            Region {
                item: trailingSectionHole
                intersection: Intersection.Subtract
            }
        }

        Rectangle {
            id: dismissMask

            anchors.fill: parent
            visible: false
            color: "transparent"
        }

        Item {
            id: islandHole

            readonly property var mask: dismissWindow.active ? root.body?.inputMaskItem ?? null : null
            x: mask ? mask.x + root.hostOriginX : 0
            y: mask ? mask.y + root.hostOriginY : 0
            width: mask?.width ?? 0
            height: mask?.height ?? 0
        }

        Item {
            id: fittsStripHole

            readonly property var strip: dismissWindow.active ? root.body?.fittsStripItem ?? null : null
            x: strip ? strip.x + root.hostOriginX : 0
            y: strip ? strip.y + root.hostOriginY : 0
            width: strip?.visible ? strip.width : 0
            height: strip?.visible ? strip.height : 0
        }

        Item {
            id: leadingSectionHole

            readonly property var r: dismissWindow.active ? root.body?.leadingSectionRect ?? null : null
            x: r ? r.x + root.body.sectionOriginX : 0
            y: r ? r.y + root.body.sectionOriginY : 0
            width: r?.w ?? 0
            height: r?.h ?? 0
        }

        // A hosted island shares the centre section with other widgets; they stay clickable while the sheet is out.
        Item {
            id: centerSectionHole

            readonly property var r: dismissWindow.active ? root.body?.centerSectionRect ?? null : null
            x: r ? r.x + root.body.sectionOriginX : 0
            y: r ? r.y + root.body.sectionOriginY : 0
            width: r?.w ?? 0
            height: r?.h ?? 0
        }

        Item {
            id: trailingSectionHole

            readonly property var r: dismissWindow.active ? root.body?.trailingSectionRect ?? null : null
            x: r ? r.x + root.body.sectionOriginX : 0
            y: r ? r.y + root.body.sectionOriginY : 0
            width: r?.w ?? 0
            height: r?.h ?? 0
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            onPressed: mouse => {
                root.islandController?.requestCollapse();
                mouse.accepted = true;
            }
        }
    }
}
