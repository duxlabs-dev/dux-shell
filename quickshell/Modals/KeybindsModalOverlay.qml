import QtQml
import QtQuick
import qs.Common
import qs.Modals
import qs.Modals.Common
import qs.Services

DModal {
    id: overlay

    signal floatingToggleRequested

    layerNamespace: "dms:keybinds"
    useOverlayLayer: true
    property real _maxW: Math.min(overlay.screenWidth * 0.92, 1200)
    property real _maxH: Math.min(overlay.screenHeight * 0.92, 900)
    modalWidth: _maxW
    modalHeight: _maxH
    onBackgroundClicked: close()
    onOpened: {
        Qt.callLater(() => {
            modalFocusScope.forceActiveFocus();
            if (contentLoader.item?.searchField)
                contentLoader.item.searchField.forceActiveFocus();
        });
        if (!Object.keys(KeybindsService.cheatsheet).length && KeybindsService.cheatsheetAvailable)
            KeybindsService.loadCheatsheet();
    }

    content: Component {
        KeybindsContent {
            anchors.fill: parent
            showFloatingToggle: true
            floating: false
            onCloseRequested: overlay.close()
            onFloatingToggleRequested: overlay.floatingToggleRequested()
        }
    }
}
