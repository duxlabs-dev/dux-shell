import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../../../Common/LyricLayout.js" as LyricLayout
import "../../DDash/Media/LyricsModel.js" as LyricsModel

Item {
    id: root

    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    required property var controller
    property alias font: measure.font
    property color color: Theme.surfaceText
    property bool live: true
    property bool scroll: true
    property bool playing: true
    // Fills each word across its sung time instead of at once, like the dash's smooth highlight.
    property bool sweep: false

    readonly property int revision: controller.wordRevision
    readonly property string fontKey: measure.font.family + "/" + measure.font.pixelSize + "/" + measure.font.weight
    property string pagedKey: ""
    property string pageKey: ""
    property string measuredFontKey: ""
    property var pages: []
    property var cueSpans: []
    property bool snapping: false
    property real shift: 0
    property real pageWidth: 0
    property real scrollOffset: 0
    property real holdStartMs: 1200
    property real pxPerMs: 1 / 20
    property real overscroll: 5
    property int stepInterval: 60
    property var scrollMotion: null
    property bool scrollMoving: false

    readonly property bool scrollEnabled: scroll && !SettingsData.reduceMotion
    readonly property real maxScrollOffset: Math.max(0, pageWidth - width + overscroll)
    readonly property bool scrollable: scrollEnabled && width > 0 && pageWidth > width && current.text !== ""
    readonly property bool scrollActive: scrollable && playing && controller.rate > 0 && live && visible && (Window.window?.visible ?? false)

    clip: true

    onRevisionChanged: place()
    onVisibleChanged: place()
    onWidthChanged: place()
    onFontKeyChanged: place()
    onLiveChanged: place()
    onSweepChanged: place()
    onScrollEnabledChanged: place()
    onScrollActiveChanged: syncScroll()
    Component.onCompleted: place()

    function flat(value) {
        return value.replace(/\s*\n\s*/g, " ");
    }

    function widthOf(value) {
        measure.text = value.replace(/\s+$/, "");
        return measure.implicitWidth;
    }

    function place() {
        sweepMotion.stop();
        const parts = visible ? (controller.lines[controller.activeIndex]?.parts ?? []) : [];
        const at = controller.shownTime();
        const next = parts.find(candidate => !candidate.background && at >= candidate.t && at < candidate.e) ?? parts.find(candidate => !candidate.background) ?? parts[0] ?? null;
        if (!next) {
            clearLine();
            return;
        }
        const key = controller.activeIndex + "/" + next.t + "/" + next.voice;
        const paged = key + "/" + width + "/" + fontKey + "/" + scrollEnabled + "/" + sweep;
        if (paged !== pagedKey) {
            pagedKey = paged;
            const chunks = next.w.length > 0 ? next.w.map(word => word.x) : (flat(next.x).match(/\S+\s*/g) ?? [flat(next.x)]);
            pages = scrollEnabled ? [{
                first: 0,
                last: chunks.length - 1,
                text: flat(next.x)
            }] : paginate(chunks);
            cueSpans = next.w.length > 0 && (scrollEnabled || sweep) ? LyricsModel.cueSpans(next) : [];
        }
        if (next.w.length > 0) {
            placeWords(key, next, at);
        } else {
            placeLine(key, next, at);
            scrollMotion = { start: next.t, end: next.e, from: 0, to: maxScrollOffset, hold: holdStartMs / 1000, speed: pxPerMs * 1000 };
        }
        syncScroll();
    }

    function placeWords(key, line, at) {
        nextPage.stop();
        const index = lastStarted(line.w, at);
        const page = pages.find(candidate => index <= candidate.last) ?? pages[pages.length - 1];
        const sung = index < page.first ? 0 : widthOf(flat(line.w.slice(page.first, index + 1).map(word => word.x).join("")));
        const span = index < page.first ? null : cueSpans[index];
        const before = !span || index <= page.first ? 0 : widthOf(flat(line.w.slice(page.first, index).map(word => word.x).join("")));
        scrollMotion = span ? {
            start: span.t, end: span.e, from: before - width * 0.75, to: sung - width * 0.75, hold: 0, speed: pxPerMs * 1000
        } : null;
        if (!sweep || index < page.first) {
            turnTo(key + "/" + page.first, page.text, sung);
            return;
        }
        const duration = span.e - span.t;
        const progress = Number.isFinite(duration) && duration > 0 ? Math.max(0, Math.min(1, (at - span.t) / duration)) : 1;
        turnTo(key + "/" + page.first, page.text, before + (sung - before) * progress);
        if (progress >= 1 || !live || !controller.playing || controller.rate <= 0 || SettingsData.reduceMotion)
            return;
        sweepMotion.to = sung;
        sweepMotion.duration = Math.max(1, Math.min(2147483647, (span.e - at) * 1000 / controller.rate));
        sweepMotion.start();
    }

    function placeLine(key, line, at) {
        nextPage.stop();
        const span = line.e - line.t;
        const timed = pages.length > 1 && Number.isFinite(span) && span > 0;
        const pageIndex = timed ? Math.max(0, Math.min(pages.length - 1, Math.floor((at - line.t) / span * pages.length))) : 0;
        const page = pages[pageIndex];
        turnTo(key + "/" + page.first, page.text, widthOf(page.text));
        if (!timed || !live || !controller.playing || controller.rate <= 0 || pageIndex >= pages.length - 1)
            return;
        const boundary = line.t + span * (pageIndex + 1) / pages.length;
        nextPage.interval = Math.max(1, Math.min(2147483647, (boundary - at) * 1000 / controller.rate));
        nextPage.start();
    }

    // Time-sorted cues reorder kugou's space cues, which share the next word's start; w keeps text order.
    function lastStarted(words, at) {
        let index = -1;
        for (let i = 0; i < words.length; i++) {
            if (words[i].t <= at)
                index = i;
        }
        return index;
    }

    function paginate(chunks) {
        const words = [];
        for (let i = 0; i < chunks.length; i++) {
            const text = flat(chunks[i]);
            const open = words.length > 0 && !words[words.length - 1].closed;
            if (open) {
                words[words.length - 1].last = i;
                words[words.length - 1].text += text;
            } else {
                words.push({
                    first: i,
                    last: i,
                    text
                });
            }
            words[words.length - 1].closed = /\s$/.test(text);
        }
        const result = [];
        let page = null;
        for (const word of words) {
            if (page && widthOf(page.text + word.text) > width) {
                result.push(page);
                page = null;
            }
            if (!page) {
                page = {
                    first: word.first,
                    last: word.last,
                    text: word.text
                };
                continue;
            }
            page.last = word.last;
            page.text += word.text;
        }
        if (page)
            result.push(page);
        return result;
    }

    function turnTo(key, text, sung) {
        const previousOffset = current.offset;
        if (current.text !== text || measuredFontKey !== fontKey) {
            pageWidth = widthOf(text);
            measuredFontKey = fontKey;
        }
        if (key === pageKey && text === current.text) {
            current.fill = sung;
            return;
        }
        pageKey = key;
        slide.stop();
        resetScroll();
        const animate = live && !SettingsData.reduceMotion && current.text !== "";
        outgoing.text = animate ? current.text : "";
        outgoing.fill = current.fill;
        outgoing.offset = animate ? previousOffset : 0;
        snap(text, sung);
        shift = animate ? 1 : 0;
        if (animate)
            slide.start();
    }

    function resetScroll() {
        scrollTick.stop();
        scrollOffset = 0;
        scrollMoving = false;
    }

    function syncScroll(cava = false) {
        scrollTick.stop();
        if (!scrollable) {
            scrollOffset = 0;
            scrollMoving = false;
            return;
        }
        const state = LyricLayout.scrollState(scrollMotion, controller.shownTime(), maxScrollOffset);
        scrollOffset = state.offset;
        scrollMoving = state.wait === 0;
        if (!scrollActive || controller.rate <= 0 || !Number.isFinite(state.wait))
            return;
        // Cava defers the fallback; no second clock wakes while those frames keep arriving (#2863).
        scrollTick.interval = Math.max(cava ? 150 : stepInterval, Math.min(2147483647, state.wait * 1000 / controller.rate));
        scrollTick.start();
    }

    function clearLine() {
        nextPage.stop();
        sweepMotion.stop();
        slide.stop();
        pagedKey = "";
        pageKey = "";
        pages = [];
        cueSpans = [];
        scrollMotion = null;
        pageWidth = 0;
        resetScroll();
        outgoing.text = "";
        snap("", 0);
        shift = 0;
    }

    function snap(text, sung) {
        snapping = true;
        current.text = text;
        current.fill = sung;
        snapping = false;
    }

    Timer {
        id: nextPage
        onTriggered: root.place()
    }

    Timer {
        id: scrollTick
        onTriggered: root.syncScroll()
    }

    Connections {
        target: CavaService
        enabled: root.scrollActive && root.scrollMoving && SettingsData.audioVisualizerEnabled && CavaService.cavaAvailable
        function onValuesChanged() { root.syncScroll(true); }
    }

    NumberAnimation {
        id: slide
        target: root
        property: "shift"
        to: 0
        duration: Theme.mediumDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.emphasizedDecel
        onFinished: outgoing.text = ""
    }

    NumberAnimation {
        id: sweepMotion
        target: current
        property: "fill"
    }

    StyledText {
        id: measure
        visible: false
        wrapMode: Text.NoWrap
        elide: Text.ElideNone
    }

    component Face: Item {
        id: face
        property string text: ""
        property real fill: 0
        property real offset: 0

        width: root.width
        height: root.height

        Behavior on fill {
            enabled: root.live && !root.snapping && !root.sweep && !SettingsData.reduceMotion
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.emphasizedDecel
            }
        }

        StyledText {
            id: dim
            x: -face.offset
            anchors.verticalCenter: parent.verticalCenter
            text: face.text
            font: measure.font
            color: Theme.withAlpha(root.color, Theme.pendingOpacity)
            wrapMode: Text.NoWrap
            elide: Text.ElideNone
            // Fractional offsets under NativeRendering quantise glyph positions and stutter.
            renderType: root.scrollable ? Text.QtRendering : resolvedRenderType
            Accessible.name: face.text
        }

        Item {
            width: Math.max(0, face.fill - face.offset)
            height: parent.height
            clip: true

            StyledText {
                x: -face.offset
                anchors.verticalCenter: parent.verticalCenter
                text: face.text
                font: measure.font
                color: root.color
                wrapMode: Text.NoWrap
                elide: Text.ElideNone
                renderType: root.scrollable ? Text.QtRendering : resolvedRenderType
                Accessible.ignored: true
            }
        }
    }

    Face {
        id: outgoing
        y: (root.shift - 1) * root.height
        opacity: root.shift
        visible: text !== ""
    }

    Face {
        id: current
        y: root.shift * root.height
        opacity: 1 - root.shift
        offset: root.scrollable ? Math.min(root.scrollOffset, root.maxScrollOffset) : 0
    }
}
