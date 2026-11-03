pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

Item {
    id: root

    x: Math.round(parent.x) - parent.x
    y: Math.round(parent.y) - parent.y
    width: Math.round(parent.x + parent.width) - Math.round(parent.x)
    height: Math.round(parent.y + parent.height) - Math.round(parent.y)
    clip: true

    required property var controller
    required property real islandX
    required property real islandY
    required property real hostWidth
    required property real hostHeight
    required property real springTimeConstantMs
    required property real morphProgress
    required property bool expanded
    required property bool pointerInside
    required property string activityId
    // The colour painted behind the faces, so edge fades blend into it.
    required property color surfaceColor
    property bool freeMode: false
    property Component compactFaceOverride: null
    // Hosted islands fold the slot anchor into every target; the face must pin to the same resolved slot.
    property var resolveTarget: target => target
    // Embedded sheets grow by this on the near edge; the face keeps its content size below the fold.
    property real expandedInset: 0
    required property Component homeCompactComponent
    required property Component homeExpandedComponent
    required property Component mediaCompactComponent
    required property Component mediaExpandedComponent
    required property Component launcherCompactComponent
    required property Component launcherExpandedComponent
    required property Component controlCenterCompactComponent
    required property Component controlCenterExpandedComponent
    required property Component wallpaperCompactComponent
    required property Component wallpaperExpandedComponent
    required property Component weatherCompactComponent
    required property Component weatherExpandedComponent
    required property Component wellbeingCompactComponent
    required property Component wellbeingExpandedComponent
    required property Component systemCompactComponent
    required property Component systemExpandedComponent
    required property Component notificationCompactComponent
    required property Component notificationExpandedComponent
    required property Component notificationCenterCompactComponent
    required property Component notificationCenterExpandedComponent
    required property Component clipboardCompactComponent
    required property Component clipboardExpandedComponent
    required property Component powerMenuCompactComponent
    required property Component powerMenuExpandedComponent

    readonly property real compactFade: root.fadeCompact(root.morphProgress)
    readonly property real expandedFade: root.fadeExpanded(root.morphProgress)
    readonly property real outgoingCompactFade: root.fadeCompact(root.outgoingMorph)
    readonly property real outgoingExpandedFade: root.fadeExpanded(root.outgoingMorph)
    readonly property bool mediaSurfaceActive: root.surfaceActive("media")
    readonly property bool systemSurfaceActive: root.controller.systemActivities.some(id => root.surfaceActive(id))

    function systemOpacity(opacityFor) {
        const incoming = root.controller.isSystemActivity(root.renderedActivity) ? opacityFor(root.renderedActivity) : 0;
        const outgoing = root.controller.isSystemActivity(root.outgoingActivity) ? opacityFor(root.outgoingActivity) : 0;
        return Math.max(incoming, outgoing);
    }

    property string renderedActivity: "home"
    property string outgoingActivity: ""
    property real activityFade: 1
    property real outgoingMorph: 0
    property bool homeExpandedTouched: false

    Keys.onEscapePressed: root.controller.requestCollapse()

    function fadeCompact(morph) {
        return 1 - Math.max(0, Math.min(1, morph / 0.34));
    }

    function fadeExpanded(morph) {
        return Math.max(0, Math.min(1, (morph - 0.22) / 0.42));
    }

    function surfaceActive(activity) {
        return root.renderedActivity === activity || root.outgoingActivity === activity;
    }

    function compactOpacity(activity) {
        const incoming = root.renderedActivity === activity ? root.activityFade * root.compactFade : 0;
        const outgoing = root.outgoingActivity === activity ? (1 - root.activityFade) * root.outgoingCompactFade : 0;
        return Math.max(incoming, outgoing);
    }

    function expandedOpacity(activity) {
        const incoming = root.renderedActivity === activity ? root.activityFade * root.expandedFade : 0;
        const outgoing = root.outgoingActivity === activity ? (1 - root.activityFade) * root.outgoingExpandedFade : 0;
        return Math.max(incoming, outgoing);
    }

    readonly property var focusableFaces: ({
            "home": homeExpandedLoader,
            "media": mediaExpandedLoader,
            "launcher": launcherExpandedLoader,
            "wallpaper": wallpaperExpandedLoader,
            "weather": weatherExpandedLoader,
            "wellbeing": wellbeingExpandedLoader,
            "notificationcenter": notificationCenterExpandedLoader,
            "clipboard": clipboardExpandedLoader,
            "powermenu": powerMenuExpandedLoader,
            "controlcenter": controlCenterExpandedLoader
        })

    // Faces load async and stay disabled until half faded in, so ExpandedFace calls this again on each ready edge.
    function requestActivityFocus() {
        if (!root.controller.keyboardDismissRequested)
            return;
        const face = root.focusableFaces[root.activityId];
        if (!face?.enabled || !face.item || face.item.activeFocus)
            return;
        face.item.focusFace?.();
    }

    function latchHomeExpanded() {
        if (!homeExpandedTouched && expanded && activityId === "home")
            homeExpandedTouched = true;
    }

    onPointerInsideChanged: {
        if (root.pointerInside)
            root.homeExpandedTouched = true;
    }

    onExpandedChanged: latchHomeExpanded()

    onActivityIdChanged: {
        latchHomeExpanded();
        if (activityId === renderedActivity)
            return;
        outgoingMorph = morphProgress;
        outgoingActivity = renderedActivity;
        renderedActivity = activityId;
        activityFade = 0;
        activityTransition.restart();
    }

    SequentialAnimation {
        id: activityTransition

        PauseAnimation {
            duration: Math.round(root.springTimeConstantMs)
        }

        NumberAnimation {
            target: root
            property: "activityFade"
            to: 1
            duration: Math.round(root.springTimeConstantMs * 3)
            easing.type: Easing.OutCubic
        }

        ScriptAction {
            script: root.outgoingActivity = ""
        }
    }

    // Where a resolved target sits at rest, in host coordinates.
    function slotAlong(target) {
        return root.controller.isVertical ? (root.hostHeight - target.height) / 2 + target.offsetAlong : (root.hostWidth - target.width) / 2 + target.offsetAlong;
    }

    function slotCross(target) {
        if (!root.controller.farEdge)
            return target.offsetCross;
        return root.controller.isVertical ? root.hostWidth - target.offsetCross - target.width : root.hostHeight - target.offsetCross - target.height;
    }

    // Pinned to the compact target's own screen slot so the face holds still while the island morphs.
    component CompactFace: Loader {
        required property string activity
        required property Component face
        // A free face only centres in the island, so it skips the anchor-resolved slot every drag event would rebuild.
        readonly property var target: root.freeMode ? root.controller.compactTargetFor(activity) : root.resolveTarget(root.controller.compactTargetFor(activity))
        readonly property bool isVertical: root.controller.isVertical
        readonly property real alongPos: !active || root.freeMode ? 0 : Math.round(root.slotAlong(target)) - Math.round(isVertical ? root.islandY : root.islandX)
        readonly property real crossPos: !active || root.freeMode ? 0 : Math.round(root.slotCross(target)) - Math.round(isVertical ? root.islandX : root.islandY)

        x: root.freeMode ? Math.round((parent.width - width) / 2) : (isVertical ? crossPos : alongPos)
        y: root.freeMode ? Math.round((parent.height - height) / 2) : (isVertical ? alongPos : crossPos)
        width: target.width
        height: target.height
        asynchronous: false
        sourceComponent: root.compactFaceOverride && root.controller.usesDotFace(activity) ? root.compactFaceOverride : face
        opacity: !active ? 0 : root.controller.isSystemActivity(activity) ? root.systemOpacity(root.compactOpacity) : root.compactOpacity(activity)
        visible: opacity > 0.001
        enabled: opacity >= 0.5
    }

    // Pinned to the sheet's settled slot so the content holds still while the island morphs.
    component ExpandedFace: Loader {
        required property string activity
        readonly property var target: root.controller.expandedTargetFor(activity)
        // A hidden face stays put, so a kept-alive sheet is not re-laid out on every move of the pill.
        readonly property bool placed: active && visible
        readonly property var slot: placed ? root.resolveTarget(target) : target
        readonly property bool isVertical: root.controller.isVertical
        readonly property real inset: root.controller.farEdge ? 0 : root.expandedInset
        readonly property real alongPos: !placed ? 0 : Math.round(root.slotAlong(slot)) - Math.round(isVertical ? root.islandY : root.islandX)
        readonly property real crossPos: !placed ? 0 : Math.round(root.slotCross(slot)) - Math.round(isVertical ? root.islandX : root.islandY) + inset

        x: isVertical ? crossPos : alongPos
        y: isVertical ? alongPos : crossPos
        width: target.width
        height: target.height
        opacity: !active ? 0 : root.controller.isSystemActivity(activity) ? root.systemOpacity(root.expandedOpacity) : root.expandedOpacity(activity)
        visible: opacity > 0.001
        enabled: opacity >= 0.5
        onEnabledChanged: {
            if (enabled && activity === root.activityId)
                root.requestActivityFocus();
        }
        onItemChanged: {
            if (item && activity === root.activityId)
                root.requestActivityFocus();
        }
    }

    CompactFace {
        active: true
        activity: "home"
        face: root.homeCompactComponent
    }

    ExpandedFace {
        id: homeExpandedLoader

        activity: "home"
        active: root.homeExpandedTouched
        asynchronous: true
        sourceComponent: root.homeExpandedComponent
    }

    CompactFace {
        active: root.mediaSurfaceActive
        activity: "media"
        face: root.mediaCompactComponent
    }

    ExpandedFace {
        id: mediaExpandedLoader

        activity: "media"
        active: root.mediaSurfaceActive && (root.expanded || root.expandedFade > 0)
        asynchronous: false
        sourceComponent: root.mediaExpandedComponent
    }

    CompactFace {
        active: root.surfaceActive("launcher")
        activity: "launcher"
        face: root.launcherCompactComponent
    }

    ExpandedFace {
        id: launcherExpandedLoader

        activity: "launcher"
        active: root.controller.visualsRequested("launcher")
        asynchronous: true
        sourceComponent: root.launcherExpandedComponent
    }

    CompactFace {
        active: root.surfaceActive("controlcenter")
        activity: "controlcenter"
        face: root.controlCenterCompactComponent
    }

    ExpandedFace {
        id: controlCenterExpandedLoader
        activity: "controlcenter"
        active: root.controller.visualsRequested("controlcenter")
        asynchronous: false
        sourceComponent: root.controlCenterExpandedComponent
    }

    CompactFace {
        active: root.surfaceActive("wallpaper")
        activity: "wallpaper"
        face: root.wallpaperCompactComponent
    }

    ExpandedFace {
        id: wallpaperExpandedLoader

        activity: "wallpaper"
        active: root.controller.visualsRequested("wallpaper")
        asynchronous: true
        sourceComponent: root.wallpaperExpandedComponent
    }

    CompactFace {
        active: root.surfaceActive("weather")
        activity: "weather"
        face: root.weatherCompactComponent
    }

    ExpandedFace {
        id: weatherExpandedLoader

        activity: "weather"
        active: root.controller.visualsRequested("weather")
        asynchronous: true
        sourceComponent: root.weatherExpandedComponent
    }

    CompactFace {
        active: root.surfaceActive("wellbeing")
        activity: "wellbeing"
        face: root.wellbeingCompactComponent
    }

    ExpandedFace {
        id: wellbeingExpandedLoader

        activity: "wellbeing"
        active: root.controller.visualsRequested("wellbeing")
        asynchronous: true
        sourceComponent: root.wellbeingExpandedComponent
    }

    CompactFace {
        active: root.surfaceActive("notificationcenter")
        activity: "notificationcenter"
        face: root.notificationCenterCompactComponent
    }

    ExpandedFace {
        id: notificationCenterExpandedLoader

        activity: "notificationcenter"
        active: root.controller.visualsRequested("notificationcenter")
        asynchronous: true
        sourceComponent: root.notificationCenterExpandedComponent
    }

    CompactFace {
        active: root.surfaceActive("clipboard")
        activity: "clipboard"
        face: root.clipboardCompactComponent
    }

    ExpandedFace {
        id: clipboardExpandedLoader

        activity: "clipboard"
        active: root.controller.visualsRequested("clipboard")
        asynchronous: true
        sourceComponent: root.clipboardExpandedComponent
    }

    CompactFace {
        active: root.surfaceActive("powermenu")
        activity: "powermenu"
        face: root.powerMenuCompactComponent
    }

    ExpandedFace {
        id: powerMenuExpandedLoader

        activity: "powermenu"
        active: root.controller.visualsRequested("powermenu")
        asynchronous: true
        sourceComponent: root.powerMenuExpandedComponent
    }

    CompactFace {
        active: root.systemSurfaceActive
        activity: "volume"
        face: root.systemCompactComponent
    }

    ExpandedFace {
        activity: "volume"
        active: root.systemSurfaceActive && (root.expanded || root.expandedFade > 0)
        asynchronous: false
        sourceComponent: root.systemExpandedComponent
    }

    CompactFace {
        active: root.surfaceActive("notification")
        activity: "notification"
        face: root.notificationCompactComponent
    }

    ExpandedFace {
        activity: "notification"
        active: root.surfaceActive("notification") && (root.expanded || root.expandedFade > 0)
        asynchronous: false
        sourceComponent: root.notificationExpandedComponent
    }
}
