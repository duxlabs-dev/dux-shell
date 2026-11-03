import QtQuick
import qs.Common
import qs.Modules.DDash as New

New.WallpaperTab {
    id: shim
    Component.onCompleted: Deprecation.module(shim, "WallpaperTab", "qs.Modules.DankDash", "qs.Modules.DDash")
}
