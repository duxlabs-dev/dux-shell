import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.Weather {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "Weather", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
