import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets as New

New.PrivacyIndicator {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "PrivacyIndicator", "qs.Modules.DankBar.Widgets", "qs.Modules.DBar.Widgets")
}
