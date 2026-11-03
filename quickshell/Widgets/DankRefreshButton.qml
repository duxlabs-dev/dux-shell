import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DRefreshButton {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankRefreshButton", "DRefreshButton", "qs.DCommon.Widgets")
}
