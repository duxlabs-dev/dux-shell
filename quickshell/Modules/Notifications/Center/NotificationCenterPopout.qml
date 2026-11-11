import QtQuick
import qs.Common
import qs.Modules.DDash
import qs.Modules.Notifications
import qs.Services
import qs.Widgets

DPopout {
    id: root

    layerNamespace: "dms:notification-center-popout"
    contentHandlesKeys: true
    onOpened: contentFocusTimer.restart()

    Timer {
        id: contentFocusTimer
        interval: 0
        onTriggered: {
            if (root.shouldBeVisible)
                root.contentLoader.item?.tab.forceActiveFocus();
        }
    }

    property bool notificationHistoryVisible: false
    property var triggerScreen: null
    property real stablePopupHeight: NotificationMetrics.popupWidth
    property real _lastAlignedContentHeight: -1
    property bool _pendingSizedOpen: false
    property bool _heightUpdatePending: false

    function updateStablePopupHeight() {
        const item = contentLoader.item;
        if (item && !root.shouldBeVisible)
            item.tab.forceLayout();
        const target = item ? Theme.px(item.implicitHeight, dpr) : NotificationMetrics.popupWidth;
        if (Math.abs(target - _lastAlignedContentHeight) < 0.5)
            return;
        _lastAlignedContentHeight = target;
        stablePopupHeight = target;
    }

    function queueStablePopupHeightUpdate() {
        if (_heightUpdatePending)
            return;
        _heightUpdatePending = true;
        Qt.callLater(() => {
            _heightUpdatePending = false;
            updateStablePopupHeight();
        });
    }

    popupWidth: NotificationMetrics.popupWidth + Theme.spacingL
    popupHeight: stablePopupHeight
    positioning: ""
    suspendShadowWhileResizing: false

    screen: triggerScreen

    function toggle() {
        notificationHistoryVisible = !notificationHistoryVisible;
    }

    function present() {
        openSized();
    }

    function openSized() {
        if (!notificationHistoryVisible)
            return;

        primeContent();
        if (contentLoader.item) {
            updateStablePopupHeight();
            _pendingSizedOpen = false;
            Qt.callLater(() => {
                if (!notificationHistoryVisible)
                    return;
                updateStablePopupHeight();
                open();
                clearPrimedContent();
            });
            return;
        }

        _pendingSizedOpen = true;
    }

    function requestSettings() {
        notificationHistoryVisible = false;
        PopoutService.openSettingsWithTab("notifications", root, () => root.open());
    }

    onBackgroundClicked: {
        notificationHistoryVisible = false;
    }

    onNotificationHistoryVisibleChanged: {
        if (notificationHistoryVisible) {
            openSized();
        } else {
            _pendingSizedOpen = false;
            clearPrimedContent();
            close();
        }
    }

    Connections {
        target: contentLoader
        function onLoaded() {
            root.updateStablePopupHeight();
            if (!root._pendingSizedOpen || !root.notificationHistoryVisible)
                return;
            Qt.callLater(() => {
                if (!root._pendingSizedOpen || !root.notificationHistoryVisible)
                    return;
                root.updateStablePopupHeight();
                root._pendingSizedOpen = false;
                root.open();
                root.clearPrimedContent();
            });
        }
    }

    readonly property real contentImplicitHeight: contentLoader.item?.implicitHeight ?? 0

    onContentImplicitHeightChanged: queueStablePopupHeightUpdate()

    onDprChanged: updateStablePopupHeight()

    onShouldBeVisibleChanged: {
        notificationHistoryVisible = shouldBeVisible;

        if (shouldBeVisible) {
            NotificationService.onOverlayOpen();
            updateStablePopupHeight();
            return;
        }
        NotificationService.onOverlayClose();
        NotificationService.expandedGroups = {};
        NotificationService.expandedMessages = {};
    }

    content: Component {
        FocusScope {
            id: notificationContent

            readonly property alias tab: tab
            readonly property real maxContentHeight: (root.screen?.height ?? 1080) * NotificationMetrics.screenHeightRatio

            implicitHeight: Math.max(NotificationMetrics.centerMinHeight, Math.min(PopoutMetrics.contentPadding * 2 + Math.min(tab.contentHeight, NotificationMetrics.centerMaxHeight), maxContentHeight))
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.notificationHistoryVisible = false;
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Left && tab.currentTab > 0) {
                    tab.currentTab = 0;
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Right && tab.currentTab === 0 && SettingsData.notificationHistoryEnabled) {
                    tab.currentTab = 1;
                    event.accepted = true;
                }
            }

            Item {
                anchors.fill: parent
                clip: height < tab.height + PopoutMetrics.contentPadding * 2

                NotificationsTab {
                    id: tab
                    x: PopoutMetrics.contentPadding
                    y: PopoutMetrics.contentPadding
                    width: parent.width - PopoutMetrics.contentPadding * 2
                    height: Math.max(parent.height, root.alignedHeight) - PopoutMetrics.contentPadding * 2
                    live: root.shouldBeVisible
                    sizeToContent: true
                    settingsAction: true
                    swipeBleed: PopoutMetrics.contentPadding
                    transientSurfaceTracker: root.transientSurfaceTracker
                    onSettingsRequested: root.requestSettings()
                }
            }
        }
    }
}
