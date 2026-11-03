import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DListView {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankListView", "DListView", "qs.DCommon.Widgets")
}
