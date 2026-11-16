pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Common as DCommon
import qs.DCommon.Widgets

Popup {
    id: root

    property var targetTextArea: null
    property int selectedIndex: -1
    property bool keyboardNavigation: false
    property int openRevision: 0

    readonly property var menuItems: [
        {
            text: I18n.tr("Cut"),
            icon: "content_cut",
            isEnabled: () => !!targetTextArea && targetTextArea.selectedText.length > 0,
            action: () => targetTextArea?.cut()
        },
        {
            text: I18n.tr("Copy"),
            icon: "content_copy",
            isEnabled: () => !!targetTextArea && targetTextArea.selectedText.length > 0,
            action: () => targetTextArea?.copy()
        },
        {
            text: I18n.tr("Paste"),
            icon: "content_paste",
            isEnabled: () => !!targetTextArea && targetTextArea.canPaste,
            action: () => targetTextArea?.paste()
        },
        {
            text: I18n.tr("Delete"),
            icon: "delete",
            isEnabled: () => !!targetTextArea && targetTextArea.selectedText.length > 0,
            action: () => targetTextArea?.remove(targetTextArea.selectionStart, targetTextArea.selectionEnd)
        },
        {
            type: "separator"
        },
        {
            text: I18n.tr("Select All"),
            icon: "select_all",
            isEnabled: () => !!targetTextArea && targetTextArea.length > 0,
            action: () => targetTextArea?.selectAll()
        }
    ]

    function isItemEnabled(item) {
        return !!item && item.type !== "separator" && (item.isEnabled ? item.isEnabled() : true);
    }

    function hasSelectableItems() {
        return menuItems.some(item => isItemEnabled(item));
    }

    function show(x, y, fromKeyboard) {
        let finalX = x;
        let finalY = y;

        if (root.parent) {
            const parentWidth = root.parent.width;
            const parentHeight = root.parent.height;
            const menuWidth = root.width;
            const menuHeight = root.height;
            const gap = Theme.spacingXS;

            if (targetTextArea && targetTextArea.selectedText.length > 0) {
                const startRect = targetTextArea.positionToRectangle(targetTextArea.selectionStart);
                const endRect = targetTextArea.positionToRectangle(targetTextArea.selectionEnd);
                const startPos = targetTextArea.mapToItem(root.parent, startRect.x, startRect.y);
                const endPos = targetTextArea.mapToItem(root.parent, endRect.x, endRect.y + endRect.height);
                const selTop = Math.min(startPos.y, endPos.y - endRect.height);
                const selBottom = Math.max(startPos.y + startRect.height, endPos.y);

                if (finalY < selBottom && finalY + menuHeight > selTop) {
                    const belowY = selBottom + gap;
                    const aboveY = selTop - gap - menuHeight;
                    if (belowY + menuHeight <= parentHeight)
                        finalY = belowY;
                    else if (aboveY >= 0)
                        finalY = aboveY;
                }
            }

            if (finalX + menuWidth > parentWidth)
                finalX = Math.max(0, parentWidth - menuWidth);
            if (finalY + menuHeight > parentHeight)
                finalY = Math.max(0, parentHeight - menuHeight);
            finalX = Math.max(0, finalX);
            finalY = Math.max(0, finalY);
        }

        root.x = finalX;
        root.y = finalY;
        openRevision++;
        keyboardNavigation = !!fromKeyboard;
        selectedIndex = -1;
        if (keyboardNavigation)
            selectNext();
        open();
    }

    function selectNext() {
        if (!hasSelectableItems())
            return;
        for (let step = 1; step <= menuItems.length; step++) {
            const idx = (selectedIndex + step + menuItems.length) % menuItems.length;
            if (isItemEnabled(menuItems[idx])) {
                selectedIndex = idx;
                return;
            }
        }
    }

    function selectPrevious() {
        if (!hasSelectableItems())
            return;
        const start = selectedIndex < 0 ? 0 : selectedIndex;
        for (let step = 1; step <= menuItems.length; step++) {
            const idx = (start - step + menuItems.length) % menuItems.length;
            if (isItemEnabled(menuItems[idx])) {
                selectedIndex = idx;
                return;
            }
        }
    }

    function activateItem(item) {
        if (!isItemEnabled(item))
            return;
        item.action();
        close();
    }

    width: Math.max(Theme.fieldDefaultWidth, labelMetrics.width + DCommon.Style.menuItemIconSize + Theme.spacingM * 2 + Theme.spacingS * 2 + Theme.spacingXS * 2)
    height: menuCard.height
    padding: 0
    modal: true
    dim: false
    closePolicy: Popup.CloseOnEscape

    onOpened: {
        outsideClickTimer.start();
        if (keyboardNavigation)
            Qt.callLater(() => keyboardHandler.forceActiveFocus());
    }

    onClosed: {
        outsideClickTimer.stop();
        closePolicy = Popup.CloseOnEscape;
        keyboardNavigation = false;
        selectedIndex = -1;
        if (root.parent?.surfaceVisible !== false && targetTextArea?.visible)
            Qt.callLater(() => targetTextArea?.forceActiveFocus());
    }

    Timer {
        id: outsideClickTimer
        interval: 100
        onTriggered: root.closePolicy = Popup.CloseOnEscape | Popup.CloseOnPressOutside
    }

    StyledTextMetrics {
        id: labelMetrics
        font.pixelSize: Theme.fontSizeSmall
        text: {
            let longest = "";
            for (const item of root.menuItems) {
                if (item.text && item.text.length > longest.length)
                    longest = item.text;
            }
            return longest;
        }
    }

    background: Rectangle {
        color: "transparent"
    }

    contentItem: Item {
        Item {
            id: keyboardHandler
            anchors.fill: parent
            focus: root.keyboardNavigation

            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Down:
                    root.keyboardNavigation = true;
                    root.selectNext();
                    event.accepted = true;
                    return;
                case Qt.Key_Up:
                    root.keyboardNavigation = true;
                    root.selectPrevious();
                    event.accepted = true;
                    return;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    if (root.selectedIndex >= 0 && root.selectedIndex < root.menuItems.length)
                        root.activateItem(root.menuItems[root.selectedIndex]);
                    event.accepted = true;
                    return;
                case Qt.Key_Escape:
                    root.close();
                    event.accepted = true;
                    return;
                }
            }
        }

        Rectangle {
            id: menuCard
            anchors.left: parent.left
            anchors.right: parent.right
            height: menuColumn.implicitHeight + Theme.spacingXS * 2
            color: Theme.foregroundColor(Theme.chipSurfaceNested, Theme.isFloatingWindow(root))
            radius: Theme.windowRadius
            border.color: Theme.outlineMedium
            border.width: Theme.layerOutlineWidth

            Column {
                id: menuColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingXS
                spacing: Theme.groupedListGap

                Repeater {
                    model: root.menuItems

                    Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool isSeparator: modelData.type === "separator"
                        readonly property bool itemEnabled: root.openRevision >= 0 && root.isItemEnabled(modelData)
                        width: menuColumn.width
                        height: isSeparator ? Theme.spacingXS + Theme.dividerWidth : DCommon.Style.menuRowHeight

                        Rectangle {
                            visible: row.isSeparator
                            width: parent.width - Theme.spacingS * 2
                            height: Theme.dividerWidth
                            anchors.centerIn: parent
                            color: Theme.outlineHeavy
                        }

                        Rectangle {
                            visible: !row.isSeparator
                            width: parent.width
                            height: DCommon.Style.menuRowHeight
                            radius: Theme.cornerRadiusM
                            color: {
                                if (!row.itemEnabled)
                                    return "transparent";
                                const isSelected = root.keyboardNavigation && root.selectedIndex === row.index;
                                if (isSelected)
                                    return Theme.selectedContainer;
                                return itemArea.pressed ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerPressed) : itemArea.containsMouse ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerHover) : "transparent";
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingS
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS

                                DIcon {
                                    name: row.modelData.icon || ""
                                    size: DCommon.Style.menuItemIconSize
                                    color: row.itemEnabled ? Theme.surfaceText : Theme.onSurface_38
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: row.modelData.text || ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: row.itemEnabled ? Theme.surfaceText : Theme.onSurface_38
                                    elide: Text.ElideRight
                                    width: parent.width - DCommon.Style.menuItemIconSize - Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: itemArea
                                anchors.fill: parent
                                hoverEnabled: row.itemEnabled
                                enabled: row.itemEnabled
                                cursorShape: row.itemEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.activateItem(row.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
