import QtQuick
import "." as Center
import Quickshell
import qs.Modules.Notifications
import qs.Common
import qs.Services
import qs.DCommon.Widgets

DListView {
    id: listView

    property var keyboardController: null
    property bool keyboardActive: false
    property bool focusAllowed: true
    property bool autoScrollDisabled: false
    property bool isAnimatingExpansion: false
    property alias listContentHeight: listView.contentHeight
    property real stableContentHeight: 0
    property bool cardAnimateExpansion: true
    property bool trackStableContentHeight: true
    property real swipeBleed: 0
    property var transientSurfaceTracker: null
    property bool nested: false

    Timer {
        interval: 0
        running: true
        onTriggered: listView.syncStableContentHeight(false)
    }

    Timer {
        id: stableHeightTimer
        property bool useTarget: false
        interval: 0
        onTriggered: listView.syncStableContentHeight(useTarget || listView.isAnimatingExpansion)
    }

    Timer {
        id: ensureVisibleTimer
        interval: 0
        onTriggered: {
            if (listView.keyboardController?.keyboardNavigationActive && !listView.autoScrollDisabled)
                listView.keyboardController.ensureVisible();
        }
    }

    Timer {
        id: expansionStateTimer
        interval: 0
        onTriggered: {
            for (let i = 0; i < listView.count; i++) {
                if (!listView.itemAtIndex(i)?.isCardAnimating)
                    continue;
                listView.isAnimatingExpansion = true;
                return;
            }
            listView.isAnimatingExpansion = false;
        }
    }

    function targetContentHeight() {
        if (count <= 0)
            return contentHeight;

        let total = topMargin + bottomMargin + Math.max(0, count - 1) * spacing;
        for (let i = 0; i < count; i++) {
            const item = itemAtIndex(i);
            if (!item || item.nonAnimHeight === undefined)
                return contentHeight;
            total += item.nonAnimHeight;
        }
        return Math.max(0, total);
    }

    function forceContentLayout() {
        forceLayout();
        for (let i = 0; i < count; i++)
            itemAtIndex(i)?.forceLayout();
        forceLayout();
        syncStableContentHeight(true);
    }

    function syncStableContentHeight(useTarget) {
        if (!trackStableContentHeight)
            return;
        const nextHeight = useTarget ? targetContentHeight() : contentHeight;
        if (Math.abs(nextHeight - stableContentHeight) <= 0.5)
            return;
        stableContentHeight = nextHeight;
    }

    function queueStableContentHeightUpdate(useTarget) {
        if (!trackStableContentHeight || stableHeightTimer.running)
            return;
        stableHeightTimer.useTarget = useTarget;
        stableHeightTimer.start();
    }

    onContentHeightChanged: {
        if (trackStableContentHeight && !isAnimatingExpansion)
            queueStableContentHeightUpdate(false);
    }

    onIsAnimatingExpansionChanged: {
        if (!trackStableContentHeight)
            return;
        if (isAnimatingExpansion) {
            syncStableContentHeight(true);
        } else {
            queueStableContentHeightUpdate(false);
        }
    }

    clip: true
    leftMargin: swipeBleed
    rightMargin: swipeBleed
    model: ScriptModel {
        values: NotificationService.groupedNotifications.map(group => group.key)
    }
    spacing: Theme.groupedListGap
    rowFadeEnabled: NotificationMetrics.animationsEnabled
    fadeInitialRows: false

    onIsUserScrollingChanged: {
        if (isUserScrolling && keyboardController && keyboardController.keyboardNavigationActive) {
            autoScrollDisabled = true;
        }
    }

    function enableAutoScroll() {
        autoScrollDisabled = false;
    }

    Timer {
        id: expansionEnsureVisibleTimer
        interval: NotificationMetrics.expandDuration
        repeat: false
        onTriggered: {
            if (keyboardController && keyboardController.keyboardNavigationActive && !autoScrollDisabled) {
                keyboardController.ensureVisible();
            }
        }
    }

    NotificationEmptyState {
        parent: listView
        visible: listView.count === 0
    }

    NotificationSwipeGroup {
        id: swipeGroup
    }

    onModelChanged: {
        if (!keyboardController || !keyboardController.keyboardNavigationActive)
            return;
        keyboardController.rebuildFlatNavigation();
        ensureVisibleTimer.restart();
    }

    delegate: NotificationSwipeRow {
        id: delegateRoot
        required property string modelData

        readonly property var notificationGroup: NotificationService.groupedNotifications.find(group => group.key === modelData)
        readonly property bool isExpanded: NotificationService.expandedGroups[modelData] || false
        readonly property real nonAnimHeight: notificationCard.targetHeight

        readonly property bool isCardAnimating: notificationCard.isAnimating

        function forceLayout() {
            notificationCard.forceLayout();
        }

        Timer {
            interval: 0
            running: true
            onTriggered: {
                listView.queueStableContentHeightUpdate(listView.isAnimatingExpansion);
            }
        }

        group: swipeGroup
        bleed: listView.swipeBleed
        width: ListView.view.width - listView.swipeBleed * 2
        height: notificationCard.height
        onDismissed: NotificationService.dismissGroup(modelData)

        Component.onCompleted: listView.fadeIn(delegateRoot, index)

        Center.NotificationCard {
            id: notificationCard
            width: parent.width
            x: delegateRoot.offset
            topRoundness: delegateRoot.topRoundness
            bottomRoundness: delegateRoot.bottomRoundness
            contentOpacity: delegateRoot.contentOpacity
            swipeBleed: listView.swipeBleed
            notificationGroup: delegateRoot.notificationGroup
            nested: listView.nested
            firstInList: index === 0
            lastInList: index === listView.count - 1
            keyboardNavigationActive: listView.keyboardActive && listView.focusAllowed
            animateExpansion: listView.cardAnimateExpansion
            transientSurfaceTracker: listView.transientSurfaceTracker
            onIsAnimatingChanged: {
                if (!listView.trackStableContentHeight)
                    return;
                if (!isAnimating) {
                    expansionStateTimer.restart();
                    return;
                }
                listView.isAnimatingExpansion = true;
                listView.syncStableContentHeight(true);
            }

            onTargetHeightChanged: {
                if (!listView.trackStableContentHeight)
                    return;
                if (isAnimating || listView.isAnimatingExpansion)
                    listView.syncStableContentHeight(true);
                else
                    listView.queueStableContentHeightUpdate(false);
            }

            isGroupSelected: {
                if (!keyboardController || !keyboardController.keyboardNavigationActive || !listView.keyboardActive || !listView.focusAllowed)
                    return false;
                keyboardController.selectionVersion;
                const selection = keyboardController.getCurrentSelection();
                return selection.type === "group" && selection.groupIndex === index;
            }

            selectedNotificationIndex: {
                if (!keyboardController || !keyboardController.keyboardNavigationActive || !listView.keyboardActive || !listView.focusAllowed)
                    return -1;
                keyboardController.selectionVersion;
                const selection = keyboardController.getCurrentSelection();
                return (selection.type === "notification" && selection.groupIndex === index) ? selection.notificationIndex : -1;
            }
        }
    }

    readonly property var serviceGroupedNotifications: NotificationService.groupedNotifications
    readonly property var serviceExpandedGroups: NotificationService.expandedGroups
    readonly property var serviceExpandedMessages: NotificationService.expandedMessages

    onServiceGroupedNotificationsChanged: {
        if (!keyboardController) {
            return;
        }

        if (keyboardController.isTogglingGroup) {
            keyboardController.rebuildFlatNavigation();
            return;
        }

        keyboardController.rebuildFlatNavigation();

        if (keyboardController.keyboardNavigationActive) {
            ensureVisibleTimer.restart();
        }
    }

    onServiceExpandedGroupsChanged: {
        keyboardController?.rebuildFlatNavigation();
        if (!keyboardController || !keyboardController.keyboardNavigationActive)
            return;
        expansionEnsureVisibleTimer.restart();
    }

    onServiceExpandedMessagesChanged: {
        if (!keyboardController || !keyboardController.keyboardNavigationActive)
            return;
        expansionEnsureVisibleTimer.restart();
    }
}
