import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DTextField {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankTextField", "DTextField", "qs.DCommon.Widgets")
}
