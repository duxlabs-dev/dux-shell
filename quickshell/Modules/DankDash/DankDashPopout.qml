import QtQuick
import qs.Common
import qs.Modules.DDash as New

New.DDashPopout {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankDashPopout", "DDashPopout", "qs.Modules.DDash")
}
