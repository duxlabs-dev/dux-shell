import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.PowerMenuButton {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "PowerMenuButton", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
