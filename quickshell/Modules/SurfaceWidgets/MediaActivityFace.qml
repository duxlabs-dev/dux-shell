pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.DBar.Widgets
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../../Common/LyricLayout.js" as LyricLayout

Item {
    id: root

    required property var mediaModel

    property bool dense: false
    property real contentScale: 1
    property bool isVertical: false
    property real artworkSize: Theme.iconSizeLarge
    readonly property real textGutter: Theme.spacingXS
    readonly property real cavaWidth: 20
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
    property bool lyricsEnabled: false
    readonly property bool lyricsWanted: lyricsEnabled && LyricsService.allowed && !isVertical
    readonly property bool lyricsLive: lyricsWanted && enabled
    readonly property bool lyricActive: {
        if (!lyricsLive)
            return false;
        const controller = LyricsService.controller;
        if (!controller.enabled || !controller.synced)
            return false;
        const parts = controller.lines[controller.activeIndex]?.parts ?? [];
        return parts.some(part => LyricLayout.hasWords(part.x));
    }
    property real maxLength: Infinity
    property var lyricWidths: []
    property real lyricWordWidth: 0
    readonly property real titleFontSize: Theme.fontSizeSmall * root.contentScale
    readonly property real chromeWidth: {
        let width = Theme.spacingS + root.artworkSize + Theme.spacingXS + root.cavaWidth + Theme.spacingXS + root.textGutter * 2 + Theme.spacingXS;
        if (root.clockVisible)
            width += clockText.width + Theme.spacingXS * 2 + Theme.spacingS;
        return width;
    }
    readonly property real lyricWidth: LyricsService.controller.synced ? LyricLayout.pageWidth(root.lyricWidths, root.maxLength - root.chromeWidth, root.minTextWidth, root.lyricWordWidth / 2) : 0
    readonly property real naturalTextWidth: root.lyricWidth > 0 ? root.lyricWidth : Math.max(root.minTextWidth, titleMetrics.width, root.dense ? 0 : artistMetrics.width)
    readonly property real measuredWidth: root.chromeWidth + root.naturalTextWidth

    onLyricsWantedChanged: measureLyrics()

    function measureLyrics() {
        if (!root.lyricsWanted && root.lyricWidths.length === 0)
            return;
        const widths = [];
        let words = 0;
        for (const line of root.lyricsWanted ? LyricsService.controller.lines : []) {
            for (const part of line.parts) {
                if (part.background || !LyricLayout.hasWords(part.x))
                    continue;
                lyricMetrics.text = part.x.replace(/\s+/g, " ").trim();
                widths.push(lyricMetrics.width);
                words += lyricMetrics.text.split(" ").length;
            }
        }
        lyricMetrics.text = "";
        root.lyricWordWidth = words > 0 ? widths.reduce((sum, width) => sum + width, 0) / words : 0;
        root.lyricWidths = widths;
    }

    implicitWidth: isVertical ? artworkSize + verticalPad * 2 : measuredWidth
    implicitHeight: isVertical ? verticalFace.implicitHeight + verticalPad * 2 : artworkSize
    readonly property bool clockHovered: enabled && visible && ((clockArea.visible && clockArea.containsMouse) || (verticalClockArea.visible && verticalClockArea.containsMouse))
    signal clockClicked

    StyledTextMetrics {
        id: titleMetrics

        font.pixelSize: root.titleFontSize
        font.weight: Theme.fontWeightMedium
        text: root.mediaModel.title
    }

    StyledTextMetrics {
        id: lyricMetrics

        font.pixelSize: root.titleFontSize
        font.weight: Theme.fontWeightMedium
        onFontChanged: root.measureLyrics()
    }

    Connections {
        target: LyricsService.controller

        function onLinesChanged() {
            root.measureLyrics();
        }
    }

    StyledTextMetrics {
        id: artistMetrics

        font.pixelSize: Theme.fontSizeXSmall * root.contentScale
        text: root.dense ? "" : root.mediaModel.artist
    }

    LyricsSubscription {
        active: root.lyricsLive && root.mediaModel.available
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
        visible: !root.isVertical
        width: root.artworkSize
        height: width
        artUrl: root.mediaModel.artUrl
    }

    Row {
        visible: !root.isVertical
        anchors {
            left: artwork.right
            leftMargin: Theme.spacingXS
            right: root.clockVisible ? rightActivity.left : parent.right
            rightMargin: Theme.spacingXS
            verticalCenter: parent.verticalCenter
        }
        height: root.artworkSize
        spacing: Theme.spacingXS

        AudioVisualization {
            anchors.verticalCenter: parent.verticalCenter
            width: root.cavaWidth
            height: parent.height
            maxBarHeight: Math.max(3, height - 2)
            idleIconName: "graphic_eq"
        }

        Column {
            width: parent.width - root.cavaWidth - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            ScrollingText {
                id: titleText

                x: root.textGutter
                width: parent.width - root.textGutter * 2
                visible: !root.lyricActive
                text: root.mediaModel.title
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall * root.contentScale
                font.weight: Theme.fontWeightMedium
                active: root.enabled && root.mediaModel.playing
                holdStartMs: 1600
                holdEndMs: 1200
                pxPerMs: 1 / 62.5
                overscroll: root.textGutter
            }

            MediaLyricLine {
                x: root.textGutter
                width: parent.width - root.textGutter * 2
                height: titleText.height
                visible: root.lyricActive
                controller: LyricsService.controller
                color: Theme.surfaceText
                font.pixelSize: titleText.font.pixelSize
                font.weight: titleText.font.weight
                live: root.enabled
            }

            StyledText {
                x: root.textGutter
                width: parent.width - root.textGutter * 2
                visible: !root.dense
                text: root.mediaModel.artist
                color: Theme.surfaceTextSecondary
                font.pixelSize: Theme.fontSizeXSmall * root.contentScale
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
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
                text: root.timeText
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
        spacing: Theme.spacingXS

        MediaArtwork {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.verticalArtworkSize
            height: width
            artUrl: root.mediaModel.artUrl
        }

        AudioVisualization {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.verticalArtworkSize
            height: root.cavaWidth
            maxBarHeight: Math.max(3, height - 2)
            idleIconName: "graphic_eq"
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
                    text: root.hourText
                    reserveText: "00"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall * root.contentScale
                    font.weight: Theme.fontWeightMedium
                }

                NumericText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.minuteText
                    reserveText: "00"
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
