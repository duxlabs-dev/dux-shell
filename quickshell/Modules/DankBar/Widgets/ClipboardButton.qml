import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.ClipboardButton {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "ClipboardButton", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
