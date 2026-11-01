pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.DIsland.Activities

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
    required property Component liveCompactComponent
    required property Component liveExpandedComponent
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
    readonly property var stableTarget: root.resolveTarget(root.controller.compactTarget)
    readonly property bool followsCompactBody: !root.expanded && root.morphProgress < 0.5
    readonly property real stableSpan: followsCompactBody ? (controller.isVertical ? height : width) : (controller.isVertical ? stableTarget.height : stableTarget.width)
    readonly property real stableStart: followsCompactBody ? 0 : root.controller.isVertical ? (root.freeMode ? (height - stableTarget.height) / 2 : (hostHeight - stableTarget.height) / 2 + stableTarget.offsetAlong - islandY) : (root.freeMode ? (width - stableTarget.width) / 2 : (hostWidth - stableTarget.width) / 2 + stableTarget.offsetAlong - islandX)

    component StableSlots: IslandActivitySlots {
        property real start: 0
        controller: root.controller
        width: implicitWidth
        height: implicitHeight
        x: controller.isVertical ? (parent.width - width) / 2 : root.stableStart + start
        y: controller.isVertical ? root.stableStart + start : (parent.height - height) / 2
        opacity: root.compactFade
        visible: occupied && opacity > 0.001
        enabled: opacity >= 0.5
    }

    StableSlots {
        position: "left"
    }
    StableSlots {
        position: "center"
        start: root.controller.stableSlotLengths.left
    }
    StableSlots {
        position: "right"
        start: root.stableSpan - root.controller.stableSlotLengths.right
    }

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
        return 1 - Math.max(0, Math.min(1, morph / 0.5));
    }

    function fadeExpanded(morph) {
        return Math.max(0, Math.min(1, (morph - 0.12) / 0.76));
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
            "live": liveExpandedLoader,
            "home": homeExpandedLoader,
            "media": mediaExpandedLoader,
            "launcher": launcherExpandedLoader,
            "wallpaper": wallpaperExpandedLoader,
            "weather": weatherExpandedLoader,
            "notificationcenter": notificationCenterExpandedLoader,
            "clipboard": clipboardExpandedLoader,
            "powermenu": powerMenuExpandedLoader,
            "controlcenter": controlCenterExpandedLoader
        })

    function requestActivityFocus() {
        if (root.activityId === "launcher" && launcherExpandedLoader.active) {
            // Reserve focus until the launcher is ready.
            root.refocusLauncher();
            return true;
        }
        const face = root.focusableFaces[root.activityId]?.item;
        if (!face || typeof face.focusFace !== "function")
            return false;
        return face.focusFace() === true;
    }

    function refocusLauncher() {
        if (root.activityId !== "launcher" || !root.controller.keyboardDismissRequested || !launcherExpandedLoader.enabled)
            return;
        const face = launcherExpandedLoader.item;
        if (!face || face.activeFocus)
            return;
        face.focusFace();
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
        readonly property var target: root.resolveTarget(root.controller.compactTargetFor(activity))
        readonly property bool isVertical: root.controller.isVertical
        readonly property real alongPos: !active ? 0 : Math.round(root.slotAlong(target) + root.controller.stableLeadingLength) - Math.round(isVertical ? root.islandY : root.islandX)
        readonly property real crossPos: !active ? 0 : Math.round(root.slotCross(target)) - Math.round(isVertical ? root.islandX : root.islandY)
        readonly property bool followsBody: root.followsCompactBody && activity === root.activityId
        readonly property real bodySpan: Math.max(root.controller.compactFaceThickness, Math.min(Math.max(root.controller.mediaCompactMaxLength, (isVertical ? target.height : target.width) - root.controller.stableSlotsLength), (isVertical ? parent.height : parent.width) - root.controller.stableSlotsLength))
        readonly property real bodyStart: root.controller.stableLeadingLength + Math.max(0, ((isVertical ? parent.height : parent.width) - root.controller.stableSlotsLength - bodySpan) / 2)

        x: followsBody ? (isVertical ? crossPos : bodyStart) : root.freeMode ? (isVertical ? crossPos : Math.round((parent.width - target.width) / 2 + root.controller.stableLeadingLength)) : (isVertical ? crossPos : alongPos)
        y: followsBody ? (isVertical ? bodyStart : crossPos) : root.freeMode ? (isVertical ? Math.round((parent.height - target.height) / 2 + root.controller.stableLeadingLength) : crossPos) : (isVertical ? alongPos : crossPos)
        width: isVertical ? target.width : followsBody ? bodySpan : Math.max(root.controller.compactFaceThickness, target.width - root.controller.stableSlotsLength)
        height: isVertical ? followsBody ? bodySpan : Math.max(root.controller.compactFaceThickness, target.height - root.controller.stableSlotsLength) : target.height
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
        readonly property var slot: root.resolveTarget(target)
        readonly property bool isVertical: root.controller.isVertical
        readonly property real inset: root.controller.farEdge ? 0 : root.expandedInset
        readonly property real alongPos: !active ? 0 : Math.round(root.slotAlong(slot)) - Math.round(isVertical ? root.islandY : root.islandX)
        readonly property real crossPos: !active ? 0 : Math.round(root.slotCross(slot)) - Math.round(isVertical ? root.islandX : root.islandY) + inset

        x: isVertical ? crossPos : alongPos
        y: isVertical ? alongPos : crossPos
        transformOrigin: isVertical ? (root.controller.farEdge ? Item.Right : Item.Left) : (root.controller.farEdge ? Item.Bottom : Item.Top)
        scale: Math.max(0, Math.min(1, (parent.width - (isVertical ? root.expandedInset : 0)) / Math.max(1, width), (parent.height - (isVertical ? 0 : root.expandedInset)) / Math.max(1, height)))
        width: target.width
        height: target.height
        opacity: !active ? 0 : root.controller.isSystemActivity(activity) ? root.systemOpacity(root.expandedOpacity) : root.expandedOpacity(activity)
        visible: opacity > 0.001
        enabled: opacity >= 0.5
    }

    CompactFace {
        active: root.surfaceActive("live")
        activity: "live"
        face: root.liveCompactComponent
        opacity: root.compactOpacity("live")
    }

    ExpandedFace {
        id: liveExpandedLoader
        activity: "live"
        active: root.surfaceActive("live") && (root.expanded || root.expandedFade > 0)
        sourceComponent: root.liveExpandedComponent
        opacity: root.expandedOpacity("live")
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
        onEnabledChanged: {
            if (enabled)
                root.refocusLauncher();
        }
        onItemChanged: {
            if (item)
                root.refocusLauncher();
        }
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
