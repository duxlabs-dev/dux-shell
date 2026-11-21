import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

DPopout {
    id: root

    layerNamespace: "dms:control-center"
    resizeMotion: true
    resizing: contentLoader.item?.panelResizing ?? false
    // Hangs above wherever a strip below would push the panel off its resting spot (bottom bar, low side-bar trigger).
    readonly property bool stripAbove: alignedYFor(0, CcMetrics.editActionsHeight) !== alignedYFor(0, 0)
    readonly property bool growsFromTop: effectiveBarPosition === SettingsData.Position.Top
    bottomOverflow: _stripEdit && !stripAbove ? CcMetrics.editActionsHeight : 0
    topOverflow: _stripEdit && stripAbove ? CcMetrics.editActionsHeight : 0
    leftOverflow: dock.leftOverflow
    rightOverflow: dock.rightOverflow
    readonly property real dockPanelMinHeight: CcMetrics.dockedPanelMinHeight
    readonly property real dockOverhang: dock.overhang
    readonly property bool dockAbove: dock.dockAbove
    sideTopOverflow: dock.sideTopOverflow
    sideBottomOverflow: dock.sideBottomOverflow
    sideBlurItem: contentLoader.item?.dockedBlurItem ?? null
    sideBlurRadius: contentLoader.item?.surfaceRadius ?? 0
    inputMargin: editMode ? CcMetrics.editOverflow : 0
    minimumSurfaceWidth: editMode ? CcMetrics.sheetWidthFor(gridColumnCap) : 0

    property string expandedSection: ""
    property string pendingSection: ""
    // Outlives the content, which unloads a while after closing.
    property int currentPage: 0
    property var triggerScreen: null
    property bool editMode: false
    readonly property string dockSide: dock.side
    readonly property bool _stripEdit: dock.stripEdit
    readonly property real dockGap: dock.gap
    readonly property real dockInset: dock.inset
    readonly property bool editPopover: dock.popover
    readonly property bool dockFits: dock.fits
    readonly property bool editLayoutDecided: dock.decided
    readonly property int _baseColumnCap: CcMetrics.columnCapFor(maxBodyWidth > 0 ? maxBodyWidth - PopoutMetrics.editOverflow * 2 : CcMetrics.sheetWidthDefault)

    DockedEditLayout {
        id: dock
        popout: root
        editMode: root.editMode
        wanted: SettingsData.controlCenterEditLayout === "docked"
        panelWidth: CcMetrics.dockedPanelWidth
        panelGap: CcMetrics.dockedPanelGap
        connectedPanelGap: CcMetrics.dockedPanelConnectedGap
        minHeight: CcMetrics.dockedPanelMinHeight
        minBodyHeight: CcMetrics.minHeight
        availableHeight: root.availableHeight
        baseCap: root._baseColumnCap
        pickColumns: Math.max(root.gridColumns, CcMetrics.minimumColumns)
        keepColumns: CcMetrics.minimumColumns
        widthFor: columns => CcMetrics.sheetWidthFor(columns)
    }

    readonly property int gridColumnCap: dock.cap
    readonly property int gridColumns: Math.min(CcMetrics.gridColumns, gridColumnCap)
    readonly property real sheetContentWidth: CcMetrics.sheetWidthFor(gridColumns)
    readonly property real availableHeight: _maxPopupHeight(0)

    function resizeYFor(height) {
        const overhang = dock.overhangFor(height);
        return alignedYFor(topOverflow + (dockAbove ? overhang : 0), bottomOverflow + (dockAbove ? 0 : overhang), height);
    }
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
    // With the popover up, removing tiles stops shrinking the body at its minimum.
    readonly property real _editFloor: !dockFits && (contentLoader.item?.widgetPopoverOpen ?? false) ? CcMetrics.widgetPopoverMinHeight + CcMetrics.sheetPadding * 2 : CcMetrics.minHeight
    popupHeight: Math.min(_maxPopupHeight(_stripEdit ? CcMetrics.editOverflow : 0), Math.max(_editFloor, contentLoader.item?.targetImplicitHeight ?? CcMetrics.minHeight))
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
