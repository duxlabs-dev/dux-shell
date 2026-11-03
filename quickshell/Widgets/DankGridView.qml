import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DGridView {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankGridView", "DGridView", "qs.DCommon.Widgets")
}
