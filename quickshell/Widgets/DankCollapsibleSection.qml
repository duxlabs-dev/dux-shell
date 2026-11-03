import QtQuick
import qs.Common
import qs.DCommon.Widgets as DCommon

DCommon.DCollapsibleSection {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankCollapsibleSection", "DCollapsibleSection", "qs.DCommon.Widgets")
}
