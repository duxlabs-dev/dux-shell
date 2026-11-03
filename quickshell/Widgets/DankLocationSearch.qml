import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DLocationSearch {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankLocationSearch", "DLocationSearch", "qs.DCommon.Widgets")
}
