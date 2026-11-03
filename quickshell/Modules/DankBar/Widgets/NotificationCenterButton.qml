import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.NotificationCenterButton {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "NotificationCenterButton", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
