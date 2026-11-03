import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DScrollbar {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankScrollbar", "DScrollbar", "qs.DCommon.Widgets")
}
