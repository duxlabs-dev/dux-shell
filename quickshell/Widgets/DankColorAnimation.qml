import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DColorAnimation {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankColorAnimation", "DColorAnimation", "qs.DCommon.Widgets")
}
