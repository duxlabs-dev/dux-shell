import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets

DockContextMenuBase {
    id: root

    property var appData: null
    property bool hidePin: false
    property var desktopEntry: null
    property var dockApps: null
    readonly property bool isDmsWindow: Paths.isDmsAppId(appData?.appId)
    readonly property var settingsJumpGroups: visible && appData?.appId === "dms_settings" ? buildSettingsJumpGroups() : []

    layerNamespace: "dms:dock-context-menu"

    function showForButton(button, data, dockHeight, hidePinOption, entry, dockScreen, parentDockApps) {
        appData = Qt.binding(() => button?.appData ?? null);
        hidePin = hidePinOption || false;
        desktopEntry = entry || null;
        dockApps = parentDockApps || null;
        options = dockApps?.options ?? ({});
        show(button, dockHeight, dockScreen);
    }

    function buildSettingsJumpGroups() {
        const groups = [[]];
        for (const item of SettingsTabs.structure) {
            if (item.separator) {
                if (groups[groups.length - 1].length > 0)
                    groups.push([]);
                continue;
            }
            const entry = SettingsTabs.page(item.id);
            if (SettingsTabs.isVisible(entry))
                groups[groups.length - 1].push(entry);
        }
        return groups.filter(group => group.length > 0);
    }

    Repeater {
        model: {
            if (!root.appData || root.appData.type !== "grouped")
                return [];
            return (root.appData.allWindows || []).map(w => w.toplevel).filter(t => t != null);
        }

        Rectangle {
            implicitWidth: Theme.spacingS + windowTitle.implicitWidth + Theme.spacingXS + (minimizeButton.visible ? minimizeButton.width + 2 : 0) + closeButton.width + Theme.spacingXS
            width: parent.width
            height: 28
            radius: Theme.cornerRadius
            color: windowArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : Theme.withAlpha(BlurService.hoverColor(Theme.widgetBaseHoverColor), 0)

            StyledText {
                id: windowTitle
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.right: minimizeButton.visible ? minimizeButton.left : closeButton.left
                anchors.rightMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                text: (modelData && modelData.title) ? modelData.title : I18n.tr("(Unnamed)", "dock menu fallback for a window without a title")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                font.weight: Theme.fontWeight
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Rectangle {
                id: minimizeButton
                Accessible.role: Accessible.Button
                Accessible.name: modelData.minimized ? I18n.tr("Restore", "verb, action restoring a minimized window") : I18n.tr("Minimize", "verb, action minimizing a window")
                visible: CompositorService.canMinimize(modelData)
                anchors.right: closeButton.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                radius: Theme.cornerRadiusS
                color: minimizeMouseArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : "transparent"

                DIcon {
                    anchors.centerIn: parent
                    name: modelData.minimized ? "expand_content" : "minimize"
                    size: 12
                    color: Theme.surfaceText
                }

                MouseArea {
                    id: minimizeMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.minimized) {
                            CompositorService.activateToplevel(modelData);
                        } else {
                            modelData.minimized = true;
                        }
                        root.close();
                    }
                }
            }

            Rectangle {
                id: closeButton
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("Close Window")
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                radius: Theme.cornerRadiusS
                color: closeMouseArea.containsMouse ? Theme.errorPressed : Theme.withAlpha(Theme.errorPressed, 0)

                DIcon {
                    anchors.centerIn: parent
                    name: "close"
                    size: 12
                    color: closeMouseArea.containsMouse ? Theme.error : Theme.surfaceText
                }

                MouseArea {
                    id: closeMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData && modelData.close) {
                            modelData.close();
                        }
                        root.close();
                    }
                }
            }

            DRipple {
                id: windowRipple
                rippleColor: Theme.surfaceText
                cornerRadius: Theme.cornerRadius
            }

            MouseArea {
                id: windowArea
                anchors.fill: parent
                anchors.rightMargin: minimizeButton.visible ? 46 : 24
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => windowRipple.trigger(mouse.x, mouse.y)
                onClicked: {
                    CompositorService.activateToplevel(modelData);
                    root.close();
                }
            }
        }
    }

    Rectangle {
        visible: {
            if (!root.appData)
                return false;
            if (root.appData.type !== "grouped")
                return false;
            return root.appData.windowCount > 0;
        }
        width: parent.width
        height: 1
        color: Theme.outlineHeavy
    }

    Repeater {
        model: root.desktopEntry && root.desktopEntry.actions ? root.desktopEntry.actions : []

        Rectangle {
            implicitWidth: Theme.spacingS * 2 + (actionIcon.visible ? actionIcon.width + Theme.spacingXS : 0) + actionLabel.implicitWidth
            width: parent.width
            height: 28
            radius: Theme.cornerRadius
            color: actionArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : Theme.withAlpha(BlurService.hoverColor(Theme.widgetBaseHoverColor), 0)

            Item {
                id: actionIcon
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                visible: modelData.icon && modelData.icon !== ""

                IconImage {
                    anchors.fill: parent
                    source: modelData.icon ? Paths.resolveIconPath(modelData.icon) : ""
                    smooth: true
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }

            StyledText {
                id: actionLabel
                anchors.left: actionIcon.visible ? actionIcon.right : parent.left
                anchors.leftMargin: actionIcon.visible ? Theme.spacingXS : Theme.spacingS
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name || ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                font.weight: Theme.fontWeight
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            DRipple {
                id: actionRipple
                rippleColor: Theme.surfaceText
                cornerRadius: Theme.cornerRadius
            }

            MouseArea {
                id: actionArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => actionRipple.trigger(mouse.x, mouse.y)
                onClicked: {
                    if (modelData) {
                        SessionService.launchDesktopAction(root.desktopEntry, modelData);
                    }
                    root.close();
                }
            }
        }
    }

    Repeater {
        model: root.settingsJumpGroups

        Column {
            id: jumpGroup

            required property var modelData
            required property int index

            width: parent.width
            spacing: 1

            Rectangle {
                visible: jumpGroup.index > 0
                width: parent.width
                height: 1
                color: Theme.outlineHeavy
            }

            Repeater {
                model: jumpGroup.modelData

                DockTrashMenuItem {
                    required property var modelData

                    width: parent.width
                    text: modelData.text
                    iconName: modelData.icon
                    onTriggered: {
                        PopoutService.openSettingsWithTab(modelData.id);
                        root.close();
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.settingsJumpGroups.length > 0 && !root.hidePin
        width: parent.width
        height: 1
        color: Theme.outlineHeavy
    }

    Rectangle {
        visible: {
            if (!root.desktopEntry?.actions || root.desktopEntry.actions.length === 0) {
                return false;
            }
            return !root.hidePin || (!root.isDmsWindow && root.desktopEntry && SessionService.nvidiaCommand);
        }
        width: parent.width
        height: 1
        color: Theme.outlineHeavy
    }

    Rectangle {
        visible: !root.hidePin
        implicitWidth: Theme.spacingS * 2 + pinIcon.width + Theme.spacingXS + pinLabel.implicitWidth
        width: parent.width
        height: 28
        radius: Theme.cornerRadius
        color: pinArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : Theme.withAlpha(BlurService.hoverColor(Theme.widgetBaseHoverColor), 0)

        DIcon {
            id: pinIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            name: root.appData && root.appData.isPinned ? "keep_off" : "push_pin"
            size: 14
            color: Theme.surfaceText
            opacity: 0.7
        }

        StyledText {
            id: pinLabel
            anchors.left: pinIcon.right
            anchors.leftMargin: Theme.spacingXS
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: root.appData && root.appData.isPinned ? I18n.tr("Unpin from Dock") : I18n.tr("Pin to Dock")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            font.weight: Theme.fontWeight
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        DRipple {
            id: pinRipple
            rippleColor: Theme.surfaceText
            cornerRadius: Theme.cornerRadius
        }

        MouseArea {
            id: pinArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => pinRipple.trigger(mouse.x, mouse.y)
            onClicked: {
                if (!root.appData)
                    return;

                if (root.appData.isPinned) {
                    root.dockApps.removePinnedApp(root.appData.appId);
                } else {
                    root.dockApps.addPinnedApp(root.appData.appId);
                }
                root.close();
            }
        }
    }

    Rectangle {
        visible: {
            const hasNvidia = !root.isDmsWindow && root.desktopEntry && SessionService.nvidiaCommand;
            const hasWindow = root.appData && (root.appData.type === "window" || (root.appData.type === "grouped" && root.appData.windowCount > 0));
            const hasPinOption = !root.hidePin;
            const hasContentAbove = hasPinOption || hasNvidia;
            return hasContentAbove && hasWindow;
        }
        width: parent.width
        height: 1
        color: Theme.outlineHeavy
    }

    Rectangle {
        visible: !root.isDmsWindow && root.desktopEntry && SessionService.nvidiaCommand
        implicitWidth: Theme.spacingS * 2 + nvidiaIcon.width + Theme.spacingXS + nvidiaLabel.implicitWidth
        width: parent.width
        height: 28
        radius: Theme.cornerRadius
        color: nvidiaArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : Theme.withAlpha(BlurService.hoverColor(Theme.widgetBaseHoverColor), 0)

        DIcon {
            id: nvidiaIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            name: "memory"
            size: 14
            color: Theme.surfaceText
            opacity: 0.7
        }

        StyledText {
            id: nvidiaLabel
            anchors.left: nvidiaIcon.right
            anchors.leftMargin: Theme.spacingXS
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Launch on dGPU")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            font.weight: Theme.fontWeight
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        DRipple {
            id: nvidiaRipple
            rippleColor: Theme.surfaceText
            cornerRadius: Theme.cornerRadius
        }

        MouseArea {
            id: nvidiaArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => nvidiaRipple.trigger(mouse.x, mouse.y)
            onClicked: {
                if (root.desktopEntry) {
                    SessionService.launchDesktopEntry(root.desktopEntry, true);
                }
                root.close();
            }
        }
    }

    Rectangle {
        visible: root.appData && (root.appData.type === "window" || (root.appData.type === "grouped" && root.appData.windowCount > 0))
        implicitWidth: Theme.spacingS * 2 + closeIcon.width + Theme.spacingXS + closeLabel.implicitWidth
        width: parent.width
        height: 28
        radius: Theme.cornerRadius
        color: closeArea.containsMouse ? Theme.errorHover : Theme.withAlpha(Theme.errorHover, 0)

        DIcon {
            id: closeIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            name: "close"
            size: 14
            color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
            opacity: 0.7
        }

        StyledText {
            id: closeLabel
            anchors.left: closeIcon.right
            anchors.leftMargin: Theme.spacingXS
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: root.appData && root.appData.type === "grouped" ? I18n.tr("Close All Windows") : I18n.tr("Close Window")
            font.pixelSize: Theme.fontSizeSmall
            color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
            font.weight: Theme.fontWeight
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        DRipple {
            id: closeRipple
            rippleColor: Theme.error
            cornerRadius: Theme.cornerRadius
        }

        MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => closeRipple.trigger(mouse.x, mouse.y)
            onClicked: {
                if (root.appData?.type === "window") {
                    root.appData?.toplevel?.close();
                } else if (root.appData?.type === "grouped") {
                    root.appData?.allWindows?.forEach(window => window.toplevel?.close());
                }
                root.close();
            }
        }
    }
    DockTrashMenuItem {
        visible: root.dockApps?.surfaceContext?.kind === "dock"
        width: parent.width
        text: I18n.tr("Edit widgets")
        iconName: "edit"
        onTriggered: {
            root.dockApps.surfaceContext.host.editMode = true;
            root.close();
        }
    }
}
