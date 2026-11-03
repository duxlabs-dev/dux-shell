import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.Vpn {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "Vpn", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
