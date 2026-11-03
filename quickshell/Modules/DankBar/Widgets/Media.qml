import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.Media {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "Media", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
