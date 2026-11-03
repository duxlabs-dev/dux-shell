import QtQuick
import qs.Common
import qs.Modules.DDash as New

New.WeatherTab {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "WeatherTab", "qs.Modules.DankDash", "qs.Modules.DDash")
}
