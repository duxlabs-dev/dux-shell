import QtQuick
import "../../../../../Common/niri/sections/look.js" as Look
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components

// DMS stores the radius as -1 (follow the theme) or a size in px; 0 is a real size that
// squares every DMS surface. The toggle keeps theme auto as its resting state, the
// slider below only shows once it is on, and an off toggle writes -1, never a stray 0.
NiriRow {
    id: root

    settingKey: "look.radius"
    toggle: false
    tryValue: undefined

    readonly property bool overriding: !Look.radiusAuto(value)

    DToggle {
        anchors.verticalCenter: parent.verticalCenter
        checked: root.overriding
        Accessible.name: root.title
        onToggled: checked => root.write(Look.radiusWrite(checked, Theme.windowRadius))
    }
}
