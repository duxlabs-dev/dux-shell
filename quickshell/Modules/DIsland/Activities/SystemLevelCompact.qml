pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.OSD
import qs.DCommon.Widgets

Item {
    id: root

    required property var systemModel
    property bool isVertical: false
    property real iconSize: 36

    readonly property int maximum: Math.max(root.systemModel.minimum + 1, Math.round(root.systemModel.maximum))
    readonly property real fillRatio: Math.max(0, Math.min(1, (root.systemModel.value - root.systemModel.minimum) / Math.max(1, root.maximum - root.systemModel.minimum)))
    // DSlider's own metrics, transposed, so the two orientations read as the same control.
    readonly property real trackThickness: 12
    readonly property real handleThickness: 4
    readonly property real handleBreadth: 20
    readonly property real fillHandleGap: 3

    function trackFraction(localY) {
        if (track.travel <= 0)
            return 0;
        return 1 - (localY - root.handleThickness / 2) / track.travel;
    }

    function applyFraction(fraction) {
        const clamped = Math.max(0, Math.min(1, fraction));
        const level = root.systemModel.minimum + clamped * (root.maximum - root.systemModel.minimum);
        root.systemModel.setRatio(level / Math.max(1, root.maximum));
    }

    OsdLevelRow {
        anchors.fill: parent
        visible: !root.isVertical
        iconName: root.systemModel.iconName
        tonalIcon: false
        iconInteractive: root.systemModel.mutable
        iconLabel: root.systemModel.muted ? I18n.tr("Unmute") : I18n.tr("Mute")
        value: Math.round(root.systemModel.value)
        minimum: root.systemModel.minimum
        maximum: root.maximum
        unit: root.systemModel.unit
        displayText: root.systemModel.displayValue
        sliderEnabled: root.systemModel.available
        onIconClicked: root.systemModel.toggleMute()
        onSliderValueChanged: newValue => root.systemModel.setRatio(newValue / Math.max(1, root.maximum))
    }

    // DSlider is horizontal only, so a side strip gets its own stacked track.
    Item {
        id: verticalFace

        anchors.fill: parent
        anchors.topMargin: Theme.spacingS
        anchors.bottomMargin: Theme.spacingS
        visible: root.isVertical

        DIcon {
            id: levelIcon

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            name: root.systemModel.iconName
            size: Math.min(Theme.iconSize, root.iconSize)
            color: root.systemModel.mutable ? Theme.surfaceText : Theme.primary

            MouseArea {
                anchors.fill: parent
                enabled: root.systemModel.mutable
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.systemModel.toggleMute()
            }
        }

        StyledText {
            id: levelLabel

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: root.systemModel.displayValue.length > 0 ? root.systemModel.displayValue : (Math.round(root.systemModel.value) + root.systemModel.unit)
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
        }

        Item {
            id: track

            readonly property real travel: Math.max(0, height - root.handleThickness)
            readonly property real handleOffset: track.travel * root.fillRatio

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: levelIcon.bottom
            anchors.topMargin: Theme.spacingS
            anchors.bottom: levelLabel.top
            anchors.bottomMargin: Theme.spacingS
            width: root.handleBreadth

            Rectangle {
                id: groove

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.trackThickness
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.outline, Theme.foregroundAlpha)

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.max(0, Math.min(parent.height, track.handleOffset - root.fillHandleGap))
                    radius: Theme.cornerRadius
                    topLeftRadius: 0
                    topRightRadius: 0
                    color: root.systemModel.available ? Theme.primary : Theme.withAlpha(Theme.surfaceText, 0.12)
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: track.travel - track.handleOffset
                width: root.handleBreadth
                height: root.handleThickness
                radius: Theme.cornerRadius
                color: root.systemModel.available ? Theme.primary : Theme.withAlpha(Theme.surfaceText, 0.12)
            }

            MouseArea {
                id: trackArea

                readonly property real grabPad: Theme.spacingS

                anchors.fill: parent
                anchors.margins: -grabPad
                enabled: root.systemModel.available
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: mouse => root.applyFraction(root.trackFraction(mouse.y - grabPad))
                onPositionChanged: mouse => {
                    if (pressed)
                        root.applyFraction(root.trackFraction(mouse.y - grabPad));
                }
            }
        }
    }
}
