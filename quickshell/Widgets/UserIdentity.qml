pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../Common/IconFolders.js" as IconFolders
import "../DCommon/Widgets/MaterialShapes.js" as Shapes

Item {
    id: root

    property bool live: Window.window?.visible ?? false
    property var options: ({})
    property real avatarSize: Theme.buttonHeightM
    property real textGap: Theme.spacingM
    property bool narrow: false
    property bool tall: false
    property bool stacked: false
    // A Material shape name masks the avatar; empty keeps the ringed circle.
    property string shape: ""
    property color contentColor: Theme.surfaceText
    property color mutedColor: Theme.surfaceVariantText
    property color badgeColor: Theme.primaryContainer
    property color badgeContentColor: Theme.onPrimaryContainer
    property color ringColor: Theme.avatarRingColor

    readonly property real avatarDiameter: Math.min(avatarSize, width, height)
    readonly property real badgeSize: Math.round(Math.max(Theme.iconSizeSmall + Theme.spacingXS, avatarDiameter / 3))
    readonly property real badgeOverhang: 0.15
    readonly property real badgeIconRatio: 0.6
    // Names outside the Material catalog are dux-icons tile outlines.
    readonly property string outline: shape === "" || shape in Shapes.catalog ? "" : IconFolders.outlinePath(shape)
    // Fit inside the plain avatar circle so corners never poke out of pill ends.
    readonly property real shapeFit: outline !== "" ? IconFolders.circleFit(shape) : Math.min(1, Shapes.rotationScale(shape))
    readonly property bool showHostname: options.hostname !== false && UserInfoService.hostname !== ""
    readonly property bool showCompositor: options.compositor !== false && compositorName !== ""
    readonly property bool compositorInline: showCompositor && !stacked
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

    component AvatarShape: Shape {
        id: avatarShape

        property color color: Theme.primary

        anchors.centerIn: parent
        width: Math.round(parent.width * root.shapeFit)
        height: width
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            // Both path sources share the 64-unit outline canvas.
            scale: Qt.size(avatarShape.width / 64, avatarShape.height / 64)
            fillColor: avatarShape.color
            strokeColor: "transparent"
            strokeWidth: -1

            PathSvg {
                // A picked avatar shape stays itself under the square Classic style.
                path: root.outline !== "" ? root.outline : Shapes.buildPath(root.shape, 64, 64, false)
            }
        }
    }

    Ref {
        service: DgopService
        modules: ["system"]
        active: root.live && root.showUptime && !root.narrow
    }

    Item {
        id: avatarBox

        x: root.narrow ? (parent.width - width) / 2 : I18n.isRtl ? parent.width - width : 0
        anchors.verticalCenter: parent.verticalCenter
        width: root.avatarDiameter
        height: root.avatarDiameter

        DCircularImage {
            anchors.fill: parent
            visible: root.shape === ""
            imageSource: root.shape === "" ? root.avatarSource : ""
            fallbackIcon: "material:person"
            ringWidth: Theme.avatarRingWidth
            ringColor: root.ringColor
        }

        // Only the mask follows the shape; the picture never reloads on a shape change.
        Loader {
            anchors.fill: parent
            active: root.shape !== ""

            sourceComponent: Item {
                id: shaped

                readonly property bool hasImage: picture.status === Image.Ready

                AvatarShape {
                    color: Theme.primaryContainer
                    visible: !shaped.hasImage
                }

                DIcon {
                    anchors.centerIn: parent
                    name: "person"
                    size: Math.round(parent.width * root.shapeFit / 2)
                    color: Theme.onPrimaryContainer
                    filled: true
                    visible: !shaped.hasImage
                }

                Item {
                    id: avatarMask

                    anchors.fill: parent
                    layer.enabled: shaped.hasImage
                    visible: false

                    AvatarShape {}
                }

                Image {
                    id: picture

                    anchors.fill: parent
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                    retainWhileLoading: true
                    visible: shaped.hasImage
                    sourceSize.width: Math.max(1, Math.ceil(width * Screen.devicePixelRatio))
                    sourceSize.height: Math.max(1, Math.ceil(height * Screen.devicePixelRatio))
                    source: root.avatarSource
                    layer.enabled: shaped.hasImage
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: avatarMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }
                }
            }
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
                visible: root.compositorInline

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
                // Not compositorDetails.visible: that reads false while the surface is hidden and wraps this row until the next layout.
                readonly property real remaining: parent.width - (root.compositorInline ? compositorDetails.width + parent.spacing : 0)

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
