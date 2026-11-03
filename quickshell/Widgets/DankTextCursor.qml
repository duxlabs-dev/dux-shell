import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DTextCursor {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankTextCursor", "DTextCursor", "qs.DCommon.Widgets")
}
