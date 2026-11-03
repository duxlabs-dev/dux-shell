import QtQuick
import qs.Common

DOSD {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankOSD", "DOSD", "qs.Widgets")
}
