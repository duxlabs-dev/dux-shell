import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.IdleInhibitor {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "IdleInhibitor", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
