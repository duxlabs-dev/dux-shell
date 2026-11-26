import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Notifications
import qs.Modules.Notifications as Notifications

Item {
    id: root

    property var notificationGroup
    property bool expanded: NotificationService.expandedGroups[notificationGroup?.key] || false
    property bool animateExpansion: true
    property bool isGroupSelected: false
    property int selectedNotificationIndex: -1
    property bool keyboardNavigationActive: false
    property var transientSurfaceTracker: null
    property bool firstInList: true
    property bool lastInList: true
    property bool nested: false
    property real topRoundness: 0
    property real bottomRoundness: 0
    property real contentOpacity: 1
    property real swipeBleed: 0
    readonly property color cardSurfaceColor: Theme.foregroundColor(nested ? Theme.chipSurface : Theme.cardSurface, Theme.isFloatingWindow(root))
    readonly property color cardChipColor: nested ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerFocus) : Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))
    readonly property Item expandedContent: expandedLoader.item
    readonly property real expandedTargetHeight: {
        if (!expandedContent)
            return collapsedCard.targetHeight;
        let total = expandedContent.headerHeight;
        for (const child of expandedContent.children) {
            if (child.targetHeight === undefined)
                continue;
            total += Theme.groupedListGap + child.targetHeight;
        }
        return total;
    }
    readonly property real targetHeight: expanded ? expandedTargetHeight : collapsedCard.targetHeight
    readonly property bool isAnimating: heightAnimation.running
    readonly property int groupCount: notificationGroup?.count ?? 0
    property bool _laidOut: false
    property bool ready: false
    property bool resizing: false

    width: parent ? parent.width : NotificationMetrics.popupWidth
    height: targetHeight
    clip: isAnimating

    function forceLayout() {
        collapsedCard.forceLayout();
        expandedContent?.layoutRows();
    }

    function toggleGroup() {
        NotificationService.toggleGroupExpansion(notificationGroup?.key || "");
    }

    function invokeAction(action) {
        if (!action?.invoke)
            return;
        action.invoke();
        PopoutService.closeNotificationCenter();
    }

    // positioners size on polish, so lay out once the width is known or the card is measured at its minimum height
    function settleLayout() {
        if (_laidOut || width <= 0)
            return;
        forceLayout();
        _laidOut = true;
    }

    // height follows layout while a card is built and presented; only a change the user or the model made animates
    function animateResize() {
        if (ready)
            resizing = true;
    }

    onExpandedChanged: animateResize()
    onGroupCountChanged: animateResize()
    onWidthChanged: Qt.callLater(settleLayout)
    Component.onCompleted: {
        settleLayout();
        ready = true;
    }

    NotificationSwipeGroup {
        id: rowSwipe
    }

    Behavior on height {
        enabled: root.resizing && root.animateExpansion && NotificationMetrics.animationsEnabled
        NumberAnimation {
            id: heightAnimation
            duration: NotificationMetrics.expandDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: NotificationMetrics.expandCurve
            onRunningChanged: {
                if (!running)
                    root.resizing = false;
            }
        }
    }

    Notifications.NotificationCard {
        id: collapsedCard
        width: parent.width
        surfaceColor: root.cardSurfaceColor
        chipColor: root.cardChipColor
        visible: !root.expanded
        notificationData: root.notificationGroup?.latestNotification ?? null
        groupCount: root.notificationGroup?.count || 0
        descriptionExpanded: NotificationService.expandedMessages[(notificationData?.notification?.id || "") + "_desc"] || false
        firstInGroup: root.firstInList
        lastInGroup: root.lastInList
        topRoundness: root.topRoundness
        bottomRoundness: root.bottomRoundness
        contentOpacity: root.contentOpacity
        keyboardSelected: root.keyboardNavigationActive && root.isGroupSelected
        keyboardHints: keyboardSelected
        animateHeight: false
        showDismiss: false
        showClose: true
        transientSurfaceTracker: root.transientSurfaceTracker
        closeTooltip: I18n.tr("Close (keep in history)")
        onDescriptionExpandedChanged: root.animateResize()
        onExpandRequested: NotificationService.toggleMessageExpansion((notificationData?.notification?.id || "") + "_desc")
        onGroupToggleRequested: root.toggleGroup()
        onCloseRequested: NotificationService.dismissGroup(root.notificationGroup?.key || "")
        onActionRequested: action => root.invokeAction(action)
        onBodyClicked: {
            if (groupCount > 1) {
                root.toggleGroup();
                return;
            }
            root.invokeAction(contextActions.defaultAction(notificationData));
        }
    }

    Loader {
        id: expandedLoader
        width: parent.width
        active: root.expanded

        sourceComponent: Column {
            id: expandedColumn

            readonly property real headerHeight: groupHeader.height

            function layoutRows() {
                for (let i = 0; i < notificationRepeater.count; i++)
                    notificationRepeater.itemAt(i)?.forceLayout();
                forceLayout();
            }

            objectName: "expandedContent"
            opacity: root.contentOpacity
            spacing: Theme.groupedListGap

            Rectangle {
                id: groupHeader
                width: parent.width
                height: NotificationMetrics.cardPadding * 2 + NotificationMetrics.controlSize
                radius: Theme.groupedListOuterRadius
                color: "transparent"
                border.width: root.keyboardNavigationActive && root.isGroupSelected ? Theme.focusRingWidth : 0
                border.color: Theme.focusRingColor
                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: NotificationMetrics.cardPadding
                    anchors.right: groupControls.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.notificationGroup?.appName || ""
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: Theme.primary
                    elide: Text.ElideRight
                }
                Row {
                    id: groupControls
                    anchors.right: parent.right
                    anchors.rightMargin: NotificationMetrics.cardPadding
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    DButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.notificationGroup?.count || 0).toString()
                        iconName: "expand_less"
                        buttonHeight: NotificationMetrics.controlSize
                        horizontalPadding: Theme.spacingS
                        backgroundColor: root.cardChipColor
                        textColor: Theme.onSurfaceVariant
                        Accessible.name: I18n.tr("Collapse")
                        onClicked: root.toggleGroup()
                    }
                    DActionButton {
                        id: groupMenuButton
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "more_horiz"
                        buttonSize: NotificationMetrics.controlSize
                        iconSize: Theme.iconSizeSmall
                        tooltipText: I18n.tr("More")
                        // The hidden collapsed card carries the group's latest notification and closes the whole group.
                        onClicked: collapsedCard.openMenu(groupMenuButton)
                    }
                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "close"
                        buttonSize: NotificationMetrics.controlSize
                        iconSize: Theme.iconSizeSmall
                        tooltipText: I18n.tr("Close all", "notification group header button, dismisses every notification in the group")
                        onClicked: NotificationService.dismissGroup(root.notificationGroup?.key || "")
                    }
                }
            }

            Repeater {
                id: notificationRepeater
                objectName: "notificationRepeater"
                model: ScriptModel {
                    values: root.expanded ? (root.notificationGroup?.notifications?.slice(0, NotificationMetrics.expandedLimit) || []) : []
                }

                NotificationSwipeRow {
                    id: row
                    required property var modelData
                    property bool collapsing: false
                    property var notificationToDismiss: null
                    readonly property real targetHeight: collapsing ? 0 : message.targetHeight

                    function forceLayout() {
                        message.forceLayout();
                    }

                    group: rowSwipe
                    bleed: root.swipeBleed
                    width: expandedColumn.width
                    height: message.height
                    clip: collapsing
                    onDismissed: {
                        root.animateResize();
                        notificationToDismiss = modelData;
                        collapseAnimation.start();
                    }

                    Notifications.NotificationCard {
                        id: message
                        animateHeight: root.resizing
                        surfaceColor: root.cardSurfaceColor
                        chipColor: root.cardChipColor
                        x: row.offset
                        width: parent.width
                        notificationData: row.modelData
                        firstInGroup: row.index === 0
                        lastInGroup: row.index === notificationRepeater.count - 1
                        topRoundness: row.topRoundness
                        bottomRoundness: row.bottomRoundness
                        contentOpacity: row.contentOpacity
                        keyboardSelected: root.keyboardNavigationActive && root.selectedNotificationIndex === row.index
                        keyboardHints: keyboardSelected
                        descriptionExpanded: NotificationService.expandedMessages[(notificationData?.notification?.id || "") + "_desc"] || false
                        showDismiss: false
                        showClose: true
                        transientSurfaceTracker: root.transientSurfaceTracker
                        closeTooltip: I18n.tr("Close (keep in history)")
                        onDescriptionExpandedChanged: root.animateResize()
                        onExpandRequested: NotificationService.toggleMessageExpansion((notificationData?.notification?.id || "") + "_desc")
                        onCloseRequested: NotificationService.dismissNotification(row.modelData)
                        onActionRequested: action => root.invokeAction(action)
                        onBodyClicked: root.invokeAction(contextActions.defaultAction(notificationData))
                    }

                    SequentialAnimation {
                        id: collapseAnimation

                        PropertyAction {
                            target: row
                            property: "collapsing"
                            value: true
                        }
                        NumberAnimation {
                            target: row
                            property: "height"
                            to: 0
                            duration: NotificationMetrics.animationsEnabled ? NotificationMetrics.expandDuration : 0
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: NotificationMetrics.expandCurve
                        }
                        ScriptAction {
                            script: NotificationService.dismissNotification(row.notificationToDismiss)
                        }
                    }
                }
            }
        }
    }

    NotificationActions {
        id: contextActions
    }
}
