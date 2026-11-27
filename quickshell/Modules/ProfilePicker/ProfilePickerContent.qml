pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash

FocusScope {
    id: root

    property string view: "carousel"
    property var targetScreen: null
    property real availableWidth: screenWidth

    signal closeRequested
    signal selectionRevealRequested(bool instant)

    readonly property real carouselCardRatio: 0.41
    readonly property real carouselPitchRatio: 0.87
    readonly property real carouselSideScale: 0.72
    readonly property real carouselFarAlpha: 0.55
    readonly property int wheelNotch: 120
    readonly property int carouselSideSlots: 2
    readonly property int dashVisibleSlots: 1
    readonly property real dashCardRatio: 0.18
    readonly property real dashPadding: Theme.spacingS
    readonly property real gridWidthRatio: 0.84
    readonly property real gridHeightRatio: 0.8
    readonly property real gridCardMaxRatio: 0.41
    readonly property int gridSingleRowMax: 3
    readonly property int gridSquareCount: 4
    readonly property int gridSquareColumns: 2
    readonly property int gridThreeColumnMax: 6
    readonly property int gridMaxColumns: 4
    readonly property real gridGap: Theme.spacingXL

    readonly property bool isGrid: view === "grid"
    readonly property bool isDash: view === "dash"
    readonly property real screenWidth: targetScreen?.width ?? Screen.width
    readonly property real screenHeight: targetScreen?.height ?? Screen.height
    readonly property real spanWidth: Math.min(availableWidth, screenWidth)

    readonly property int profileCount: ConfigProfileService.profiles.length
    property string selectedId: ""
    // Remaps by id when the list is rebuilt while open; a removed selection falls back to the active profile.
    readonly property int selectedIndex: {
        const profiles = ConfigProfileService.profiles;
        const index = profiles.findIndex(p => p.id === selectedId);
        if (index >= 0)
            return index;
        const active = profiles.findIndex(p => p.id === ConfigProfileService.activeProfileId);
        return active >= 0 ? active : (profiles.length > 0 ? 0 : -1);
    }
    property bool animateSelection: true

    readonly property int gridColumns: {
        const n = profileCount;
        if (n <= gridSingleRowMax)
            return Math.max(1, n);
        if (n === gridSquareCount)
            return gridSquareColumns;
        return n <= gridThreeColumnMax ? gridSingleRowMax : gridMaxColumns;
    }
    readonly property real gridWidth: Math.min(availableWidth, screenWidth * gridWidthRatio)
    readonly property real carouselCardWidth: Math.round(spanWidth * carouselCardRatio)
    readonly property real dashCardWidth: Math.round(Math.min(screenWidth * dashCardRatio, (spanWidth - 2 * dashPadding) * DashMetrics.carouselItemRatio))
    readonly property real gridCardWidth: Math.floor(Math.min(screenWidth * gridCardMaxRatio, (gridWidth - gridColumns * gridGap) / gridColumns))
    readonly property real cardWidth: isGrid ? gridCardWidth : isDash ? dashCardWidth : carouselCardWidth
    readonly property real cardHeight: sizeProbe.implicitHeight
    readonly property int gridRows: Math.ceil(profileCount / gridColumns)

    implicitWidth: isGrid ? gridColumns * (cardWidth + gridGap) : spanWidth
    implicitHeight: isGrid ? Math.min(gridRows * (cardHeight + gridGap), Math.floor(screenHeight * gridHeightRatio)) : cardHeight + (isDash ? 2 * dashPadding : 0)

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    // Hover only selects after the pointer really moved, not when cards move under a resting one.
    property bool hoverSelects: false
    property point hoverOrigin: Qt.point(NaN, NaN)

    function reset() {
        hoverSelects = false;
        hoverOrigin = Qt.point(NaN, NaN);
        animateSelection = false;
        selectedId = ConfigProfileService.activeProfileId || (ConfigProfileService.profiles[0]?.id ?? "");
        selectionRevealRequested(true);
        Qt.callLater(() => root.animateSelection = true);
    }

    function focusContent() {
        forceActiveFocus();
    }

    function select(index) {
        if (index === selectedIndex)
            return;
        hoverSelects = false;
        selectedId = ConfigProfileService.profiles[index].id;
        selectionRevealRequested(false);
    }

    function step(delta) {
        if (selectedIndex >= 0)
            select(((selectedIndex + delta) % profileCount + profileCount) % profileCount);
    }

    // Up and Down wrap within the column; the last row can be shorter.
    function stepRow(down) {
        if (selectedIndex < 0)
            return;
        const column = selectedIndex % gridColumns;
        if (down)
            select(selectedIndex + gridColumns < profileCount ? selectedIndex + gridColumns : column);
        else
            select(selectedIndex >= gridColumns ? selectedIndex - gridColumns : column + gridColumns * Math.floor((profileCount - 1 - column) / gridColumns));
    }

    property string pendingId: ""
    readonly property bool shown: visible && (Window.window?.visible ?? false)

    onShownChanged: {
        if (!shown)
            activatePending();
    }
    Component.onDestruction: activatePending()

    // Waits for the host to finish closing, so a switch transition freezes the screen without the picker.
    function apply(id) {
        pendingId = id;
        closeLimit.restart();
        closeRequested();
    }

    // The applied profile can rebuild the host, so nothing may touch this item after activate().
    function activatePending() {
        const id = pendingId;
        if (!id)
            return;
        pendingId = "";
        closeLimit.stop();
        // Out of the host's close handler, which may still be running.
        Qt.callLater(ConfigProfileService.activate, id);
    }

    Timer {
        id: closeLimit
        interval: Timing.settleSlow
        onTriggered: root.activatePending()
    }

    onProfileCountChanged: {
        if (profileCount === 0 && visible)
            closeRequested();
    }

    // In the dash, keys arrive through the tab's handleKeyEvent instead.
    Keys.enabled: !isDash
    Keys.onPressed: event => event.accepted = handleKey(event)

    function handleKey(event) {
        const forward = I18n.isRtl ? -1 : 1;
        switch (event.key) {
        case Qt.Key_Left:
            step(-forward);
            break;
        case Qt.Key_Right:
            step(forward);
            break;
        case Qt.Key_Up:
        case Qt.Key_Down:
            if (!isGrid)
                return false;
            stepRow(event.key === Qt.Key_Down);
            break;
        case Qt.Key_Home:
            if (profileCount > 0)
                select(0);
            break;
        case Qt.Key_End:
            if (profileCount > 0)
                select(profileCount - 1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (selectedIndex >= 0)
                apply(ConfigProfileService.profiles[selectedIndex].id);
            break;
        case Qt.Key_Escape:
            closeRequested();
            break;
        default:
            return false;
        }
        return true;
    }

    HoverHandler {
        enabled: root.isGrid
        onPointChanged: {
            const pos = point.scenePosition;
            if (!root.hoverSelects && !isNaN(root.hoverOrigin.x) && (pos.x !== root.hoverOrigin.x || pos.y !== root.hoverOrigin.y))
                root.hoverSelects = true;
            root.hoverOrigin = pos;
        }
    }

    WheelHandler {
        property int wheelDistance: 0

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            event.accepted = true;
            wheelDistance += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
            if (Math.abs(wheelDistance) < root.wheelNotch)
                return;
            root.step(wheelDistance > 0 ? -1 : 1);
            wheelDistance = 0;
        }
    }

    // Sizes the views before any delegate exists.
    ProfilePickerCard {
        id: sizeProbe
        visible: false
        width: root.cardWidth
        profile: ({
                "id": "",
                "name": ""
            })
        compact: root.isGrid
        targetScreen: root.targetScreen
    }

    // A click beside the floating carousel cards closes it, like a click on the shade around them.
    MouseArea {
        anchors.fill: parent
        enabled: root.view === "carousel"
        onClicked: root.closeRequested()
    }

    Loader {
        anchors.fill: parent
        anchors.margins: root.isDash ? root.dashPadding : 0
        sourceComponent: root.isGrid ? gridView : ringView
    }

    Component {
        id: ringView

        Item {
            id: ring

            readonly property int count: root.profileCount
            readonly property int selected: root.selectedIndex
            readonly property real pitch: root.cardWidth * (root.isDash ? 1 - DashMetrics.carouselOverlap : root.carouselPitchRatio)
            // Unwrapped, so a step across the wrap still moves one slot.
            property real target: 0
            property real position: 0
            property bool settled: false
            property int followedCount: -1

            // Wrapped the shorter way round; two profiles don't wrap, so the other one stays on one side.
            function ringOffset(index, from) {
                const d = index - from;
                if (count <= 2)
                    return d;
                const wrapped = ((d % count) + count) % count;
                return wrapped >= count / 2 ? wrapped - count : wrapped;
            }

            function follow() {
                if (selected < 0)
                    return;
                const instant = followedCount !== count;
                followedCount = count;
                target = count <= 2 || instant ? selected : target + ringOffset(selected, target);
                if (instant)
                    settled = false;
                position = target;
                settled = true;
            }

            clip: true

            onSelectedChanged: follow()
            onCountChanged: follow()
            Component.onCompleted: follow()

            Behavior on position {
                enabled: ring.settled && root.animateSelection && !Theme.reduceMotion

                NumberAnimation {
                    duration: Theme.expressiveDurations.expressiveDefaultSpatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
                }
            }

            Repeater {
                model: ConfigProfileService.profiles

                delegate: Item {
                    id: slide

                    required property int index
                    required property var modelData

                    readonly property real offset: ring.ringOffset(index, ring.position)
                    readonly property real distance: Math.abs(offset)
                    // Fades a card out before it wraps to the other side, so few profiles never show one twice.
                    readonly property real wrapFade: ring.count <= 2 ? 1 : Math.max(0, Math.min(1, (ring.count / 2 - distance) * 2))

                    x: (ring.width - width) / 2 + (I18n.isRtl ? -offset : offset) * ring.pitch
                    width: root.cardWidth
                    height: ring.height
                    z: -distance
                    visible: opacity > 0
                    scale: root.isDash ? 1 - (1 - DashMetrics.carouselSideScale) * Math.min(distance, root.dashVisibleSlots) : 1 - (1 - root.carouselSideScale) * Math.min(distance, root.carouselSideSlots)
                    opacity: {
                        if (root.isDash && distance <= root.dashVisibleSlots)
                            return wrapFade * (1 - (1 - DashMetrics.carouselSideAlpha) * distance);
                        if (root.isDash)
                            return wrapFade * Math.max(0, DashMetrics.carouselSideAlpha * (root.dashVisibleSlots + 1 - distance));
                        if (distance <= 1)
                            return wrapFade;
                        if (distance <= root.carouselSideSlots)
                            return wrapFade * (1 - (1 - root.carouselFarAlpha) * (distance - 1) / (root.carouselSideSlots - 1));
                        return wrapFade * Math.max(0, root.carouselFarAlpha * (root.carouselSideSlots + 1 - distance));
                    }

                    ProfilePickerCard {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        profile: slide.modelData
                        targetScreen: root.targetScreen
                        selected: slide.index === root.selectedIndex
                        showCaption: selected
                        onClicked: root.apply(slide.modelData.id)
                    }
                }
            }
        }
    }

    Component {
        id: gridView

        DGridView {
            id: grid

            model: ConfigProfileService.profiles
            cellWidth: root.cardWidth + root.gridGap
            cellHeight: root.cardHeight + root.gridGap
            interactive: false
            wheelEnabled: false
            keyNavigationEnabled: false
            activeFocusOnTab: false
            clip: true

            Component.onCompleted: {
                if (root.selectedIndex >= 0)
                    positionViewAtIndex(root.selectedIndex, GridView.Contain);
            }

            Connections {
                target: root
                function onSelectionRevealRequested(instant) {
                    if (root.selectedIndex < 0)
                        return;
                    if (instant)
                        grid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
                    else
                        grid.revealIndex(root.selectedIndex);
                }
            }

            delegate: Item {
                id: cell

                required property int index
                required property var modelData

                width: grid.cellWidth
                height: grid.cellHeight

                ProfilePickerCard {
                    readonly property bool pointerPicks: hovered && root.hoverSelects

                    anchors.centerIn: parent
                    width: root.cardWidth
                    profile: cell.modelData
                    targetScreen: root.targetScreen
                    compact: true
                    selected: cell.index === root.selectedIndex
                    onClicked: root.apply(cell.modelData.id)
                    onPointerPicksChanged: {
                        if (pointerPicks)
                            root.selectedId = cell.modelData.id;
                    }
                }
            }
        }
    }
}
