import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.MonitorPill {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "MonitorPill", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
