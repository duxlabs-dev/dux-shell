import QtQuick
import qs.Common
import qs.Modals.FileBrowser
import qs.Services

FileBrowserSurfaceModal {
    browserTitle: I18n.tr("Import VPN")
    bucket: "vpn"
    filters: VPNService.getFileFilter()
    onAccepted: paths => VPNService.importVpn(paths[0])
}
