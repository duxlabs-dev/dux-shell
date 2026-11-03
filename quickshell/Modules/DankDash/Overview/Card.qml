import QtQuick
import qs.Common
import qs.Modules.DDash.Overview as New

New.Card {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "Card", "qs.Modules.DankDash.Overview", "qs.Modules.DDash.Overview")
}
