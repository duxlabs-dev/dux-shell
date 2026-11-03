pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Services

FocusScope {
    id: root

    required property var controller
    property var effectiveScreen: null
    property real alignedX: 0
    property real alignedY: 0
    property real alignedWidth: 0
    property real alignedHeight: 0
    property QtObject resizeGeometry: null
    readonly property real inset: CcMetrics.islandInset
    property bool _heightReportPending: false
    signal windowRequested(string windowName)

    clip: true

    function resetState() {
        hostContract.editMode = false;
        hostContract.expandedSection = "";
    }

    function beginSession() {
        hostContract.editMode = false;
        hostContract.expandedSection = root.controller.controlCenterPendingSection || "";
        root.queueHeightReport();
    }

    function focusFace() {
        content.forceActiveFocus();
        return true;
    }

    function queueHeightReport() {
        if (root._heightReportPending)
            return;
        root._heightReportPending = true;
        Qt.callLater(() => {
            root._heightReportPending = false;
            root.controller.setDestinationContentHeight("controlcenter", content.targetImplicitHeight + root.inset * 2);
        });
    }

    QtObject {
        id: hostContract

        property bool editMode: false
        property string expandedSection: ""

        onEditModeChanged: root.controller.setEditing("controlcenter", editMode, CcMetrics.islandEditRoom)

        readonly property int gridColumnCap: root.controller.controlCenterColumnCap
        readonly property int gridColumns: root.controller.controlCenterColumns
        readonly property real availableHeight: root.controller.controlCenterMaxHeight - root.inset * 2
        readonly property real sheetContentWidth: root.controller.controlCenterSheetWidth
        readonly property real renderedAlignedX: (root.resizeGeometry?.renderedX ?? 0) + root.inset
        readonly property real renderedAlignedY: root.resizeGeometry?.renderedY ?? 0
        readonly property bool shouldBeVisible: root.controller.activeActivity === "controlcenter" && root.controller.expanded
        readonly property bool headerTogglesClose: true
        readonly property real editRoom: CcMetrics.islandEditRoom
        readonly property bool editRoomShown: root.controller.editRoomGranted && root.controller.editingActivity === "controlcenter"
        readonly property bool growsFromTop: root.controller.edge === "top"
        readonly property bool powerMenuOpen: PopoutService.powerMenuModalLoader?.item?.shouldBeVisible ?? false
        readonly property var screen: root.effectiveScreen
        readonly property var triggerScreen: root.effectiveScreen
        readonly property var colorPickerModal: PopoutService.colorPickerModal
        readonly property var powerMenuModalLoader: PopoutService.powerMenuModalLoader
        readonly property var transientSurfaceTracker: root.controller.transientSurfaces
        readonly property real alignedX: root.alignedX
        readonly property real alignedY: root.alignedY
        readonly property real alignedWidth: root.alignedWidth
        readonly property real alignedHeight: root.alignedHeight
        readonly property real popupWidth: root.alignedWidth
        readonly property real popupHeight: root.alignedHeight

        signal lockRequested

        function close() {
            root.controller.requestCollapse();
        }

        function openSettings() {
            root.windowRequested("settings");
        }

        function openAccounts() {
            root.windowRequested("accounts");
        }

        function openColorPicker() {
            if (!PopoutService.colorPickerModal)
                return;
            root.windowRequested("colorPicker");
        }

        function collapseAll() {
            hostContract.expandedSection = "";
        }

        function alignedXFor(width) {
            return (root.resizeGeometry?.screenXFor(width + root.inset * 2) ?? 0) + root.inset;
        }
    }

    function releaseScanState() {
        if (NetworkService.activeService)
            NetworkService.activeService.autoRefreshEnabled = false;
        if (BluetoothService.adapter && BluetoothService.adapter.discovering)
            BluetoothService.adapter.discovering = false;
    }

    function applyPresentationLifecycle() {
        if (!hostContract.shouldBeVisible) {
            root.releaseScanState();
            return;
        }
        if (NetworkService.activeService)
            NetworkService.activeService.autoRefreshEnabled = NetworkService.wifiEnabled;
    }

    Component.onDestruction: {
        root.controller.setEditing("controlcenter", false);
        if (hostContract.shouldBeVisible)
            root.releaseScanState();
    }

    Connections {
        target: hostContract

        function onLockRequested() {
            IdleService.lockRequested();
        }

        function onShouldBeVisibleChanged() {
            Qt.callLater(root.applyPresentationLifecycle);
        }
    }

    Connections {
        target: NetworkService

        function onCredentialsRequestedChanged() {
            if (NetworkService.credentialsRequested && hostContract.shouldBeVisible)
                root.controller.requestCollapse();
        }
    }

    ControlCenterContent {
        id: content

        anchors.fill: parent
        anchors.margins: root.inset
        host: hostContract

        onTargetImplicitHeightChanged: root.queueHeightReport()
    }

    Connections {
        target: root.controller

        function onSessionStarted(activityId) {
            if (activityId === "controlcenter")
                Qt.callLater(root.beginSession);
        }

        function onExpandedChanged() {
            if (!root.controller.expanded)
                root.resetState();
        }

        function onActiveActivityChanged() {
            if (root.controller.activeActivity !== "controlcenter")
                root.resetState();
        }
    }

    Component.onCompleted: root.controller.markVisualsReady("controlcenter")
}
