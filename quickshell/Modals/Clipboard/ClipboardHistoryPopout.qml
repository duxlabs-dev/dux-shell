pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Modals.Clipboard
import qs.Modals.Common
import qs.Services
import qs.Widgets

DPopout {
    id: root

    layerNamespace: "dms:clipboard-popout"

    property var parentWidget: null
    property var triggerScreen: null
    property string activeTab: "recents"

    readonly property bool clipboardAvailable: ClipboardService.clipboardAvailable
    readonly property int pinnedCount: ClipboardService.pinnedCount
    readonly property var confirmDialog: clearConfirmDialog
    readonly property var modalFocusScope: contentLoader.item ?? null

    function show() {
        open();

        Qt.callLater(function () {
            if (contentLoader.item) {
                contentLoader.item.activeTab = activeTab;
                contentLoader.item.resetState();
            }
            if (contentLoader.item?.searchField) {
                contentLoader.item.searchField.text = "";
                contentLoader.item.searchField.forceActiveFocus();
            }
        });
    }

    function releaseTextInputFocus() {
        contentLoader.item?.releaseTextInputFocus();
    }

    function hide() {
        releaseTextInputFocus();
        Qt.callLater(function () {
            root.close();
        });
    }

    function clearAll() {
        ClipboardService.clearAll();
    }

    popupWidth: ClipboardConstants.popoutWidth
    popupHeight: ClipboardConstants.popoutHeight
    triggerWidth: 55
    positioning: ""
    screen: triggerScreen
    shouldBeVisible: false
    contentHandlesKeys: true

    onBackgroundClicked: hide()

    onShouldBeVisibleChanged: {
        if (!shouldBeVisible) {
            releaseTextInputFocus();
            return;
        }
        if (clipboardAvailable) {
            if (Theme.isConnectedEffect) {
                Qt.callLater(() => {
                    if (root.shouldBeVisible) {
                        ClipboardService.refresh();
                    }
                });
            } else {
                ClipboardService.refresh();
            }
        }
        Qt.callLater(function () {
            if (contentLoader.item) {
                contentLoader.item.activeTab = activeTab;
                contentLoader.item.resetState();
            }
            if (contentLoader.item?.searchField) {
                contentLoader.item.searchField.text = "";
                contentLoader.item.searchField.forceActiveFocus();
            }
        });
    }

    onPopoutClosed: {
        if (contentLoader.item) {
            contentLoader.item.resetState();
        }
    }

    Ref {
        service: ClipboardService
        active: root.shouldBeVisible
    }

    ConfirmModal {
        id: clearConfirmDialog
        confirmButtonText: I18n.tr("Clear All")
        confirmButtonColor: Theme.primary
        useOverlayLayer: true
        onShouldBeVisibleChanged: {
            if (shouldBeVisible) {
                root.customKeyboardFocus = WlrKeyboardFocus.None;
                selectedButton = 0;
                keyboardNavigation = true;
                return;
            }
            root.customKeyboardFocus = null;
            Qt.callLater(function () {
                if (!root.shouldBeVisible || !root.contentLoader.item) {
                    return;
                }
                root.contentLoader.item.forceActiveFocus();
                if (root.contentLoader.item.searchField) {
                    root.contentLoader.item.searchField.forceActiveFocus();
                }
            });
        }
        Connections {
            target: clearConfirmDialog.modalFocusScope.Keys
            function onPressed(event) {
                if (!clearConfirmDialog.shouldBeVisible || event.key !== Qt.Key_Backtab) {
                    return;
                }
                clearConfirmDialog.selectedButton = clearConfirmDialog.selectedButton === -1 ? 1 : (clearConfirmDialog.selectedButton - 1 + 2) % 2;
                clearConfirmDialog.keyboardNavigation = true;
                event.accepted = true;
            }
        }
    }

    content: Component {
        ClipboardHistoryContent {
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true

            surfaceHost: root
            transientSurfaceTracker: root.transientSurfaceTracker
            popout: true
            clearConfirmDialog: clearConfirmDialog
            onCloseRequested: root.hide()
            onInstantCloseRequested: root.hide()

            Component.onCompleted: {
                activeTab = root.activeTab;
                if (root.shouldBeVisible) {
                    forceActiveFocus();
                }
            }
        }
    }
}
