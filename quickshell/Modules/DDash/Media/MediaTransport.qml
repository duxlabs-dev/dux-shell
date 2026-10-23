pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.DDash
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

RowLayout {
    id: root

    required property var player
    required property var presentation
    property real buttonSize: Theme.buttonHeightM

    readonly property var focusTargets: [previousButton, playButton, nextButton]
    readonly property bool hasControls: !!presentation
    readonly property var pressSpring: Theme.springPreset("fast", Theme.expressiveDurations.expressiveFastSpatial)

    spacing: Theme.spacingS
    implicitHeight: root.buttonSize
    height: implicitHeight
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    Keys.onPressed: event => event.accepted = FocusNavigation.handleHorizontalKey(event, focusTargets, false)

    TransportButton {
        id: previousButton
        mediaAction: "previous"
        groupStart: true
        containerColor: MediaAccentService.accentContainer
        contentColor: MediaAccentService.onAccentContainer
    }

    TransportButton {
        id: playButton
        mediaAction: "play"
        size: "m"
        weight: DashMetrics.mediaPlayWidthRatio
        iconSize: Math.round(root.buttonSize * Theme.iconSizeLarge / Theme.buttonHeightM)
        containerColor: MediaAccentService.accentSecondaryContainer
        contentColor: MediaAccentService.onAccentSecondaryContainer
    }

    TransportButton {
        id: nextButton
        mediaAction: "next"
        groupEnd: true
        containerColor: MediaAccentService.accentContainer
        contentColor: MediaAccentService.onAccentContainer
    }

    component TransportButton: MediaTransportButton {
        id: button

        property real weight: 1
        property bool groupStart: false
        property bool groupEnd: false
        readonly property real outerRadius: Theme.fullRadius(width, height)
        readonly property real targetWeight: weight * (pressed ? DashMetrics.mediaTransportPressScale : 1)

        player: root.player
        keepNavigation: true
        Layout.fillWidth: true
        Layout.preferredWidth: Theme.minimumTouchTargetSize * widthSpring.value
        Layout.minimumWidth: Theme.iconSizeMedium + Theme.spacingXS * 2
        Layout.alignment: Qt.AlignVCenter
        round: false
        buttonSize: root.buttonSize
        iconSize: Math.round(root.buttonSize * Theme.iconSize / Theme.buttonHeightM)
        iconFilled: true
        radius: Theme.buttonRadius(width, height, buttonSize, pressed, true)
        variant: "tonal"
        containerColor: MediaAccentService.accentSecondaryContainer
        contentColor: MediaAccentService.onAccentSecondaryContainer

        onTargetWeightChanged: widthSpring.retarget(targetWeight)

        SpringMotion {
            id: widthSpring
            enabled: root.visible && root.player.live && !Theme.springMotionDisabled
            stiffness: root.pressSpring.stiffness
            damping: root.pressSpring.damping
            Component.onCompleted: snapTo(button.targetWeight)
        }
    }
}
