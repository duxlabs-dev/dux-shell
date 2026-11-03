import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.ControlCenterButton {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "ControlCenterButton", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
