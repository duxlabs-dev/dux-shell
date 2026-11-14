import QtQuick
import Quickshell
import qs.Modals.FileBrowser

Scope {
    id: root

    property bool surface: false
    property string target: ""

    signal picked(string key, string path)

    function open(key) {
        target = key;
        loader.active = true;
        if (loader.item)
            loader.item.open();
    }

    readonly property var certFilters: ["*.pem", "*.crt", "*.cer", "*.der", "*.p12", "*.pfx", "*.key", "*"]

    LazyLoader {
        id: loader
        active: false
        component: root.surface ? surfaceBrowser : windowBrowser
    }

    Component {
        id: windowBrowser

        FileBrowserModal {
            bucket: "certificate"
            filters: root.certFilters
            onAccepted: paths => root.picked(root.target, paths[0])
        }
    }

    Component {
        id: surfaceBrowser

        FileBrowserSurfaceModal {
            bucket: "certificate"
            filters: root.certFilters
            onAccepted: paths => root.picked(root.target, paths[0])
        }
    }
}
