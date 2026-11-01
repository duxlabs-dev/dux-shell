import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// One live window, already scaled to the desk; geometry eases so niri's moves read as motion.
Item {
    id: root

    property string appId: ""
    property string title: ""
    property bool active: false
    property real radius: 0
    property real ringWidth: 0
    property color ringColor: Theme.primary
    property bool borderOn: false
    property real borderWidth: 0
    property color borderColor: Theme.primary
    property color borderInactiveColor: Theme.outline
    property bool blurOn: false
    property bool shadowOn: false

    readonly property bool animate: Theme.mediumDuration > 0 && !SettingsData.reduceMotion
    readonly property color body: Theme.isLightMode ? Theme.surface : Theme.surfaceContainerHigh
    readonly property real headerHeight: Math.min(height * 0.3, Theme.fontSizeSmall + Theme.spacingS)
    readonly property string iconSource: appId ? Paths.getAppIcon(appId, DesktopEntries.heuristicLookup(Paths.moddedAppId(appId))) : ""

    Behavior on x {
        enabled: root.animate
        NumberAnimation {
            duration: Theme.mediumDuration
            easing.type: Theme.standardEasing
        }
    }
    Behavior on y {
        enabled: root.animate
        NumberAnimation {
            duration: Theme.mediumDuration
            easing.type: Theme.standardEasing
        }
    }
    Behavior on width {
        enabled: root.animate
        NumberAnimation {
            duration: Theme.mediumDuration
            easing.type: Theme.standardEasing
        }
    }
    Behavior on height {
        enabled: root.animate
        NumberAnimation {
            duration: Theme.mediumDuration
            easing.type: Theme.standardEasing
        }
    }

    ElevationShadow {
        anchors.fill: parent
        visible: root.shadowOn
        shadowEnabled: visible
        targetRadius: root.radius
        targetColor: "transparent"
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -root.ringWidth
        radius: root.radius + root.ringWidth
        color: root.ringColor
        visible: root.active && root.ringWidth > 0
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.withAlpha(root.body, root.blurOn ? 0.72 : 1)
        // A hairline keeps light windows apart from a light wallpaper when niri draws no border
        border.width: root.borderOn ? root.borderWidth : Theme.outlineWidth
        border.color: !root.borderOn ? Theme.outlineVariant : root.active ? root.borderColor : root.borderInactiveColor

        Rectangle {
            id: header
            width: parent.width
            height: root.headerHeight
            color: Theme.surfaceContainerHighest

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingXS
                anchors.rightMargin: Theme.spacingXS
                spacing: Theme.spacingXS

                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: Math.max(0, root.headerHeight - Theme.spacingXS)
                    source: root.iconSource
                    asynchronous: true
                    visible: status === Image.Ready
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - root.headerHeight
                    text: root.title || root.appId
                    font.pixelSize: Math.max(1, Math.min(Theme.fontSizeSmall, root.headerHeight * 0.7))
                    color: root.active ? Theme.surfaceText : Theme.surfaceVariantText
                    elide: Text.ElideRight
                    visible: root.width > Theme.iconSize * 2
                }
            }
        }

        IconImage {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.headerHeight / 2
            implicitSize: Math.min(Theme.iconSizeLarge, root.width * 0.4, (root.height - root.headerHeight) * 0.5)
            source: root.iconSource
            asynchronous: true
            opacity: root.active ? 0.9 : 0.5
            visible: status === Image.Ready
        }
    }
}
