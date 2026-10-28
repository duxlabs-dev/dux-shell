import QtQuick
import qs.Modules.Notifications
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    property string selectedFilterKey: "all"
    property var keyboardController: null
    property bool keyboardActive: false
    property bool focusAllowed: true
    property int selectedIndex: -1
    property bool showKeyboardHints: false
    property bool nested: false
    property real swipeBleed: 0
    property alias showScrollBar: historyListView.showScrollBar

    function getStartOfDay(date) {
        const d = new Date(date);
        d.setHours(0, 0, 0, 0);
        return d;
    }

    function getFilterRange(key) {
        const now = new Date();
        const startOfToday = getStartOfDay(now);
        const startOfYesterday = new Date(startOfToday.getTime() - 86400000);

        switch (key) {
        case "all":
            return {
                start: null,
                end: null
            };
        case "1h":
            return {
                start: new Date(now.getTime() - 3600000),
                end: null
            };
        case "today":
            return {
                start: startOfToday,
                end: null
            };
        case "yesterday":
            return {
                start: startOfYesterday,
                end: startOfToday
            };
        case "older":
            return {
                start: null,
                end: getOlderCutoff()
            };
        case "7d":
            return {
                start: new Date(now.getTime() - 7 * 86400000),
                end: null
            };
        case "30d":
            return {
                start: new Date(now.getTime() - 30 * 86400000),
                end: null
            };
        default:
            return {
                start: null,
                end: null
            };
        }
    }

    function countForFilter(key) {
        const range = getFilterRange(key);
        if (!range.start && !range.end)
            return NotificationService.historyList.length;
        return NotificationService.historyList.filter(n => {
            const ts = n.timestamp;
            if (range.start && ts < range.start.getTime())
                return false;
            if (range.end && ts >= range.end.getTime())
                return false;
            return true;
        }).length;
    }

    readonly property var allFilters: [
        {
            label: I18n.tr("All", "notification history filter"),
            key: "all",
            maxDays: 0
        },
        {
            label: I18n.tr("Last hour", "notification history filter"),
            key: "1h",
            maxDays: 1
        },
        {
            label: I18n.tr("Today", "notification history filter"),
            key: "today",
            maxDays: 1
        },
        {
            label: I18n.tr("Yesterday", "notification history filter"),
            key: "yesterday",
            maxDays: 2
        },
        {
            label: I18n.duration(7 * 86400),
            key: "7d",
            maxDays: 7
        },
        {
            label: I18n.duration(30 * 86400),
            key: "30d",
            maxDays: 30
        },
        {
            label: I18n.tr("Older", "notification history filter for content older than other filters"),
            key: "older",
            maxDays: 0
        }
    ]

    function filterRelevantForRetention(filter) {
        const retention = SettingsData.notificationHistoryMaxAgeDays;
        if (filter.key === "older") {
            if (retention === 0)
                return true;
            return retention > 2 && retention < 7 || retention > 30;
        }
        if (retention === 0)
            return true;
        if (filter.maxDays === 0)
            return true;
        return filter.maxDays <= retention;
    }

    function getOlderCutoff() {
        const retention = SettingsData.notificationHistoryMaxAgeDays;
        const now = new Date();
        if (retention === 0 || retention > 30)
            return new Date(now.getTime() - 30 * 86400000);
        if (retention >= 7)
            return new Date(now.getTime() - 7 * 86400000);
        const startOfToday = getStartOfDay(now);
        return new Date(startOfToday.getTime() - 86400000);
    }

    readonly property var visibleFilters: {
        const result = [];
        const retention = SettingsData.notificationHistoryMaxAgeDays;
        for (let i = 0; i < allFilters.length; i++) {
            const f = allFilters[i];
            if (!filterRelevantForRetention(f))
                continue;
            const count = countForFilter(f.key);
            if (f.key === "all" || count > 0) {
                result.push({
                    label: f.label,
                    key: f.key,
                    count: count
                });
            }
        }
        return result;
    }

    onVisibleFiltersChanged: {
        let found = false;
        for (let i = 0; i < visibleFilters.length; i++) {
            if (visibleFilters[i].key === selectedFilterKey) {
                found = true;
                break;
            }
        }
        if (!found)
            selectedFilterKey = "all";
    }

    function getFilteredHistory() {
        const range = getFilterRange(selectedFilterKey);
        if (!range.start && !range.end)
            return NotificationService.historyList;
        return NotificationService.historyList.filter(n => {
            const ts = n.timestamp;
            if (range.start && ts < range.start.getTime())
                return false;
            if (range.end && ts >= range.end.getTime())
                return false;
            return true;
        });
    }

    function getChipIndex() {
        for (let i = 0; i < visibleFilters.length; i++) {
            if (visibleFilters[i].key === selectedFilterKey)
                return i;
        }
        return 0;
    }

    function enableAutoScroll() {
    }

    function removeWithScrollPreserve(itemId) {
        historyListView.savedY = historyListView.contentY;
        NotificationService.removeFromHistory(itemId);
        layoutTimer.restart();
    }

    Timer {
        id: layoutTimer
        interval: 0
        onTriggered: historyListView.forceLayout()
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spacingS

        DFilterChips {
            id: filterChips
            width: parent.width
            visible: root.visibleFilters.length > 1
            currentIndex: root.getChipIndex()
            showCounts: true
            model: root.visibleFilters
            onSelectionChanged: index => {
                if (index >= 0 && index < root.visibleFilters.length) {
                    root.selectedFilterKey = root.visibleFilters[index].key;
                }
            }
        }

        DListView {
            id: historyListView
            x: -root.swipeBleed
            width: parent.width + root.swipeBleed * 2
            height: parent.height - (filterChips.visible ? filterChips.height + Theme.spacingS : 0)
            clip: true
            leftMargin: root.swipeBleed
            rightMargin: root.swipeBleed
            spacing: Theme.groupedListGap
            rowFadeEnabled: NotificationMetrics.animationsEnabled
            fadeInitialRows: false

            model: ScriptModel {
                id: historyModel
                values: root.getFilteredHistory()
                objectProp: "id"
            }

            NotificationEmptyState {
                parent: historyListView
                visible: historyListView.count === 0
            }

            NotificationSwipeGroup {
                id: historySwipe
            }

            delegate: NotificationSwipeRow {
                id: delegateRoot
                required property var modelData

                group: historySwipe
                bleed: root.swipeBleed
                width: ListView.view.width - root.swipeBleed * 2
                height: historyCard.height
                onDismissed: root.removeWithScrollPreserve(modelData?.id || "")

                Component.onCompleted: historyListView.fadeIn(delegateRoot, index)

                HistoryNotificationCard {
                    id: historyCard
                    width: parent.width
                    x: delegateRoot.offset
                    historyItem: modelData
                    nested: root.nested
                    firstInGroup: index === 0
                    lastInGroup: index === historyListView.count - 1
                    topRoundness: delegateRoot.topRoundness
                    bottomRoundness: delegateRoot.bottomRoundness
                    contentOpacity: delegateRoot.contentOpacity
                    isSelected: root.keyboardActive && root.focusAllowed && root.selectedIndex === index
                    keyboardNavigationActive: root.keyboardActive && root.focusAllowed
                }
            }
        }
    }

    function selectNext() {
        if (historyModel.values.length === 0)
            return;
        keyboardActive = true;
        selectedIndex = Math.min(selectedIndex + 1, historyModel.values.length - 1);
        historyListView.revealIndex(selectedIndex);
    }

    function selectPrevious() {
        if (historyModel.values.length === 0)
            return;
        if (selectedIndex <= 0) {
            keyboardActive = false;
            selectedIndex = -1;
            return;
        }
        selectedIndex = Math.max(selectedIndex - 1, 0);
        historyListView.revealIndex(selectedIndex);
    }

    function clearSelected() {
        if (selectedIndex < 0 || selectedIndex >= historyModel.values.length)
            return;
        const item = historyModel.values[selectedIndex];
        NotificationService.removeFromHistory(item.id);
        if (historyModel.values.length === 0) {
            keyboardActive = false;
            selectedIndex = -1;
        } else {
            selectedIndex = Math.min(selectedIndex, historyModel.values.length - 1);
        }
    }

    function handleKey(event) {
        const dismissKey = event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace;
        if (dismissKey && (event.modifiers & Qt.ShiftModifier)) {
            NotificationService.clearHistory();
            keyboardActive = false;
            selectedIndex = -1;
            event.accepted = true;
            return;
        }
        switch (event.key) {
        case Qt.Key_Down:
            if (!keyboardActive) {
                keyboardActive = true;
                selectedIndex = 0;
                event.accepted = true;
                return;
            }
            selectNext();
            event.accepted = true;
            return;
        case Qt.Key_Up:
            if (keyboardActive)
                selectPrevious();
            event.accepted = true;
            return;
        case Qt.Key_Delete:
        case Qt.Key_Backspace:
            if (!keyboardActive)
                return;
            clearSelected();
            event.accepted = true;
            return;
        case Qt.Key_F10:
            showKeyboardHints = !showKeyboardHints;
            event.accepted = true;
        }
    }
}
