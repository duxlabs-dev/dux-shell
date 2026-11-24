import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

PanelWindow {
    id: root
    property var options: ({})

    default property alias content: menuColumn.children

    property var anchorItem: null
    property var surfaceContext: null
    property real dockVisibleHeight: 40
    property int margin: 10
    property string layerNamespace: "dms:dock-context-menu"
    property real menuMaxWidth: 400
    property real menuMinWidth: 180
    // Growing from the top keeps the clicked row under the pointer.
    property real heldY: -1

    property point anchorPos: Qt.point(screen ? screen.width / 2 : 0, screen ? screen.height - 100 : 0)

    function show(button, dockHeight, dockScreen) {
        if (dockScreen)
            screen = dockScreen;
        surfaceContext = button?.dockApps?.surfaceContext ?? null;
        anchorItem = button;
        dockVisibleHeight = dockHeight || 40;
        heldY = -1;
        visible = true;
    }

    function holdPosition() {
        heldY = menuContainer.y;
    }

    function containsScenePoint(point) {
        return menuContainer.contains(menuContainer.mapFromItem(null, point.x, point.y));
    }

    readonly property alias menuSurface: menuContainer

    function close() {
        visible = false;
    }

    function updatePosition() {
        if (!anchorItem || !screen)
            return;
        const point = surfaceContext?.screenPoint(anchorItem, anchorItem.width / 2, anchorItem.height / 2);
        if (!point)
            return;
        const extent = (surfaceContext?.thickness ?? dockVisibleHeight) / 2 + Theme.spacingS;
        switch (root.options.position) {
        case SettingsData.Position.Left:
            anchorPos = Qt.point(point.x + extent, point.y);
            return;
        case SettingsData.Position.Right:
            anchorPos = Qt.point(point.x - extent, point.y);
            return;
        case SettingsData.Position.Top:
            anchorPos = Qt.point(point.x, point.y + extent);
            return;
        default:
            anchorPos = Qt.point(point.x, point.y - extent);
        }
    }

    onAnchorItemChanged: {
        if (!anchorItem) {
            close();
            return;
        }
        updatePosition();
    }
    onVisibleChanged: {
        if (visible) {
            updatePosition();
            return;
        }
        anchorItem = null;
        surfaceContext = null;
        heldY = -1;
    }

    WindowBlur {
        targetWindow: root
        surfaceColor: menuContainer.color
        blurX: menuContainer.x
        blurY: menuContainer.y
        blurWidth: root.visible ? menuContainer.width : 0
        blurHeight: root.visible ? menuContainer.height : 0
        blurRadius: Theme.windowRadius
    }

    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    screen: null
    visible: false
    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    Rectangle {
        id: menuContainer

        readonly property bool isVertical: root.options.position === SettingsData.Position.Left || root.options.position === SettingsData.Position.Right

        x: {
            if (!isVertical) {
                const want = root.anchorPos.x - width / 2;
                return Math.max(10, Math.min(root.width - width - 10, want));
            }
            if (root.options.position === SettingsData.Position.Right)
                return Math.max(10, root.anchorPos.x - width);
            return Math.min(root.width - width - 10, root.anchorPos.x);
        }
        y: {
            if (root.heldY >= 0) {
                const bottom = root.options.position === SettingsData.Position.Bottom ? root.anchorPos.y : root.height - 10;
                return Math.max(10, Math.min(bottom - height, root.heldY));
            }
            if (isVertical) {
                const want = root.anchorPos.y - height / 2;
                return Math.max(10, Math.min(root.height - height - 10, want));
            }
            if (root.options.position === SettingsData.Position.Bottom)
                return Math.max(10, root.anchorPos.y - height);
            return Math.min(root.height - height - 10, root.anchorPos.y);
        }

        width: Math.min(root.menuMaxWidth, Math.max(root.menuMinWidth, menuColumn.implicitWidth + Theme.spacingS * 2))
        height: Math.min(root.height - 20, menuColumn.implicitHeight + Theme.spacingS * 2)
        color: Theme.floatingSurface
        radius: Theme.windowRadius
        border.color: BlurService.borderColor
        border.width: BlurService.borderWidth

        opacity: root.visible ? 1 : 0
        visible: opacity > 0

        Behavior on height {
            enabled: root.heldY >= 0
            NumberAnimation {
                duration: Theme.reduceMotion ? 0 : Theme.expressiveDurations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveFastEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.leftMargin: 2
            anchors.rightMargin: -2
            anchors.bottomMargin: -4
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.15)
            z: -1
        }

        DFlickable {
            id: menuFlickable
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            clip: true
            contentWidth: width
            contentHeight: menuColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height + 0.5

            Column {
                id: menuColumn
                width: menuFlickable.width
                spacing: 1
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.close()
    }
}
