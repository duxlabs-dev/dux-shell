import QtQuick
import qs.Common
import qs.Modules.DDash as New

New.OverviewTab {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "OverviewTab", "qs.Modules.DankDash", "qs.Modules.DDash")
}
