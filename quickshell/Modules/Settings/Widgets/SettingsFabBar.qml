import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    default property alias content: row.data
    property bool shown: true
    readonly property real reservedHeight: shown && !inline ? row.implicitHeight + Theme.spacingL : 0
    readonly property var scaleSpring: Theme.springPreset("fastSpatial")
    readonly property real shadowPadding: Theme.elevationRenderPadding(Theme.elevationLevel3, Theme.elevationLightDirection, Theme.spacingXS, Theme.spacingS, Theme.spacingL)

    property bool inline: false

    width: parent?.width ?? 0
    height: inline && shown ? row.implicitHeight : 0

    // only the surface moves: a hidden Column child reparented into the page never renders
    function attachToPage() {
        let page = parent;
        while (page && page.fabBar === undefined)
            page = page.parent;
        // A page shown inside another page has no viewport of its own to float over
        if (page?.embedded) {
            inline = true;
            surface.anchors.horizontalCenter = root.horizontalCenter;
            surface.y = -shadowPadding;
            return;
        }
        if (page)
            page.fabBar = root;
        const host = page ?? parent;
        surface.parent = host;
        surface.anchors.horizontalCenter = host.horizontalCenter;
        surface.anchors.bottom = host.bottom;
    }

    onShownChanged: scaleMotion.retarget(shown ? 1 : Theme.fabEnterScale)

    Component.onCompleted: {
        scaleMotion.snapTo(shown ? 1 : Theme.fabEnterScale);
        attachToPage();
    }

    SpringMotion {
        id: scaleMotion
        stiffness: root.scaleSpring.stiffness
        damping: root.scaleSpring.damping
    }

    DLayer {
        id: surface

        width: row.implicitWidth + root.shadowPadding * 2
        height: row.implicitHeight + root.shadowPadding * 2
        // above the DFlickable edge fade, which sits at z 1
        z: 2
        anchors.bottomMargin: Theme.spacingL - root.shadowPadding
        opacity: root.shown ? 1 : 0
        visible: opacity > 0
        layer.enabled: visible && (scaleMotion.running || opacity < 1)
        layer.smooth: true

        transform: Scale {
            origin.x: surface.width / 2
            origin.y: surface.height - root.shadowPadding
            xScale: scaleMotion.value
            yScale: scaleMotion.value
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveFastEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
            }
        }

        Row {
            id: row
            x: root.shadowPadding
            y: root.shadowPadding
            spacing: Theme.spacingS
        }
    }
}
