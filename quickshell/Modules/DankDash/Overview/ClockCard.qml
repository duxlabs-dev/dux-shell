import QtQuick
import qs.Common
import qs.Modules.DDash.Overview as New

New.ClockCard {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "ClockCard", "qs.Modules.DankDash.Overview", "qs.Modules.DDash.Overview")
}
