import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings

Item {
    id: root

    required property var profile
    property bool selected: false
    property bool showCaption: true
    property bool compact: false
    property var targetScreen: null

    readonly property bool hovered: hover.hovered
    readonly property bool isActive: profile.id === ConfigProfileService.activeProfileId

    signal clicked

    implicitHeight: preview.implicitHeight + caption.anchors.topMargin + caption.height
    Accessible.role: Accessible.Button
    Accessible.name: profile.name
    Accessible.description: isActive ? I18n.tr("Active", "config profile picker: badge on the currently applied profile") : ""
    Accessible.selected: selected
    Accessible.focused: selected
    Accessible.onPressAction: root.clicked()

    HoverHandler {
        id: hover
    }

    ProfilePreview {
        id: preview
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        owner: root.profile
        targetScreen: root.targetScreen
        radius: Theme.cornerRadiusXL

        StateLayer {
            stateColor: Theme.primary
            onClicked: root.clicked()
        }
    }

    MouseArea {
        anchors.top: preview.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Rectangle {
        anchors.fill: preview
        radius: preview.radius
        color: "transparent"
        border.width: Theme.outlineWidthFocused
        border.color: Theme.primary
        opacity: root.selected ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }
    }

    Row {
        id: caption
        anchors.top: preview.bottom
        anchors.topMargin: root.compact ? Theme.spacingS : Theme.spacingM
        anchors.horizontalCenter: parent.horizontalCenter
        height: Math.max(nameText.implicitHeight, activeChip.height)
        spacing: Theme.spacingS
        opacity: root.showCaption ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        StyledText {
            id: nameText
            width: Math.min(implicitWidth, root.width - (activeChip.visible ? activeChip.width + caption.spacing : 0))
            anchors.verticalCenter: parent.verticalCenter
            text: root.profile.name ?? ""
            font.pixelSize: root.compact ? Theme.fontSizeMedium : Theme.fontSizeXLarge
            font.weight: Theme.fontWeightMedium
            color: root.selected ? Theme.primary : Theme.surfaceText
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        PluginBadge {
            id: activeChip
            visible: root.isActive
            anchors.verticalCenter: parent.verticalCenter
            iconName: "check"
            label: I18n.tr("Active", "config profile picker: badge on the currently applied profile")
            tone: Theme.onSecondaryContainer
            color: Theme.secondaryContainer
            border.width: 0
        }
    }
}
