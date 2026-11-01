pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.DBar.Widgets
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    required property var mediaModel

    property bool dense: false
    property bool titleVisible: true
    property bool visualizerIdle: false
    property bool artworkCircular: true
    property bool artworkVisible: true
    property bool visualizerEnabled: true
    property real titleMaxWidth: 220
    readonly property bool visualizerVisible: root.visualizerEnabled && (root.mediaModel.playing || root.visualizerIdle)
    property real contentScale: 1
    property bool isVertical: false
    property real artworkSize: Theme.iconSizeLarge
    readonly property real textGutter: Theme.spacingXS
    readonly property real cavaWidth: 20
    readonly property real artworkWaveGap: Theme.spacingM
    readonly property real minTextWidth: 48
    readonly property real clockLeadPad: Theme.spacingXS / 2
    readonly property real clockTrailPad: Theme.spacingS
    readonly property real clockPillHeight: root.dense ? Math.max(22, root.artworkSize - Theme.spacingXS) : 32
    // A fully rounded side strip crowds square content, so the vertical face insets on both axes.
    readonly property real verticalPad: Theme.spacingS
    readonly property real verticalArtworkSize: Math.max(12, Math.min(root.artworkSize, root.width - root.verticalPad * 2))
    readonly property string timeText: systemClock.date.toLocaleTimeString(I18n.locale(), SettingsData.getEffectiveTimeFormat())
    readonly property string hourText: {
        const hours = systemClock.date.getHours();
        if (SettingsData.use24HourClock)
            return String(hours).padStart(2, "0");
        return String(hours === 0 ? 12 : (hours > 12 ? hours - 12 : hours)).padStart(2, "0");
    }
    readonly property string minuteText: String(systemClock.date.getMinutes()).padStart(2, "0")
    property bool clockVisible: false
    readonly property real naturalTextWidth: Math.min(Math.max(root.minTextWidth, root.titleMaxWidth), Math.max(root.minTextWidth, titleMetrics.width, root.dense ? 0 : artistMetrics.width)) + root.textGutter * 2
    readonly property real measuredWidth: {
        let width = Theme.spacingS + (root.artworkVisible ? root.artworkSize : 0) + (horizontalWave.retained ? (root.artworkVisible ? root.artworkWaveGap : 0) + root.cavaWidth : 0) + Theme.spacingXS + (titleSlot.retained ? root.naturalTextWidth + Theme.spacingXS : 0);
        if (root.clockVisible)
            width += clockText.width + Theme.spacingXS * 2 + Theme.spacingS;
        return width;
    }

    implicitWidth: isVertical ? artworkSize + verticalPad * 2 : measuredWidth
    implicitHeight: isVertical ? verticalFace.implicitHeight + verticalPad * 2 : artworkSize
    readonly property bool clockHovered: enabled && visible && ((clockArea.visible && clockArea.containsMouse) || (verticalClockArea.visible && verticalClockArea.containsMouse))
    signal clockClicked
    signal mediaClicked

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.mediaClicked()
    }

    StyledTextMetrics {
        id: titleMetrics

        font.pixelSize: Theme.fontSizeSmall * root.contentScale
        font.weight: Theme.fontWeightMedium
        text: root.mediaModel.title
    }

    StyledTextMetrics {
        id: artistMetrics

        font.pixelSize: Math.max(9, Theme.fontSizeSmall - 2) * root.contentScale
        text: root.dense ? "" : root.mediaModel.artist
    }

    SystemClock {
        id: systemClock

        enabled: root.enabled && root.visible && root.clockVisible
        precision: SettingsData.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    MediaArtwork {
        id: artwork

        anchors {
            left: parent.left
            leftMargin: Theme.spacingS
            verticalCenter: parent.verticalCenter
        }
        visible: !root.isVertical && root.artworkVisible
        width: root.artworkVisible ? root.artworkSize : 0
        height: width
        cornerRadius: root.artworkCircular ? Math.min(width, height) / 2 : 0
        artUrl: root.mediaModel.artUrl
    }

    Row {
        visible: !root.isVertical
        anchors {
            left: artwork.right
            leftMargin: root.artworkVisible ? root.artworkWaveGap : 0
            right: root.clockVisible ? rightActivity.left : parent.right
            rightMargin: Theme.spacingXS
            verticalCenter: parent.verticalCenter
        }
        height: root.artworkSize
        spacing: Theme.spacingXS

        FadePresence {
            id: horizontalWave
            anchors.verticalCenter: parent.verticalCenter
            shown: root.visualizerVisible
            width: root.cavaWidth
            height: parent.height

            AudioVisualization {
                anchors.fill: parent
                maxBarHeight: Math.max(3, height - 2)
                idleIconName: "graphic_eq"
            }
        }

        FadePresence {
            id: titleSlot
            duration: Theme.mediumDuration
            clip: true
            shown: root.titleVisible
            width: Math.max(0, parent.width - (horizontalWave.retained ? root.cavaWidth + parent.spacing : 0))
            height: trackText.implicitHeight
            anchors.verticalCenter: parent.verticalCenter

            Column {
                id: trackText
                width: parent.width
                spacing: 0

                ScrollingText {
                    x: root.textGutter
                    width: parent.width - root.textGutter * 2
                    text: root.mediaModel.title
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall * root.contentScale
                    font.weight: Theme.fontWeightMedium
                    active: root.enabled && root.mediaModel.playing && titleSlot.shown
                    holdStartMs: 1600
                    holdEndMs: 1200
                    pxPerMs: 1 / 62.5
                    overscroll: root.textGutter
                }

                StyledText {
                    x: root.textGutter
                    width: parent.width - root.textGutter * 2
                    visible: !root.dense
                    text: root.mediaModel.artist
                    color: Theme.surfaceTextSecondary
                    font.pixelSize: Math.max(9, Theme.fontSizeSmall - 2) * root.contentScale
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }
        }
    }

    Item {
        id: rightActivity

        anchors {
            right: parent.right
            rightMargin: Theme.spacingS
            verticalCenter: parent.verticalCenter
        }
        width: root.clockVisible ? (clockText.width + Theme.spacingXS * 2) : 0
        height: root.clockPillHeight
        visible: root.clockVisible && !root.isVertical

        Rectangle {
            anchors.fill: parent
            radius: Math.min(Theme.cornerRadiusFull, height / 2)
            color: clockArea.containsMouse ? Theme.surfaceTextHover : "transparent"

            NumericText {
                id: clockText

                anchors.centerIn: parent
                isMonospace: false
                text: root.timeText
                reserveText: root.timeText.replace(/\d/g, "0")
                width: Math.ceil(Math.max(implicitWidth, reservedWidth))
                horizontalAlignment: Text.AlignHCenter
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall * root.contentScale
                font.weight: Theme.fontWeightMedium
            }

            MouseArea {
                id: clockArea

                anchors.verticalCenter: parent.verticalCenter
                x: -root.clockLeadPad
                width: parent.width + root.clockLeadPad + root.clockTrailPad
                height: root.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clockClicked()
            }
        }
    }

    // A side strip has no room for track text, so the vertical face is artwork over the meter.
    Column {
        id: verticalFace

        anchors.centerIn: parent
        visible: root.isVertical
        spacing: root.artworkWaveGap

        MediaArtwork {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.artworkVisible
            width: root.verticalArtworkSize
            height: width
            cornerRadius: root.artworkCircular ? Math.min(width, height) / 2 : 0
            artUrl: root.mediaModel.artUrl
        }

        FadePresence {
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.visualizerVisible
            width: root.verticalArtworkSize
            height: root.cavaWidth

            AudioVisualization {
                anchors.fill: parent
                maxBarHeight: Math.max(3, height - 2)
                idleIconName: "graphic_eq"
            }
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.clockVisible
            width: verticalClock.width
            height: verticalClock.height

            // A side strip cannot fit "10:42 PM" on one line, so the hour sits over the minute.
            Column {
                id: verticalClock

                spacing: 0

                NumericText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    isMonospace: false
                    text: root.hourText
                    reserveText: "00"
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall * root.contentScale
                    font.weight: Theme.fontWeightMedium
                }

                NumericText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    isMonospace: false
                    text: root.minuteText
                    reserveText: "00"
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.surfaceTextMedium
                    font.pixelSize: Theme.fontSizeSmall * root.contentScale
                    font.weight: Theme.fontWeightMedium
                }
            }

            MouseArea {
                id: verticalClockArea
                anchors.centerIn: parent
                width: root.width
                height: parent.height + Theme.spacingXS
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clockClicked()
            }
        }
    }
}
