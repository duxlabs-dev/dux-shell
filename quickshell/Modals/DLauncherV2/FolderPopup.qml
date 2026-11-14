pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.DLauncherV2.Components

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var controller: null
    property var host: null
    property Item focusReturnTarget: null
    property bool animationsEnabled: true
    property int liftedMemberIndex: -1
    property bool dragActive: false
    property bool memberDragOutside: false

    signal dismissed
    signal memberRightClicked(var item, real sceneX, real sceneY)
    signal memberDragPressed(Item tile, int memberIndex, real sceneX, real sceneY)
    signal memberDragMoved(real sceneX, real sceneY)
    signal memberDragReleased(real sceneX, real sceneY)
    signal memberDragCanceled

    // Keep members alive for the close transition.
    property string folderId: ""
    property var members: []
    property string membersKey: ""
    property int columns: 1

    property bool closing: false
    property bool enterPending: false
    property bool hasAnchor: false
    property rect anchorRect: Qt.rect(0, 0, 0, 0)

    // Avoid rebuilding delegates while a member is being dragged.
    readonly property string liveMembersKey: (controller?.folderMembers ?? []).map(member => member.id + "\t" + member.name + "\t" + member.icon).join("\n")
    readonly property string liveName: controller?.activeFolder?.name ?? ""
    readonly property bool renamePending: controller?.folderRenamePending ?? false
    readonly property int selectedIndex: controller?.folderSelectedIndex ?? -1
    readonly property bool animate: animationsEnabled && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None && !SettingsData.reduceMotion
    readonly property bool transitioning: enterPending || enterAnimation.running || exitAnimation.running

    readonly property real padding: Theme.spacingL
    readonly property real headerHeight: Theme.buttonHeightS
    readonly property real cellHeight: LauncherMetrics.iconsCellHeight
    readonly property int maxVisibleRows: LauncherMetrics.folderMaxVisibleRows
    readonly property int rowCount: Math.ceil(members.length / columns)
    readonly property real finalWidth: Math.max(0, Math.min(width - padding * 2, columns * cellHeight + padding * 2))
    readonly property real finalHeight: Math.max(0, Math.min(height - padding * 2, padding * 2 + headerHeight + Theme.spacingS + Math.min(rowCount, maxVisibleRows) * cellHeight))
    readonly property real anchorGap: LauncherMetrics.folderAnchorGap
    readonly property real anchorCenterX: anchorRect.x + anchorRect.width / 2
    readonly property real anchorCenterY: anchorRect.y + anchorRect.height / 2
    readonly property bool fitsBelow: anchorRect.y + anchorRect.height + anchorGap + finalHeight <= height - padding
    readonly property real anchoredY: fitsBelow ? anchorRect.y + anchorRect.height + anchorGap : anchorRect.y - anchorGap - finalHeight
    readonly property real surfaceX: hasAnchor ? _clamp(anchorCenterX - finalWidth / 2, padding, width - padding - finalWidth) : (width - finalWidth) / 2
    readonly property real surfaceY: hasAnchor ? _clamp(anchoredY, padding, height - padding - finalHeight) : (height - finalHeight) / 2
    readonly property real scaleOriginX: hasAnchor ? _clamp(anchorCenterX - surfaceX, 0, finalWidth) : finalWidth / 2
    readonly property real scaleOriginY: hasAnchor ? _clamp(anchorCenterY - surfaceY, 0, finalHeight) : finalHeight / 2

    layer.enabled: transitioning
    Accessible.role: Accessible.Dialog
    Accessible.name: nameField.text

    onLiveMembersKeyChanged: _syncSnapshot()
    onLiveNameChanged: {
        if (closing || !liveName || nameField.getActiveFocus())
            return;
        nameField.text = liveName;
    }
    onRenamePendingChanged: _consumeRenamePending()
    onSelectedIndexChanged: {
        if (!controller?.keyboardNavigationActive || selectedIndex < 0)
            return;
        const row = Math.floor(selectedIndex / columns);
        flick.revealRange(row * cellHeight, (row + 1) * cellHeight);
    }

    Component.onCompleted: {
        folderId = controller?.activeFolderId ?? "";
        _syncSnapshot();
        nameField.text = liveName;
        _consumeRenamePending();
    }

    function open(id) {
        folderId = id;
        closing = false;
        _syncSnapshot();
        if (!nameField.getActiveFocus())
            nameField.text = liveName;
        exitAnimation.stop();
        enterAnimation.stop();
        // Resolve after delegates rebuild, including with reduced motion.
        enterPending = true;
        opacity = 0;
        surface.entryScale = animate ? LauncherMetrics.popupEnterScale : 1;
    }

    function close() {
        if (closing)
            return true;
        _commitName(nameField.text);
        if (nameField.getActiveFocus())
            focusReturnTarget?.forceActiveFocus();
        closing = true;
        enterPending = false;
        enterAnimation.stop();
        if (!animate || opacity === 0)
            return false;
        exitAnimation.start();
        return true;
    }

    function surfaceContains(sceneX, sceneY) {
        const point = surface.mapFromItem(null, sceneX, sceneY);
        return point.x >= 0 && point.y >= 0 && point.x <= surface.width && point.y <= surface.height;
    }

    function memberIndexAt(sceneX, sceneY) {
        const viewport = flick.mapFromItem(null, sceneX, sceneY);
        if (viewport.x < 0 || viewport.y < 0 || viewport.x >= flick.width || viewport.y >= flick.height)
            return -1;
        const cellWidth = flick.width / columns;
        const column = Math.floor((I18n.isRtl ? flick.width - viewport.x : viewport.x) / cellWidth);
        const row = Math.floor((viewport.y + flick.contentY) / cellHeight);
        const index = row * columns + column;
        if (column < 0 || column >= columns || index >= members.length)
            return -1;
        return index;
    }

    function selectedCellScenePosition() {
        const index = Math.max(0, selectedIndex);
        const cellWidth = flick.width / columns;
        const column = index % columns;
        const x = (I18n.isRtl ? flick.width - (column + 1) * cellWidth : column * cellWidth) + cellWidth / 2;
        const y = Math.floor(index / columns) * cellHeight - flick.contentY + cellHeight / 2;
        return flick.mapToItem(null, x, Math.max(0, Math.min(flick.height, y)));
    }

    function _syncSnapshot() {
        if (closing || !liveMembersKey || liveMembersKey === membersKey)
            return;
        membersKey = liveMembersKey;
        members = controller.folderMembers;
        columns = controller.folderColumns;
    }

    function _resolveAnchor() {
        _setAnchor(host?.cellSceneRect(controller?.folderOriginFlatIndex ?? -1, "folder:" + folderId) ?? null);
    }

    function _setAnchor(sceneRect) {
        hasAnchor = !!sceneRect;
        if (!sceneRect)
            return;
        const point = mapFromItem(null, sceneRect.x, sceneRect.y);
        anchorRect = Qt.rect(point.x, point.y, sceneRect.width, sceneRect.height);
    }

    function _clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function _consumeRenamePending() {
        if (!renamePending || closing)
            return;
        nameField.forceActiveFocus();
        nameField.selectAll();
        controller.folderRenamePending = false;
    }

    function _commitName(text) {
        const folder = SessionData.getLauncherFolder(folderId);
        if (!folder)
            return;
        const name = text.trim();
        if (name.length === 0) {
            nameField.text = folder.name;
            return;
        }
        if (name !== folder.name)
            SessionData.renameLauncherFolder(folderId, name);
    }

    function _acceptName(event) {
        _commitName(nameField.text);
        focusReturnTarget?.forceActiveFocus();
        event.accepted = true;
    }

    TextMetrics {
        id: nameMetrics
        font: nameField.font
        text: nameField.text || nameField.placeholderText
    }

    Connections {
        target: root.Window.window
        enabled: root.enterPending

        function onFrameSwapped() {
            root.enterPending = false;
            root._resolveAnchor();
            if (root.animate)
                enterAnimation.start();
            else
                root.opacity = 1;
        }
    }

    ParallelAnimation {
        id: enterAnimation

        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
        NumberAnimation {
            target: surface
            property: "entryScale"
            to: 1
            duration: Theme.expressiveDurations.expressiveDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
        }
    }

    NumberAnimation {
        id: exitAnimation
        target: root
        property: "opacity"
        to: 0
        duration: Theme.expressiveDurations.expressiveEffects
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        onFinished: root.dismissed()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrimColor
        opacity: Theme.scrimAlpha
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.closing
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onClicked: root.controller?.closeLauncherFolder()
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        id: surface

        property real entryScale: 1

        x: root.surfaceX
        y: root.surfaceY
        width: root.finalWidth
        height: root.finalHeight
        radius: Theme.cornerRadiusXL
        color: Theme.foregroundColor(Theme.hostSurface, Theme.isFloatingWindow(root))
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        transform: Scale {
            origin.x: root.scaleOriginX
            origin.y: root.scaleOriginY
            xScale: surface.entryScale
            yScale: surface.entryScale
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        DTextField {
            id: nameField

            anchors.top: parent.top
            anchors.topMargin: root.padding
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - root.padding * 2, nameMetrics.advanceWidth + leftPadding + rightPadding + Theme.spacingXS)
            height: root.headerHeight
            controlHeight: root.headerHeight
            cornerRadius: Theme.fullRadius(width, height)
            backgroundColor: "transparent"
            normalBorderColor: "transparent"
            textColor: Theme.onSurface
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightMedium
            placeholderText: I18n.tr("Folder")
            onEditingFinished: root._commitName(text)
            Keys.onReturnPressed: event => root._acceptName(event)
            Keys.onEnterPressed: event => root._acceptName(event)
            Keys.onEscapePressed: event => {
                nameField.text = SessionData.getLauncherFolder(root.folderId)?.name ?? root.liveName;
                root.focusReturnTarget?.forceActiveFocus();
                event.accepted = true;
            }
        }

        DFlickable {
            id: flick

            anchors.top: nameField.bottom
            anchors.topMargin: Theme.spacingS
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: root.padding
            contentWidth: width
            contentHeight: root.rowCount * root.cellHeight
            clip: true
            interactive: !root.dragActive && contentHeight > height

            LauncherHighlight {
                readonly property real cellWidth: flick.width / root.columns
                readonly property int column: root.selectedIndex % root.columns
                visible: root.selectedIndex >= 0 && root.selectedIndex < root.members.length
                x: (I18n.isRtl ? flick.width - (column + 1) * cellWidth : column * cellWidth) + LauncherMetrics.tileGap / 2
                y: Math.floor(root.selectedIndex / root.columns) * root.cellHeight + LauncherMetrics.tileGap / 2
                width: cellWidth - LauncherMetrics.tileGap
                height: root.cellHeight - LauncherMetrics.tileGap
            }

            Grid {
                columns: root.columns

                Repeater {
                    model: root.members

                    Item {
                        id: cell

                        required property var modelData
                        required property int index

                        width: flick.width / root.columns
                        height: root.cellHeight

                        LauncherTile {
                            id: tile

                            anchors.fill: parent
                            anchors.margins: LauncherMetrics.tileGap / 2
                            bare: true
                            externalHighlight: true
                            item: cell.modelData
                            isSelected: cell.index === root.selectedIndex
                            controller: root.controller
                            dragSource: cell.index === root.liftedMemberIndex

                            onClicked: root.controller?.executeItem(cell.modelData)
                            onRightClicked: (sceneX, sceneY) => root.memberRightClicked(cell.modelData, sceneX, sceneY)
                            onDragPressed: (sceneX, sceneY) => root.memberDragPressed(tile, cell.index, sceneX, sceneY)
                            onDragMoved: (sceneX, sceneY) => root.memberDragMoved(sceneX, sceneY)
                            onDragReleased: (sceneX, sceneY) => root.memberDragReleased(sceneX, sceneY)
                            onDragCanceled: root.memberDragCanceled()
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: removeCue

        readonly property bool shown: root.memberDragOutside && !root.closing
        readonly property bool fitsBelow: surface.y + surface.height + root.anchorGap + height <= root.height - root.padding

        x: root._clamp(surface.x + (surface.width - width) / 2, root.padding, root.width - root.padding - width)
        y: fitsBelow ? surface.y + surface.height + root.anchorGap : surface.y - root.anchorGap - height
        width: cueRow.implicitWidth + Theme.spacingM * 2
        height: Theme.buttonHeightXS
        radius: Theme.fullRadius(width, height)
        color: Theme.inverseSurface
        visible: opacity > 0
        opacity: shown ? 1 : 0

        Behavior on opacity {
            enabled: root.animate
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        Row {
            id: cueRow

            anchors.centerIn: parent
            spacing: Theme.spacingXS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "folder_off"
                size: Theme.iconSizeSmall
                color: Theme.inverseOnSurface
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Remove from folder")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.inverseOnSurface
            }
        }
    }
}
