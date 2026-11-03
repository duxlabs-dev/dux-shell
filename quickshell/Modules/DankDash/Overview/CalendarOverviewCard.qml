import QtQuick
import qs.Common
import qs.Modules.DDash.Overview as New

New.CalendarOverviewCard {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "CalendarOverviewCard", "qs.Modules.DankDash.Overview", "qs.Modules.DDash.Overview")
}
