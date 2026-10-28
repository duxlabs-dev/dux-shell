pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Modules.DBar
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    property var trayItem: null
    property var menuHandle: trayItem?.menu ?? null
    property var anchorWindow: null
    property var bar: null

    signal closeRequested()
    signal actionTriggered()

    implicitWidth: Math.max(Theme.fieldDefaultWidth, menuColumn.implicitWidth)
    implicitHeight: menuColumn.implicitHeight
    width: implicitWidth
    height: implicitHeight

    focus: true
    property alias entryStack: entryStack

    ListModel {
        id: entryStack
    }

    function clearState() {
        entryStack.clear();
    }

    function topEntry() {
        return entryStack.count ? entryStack.get(entryStack.count - 1).handle : null;
    }

    function showSubMenu(entry) {
        if (!entry || !entry.hasChildren)
            return;
        entryStack.append({
            handle: entry
        });
        const h = entry.menu || entry;
        if (h && typeof h.updateLayout === "function")
            h.updateLayout();
        if (root.anchorWindow) {
            submenuHydrator.menu = h;
            submenuHydrator.open();
            Qt.callLater(() => submenuHydrator.close());
        }
    }

    function goBack() {
        if (!entryStack.count)
            return;
        entryStack.remove(entryStack.count - 1);
    }

    QsMenuAnchor {
        id: submenuHydrator
        anchor.window: root.anchorWindow
    }

    QsMenuOpener {
        id: rootOpener
        menu: root.menuHandle
    }

    QsMenuOpener {
        id: subOpener
        menu: {
            const e = root.topEntry();
            return e ? (e.menu || e) : null;
        }
    }

    Keys.onEscapePressed: {
        if (entryStack.count > 0)
            root.goBack();
        else
            root.closeRequested();
    }

    Column {
        id: menuColumn
        width: root.width > 0 ? root.width : Theme.fieldDefaultWidth
        spacing: 0

        Rectangle {
            visible: entryStack.count === 0
            width: parent.width
            height: BarMetrics.menuRowHeight
            radius: Theme.cornerRadiusS
            color: Theme.withAlpha(Theme.onSurface, visibilityToggleArea.pressed ? Theme.stateLayerPressed : visibilityToggleArea.containsMouse ? Theme.stateLayerHover : 0)

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const itemTitle = root.trayItem?.tooltipTitle || root.trayItem?.id || I18n.tr("Unknown");
                    if (root.bar && root.bar.isAutoOverflowTrayItem(root.trayItem))
                        return itemTitle + " · " + I18n.tr("Keep in Bar");
                    return itemTitle;
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceTextMedium
                elide: Text.ElideMiddle
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                width: parent.width - Theme.spacingS * 2 - (Theme.iconSizeSmall + Theme.spacingS)
            }

            DIcon {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                name: {
                    if (root.bar && root.bar.isAutoOverflowTrayItem(root.trayItem))
                        return "push_pin";
                    const itemKey = TrayMenuManager.getTrayItemKey(root.trayItem);
                    const isHidden = root.bar ? root.bar.isManualHiddenTrayItem(root.trayItem) : SessionData.isHiddenTrayId(itemKey);
                    return isHidden ? "visibility" : "visibility_off";
                }
                size: Theme.iconSizeSmall
                color: Theme.widgetTextColor
            }

            MouseArea {
                id: visibilityToggleArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const itemKey = TrayMenuManager.getTrayItemKey(root.trayItem);
                    if (!itemKey)
                        return;
                    if (root.bar && root.bar.isAutoOverflowTrayItem(root.trayItem)) {
                        root.bar.promoteTrayItemToBar(root.trayItem);
                    } else {
                        const isHidden = root.bar ? root.bar.isManualHiddenTrayItem(root.trayItem) : SessionData.isHiddenTrayId(itemKey);
                        if (isHidden)
                            SessionData.showTrayId(itemKey);
                        else
                            SessionData.hideTrayId(itemKey);
                    }
                    root.closeRequested();
                }
            }
        }

        Rectangle {
            visible: entryStack.count === 0
            width: parent.width
            height: Theme.dividerWidth
            color: Theme.outlineHeavy
        }

        Rectangle {
            visible: entryStack.count > 0
            width: parent.width
            height: BarMetrics.menuRowHeight
            radius: Theme.cornerRadiusS
            color: Theme.withAlpha(Theme.onSurface, backArea.pressed ? Theme.stateLayerPressed : backArea.containsMouse ? Theme.stateLayerHover : 0)

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                DIcon {
                    name: "arrow_back"
                    size: Theme.iconSizeSmall
                    color: Theme.widgetTextColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: I18n.tr("Back")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.widgetTextColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goBack()
            }
        }

        Rectangle {
            visible: entryStack.count > 0
            width: parent.width
            height: Theme.dividerWidth
            color: Theme.outlineHeavy
        }

        Repeater {
            model: entryStack.count ? (subOpener.children ? subOpener.children : (topEntry()?.children || [])) : rootOpener.children

            Rectangle {
                id: menuEntryDelegate
                required property var modelData
                readonly property var menuEntry: modelData

                width: menuColumn.width
                height: menuEntry?.isSeparator ? Theme.dividerWidth : BarMetrics.menuRowHeight
                radius: menuEntry?.isSeparator ? 0 : Theme.cornerRadiusS
                color: {
                    if (menuEntry?.isSeparator)
                        return Theme.outlineHeavy;
                    return Theme.withAlpha(Theme.onSurface, entryItemArea.pressed ? Theme.stateLayerPressed : entryItemArea.containsMouse ? Theme.stateLayerHover : 0);
                }

                MouseArea {
                    id: entryItemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !menuEntry?.isSeparator && (menuEntry?.enabled !== false)
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        if (!menuEntry || menuEntry.isSeparator)
                            return;
                        if (menuEntry.hasChildren) {
                            root.showSubMenu(menuEntry);
                            return;
                        }
                        if (typeof menuEntry.activate === "function") {
                            menuEntry.activate();
                        } else if (typeof menuEntry.triggered === "function") {
                            menuEntry.triggered();
                        }
                        root.actionTriggered();
                    }
                }

                RowLayout {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    visible: !menuEntry?.isSeparator

                    Rectangle {
                        Layout.preferredWidth: Theme.iconSizeSmall
                        Layout.preferredHeight: Theme.iconSizeSmall
                        Layout.alignment: Qt.AlignVCenter
                        visible: menuEntry?.buttonType !== undefined && menuEntry.buttonType !== 0
                        radius: menuEntry?.buttonType === 2 ? Theme.cornerRadiusFull : Theme.cornerRadiusXXS
                        border.width: Theme.outlineWidth
                        border.color: Theme.outline
                        color: "transparent"

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - Theme.spacingXS - Theme.spacingXXS
                            height: parent.height - Theme.spacingXS - Theme.spacingXXS
                            radius: menuEntry?.buttonType === 2 ? Theme.cornerRadiusFull : Theme.cornerRadiusXXS
                            color: Theme.primary
                            visible: menuEntry?.checkState === 2
                        }

                        DIcon {
                            anchors.centerIn: parent
                            name: "check"
                            size: Theme.iconSizeSmall - Theme.spacingXS - Theme.spacingXXS
                            color: Theme.primaryText
                            visible: menuEntry?.buttonType === 1 && menuEntry?.checkState === 2
                        }
                    }

                    Item {
                        Layout.preferredWidth: Theme.iconSizeSmall
                        Layout.preferredHeight: Theme.iconSizeSmall
                        Layout.alignment: Qt.AlignVCenter
                        visible: (menuEntry?.icon ?? "") !== ""

                        Image {
                            anchors.fill: parent
                            source: menuEntry?.icon || ""
                            sourceSize.width: Theme.iconSizeSmall
                            sourceSize.height: Theme.iconSizeSmall
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                    }

                    StyledText {
                        text: menuEntry?.text || ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: (menuEntry?.enabled !== false) ? Theme.surfaceText : Theme.surfaceTextMedium
                        elide: Text.ElideRight
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        wrapMode: Text.NoWrap
                    }

                    Item {
                        Layout.preferredWidth: Theme.iconSizeSmall
                        Layout.preferredHeight: Theme.iconSizeSmall
                        Layout.alignment: Qt.AlignVCenter
                        visible: menuEntry?.hasChildren ?? false

                        DIcon {
                            anchors.centerIn: parent
                            name: "chevron_right"
                            size: Theme.iconSizeSmall - 2
                            color: Theme.widgetTextColor
                        }
                    }
                }
            }
        }
    }
}
