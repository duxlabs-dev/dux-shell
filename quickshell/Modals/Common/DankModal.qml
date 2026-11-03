import QtQuick
import qs.Common

DModal {
    id: shim
    Component.onCompleted: Deprecation.type(shim, "DankModal", "DModal", "qs.Modals.Common")
}
