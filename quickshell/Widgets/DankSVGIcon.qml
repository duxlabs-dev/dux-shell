import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DSVGIcon {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankSVGIcon", "DSVGIcon", "qs.DCommon.Widgets")
}
