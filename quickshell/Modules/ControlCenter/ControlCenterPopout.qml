import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

DPopout {
    id: root

    layerNamespace: "dms:control-center"
    fullHeightSurface: true
    resizeCurve: Theme.expressiveCurves.standard
    resizeDuration: CcMetrics.transitionDuration
    resizeMotion: true
    resizing: contentLoader.item?.panelResizing ?? false
    surfacePadding: CcMetrics.editOverflow
    // Hangs above wherever a strip below would push the panel off its resting spot (bottom bar, low side-bar trigger).
    readonly property bool stripAbove: alignedYFor(0, CcMetrics.editActionsHeight) !== alignedYFor(0, 0)
    readonly property bool growsFromTop: effectiveBarPosition === SettingsData.Position.Top
    bottomOverflow: editMode && !stripAbove ? CcMetrics.editActionsHeight : 0
    topOverflow: editMode && stripAbove ? CcMetrics.editActionsHeight : 0
    inputMargin: editMode ? CcMetrics.editOverflow : 0
    minimumSurfaceWidth: editMode ? CcMetrics.sheetWidthFor(gridColumnCap) : 0

    property string expandedSection: ""
    property string pendingSection: ""
    property var triggerScreen: null
    property bool editMode: false
    readonly property int gridColumnCap: CcMetrics.columnCapFor(maxBodyWidth > 0 ? maxBodyWidth - PopoutMetrics.editOverflow * 2 : CcMetrics.sheetWidthDefault)
    readonly property int gridColumns: Math.min(CcMetrics.gridColumns, gridColumnCap)
    readonly property real sheetContentWidth: CcMetrics.sheetWidthFor(gridColumns)
    readonly property real availableHeight: _maxPopupHeight(0)
    property bool powerMenuOpen: powerMenuModalLoader?.item?.shouldBeVisible ?? false
    property var colorPickerModal: null
    property var powerMenuModalLoader: null

    property string requestedWindow: ""

    function openSettings() {
        requestedWindow = "settings";
        close();
    }

    function openAccounts() {
        requestedWindow = "accounts";
        close();
    }

    function openColorPicker() {
        if (!colorPickerModal)
            return;
        requestedWindow = "colorPicker";
        close();
    }

    function completeWindowClose() {
        if (!requestedWindow || !isClosing)
            return;
        instantClose();
    }

    onCloseAnimationFinished: finishClose.schedule()

    DeferredAction {
        id: finishClose
        onTriggered: root.completeWindowClose()
    }

    DeferredAction {
        id: openWindow
        onTriggered: {
            const requested = root.requestedWindow;
            root.requestedWindow = "";
            switch (requested) {
            case "settings":
                PopoutService.focusOrToggleSettings();
                break;
            case "accounts":
                PopoutService.openSettingsWithTab("user_accounts");
                break;
            case "colorPicker":
                root.colorPickerModal?.show();
                break;
            }
        }
    }

    onPopoutClosed: {
        editMode = false;
        collapseAll();
        if (requestedWindow)
            openWindow.schedule();
    }

    signal lockRequested

    function _maxPopupHeight(reserved) {
        if (maxBodyHeight <= 0)
            return CcMetrics.fallbackScreenHeight - CcMetrics.maxHeightInset;
        return maxBodyHeight - reserved;
    }

    function collapseAll() {
        expandedSection = "";
    }

    popupWidth: sheetContentWidth
    popupHeight: Math.min(_maxPopupHeight(editMode ? CcMetrics.editOverflow : 0), Math.max(CcMetrics.minHeight, contentLoader.item?.targetImplicitHeight ?? CcMetrics.minHeight))
    triggerWidth: CcMetrics.triggerWidth
    positioning: ""
    screen: triggerScreen
    shouldBeVisible: false
    contentHandlesKeys: true

    property bool credentialsPromptOpen: NetworkService.credentialsRequested
    property bool wifiPasswordModalOpen: PopoutService.wifiPasswordModal?.shouldBeVisible ?? false
    property bool polkitModalOpen: PopoutService.polkitAuthModal?.visible ?? false
    property bool anyModalOpen: credentialsPromptOpen || wifiPasswordModalOpen || polkitModalOpen || powerMenuOpen

    backgroundInteractive: !anyModalOpen
    hoverDismissSuspended: editMode || expandedSection !== "" || anyModalOpen

    onCredentialsPromptOpenChanged: {
        if (credentialsPromptOpen && shouldBeVisible)
            close();
    }

    onPolkitModalOpenChanged: {
        if (polkitModalOpen && shouldBeVisible)
            close();
    }

    customKeyboardFocus: anyModalOpen ? WlrKeyboardFocus.None : null

    onBackgroundClicked: close()

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            finishClose.cancel();
            openWindow.cancel();
            requestedWindow = "";
            expandedSection = pendingSection;
            pendingSection = "";
            Qt.callLater(() => contentLoader.item?.forceActiveFocus());
            return;
        }
        Qt.callLater(() => {
            if (BluetoothService.adapter && BluetoothService.adapter.discovering)
                BluetoothService.adapter.discovering = false;
        });
    }

    content: Component {
        ControlCenterContent {
            host: root
        }
    }
}
