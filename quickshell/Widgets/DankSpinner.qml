import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DSpinner {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankSpinner", "DSpinner", "qs.DCommon.Widgets")
}
