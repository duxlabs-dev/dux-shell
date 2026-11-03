import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DFilterChips {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankFilterChips", "DFilterChips", "qs.DCommon.Widgets")
}
