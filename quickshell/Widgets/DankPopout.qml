import QtQuick
import qs.Common

DPopout {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankPopout", "DPopout", "qs.Widgets")
}
