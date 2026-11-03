import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DIcon {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankIcon", "DIcon", "qs.DCommon.Widgets")
}
