import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.DDash

Card {
    id: root

    property bool live: Window.window?.visible ?? false
    readonly property bool narrow: width < DashMetrics.gridRowUnit * 2
    readonly property bool tall: height >= DashMetrics.gridRowUnit * 2

    entryId: "user"

    UserIdentity {
        anchors.fill: parent
        live: root.live
        options: root.options
        narrow: root.narrow
        tall: root.tall
        avatarSize: root.tall ? DashMetrics.avatarSizeHero : DashMetrics.avatarSize
        contentColor: root.contentColor
        mutedColor: root.mutedColor
        badgeColor: root.tinted ? root.contentColor : Theme.primaryContainer
        badgeContentColor: root.tinted ? root.containerColor : Theme.onPrimaryContainer
        ringColor: root.tinted ? root.containerColor : Theme.avatarRingColor
    }
}
