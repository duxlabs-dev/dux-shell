import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    property bool live: Window.window?.visible ?? false
    property var options: ({})
    property real avatarSize: Theme.buttonHeightM
    property real textGap: Theme.spacingM
    property bool narrow: false
    property bool tall: false
    property bool stacked: false
    property color contentColor: Theme.surfaceText
    property color mutedColor: Theme.surfaceVariantText
    property color badgeColor: Theme.primaryContainer
    property color badgeContentColor: Theme.onPrimaryContainer
    property color ringColor: Theme.avatarRingColor

    readonly property real avatarDiameter: Math.min(avatarSize, width, height)
    readonly property real badgeSize: Math.round(Math.max(Theme.iconSizeSmall + Theme.spacingXS, avatarDiameter / 3))
    readonly property real badgeOverhang: 0.15
    readonly property real badgeIconRatio: 0.6
    readonly property bool showHostname: options.hostname !== false && UserInfoService.hostname !== ""
    readonly property bool showCompositor: options.compositor !== false && compositorName !== ""
    readonly property bool showUptime: options.uptime !== false
    readonly property bool showBadge: options.badge !== false
    readonly property string compositorName: CompositorService.displayName
    readonly property string detailsText: [showHostname ? UserInfoService.hostname : "", showCompositor ? compositorName : ""].filter(text => text !== "").join(" · ")
    readonly property string uptimeText: {
        const prefix = I18n.tr("up", "uptime prefix, e.g. 'up 4h 2m'");
        return DgopService.shortUptime ? prefix + DgopService.shortUptime.slice(2) : prefix;
    }
    readonly property string avatarSource: PortalService.profileImageUrl

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true
    Accessible.role: Accessible.StaticText
    Accessible.name: [UserInfoService.username, detailsText, showUptime && DgopService.shortUptime !== "" ? uptimeText : ""].filter(text => text !== "").join(", ")

    Ref {
        service: DgopService
        modules: ["system"]
        active: root.live && root.showUptime
    }

    Item {
        id: avatarBox

        x: root.narrow ? (parent.width - width) / 2 : I18n.isRtl ? parent.width - width : 0
        anchors.verticalCenter: parent.verticalCenter
        width: root.avatarDiameter
        height: root.avatarDiameter

        DCircularImage {
            anchors.fill: parent
            imageSource: root.avatarSource
            fallbackIcon: "material:person"
            ringWidth: Theme.avatarRingWidth
            ringColor: root.ringColor
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -root.badgeSize * root.badgeOverhang
            anchors.bottomMargin: -root.badgeSize * root.badgeOverhang
            width: root.badgeSize
            height: root.badgeSize
            radius: Theme.fullRadius(width, height)
            color: root.badgeColor
            border.width: Theme.avatarRingWidth
            border.color: root.ringColor
            visible: root.showBadge

            SystemLogo {
                anchors.centerIn: parent
                width: Math.round(parent.width * root.badgeIconRatio)
                height: width
                colorOverride: String(root.badgeContentColor)
            }
        }
    }

    Column {
        anchors.left: avatarBox.right
        anchors.leftMargin: root.textGap
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.narrow
        spacing: root.stacked ? Theme.spacingXS : 0

        StyledText {
            width: parent.width
            text: !root.stacked && root.showHostname ? UserInfoService.username + " @ " + UserInfoService.hostname : UserInfoService.username
            font.pixelSize: root.stacked || root.tall ? Theme.fontSizeXLarge : Theme.fontSizeLarge
            font.weight: Theme.fontWeightMedium
            color: root.contentColor
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
            maximumLineCount: 1
            Accessible.ignored: true
        }

        StyledText {
            width: parent.width
            visible: root.stacked && text !== ""
            text: root.detailsText
            font.pixelSize: Theme.fontSizeSmall
            color: root.mutedColor
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
            Accessible.ignored: true
        }

        Flow {
            width: parent.width
            spacing: root.stacked ? 0 : Theme.spacingS

            Row {
                id: compositorDetails
                spacing: Theme.spacingXS
                visible: root.showCompositor && !root.stacked

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "select_window"
                    size: Theme.iconSizeSmall
                    color: root.mutedColor
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.compositorName
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.mutedColor
                    Accessible.ignored: true
                }
            }

            Row {
                readonly property real remaining: parent.width - (compositorDetails.visible ? compositorDetails.width + parent.spacing : 0)

                width: root.tall && !root.stacked ? Math.min(uptimeIcon.width + spacing + uptimeLabel.implicitWidth, parent.width) : Math.max(0, remaining)
                spacing: Theme.spacingXS
                visible: root.showUptime
                opacity: DgopService.shortUptime !== "" ? 1 : 0

                DIcon {
                    id: uptimeIcon
                    anchors.verticalCenter: parent.verticalCenter
                    name: "schedule"
                    size: Theme.iconSizeSmall
                    color: root.mutedColor
                }

                StyledText {
                    id: uptimeLabel

                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - uptimeIcon.width - parent.spacing)
                    text: root.uptimeText
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.mutedColor
                    wrapMode: Text.NoWrap
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }
            }
        }
    }
}
