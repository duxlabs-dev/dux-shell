pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.DLauncherV2.Components
import qs.Widgets as Widgets
import "../../Common/settings/AppFolders.js" as AppFolders

DockContextMenuBase {
    id: root

    layerNamespace: "dms:dock-folder-menu"
    // Minimum two cells leaves room for the title next to the options button.
    menuMinWidth: Math.max(2, columns) * tileWidth + Theme.spacingL * 2
    menuMaxWidth: menuMinWidth
    WlrLayershell.keyboardFocus: screenshotActive ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
    mask: screenshotActive ? screenshotMask : actions.renderActive ? null : folderMask

    property Region screenshotMask: Region {}
    property Region folderMask: Region {
        item: root.contentItem
        Region {
            intersection: Intersection.Subtract
            x: root.dockBounds.x
            y: root.dockBounds.y
            width: root.dockBounds.width
            height: root.dockBounds.height
        }
        Region {
            item: root.menuSurface
        }
    }

    readonly property var strip: anchorItem?.dockApps ?? null
    readonly property var folder: visible ? AppFolders.folderById(strip?.pinnedApps, anchorItem?.appData?.folder?.id) : null
    readonly property var members: folder && strip ? strip.folderMembers(folder) : []
    readonly property bool screenshotActive: PopoutManager.screenshotActive
    readonly property rect dockBounds: {
        const dockStrip = visible ? strip?.mixedStrip : null;
        if (!dockStrip)
            return Qt.rect(0, 0, 0, 0);
        dockStrip.x;
        dockStrip.y;
        const origin = surfaceContext?.screenPoint(dockStrip, 0, 0);
        return origin ? Qt.rect(origin.x, origin.y, dockStrip.width, dockStrip.height) : Qt.rect(0, 0, 0, 0);
    }
    readonly property int columns: Math.min(LauncherMetrics.folderMaxColumns, Math.max(1, members.length))
    readonly property real iconSize: anchorItem?.actualIconSize ?? LauncherMetrics.iconsIconSize
    readonly property real tileWidth: Math.max(LauncherMetrics.iconsCellHeight, iconSize + Theme.spacingXL * 2)
    readonly property real tileHeight: LauncherMetrics.iconsCellHeight - LauncherMetrics.iconsIconSize + iconSize
    readonly property var windows: anchorItem?.appData?.allWindows ?? []
    readonly property bool memberDragActive: draggedMember !== null
    readonly property string hoveredMemberId: memberDragActive ? memberAt(dragPoint) : ""
    readonly property bool memberDragOutside: memberDragActive && !containsScenePoint(dragPoint)
    property var draggedMember: null
    property point dragPoint
    property bool receivingPin: false
    property bool renaming: false

    onScreenshotActiveChanged: {
        if (screenshotActive)
            draggedMember = null;
    }
    onFolderChanged: {
        if (!folder && visible)
            close();
    }
    onVisibleChanged: {
        if (visible) {
            panel?.forceActiveFocus();
        } else {
            actions?.hide();
            draggedMember = null;
            receivingPin = false;
            renaming = false;
            if (list)
                list.contentY = 0;
        }
    }

    function memberWindows(member) {
        return windows.filter(window => window.appId === member.appId).map(window => window.toplevel);
    }
    function launch(member) {
        const toplevels = memberWindows(member);
        const button = anchorItem;
        if (toplevels.length && button) {
            const focused = toplevels.findIndex(toplevel => button.isToplevelFocused(toplevel));
            button.activateWindow(toplevels[(focused + 1) % toplevels.length]);
        } else {
            strip?.launchApp(member.appId, member.core, member.entry);
        }
        close();
    }
    function memberAt(point) {
        const viewport = list.mapFromItem(null, point.x, point.y);
        if (!list.contains(viewport))
            return "";
        const index = AppFolders.memberGridIndex(viewport.x - grid.inset, viewport.y + list.contentY, columns * tileWidth, tileHeight, columns, I18n.isRtl);
        return members[index]?.id ?? "";
    }
    function updatePinDrop(item, x, y) {
        const point = folder && !actions.renderActive && !screenshotActive ? surfaceContext?.screenPoint(item, x, y) : null;
        receivingPin = !!point && containsScenePoint(point);
        return receivingPin ? "folder:" + folder.id : "";
    }
    function finishMemberDrag(point) {
        const sourceId = draggedMember?.id;
        draggedMember = null;
        if (!sourceId)
            return;
        const outside = !containsScenePoint(point);
        const targetId = outside ? "" : memberAt(point);
        if (!outside && (!targetId || targetId === sourceId))
            return;
        scheduleMemberDrop(sourceId, targetId);
    }
    function scheduleMemberDrop(sourceId, targetId = "") {
        if (!folder)
            return;
        memberDrop.folderId = folder.id;
        memberDrop.sourceId = sourceId;
        memberDrop.targetId = targetId;
        memberDrop.schedule();
    }
    function finishRename(name) {
        if (!renaming)
            return;
        renameCommit.name = name;
        renameCommit.schedule();
    }
    function openActions(item, x, y, memberId = "", keyboard = false) {
        actions.menuItems = memberId ? [
            {
                type: "item",
                text: I18n.tr("Remove from folder"),
                icon: "drive_file_move",
                action: () => root.scheduleMemberDrop(memberId)
            }
        ] : [
            {
                type: "item",
                text: I18n.tr("Rename"),
                icon: "edit",
                action: () => root.renaming = true
            },
            {
                type: "item",
                text: I18n.tr("Dissolve folder"),
                icon: "folder_delete",
                action: () => {
                    if (root.folder)
                        root.strip?.dissolveFolder(root.folder.id);
                    root.close();
                }
            }
        ];
        const point = item.mapToItem(null, x, y);
        actions.openInWindow(root, point.x, point.y, keyboard);
    }

    // A drop can remove the member delegate delivering the release.
    property DeferredAction memberDrop: DeferredAction {
        enabled: root.visible
        property string folderId
        property string sourceId
        property string targetId
        onTriggered: {
            if (root.folder?.id !== folderId)
                return;
            if (targetId)
                root.strip?.moveFolderApp(folderId, sourceId, targetId);
            else
                root.strip?.extractFolderApp(folderId, sourceId);
        }
    }

    property DeferredAction renameCommit: DeferredAction {
        enabled: root.visible && root.renaming
        property string name
        onTriggered: {
            root.renaming = false;
            if (root.folder && name.trim())
                root.strip?.renameFolder(root.folder.id, name);
        }
    }

    FocusScope {
        id: panel
        width: Math.max(0, Math.min(root.menuMinWidth, root.menuMaxWidth) - Theme.spacingS * 2)
        height: content.implicitHeight + (Theme.spacingL - Theme.spacingS) * 2
        Keys.onEscapePressed: {
            if (root.memberDragActive)
                root.draggedMember = null;
            else
                root.close();
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadiusM
            color: "transparent"
            border.color: Theme.primary
            border.width: Theme.outlineWidth * 2
            visible: root.receivingPin
        }

        Loader {
            parent: root.contentItem
            z: 1
            active: root.memberDragActive
            x: Math.max(0, Math.min(root.width - width, root.dragPoint.x - width / 2))
            y: Math.max(0, Math.min(root.height - height, root.dragPoint.y - root.iconSize / 2))
            sourceComponent: Column {
                spacing: Theme.spacingXS

                Widgets.AppFolderMemberIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: implicitWidth
                    height: implicitHeight
                    member: root.draggedMember
                    iconSize: root.iconSize
                    scale: LauncherMetrics.dragLiftScale
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.memberDragOutside
                    width: removeLabel.implicitWidth + Theme.spacingM * 2
                    height: Theme.buttonHeightXS
                    radius: Theme.fullRadius(width, height)
                    color: Theme.inverseSurface

                    StyledText {
                        id: removeLabel
                        anchors.centerIn: parent
                        text: I18n.tr("Remove from folder")
                        color: Theme.inverseOnSurface
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }
        }

        Column {
            id: content
            x: Theme.spacingL - Theme.spacingS
            y: x
            width: parent.width - x * 2
            spacing: Theme.spacingS

            RowLayout {
                width: parent.width
                layoutDirection: I18n.isRtl ? Qt.RightToLeft : Qt.LeftToRight
                spacing: Theme.spacingXS

                // Mirrors the options button width so the title stays centered.
                Item {
                    Layout.preferredWidth: optionsButton.width
                    Layout.preferredHeight: 1
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.buttonHeightS

                    TextMetrics {
                        id: titleMetrics
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Theme.fontWeightMedium
                        text: (title.item as DTextField)?.text || I18n.tr("Folder")
                    }

                    Loader {
                        id: title
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: parent.height
                        width: {
                            const editor = title.item as DTextField;
                            return editor && root.renaming ? Math.min(parent.width, titleMetrics.advanceWidth + editor.leftPadding + editor.rightPadding + Theme.spacingXS) : parent.width;
                        }
                        sourceComponent: root.renaming ? titleEditor : titleButton
                        onLoaded: {
                            if (!root.renaming)
                                return;
                            const editor = item as DTextField;
                            editor.forceActiveFocus();
                            editor.selectAll();
                        }
                    }
                }

                Component {
                    id: titleButton
                    StyledButton {
                        id: button
                        Accessible.name: root.folder?.name || I18n.tr("Folder")
                        Accessible.description: I18n.tr("Rename")
                        color: hovered || activeFocus ? Theme.widgetBaseHoverColor : "transparent"
                        onClicked: root.renaming = true

                        StyledText {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingS
                            text: button.Accessible.name
                            color: Theme.onSurface
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Theme.fontWeightMedium
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }

                Component {
                    id: titleEditor
                    DTextField {
                        text: root.folder?.name ?? ""
                        controlHeight: Theme.buttonHeightS
                        cornerRadius: Theme.fullRadius(width, height)
                        backgroundColor: "transparent"
                        normalBorderColor: "transparent"
                        textColor: Theme.onSurface
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Theme.fontWeightMedium
                        Accessible.name: I18n.tr("Rename")
                        onEditingFinished: root.finishRename(text)
                        onAccepted: root.finishRename(text)
                        Keys.onEscapePressed: event => {
                            root.renaming = false;
                            event.accepted = true;
                        }
                    }
                }

                DActionButton {
                    id: optionsButton
                    iconName: "more_vert"
                    Accessible.name: I18n.tr("Options")
                    onClicked: root.openActions(optionsButton, width / 2, height)
                }
            }

            DFlickable {
                id: list
                width: parent.width
                height: Math.min(contentHeight, root.tileHeight * 3, root.height / 2)
                contentWidth: width
                contentHeight: grid.height
                clip: contentHeight > height
                interactive: !root.memberDragActive && contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                readonly property int dragScrollDirection: {
                    if (!root.memberDragActive)
                        return 0;
                    const point = mapFromItem(null, root.dragPoint.x, root.dragPoint.y);
                    if (!contains(point))
                        return 0;
                    if (point.y < Theme.spacingL && contentY > 0)
                        return -1;
                    if (point.y > height - Theme.spacingL && contentY < contentHeight - height)
                        return 1;
                    return 0;
                }
                onDragScrollDirectionChanged: {
                    dragScroll.stop();
                    if (dragScrollDirection === 0)
                        return;
                    dragScroll.from = contentY;
                    dragScroll.to = dragScrollDirection < 0 ? 0 : contentHeight - height;
                    dragScroll.duration = Math.round(Math.abs(dragScroll.to - dragScroll.from) / root.tileHeight * Theme.expressiveDurations.expressiveDefaultSpatial);
                    dragScroll.start();
                }
                NumberAnimation {
                    id: dragScroll
                    target: list
                    property: "contentY"
                }

                Item {
                    id: grid
                    readonly property real inset: (width - root.columns * root.tileWidth) / 2
                    width: list.width
                    height: Math.ceil(root.members.length / root.columns) * root.tileHeight

                    Repeater {
                        id: tiles
                        model: ScriptModel {
                            values: root.members
                            objectProp: "id"
                        }

                        FolderTile {
                            width: root.tileWidth
                            readonly property int column: index % root.columns
                            x: grid.inset + (I18n.isRtl ? root.columns - 1 - column : column) * width
                            y: Math.floor(index / root.columns) * height
                        }
                    }
                }
            }
        }

        Widgets.DContextMenu {
            id: actions
            inlineHost: root.contentItem
            keyboardNavigable: true
            onRenderActiveChanged: {
                if (renderActive || !root.visible || PopoutManager.screenshotActive)
                    return;
                if (root.renaming)
                    (title.item as DTextField)?.forceActiveFocus();
                else
                    panel.forceActiveFocus();
            }
        }
    }

    component FolderTile: Item {
        id: tile

        required property var modelData
        required property int index
        height: root.tileHeight
        readonly property bool dragSource: root.draggedMember?.id === modelData.id
        readonly property var toplevels: root.memberWindows(modelData)
        readonly property bool focusedApp: toplevels.some(toplevel => root.anchorItem?.isToplevelFocused(toplevel) ?? false)

        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: modelData.name
        Accessible.onPressAction: root.launch(modelData)
        Keys.onReturnPressed: root.launch(modelData)
        Keys.onEnterPressed: root.launch(modelData)
        Keys.onSpacePressed: root.launch(modelData)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                root.openActions(tile, width / 2, height, modelData.id, true);
                event.accepted = true;
                return;
            }
            let step;
            switch (event.key) {
            case Qt.Key_Left:
                step = I18n.isRtl ? 1 : -1;
                break;
            case Qt.Key_Right:
                step = I18n.isRtl ? -1 : 1;
                break;
            case Qt.Key_Up:
                step = -root.columns;
                break;
            case Qt.Key_Down:
                step = root.columns;
                break;
            default:
                return;
            }
            tiles.itemAt(index + step)?.forceActiveFocus();
            event.accepted = true;
        }
        onActiveFocusChanged: {
            if (activeFocus)
                list.revealRange(y, y + height);
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: LauncherMetrics.tileGap / 2
            radius: Theme.cornerRadiusL
            color: {
                if (root.hoveredMemberId === tile.modelData.id && !tile.dragSource)
                    return Theme.withAlpha(Theme.primary, Theme.stateLayerDrag);
                if (root.memberDragActive)
                    return "transparent";
                if (pointer.pressed)
                    return Theme.withAlpha(Theme.onSurface, Theme.stateLayerPressed);
                return pointer.containsMouse || tile.activeFocus ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerHover) : "transparent";
            }
        }

        // Baseline-centered like LauncherTile; keep the two in sync.
        Item {
            id: tileContent
            anchors.centerIn: parent
            width: parent.width - Theme.spacingS * 2
            height: root.iconSize + Theme.spacingS + LauncherMetrics.tileLabelBaseline
            opacity: tile.dragSource ? LauncherMetrics.dragSourceOpacity : 1

            Widgets.AppFolderMemberIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconSize
                height: root.iconSize
                member: tile.modelData
                iconSize: root.iconSize
                fallbackBackgroundColor: Theme.primaryContainer
                fallbackTextColor: Theme.onPrimaryContainer
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.iconSize + (Theme.spacingS - height) / 2
                width: tile.focusedApp ? height * 3 : height
                height: Theme.spacingXS
                radius: height / 2
                visible: tile.toplevels.length > 0
                color: tile.focusedApp ? Theme.primary : Theme.surfaceTextSecondary
            }

            StyledText {
                y: root.iconSize + Theme.spacingS
                width: parent.width
                height: LauncherMetrics.tileLabelBlockHeight
                verticalAlignment: Text.AlignTop
                text: tile.modelData.name
                horizontalAlignment: Text.AlignHCenter
                color: Theme.onSurface
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }
        }

        MouseArea {
            id: pointer
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            enabled: !root.screenshotActive
            cursorShape: tile.dragSource ? Qt.DragMoveCursor : Qt.PointingHandCursor
            pressAndHoldInterval: Timing.longPress
            preventStealing: mouseDrag || tile.dragSource
            property bool mouseDrag: false
            property bool lifted: false
            property point pressPoint

            function lift(point) {
                if (lifted)
                    return;
                lifted = true;
                root.dragPoint = point;
                root.draggedMember = tile.modelData;
            }

            onPressed: mouse => {
                if (mouse.button !== Qt.LeftButton)
                    return;
                lifted = false;
                pressPoint = Qt.point(mouse.x, mouse.y);
                mouseDrag = mouse.source === Qt.MouseEventNotSynthesized;
            }
            onPressAndHold: mouse => {
                if (mouse.button === Qt.LeftButton)
                    lift(mapToItem(null, mouse.x, mouse.y));
            }
            onPositionChanged: mouse => {
                if (!(pressedButtons & Qt.LeftButton))
                    return;
                const point = mapToItem(null, mouse.x, mouse.y);
                if (mouseDrag && Math.hypot(mouse.x - pressPoint.x, mouse.y - pressPoint.y) >= drag.threshold)
                    lift(point);
                if (tile.dragSource)
                    root.dragPoint = point;
            }
            onReleased: mouse => {
                if (mouse.button !== Qt.LeftButton)
                    return;
                mouseDrag = false;
                if (tile.dragSource)
                    root.finishMemberDrag(mapToItem(null, mouse.x, mouse.y));
            }
            onClicked: mouse => {
                if (root.memberDragActive)
                    return;
                if (mouse.button === Qt.RightButton)
                    root.openActions(pointer, mouse.x, mouse.y, tile.modelData.id);
                else if (!lifted)
                    root.launch(tile.modelData);
            }
            onCanceled: {
                mouseDrag = false;
                if (tile.dragSource)
                    root.draggedMember = null;
            }
        }
    }
}
