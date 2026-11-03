import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DIconPicker {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankIconPicker", "DIconPicker", "qs.DCommon.Widgets")
}
