import QtQuick
import qs.Common

DTooltip {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankTooltip", "DTooltip", "qs.Widgets")
}
