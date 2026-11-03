import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Modals.Common
import qs.Services

DModal {
    id: root

    property var parentPopout: null
    property var currentFlow: null

    function cancelAuth() {
        const flow = currentFlow;
        currentFlow = null;
        close();
        if (!flow || flow.isCompleted)
            return;
        flow.cancelAuthenticationRequest();
    }

    layerNamespace: "dms:polkit-auth-surface"
    modalWidth: Math.min(Theme.dialogMaxWidth, screenWidth - Theme.spacingXL * 2)
    modalHeight: Math.min(screenHeight - Theme.spacingXL * 2, Math.max(220, contentLoader?.item?.implicitHeight ?? 0))
    closeOnEscapeKey: false
    closeOnBackgroundClick: false
    allowStacking: true
    keepPopoutsOpen: true

    onOpened: {
        currentFlow = PolkitService.agent?.flow ?? null;
        if (parentPopout)
            parentPopout.customKeyboardFocus = WlrKeyboardFocus.None;
        Qt.callLater(() => {
            if (contentLoader.item) {
                contentLoader.item.reset();
                contentLoader.item.focusPasswordField();
            }
        });
    }

    onDialogClosed: {
        if (parentPopout)
            parentPopout.customKeyboardFocus = null;
    }

    Connections {
        target: PolkitService.agent
        enabled: PolkitService.polkitAvailable

        function onIsActiveChanged() {
            if (!(PolkitService.agent?.isActive ?? false))
                root.close();
        }
    }

    content: PolkitAuthContent {
        focus: true
        currentFlow: root.currentFlow
        onCancelRequested: root.cancelAuth()
        onCloseRequested: root.close()
    }
}
