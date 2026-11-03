import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DBlink {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankBlink", "DBlink", "qs.DCommon.Widgets")
}
