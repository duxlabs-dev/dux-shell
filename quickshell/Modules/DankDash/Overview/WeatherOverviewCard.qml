import QtQuick
import qs.Common
import qs.Modules.DDash.Overview as New

New.WeatherOverviewCard {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "WeatherOverviewCard", "qs.Modules.DankDash.Overview", "qs.Modules.DDash.Overview")
}
