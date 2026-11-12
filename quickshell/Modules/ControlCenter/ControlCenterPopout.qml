import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

DPopout {
    id: root

    layerNamespace: "dms:control-center"
    resizeCurve: Theme.expressiveCurves.standard
    resizeDuration: CcMetrics.transitionDuration
    resizeMotion: true
    resizing: contentLoader.item?.panelResizing ?? false
    // Hangs above wherever a strip below would push the panel off its resting spot (bottom bar, low side-bar trigger).
    readonly property bool stripAbove: alignedYFor(0, CcMetrics.editActionsHeight) !== alignedYFor(0, 0)
    readonly property bool growsFromTop: effectiveBarPosition === SettingsData.Position.Top
    bottomOverflow: _stripEdit && !stripAbove ? CcMetrics.editActionsHeight : 0
    topOverflow: _stripEdit && stripAbove ? CcMetrics.editActionsHeight : 0
    leftOverflow: dockFits && dockSide === "left" ? _dockReserve : 0
    rightOverflow: dockFits && dockSide === "right" ? _dockReserve : 0
    sideBlurItem: contentLoader.item?.dockedBlurItem ?? null
    sideBlurRadius: contentLoader.item?.surfaceRadius ?? 0
    inputMargin: editMode ? CcMetrics.editOverflow : 0

    property string expandedSection: ""
    property string pendingSection: ""
    // Outlives the content, which unloads a while after closing.
    property int currentPage: 0
    property var triggerScreen: null
    property bool editMode: false
    // Latched on entering edit mode ("" until decided, then "strip", "left" or "right") so a width change cannot move the body mid-edit.
    property string _editLayout: ""
    // Drops to the strip if the screen loses the room mid-edit (output change, bar resize) instead of squeezing the panel.
    readonly property string dockSide: (_editLayout === "left" || _editLayout === "right") && _dockRoomFor(_editLayout) ? _editLayout : ""
    readonly property bool _stripEdit: editMode && editLayoutDecided && dockSide === ""
    // Connected, the body's flares run along the bar, so the panel keeps clear of them and of the bar itself.
    readonly property real dockGap: usesConnectedSurfaceChrome ? CcMetrics.dockedPanelConnectedGap : CcMetrics.dockedPanelGap
    readonly property real dockInset: usesConnectedSurfaceChrome && (effectiveBarPosition === SettingsData.Position.Top || effectiveBarPosition === SettingsData.Position.Bottom) ? dockGap : 0
    readonly property real _dockMinHeight: CcMetrics.dockedPanelMinHeight + dockInset
    readonly property real _dockReserve: CcMetrics.dockedPanelWidth + dockGap
    // Docked was wanted but did not fit: Add widget opens the list as a popover over the body instead of the sheet.
    readonly property bool editPopover: _stripEdit && SettingsData.controlCenterEditLayout === "docked"
    readonly property bool dockFits: editMode && dockSide !== ""
    readonly property bool editLayoutDecided: _editLayout !== ""
    readonly property int _baseColumnCap: CcMetrics.columnCapFor(maxBodyWidth > 0 ? maxBodyWidth - PopoutMetrics.editOverflow * 2 : CcMetrics.sheetWidthDefault)

    function _dockedCap(side) {
        for (let columns = _baseColumnCap; columns >= 1; columns--) {
            const width = CcMetrics.sheetWidthFor(columns);
            if ((side === "left" ? roomLeftFor(width) : roomRightFor(width)) >= _dockReserve)
                return columns;
        }
        return 0;
    }

    function _dockRoomFor(side) {
        return _maxPopupHeight(0) >= _dockMinHeight && _dockedCap(side) >= CcMetrics.minimumColumns;
    }

    // Small or short screens keep the strip, with the list in a popover.
    function _pickDockSide() {
        if (SettingsData.controlCenterEditLayout !== "docked")
            return "strip";
        // Docking never grows the body, so a short one keeps the strip.
        if (popupHeight < _dockMinHeight)
            return "strip";
        let preferLeft;
        switch (effectiveBarPosition) {
        case SettingsData.Position.Right:
            preferLeft = true;
            break;
        case SettingsData.Position.Left:
            preferLeft = false;
            break;
        default:
            preferLeft = alignedX + alignedWidth / 2 >= screenWidth / 2;
        }
        const first = preferLeft ? "left" : "right";
        const second = preferLeft ? "right" : "left";
        const need = Math.max(gridColumns, CcMetrics.minimumColumns);
        if (_dockedCap(first) >= need)
            return first;
        if (_dockedCap(second) >= need)
            return second;
        return "strip";
    }

    onEditModeChanged: _editLayout = editMode ? _pickDockSide() : ""
    // While docked the cap keeps the panel's room free, so widening the body can never squeeze it out.
    readonly property int gridColumnCap: dockSide !== "" ? Math.min(_baseColumnCap, _dockedCap(dockSide)) : _baseColumnCap
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
    // With the panel or popover up, removing tiles stops shrinking the body at its minimum.
    readonly property real _editFloor: dockFits ? _dockMinHeight : (contentLoader.item?.widgetPopoverOpen ?? false) ? CcMetrics.widgetPopoverMinHeight + CcMetrics.sheetPadding * 2 : CcMetrics.minHeight
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
