import QtQuick
import qs.Common
import qs.Modules.DDash as New

New.MediaPlayerTab {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "MediaPlayerTab", "qs.Modules.DankDash", "qs.Modules.DDash")
}
