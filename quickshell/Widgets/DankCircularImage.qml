import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DCircularImage {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankCircularImage", "DCircularImage", "qs.DCommon.Widgets")
}
