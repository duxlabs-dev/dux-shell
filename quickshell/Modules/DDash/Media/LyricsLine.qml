pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash
import "LyricsModel.js" as LyricsModel

Item {
    id: root

    required property var item
    required property int index
    required property var controller
    // The playback time for the lines around the centre, -1 ahead of it and Infinity behind it.
    property real clock: -1
    property bool promoted: false
    property bool synced: true
    property bool following: true
    property bool playing: false
    property bool sweep: true
    property bool animationsEnabled: true
    property real leadFontSize: Theme.fontSizeXLarge
    property FontMetrics leadMetrics: null
    property FontMetrics backgroundMetrics: null
    property real breakSize: Theme.iconSizeLarge
    property real shift: 0
    // A line that playback moves on from keeps its highlight a moment before it dims.
    property bool lingering: false
    // A line left by a seek turns inactive at once and stays unsung until the dimming hides its real fill.
    property bool holding: false
    property real ringProgress: 0

    readonly property bool isBreak: item.kind === "break"
    readonly property bool isPlain: item.kind === "plain"
    readonly property bool lit: promoted || lingering
    readonly property real shownClock: holding ? -1 : clock
    readonly property real breakProgress: isBreak ? Math.max(0, Math.min(1, (clock - item.t) / (item.e - item.t))) : 0
    // Lines that wait or are done rest in one translucent colour, a single fade instead of a colour and
    // an opacity that move at different paces. While browsing every line stays fully visible.
    readonly property color restingColor: Theme.withAlpha(Theme.onSurfaceVariant, synced && following ? DashMetrics.lyricsLineInactiveAlpha : 1)
    readonly property bool shrunk: synced && following && !isPlain && !promoted
    // Every part is wrapped here, so the height is known when the row is created. A height that
    // settles a frame later moves the rows around it while the view scrolls past.
    readonly property var layouts: {
        if (isBreak || isPlain || width <= 0 || !leadMetrics || !backgroundMetrics)
            return [];
        leadMetrics.font;
        backgroundMetrics.font;
        return LyricsModel.partLayouts(item.group.parts, width, leadMetrics, backgroundMetrics, Theme.spacingXS);
    }

    signal activated

    // The push starts from where the line was, so the view can snap and the lines catch up.
    function push(delta, delay) {
        pushMotion.stop();
        shift += delta;
        pushPause.duration = delay;
        pushMotion.start();
    }

    function settle() {
        pushMotion.stop();
        shift = 0;
    }

    onPromotedChanged: {
        lingerTimer.stop();
        fadeTimer.stop();
        lingering = !promoted && !controller.jumping;
        holding = !promoted && controller.jumping;
        if (holding) {
            ringProgress = 0;
            fadeTimer.start();
        } else if (lingering) {
            lingerTimer.start();
        }
    }

    implicitHeight: isPlain ? plainLoader.height + Theme.spacingS * 2 : LyricsModel.rowHeight(item, layouts, breakSize, Theme.spacingS, Theme.spacingXS)
    height: implicitHeight
    Accessible.role: Accessible.StaticText
    Accessible.name: isBreak ? I18n.tr("Instrumental", "Track has no lyrics because it is instrumental") : isPlain ? item.text : item.group.x
    ListView.onPooled: settle()
    ListView.onReused: {
        settle();
        lingerTimer.stop();
        fadeTimer.stop();
        lingering = false;
        holding = false;
        ringProgress = 0;
    }

    // Only the active break shows its progress, every other one rests empty like an unsung line. A
    // break that playback moves on from keeps its arc while it fades and empties once it is dim.
    Binding {
        target: root
        property: "ringProgress"
        value: root.breakProgress
        when: root.isBreak && root.lit
        restoreMode: Binding.RestoreNone
    }

    Timer {
        id: lingerTimer
        interval: DashMetrics.lyricsLineLinger
        onTriggered: {
            root.lingering = false;
            fadeTimer.start();
        }
    }

    Timer {
        id: fadeTimer
        interval: DashMetrics.lyricsLineFadeDuration
        onTriggered: {
            root.holding = false;
            root.ringProgress = 0;
        }
    }

    SequentialAnimation {
        id: pushMotion

        PauseAnimation {
            id: pushPause
        }

        NumberAnimation {
            target: root
            property: "shift"
            to: 0
            duration: DashMetrics.lyricsTrackMoveDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: DashMetrics.lyricsTrackCurve
        }
    }

    Item {
        id: face

        width: root.width
        height: root.height
        transform: Translate {
            y: root.shift
        }

        Repeater {
            model: root.layouts

            LyricsPart {
                required property var modelData

                y: Theme.spacingS + modelData.y
                width: face.width
                layout: modelData
            }
        }

        Loader {
            id: breakLoader

            y: Theme.spacingS
            width: parent.width
            height: root.breakSize
            active: root.isBreak
            scale: root.shrunk ? DashMetrics.lyricsLineInactiveScale : 1

            Behavior on scale {
                enabled: root.animationsEnabled
                NumberAnimation {
                    duration: DashMetrics.lyricsLineScaleDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: DashMetrics.lyricsTrackCurve
                }
            }

            sourceComponent: DCircularWavyProgress {
                progress: root.ringProgress
                color: root.lit ? MediaAccentService.lyricsLead : root.restingColor
                trackColor: root.lit && root.following ? Theme.withAlpha(MediaAccentService.lyricsLead, DashMetrics.lyricsRestAlpha) : root.restingColor
                waveSpeed: root.promoted && root.playing && root.animationsEnabled ? wavelength : 0

                Behavior on color {
                    enabled: root.animationsEnabled
                    ColorAnimation {
                        duration: DashMetrics.lyricsLineFadeDuration
                    }
                }

                Behavior on trackColor {
                    enabled: root.animationsEnabled
                    ColorAnimation {
                        duration: DashMetrics.lyricsLineFadeDuration
                    }
                }
            }
        }

        Loader {
            id: plainLoader

            y: Theme.spacingS
            width: parent.width
            height: item?.implicitHeight ?? 0
            active: root.isPlain

            sourceComponent: StyledText {
                text: root.item.text || " "
                color: Theme.onSurfaceVariant
                font.pixelSize: root.leadFontSize
                font.weight: Theme.fontWeightMedium
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                Accessible.ignored: true
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !root.isPlain && root.controller.canSeekLines
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activated()
        }
    }

    component LyricsPart: Item {
        id: lyricsPart

        required property var layout

        readonly property var part: layout.part
        readonly property bool timed: part.w.length > 0
        readonly property bool rtl: LyricsModel.isRtl(part.x)
        readonly property int alignment: part.side === 0 ? Text.AlignHCenter : (part.side < 0) !== rtl ? Text.AlignLeft : Text.AlignRight
        readonly property bool sung: root.shownClock >= part.t
        // A background part can still be sung after its line left the centre.
        readonly property bool lit: root.lit || (sung && root.shownClock < part.e)
        // Duets keep a colour per singer, a single voice takes the first one.
        readonly property color accent: {
            if (part.chorus)
                return MediaAccentService.lyricsGroupAccent;
            if (part.side !== 0)
                return MediaAccentService.lyricsAccents[part.voiceIndex % MediaAccentService.lyricsAccents.length];
            return MediaAccentService.lyricsLead;
        }
        // While browsing every line rests in the same colour, so the playing one reads by its fill alone.
        readonly property color restColor: lit && root.following ? Theme.withAlpha(accent, DashMetrics.lyricsRestAlpha) : root.restingColor
        readonly property color fillColor: lit ? accent : root.restingColor

        height: layout.rows.length * layout.rowHeight
        // A background part still being sung keeps its size while the rest of its line shrinks. A lead
        // part that is still finishing as the next line moves in shrinks with its line.
        scale: root.shrunk && !(part.background && root.clock >= part.t && root.clock < part.e) ? DashMetrics.lyricsLineInactiveScale : 1
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        Behavior on scale {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: DashMetrics.lyricsLineScaleDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: DashMetrics.lyricsTrackCurve
            }
        }

        Repeater {
            model: lyricsPart.layout.rows

            Item {
                id: row

                required property var modelData
                required property int index
                // Line timed parts have no cues, so the whole line changes colour when it starts.
                readonly property real fill: lyricsPart.timed ? Math.round(Math.min(width, LyricsModel.rowFill(modelData.segments, root.shownClock, root.sweep))) : 0

                x: lyricsPart.alignment === Text.AlignLeft ? 0 : lyricsPart.alignment === Text.AlignRight ? lyricsPart.width - width : (lyricsPart.width - width) / 2
                y: index * lyricsPart.layout.rowHeight
                width: modelData.width
                height: lyricsPart.layout.rowHeight

                // The two copies meet at the fill edge rather than overlap, so translucent colours do not add up.
                Item {
                    x: lyricsPart.rtl ? 0 : row.fill
                    width: parent.width - row.fill
                    height: parent.height
                    clip: true
                    visible: width > 0

                    StyledText {
                        x: -parent.x
                        text: row.modelData.text
                        color: !lyricsPart.timed && lyricsPart.sung ? lyricsPart.fillColor : lyricsPart.restColor
                        font: lyricsPart.layout.font
                        wrapMode: Text.NoWrap
                        Accessible.ignored: true

                        Behavior on color {
                            enabled: root.animationsEnabled
                            ColorAnimation {
                                duration: DashMetrics.lyricsLineFadeDuration
                            }
                        }
                    }
                }

                Item {
                    x: lyricsPart.rtl ? parent.width - width : 0
                    width: row.fill
                    height: parent.height
                    clip: true
                    visible: width > 0

                    StyledText {
                        x: -parent.x
                        text: row.modelData.text
                        color: lyricsPart.fillColor
                        font: lyricsPart.layout.font
                        wrapMode: Text.NoWrap
                        Accessible.ignored: true

                        Behavior on color {
                            enabled: root.animationsEnabled
                            ColorAnimation {
                                duration: DashMetrics.lyricsLineFadeDuration
                            }
                        }
                    }
                }
            }
        }
    }
}
