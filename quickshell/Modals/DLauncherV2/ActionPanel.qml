pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modals.DLauncherV2.Components

Rectangle {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var selectedItem: null
    property var controller: null
    property bool expanded: false
    property int selectedActionIndex: 0
    readonly property bool animating: heightAnimation.running

    onSelectedActionIndexChanged: revealTimer.restart()
    onActionsChanged: revealTimer.restart()
    onExpandedChanged: {
        if (expanded)
            revealTimer.restart();
    }

    Timer {
        id: revealTimer
        interval: 0
        onTriggered: root.ensureSelectedVisible()
    }

    function getPluginContextMenuActions() {
        if (selectedItem?.type !== "plugin" || !selectedItem?.pluginId)
            return [];
        var instance = PluginService.pluginInstances[selectedItem.pluginId];
        if (!instance)
            return [];
        if (typeof instance.getContextMenuActions !== "function")
            return [];
        var actions = instance.getContextMenuActions(selectedItem.data);
        if (!Array.isArray(actions))
            return [];
        return actions;
    }

    readonly property var actions: {
        var result = [];
        if (selectedItem?.primaryAction) {
            result.push(selectedItem.primaryAction);
        }

        switch (selectedItem?.type) {
        case "plugin":
            var pluginActions = getPluginContextMenuActions();
            for (var i = 0; i < pluginActions.length; i++) {
                var act = pluginActions[i];
                result.push({
                    name: act.text || act.name || "",
                    icon: act.icon || "play_arrow",
                    action: "plugin_action",
                    pluginAction: act.action
                });
            }
            break;
        case "plugin_browse":
            if (selectedItem?.actions) {
                for (var i = 0; i < selectedItem.actions.length; i++) {
                    result.push(selectedItem.actions[i]);
                }
            }
            break;
        case "app":
            if (selectedItem?.isCore)
                break;
            if (SessionService.nvidiaCommand) {
                result.push({
                    name: I18n.tr("Launch on dGPU"),
                    icon: "memory",
                    action: "launch_dgpu"
                });
            }
            if (selectedItem?.actions) {
                for (var i = 0; i < selectedItem.actions.length; i++) {
                    result.push(selectedItem.actions[i]);
                }
            }
            break;
        case "file":
            if (selectedItem?.actions) {
                for (var i = 0; i < selectedItem.actions.length; i++) {
                    result.push(selectedItem.actions[i]);
                }
            }
            break;
        case "clipboard":
            if (selectedItem?.actions) {
                for (var i = 0; i < selectedItem.actions.length; i++) {
                    result.push(selectedItem.actions[i]);
                }
            }
            break;
        }
        return result;
    }

    readonly property bool hasActions: {
        switch (selectedItem?.type) {
        case "app":
            return !selectedItem?.isCore;
        case "plugin":
            return getPluginContextMenuActions().length > 0;
        case "plugin_browse":
            return selectedItem?.actions?.length > 0;
        case "file":
            return selectedItem?.actions?.length > 0;
        default:
            return actions.length > 1;
        }
    }

    width: parent?.width ?? Theme.fieldDefaultWidth
    height: expanded && hasActions ? LauncherMetrics.rowHeight : 0
    color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineMedium
    radius: Theme.cornerRadius

    clip: true

    Behavior on height {
        NumberAnimation {
            id: heightAnimation
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: Theme.outlineWidth
        color: Theme.outlineMedium
    }

    Item {
        anchors.fill: parent
        anchors.margins: Theme.spacingS

        DFlickable {
            id: actionsFlickable
            anchors.left: parent.left
            anchors.right: tabHint.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            contentWidth: actionsRow.width
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick

            Row {
                id: actionsRow
                height: parent.height
                spacing: Theme.spacingS

                Repeater {
                    id: actionRepeater
                    model: root.actions

                    DButton {
                        id: actionButton
                        required property var modelData
                        required property int index
                        anchors.verticalCenter: actionsRow.verticalCenter
                        text: modelData?.name ?? ""
                        iconName: modelData?.icon ?? "play_arrow"
                        buttonHeight: Theme.buttonHeightXS
                        backgroundColor: index === root.selectedActionIndex ? Theme.secondaryContainer : "transparent"
                        textColor: index === root.selectedActionIndex ? Theme.onSecondaryContainer : Theme.onSurfaceVariant
                        onHoveredChanged: {
                            if (hovered)
                                root.selectedActionIndex = index;
                        }
                        onClicked: {
                            if (!root.controller || !root.selectedItem)
                                return;
                            root.controller.executeAction(root.selectedItem, modelData);
                        }
                    }
                }
            }
        }

        DKeycap {
            id: tabHint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasActions
            text: I18n.tr("Tab", "keyboard tab key name", true)
            textColor: Theme.onSurfaceVariant
        }
    }

    function toggle() {
        expanded = !expanded;
        selectedActionIndex = 0;
    }

    function show() {
        expanded = true;
        selectedActionIndex = actions.length > 1 ? 1 : 0;
    }

    function hide() {
        expanded = false;
        selectedActionIndex = 0;
    }

    function cycleAction(reverse = false) {
        if (actions.length > 0) {
            selectedActionIndex = reverse ? (selectedActionIndex - 1 + actions.length) % actions.length : (selectedActionIndex + 1) % actions.length;
        }
    }

    function ensureSelectedVisible() {
        var button = actionRepeater.itemAt(selectedActionIndex);
        if (!button)
            return;
        var buttonX = button.x;
        var buttonRight = buttonX + button.width;
        var viewLeft = actionsFlickable.contentX;
        var viewRight = viewLeft + actionsFlickable.width;

        if (buttonX < viewLeft) {
            actionsFlickable.contentX = Math.max(0, buttonX - Theme.spacingS);
            return;
        }
        if (buttonRight > viewRight)
            actionsFlickable.contentX = Math.max(0, Math.min(actionsFlickable.contentWidth - actionsFlickable.width, buttonRight - actionsFlickable.width + Theme.spacingS));
    }

    function executeSelectedAction() {
        if (!controller || !selectedItem || selectedActionIndex >= actions.length)
            return;
        var action = actions[selectedActionIndex];
        if (action.action === "plugin_action" && typeof action.pluginAction === "function") {
            action.pluginAction();
            controller.performSearch();
            controller.itemExecuted();
        } else {
            controller.executeAction(selectedItem, action);
        }
    }
}
