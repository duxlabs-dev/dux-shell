import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.DDash
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../utils/widgets.js" as WidgetUtils

Item {
    id: root

    property var widgetData: ({})
    property var widgetDef: null
    property var host: null
    property bool live: true
    property bool interactive: true
    property real columns: 2
    property real rows: 2
    property bool compact: false

    signal optionChanged(string key, var value)

    readonly property bool wide: width >= height * 2
    readonly property bool background: widgetData?.background === true
    readonly property bool tall: height >= CcMetrics.gridRowUnit * 2
    readonly property real inset: background ? (tall ? CcMetrics.tallTilePadding : CcMetrics.tilePadding) : 0
    readonly property real avatarSide: Math.min(width, height) - inset * 2
    readonly property string shape: widgetData?.shape ?? WidgetUtils.USER_SHAPES[0]
    readonly property bool editMode: host?.editMode ?? false
    readonly property bool tapToClose: interactive && (host?.tapToClose ?? false)
    readonly property Item passthrough: shapeButton
    readonly property real bodyRadius: {
        if (!background)
            return Theme.fullRadius(avatarSide, avatarSide);
        return tall ? Math.min(CcMetrics.tallTileRadius, width / 2, height / 2) : CcMetrics.pillRadius(width, height);
    }
    readonly property real fallbackGlyphRatio: 0.5
    readonly property string avatarSource: PortalService.profileImageUrl
    readonly property bool hasImage: picture.status === Image.Ready

    width: parent?.width ?? 0
    height: parent?.height ?? 0
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true
    Accessible.role: Accessible.StaticText
    Accessible.name: UserInfoService.fullName || UserInfoService.username

    Rectangle {
        anchors.fill: parent
        radius: root.bodyRadius
        color: CcMetrics.tileInactiveColor
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        visible: root.background
    }

    UserIdentity {
        anchors.fill: parent
        anchors.margins: root.inset
        visible: root.wide
        live: root.live && root.wide
        options: DashRegistry.resolvedOptions("user", root.widgetData)
        avatarSize: height
        textGap: Theme.spacingM
        stacked: root.rows >= 2
        contentColor: Theme.onSurface
        mutedColor: Theme.onSurfaceVariant
    }

    Item {
        id: avatar

        anchors.centerIn: parent
        width: root.avatarSide
        height: root.avatarSide
        visible: !root.wide

        DMaterialShape {
            anchors.fill: parent
            shape: root.shape
            color: Theme.primaryContainer
            visible: !root.hasImage
        }

        DIcon {
            anchors.centerIn: parent
            name: "person"
            size: Math.round(root.avatarSide * root.fallbackGlyphRatio)
            color: Theme.onPrimaryContainer
            filled: true
            visible: !root.hasImage
        }

        Item {
            id: avatarMask

            anchors.fill: parent
            layer.enabled: root.hasImage
            visible: false

            DMaterialShape {
                anchors.fill: parent
                shape: root.shape
            }
        }

        Image {
            id: picture

            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
            retainWhileLoading: true
            visible: root.hasImage
            sourceSize.width: Math.max(1, Math.ceil(width * Screen.devicePixelRatio))
            sourceSize.height: Math.max(1, Math.ceil(height * Screen.devicePixelRatio))
            source: avatar.visible ? root.avatarSource : ""
            layer.enabled: root.hasImage
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: avatarMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
        }
    }

    StyledButton {
        objectName: "userCloseButton"
        anchors.fill: parent
        visible: root.tapToClose
        radius: root.bodyRadius
        Accessible.name: I18n.tr("Close")
        onClicked: root.host?.closeRequested()

        FocusRing {
            visible: parent.visualFocus
        }

        StateLayer {
            control: parent
            cornerRadius: root.bodyRadius
        }
    }

    StyledButton {
        objectName: "userAvatarButton"
        x: !root.wide ? (root.width - width) / 2 : I18n.isRtl ? root.width - root.inset - width : root.inset
        y: (root.height - height) / 2
        width: root.avatarSide
        height: root.avatarSide
        radius: Theme.fullRadius(width, height)
        visible: root.interactive
        Accessible.name: I18n.tr("Users & accounts", "settings sidebar category")
        onClicked: root.host?.accountsRequested()

        FocusRing {
            visible: parent.visualFocus
        }

        StateLayer {
            control: parent
            cornerRadius: parent.radius
            tooltipText: parent.Accessible.name
        }
    }

    DActionButton {
        id: shapeButton

        anchors.bottom: avatar.bottom
        anchors.left: avatar.left
        buttonSize: CcMetrics.shapeButtonSize
        iconSize: Theme.iconSizeSmall
        iconName: "shuffle"
        iconColor: Theme.onSurface
        backgroundColor: Theme.chipSurfaceNested
        Accessible.name: I18n.tr("Shuffle")
        visible: root.editMode && avatar.visible
        onClicked: root.optionChanged("shape", WidgetUtils.nextUserShape(root.shape))
    }
}
