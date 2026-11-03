import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DColorSwatch {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankColorSwatch", "DColorSwatch", "qs.DCommon.Widgets")
}
