import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.KeyboardLayoutName {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "KeyboardLayoutName", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
