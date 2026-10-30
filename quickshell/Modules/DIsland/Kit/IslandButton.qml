pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Common
import qs.DCommon.Widgets
import "../../../DCommon/Common/Contrast.js" as Contrast
import "../../../Common/IslandKit.js" as Kit

// A tile on DMS's corner setting, never a pill, so every card's actions read as one family.
StyledButton {
    id: root

    // "primary" (filled), "plain" (the secondary tile), "quiet" (text link).
    property string role: "plain"
    property string iconName: ""
    property real weight: 1
    property int buttonHeight: Theme.buttonHeightS

    readonly property bool iconOnly: root.text === ""
    readonly property bool still: Theme.currentAnimationBaseDuration <= 0 || SettingsData.reduceMotion
    readonly property bool outlined: root.role !== "primary" && root.role !== "quiet"

    readonly property color baseColor: root.role === "primary" ? Theme.primary : root.role === "quiet" ? "transparent" : Theme.surfaceContainerHigh
    readonly property color inkColor: !root.enabled ? Theme.onSurface_38 : root.role === "primary" ? Theme.onPrimary : root.role === "quiet" ? root.quietInk : Theme.surfaceText
    // A text link keeps the primary tone where it reads at AA on the island's surfaces, hover and press tints included;
    // elsewhere (a light theme's pale primary) it takes the surface's text tone.
    readonly property color quietInk: {
        const grounds = [Theme.surface, Theme.surfaceContainer, Theme.surfaceContainerHigh];
        return Contrast.readableOnAll(grounds.concat(grounds.map(ground => Contrast.mix(ground, Theme.primary, Theme.stateLayerPressed))), [Theme.primary, Theme.surfaceText], root.labelContrast);
    }
    readonly property real layerAlpha: root.down ? Theme.stateLayerPressed : root.hovered ? Theme.stateLayerHover : 0
    // AA's 4.5:1 for a label, with room for the 8-bit rounding of the drawn tile.
    readonly property real labelContrast: 4.55

    implicitWidth: root.iconOnly ? root.buttonHeight : Math.max(root.buttonHeight, face.naturalWidth + Theme.spacingS * 2)
    implicitHeight: root.buttonHeight
    radius: Math.min(Theme.cornerRadius, height / 2)
    // Disabled as DMS's buttons: a faint tile and ink; a text link keeps no tile.
    color: root.enabled || root.role === "quiet" ? root.baseColor : Theme.onSurface_12
    border.width: root.outlined ? Theme.layerOutlineWidth : 0
    border.color: Theme.outlineMedium
    // An icon's ligature is no name: a button without text gets its Accessible.name from the caller, through I18n.tr().
    Accessible.name: root.text
    Component.onCompleted: {
        if (root.iconOnly && root.iconName !== "" && root.Accessible.name === "")
            Log.scoped("IslandButton").warn("icon-only button without an Accessible.name:", root.iconName);
    }

    readonly property real sink: press.value
    // A press sinks the tile this many times deeper than DMS's press scale.
    readonly property real sinkDepth: 1.5

    transform: Translate {
        y: root.sink * Theme.spacingXXS
    }
    scale: 1 - (1 - Theme.pressScale) * root.sinkDepth * root.sink

    onDownChanged: press.retarget(root.down ? 1 : 0)

    Behavior on color {
        enabled: !root.still
        DColorAnim {
            duration: Theme.expressiveDurations.expressiveEffects
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    // The kit's cell spring (IslandKit.springs.cell): presses.
    SpringMotion {
        id: press

        readonly property var spec: Kit.spring("cell", Theme.currentAnimationBaseDuration)
        enabled: !root.still
        stiffness: spec.stiffness
        damping: spec.damping
        mass: spec.mass
    }

    // A text link has no tile, but shows one on hover.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        // On the filled tile the tint stops where the label would fall under AA (a light theme's white on its primary).
        color: root.role === "primary" && root.enabled && root.layerAlpha > 0 ? Contrast.subtleTint(Theme.primary, root.inkColor, root.inkColor, root.layerAlpha, root.labelContrast) : Theme.withAlpha(root.inkColor, root.layerAlpha)

        Behavior on color {
            enabled: !root.still
            DColorAnim {
                duration: Theme.shorterDuration
                easing.bezierCurve: Theme.expressiveCurves.standardDecel
            }
        }
    }

    // Keyboard focus only (visualFocus): a click draws no ring. DMS's ring, its width, offset and tone settings.
    FocusRing {
        visible: root.visualFocus
    }

    // A label cut short reads in full on hover or keyboard focus. Multiline is DTooltipV2's only plain text format: a
    // caller's label shows as written, as on the face, never as markup or an image.
    DTooltipHost {
        id: fullLabel

        readonly property bool asked: root.hovered || root.visualFocus

        multiline: true
        text: face.truncated ? root.text : ""
        target: root
        onAskedChanged: fullLabel.asked ? fullLabel.schedule() : fullLabel.dismiss()
    }

    // A handler's margin widens the touch target, not a containmentMask: Qt skips an item whose bounds and handlers'
    // margins miss the point before it asks the mask.
    HoverHandler {
        margin: Math.max(0, (Theme.minimumTouchTargetSize - Math.min(root.width, root.height)) / 2)
    }

    IslandButtonFace {
        id: face

        ink: root.inkColor
        icon: root.iconName
        text: root.text
        room: root.width - Theme.spacingS * 2
        x: (root.width - width) / 2
        y: (root.height - height) / 2
    }
}
