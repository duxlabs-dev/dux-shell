import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

DCard {
    id: card

    required property var profile
    required property var reorderList
    required property int index
    property bool compact: false
    property var targetScreen: null

    signal editRequested(string id)
    signal menuRequested(real x, real y, bool keyboard)

    readonly property bool isActive: profile.id === ConfigProfileService.activeProfileId
    readonly property bool dragging: reorderList.draggingIndex === index

    function focusHandle(reason) {
        card.forceActiveFocus(reason);
    }

    implicitHeight: previewArea.height + nameRow.implicitHeight + Theme.spacingS * 2 + Theme.spacingXS
    pad: 0
    radius: Theme.cornerRadiusM
    color: dragging ? Theme.blend(SettingsMetrics.rowColor, Theme.onSurface, Theme.stateLayerDrag) : SettingsMetrics.rowColor
    z: dragging ? 1 : 0
    border.color: isActive ? Theme.primary : Theme.outlineMedium
    border.width: isActive ? Theme.outlineWidthFocused : Theme.layerOutlineWidth
    clickable: true
    Accessible.name: profile.name
    Accessible.description: [isActive ? I18n.tr("Active") + (profile.sync ? ", " + I18n.tr("Synchronized", "config profile, screen reader: setting changes are saved into the active profile") : "") : "", reorderList.count > 1 ? I18n.tr("Drag to reorder") : ""].filter(s => s).join(". ")
    onClicked: ConfigProfileService.activate(profile.id)
    Keys.onPressed: event => {
        const vertical = reorderList.columns <= 1;
        const back = vertical ? Qt.Key_Up : Qt.Key_Left;
        const forward = vertical ? Qt.Key_Down : Qt.Key_Right;
        if (event.modifiers & Qt.ControlModifier && (event.key === back || event.key === forward)) {
            const delta = (event.key === back) === (I18n.isRtl && !vertical) ? 1 : -1;
            const target = index + delta;
            if (reorderList.count > 1 && target >= 0 && target < reorderList.count) {
                reorderList.move(index, delta);
                event.accepted = true;
            }
            return;
        }
        if (event.key !== Qt.Key_Menu && !(event.key === Qt.Key_F10 && event.modifiers & Qt.ShiftModifier))
            return;
        card.menuRequested(width / 2, height / 2, true);
        event.accepted = true;
    }

    DragHandler {
        target: null
        // Not on the content layer: there its passive grab swallows plain clicks.
        parent: card.focusTarget
        enabled: card.reorderList.count > 1
        cursorShape: Qt.ClosedHandCursor
        // Keeps the page's flickable from taking the drag over.
        grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
        onGrabChanged: (transition, point) => {
            const list = card.reorderList;
            switch (transition) {
            case PointerDevice.GrabExclusive:
                list.begin(card.index, list.mapFromItem(null, point.scenePressPosition.x, point.scenePressPosition.y));
                list.dragTo(list.mapFromItem(null, point.scenePosition.x, point.scenePosition.y));
                return;
            case PointerDevice.UngrabExclusive:
                if (card.dragging)
                    list.finish();
                return;
            case PointerDevice.CancelGrabExclusive:
                list.cancel();
                return;
            }
        }
        onCentroidChanged: {
            if (active && card.dragging)
                card.reorderList.dragTo(card.reorderList.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y));
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: eventPoint => card.menuRequested(eventPoint.position.x, eventPoint.position.y, false)
    }

    Item {
        id: previewArea
        z: 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingS
        height: preview.implicitHeight

        ProfilePreview {
            id: preview
            anchors.fill: parent
            owner: card.profile
            targetScreen: card.targetScreen
        }

        PluginBadge {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: Theme.spacingXS
            iconName: "sync"
            tone: Theme.primary
            visible: card.isActive && !!card.profile.sync
        }
    }

    Row {
        id: nameRow
        z: 1
        anchors.top: previewArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.spacingXS
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        spacing: Theme.spacingS

        StyledText {
            width: parent.width - (editButton.visible ? editButton.width + parent.spacing : 0)
            text: card.profile.name
            font.pixelSize: card.compact ? Theme.fontSizeSmall : Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: card.isActive ? Theme.primary : Theme.surfaceText
            elide: Text.ElideRight
            maximumLineCount: 1
            anchors.verticalCenter: parent.verticalCenter
        }

        DIconButton {
            id: editButton
            visible: !card.compact
            iconName: "edit"
            variant: "tonal"
            tooltipText: I18n.tr("Edit")
            anchors.verticalCenter: parent.verticalCenter
            onClicked: card.editRequested(card.profile.id)
        }
    }

    Behavior on x {
        enabled: card.reorderList.animateLayout && !card.dragging && !Theme.reduceMotion
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    Behavior on y {
        enabled: card.reorderList.animateLayout && !card.dragging && !Theme.reduceMotion
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }
}
