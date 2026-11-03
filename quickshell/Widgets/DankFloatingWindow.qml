import QtQuick
import qs.Common

DFloatingWindow {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankFloatingWindow", "DFloatingWindow", "qs.Widgets")
}
