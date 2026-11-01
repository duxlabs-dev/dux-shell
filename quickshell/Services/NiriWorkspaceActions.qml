pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modals.Common
import qs.Services
import "../Common/niri/sections/close.js" as Close

Singleton {
    id: root

    property var _pending: null

    // The modal is created asynchronously on the first activation, so the request waits for it.
    LazyLoader {
        id: confirmLoader
        active: false
        readonly property ConfirmModal loadedModal: item as ConfirmModal
        onLoadedModalChanged: root.showPending()

        ConfirmModal {}
    }

    function showPending() {
        if (!_pending || !confirmLoader.loadedModal)
            return;
        confirmLoader.loadedModal.showWithOptions(_pending);
        _pending = null;
    }

    function focusedWindowIds() {
        const wsId = NiriService.focusedWorkspaceId;
        if (wsId === "")
            return [];
        // focusedWorkspaceId is a string, workspace_id a number.
        return NiriService.windows.filter(w => String(w.workspace_id) === String(wsId)).map(w => w.id);
    }

    function focusedWorkspaceName() {
        const ws = NiriService.allWorkspaces.find(w => String(w.id) === String(NiriService.focusedWorkspaceId));
        return ws ? (ws.name || String(ws.idx)) : "";
    }

    function closeWindows(ids) {
        for (const id of ids)
            NiriService.send({
                "Action": {
                    "CloseWindow": {
                        "id": id
                    }
                }
            });
    }

    function closeFocusedWorkspace() {
        if (!CompositorService.isNiri)
            return "WORKSPACE_UNSUPPORTED_COMPOSITOR";
        const ids = focusedWindowIds();
        if (!ids.length)
            return "WORKSPACE_EMPTY";
        const state = {
            "close.askFrom": NiriPageService.get("close.askFrom"),
            "close.neverAsk": NiriPageService.get("close.neverAsk")
        };
        if (!Close.needsConfirm(state, ids.length)) {
            closeWindows(ids);
            return "WORKSPACE_CLOSED";
        }
        // The ids asked about are the ones closed: a window opened while the dialog is up stays.
        _pending = {
            "title": ids.length === 1 ? I18n.tr("Close %1 window on \"%2\"?", "close whole workspace confirmation; singular, %1 is 1, %2 a workspace name").arg(1).arg(focusedWorkspaceName()) : I18n.tr("Close %1 windows on \"%2\"?", "close whole workspace confirmation, %1 is a count, %2 a workspace name").arg(ids.length).arg(focusedWorkspaceName()),
            "message": I18n.tr("This cannot be undone."),
            "confirmText": I18n.tr("Close all"),
            "cancelText": I18n.tr("Cancel"),
            "confirmColor": Theme.error,
            "defaultButton": 1,
            "onConfirm": () => root.closeWindows(ids)
        };
        confirmLoader.active = true;
        showPending();
        return "WORKSPACE_CONFIRM";
    }
}
