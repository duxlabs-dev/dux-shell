import QtQuick
import qs.Common

DSlideout {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankSlideout", "DSlideout", "qs.Widgets")
}
