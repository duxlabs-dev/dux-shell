import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DKeycap {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankKeycap", "DKeycap", "qs.DCommon.Widgets")
}
