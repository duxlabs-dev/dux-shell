import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.GpuTemperature {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "GpuTemperature", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
