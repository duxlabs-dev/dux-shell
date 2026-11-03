import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DTextEdit {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankTextEdit", "DTextEdit", "qs.DCommon.Widgets")
}
