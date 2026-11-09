import QtQuick
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
import qs.Services

Scope {
    id: root

    property bool surface: false
    property var parentPopout: null

    function open() {
        loader.active = true;
        loader.item?.open();
    }

    Loader {
        id: loader
        active: false
        sourceComponent: root.surface ? surfaceBrowser : windowBrowser
    }

    Component {
        id: windowBrowser

        FileBrowserModal {
            browserTitle: I18n.tr("Import VPN")
            bucket: "vpn"
            filters: VPNService.getFileFilter()
            onAccepted: paths => VPNService.importVpn(paths[0])
        }
    }

    Component {
        id: surfaceBrowser

        FileBrowserSurfaceModal {
            browserTitle: I18n.tr("Import VPN")
            bucket: "vpn"
            filters: VPNService.getFileFilter()
            parentPopout: root.parentPopout
            onAccepted: paths => VPNService.importVpn(paths[0])
        }
    }
}
