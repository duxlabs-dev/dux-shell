import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DSlider {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankSlider", "DSlider", "qs.DCommon.Widgets")
}
