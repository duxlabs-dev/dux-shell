import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.CpuMonitor {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "CpuMonitor", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
