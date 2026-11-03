import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DDropdown {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankDropdown", "DDropdown", "qs.DCommon.Widgets")
}
