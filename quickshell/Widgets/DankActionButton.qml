import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DActionButton {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankActionButton", "DActionButton", "qs.DCommon.Widgets")
}
