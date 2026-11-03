import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DFlickable {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankFlickable", "DFlickable", "qs.DCommon.Widgets")
}
