import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.DDash
import qs.Services

FocusScope {
    id: root

    required property var modal
    readonly property alias tab: tab

    anchors.fill: parent
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Keys.onPressed: event => {
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

    Column {
        anchors.fill: parent
        anchors.margins: PopoutMetrics.contentPadding
        spacing: PopoutMetrics.contentGap

        DWindowHeader {
            id: header
            width: parent.width
            controls: null
            horizontalPadding: 0
            verticalPadding: 0
            title: I18n.tr("Notifications")
            onCloseRequested: root.modal.close()
        }

        NotificationsTab {
            id: tab
            width: parent.width
            height: parent.height - header.height - parent.spacing
            live: root.modal.shouldBeVisible
            settingsAction: true
            swipeBleed: PopoutMetrics.contentPadding
            transientSurfaceTracker: root.modal.transientSurfaceTracker
            onSettingsRequested: {
                root.modal.close();
                PopoutService.openSettingsWithTab("notifications", root.modal, () => root.modal.open());
            }
        }
    }
}
