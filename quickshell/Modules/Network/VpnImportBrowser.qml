import QtQuick
import Quickshell

Scope {
    id: root

    property bool surface: false
    property var parentPopout: null

    function open() {
        if (!loader.item) {
            if (root.surface)
                loader.setSource("VpnImportSurfaceBrowser.qml", {
                    parentPopout: root.parentPopout
                });
            else
                loader.setSource("VpnImportWindowBrowser.qml");
        }
        loader.item?.open();
    }

    Loader {
        id: loader
    }
}
