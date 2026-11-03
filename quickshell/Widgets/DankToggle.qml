import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DToggle {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankToggle", "DToggle", "qs.DCommon.Widgets")
}
