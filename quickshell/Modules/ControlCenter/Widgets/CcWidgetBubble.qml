import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

StyledButton {
    id: item

    required property var entry
    property real bubbleSize: CcMetrics.previewSize
    property bool draggable: false
    property bool roundAll: true
    property var canStep: (dx, dy) => true

    signal dragStarted(point scenePoint)
    signal dragMoved(point scenePoint)
    signal dragEnded(bool canceled)
    signal step(int dx, int dy)

    height: preview.height + Theme.spacingS + label.implicitHeight
    Accessible.name: entry.text
    Accessible.description: entry.description ?? ""

    function tryStep(event, dx, dy) {
        event.accepted = canStep(dx, dy);
        if (event.accepted)
            step(dx, dy);
    }

    Keys.onLeftPressed: event => tryStep(event, I18n.isRtl ? 1 : -1, 0)
    Keys.onRightPressed: event => tryStep(event, I18n.isRtl ? -1 : 1, 0)
    Keys.onUpPressed: event => tryStep(event, 0, -1)
    Keys.onDownPressed: event => tryStep(event, 0, 1)

    Component.onDestruction: {
        if (drag.started)
            dragEnded(true);
    }

    Rectangle {
        id: preview

        anchors.horizontalCenter: parent.horizontalCenter
        width: item.bubbleSize
        height: width
        radius: item.roundAll || item.entry.id === "user" ? Theme.fullRadius(width, height) : Theme.cornerRadiusLIncreased
        color: CcMetrics.iconBoxInactiveColor

        DIcon {
            anchors.centerIn: parent
            name: item.entry.icon
            size: Theme.iconSizeLarge
            color: Theme.primary
            visible: item.entry.id !== "user" || PortalService.profileImageUrl === ""
        }

        Loader {
            anchors.fill: parent
            active: item.entry.id === "user" && PortalService.profileImageUrl !== ""
            sourceComponent: DCircularImage {
                imageSource: PortalService.profileImageUrl
                fallbackIcon: "material:person"
            }
        }

        FocusRing {
            visible: item.visualFocus
        }

        StateLayer {
            control: item
            stateColor: Theme.primary
        }
    }

    StyledText {
        id: label
        anchors.top: preview.bottom
        anchors.topMargin: Theme.spacingS
        width: parent.width
        text: item.entry.text
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
    }

    DragHandler {
        id: drag

        property bool started: false

        target: null
        enabled: item.draggable
        cursorShape: Qt.ClosedHandCursor
        // Once dragging, the list's flickable may not take the point back and cancel the drag.
        grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
        onActiveChanged: {
            if (!active)
                return;
            started = true;
            item.dragStarted(centroid.scenePosition);
        }
        // Qt deactivates before emitting canceled, so the drag ends here, where the transition says which it was.
        onGrabChanged: (transition, point) => {
            if (!started || active)
                return;
            if (transition !== PointerDevice.UngrabExclusive && transition !== PointerDevice.CancelGrabExclusive)
                return;
            started = false;
            item.dragEnded(transition === PointerDevice.CancelGrabExclusive);
        }
        onCentroidChanged: {
            if (active)
                item.dragMoved(centroid.scenePosition);
        }
    }
}
