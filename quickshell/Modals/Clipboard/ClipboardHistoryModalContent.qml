import QtQuick

ClipboardHistoryContent {
    required property var modal

    surfaceHost: modal
    transientSurfaceTracker: modal.transientSurfaceTracker
    clearConfirmDialog: modal.confirmDialog
    onCloseRequested: modal.hide()
    onInstantCloseRequested: modal.instantHide()
}
