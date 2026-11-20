import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
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

    property point anchorPos: Qt.point(screen ? screen.width / 2 : 0, screen ? screen.height - 100 : 0)

    function show(button, dockHeight, dockScreen) {
        if (dockScreen)
            screen = dockScreen;
        surfaceContext = button?.dockApps?.surfaceContext ?? null;
        anchorItem = button;
        dockVisibleHeight = dockHeight || 40;
        visible = true;
    }

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
            if (isVertical) {
                const want = root.anchorPos.y - height / 2;
                return Math.max(10, Math.min(root.height - height - 10, want));
            }
            if (root.options.position === SettingsData.Position.Bottom)
                return Math.max(10, root.anchorPos.y - height);
            return Math.min(root.height - height - 10, root.anchorPos.y);
        }

        width: Math.min(root.menuMaxWidth, Math.max(root.menuMinWidth, menuColumn.implicitWidth + Theme.spacingS * 2))
        height: menuColumn.implicitHeight + Theme.spacingS * 2
        color: Theme.floatingSurface
        radius: Theme.windowRadius
        border.color: BlurService.borderColor
        border.width: BlurService.borderWidth

        opacity: root.visible ? 1 : 0
        visible: opacity > 0

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

        Column {
            id: menuColumn
            width: parent.width - Theme.spacingS * 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.spacingS
            spacing: 1
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.close()
    }
}
